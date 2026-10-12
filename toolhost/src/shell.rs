//! Shell effects through the pinned upstream engine.
//!
//! Engine provenance: `build/upstream/oh-my-pi` @
//! `90701813e5fba6919067848989378b4ee6239c13` — `crates/pi-shell`
//! (`Shell`/`execute_shell`, the `output_decode` transcript decoder, the
//! `cancel` token), `crates/pi-builtins` and `crates/vendor/brush-core`, the
//! brush interpreter that owns parsing, expansion, builtins, redirection and
//! pipelines. External commands are spawned directly as argv by
//! `brush-core/src/sys/tokio_process.rs` (no `/bin/sh -c` wrapper, no Bun, no
//! NAPI); this module adds no shell semantics of its own.
//!
//! Contract ([`run`]): a JSON object in, a JSON envelope out.
//!
//! * Required: `command` (non-empty string), `cwd` (absolute, canonical,
//!   existing session workspace directory), `env` (string map, per-command,
//!   may be empty), `timeoutMs` (positive integer, enforced by the engine's
//!   cancellation token).
//! * Upstream shell options: `sessionEnv` (`ShellOptions::session_env`),
//!   `snapshotPath` (`ShellOptions::snapshot_path`, sourced once per session),
//!   `minimizer` (`MinimizerOptions`; inert unless `enabled`/`settingsPath`
//!   opt in), `filesystem` (accepted only as `null`: this helper serves the
//!   native host filesystem — the injected `scheme://` filesystem is a JS
//!   handler that cannot cross a process boundary).
//! * Helper-level: `sessionId` (retain one engine session per id inside this
//!   process, see "Session semantics"), `workspaceRoot` (optional containment
//!   check on `cwd`), `abortOnSignals` (default `true`, see "Cancellation").
//!
//! Unknown parameters are rejected rather than ignored: a misspelled
//! `timeoutMs` must not become an unbounded run.
//!
//! # Session semantics
//!
//! `pi_shell::Shell` *is* a persistent session: working directory, shell
//! variables/functions, shell options, jobs and `nohup`/`&` children live in
//! the `BrushShell` instance and survive across `run` calls on the same
//! `Shell` (`session_keepalive`: normal completion keeps the session).
//! Upstream keys one `Shell` per harness session and keeps the object alive
//! for the life of the harness process.
//!
//! This helper can only preserve that state while *its own* process lives:
//! sessions are retained in a process-global registry keyed by `sessionId`,
//! with a fingerprint over `sessionEnv`/`snapshotPath`/`minimizer` so a reused
//! id with different configuration is reported (`sessionState`) instead of
//! silently inheriting the old shell. A call without `sessionId` runs on a
//! throwaway `Shell` that is dropped at the end — which is upstream's
//! kill-on-drop teardown for a non-retained session, so `&`/`nohup` children
//! do not outlive a per-call helper process. To get upstream's cross-call
//! behaviour (a `cd`, an exported variable, a background server) the host must
//! keep one toolhost process alive and pass the same `sessionId`.
//!
//! # Cancellation
//!
//! `timeoutMs` is enforced inside the engine (`CancelToken::new`), producing
//! `timedOut: true`, `cancelled: false`, `exitCode: null` — the same raw flags
//! upstream's bash executor branches on. `abortOnSignals` (default on,
//! unix only) installs SIGINT/SIGTERM handling: either signal aborts the
//! in-flight run through the engine's own abort token (`cancelled: true`,
//! which is what the upstream JS caller does with `Shell::abort()`, process
//! termination included). With no run in flight the helper exits with
//! `128 + signal` instead of lingering on a handler, and a cancelled or
//! timed-out session is dropped rather than retained (upstream quarantines
//! such sessions too). Nothing is retried, ever.
//!
//! Not implemented here, deliberately: interactive PTY sessions, the job
//! manager's foreground/background control loop, `Shell::pids()`-driven live
//! process probing, and the JS-side artifact/truncation handling of minimized
//! output. The model-facing `ToolResult` text is the TypeScript core's job;
//! this module returns the engine's raw transcript and flags.

