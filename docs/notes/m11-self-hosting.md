# Self-hosting (M11): what exists, what is missing

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
