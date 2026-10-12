//! Glob engine effect boundary: the upstream `pi-walker` scan engine behind a
//! shell-free CLI call.
//!
//! Upstream (`crates/pi-natives/src/glob.rs`) exposes this operation over
//! N-API: `glob(options, onMatch)` resolves a search root through `pi-vfs`,
//! walks it with `pi-walker` (glob matching, gitignore semantics, `.git` and
//! `node_modules` policy, depth bounds, mtime ranking, limits, scan cache),
//! applies the native file-type filter, and returns `{ matches, totalMatches }`.
//!
//! The engine stays upstream code: `pi_walker::CompiledWalkGlob` (compiled by
//! `globset` with `literal_separator`), `pi_walker::WalkRequest` and its
//! collection APIs, and `pi_vfs::BlockingFs` are used unchanged. Only the
//! transport is replaced here:
//!
//! - the N-API options object arrives as a JSON object and the result leaves as
//!   the same JSON shape (`iofs::GlobMatch` / `GlobResult`, `camelCase` keys,
//!   `FileType` as the numeric enum N-API hands to JavaScript);
//! - `onMatch` (a `ThreadsafeFunction` that re-announced the matches this
//!   operation returns) has no counterpart in a one-shot CLI: there is no
//!   partial-result stream, and no effect is replayed;
//! - the JS `AbortSignal` half of upstream's `CancelToken` cannot exist here,
//!   because the parent kills the process on peer loss or deadline. The
//!   deadline half is kept: the walker's heartbeat and the per-match heartbeat
//!   check the same armed deadline, and an engine that observes it fails the
//!   call with upstream's own `Aborted: Timeout` error instead of reporting a
//! truncated walk as an empty or complete result. `signal` belongs to the
//! parent transport; non-null `filesystem` providers are rejected explicitly
//! until that provider transport is registered.
//!
//! `build_glob_pattern` and `walk_depth_bound` are ported verbatim from
//! `crates/pi-natives/src/glob_util.rs`: that module is N-API-only (it builds
//! `napi::Error`s), but these two functions are pure pattern string policy and
//! the normalization they perform is required for the real matcher to see the
//! same patterns upstream feeds it.

use std::{
    cmp::Ordering,
    fmt,
    path::{Path, PathBuf},
    time::{Duration, Instant},
};

use pi_vfs::BlockingFs;
use serde::{Deserialize, Serialize, Serializer};
use serde_json::Value;

/// Resolved filesystem entry kind (`iofs::FileType`).
///
/// The discriminants are the values N-API passes to JavaScript
/// (`File = 1`, `Dir = 2`, `Symlink = 3`) and the values this module reports.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
#[repr(u32)]
enum FileType {
    /// Regular file.
    File = 1,
    /// Directory.
    Dir = 2,
    /// Symbolic link.
    Symlink = 3,
}

impl Serialize for FileType {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_u32(*self as u32)
    }
}

/// The `fileType` input: N-API receives the numeric enum; the documented names
/// are accepted as the same three values.
#[derive(Deserialize)]
#[serde(untagged)]
enum FileTypeParam {
    Numeric(u32),
    Named(String),
}

impl FileType {
    fn from_param(param: FileTypeParam) -> Result<Self, String> {
        match param {
            FileTypeParam::Numeric(value) => match value {
                1 => Ok(Self::File),
                2 => Ok(Self::Dir),
                3 => Ok(Self::Symlink),
                other => Err(format!(
                    "Invalid glob fileType: {other}; expected 1 (file), 2 (dir), or 3 (symlink)"
                )),
            },
            FileTypeParam::Named(name) => match name.as_str() {
                "file" => Ok(Self::File),
                "dir" => Ok(Self::Dir),
                "symlink" => Ok(Self::Symlink),
                other => Err(format!(
                    "Invalid glob fileType: {other:?}; expected \"file\", \"dir\", or \"symlink\""
                )),
            },
        }
    }
}

/// `iofs::from_walker_file_type`.
const fn from_walker_file_type(file_type: pi_walker::FileType) -> FileType {
    match file_type {
        pi_walker::FileType::File => FileType::File,
        pi_walker::FileType::Dir => FileType::Dir,
        pi_walker::FileType::Symlink => FileType::Symlink,
    }
}