use std::{
    any::Any,
    collections::HashMap,
    fs,
    path::Path,
    sync::{
        Arc, LazyLock, Mutex,
        atomic::{AtomicBool, Ordering},
        mpsc,
    },
    time::Duration,
};

use pi_shell::{
    Shell, ShellOptions, ShellRunOptions,
    cancel::{AbortReason, AbortToken, CancelToken},
    minimizer::MinimizerOptions,
};
use serde_json::{Map, Value};

/// How long an interrupted run waits for its output reader to finish before
/// the reader is detached and the transcript is taken as-is.
///
/// Mirrors the engine's own bound for this situation
/// (`pi-natives/src/shell.rs::INTERRUPTED_DRAIN_SHUTDOWN_TIMEOUT`): a cancelled
/// run may detach a pipe reader whose sender never closes, and waiting on
/// channel disconnect would hang the caller forever. Successful and failed
/// runs drain without a deadline so no accepted chunk is dropped.
const INTERRUPTED_DRAIN_TIMEOUT: Duration = Duration::from_secs(2);

/// Abort handle of the run in flight, if any.
///
/// The signalling task reaches a run through the engine's own abort token
/// instead of `Shell::abort()` so no `Shell` reference crosses threads.
static ABORT_SLOT: LazyLock<Mutex<Option<AbortToken>>> = LazyLock::new(|| Mutex::new(None));

/// Whether SIGINT/SIGTERM handling was installed (reported as `signalsArmed`).
static SIGNALS_ARMED: AtomicBool = AtomicBool::new(false);

/// The engine's runtime; the shell API is async and spawns its own tasks.
static RUNTIME: LazyLock<Result<tokio::runtime::Runtime, String>> = LazyLock::new(|| {
    tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .enable_all()
        .thread_name("toolhost-shell")
        .build()
        .map_err(|err| format!("failed to start the shell runtime: {err}"))
});

fn runtime() -> Result<&'static tokio::runtime::Runtime, String> {
    match &*RUNTIME {
        Ok(runtime) => Ok(runtime),
        Err(err) => Err(err.clone()),
    }
}

struct SessionEntry {
    shell: Shell,
    fingerprint: String,
}

/// Retained sessions, keyed by the caller's `sessionId` (see module docs).
static SESSIONS: LazyLock<Mutex<HashMap<String, SessionEntry>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

