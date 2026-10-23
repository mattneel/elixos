#!/bin/sh
# The board drivers' host tests (docs/notes/coproc-firmware.md, "Board
# drivers"):
#   1. the protocol traces: our drivers (coproc/src/lora_k230.c,
#      touch_k230.c, power_k230.c) and LilyGO's code for the same device
#      (vendor.lock, fetched and checked by sha256) run the same scenario
#      against the same device models (coproc/test/models/); the SX1262's
#      command stream, the GT9895's I2C transfers and the PMU's register
#      trace are recorded, and ours must be the vendor's with exactly the
#      documented differences of elixos-<device>.patch applied (none for
#      the PMU);
#   2. the drivers' unit tests (coproc/test/board_k230_test.c), for the
#      board build and for the no-devices (QEMU virt) build.
#
#   run.sh <coproc-dir> <download-dir> <work-dir>
#
# melange/coproc-firmware.yaml runs it before the cross builds with its
# download cache (build/coproc-dl on the host); by hand, e.g.
#   sh coproc/test/board_trace/run.sh coproc build/coproc-dl build/board-trace
# Regenerating a patch after a deliberate change: run it, then
#   diff -u <work>/golden-<device>.trace <work>/ours-<device>.trace
# and keep the patch's header up to date with what the hunks are.
set -eu

[ $# -eq 3 ] || { echo "usage: run.sh <coproc-dir> <download-dir> <work-dir>" >&2; exit 2; }
coproc="$(cd "$1" && pwd)"
dl="$2"
work="$3"
here="$coproc/test/board_trace"
cc="${CC:-cc}"
cxx="${CXX:-c++}"
mkdir -p "$dl" "$work"

vendor="$work/vendor"
rm -rf "$vendor"
while read -r sha name url; do
  case "$sha" in '' | '#'*) continue ;; esac
  file="$dl/k230-board-$(echo "$name" | tr / _)"
  if ! echo "$sha  $file" | sha256sum -c - 2>&1; then
    curl -fsSL -o "$file.part" "$url"
    mv "$file.part" "$file"
    echo "$sha  $file" | sha256sum -c -
  fi
  mkdir -p "$(dirname "$vendor/$name")"
  cp "$file" "$vendor/$name"
done < "$here/vendor.lock"
# The power-key driver's register code: the new file's lines 90-583 of the
# patch (its defines, state, register helpers, IRQ handler, probe-time set-up
# and power-off), without the patch's leading '+'.
sed -n '90,583p' "$vendor/0064-input-k230-pmu-pwrkey.patch" | sed 's/^+//' > "$work/pmu_pwrkey.inc"

strict="-std=gnu11 -O1 -g -Wall -Wextra -Werror"
models="$coproc/test/models"
includes="-I$coproc/src -I$coproc/test -I$models"
model_sources="$coproc/test/k230_mmio_mock.c $models/gpio_model.c $models/sx1262_model.c $models/dw_ssi_model.c
  $models/dw_i2c_model.c $models/gt9895_model.c $models/pmu_model.c"

echo "board trace: building the device models"
objects=""
for source in $model_sources; do
  object="$work/model-$(basename "$source" .c).o"
  # shellcheck disable=SC2086
  $cc $strict $includes -c -o "$object" "$source"
  objects="$objects $object"
done

echo "board trace: building LilyGO's code against the models"
lora_lib="$vendor/lora_lib"
radiolib=""
for source in Module.cpp Hal.cpp protocols/PhysicalLayer/PhysicalLayer.cpp modules/SX126x/SX126x.cpp \
  modules/SX126x/SX1262.cpp; do
  object="$work/radiolib-$(basename "$source" .cpp).o"
  $cxx -std=gnu++17 -O1 -g -I"$lora_lib" -c -o "$object" "$lora_lib/$source"
  radiolib="$radiolib $object"
done
# (golden_*.c include or call vendor code: no -Werror.)
# shellcheck disable=SC2086
$cxx -std=gnu++17 -O1 -g -Wall -I"$lora_lib" $includes -c -o "$work/golden_lora.o" "$here/golden_lora.cc"
# shellcheck disable=SC2086
$cxx -o "$work/golden_lora" "$work/golden_lora.o" $radiolib $objects
# shellcheck disable=SC2086
$cc -std=gnu11 -O1 -g -I"$here/include" -I"$vendor" $includes -o "$work/golden_touch" \
  "$here/golden_touch.c" $objects
# shellcheck disable=SC2086
$cc -std=gnu11 -O1 -g -I"$here/include" -I"$work" $includes -o "$work/golden_power" \
  "$here/golden_power.c" $objects

echo "board trace: building the drivers and their unit tests"
drivers="$coproc/src/k230_io.c $coproc/src/k230_i2c.c $coproc/src/k230_spi.c $coproc/src/lora_k230.c
  $coproc/src/touch_k230.c $coproc/src/power_k230.c $coproc/src/uart_k230.c"
for devices in 1 0; do
  # shellcheck disable=SC2086
  $cc $strict -DCOPROC_K230_DEVICES=$devices $includes -o "$work/board_k230_test-$devices" \
    "$coproc/test/board_k230_test.c" $drivers $objects
done

for device in lora touch power; do
  "$work/golden_$device" "$work/golden-$device.trace"
  "$work/board_k230_test-1" trace "$device" "$work/ours-$device.trace"
  rm -f "$work/expected-$device.trace"
  if [ -f "$here/elixos-$device.patch" ]; then
    patch --fuzz=0 -o "$work/expected-$device.trace" "$work/golden-$device.trace" < "$here/elixos-$device.patch"
    rule="vendor's + elixos-$device.patch"
  else
    cp "$work/golden-$device.trace" "$work/expected-$device.trace"
    rule="vendor's"
  fi
  if cmp "$work/expected-$device.trace" "$work/ours-$device.trace"; then
    echo "board trace ($device): ours = $rule: $(wc -l < "$work/ours-$device.trace") lines," \
      "vendor's $(wc -l < "$work/golden-$device.trace")"
  else
    echo "board trace ($device): ours differs from $rule:" >&2
    diff -u "$work/expected-$device.trace" "$work/ours-$device.trace" >&2
    exit 1
  fi
done

"$work/board_k230_test-1"
"$work/board_k230_test-0"
