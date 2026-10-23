# Optional native Eval factory profile (ADR-092)

This is the **opt-in** Linux x86_64/aarch64 packaging path for Oh-My-Jido
F05/E01–E07. It does not change the default pure-BEAM factory selection or
claim either target verified. No build, quality check, QEMU run or disk
operation was performed while implementing these sources. The parent must
observe the real package builds and guest smoke before recording target proof.

## Package and source contract

- `melange/factory.yaml` and `scripts/package-factory.sh` keep the default
  factory pure BEAM. `factory-eval.yaml` selects the optional closure before
  compiling the **same** OS/canonical library with OTP **29.1.1**, Elixir
  **1.20.4** and target **musl**. An already compiled base factory is not a
  valid Python Eval host: the canonical adapter has a compile-time optional
  Snakepit boundary. No runtime overlay replaces protected factory modules.
- `scripts/stage-coding.exs pin-eval` / `stage-eval` require a reviewed canonical
  content pin and the MIT `vendor/snakepit/UPSTREAM.json` snapshot. Jido/ReqLLM
  licenses, notices and pristine-source inventories remain intact. Ordinary
  staging also carries the licensed optional snapshot if the canonical Mix
  project references it, but does **not** select its runtime dependency.
- `build-coding-eval.exs` uses native `Mix.Project.in_project/4` post-config:
  OS source, dependency source and committed locks are not rewritten. Its
  separate `coding/eval.lock` retains every existing OS entry and adds only
  absent canonical entries. Both dependency resolutions must leave it and the
  OS lock unchanged. QuickBEAM/Snakepit release applications are `:load`, not
  boot callbacks. The native host starts no coding session implicitly.
- QuickBEAM **0.11.3** uses its published `ZiglerPrecompiled` musl artifacts,
  never a guessed glibc download or a host NIF. `TARGET_ARCH`, `TARGET_OS=linux`,
  `TARGET_ABI=musl`, `TARGET_VENDOR=unknown` are exported in the builder;
  `ZIGLER_PRECOMPILED_GLOBAL_CACHE_PATH` retains the exact validated archive.
  Its shipped `checksum-QuickBEAM.Native.exs` specifies:

  | target archive | upstream SHA256 |
  |---|---|
  | `Elixir.QuickBEAM.Native-v0.11.3-x86_64-linux-musl.so.tar.gz` | `1eceef095c44a786f45f4e68e0337f92cb98a6903fa21370e76d6ec6e024f1fa` |
  | `Elixir.QuickBEAM.Native-v0.11.3-aarch64-linux-musl.so.tar.gz` | `90b16a8479f2aa16283c1f6d76dde94ca3869be733b79ee163d0ebe6d74a3f7a` |

  The builder checks the actual archive bytes against that manifest, compiles
  the Elixir loader with target OTP and retains the archive, source and emitted
  library digests. These published SHA256 values are not a target load proof.
- QuickBEAM's required OXC **0.19.0** has no aarch64-musl parser artifact and
  no musl formatter/linter artifacts. The recipe therefore builds **all three
  real upstream Rust NIF crates**, on both targets, with Alpine
  `rust/cargo=1.96.1-r0`, the OS-pinned Rustler **0.38.0**,
  `RUSTLER_TARGET=<arch>-unknown-linux-musl`, and
  `RUSTFLAGS=-C target-feature=-crt-static`. Cargo fetches with `--locked`;
  compilation is offline after that fetch, and all three original Cargo locks
  must remain unchanged. Rustler's explicit target configuration selects that
  target; the environment variable alone is not assumed to configure Rustler.
  There is no Rust runtime helper. No source-built NIF is mislabeled an upstream
  precompiled artifact.
- Existing kernel/OTP cross-builds stay unchanged. The target factory/OXC
  compile runs in melange's **target** environment, as the normal factory does.
  The existing image script's ARM path retains its ADR-060 x86_64 cross-bootstrap;
  the two-target command below is for an x86_64 build host with an explicitly
  installed aarch64 binfmt/QEMU user runner for target recipe execution.
  Matching-architecture melange workers need no emulator for the Eval recipe
  itself. No new emulator, toolchain or target is installed automatically.
