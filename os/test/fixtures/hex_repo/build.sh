#!/usr/bin/env bash
# Rebuild this fixture's static Hex repository from the package sources.
#
#   os/test/fixtures/hex_repo/build.sh
#
# `packages/<project>/` holds the sources of every fixture package (hello_pkg,
# hello_dep, hello_app: the last two make install-by-name resolve a
# dependency closure). This script builds each with `mix hex.build`, collects
# the tarballs, and rebuilds the signed registry in `public/` with the
# fixture's throwaway key - the same steps the README describes, runnable.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

for project in packages/*/; do
  [ -f "$project/mix.exs" ] || continue
  name="$(basename "$project")"
  echo "fixture: building $name"
  ( cd "$project" && mix hex.build >/dev/null )
  cp "$project"/*.tar public/tarballs/
  rm -f "$project"/*.tar
done

echo "fixture: rebuilding the registry (elixos-test, fixture key)"
rm -rf public/names public/versions public/packages
mix hex.registry build public --name=elixos-test --private-key=private_key.pem >/dev/null

echo "fixture: $(ls public/tarballs/ | wc -l) package(s)"
ls public/tarballs/