/// Executes one shell effect on the pinned `pi-shell` engine.
///
/// See the module documentation for the parameter contract and the envelope
/// this returns: the engine's `ShellRunResult` fields (`exitCode`,
/// `cancelled`, `timedOut`, `workingDir`, `minimized`) plus the transcript the
/// upstream caller receives through its `onChunk` callback (`output`,
/// `outputBytes`) and the session/teardown facts the host needs to decide
/// retention (`liveBackgroundJobs`, `sessionState`, `sessionRetained`).
pub fn run(params: Value) -> Result<Value, String> {
    let params = Params::parse(params)?;

    let runtime = runtime()?;
    if params.abort_on_signals {
        arm_signals();
    }
    let signals_armed = SIGNALS_ARMED.load(Ordering::Relaxed);

    // Take the retained session for this id, if it exists, so the registry
    // lock is never held while a command runs. An id reused with different
    // session configuration replaces the entry (upstream builds a distinct
    // session per configuration key) and says so in the response; a session
    // taken here is either put back after a clean run or dropped (kill-on-drop)
    // after a cancellation/error, matching upstream's quarantine.
    let mut session_state = "one-shot";
    let mut fingerprint = String::new();
    let mut shell = None;
    if let Some(id) = params.session_id.as_deref() {
        fingerprint = params.fingerprint();
        let taken = {
            let mut registry = SESSIONS.lock().unwrap_or_else(|err| err.into_inner());
            registry.remove(id)
        };
        match taken {
            Some(entry) if entry.fingerprint == fingerprint => {
                session_state = "reused";
                shell = Some(entry.shell);
            }
            Some(_) => session_state = "recreated",
            None => session_state = "created",
        }
    }
    let shell = shell.unwrap_or_else(|| {
        Shell::new(Some(ShellOptions {
            session_env: params.session_env,
            snapshot_path: params.snapshot_path,
            minimizer: params.minimizer,
            ..ShellOptions::default()
        }))
    });

    let transcript = Transcript::start()?;

    let mut cancel_token = CancelToken::new(Some(params.timeout_ms));
    // The abort token reaches this run's cancellation flag; it is what the
    // signal watcher aborts (upstream: `Shell::abort()` from the JS caller).
    let abort_token = cancel_token.emplace_abort_token();
    *ABORT_SLOT.lock().unwrap_or_else(|err| err.into_inner()) = Some(abort_token);

    let run_options = ShellRunOptions {
        command: params.command,
        cwd: Some(params.cwd),
        env: Some(params.env),
        timeout_ms: Some(params.timeout_ms),
        filesystem: None,
    };
    let outcome = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        runtime.block_on(shell.run(run_options, Some(transcript.sink()), cancel_token))
    }));

    *ABORT_SLOT.lock().unwrap_or_else(|err| err.into_inner()) = None;

    let result = match outcome {
        Ok(Ok(result)) => result,
        Ok(Err(err)) => {
            transcript.abandon();
            drop(shell);
            return Err(format!("shell engine error: {err}"));
        }
        Err(payload) => {
            transcript.abandon();
            drop(shell);
            return Err(format!(
                "shell engine panicked: {}",
                panic_message(payload.as_ref())
            ));
        }
    };

    // The engine aborts by killing its spawned processes, so a cancelled or
    // timed-out run can leave a pipe reader holding the chunk sender; bound
    // that wait and keep the transcript received so far.
    let interrupted = result.cancelled || result.timed_out;
    let output = transcript.finish(interrupted);
    let output_bytes = output.len() as u64;

    // `live_background_job_count` reaps finished jobs before counting, the same
    // probe the upstream host uses to decide whether a session must be kept.
    let live_background_jobs = runtime.block_on(shell.live_background_job_count());

    let retain = params.session_id.is_some() && !interrupted;
    if retain {
        let id = params.session_id.clone().unwrap_or_default();
        let mut registry = SESSIONS.lock().unwrap_or_else(|err| err.into_inner());
        registry.insert(id, SessionEntry { shell, fingerprint });
    } else {
        // Explicit: dropping the session is the engine's kill-on-drop teardown
        // for background children (upstream does the same for a session it
        // does not retain, and for every cancelled/quarantined one).
        drop(shell);
    }

    let mut envelope = Map::new();
    if let Some(exit_code) = result.exit_code {
        envelope.insert("exitCode".to_string(), Value::from(exit_code));
    }
    envelope.insert("cancelled".to_string(), Value::Bool(result.cancelled));
    envelope.insert("timedOut".to_string(), Value::Bool(result.timed_out));
    if let Some(directory) = result.working_dir {
        envelope.insert("workingDir".to_string(), Value::from(directory));
    }
    if result.minimized.is_some() {
        envelope.insert("minimized".to_string(), minimized_json(result.minimized));
    }
    envelope.insert("output".to_string(), Value::from(output));
    envelope.insert("outputBytes".to_string(), Value::from(output_bytes));
    envelope.insert(
        "liveBackgroundJobs".to_string(),
        Value::from(live_background_jobs),
    );
    envelope.insert(
        "sessionId".to_string(),
        params.session_id.map_or(Value::Null, Value::from),
    );
    envelope.insert("sessionState".to_string(), Value::from(session_state));
    envelope.insert("sessionRetained".to_string(), Value::Bool(retain));
    envelope.insert("signalsArmed".to_string(), Value::Bool(signals_armed));
    Ok(Value::Object(envelope))
}

/// One engine session's output transcript: the merged stdout/stderr stream the
/// engine delivers through `on_chunk`, accumulated by its own thread so a
/// verbose command never blocks on the consumer.
struct Transcript {
    /// Our handle on the engine's sink; dropped before the reader is awaited so
    /// the channel can disconnect once the engine's own clone is gone.
    chunks: flume::Sender<String>,
    collected: Arc<Mutex<String>>,
    reader: std::thread::JoinHandle<()>,
    /// Fires when the reader has consumed everything still queued.
    drained: mpsc::Receiver<()>,
}

