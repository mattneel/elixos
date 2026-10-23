#!/usr/bin/env bash
# Shared native factory assembly. Invoked only inside a melange build workspace.
set -euo pipefail
: "${FACTORY_DEST:?}" "${FACTORY_ARCH:?}" "${FACTORY_VERSION:?}"
FACTORY_EVAL="${FACTORY_EVAL:-0}"
version="$(sed -n 's/^  @version "\(.*\)"$/\1/p' /home/build/os/mix.exs)"
[ "$version" = "$FACTORY_VERSION" ] || { echo 'factory: OS/package version mismatch' >&2; exit 1; }
export MIX_ENV=prod HEX_HOME=/tmp/hex MIX_HOME=/tmp/mix
export ELIXOS_GUI_PACKAGED=1 EMERGE_SKIA_BUILD=1
export ELIXOS_OH_MY_JIDO_SOURCE=/home/build/coding/oh_my_jido
export MIX_BUILD_PATH=/home/build/os/_build/prod
export TARGET_ARCH="$FACTORY_ARCH" TARGET_OS=linux TARGET_ABI=musl TARGET_VENDOR=unknown
mix local.hex 2.5.1 --force >/dev/null
cd /home/build/os
locked="$(sha256sum mix.lock | cut -d' ' -f1)"
lib=/usr/local/lib/erlang
erts="$(find "$lib" -maxdepth 1 -type d -name 'erts-*')"
[ -d "$erts" ] || { echo 'factory: expected one installed ERTS' >&2; exit 1; }
export ELIXOS_ERTS="$erts" ELIXOS_INCLUDE_ERTS=0
if [ "$FACTORY_EVAL" = 1 ]; then
  export CARGO_NET_GIT_FETCH_WITH_CLI=true
  export RUSTLER_TARGET="$FACTORY_ARCH-unknown-linux-musl"
  export RUSTFLAGS='-C target-feature=-crt-static'
  export OXC_EX_BUILD=1
  elixir /home/build/scripts/build-coding-eval.exs
else
  mix deps.get --check-locked
  [ "$(sha256sum mix.lock | cut -d' ' -f1)" = "$locked" ] || { echo 'factory: OS lock changed' >&2; exit 1; }
  mix release --overwrite --path /tmp/rel
  (
    cd /home/build/coding/oh_my_jido/examples/elixos
    export ELIXOS_FACTORY=1 ELIXOS_SOURCE=/home/build/os ELIXOS_FACTORY_DEPS=/home/build/os/deps
    mix deps.get --check-locked
    mix do loadconfig /home/build/os/config/config.exs, compile --warnings-as-errors
  )
fi
[ "$(sha256sum /home/build/os/mix.lock | cut -d' ' -f1)" = "$locked" ] || { echo 'factory: OS lock changed' >&2; exit 1; }
dest="$FACTORY_DEST/factory"
mkdir -p "$dest"
cp -a /tmp/rel/. "$dest/"
rm -rf "$dest/bin"
cp -aL "$MIX_BUILD_PATH/lib/elixos_host" "$dest/lib/elixos_host-0.1.0"
for emerge in "$dest"/lib/emerge-*; do
  [ -d "$emerge/priv" ] || { echo 'factory: Emerge priv missing' >&2; exit 1; }
  rm -rf "$emerge/priv/native"
  ln -s "/system/gui/$FACTORY_ARCH-unknown-linux-musl" "$emerge/priv/native"
  licenses="$emerge/priv/licenses"
  mkdir -p "$licenses"
  cp /home/build/os/deps/emerge/LICENSE /home/build/os/deps/emerge/NOTICE "$licenses/"
  cp -a /home/build/os/deps/emerge/licenses/. "$licenses/"
  for font in inter jetbrains-mono; do
    install -m 0644 "/home/build/os/deps/emerge/native/emerge_skia/src/fonts/$font/OFL.txt" "$licenses/$font-OFL.txt"
  done
