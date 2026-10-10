# Build environment quirks (host-side)

## `LLVM` in the environment breaks the kernel build

`scripts/build-kernel.sh` failed with
`Makefile:454: *** Invalid value for LLVM, see Documentation/kbuild/llvm.rst`.

Cause: this host sources emsdk (through mise), which exports
`LLVM=/home/.../emsdk/6.0.9/upstream/bin`. kbuild reads `$LLVM` as "build with
clang" and accepts only an empty value, `1`, a `%/`-terminated prefix or a
`-%` suffix; a bare bin directory is none of those.

Fix: the script `unset LLVM` before configuring. We build with gcc
(`x86_64_defconfig`), so clang is not wanted anyway.

## flex and bison are required

`make check-tools` reports them; `apt install flex bison`. Without them
`make olddefconfig` dies deep inside kconfig.

## KVM

`/dev/kvm` exists here, so QEMU runs at full speed and
`ELIXOS_QEMU_SLOWDOWN` can stay at 1. On a host without nested
virtualization, raise it instead of raising test timeouts.