impl Transcript {
    fn start() -> Result<Self, String> {
        let (chunks, received) = flume::unbounded::<String>();
        let collected = Arc::new(Mutex::new(String::new()));
        let (drained_tx, drained) = mpsc::channel::<()>();
        let reader = std::thread::Builder::new()
            .name("toolhost-shell-transcript".to_string())
            .spawn({
                let collected = Arc::clone(&collected);
                move || {
                    while let Ok(chunk) = received.recv() {
                        collected
                            .lock()
                            .unwrap_or_else(|err| err.into_inner())
                            .push_str(&chunk);
                    }
                    drop(drained_tx);
                }
            })
            .map_err(|err| format!("failed to spawn the transcript reader: {err}"))?;
        Ok(Self {
            chunks,
            collected,
            reader,
            drained,
        })
    }

    /// The sink the engine streams into for one run.
    fn sink(&self) -> flume::Sender<String> {
        self.chunks.clone()
    }

    /// Waits for the reader and returns the transcript.
    ///
    /// `interrupted` bounds the wait (see [`INTERRUPTED_DRAIN_TIMEOUT`]): an
    /// interrupted run can leave a pipe reader holding the sender open, and the
    /// transcript is then taken as delivered. Clean runs wait without a
    /// deadline, so no chunk the engine accepted is dropped.
    fn finish(self, interrupted: bool) -> String {
        let Self {
            chunks,
            collected,
            reader,
            drained,
        } = self;
        drop(chunks);
        let done = if interrupted {
            drained.recv_timeout(INTERRUPTED_DRAIN_TIMEOUT).is_ok()
        } else {
            let _ = drained.recv();
            true
        };
        if done {
            let _ = reader.join();
        }
        std::mem::take(&mut *collected.lock().unwrap_or_else(|err| err.into_inner()))
    }

    /// Bounded teardown for the paths that discard the transcript (an engine
    /// error or panic): the reader must not be left holding the buffer.
    fn abandon(self) {
        let Self {
            chunks,
            reader,
            drained,
            ..
        } = self;
        drop(chunks);
        let _ = drained.recv_timeout(INTERRUPTED_DRAIN_TIMEOUT);
        drop(reader);
    }
}

/// Serializes the engine's `MinimizerResult` with the field names the upstream
/// native binding exposes to TypeScript (`originalText`, `inputBytes`, …).
fn minimized_json(minimized: Option<pi_shell::MinimizerResult>) -> Value {
    let Some(minimized) = minimized else {
        return Value::Null;
    };
    let mut object = Map::new();
    object.insert("filter".to_string(), Value::from(minimized.filter));
    object.insert("text".to_string(), Value::from(minimized.text));
    object.insert(
        "originalText".to_string(),
        Value::from(minimized.original_text),
    );
    object.insert("inputBytes".to_string(), Value::from(minimized.input_bytes));
    object.insert(
        "outputBytes".to_string(),
        Value::from(minimized.output_bytes),
    );
    Value::Object(object)
}

fn panic_message(payload: &(dyn Any + Send)) -> String {
    if let Some(message) = payload.downcast_ref::<&str>() {
        return (*message).to_string();
    }
    if let Some(message) = payload.downcast_ref::<String>() {
        return message.clone();
    }
    "non-string panic payload".to_string()
}

/// Installs SIGINT/SIGTERM handling once per process: a signal aborts the
/// in-flight run through the engine's abort token; with no run in flight the
/// helper exits with `128 + signal` rather than swallowing the signal.
///
/// Unix only: elsewhere no handler is installed and the envelope reports
/// `signalsArmed: false`, so a host on those platforms must cancel by killing
/// the helper process.
#[cfg(unix)]
fn arm_signals() {
    static WATCHER: LazyLock<()> = LazyLock::new(|| {
        use tokio::signal::unix::{SignalKind, signal};

        let Ok(runtime) = runtime() else {
            return;
        };
        // Registered here, on the calling thread, so `signalsArmed` is already
        // true when the run starts; the task only reads the streams.
        let (Ok(mut interrupt), Ok(mut terminate)) = runtime.block_on(async {
            (
                signal(SignalKind::interrupt()),
                signal(SignalKind::terminate()),
            )
        }) else {
            return;
        };
        SIGNALS_ARMED.store(true, Ordering::Relaxed);
        runtime.spawn(async move {
            loop {
                let number = tokio::select! {
                    _ = interrupt.recv() => 2,
                    _ = terminate.recv() => 15,
                };
                if !abort_in_flight_run() {
                    std::process::exit(128 + number);
                }
            }
        });
    });
    LazyLock::force(&WATCHER);
}