done
for app in "$lib"/lib/*; do
  name="$(basename "$app")"
  [ -e "$dest/lib/$name" ] || ln -sfn "$app" "$dest/lib/$name"
done
ln -sfn "$erts" "$dest/$(basename "$erts")"
ln -sfn "$(basename "$erts")" "$dest/erts"
ln -sfn "$version" "$dest/releases/current"
cp -a /usr/local/lib/elixir/lib/mix /usr/local/lib/elixir/lib/ex_unit "$dest/lib/"
mkdir -p "$dest/source/os"
cp -a /home/build/os/mix.exs /home/build/os/mix.lock /home/build/os/lib /home/build/os/config /home/build/os/priv /home/build/os/test "$dest/source/os/"
cp -a /home/build/spec /home/build/MILESTONE "$dest/source/"
rm -f "$dest/source/os/test/fixtures/hex_repo/private_key.pem"
mkdir -p "$dest/coding" "$dest/source/oh_my_jido"
cp /home/build/coding/source.json "$dest/coding/source.json"
cp -a /home/build/coding/oh_my_jido/. "$dest/source/oh_my_jido/"
for source in /home/build/os/deps/* /home/build/coding/oh_my_jido/vendor/jido /home/build/coding/oh_my_jido/vendor/req_llm /home/build/coding/oh_my_jido/vendor/snakepit; do
  app="$(basename "$source")"
  for installed in "$dest/lib/$app"-*; do
    [ -d "$installed" ] || continue
    for notice in "$source"/LICENSE* "$source"/LICENCE* "$source"/NOTICE* "$source"/COPYING*; do
      [ -f "$notice" ] || continue
      mkdir -p "$installed/priv/licenses"
      install -m 0644 "$notice" "$installed/priv/licenses/$(basename "$notice")"
    done
  done
done
mkdir -p "$dest/coding/inputs"
cp /home/build/scripts/stage-coding.exs /home/build/scripts/factory-coding-receipt.exs /home/build/scripts/build-image.sh /home/build/scripts/package-factory.sh /home/build/melange/factory.yaml "$dest/coding/inputs/"
cp /home/build/.tool-versions "$dest/coding/inputs/tool-versions"
if [ "$FACTORY_EVAL" = 1 ]; then
  cp -a /home/build/scripts/coding-eval "$dest/coding/inputs/"
  cp /home/build/scripts/build-coding-eval.exs /home/build/scripts/coding-eval-native.py /home/build/melange/factory-eval.yaml /home/build/melange/coding-eval-python.yaml /home/build/coding/eval.lock "$dest/coding/inputs/"
  cp /home/build/coding/eval-build.json "$dest/coding/eval-build.json"
  # All native compiler inputs, including source-specific Cargo locks/checksums,
  # remain immutable and independently hashable beside the emitted libraries.
  mkdir -p "$dest/coding/native-sources"
  cp -a /home/build/os/deps/quickbeam /home/build/os/deps/oxc "$dest/coding/native-sources/"
  find "$dest/coding/native-sources" -type d \( -name target -o -name _build -o -name .git \) -prune -exec rm -rf {} +
  cp -a /home/build/coding/eval-artifacts "$dest/coding/native-artifacts"
  python3 /home/build/scripts/coding-eval-native.py "$FACTORY_DEST" "$FACTORY_ARCH" /factory/coding/native.json
fi
elixir /home/build/scripts/factory-coding-receipt.exs "$dest" "$FACTORY_EVAL"
mkdir -p "$dest/bin"
ln -sfn "$lib/bin/start_clean.boot" "$dest/bin/start.boot"
ln -sfn "$lib/bin/start_clean.boot" "$dest/bin/start_clean.boot"
ln -sfn "$lib/bin/no_dot_erlang.boot" "$dest/bin/no_dot_erlang.boot"
mkdir -p "$dest/hex/keys"
cp /home/build/hex/keys/elixos.pub "$dest/hex/keys/elixos.pub"
{
  printf '[\n  elixos: [\n    url: "https://mattneel.github.io/elixos",\n    key: """\n'
  cat /home/build/hex/keys/elixos.pub
  printf '"""\n  ]\n]\n'
} > "$dest/hex/repos.exs"
