#!/usr/bin/env bash
# The LilyGO T-Display K230 deck SD card (M33): build/k230/elixos-deck.img.
#
# The bring-up card's layout (scripts/k230-sd.sh) with:
#   p1  the little core's AtomVM firmware as coproc.bin (coproc-k230.bin, at
#       0x7000000) and its payload as coproc-payload.bin (at 0x7400000):
#       the coprocessor runtime, atomvmlib, the cookie, its node and address,
#       ELIXOS_COPROC_DRIVERS=k230: the board backends of all five drivers
#       (display, touch, LoRa, power, console; docs/notes/coproc-firmware.md)
#   env the deck environment (boards/t-display-k230/uboot-env-deck.txt over
#       the firmware's env.bin, scripts/k230-env.py): both files loaded before
#       boot_baremetal, and the deck's kernel command line - the framebuffer
#       and ring as UIO devices, the ring's link, the persistent data
#       partition (elixos.data=/dev/mmcblk0p2, not live) and the deck profile
#       (elixos.profile=deck, ADR-111)
#   p2  the data disk with /priv/coproc/config.exs and /priv/coproc/cookie,
#       so Elixos.Coproc dials the coprocessor from the first boot
#
# The cookie is random per build unless ELIXOS_DECK_COOKIE is set; it is on
# both partitions of the card, which is the trust boundary. The LoRa frequency
# is the board's SKU, in Hz: ELIXOS_DECK_LORA_FREQUENCY (default 915000000;
# 433, 868 and 923 MHz boards set theirs).
#
# Inputs: scripts/build-image.sh riscv64, scripts/build-k230-firmware.sh and
# scripts/build-coproc-firmware.sh (both run from here), and the os/ Mix
# project (the runtime is packed from its compiled code). Writes nothing
# outside build/k230/.
set -euo pipefail

K230_NAME=deck
# shellcheck source=scripts/k230-sd.sh
. "$(dirname "$0")/k230-sd.sh"
IMG="$OUT/elixos-deck.img"
COPROC_OUT="$BUILD/coproc"

COPROC_NODE=coproc@10.0.3.9
COPROC_ADDRESS=10.0.3.9/24
COPROC_PORT=4370
COPROC_DRIVERS=k230
LORA_FREQUENCY="${ELIXOS_DECK_LORA_FREQUENCY:-915000000}"
case "$LORA_FREQUENCY" in
  '' | *[!0-9]*) echo "deck: ELIXOS_DECK_LORA_FREQUENCY must be a frequency in Hz" >&2; exit 1 ;;
esac
PAYLOAD_OFFSET=$((4 * MIB))
PAYLOAD_MAX=$((2 * MIB))
BEAM_UID=1000
BEAM_GID=1000

command -v python3 >/dev/null || die "python3 is needed (mkpayload.py, k230-env.py)"
command -v debugfs >/dev/null || die "debugfs (e2fsprogs) is needed"

k230_require_image
k230_firmware
"$ROOT/scripts/build-coproc-firmware.sh"
for file in coproc-k230.bin atomvmlib.avm mkpayload.py; do
  [ -f "$COPROC_OUT/$file" ] || die "the coprocessor firmware build left no $COPROC_OUT/$file"
done
fits "coproc-k230.bin" 0 "$(size "$COPROC_OUT/coproc-k230.bin")" "$PAYLOAD_OFFSET"

mkdir -p "$OUT"
WORK="$(mktemp -d "$OUT/.work.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# The coprocessor runtime, packed by Elixos from its own compiled code
# (Elixos.Coproc.runtime/0), as the QEMU firmware test does.
(cd "$ROOT/os" && mix run --no-start -e "{:ok, avm} = Elixos.Coproc.runtime(); File.write!(\"$WORK/runtime.avm\", avm)")
[ -s "$WORK/runtime.avm" ] || die "no runtime.avm from Elixos.Coproc.runtime/0"

cookie="${ELIXOS_DECK_COOKIE:-$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')}"
printf '%s\n' "$cookie" > "$WORK/cookie"
seed="$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')"

mkdir -p "$WORK/boot"
cp "$COPROC_OUT/coproc-k230.bin" "$WORK/boot/coproc.bin"
python3 "$COPROC_OUT/mkpayload.py" -o "$WORK/boot/coproc-payload.bin" \
  --env "ELIXOS_COPROC_NODE=$COPROC_NODE" \
  --env "ELIXOS_COPROC_PORT=$COPROC_PORT" \
  --env "ELIXOS_COPROC_COOKIE_FILE=cookie" \
  --env "ELIXOS_COPROC_BUNDLE=bundle.avm" \
  --env "ELIXOS_COPROC_DRIVERS=$COPROC_DRIVERS" \
  --env "ELIXOS_COPROC_LORA_FREQUENCY=$LORA_FREQUENCY" \
  --env "ELIXOS_COPROC_ADDRESS=$COPROC_ADDRESS" \
  --env "ELIXOS_COPROC_SEED=$seed" \
  --avm "$WORK/runtime.avm" --avm "$COPROC_OUT/atomvmlib.avm" \
  --file "cookie=$WORK/cookie"
fits "coproc-payload.bin" 0 "$(size "$WORK/boot/coproc-payload.bin")" "$PAYLOAD_MAX"
k230_boot_partition "$WORK/boot" "$WORK/boot.img"

# The deck environment.
redundant=()
[ -n "${ENV_REDUNDANT:-}" ] && redundant=(--redundant)
echo "deck: U-Boot environment"
python3 "$ROOT/scripts/k230-env.py" "$FIRMWARE/env.bin" "$BOARD/uboot-env-deck.txt" "$WORK/env.bin" "${redundant[@]}"

# p2, with the link's configuration for Elixos.Coproc (owned by the BEAM).
k230_data_partition "$WORK/data.img"
printf '[node: :"%s", port: %d, listen_port: %d]\n' "$COPROC_NODE" "$COPROC_PORT" "$COPROC_PORT" > "$WORK/config.exs"
debugfs -w "$WORK/data.img" -f - <<EOF
mkdir /coproc
write $WORK/config.exs /coproc/config.exs
write $WORK/cookie /coproc/cookie
set_inode_field /coproc uid $BEAM_UID
set_inode_field /coproc gid $BEAM_GID
set_inode_field /coproc mode 040700
set_inode_field /coproc/config.exs uid $BEAM_UID
set_inode_field /coproc/config.exs gid $BEAM_GID
set_inode_field /coproc/config.exs mode 0100600
set_inode_field /coproc/cookie uid $BEAM_UID
set_inode_field /coproc/cookie gid $BEAM_GID
set_inode_field /coproc/cookie mode 0100600
EOF
debugfs -R 'ls -l /coproc' "$WORK/data.img"

k230_assemble "$IMG" "$WORK/boot.img" "$WORK/data.img" "$WORK/env.bin"
k230_report "$IMG" "$WORK/boot"