#[cfg(not(unix))]
fn arm_signals() {
    // Signal-driven cancellation is unix-only in this helper (see the module
    // docs); `SIGNALS_ARMED` therefore stays false and the host cancels by
    // killing the process.
}

/// Aborts the run recorded in [`ABORT_SLOT`]; `false` when no run is in flight.
fn abort_in_flight_run() -> bool {
    let slot = ABORT_SLOT.lock().unwrap_or_else(|err| err.into_inner());
    slot.as_ref().is_some_and(|token| {
        token.abort(AbortReason::Signal);
        true
    })
}

/// Validated run parameters, owned and never re-read from the JSON object.
struct Params {
    command: String,
    cwd: String,
    env: HashMap<String, String>,
    timeout_ms: u32,
    session_env: Option<HashMap<String, String>>,
    snapshot_path: Option<String>,
    minimizer: Option<MinimizerOptions>,
    session_id: Option<String>,
    abort_on_signals: bool,
}

/// Every key the engine accepts; anything else is a caller mistake.
const KNOWN_KEYS: [&str; 11] = [
    "command",
    "cwd",
    "env",
    "timeoutMs",
    "sessionEnv",
    "snapshotPath",
    "minimizer",
    "sessionId",
    "workspaceRoot",
    "abortOnSignals",
    "filesystem",
];

/// Minimizer keys mirroring the upstream native `MinimizerOptions` surface.
const MINIMIZER_KEYS: [&str; 8] = [
    "enabled",
    "settingsPath",
    "settingsHash",
    "only",
    "except",
    "maxCaptureBytes",
    "sourceOutlineLevel",
    "legacyFilters",
];

impl Params {
    fn parse(params: Value) -> Result<Self, String> {
        let Value::Object(params) = params else {
            return Err("params must be a JSON object".to_string());
        };

        for key in params.keys() {
            if !KNOWN_KEYS.contains(&key.as_str()) {
                return Err(format!(
                    "unknown parameter {key:?}; expected one of {KNOWN_KEYS:?}"
                ));
            }
        }

        let command = required_str(&params, "command")?.to_string();
        if command.is_empty() {
            return Err("command must not be empty".to_string());
        }
        if command.contains('\0') {
            return Err("command must not contain a NUL byte".to_string());
        }

        let cwd = required_str(&params, "cwd")?;
        let cwd = canonical_dir(cwd, "cwd")?;
        if let Some(root) = optional_str(&params, "workspaceRoot")? {
            let root = canonical_dir(root, "workspaceRoot")?;
            if cwd != root && !Path::new(&cwd).starts_with(&root) {
                return Err(format!(
                    "cwd {cwd:?} is outside the authorized workspace root {root:?}"
                ));
            }
        }

        let env = match params.get("env") {
            Some(value) => string_map(value, "env")?,
            None => return Err("env is required (pass an object, possibly empty)".to_string()),
        };

        let timeout_ms = match params.get("timeoutMs") {
            Some(value) => {
                let Some(ms) = value.as_u64() else {
                    return Err(format!("timeoutMs must be a positive integer, got {value}"));
                };
                if ms == 0 {
                    return Err("timeoutMs must be a positive integer, got 0".to_string());
                }
                u32::try_from(ms).map_err(|_| format!("timeoutMs must fit in 32 bits, got {ms}"))?
            }
            None => return Err("timeoutMs is required (milliseconds, positive)".to_string()),
        };

        let session_env = match params.get("sessionEnv") {
            Some(value) if !value.is_null() => Some(string_map(value, "sessionEnv")?),
            _ => None,
        };

        let snapshot_path = match optional_str(&params, "snapshotPath")? {
            Some(path) => Some(canonical_file(path, "snapshotPath")?),
            None => None,
        };

        let minimizer = match params.get("minimizer") {
            Some(value) if !value.is_null() => Some(minimizer_options(value)?),
            _ => None,
        };

        let session_id = match optional_str(&params, "sessionId")? {
            Some(id) => {
                if id.is_empty() {
                    None
                } else {
                    Some(id.to_string())
                }
            }
            None => None,
        };

        let abort_on_signals = match params.get("abortOnSignals") {
            Some(Value::Bool(value)) => *value,
            Some(other) => {
                return Err(format!("abortOnSignals must be a boolean, got {other}"));
            }
            None => true,
        };

        // The injected `scheme://` filesystem is a JS handler in upstream and
        // cannot exist here; native host paths are the only backend.
        match params.get("filesystem") {
            None | Some(Value::Null) => {}
            Some(_) => {
                return Err(
                    "filesystem must be null: this helper serves the native host filesystem only"
                        .to_string(),
                );
            }
        }

        Ok(Self {
            command,
            cwd,
            env,
            timeout_ms,
            session_env,
            snapshot_path,
            minimizer,
            session_id,
            abort_on_signals,
        })
    }

