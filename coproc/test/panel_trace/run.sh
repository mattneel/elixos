#!/bin/sh
# The panel port's host tests (M33, docs/notes/k230-panel.md):
#   1. the bring-up trace: coproc/src/panel_k230.c's panel_k230_open() and
#      LilyGO's U-Boot RM69A10 logo bring-up (the vendor files of
#      vendor.lock, fetched and checked by sha256) run against the same
#      register model (coproc/test/k230_mmio_mock.c); every register write,
#      read and delay is recorded, and our trace must be the vendor's with
#      exactly the documented differences of elixos.patch applied, in each
#      scenario of the model (nominal, dphy-timeout);
#   2. the port's unit tests (coproc/test/panel_k230_test.c), for the board
#      build and for the no-panel (QEMU virt) build.
#
#   run.sh <coproc-dir> <download-dir> <work-dir>
#
# melange/coproc-firmware.yaml runs it before the cross builds with its
# download cache (build/coproc-dl on the host); by hand, e.g.
#   sh coproc/test/panel_trace/run.sh coproc build/coproc-dl build/panel-trace
# Regenerating elixos.patch after a deliberate change: run it, then
#   diff -u <work>/golden-nominal.trace <work>/ours-nominal.trace
# and keep the header of elixos.patch up to date with what the hunks are.
set -eu

[ $# -eq 3 ] || { echo "usage: run.sh <coproc-dir> <download-dir> <work-dir>" >&2; exit 2; }
coproc="$(cd "$1" && pwd)"
dl="$2"
work="$3"
here="$coproc/test/panel_trace"
cc="${CC:-cc}"
cxx="${CXX:-c++}"
mkdir -p "$dl" "$work"

while read -r sha name url; do
  case "$sha" in '' | '#'*) continue ;; esac
  file="$dl/k230-panel-$name"
  if ! echo "$sha  $file" | sha256sum -c - 2>&1; then
    curl -fsSL -o "$file.part" "$url"
    mv "$file.part" "$file"
    echo "$sha  $file" | sha256sum -c -
  fi
done < "$here/vendor.lock"

vendor() { echo "$dl/k230-panel-$1"; }

# The vendor tree as st7701.c expects it (it includes "../k230_board_common.h").
golden="$work/golden-src"
rm -rf "$golden"
mkdir -p "$golden/logo"
for name in display_logo.c display_logo.h st7701.c vo_table.h sysctl.h platform.h; do
  cp "$(vendor "$name")" "$golden/logo/$name"
done
cp "$here/k230_board_common.h" "$golden/k230_board_common.h"
# k230_logo.c and k230_board_common.c are U-Boot command files; only these
# lines are compiled: the power domain, the framebuffer address, the
# RM69A10 parameters, k230_gpio().
sed -n '9,193p' "$(vendor k230_logo.c)" > "$golden/logo/k230_logo_power.inc"
sed -n '194,207p' "$(vendor k230_logo.c)" > "$golden/logo/k230_logo_fb.inc"
sed -n '317,334p' "$(vendor k230_logo.c)" > "$golden/logo/k230_logo_info.inc"
sed -n '358,411p' "$(vendor k230_board_common.c)" > "$golden/logo/k230_gpio.inc"

echo "panel trace: building the vendor bring-up against the register model"
vendor_flags="-std=gnu11 -O1 -g -DCONFIG_K230_BARE_DISP_LOGO_RM69A10 -include stdint.h -include stdbool.h"
includes="-I$golden/logo -I$here/include -I$coproc/src -I$coproc/test"
# shellcheck disable=SC2086
$cc $vendor_flags $includes -c -o "$work/display_logo.o" "$golden/logo/display_logo.c"
# shellcheck disable=SC2086
$cc $vendor_flags $includes -c -o "$work/st7701.o" "$golden/logo/st7701.c"
# (golden_main.c includes vendor lines: no -Werror.)
# shellcheck disable=SC2086
$cc -std=gnu11 -O1 -g $includes -DCONFIG_K230_BARE_DISP_LOGO_RM69A10 \
  -c -o "$work/golden_main.o" "$here/golden_main.c"
# shellcheck disable=SC2086
$cxx -std=gnu++17 -O1 -g $includes -c -o "$work/golden_board.o" "$here/golden_board.cc"
$cc -std=gnu11 -O1 -g -Wall -Wextra -Werror -I"$coproc/src" -I"$coproc/test" \
  -c -o "$work/k230_mmio_mock.o" "$coproc/test/k230_mmio_mock.c"
$cxx -o "$work/golden" "$work/golden_main.o" "$work/golden_board.o" "$work/display_logo.o" \
  "$work/st7701.o" "$work/k230_mmio_mock.o"

echo "panel trace: building the port and its unit tests"
for panel in 1 0; do
  $cc -std=gnu11 -O1 -g -Wall -Wextra -Werror -no-pie \
    -DCOPROC_PANEL_K230=$panel -DCOPROC_FB_ADDR=0x08100000 -DCOPROC_LOAD_ADDR=0x07000000 \
    -I"$coproc/src" -I"$coproc/test" -o "$work/panel_k230_test-$panel" \
    "$coproc/test/panel_k230_test.c" "$coproc/src/panel_k230.c" "$coproc/src/k230_io.c" \
    "$coproc/test/k230_mmio_mock.c"
done

for scenario in nominal dphy-timeout; do
  "$work/golden" "$scenario" "$work/golden-$scenario.trace"
  "$work/panel_k230_test-1" trace "$scenario" "$work/ours-$scenario.trace"
  rm -f "$work/expected-$scenario.trace"
  patch --fuzz=0 -o "$work/expected-$scenario.trace" "$work/golden-$scenario.trace" < "$here/elixos.patch"
  if cmp "$work/expected-$scenario.trace" "$work/ours-$scenario.trace"; then
    echo "panel trace ($scenario): ours = vendor's + elixos.patch:" \
      "$(wc -l < "$work/ours-$scenario.trace") events, vendor's $(wc -l < "$work/golden-$scenario.trace")"
  else
    echo "panel trace ($scenario): ours differs from vendor's + elixos.patch:" >&2
    diff -u "$work/expected-$scenario.trace" "$work/ours-$scenario.trace" >&2
    exit 1
  fi
done

"$work/panel_k230_test-1"
"$work/panel_k230_test-0"
