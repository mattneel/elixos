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
