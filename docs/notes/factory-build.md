# Building the factory (generation 0)

`scripts/build-factory.sh` produces `build/rootfs`: the musl loader and the
shared libraries the ERTS needs, plus `/factory` (ERTS + OTP apps + Elixir +
the Elixos release). `scripts/build-initramfs.sh` folds it into `/initrd` under
`/factory` and `/lib`. Everything is cached under `build/toolchain`, so the
script is cheap to re-run; delete that directory to rebuild from source.

## The ERTS is built with a musl cross gcc, not zig cc

ADR-008 says zig cc builds ERTS. Two properties of `zig cc` make that
impossible for the *dynamic* musl target as of Zig 0.18.0-dev.131:

* **Zig's linker localizes libc's string and math symbols.** Linking musl's
  own objects with `zig cc -shared` leaves `memcpy`, `memset`, `memcmp`,
  `bcmp` and the libm entry points out of `.dynsym` (they stay local), while
  linking the very same objects with GNU ld exports them, as a canonical musl
  loader does (checked against Alpine's `ld-musl-x86_64.so.1`). A shared
  library linked against Zig's musl — say `libcrypto.so.3` — therefore has
  *dynamic* relocations for those symbols and still needs a loader that
  exports them.
* **Zig's bundled `libc.so` is not a usable dynamic loader.** It is built
  static-pie: it has a dynamic symbol table but no `_dlstart` entry, so a
  binary whose interpreter points at it faults (verified by running one).

For OTP, `zig cc` also mishandles OTP's own build: `erts/emulator` defines
`DEP_CC=$(CC)`, so OTP preprocesses C++ sources with the **C** driver, which
does not add libc++'s include paths, and the bootstrap (host) builds inherit
whatever `CPPFLAGS`/`LDFLAGS` are exported, so musl headers ended up in front
of glibc's.

So: **ERTS is built with the musl.cc `x86_64-linux-musl-cross` gcc**, and the
shim stays on zig (ADR-003), as does the initramfs. This is a deviation from
the letter of ADR-008 (one toolchain for everything) and is recorded here per
AGENTS.md's hard rules; the ADR's goal — a *dynamically* linked musl ERTS so
NIFs can `dlopen` — is met. Replacing the cross gcc with zig cc later is a
build-script change, not an image change.

## The loader we ship

`build/rootfs/lib/ld-musl-x86_64.so.1` is the cross toolchain's `libc.so`
(musl's loader *is* its libc). It exports the canonical symbol set, which the
ERTS, libstdc++ and OpenSSL all need at run time.

## Host pitfalls found the hard way

* **Do not export `LD_LIBRARY_PATH` globally when building the factory.**
  `libstdc++.so.6` and `libgcc_s.so.1` have the same sonames as the host's
  glibc versions: with the target directory in the path, the *host's* `mix`
  and `erl` pick up the musl libraries and die with `GLIBCXX_3.4.30 not
  found`. Scope it to the target build and to running target binaries.
* **`mix release` needs the `erts-<vsn>` directory** in `include_erts`, not the
  OTP root; it finds the apps next to it (`lib/`).
* ncurses hands `-stats` to the linker (for *its* loader); neither lld nor GNU
  ld accept it, so the Makefiles are sed'ed to drop it.
* **ERTS's `-root` must be given exactly once.** `erlexec` takes `$ROOTDIR`
  and `$BINDIR` from the environment and passes `-root`/`-bindir` itself;
  repeating them makes `init` exit with `no_or_multiple_root_variables`. The
  release's boot script then needs `-boot_var RELEASE_LIB <root>/lib`
  (`cannot expand $RELEASE_LIB in bootfile` otherwise).

## What the release contains

`include_erts: ELIXOS_ERTS` and `include_executables_for: []`: the shim execs
`erts/bin/erlexec` itself, so no release `bin/` scripts (sh) exist at all
(ADR-012). `factory/erts` and `factory/releases/current` are symlinks to the
versioned directories, because the shim must not guess version strings.
