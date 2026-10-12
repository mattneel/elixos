# OMP tool port

M21 is active, not delivered. Reference: Oh-My-Pi 18.10.1 at
`90701813e5fba6919067848989378b4ee6239c13`; see
[the complete inventory](../OMP_INVENTORY.md) and ADR-071.

## Real boundaries already exercised

- `Elixos.Toolset.Peer` owns a supervised, lazy `:peer` host. Raw `erlexec`
  starts it; main VM cwd/environment stay unchanged. Peer dumps are disabled.
  Controller-bound calls fail without replay on peer loss. Node names use a
  bounded 128-slot rotation rather than creating an atom for every restart.
- `Elixos.Toolset.Session` canonicalizes both allowed roots and resolves every
  existing path component. Prefix siblings, traversal, escaped symlink parents
  and link cycles have real tests. A missing `/priv/home` on the host is valid
  session metadata, not a reason to alter M9's default.
- QuickBEAM 0.11.3 must use `ContextPool`/`Context`: the high-level start path
  does not forward the reduction budget. The configured heap, reduction and
  deadline limits have been broken deliberately; the context still evaluates
  `6 * 7` after each failure.
- Think and the complete Todo state machine execute original upstream code and
  original argument validation through named Jido Actions. Their 47 recorded
  cases pass exact outcome replay. Todo also checks the resulting state with a
  pure view call. The 44 Todo cases include every operation, missing-op repair,
  duplicate/unknown errors, atomic failures, Unicode, a single input string
  exceeding 65,536 bytes, and the session-file storage shape.
- The real descriptor capture covers all 56 IDs and 86 inventory variants.
  Constructor-only provisioned dependencies are disclosed in each capture;
  neither catalog membership nor an existing Action module proves availability
  or behavioral parity.

## NIF loading and effect capabilities

`runtime: false` and a stopped application do not keep its NIF unloaded.
Jido discovery scans **loaded application specifications** and calls
`Code.ensure_loaded?/1` for their modules. This was observed during the real
Jido smoke, not inferred from configuration.

The release now ships QuickBEAM/OXC as `:none`. `config/runtime.exs` removes
specifications Mix loaded before Jido starts; the peer alone starts the engines.
A discovery refresh and full two-tool smoke leave the main NIFs unloaded.
An active engine makes startup fail rather than being stopped or purged.

`apis: false` also retains default Beam callbacks. The host denies those
unscoped callbacks, particularly RPC/spawn, and future effects must register
session-bound handlers. `toolset_capabilities_test.exs` exercises that denial
in the actual host context. See ADR-075.

## JSON and source extraction

QuickBEAM's direct value conversion turns an undefined object property into
Elixir nil. OMP's JSON wire form omits it. Serialize the original envelope
once with `JSON.stringify` in the peer and decode it in Elixir: legitimate
null remains null; undefined disappears naturally. Do not strip fields from
reference output to make a comparison pass (ADR-074).

Todo sets `lenientArgValidation`. Bad object or array arguments can return a
normal result with `isError: true`, not throw. The replay driver now accepts
that actual error channel while retaining exact output/error/effect equality
and rejecting an error result classified as nominal (ADR-076).

The browser bundle imports narrow pure exports, not Node/Bun effect barrels.
The schema library eagerly initializes URL/File/FormData; real in-memory
constructors are bundled, with their notices, instead of enabling Node or
browser capabilities. `core-js-pure` 3.50.0 is the additional pinned MIT source
dependency authorized by ADR-074.

OXC removes only Todo's unrelated filesystem-path helper and its import by
AST declaration spans. All tool/state/schema/rendering bytes are retained;
`core-source.json` records the original digest and exclusions. The helper
remains in the upstream reference for the separate command surface.

Compiler JSON on stdout must be emitted as UTF-8 text:
`IO.write(IO.iodata_to_binary(:json.encode(value)))`. `IO.binwrite` through the
Unicode console double-encoded retained non-ASCII source; exact Todo replay
caught the changed em dash. Do not paper over that with output normalization.

## Input determinism and ownership

Glob ranks by mtime. Fixtures restore explicit initial `file_times` before
both reference and replay, with multi-match/capped cases; no output sorting
or dropping (ADR-073). Broad native-glob probes also need deterministic
**directory** mtimes because directories are real matches.

A pool's heap quota is per runtime thread, shared by its contexts. Keeping
47 sessions alive under one smoke owner exhausted the 64 MiB pool. Each
independent fixture owns and releases its context when its process exits;
this matches the actual ExUnit lifecycle. Do not raise limits to conceal a
resource failure. Long-lived sessions retain their own state deliberately.

Recorders retain existing cases rather than pruning acceptance evidence.
Reference observations stay under `build/`; the permanent JSON corpus stays
under `os/test/fixtures/omp/`.

## Portable native effects

`toolhost/` uses the original `pi-walker`, `pi-vfs` and `pi-shell` engines,
with the original vendored brush interpreter/parser. Its JSON-lines boundary
replaces N-API. Eight native-glob outcomes and four shell outcomes match the
pinned addon in independent roots: retained exports, pipelines, errors,
timeout and append-once included. An `execve` trace observes direct execution
of `/usr/bin/printf`, not a `/bin/sh` launcher.

Use the upstream `nightly-2026-10-06` compiler. Stable failed on `xutf`'s real
`portable_simd` feature; switching the compiler pin is the fix, not
`RUSTC_BOOTSTRAP`. Build objects live in `build/toolhost-target/` and are reused.
The native helper bounds its own Tokio workers; it does not allocate a worker
for every host CPU per session.

These are effect-engine checks, not proof of complete model-facing glob/bash
ports, URL filesystem provider transport, musl/ARM packaging or M24 promotion.
Those, the remaining tool/runtime surfaces, running-generation code binding
and the full M21 host/image gates remain required. No kernel or OTP was
rebuilt for this iteration.