/// A single filesystem entry from a directory scan (`iofs::GlobMatch`).
///
/// `path` is relative to the search root and uses forward slashes. `mtime`
/// (milliseconds since the Unix epoch) and `size` are present only when the
/// scan collected them, matching the `undefined` N-API fields. Both are load
/// bearing: `jfind` reads `size` (its `sortByMtime` call exists to make the
/// walker stat entries) and the glob tool ranks and reports by `mtime`.
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct GlobMatch {
    path: String,
    file_type: FileType,
    #[serde(skip_serializing_if = "Option::is_none")]
    mtime: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    size: Option<f64>,
}

impl From<pi_walker::CollectedEntry> for GlobMatch {
    fn from(entry: pi_walker::CollectedEntry) -> Self {
        Self {
            path: entry.path,
            file_type: from_walker_file_type(entry.file_type),
            mtime: entry.mtime,
            size: entry.size,
        }
    }
}

/// Result payload returned by a glob operation (`GlobResult`).
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct GlobResult {
    matches: Vec<GlobMatch>,
    total_matches: u32,
}

/// `GlobOptions` as the CLI receives them.
///
/// Unknown keys are ignored, as N-API ignores unknown properties on the options
/// object. `cache` and `includeNodeModules` are upstream options the current
/// caller does not send; they keep their upstream defaults and semantics.
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct GlobParams {
    /// Directory to search: an absolute host path.
    path: String,
    /// Glob pattern to match (e.g., "*.ts").
    pattern: String,
    /// Filter by file type: 1/"file", 2/"dir", or 3/"symlink".
    #[serde(default)]
    file_type: Option<FileTypeParam>,
    /// Match simple patterns recursively by default (`*.ts` -> recursive).
    #[serde(default)]
    recursive: Option<bool>,
    /// Include hidden files (default: false).
    #[serde(default)]
    hidden: Option<bool>,
    /// Maximum number of results to return.
    #[serde(default)]
    max_results: Option<u32>,
    /// Respect .gitignore files (default: true).
    #[serde(default)]
    gitignore: Option<bool>,
    /// Enable walker scan caching (default: false).
    #[serde(default)]
    cache: Option<bool>,
    /// Sort results by mtime (most recent first) before applying limit.
    #[serde(default)]
    sort_by_mtime: Option<bool>,
    /// Include `node_modules` entries when the pattern does not mention them.
    #[serde(default)]
    include_node_modules: Option<bool>,
    /// Timeout in milliseconds for the operation.
    #[serde(default)]
    timeout_ms: Option<u32>,
}

/// Internal runtime config for a single glob execution (`GlobConfig`).
struct GlobConfig {
    /// Filesystem `root` is walked and symlink targets are resolved through.
    filesystem: BlockingFs,
    root: PathBuf,
    pattern: String,
    recursive: bool,
    include_hidden: bool,
    file_type_filter: Option<FileType>,
    max_results: usize,
    use_gitignore: bool,
    mentions_node_modules: bool,
    sort_by_mtime: bool,
    cache: bool,
}

/// Engine-visible deadline.
///
/// Upstream arms `pi_natives::task::CancelToken::new(timeout_ms, signal)`,
/// whose core (`pi_shell::cancel::CancelToken`) is a deadline plus an optional
/// abort flag; `heartbeat()` fails with the deadline's
/// `"Aborted: Timeout"` once it passes. The abort flag carried a JavaScript
/// `AbortSignal`, which a one-shot CLI does not have: the parent kills the
/// process instead, and no effect is replayed. The deadline half is kept
/// verbatim, so an operation that notices its own deadline fails with upstream's
/// message rather than returning a false empty or partial result.
struct Deadline {
    deadline: Option<Instant>,
}

impl Deadline {
    fn new(timeout_ms: Option<u32>) -> Self {
        Self {
            deadline: timeout_ms.map(|ms| Instant::now() + Duration::from_millis(u64::from(ms))),
        }
    }

    fn heartbeat(&self) -> Result<(), DeadlineExpired> {
        let Some(deadline) = self.deadline else {
            return Ok(());
        };
        if deadline <= Instant::now() {
            return Err(DeadlineExpired);
        }
        Ok(())
    }
}

/// The engine observed an expired deadline.
///
/// Its text is the reason core cancellation carries:
/// `format!("Aborted: {reason:?}")` for `AbortReason::Timeout`.
#[derive(Debug)]
struct DeadlineExpired;