- `coding-eval-python.yaml` pins Alpine CPython **3.14.8-r0** and builds
  `/opt/oh-my-jido-eval/venv` with system interpreter links to
  `/usr/bin/python3.14`. Native pip is a **builder-only** dependency. Its
  `--require-hashes --no-deps --only-binary=:all:` download/install consumes
  the explicit PyPI URLs/SHA256 values in `scripts/coding-eval/python-wheels.json`:
  **grpcio 1.84.0**, **protobuf 7.35.1** (upstream pure-Python wheel),
  **numpy 2.5.4** and **typing-extensions 4.16.0**. grpcio/numpy have separate
  CPython 3.14 musllinux 1.2 wheels for both architectures. Wheel notices and
  bundled native libraries remain under venv site-packages and are inventoried.
- The canonical Snakepit **0.14.0** SDK is the ordinary
  `/factory/lib/snakepit-0.14.0/priv/python` release content, including its
  generated protobuf/gRPC stubs. The actual Eval import closure needs numpy,
  grpcio/protobuf and typing-extensions. grpcio-tools/protoc, pytest, showcase
  psutil, orjson and optional OpenTelemetry exporters are not runtime imports
  of this adapter and are not silently installed. Optional SnakeBridge is not
  selected. The source SDK and MIT provenance remain in the canonical source
  inventory as well as the installed application.
- `scripts/coding-eval/config.exs` is baked into this profile's release config.
  The real IEx frontend uses the package venv through Snakepit's native
  `:python_executable`, `strategy: :system, managed: false` and loopback/internal
  listener. It starts only the actual prerequisite OTP children, **never
  Snakepit.Application's provisioning bootstrap**. Worker-local adapter env
  sets `PYTHONNOUSERSITE`/`PYTHONDONTWRITEBYTECODE`; Oh-My-Jido itself supplies
  its adapter plus SDK PYTHONPATH. Venv site-packages supplies the pinned wheels.
  No host VM cwd, OS environment, Python install or global PYTHONPATH is changed.
- JavaScript/Elixir use Oh-My-Jido's matching-ERTS, bounded **JSON-only** child
  worker, without distribution, `:peer` or ETF. Python is exclusively native
  Snakepit gRPC worker management. The image is trusted-code crash separation,
  **not** an OS sandbox; no custom launcher/framework or agent loop is added.

## Parent-owned native builds

Use the reviewed canonical checkout **after** its licensed Snakepit integration
has landed. From the Elixos repository, retain the existing default outputs:

```sh
export ELIXOS_BUILD="$PWD/build-eval"
export MELANGE="$PWD/build/tools/melange"
export APKO="$PWD/build/tools/apko"
export ELIXOS_OH_MY_JIDO_SOURCE=/home/autark/src/oh_my_jido
elixir scripts/stage-coding.exs pin-eval "$ELIXOS_OH_MY_JIDO_SOURCE"
```

Review the actual printed content pin. Explicitly assign that reviewed value to
`ELIXOS_CODING_SHA256`; do **not** automatically bless a moving checkout with
command substitution. Then:

```sh
: "${ELIXOS_CODING_SHA256:?export the explicitly reviewed pin-eval result}"
ELIXOS_EVAL_PROFILE=1 scripts/build-image.sh x86_64 aarch64
```

Prerequisites are the existing pinned melange/apko binaries, their normal
unprivileged build runner, architecture runner where required, SquashFS tools,
network access to the pinned Alpine repositories, Hex, GitHub native artifacts
and locked Cargo sources, and PyPI's exact wheel URLs. A missing pinned source,
wheel, compiler target, native export or link is a build **failure**, not an
unavailable-backend success. The scripts do not provision any prerequisite.
`ELIXOS_EVAL_PROFILE=1` refuses the default `build/` directory. Optional
`apko.lock.<arch>.json` and `system.lock.<arch>.json` live in
`$ELIXOS_BUILD/locks/`; the base committed locks are not refreshed by this path.
Both profile rootfs/SBOMs and the normal service images are emitted under that
separate build directory. Retain the builder logs and signing-key identity.