    /// Session identity used to detect a reused `sessionId` whose engine
    /// configuration changed (upstream keys a session per configuration too).
    fn fingerprint(&self) -> String {
        let mut out = String::new();
        if let Some(env) = self.session_env.as_ref() {
            let mut entries: Vec<(&String, &String)> = env.iter().collect();
            entries.sort_unstable();
            for (key, value) in entries {
                out.push_str(key);
                out.push('\u{1}');
                out.push_str(value);
                out.push('\u{2}');
            }
        }
        out.push('\u{3}');
        if let Some(path) = self.snapshot_path.as_ref() {
            out.push_str(path);
        }
        out.push('\u{4}');
        if let Some(minimizer) = self.minimizer.as_ref() {
            out.push_str(&format!("{minimizer:?}"));
        }
        out
    }
}

fn required_str<'a>(params: &'a Map<String, Value>, field: &str) -> Result<&'a str, String> {
    params
        .get(field)
        .and_then(Value::as_str)
        .ok_or_else(|| format!("{field} is required and must be a string"))
}

fn optional_str<'a>(
    params: &'a Map<String, Value>,
    field: &str,
) -> Result<Option<&'a str>, String> {
    match params.get(field) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::String(value)) => Ok(Some(value)),
        Some(other) => Err(format!("{field} must be a string, got {other}")),
    }
}

/// Environment variables are names and values the child inherits; a NUL or an
/// `=` in the name would be silently unrepresentable downstream.
fn string_map(value: &Value, field: &str) -> Result<HashMap<String, String>, String> {
    let Value::Object(map) = value else {
        return Err(format!(
            "{field} must be an object of string values, got {value}"
        ));
    };
    let mut out = HashMap::with_capacity(map.len());
    for (key, value) in map {
        let Some(text) = value.as_str() else {
            return Err(format!("{field}.{key} must be a string, got {value}"));
        };
        if key.is_empty() {
            return Err(format!("{field} contains an empty variable name"));
        }
        if key.contains('=') || key.contains('\0') {
            return Err(format!("{field}.{key} is not a valid variable name"));
        }
        if text.contains('\0') {
            return Err(format!("{field}.{key} must not contain a NUL byte"));
        }
        out.insert(key.clone(), text.to_string());
    }
    Ok(out)
}

/// Requires the caller's canonical spelling: `cwd` is compared path-wise by the
/// engine when it decides whether to move the shell, so an aliased spelling
/// (`..`, a symlink, a trailing separator) is a caller bug worth reporting.
fn canonical_dir(raw: &str, field: &str) -> Result<String, String> {
    let path = Path::new(raw);
    if !path.is_absolute() {
        return Err(format!("{field} must be an absolute path, got {raw:?}"));
    }
    let canonical = fs::canonicalize(path)
        .map_err(|err| format!("{field} {raw:?} cannot be resolved: {err}"))?;
    if canonical.as_path() != path {
        return Err(format!(
            "{field} {raw:?} is not canonical; use {:?}",
            canonical.display().to_string()
        ));
    }
    let metadata = fs::metadata(&canonical)
        .map_err(|err| format!("{field} {raw:?} cannot be inspected: {err}"))?;
    if !metadata.is_dir() {
        return Err(format!("{field} {raw:?} is not a directory"));
    }
    Ok(raw.to_string())
}

