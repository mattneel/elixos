#!/bin/sh
# Builds AtomVM's library archive (atomvmlib.avm: estdlib, eavmlib,
# avm_network, ...) from a patched AtomVM tree, as melange/atomvm.yaml does
# for the Unix build. The coprocessor firmware needs its own: the bare-metal
# patches (melange/atomvm-baremetal/) change estdlib's dist controller.
#
#   build-atomvmlib.sh <atomvm-src> <build-dir> <rebar3> <atomvm_packbeam.tar>
#
# Needs erlang28, elixir, cmake, gperf and a host C toolchain with the Mbed
# TLS and zlib headers (AtomVM's top-level configure checks them). The
# downloads are verified by the caller. Output: <build-dir>/libs/atomvmlib.avm
set -eu
src=$1
build=$2
rebar3=$3
packbeam_tar=$4

tools="$build/tools-bin"
mkdir -p "$tools" "$build/packbeam"
install -m0755 "$rebar3" "$tools/rebar3"
tar -xOf "$packbeam_tar" contents.tar.gz | tar -xzf - -C "$build/packbeam"
PATH="$tools:$PATH"
export PATH
# Only the libraries are built; Alpine's MbedTLS CMake package names files
# the -dev package lacks, so AtomVM's own lookup is used (as atomvm.yaml does).
cmake -S "$src" -B "$build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DAVM_DISABLE_JIT=ON \
    -DCMAKE_DISABLE_FIND_PACKAGE_MbedTLS=ON
# AtomVM links its packbeam checkout as _checkouts/packbeam, which rebar3 does
# not match to the atomvm_packbeam dependency; link it under the app's name
# and keep rebar3 offline (docs/notes/atomvm.md).
mkdir -p "$build/tools/packbeam/_checkouts"
ln -sfn "$build/packbeam" "$build/tools/packbeam/_checkouts/atomvm_packbeam"
REBAR_OFFLINE=1 HEX_OFFLINE=1 cmake --build "$build" --target atomvmlib
ls -l "$build/libs/atomvmlib.avm"