## Builder-derived immutable receipts

The build must emit nonempty actual artifacts, not hand-authored result files:

| guest path | meaning |
|---|---|
| `/factory/coding/source.json` | every selected canonical byte and explicit source pin |
| `/factory/coding/beams.json` | target OTP/Elixir/ERTS identity, all emitted BEAM/apps, assembly input/source/license inventories, profile selection |
| `/factory/coding/eval-build.json` | exact locks, QuickBEAM archive/manifest, target architecture and Cargo/rustc identity |
| `/factory/coding/inputs/eval.lock` | separate OS-authoritative optional dependency lock |
| `/factory/coding/native-artifacts/` | actual upstream-verified QuickBEAM archive |
| `/factory/coding/native-sources/` | exact QuickBEAM/OXC compile inputs and Cargo locks/notices |
| `/factory/coding/native.json{,.sha256}` | actual factory files, target ELF machine, native links/digests and ERTS NIF exports |
| `/opt/oh-my-jido-eval/source.json` | actual downloaded wheel identity/size and interpreter digest |
| `/opt/oh-my-jido-eval/native.json{,.sha256}` | actual installed venv/native library/interpreter/link digests |

`coding-eval-native.py` is a build-only readelf inventory. It rejects wrong ELF
machine/libc, missing QuickBEAM/OXC NIFs, missing target ERTS exports, unresolved
native dependencies, empty native artifacts and absent native output. Its
resolved dependency records retain actual files' hashes, including system
libraries; apko locks/SBOMs additionally seal those packages' runtime closure.
It does not execute a target or mark `target_execution_verified` true. The
explicit frontend rechecks source/BEAM/native/link inventories, loaded module
identity and the matching runtime before enabling Eval. New source bytes need
a newly reviewed pin and rebuild; neither a receipt nor a successful loader
compile establishes F05/E01–E07 acceptance.

## Separate disposable guests, both architectures

Only the parent/human performs these approved effects. Keep existing default
`build/disk.img` untouched. The following intentionally refuses existing optional
seed disks; never remove that guard or reuse a prior scenario's writable disk:

```sh
test ! -e "$ELIXOS_BUILD/disk.img" && DISK_SIZE=8G scripts/mkdisk.sh x86_64
test ! -e "$ELIXOS_BUILD/eval-smoke-x86_64.img" &&
  cp --reflink=auto --sparse=always "$ELIXOS_BUILD/disk.img" "$ELIXOS_BUILD/eval-smoke-x86_64.img"
ELIXOS_DISK="$ELIXOS_BUILD/eval-smoke-x86_64.img" QEMU_MEMORY=4096 scripts/run-qemu.sh
```

Wait for ordinary normal boot/Health/AutoCommit. In the **real guest IEx VM**:

```elixir
Code.eval_file("/factory/coding/inputs/coding-eval/smoke.exs",
  evidence_directory: "/priv/eval-smoke-x86_64")
```

For ARM, after leaving that guest, create a separate architecture-native disk
and use the existing native ARM machine/console convention:

```sh
test ! -e "$ELIXOS_BUILD/aarch64/disk.img" && DISK_SIZE=8G scripts/mkdisk.sh aarch64
test ! -e "$ELIXOS_BUILD/eval-smoke-aarch64.img" &&
  cp --reflink=auto --sparse=always "$ELIXOS_BUILD/aarch64/disk.img" "$ELIXOS_BUILD/eval-smoke-aarch64.img"
qemu-system-aarch64 -machine virt -accel kvm -accel tcg -cpu cortex-a72 \
  -m 4096 -smp 2 -nographic -no-reboot \
  -kernel "$ELIXOS_BUILD/aarch64/Image" -initrd "$ELIXOS_BUILD/aarch64/initramfs.cpio.gz" \
  -append 'console=ttyAMA0 panic=-1' \
  -drive "file=$ELIXOS_BUILD/eval-smoke-aarch64.img,if=virtio,format=raw" \
  -device virtio-rng-pci -nic none
```