impl fmt::Display for DeadlineExpired {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("Aborted: Timeout")
    }
}

/// Upstream's `WalkError::InvalidData` message
/// (`pi-natives/src/iofs.rs::walker_error_to_napi`).
fn invalid_data(path: &Path, message: String) -> String {
    format!(
        "Native directory scan failed for {}: {message}",
        path.display()
    )
}

/// Upstream's `iofs::map_walker_error`: a heartbeat failure surfaces as its own
/// message (the deadline's `Aborted: Timeout`), an unskippable directory
/// failure as the `InvalidData` text.
fn map_walker_error<E: fmt::Display>(err: pi_walker::WalkError<E>) -> String {
    match err {
        pi_walker::WalkError::Interrupted(err) => err.to_string(),
        pi_walker::WalkError::InvalidData { path, message } => invalid_data(&path, message),
    }
}

/// Canonical spelling of an existing root, or the root itself when it cannot be
/// canonicalized (upstream `iofs::canonical_search_path`).
fn canonical_search_path(fs: &BlockingFs, path: PathBuf) -> PathBuf {
    match fs.canonicalize(&path) {
        Ok(canonical) if pi_vfs::url_scheme(&canonical) == pi_vfs::url_scheme(&path) => canonical,
        _ => path,
    }
}

/// Resolve the search root to the canonical directory a walk starts from
/// (upstream `iofs::resolve_search_dir`).
///
/// Upstream also joins relative paths with the process cwd and routes absolute
/// `scheme://` URLs to a provider filesystem. This CLI receives an already
/// authorized absolute root, installs no provider, and its parent owns root
/// confinement, so anything else is rejected here instead of being silently
/// reinterpreted.
fn resolve_search_dir(fs: &BlockingFs, path: &str) -> Result<PathBuf, String> {
    let root = PathBuf::from(path);
    if !root.is_absolute() {
        return Err(invalid_data(
            &root,
            format!("Path must be an absolute directory: {path}"),
        ));
    }
    let metadata = fs
        .metadata(&root)
        .map_err(|err| invalid_data(&root, format!("Path not found: {err}")))?;
    if !metadata.is_dir() {
        return Err(invalid_data(
            &root,
            "Search path must be a directory".to_string(),
        ));
    }
    Ok(canonical_search_path(fs, root))
}

fn match_mtime(entry: &GlobMatch) -> f64 {
    entry.mtime.unwrap_or(0.0)
}

fn compare_matches_by_rank(a: &GlobMatch, b: &GlobMatch) -> Ordering {
    match_mtime(b)
        .total_cmp(&match_mtime(a))
        .then_with(|| a.path.cmp(&b.path))
}

fn resolve_symlink_target_type(fs: &BlockingFs, target_path: PathBuf) -> Option<FileType> {
    let metadata = fs.metadata(target_path).ok()?;
    if metadata.is_dir() {
        Some(FileType::Dir)
    } else if metadata.is_file() {
        Some(FileType::File)
    } else {
        None
    }
}

fn apply_file_type_filter(
    entry: &pi_walker::CollectedEntry,
    config: &GlobConfig,
) -> Option<FileType> {
    let file_type = from_walker_file_type(entry.file_type);
    let Some(filter) = config.file_type_filter else {
        return Some(file_type);
    };
    if file_type == filter {
        return Some(file_type);
    }
    if file_type != FileType::Symlink {
        return None;
    }
    match filter {
        FileType::File | FileType::Dir => {
            let resolved =
                resolve_symlink_target_type(&config.filesystem, entry.absolute_path(&config.root))?;
            if resolved == filter {
                Some(resolved)
            } else {
                None
            }
        }
        FileType::Symlink => None,
    }
}

fn collect_ranked_matches(
    request: &pi_walker::WalkRequest,
    config: &GlobConfig,
    ct: &Deadline,
) -> Result<Vec<GlobMatch>, String> {
    let outcome = request
        .collect_ranked_with_heartbeat(
            pi_walker::WalkRank::MtimeDescPathAsc,
            config.max_results,
            || ct.heartbeat(),
        )
        .map_err(map_walker_error)?;
    Ok(outcome.entries.into_iter().map(GlobMatch::from).collect())
}

