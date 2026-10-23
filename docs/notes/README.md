# Notes

What was learned the hard way (cross-building OTP, QEMU quirks, Zig master churn),
one file per topic. Notes preserve investigation history; the main architecture,
testing guide and roadmap describe the current system.

## Build and runtime notes

- [melange and apko](melange-apko.md): current package/cross-build path, caches,
  and the historical build failures that led to it.
- [Build environment](build-environment.md): host environment pitfalls.
- [QEMU harness](qemu-harness.md): console and prompt handling.
- [Console interrupts](console-interrupt.md): OTP's cooked-console behavior.
- [Zig master APIs](zig-master-apis.md): pinned-compiler API changes.
- [Jido](jido.md): agent integration and persistence.
- [SSH](m12-ssh.md): M12 integration notes.
- [UEFI boot](uefi-boot.md): the EFI-stub hardware path.
- [Native OCI](native-oci.md): container userland, read-only seed transfer and
  real native tool tests.
- [Optional Eval profile](coding-eval.md): the ADR-092 native Eval factory
  operations and evidence procedure.
- [Emerge / M27](emerge.md): renderer artifacts, Alpine packaging traps and
  the API shape of the framebuffer GUI.

## Hardware tracks

- [LilyGO T-Display K230](k230.md): the M30 bring-up gate's output file for
  the K230 track (M28–M33). Not yet surveyed.

## Historical and unfinished work

- [Factory build before M16](factory-build.md): the replaced hand-built pipeline.
- [M11 self-hosting](m11-self-hosting.md): an implementation-time survey, not
  a list of current blockers.
