# Booting through UEFI (M13)

What the EFI-stub path actually requires, verified against the pinned Linux
7.2.9 source and by booting under OVMF.

- **No bootloader.** The kernel's EFI stub is a valid `BOOTX64.EFI`: firmware
  runs it, the stub decompresses the kernel, and the initramfs is whatever
  `CONFIG_INITRAMFS_SOURCE` baked into `usr/initramfs_data.cpio.gz`. kbuild
  accepts a compressed `.cpio.gz` file directly, so the build is: configure,
  build `bzImage`, copy it to `EFI/BOOT/BOOTX64.EFI` on a FAT filesystem.
- **The command line.** x86 has `CONFIG_CMDLINE_BOOL` and
  `CONFIG_CMDLINE_OVERRIDE`, but *no* `CMDLINE_EXTEND`. Without OVERRIDE the
  built-in line is used only when the boot loader (here: the firmware's load
  options) passes nothing; with OVERRIDE it replaces whatever the firmware
  passes, which would lock an owner out of `elixos.data=...`. So the image is
  built without OVERRIDE: the built-in line is the default, and firmware
  arguments win when they exist.
- **The ESP itself.** A bare FAT32 filesystem on the whole image, no partition
  table: `truncate` + `mformat -F` + `mmd ::/EFI ::/EFI/BOOT` + `mcopy`. OVMF
  boots it from the removable-media path. Size it from the kernel's actual
  size (the embedded initramfs makes it ~52M) plus slack.
- **kbuild refuses `O=` from a tree with in-tree artifacts**, and the QEMU
  kernel's tree has them. The UEFI kernels therefore get a second extraction
  (`build/linux-uefi-<version>`); sharing it between the serial and the
  hardware variant means switching reconfigures and rebuilds, which is fine
  for something built once per machine.
- **Device order matters.** QEMU's UEFI invocation attaches the data disk
  first and the ESP second, so the data disk stays `/dev/vda` (the shim's
  default `elixos.data`) and the ESP is `/dev/vdb`, which the kernel never
  mounts - only the EFI stub reads it, through firmware.
- Under OVMF the boot takes seconds; the M13 acceptance test asserts
  `File.dir?("/sys/firmware/efi")` to prove the firmware path, which a
  `-kernel` boot would fail.

## Laptop trial: no persistent disk

After building a fresh x86_64 image with the selected ADR-084 canonical source
pin, build the separate trial profile:

```sh
JOBS=16 scripts/build-uefi-image.sh --laptop
mcopy -i build/esp-laptop.img ::/EFI/BOOT/BOOTX64.EFI build/elixos-laptop-no-ssd.efi
```

The EFI application contains the kernel and complete initramfs. Copy the
`.efi` file onto the existing Ventoy filesystem; do not flash it to a disk,
format anything, or change a partition table. Ventoy supports direct EFI
applications. Select the USB from the laptop's one-time **UEFI** boot menu,
then select this file. The kernel is unsigned: Secure Boot must be disabled
for this trial; the build does not enroll keys or change firmware settings.
If Windows uses BitLocker/device encryption, have its recovery key available
before changing Secure Boot; that firmware change can trigger a recovery
prompt on the next Windows boot.

The trial fixes its kernel command line to:

```text
console=tty0 fbcon=font:TER16x32 panic=-1 quiet elixos.safe=1 elixos.data=/dev/elixos-no-data elixos.data_wait=0
```

Unlike the general images above, it enables `CONFIG_CMDLINE_OVERRIDE=y`.
Firmware/Ventoy arguments cannot silently remove the safety settings or
select an SSD. `elixos.safe` alone is insufficient: the shim normally mounts
the selected data device even in rescue. The deliberately nonexistent data
device prevents that mount, and zero wait avoids a storage-discovery delay.
Boot enters RAM-backed factory rescue; no NVMe/SATA/virtio data disk is
selected, mounted or written. Changes made in this session disappear at
power-off. The no-data/rescue notice is intentional.

The prompt is the laptop's own framebuffer console with USB/PS2 keyboard
input, not a serial-only console. Confirm the firmware boot from IEx with
`File.dir?("/sys/firmware/efi")`, then exit with `Elixos.poweroff()`.
The disk-backed service image is absent in this mode, so Emerge's NIF may
report a missing service library; the text IEx prompt remains usable.

Factory build details: generated Expert `.expert` caches are excluded from
canonical source staging, just like `_build` and `deps`. The separately
compiled host adapter explicitly loads the OS compile configuration so
Emerge reuses its packaged native-library boundary instead of trying to
invoke Cargo in the factory recipe.

Verified 2026-10-15 under OVMF by booting the laptop ESP as USB mass storage
with an actual framebuffer console and USB keyboard: IEx evaluated
`1000 + 234`, EFI firmware was present, mode was `:rescue`, and `/priv` was
not mounted. Writable GPT NVMe/SATA images and a valid ext4 virtio image all
retained identical SHA256 hashes before/after boot. Only generated regular
image files were passed to QEMU, never host block devices.

The extracted EFI payload was copied as a new file to the existing Ventoy
exFAT volume, flushed and SHA256-verified. Both USB partition offsets/sizes
were unchanged. This is emulator and copy verification, not a claim of a
completed physical-laptop or full-milestone gate.
