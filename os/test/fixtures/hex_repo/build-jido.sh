#!/usr/bin/env bash
# Rebuild the fixture's prebuilt jido closure (M15) and the registry.
#
#   os/test/fixtures/hex_repo/build-jido.sh
#
# Needs the network once (mix deps.get) and the pinned zig: the closure is
# built on this host from the published packages, because building it on the
# box needs rebar3 and a rebar plugin that fetches from the network - the
# reason the fixture ships it built (docs/notes/jido.md).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${ELIXOS_JIDO_BUILD:-/tmp/elixos-jido-fixture}"
ZIG="$(find "$HOME/.cache/zig/p" -maxdepth 2 -name zig -type f 2>/dev/null |
  while read -r candidate; do
    if [ "$("$candidate" version 2>/dev/null)" = "$(cat "$HERE/../../../.zig-version")" ]; then
      dirname "$candidate"
      break
    fi
  done)"

rm -rf "$WORK"
mkdir -p "$WORK"
cd "$WORK"

cat > mix.exs <<'PROJECT'
defmodule JidoFixture.MixProject do
  use Mix.Project
  def project, do: [app: :jido_only, version: "0.1.0", elixir: "~> 1.20", deps: [{:jido, "~> 2.4"}]]
  def application, do: [extra_applications: []]
end
PROJECT

mix deps.get >/dev/null
mix deps.compile >/dev/null

# Native code that ships in a package (telemetry's NIF) has to be built for
# the guest's musl, not this host's glibc.
for src in "$WORK"/deps/*/c_src/*.c; do
  [ -f "$src" ] || continue
  app="$(basename "$(dirname "$(dirname "$src")")")"
  mkdir -p "$WORK/_build/dev/lib/$app/priv"
  "$ZIG/zig" cc -shared -fPIC -O2 -target x86_64-linux-musl \
    -o "$WORK/_build/dev/lib/$app/priv/$app.so" "$src"
  echo "jido fixture: built $app NIF for musl"
done

elixir "$HERE/jido_build.exs" "$WORK/_build/dev/lib" "$HERE/public/tarballs"

"$HERE/build.sh"
