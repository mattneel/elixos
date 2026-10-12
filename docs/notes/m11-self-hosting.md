# Self-hosting (M11): historical implementation notes

> **Historical.** This survey records the start and middle of M11, not current
> blockers. M11 is delivered; M16 replaced the factory build with
> `melange/factory.yaml` and the toolchain package, and M26 added installed
> dependency resolution through `Elixos.Package.SCM`.
> See [ARCHITECTURE](../ARCHITECTURE.md) for the current system and
> [melange/apko notes](melange-apko.md) for the current build path.

From a read-only survey of the repo while starting M11. The acceptance test is
os/test/integration/m11_self_hosting_test.exs: install two fixture apps from
/priv/src on the box (one plain, one with a C NIF built by `cc`), then install,
save, power cycle and see the app's service come back.

## Already in place

- `Elixos.Package.Spec` and `Elixos.Package.Resolver` (M10) validate `elixos:`
  metadata and resolve one version per package.
- The fixtures are source-only and need no Hex download: sample_app is a plain
  Mix app whose config layers `config/elixos.exs` under `MIX_TARGET=elixos`,
  and sample_nif carries its own Mix compiler (a module in its mix.exs) that
  executes an executable named `cc` directly - no elixir_make, no make, no
  shell.
- `os/test/support/disk.ex` can write host files into the guest disk with
  debugfs (`Disk.put_tree!`), and the test seeds both fixtures that way.
- The factory's ERTS is musl and dynamic, so it can dlopen a NIF built against
  musl.

## Missing, and needed for the acceptance test

1. **A guest toolchain.** Nothing provisions zig, and `/priv/toolchain` (where
   `Elixos.Zig` promises to keep it) does not exist in the image, the disk or
   the fixtures. ADR-009 says the toolchain arrives as a package "fetched into
   /priv on first use, never in the factory"; the acceptance test has no
   network, so the fetch has to be a local source (a path repository on the
   disk, or a prebuilt toolchain the test seeds with `Disk.put_tree!`). This is
   the design decision M11 has to make and record.
2. **`Elixos.Zig`** (os/lib/zig.ex) is entirely stubbed: init/1, build/2, cc/2,
   version/0. Its moduledoc promises direct execution (no shell), the session
   directory from `Elixos.Session`, `ZIG_GLOBAL_CACHE_DIR=/priv/cache/zig`, and
   an offline `:path` option.
3. **`Elixos.Package.install/1`** (os/lib/elixos/package.ex) and `installed/0`
   are stubbed. The pipeline the moduledoc describes: build in a child ERTS
   exec'd directly (ADR-016), `MIX_TARGET=elixos`, satisfy `:elixos` from the
   running OS rather than building it, resolve with `Elixos.Package.Resolver`,
   load the result, start the `services`, and record the modules in the image.
4. **Mix inside the release.** `mix release` does not ship the `mix`
   application, and the child ERTS has to run Mix to build anything. Partly
   done: scripts/build-factory.sh copies Elixir's `mix` into the release's
   `lib/`, but the release's boot script was generated without it, so it is not
   on the code path the BEAM starts with - a child ERTS must add it (`-pa
   <factory>/lib/mix/ebin` or `Code.append_path/1`) before `Mix.CLI` is
   loadable. Verified in the guest: `Code.ensure_loaded?(Mix.CLI)` is false
   today, and `/factory/erts/usr/include/erl_nif.h` is true.
5. **`erl_nif.h`.** The sample NIF includes it; the factory does not install
   the ERTS headers.
6. **A CA bundle**, so Hex works when there *is* a network (the acceptance test
   does not need one).
7. **Generation-aware package state.** Saving bytecode is not enough for the
   power-cycle test: which apps are installed, their `elixos:` metadata and
   their services have to be restored too, and their services started under
   the system tree at boot. `Elixos.Image.Generation` currently carries only
   number, parent, modules, boot and created_at.

## Order that keeps each step testable

1. Build-side plumbing: Mix and the ERTS headers into the factory release, and
   prove a child ERTS can run `mix --version` inside the guest.
2. The toolchain decision (ADR) plus whatever it takes to make `/priv/toolchain`
   real offline; `Elixos.Zig` on top of it.
3. `Elixos.Package.install/1` for path installs, with the child-ERTS build.
4. Installed-app state in generations, service startup at boot, and the
   power-cycle test.
5. The CA bundle, which only matters for Hex (M14).

## Where the install stands (mid-M11)

`Elixos.Package.install/1` for a path is implemented: read the spec, build in
a child ERTS, load the ebin, start the services, journal the app (the image's
generations then boot every installed app's services through a
`start_service` MFA). Elixos.Zig is implemented.

Three blockers were found and fixed by running it:

1. `mix release` leaves the mix application out of the generated boot script,
   so `Mix.Project` was not even loadable. `Elixos.Application.start` appends
   the factory's `lib/mix/ebin` and starts `:mix` (whose project stack is a
   process, and `Mix.Project.get/0` calls it).
2. The BEAM ran `-mode embedded`, whose code server refuses to load anything
   from the code path. The shim now runs `-mode interactive` (PROTOCOL.md §3),
   which is also what the live image needs.
3. A child ERTS must be given `-boot_var RELEASE_LIB`, and `-eval` takes
   *Erlang*, so the child runs `'Elixir.Mix.CLI':main([<<"compile">>,
   <<"--no-deps-check">>])`. Reproduced on the host against the factory's own
   erlexec: it compiles a project successfully.

Open: inside the guest the install did not return within the test's 600s
timeout (the console showed nothing after the call). The host replica
succeeds, so the difference is environmental - the next step is a manual guest
run with a long wait and the child's output captured, not another blind
retest. The crash-dump work proved itself here too: each failed child wrote
`/priv/crash/gen0-attempt1.dump`.
