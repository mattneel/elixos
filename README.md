# Elixos

[![License: MIT](https://img.shields.io/github/license/mattneel/elixos)](LICENSE)
[![Elixir 1.20.4](https://img.shields.io/badge/Elixir-1.20.4-4B275F?logo=elixir&logoColor=white)](https://elixir-lang.org)
[![OTP 29.1.1](https://img.shields.io/badge/OTP-29.1.1-A90533?logo=erlang&logoColor=white)](https://www.erlang.org)
[![Linux 7.2.9](https://img.shields.io/badge/Linux-7.2.9-FCC624?logo=linux&logoColor=black)](kernel/VERSION)
[![Zig 0.18.0-dev.131](https://img.shields.io/badge/Zig-0.18.0--dev.131-F7A41D?logo=zig&logoColor=black)](.zig-version)

[![A module defined in IEx survives a power cycle](demos/readme-live-image.gif)](demos/m06-live-image.mp4)

[Watch the recording](demos/m06-live-image.mp4) · [All demos](demos/README.md)

**The Elixir operating system.** On a machine, an unmodified mainline Linux
kernel boots a tiny Zig PID 1 shim, which runs the BEAM and drops you at
`iex(1)>`. IEx is the machine's default shell; a POSIX shell exists for tooling.
Programs are packages, commands are functions, and the running system is a
live image you can save. Native OCI images run the same Elixos userland and
services headlessly, on the Linux kernel of the Docker daemon or the provider.

Elixos is for shipping living Elixir apps and for personal machines: USB
sticks, cyberdecks and SBCs. Machine images and native OCI packaging target
**x86_64, aarch64 and riscv64** (riscv64 since M28, for the K230 cyberdeck).
Foreign architectures are cross-built on the build host and boot-tested in
QEMU with a smoke set; the exercised runtime results below are x86_64 unless a
section says otherwise.

## Status

- **Delivered (M1–M19, M25–M29):** live generations and recovery, on-box Mix
  builds, SSH, UEFI boot, trusted Hex packages, Jido agents, package-built
  images, an unprivileged BEAM with sealed commits, PostgreSQL, persistent Oban
  jobs, a headless browser, Rust tooling, installed packages resolved as Mix
  dependencies, and an optional framebuffer GUI for Oh-My-Jido approvals,
  opened from IEx on x86_64 and ARM64. The [M27 recording](demos/m27-gui.mp4)
  shows approvals answered on the framebuffer with a real keyboard, then
  console handback. M28 boots riscv64 to `iex(1)>` on QEMU virt
  ([recording](demos/m28-riscv64.mp4)), and M29 joins an AtomVM peer to the
  cluster over a private link ([recording](demos/m29-atomvm-peer.mp4)).
- **Waiting for the board (M30–M33):** the [K230 cyberdeck track](docs/ROADMAP.md#m30-k230-bring-up-gate-needs-the-board)
  for the LilyGO T-Display K230 is built and green in CI. That covers the
  inter-core ring, AtomVM on the little core (tested in QEMU), the deck view
  and board drivers, and `make deck-image`. Its hardware checklists
  ([docs/hardware/t-display-k230.md](docs/hardware/t-display-k230.md)) still
  have to be run on a board.
- **Retired:** the M20 Ask question queue, by
  [ADR-093](docs/DECISIONS.md#adr-093-oh-my-jido-approvals-replace-the-ask-queue).
  Oh-My-Jido approvals are the only human-in-the-loop mechanism.
- **Withdrawn:** the OMP port and bundled coding-agent arc (M21–M24), by
  [ADR-083](docs/DECISIONS.md#adr-083-elixos-is-the-os-the-bundled-omp-port-is-withdrawn).
  Oh-My-Jido is a separate project, not an Elixos milestone.
- **Planned graphics variants:** AMD and NVIDIA images on the human's
  in-progress `live_gpui` stack (GPUI, LiveView and Rustler), by
  [ADR-072](docs/DECISIONS.md#adr-072-hardware-accelerated-live_gpui-ships-in-vendor-image-profiles).

See the [roadmap and acceptance criteria](docs/ROADMAP.md).

## Pick a target

| You want to | Target | Kernel owner | Main limit |
|---|---|---|---|
| Try Elixos on a laptop from a USB stick | [Live EFI](#live-efi-from-a-usb-stick-x86_64) (x86_64) | Elixos | All state is in RAM and is lost on reboot |
| Install on a machine with a data disk | [Persistent UEFI](#persistent-uefi-install) | Elixos | Physical-hardware checklist (M13) is not complete |
| Develop the OS itself | [QEMU](#qemu-development) | Elixos | Development VM only |
| Run Elixos in a container | [Native OCI on Docker](#native-oci-images-docker) | Docker daemon | No hardware control, no GUI |
| Deploy an app to Fly | [Fly](#fly-native-oci-deployment) | Fly | One Machine, one volume, no HA or backups |
| Boot a microVM | [Direct Firecracker](#direct-firecracker-x86_64) (x86_64) | Elixos | KVM only, RAM-backed, serial and loopback only |
| Ship your own Elixir app | [Native application SDK](#native-application-sdk) | Any of the above | Build output is a runtime OCI image |

`Elixos.runtime/0` returns `:machine` or `:container`. Normal and rescue
mode, and `MIX_TARGET=elixos`, are separate concepts. In a container,
`Elixos.reboot()` and `Elixos.poweroff()` stop the Elixos supervisor, not
the host kernel. The GUI is a machine feature; containers are headless.

### Build prerequisites

Every target starts from the pinned machine artifacts. Run these commands
from the repository root:

```sh
make check-tools                  # lists missing host tools
scripts/install-zig.sh            # the pinned Zig nightly
scripts/install-build-tools.sh    # pinned melange and apko
```

The image build stages the separate Oh-My-Jido library from a reviewed
source snapshot. Print its pin, review the checkout, then set the approved
value explicitly:

```sh
export ELIXOS_OH_MY_JIDO_SOURCE=/path/to/oh_my_jido
elixir scripts/stage-coding.exs pin "$ELIXOS_OH_MY_JIDO_SOURCE"
export ELIXOS_CODING_SHA256=<the reviewed hash>
make image                        # kernel, shim, initramfs, service image, disk
```

The build refuses a changed checkout under an old pin. Do not set the pin
with command substitution. `make images` builds x86_64, aarch64 and riscv64.

### Live EFI from a USB stick (x86_64)

```sh
make image
scripts/build-uefi-image.sh --live
mcopy -i build/esp-live.img ::/EFI/BOOT/BOOTX64.EFI build/elixos-x86_64-live.efi
```

Copy the `.efi` file as a new ordinary file onto an existing Ventoy USB.
No formatting, repartitioning or installer is necessary. The image is
unsigned, so Secure Boot must be off. If Windows uses BitLocker, get the
recovery key before you change firmware security settings.

Live boots the normal OS with PostgreSQL and the native toolchain. `/priv`
is in RAM, and Live never mounts physical storage. Use at least 4 GiB RAM.

**A kernel reboot discards files, database rows and generations saved with
`Elixos.save()`.**

### Persistent UEFI install

```sh
make image
scripts/build-uefi-image.sh --hardware    # build/esp-hardware.img, panel console
```

The ESP is a bare FAT image whose `EFI/BOOT/BOOTX64.EFI` is the kernel, with
the initramfs and command line built in. State lives on an ext4 data disk
([PROTOCOL §7](docs/PROTOCOL.md#7-the-persistent-disk)). Select that disk
with a firmware-level `elixos.data=/dev/<device>` argument. The default is
`/dev/vda`. The OVMF boot is tested (M13); the
[physical-hardware checklist](docs/ROADMAP.md#m13-real-hardware) is open.
[UEFI notes](docs/notes/uefi-boot.md) record the details.

### QEMU development

```sh
make qemu                       # boots build/disk.img; Ctrl-A X quits
make qemu ARGS="elixos.safe"    # rescue mode
```

`make qemu` boots the persistent `build/disk.img`, so state stays between
sessions. Tests and demos boot copies of it. [TESTING](docs/TESTING.md)
describes the test layers; [AGENTS.md](AGENTS.md) describes the milestone
loop.

### Native OCI images (Docker)

Build the two local base images from the pinned artifacts, then start an
interactive SDK container with a retained `/priv` volume:
```sh
scripts/build-image.sh x86_64    # skip if `make image` already built x86_64
scripts/build-docker-image.sh --arch x86_64              # elixos:sdk
scripts/build-docker-image.sh --runtime --arch x86_64    # elixos:runtime

docker volume create elixos-state
docker run --rm -it --name elixos-console \
  --read-only \
  --tmpfs /run:rw,nosuid,nodev,mode=0755 \
  --tmpfs /tmp:rw,nosuid,nodev,mode=1777 \
  --mount type=volume,source=elixos-state,target=/priv \
  --env ELIXOS_CONSOLE=1 \
  elixos:sdk
```

- The SDK image has the compiler SDK at `/toolchain`; the runtime image
  omits it. Both tags are local. Elixos publishes no registry image.
- The daemon, SDK image and runtime image must have the same architecture.
  No transparent emulation is used.
- No privileged mode, devices, host namespaces or custom kernel are
  necessary. Keep the root entrypoint user: the shim drops the BEAM to uid
  1000 and PostgreSQL to uid 70.
- Startup is headless by default. `ELIXOS_CONSOLE=1` gives IEx;
  `ELIXOS_SAFE=1` selects rescue mode.
- `Elixos.poweroff()` or `docker stop --timeout 45 elixos-console` exits 0.
  `Elixos.reboot()` exits 75. A restart policy must start it again.
- State survives only in the retained `/priv` volume.

[TESTING](docs/TESTING.md#native-oci-images-and-docker-proof) has the
artifact preparation details and the verified Docker results.

### Headless application deployment

This example runs an application image built with
[`mix elixos.image`](#native-application-sdk). The application must
implement its own listener on `0.0.0.0:4000` and its own `/health` endpoint.

```sh
docker volume create weather-station-state
docker run --detach --name weather-station \
  --read-only \
  --tmpfs /run:rw,nosuid,nodev,mode=0755 \
  --tmpfs /tmp:rw,nosuid,nodev,mode=1777 \
  --mount type=volume,source=weather-station-state,target=/priv \
  --publish 127.0.0.1:4000:4000 \
  --restart=on-failure --stop-timeout 45 \
  weather_station:local
```

- Publishing a port does not create a server or a health endpoint.
- `on-failure` restarts nonzero exits, including reboot exit 75, but not a
  clean exit 0.
- Supply secrets at deployment time, never in source, image or build inputs.
- A pristine volume gets the image seed once. Existing `boot.state` always
  wins, so a newer image does not upgrade a populated volume.
- Each start counts as a boot attempt until auto-commit promotes it after
  30 s of healthy uptime. If restarts come faster than that, the shim can
  fall back to the last good generation.
- A retained volume is not a backup and not high availability.

The [deployment guide](hex/README.md#deploying-the-runtime-image) has the
full rules for seeds, volumes and upgrades.

### Fly native OCI deployment

Fly runs the runtime image on its own kernel and init. The shim runs as the
child and subreaper of Fly's init. Do not supply a custom kernel or a nested
VMM. First build an [application image](#native-application-sdk) and push it
to a registry that you control. Then set `FLY_APP` to your existing app and
`FLY_IMAGE` to the pushed image reference:

```sh
fly volumes create elixos_data --app "$FLY_APP" --region iad --size 1
fly deploy --config docker/fly.toml --app "$FLY_APP" \
  --image "$FLY_IMAGE" --ha=false
```

[`docker/fly.toml`](docker/fly.toml) requests two shared CPUs, 2 GiB RAM, an
`elixos_data` volume at `/priv`, SIGTERM with 45 s grace and `on-failure`
restarts. It has no HTTP service: an HTTP application adds its own service
and checks.

A native Fly trial passed on 2026-10-22: provider kernel, seed on a fresh
volume, an app-owned HTTPS health endpoint, a runtime secret, and state kept
across a graceful SIGTERM restart. It was one Machine with one volume. It is
not proof of HA, backups, scaling or ARM64. See
[Fly application proof](docs/TESTING.md#fly-application-proof) and the
[deployment guide](hex/README.md#fly-native-oci-profile).

### Direct Firecracker (x86_64)

```sh
make image
scripts/build-uefi-image.sh --live      # writes build/initramfs-live.cpio.gz
scripts/install-firecracker.sh          # pinned Firecracker 1.17.0 under build/
scripts/run-firecracker.py              # 4 GiB RAM, two CPUs by default
```

The launcher boots the packaged `bzImage` and the Live initramfs. It needs
read/write `/dev/kvm`; there is no TCG fallback. No disk, TAP device,
management socket or GPU is attached, so all state is in RAM. PostgreSQL
works on guest loopback. `Elixos.reboot()` ends the VMM; run the launcher
again for a fresh boot. `Elixos.poweroff()` can halt the guest without
ending Firecracker; then press Ctrl-C. This is a development launcher, not
the production jailer.

### Native application SDK

The SDK is a host Mix archive. Host development uses ordinary Mix;
`MIX_TARGET=elixos` selects native source, dependencies and config.
Compilation runs inside the real Elixos userland:

```sh
cd hex/packages/elixos_sdk
MIX_ENV=prod MIX_TARGET=host mix archive.build
mix archive.install ./elixos_sdk-0.1.0.ez
cd /path/to/your/projects
mix elixos.new weather_station
cd weather_station
mix test
mix elixos.image --tag weather_station:local
```

`mix elixos.image` needs the two [native base images](#native-oci-images-docker).
It installs and saves the app in a native SDK container, cold-boots the
saved generation, and requires the default health gate before commit and
export. Only a successful export becomes a runtime image. An x86_64 app image
built this way passed the full gate on Docker
([results](docs/TESTING.md#native-oci-images-and-docker-proof)).

The [SDK guide](hex/README.md#native-application-sdk) covers `elixos: os()`
configuration, every `mix elixos.image` flag, repository trust and signed
offline mirrors. The generated counter project is not an HTTP server.

## Human approvals

Agents ask a person through [Oh-My-Jido](docs/PROTOCOL.md#10-oh-my-jido-approvals-adr-093)
sessions. `Elixos.Approvals` lists every open approval and question on the
machine, including the questions of background agents. Every login IEx or
SSH session can answer them:

```elixir
iex> approvals()
iex> approve(1)              # or deny(1)
iex> answer(2, "staging")    # a clarification
```

Questions of the OS's `Elixos.Coding` runtime expire closed after one hour by
default. `Elixos.GUI.start()` opens the optional framebuffer view. It returns
`{:error, :nothing_pending}` when nothing is open. Escape or F12 hands the
console back; Escape never denies.

## Prior art and friends

- [Autolith](https://github.com/lambda-symbolics/autolith): image generations,
  rollback and recovery images, and the introspective self-modifying agent
  direction. That agent work is still ahead of us.
- [Nerves](https://nerves-project.org/) and its
  [erlinit](https://github.com/nerves-project/erlinit): a minimal PID 1 handling
  boot, mounts and shutdown while the BEAM owns application supervision.
- [AtomVM](https://github.com/atomvm/AtomVM): a lightweight VM bringing Erlang
  and Elixir to microcontrollers and other constrained devices.
- **Smalltalk and Lisp machine images:** a live world and a changes log.
  Elixos rebuilds from code and data rather than saving the BEAM heap
  ([ADR-005](docs/DECISIONS.md)).

## Build and test

`make test` runs the unit tests. `make check M=27` builds the host image and
runs the unit tests through M27 plus that milestone's QEMU acceptance.
`make ci` is the full gate: unit tests, the QEMU suite and both image builds.
`make test-qemu-aarch64` runs the separate ARM64 smoke test. See
[TESTING](docs/TESTING.md).

## Docs

- [VISION](docs/VISION.md): what Elixos is and is not
- [ARCHITECTURE](docs/ARCHITECTURE.md): boot chain, shim, live image, REPLs, apps, toolchain
- [PROTOCOL](docs/PROTOCOL.md): every interface that is API (tests match it byte for byte)
- [DECISIONS](docs/DECISIONS.md): ADRs and open questions
- [ROADMAP](docs/ROADMAP.md): milestones and their acceptance tests
- [TESTING](docs/TESTING.md): test layers, gating, the QEMU harness and deployment evidence
- [SDK and Hex repository](hex/README.md): native apps, images and deployment
- [Notes](docs/notes/README.md): what was learned the hard way

## License

Elixos source is licensed under the [MIT License](LICENSE).
Third-party components retain their own licenses and notices.