In that real ARM guest, after normal health:

```elixir
Code.eval_file("/factory/coding/inputs/coding-eval/smoke.exs",
  evidence_directory: "/priv/eval-smoke-aarch64")
```

The compiled finite entrypoint refuses non-normal/NIC-enabled guests and existing
evidence directories. It invokes the **same real unified Jido Eval Action** for
all three languages, with retries explicitly disabled. Each backend must prove:
retained two-cell state, an independent session, a real workspace `Read` tool
grant and denial, language exceptions, combined 128-byte output quota,
display/artifact content, deadline invalidation and explicit reset, active
callback cancellation, actual native worker termination, host survival, no
implicit state recreation and confirmed native-process cleanup. Elixir/Python
exit 71; JavaScript's exact owned ERTS process group is terminated while a real
callback is active. The callback is an observable cancellable Jido Action, not
a model/provider mock. Existing native Snakepit worker lists must match before
and after; host cwd/environment must be unchanged. There is no effect replay.

Only full success emits `/priv/eval-smoke-<arch>/verified.json` plus its actual
SHA256 sidecar. Preserve both, the real serial transcript (including crash
containment and no panic), native package receipts, exact apko locks/SBOMs,
image digests and builder logs for **each** architecture. No failed/missing
backend is skipped or converted to a successful receipt. Record any actual
failure as an open F05/E01–E07 gate, not a passed subset.

## Interactive host use (not a standalone CLI product)

The profile's release config is the actual CLI/IEx host configuration, not an
example-only keyword list. In guest IEx, after reviewing the trusted-code policy:

```elixir
{:ok, host} = Elixos.CodingEval.start(trusted: true)
{:ok, owner} = Elixos.CodingEval.open(id: "eval-demo", permissions: [:read, :eval, :ask])
{:ok, session} = ElixosHost.session("eval-demo")
# Use the normal OhMyJido prompt/event/steering APIs; Eval is already a native tool.
:ok = ElixosHost.stop("eval-demo")
:ok = Elixos.CodingEval.stop()
```

The session uses the requesting group leader's Elixos directory, real host
questions/authority and durable Jido storage. No provider account is selected or
credential read by packaging or smoke. A normal host may supply credentials and
model through its existing approved integration; this profile creates neither.
Do not start a second Elixos application from an external Elixir CLI, import
build-time config paths into the live VM, start Snakepit's generic installer,
change global environment/cwd, or load native libraries into the host to fake
the isolated Eval proof.

## Source authorities

- [QuickBEAM 0.11.3 source/artifacts](https://github.com/elixir-volt/quickbeam/releases/tag/v0.11.3),
  and the checksum manifest inside the exact canonical Hex dependency.
- [OXC 0.19.0](https://github.com/elixir-volt/oxc_ex/releases/tag/v0.19.0),
  its packaged loader target lists and all three source Cargo locks.
- [Snakepit 0.14.0](https://hex.pm/packages/snakepit/0.14.0), canonical
  `vendor/snakepit/UPSTREAM.json`, `priv/python` and its generated stubs.
- [Alpine v3.24 package indexes](https://dl-cdn.alpinelinux.org/alpine/v3.24/main/)
  for both target architectures; package/source URLs are resolved by native
  melange/apko rather than by an invented binary URL.
- Exact upstream wheel metadata: [grpcio](https://pypi.org/pypi/grpcio/1.84.0/json),
  [protobuf](https://pypi.org/pypi/protobuf/7.35.1/json),
  [numpy](https://pypi.org/pypi/numpy/2.5.4/json),
  [typing-extensions](https://pypi.org/pypi/typing-extensions/4.16.0/json).