/// `snapshotPath` is sourced by the engine at session creation, so it must be
/// a real file, spelled canonically like `cwd`.
fn canonical_file(raw: &str, field: &str) -> Result<String, String> {
    let path = Path::new(raw);
    if !path.is_absolute() {
        return Err(format!("{field} must be an absolute path, got {raw:?}"));
    }
    let canonical = fs::canonicalize(path)
        .map_err(|err| format!("{field} {raw:?} cannot be resolved: {err}"))?;
    if canonical.as_path() != path {
        return Err(format!(
            "{field} {raw:?} is not canonical; use {:?}",
            canonical.display().to_string()
        ));
    }
    if !canonical.is_file() {
        return Err(format!("{field} {raw:?} is not a file"));
    }
    Ok(raw.to_string())
}

/// Maps the upstream native minimizer options one-to-one; the engine decides
/// whether they enable anything (it is inert unless `enabled`/`settingsPath`
/// opt in, and a mismatched `settingsHash` is refused by the engine itself).
fn minimizer_options(value: &Value) -> Result<MinimizerOptions, String> {
    let Value::Object(map) = value else {
        return Err(format!("minimizer must be an object, got {value}"));
    };
    for key in map.keys() {
        if !MINIMIZER_KEYS.contains(&key.as_str()) {
            return Err(format!(
                "unknown minimizer option {key:?}; expected one of {MINIMIZER_KEYS:?}"
            ));
        }
    }

    let mut options = MinimizerOptions::default();
    if let Some(value) = map.get("enabled") {
        options.enabled = Some(
            value
                .as_bool()
                .ok_or_else(|| format!("minimizer.enabled must be a boolean, got {value}"))?,
        );
    }
    if let Some(value) = map.get("settingsPath") {
        options.settings_path = Some(
            value
                .as_str()
                .ok_or_else(|| format!("minimizer.settingsPath must be a string, got {value}"))?
                .to_string(),
        );
    }
    if let Some(value) = map.get("settingsHash") {
        options.settings_hash = Some(
            value
                .as_str()
                .ok_or_else(|| format!("minimizer.settingsHash must be a string, got {value}"))?
                .to_string(),
        );
    }
    if let Some(value) = map.get("only") {
        options.only = Some(string_list(value, "minimizer.only")?);
    }
    if let Some(value) = map.get("except") {
        options.except = Some(string_list(value, "minimizer.except")?);
    }
    if let Some(value) = map.get("maxCaptureBytes") {
        let bytes = value
            .as_u64()
            .ok_or_else(|| format!("minimizer.maxCaptureBytes must be an integer, got {value}"))?;
        options.max_capture_bytes =
            Some(u32::try_from(bytes).map_err(|_| {
                format!("minimizer.maxCaptureBytes must fit in 32 bits, got {bytes}")
            })?);
    }
    if let Some(value) = map.get("sourceOutlineLevel") {
        options.source_outline_level = Some(
            value
                .as_str()
                .ok_or_else(|| {
                    format!("minimizer.sourceOutlineLevel must be a string, got {value}")
                })?
                .to_string(),
        );
    }
    if let Some(value) = map.get("legacyFilters") {
        options.legacy_filters =
            Some(value.as_bool().ok_or_else(|| {
                format!("minimizer.legacyFilters must be a boolean, got {value}")
            })?);
    }
    Ok(options)
}

fn string_list(value: &Value, field: &str) -> Result<Vec<String>, String> {
    let Value::Array(items) = value else {
        return Err(format!("{field} must be an array of strings, got {value}"));
    };
    items
        .iter()
        .map(|item| {
            item.as_str()
                .map(str::to_string)
                .ok_or_else(|| format!("{field} must contain only strings, got {item}"))
        })
        .collect()
}