fn collect_native_filtered_matches(
    request: &pi_walker::WalkRequest,
    config: &GlobConfig,
    ct: &Deadline,
) -> Result<Vec<GlobMatch>, String> {
    let outcome = request
        .collect_with_heartbeat(|| ct.heartbeat())
        .map_err(map_walker_error)?;
    let mut collected = Vec::new();
    for entry in outcome.entries {
        ct.heartbeat().map_err(|err| err.to_string())?;
        let Some(effective_file_type) = apply_file_type_filter(&entry, config) else {
            continue;
        };
        let mut matched_entry = GlobMatch::from(entry);
        matched_entry.file_type = effective_file_type;
        collected.push(matched_entry);
        if !config.sort_by_mtime && collected.len() >= config.max_results {
            break;
        }
    }
    Ok(collected)
}

/// Executes walker-owned glob filtering plus optional native file-type
/// filtering and ranking (`run_glob`).
///
/// The N-API `on_match` stream is transport, not policy: it re-announced the
/// matches this function returns, after the same filters and limits.
fn run_glob(config: GlobConfig, ct: &Deadline) -> Result<GlobResult, String> {
    let walk_glob_pattern = build_glob_pattern(&config.pattern, config.recursive);
    // Non-recursive patterns bound the walk: `dir/*` must not traverse the
    // entire subtree under `dir` to match only direct children.
    let walk_depth_limit = walk_depth_bound(&walk_glob_pattern);
    let walk_glob = pi_walker::CompiledWalkGlob::new([walk_glob_pattern])
        .map_err(|err| format!("Invalid glob pattern: {err}"))?;
    if config.max_results == 0 {
        return Ok(GlobResult {
            matches: Vec::new(),
            total_matches: 0,
        });
    }

    let scan_detail = if config.sort_by_mtime {
        pi_walker::WalkDetail::Full
    } else {
        pi_walker::WalkDetail::Minimal
    };
    let base_request = pi_walker::WalkRequest::new(config.root.clone())
        .filesystem(config.filesystem.clone())
        .hidden(config.include_hidden)
        .gitignore(config.use_gitignore)
        .skip_git(true)
        .skip_node_modules(!config.mentions_node_modules)
        .follow_links(pi_walker::FollowLinks::Never)
        .detail(scan_detail)
        .order(pi_walker::WalkOrder::Path)
        .emit_root(false)
        .depth(1, walk_depth_limit)
        .directory_errors(pi_walker::DirectoryErrorMode::SkipSkippable)
        .cache(config.cache)
        .empty_recheck(pi_walker::EmptyRecheck::Configured)
        .filter(
            pi_walker::WalkFilter::all()
                .glob(walk_glob)
                .node_modules_unless_mentioned(config.mentions_node_modules),
        );

    let mut matches = if config.sort_by_mtime && config.file_type_filter.is_none() {
        collect_ranked_matches(&base_request, &config, ct)?
    } else {
        let request = if !config.sort_by_mtime && config.file_type_filter.is_none() {
            base_request.limit(config.max_results)
        } else {
            base_request
        };
        collect_native_filtered_matches(&request, &config, ct)?
    };

    if config.sort_by_mtime {
        // Sorting mode: rank by mtime descending, then apply max-results
        // truncation.
        matches.sort_by(compare_matches_by_rank);
        matches.truncate(config.max_results);
    }
    let total_matches = matches.len().min(u32::MAX as usize) as u32;
    Ok(GlobResult {
        matches,
        total_matches,
    })
}

/// Find filesystem entries matching a glob pattern.
///
/// `params` is the upstream options object: `{ path, pattern, fileType?,
/// recursive?, hidden?, maxResults?, gitignore?, cache?, sortByMtime?,
/// includeNodeModules?, timeoutMs? }`. Returns `{ matches, totalMatches }`.
///
/// # Errors
/// Returns an error when the parameters are malformed, the search path is not
/// an absolute directory, the path cannot be resolved, the glob pattern is
/// invalid, a directory scan fails unskippably, or the deadline is observed.
pub fn run(params: Value) -> Result<Value, String> {
    if params
        .get("filesystem")
        .is_some_and(|provider| !provider.is_null())
    {
        return Err("No URL filesystem provider is registered in this native host".to_string());
    }
    let GlobParams {
        path,
        pattern,
        file_type,
        recursive,
        hidden,
        max_results,
        gitignore,
        cache,
        sort_by_mtime,
        include_node_modules,
        timeout_ms,
    } = serde_json::from_value(params).map_err(|err| format!("Invalid glob parameters: {err}"))?;
    let file_type_filter = file_type.map(FileType::from_param).transpose()?;

    // Upstream `glob()`: trim the raw pattern, then fall back to "*" when empty.
    // (The copy is paid only when trimming actually changes the pattern.)
    let mut pattern = pattern;
    if pattern.trim().len() != pattern.len() {
        let trimmed = pattern.trim().to_string();
        pattern = trimmed;
    }
    if pattern.is_empty() {
        pattern.push('*');
    }

    let mentions_node_modules =
        include_node_modules.unwrap_or_else(|| pattern.contains("node_modules"));
    let filesystem = BlockingFs::native();
    // Upstream arms the cancel token before the worker resolves the root, so the
    // deadline covers root resolution as well.
    let deadline = Deadline::new(timeout_ms);
    let root = resolve_search_dir(&filesystem, &path)?;

    let result = run_glob(
        GlobConfig {
            root,
            filesystem,
            pattern,
            include_hidden: hidden.unwrap_or(false),
            file_type_filter,
            recursive: recursive.unwrap_or(true),
            max_results: max_results.map_or(usize::MAX, |value| value as usize),
            use_gitignore: gitignore.unwrap_or(true),
            mentions_node_modules,
            sort_by_mtime: sort_by_mtime.unwrap_or(false),
            cache: cache.unwrap_or(false),
        },
        &deadline,
    )?;

    serde_json::to_value(result).map_err(|err| format!("Failed to encode glob result: {err}"))
}

/// Normalize a raw glob string: fix path separators, optionally prepend `**/`
/// for recursive matching, and close any unclosed `{` alternation groups.
///
/// Verbatim from `crates/pi-natives/src/glob_util.rs::build_glob_pattern`.
fn build_glob_pattern(glob: &str, recursive: bool) -> String {
    let normalized = glob.replace('\\', "/");
    let pattern = if !recursive
        || normalized.contains('/')
        || normalized.starts_with("**")
        || is_exact_brace_union(&normalized)
    {
        normalized
    } else {
        format!("**/{normalized}")
    };
    fix_unclosed_braces(pattern)
}

/// Maximum walk depth (path components) a normalized glob pattern can match, or
/// `usize::MAX` when unbounded.
///
/// Walk-relative globs compile with `literal_separator(true)`, so `*`, `?`, and
/// `[...]` never cross `/` — a pattern with N literal segments can only match
/// entries at most N components deep. Bounding the walk to that depth keeps
/// non-recursive patterns (`*`, `dir/*.json`) from traversing an entire subtree
/// they can never match into. `**` matches any number of components and
/// `{...}` alternations may contain `/`, so both disable the bound.
///
/// Verbatim from `crates/pi-natives/src/glob_util.rs::walk_depth_bound`.
fn walk_depth_bound(pattern: &str) -> usize {
    if pattern.contains("**") || pattern.contains('{') {
        return usize::MAX;
    }
    pattern
        .split('/')
        .filter(|seg| !seg.is_empty())
        .count()
        .max(1)
}

/// Close unclosed `{` alternation groups in a glob pattern.
///
/// LLMs occasionally produce patterns like `*.{ts,js` without the closing `}`.
/// Rather than failing, we append the missing braces.
///
/// Verbatim from `crates/pi-natives/src/glob_util.rs::fix_unclosed_braces`.
fn fix_unclosed_braces(pattern: String) -> String {
    let opens = pattern.chars().filter(|&c| c == '{').count();
    let closes = pattern.chars().filter(|&c| c == '}').count();
    if opens > closes {
        let mut fixed = pattern;
        for _ in 0..(opens - closes) {
            fixed.push('}');
        }
        fixed
    } else {
        pattern
    }
}

/// Verbatim from `crates/pi-natives/src/glob_util.rs::is_exact_brace_union`.
fn is_exact_brace_union(pattern: &str) -> bool {
    if !(pattern.starts_with('{') && pattern.ends_with('}')) {
        return false;
    }
    let inner = &pattern[1..pattern.len() - 1];
    !inner.is_empty()
        && !inner
            .chars()
            .any(|ch| matches!(ch, '*' | '?' | '[' | ']' | '{' | '}'))
}
