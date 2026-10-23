# The official Elixos Hex repository

`elixos` is the repository every Elixos box trusts out of the box (ADR-019):
the factory image ships its public key, and `/priv/hex/repos.exs` names it, so
`Elixos.Package.install(:name)` works without anyone adding a repository first.

It is a **static Hex repository** served by **GitHub Pages**:

    https://mattneel.github.io/elixos

`.github/workflows/hex-repo.yml` builds and publishes it on every change under
`hex/`: package tarballs first (`build-packages.sh`), then the signed registry
(`build-repo.sh`), then the Pages deployment. Nothing else may write to it.

## Publishing a package

    hex/packages/<project>/     source Mix project with standard Hex metadata
    hex/prebuilt/*.tar          tarballs built elsewhere, copied as they are

`build-packages.sh` compiles only the dependency-free SDK build tool on the
host, then invokes `mix elixos.package` in fresh production/Elixos processes.
It does not compile target applications or fetch their dependencies. Unlike
plain `mix hex.build`, the SDK filters both `:only` and `:targets`, preserving
target-only requirements and excluding host/test-only ones. Prebuilt
tarballs must already contain the intended target's source requirements.

Commit the project (or drop the tarball in) and push to `master`: CI rebuilds
the registry, and the new version is installable at the next `mix deps.get` or
`Elixos.Package.install/1`.

Building locally, exactly as CI does:

    mix local.hex --force
    ./hex/build-packages.sh
    ./hex/build-repo.sh                 # uses build/keys/elixos-private.pem
    # a local mirror is now in build/hex-repo/public

## Native application SDK

Use OTP 29.1.1, Elixir 1.20.4 and Hex 2.5 or later. From the Elixos checkout:

```sh
cd hex/packages/elixos_sdk
MIX_ENV=prod MIX_TARGET=host mix archive.build
mix archive.install ./elixos_sdk-0.1.0.ez
```

This installs a host build tool, not an OS dependency or a host OS facade.
`mix elixos.new PATH` creates an ordinary Mix project; `--app`, `--module`
and `--boot auto|manual` select its names and boot policy.

### Project contract

`os()` is an ordinary private function returning the existing `:elixos`
keyword configuration, not a macro or separate project language:

```elixir
def project do
  [
    app: :weather_station,
    version: "0.1.0",
    deps: [{:elixos, "~> 0.1", targets: :elixos}],
    elixos: os()
  ]
end

defp os do
  [
    services: [WeatherStation.Supervisor],
    persist: ["state"],
    min_os: "~> 0.1",
    boot: :auto
  ]
end
```

`services` are supervised by the OS. `oban` may also declare the existing
queues/cron schema. Installation explicitly starts the declared services
and queues; `boot: :auto` restores them after a saved generation boots.
`:manual` retains configuration and directories without automatically
starting that app's services or queues on the next boot. A minimum OS or
system-wide dependency conflict is refused before compilation/replacement.

These declarations apply inside real Elixos userland, on a machine or in a
native OCI container. `MIX_TARGET=elixos` selects application source,
dependencies and target config; it does not select a kernel or deployment
provider. `os()` does not configure Docker/Fly volumes, ports, resources,
secrets, health checks or restart policies. Those remain deployment settings.
`Elixos.runtime/0` reports `:machine` or `:container` at runtime.

`Elixos.Package.data_dir(:weather_station)` returns
`/priv/data/weather_station`. Relative `persist` paths are created there
before services start; traversal and symlink components are refused.
Reinstall, upgrade and removal leave this application data alone.
This is filesystem durability: **Live RAM still disappears on kernel
reboot**, and container state requires a retained `/priv` volume. An image
seed does not include application data. These declarations are not a snapshot
exporter, disk formatter, automatic mount, backup or replication policy.

### Host development, native compilation

Keep portable source in `lib`; use `mix test` and `iex -S mix` normally.
For host dependency fetching explicitly select the host target:
`mix deps.get --only test --target host`; plain dependency fetching may
consider all targets.

Native API calls belong in code compiled/run inside Elixos, not on the
development host. For example, include `target/elixos` in `elixirc_paths`
only when
`Mix.target() == :elixos`, and include that directory in `package: [files: …]`.
Select target config with
`if config_target() == :elixos, do: import_config("elixos.exs")`.
Keep build-time config evaluable on the host: Mix loads it even when only
packaging source. Call runtime OS APIs inside native modules/services, not
host-evaluated config; do not create fake `Elixos` modules.

Package from a fresh process:

```sh
MIX_ENV=prod MIX_TARGET=elixos mix elixos.package
```

`--output PATH` (`-o`) and `--unpack` have standard Hex meanings.
Include `lib`, `config`, target-only directories, `mix.exs` and the license
in the package's files. No BEAMs, native binaries, dependency trees or OS
copy are built/bundled. Native contracts require a versioned, non-optional
Hex dependency on `:elixos`; portable libraries without an `:elixos`
contract need no OS dependency.

Publish the source tarballs with standard Hex tools or a static registry:

```sh
# Keep the private key outside the served directory.
mix hex.registry build public --name=team --private-key=/secure/team.pem
```

Place tarballs under `public/tarballs/` before building. Authenticate the
public key out of band, then explicitly trust the repository on the device:

```elixir
Elixos.Package.add_repo(:team, "/priv/hex/mirrors/team", key: verified_public_key_pem)
Elixos.Package.install(:weather_station)
Elixos.save()
```

The repository API also accepts HTTP(S) URLs when OTP `:inets` is available;
the verified guest SDK path uses a filesystem mirror. `file://` is not a
local-mirror URL scheme: pass the filesystem path. On the host,
`mix hex.repo add team URL --public-key=public/public_key` is the equivalent
explicit trust step; adding it there does not change the guest's trust.
Never package or transfer the signing private key.

The Elixos installer compiles in a clean child ERTS with prod/Elixos settings,
then loads exactly the declared app/version. The running OS satisfies
`:elixos`, never a fetched or alternate path/Git copy. Other installed
packages are shared dependencies, with one version per package system-wide.
The shared VM's cwd and OS environment never change.

`elixos_demo` is a native durable measurement journal with real
`Elixos.info/0` / `Elixos.Package.data_dir/1` observations and a separate
portable `elixos_demo_stats` dependency. Its host API explicitly reports
`:elixos_target_required` instead of fabricating OS facts. Its module docs
show the runnable commands and query API.

### Build a native application image

`mix elixos.image` turns the current project's source into an OCI runtime
image using the actual native Elixos installer and saved-generation workflow.
It is not a host release build, disk-image wrapper or VM launcher. Docker
CLI, a running Linux daemon, a POSIX shell, Elixir, Hex 2.5+ and the installed
SDK archive are required on the host.

First build both native base images from the Elixos checkout's existing
pinned target artifacts:

```sh
scripts/build-docker-image.sh --arch x86_64 elixos:sdk
scripts/build-docker-image.sh --runtime --arch x86_64 elixos:runtime
```

See [artifact preparation and prerequisites](../docs/TESTING.md#preparing-native-base-images)
if those artifacts are not present. The SDK has immutable `/toolchain`; the
runtime omits the compiler SDK. These commands create local tags; Elixos does
not publish a registry image for you. Use `aarch64` artifacts with a native
ARM64 daemon, not transparent emulation. The actual Linux daemon, SDK image
and runtime image must all match; the task checks them before packaging.
Cross-packaging a base image is not target runtime verification.

From your application project, with the archive installed:

```sh
mix elixos.image --tag weather_station:local
```

There is no need to compile the application or fetch its dependencies on the
host first. The task invokes the public source packager in a fresh
`MIX_ENV=prod MIX_TARGET=elixos` process. Build-time config must still be
host-evaluable as described above.

| Flag | Contract |
|---|---|
| `--tag IMAGE` | Required local output tag; the task does not push it. |
| `--sdk-image IMAGE` | Existing native SDK base, default `elixos:sdk`. |
| `--runtime-image IMAGE` | Existing native runtime base, default `elixos:runtime`. |
| `--repo NAME --repo-url URL --repo-key PATH` | All three together, or none. The key is an independently verified PEM RSA **public** key. Existing official trust is unchanged. |
| `--repo-dir PUBLIC_TREE` | Optional signed offline static Hex mirror; requires the complete repository triplet and URL `/priv/hex/mirrors/NAME`. |
| `--install PACKAGE` | Repeatable explicit dependency installs, performed in order before installing the current source project. |

Remote repository URLs must be public HTTP(S), without credentials, query or
fragment. A URL never supplies its own trust, and a repository trusted on the
host does not automatically become trusted inside Elixos. For example, with
your verified public key and actual required package names:

```sh
mix elixos.image --tag weather_station:local \
  --repo team --repo-url https://packages.example.org \
  --repo-key /path/to/verified-team-public.pem \
  --install dependency_one --install dependency_two
```

For an offline mirror, pass only its public tree:

```sh
mix elixos.image --tag weather_station:local \
  --repo team --repo-url /priv/hex/mirrors/team \
  --repo-key /path/to/verified-team-public.pem \
  --repo-dir /path/to/public \
  --install dependency_one
```

`PUBLIC_TREE` must contain exactly `names`, `versions`, `public_key`,
`packages/` and `tarballs/`, with ordinary public resource files, no links,
nested directories or unrelated files. The task copies these resources to
the named native mirror before adding its explicit trust. Never pass a
signing key or a private working directory. `file://` is not the offline
repository scheme; the durable native path above is required.

The build has four substantive stages:

1. Package source externally and bind it read-only outside `/priv`. A native
   SDK container copies it into its writable workspace, adds only the
   explicitly trusted repository and requested dependency installs, then
   calls the real `Elixos.Package.install/1`.
2. Save a positive generation on a fresh, invocation-owned named volume and
   cleanly reboot, requiring exit 75.
3. Start a second native SDK container on that same volume, restore exactly
   the saved generation, require the existing default `Elixos.Health.run/0`,
   commit it, export the immutable seed, and power off with exit 0.
4. Build directly from the selected runtime base, using **only the exported
   seed** as the final Docker context. The seed is root-owned and read-only
   at `/usr/share/elixos/seed/`.

Both SDK boots use read-only roots, `/run` and `/tmp` tmpfs mounts, ordinary
container capabilities and no host ports, devices, privileged mode or host
namespaces. Deployment secrets and caller environment values are not
forwarded. Success requires the actual exits, owned receipts and complete
seed, not console text or liveness. A health failure prevents final image
creation; there is no weaker image-build health mode. The task cleans only
its own containers, volume and temporary material, including on failure or
interruption.

**Verified scope:** an x86_64 application image built by this task passed the
default health gate, commit and export, then ran on Docker and on Fly. The
[Docker results](../docs/TESTING.md#verified-docker-results-x86_64) and the
[Fly trial](../docs/TESTING.md#fly-application-proof) record what was
checked. ARM64 application images are not runtime-verified.

### Seed contents and retained state

The immutable seed contains the committed generation/store/journal metadata,
canonical installed package code/resources and explicitly approved public
repository configuration/trust/resources needed for ordinary restore. It
excludes application data, PostgreSQL files, SSH identities/authorized keys,
agent state/history, caches, crash/evidence files, source build workspaces and
the compiler SDK. It is not a saved BEAM heap or a database snapshot.

All build inputs must be public: do not put secrets in source, static config,
package resources or the public repository. The exporter rejects recognized
private filenames and PEM private-key material, but is not a universal secret
scanner for arbitrary application bytes. Developers remain responsible for
secrets compiled into code/config/resources. Supply deployment credentials
through runtime configuration, not the image build.

At first launch the shim initializes `/priv` only if no `boot.state` exists
and the volume is pristine; empty initial `home`, `postgres` and `lost+found`
directories are allowed. It publishes `boot.state` last, after copying the
trusted seed. An existing `boot.state`, even one needing recovery, is never
overwritten. A non-pristine volume without that marker, unsafe links or an
interrupted initialization fails closed rather than being erased.

**A newer image is not an implicit application upgrade on a populated
volume.** Existing installed generations and data take precedence over its
seed. Use the explicit package install/save/generation workflow for upgrades,
with a matching SDK-capable environment when compilation is required; the
runtime image has no compiler SDK. Recreating a container without retaining
its `/priv` volume starts fresh and loses prior runtime data. Volume retention
alone does not provide backups, replication or high availability.

### Deploying the runtime image

Normal OCI startup is headless (`ELIXOS_CONSOLE=0`). Use the
[interactive Docker recipe](../README.md#native-oci-images-docker) with
`ELIXOS_CONSOLE=1` for IEx; `ELIXOS_SAFE=1` is the rescue switch. Keep the
image's root `/init` entrypoint: it starts the BEAM as 1000:1000 and
PostgreSQL as 70:70. No custom kernel, passed host devices, privileged mode or
host namespaces are required. Host hardware/storage controls and framebuffer
GUI are unsupported in this boundary.

For a headless Docker application, retain a named `/priv` volume and the
read-only root plus `/run` and `/tmp` tmpfs mounts shown in the
[runtime recipe](../README.md#headless-application-deployment). Size the
container explicitly for the app and database. The application must implement
HTTP itself, bind `0.0.0.0`, select its port, and expose a meaningful health
endpoint before you publish that port or configure HTTP checks. The generated
counter project supplies none of those HTTP features. OS build health and
HTTP readiness are different gates.

SIGTERM requests orderly BEAM/service shutdown; clean poweroff/stop exits 0.
`Elixos.reboot()` exits 75 instead of rebooting the hosting kernel. Select a
restart policy deliberately: Docker `--restart=on-failure` restarts nonzero
exits, including 75, but not clean 0. Without a restart policy, reboot leaves
the container stopped. Provide enough stop grace for the actual workload.

#### Fly native OCI profile

[`docker/fly.toml`](../docker/fly.toml) is a headless native runtime profile,
not a custom-kernel or nested-VM launcher. Fly owns its kernel and init;
the shim runs as the child and subreaper of Fly's init and supervises only its
own descendants. A single-Machine trial of this path
[passed on 2026-10-22](../docs/TESTING.md#fly-application-proof).

The checked-in profile has no fixed app name or image. It requests region
`iad`, two shared CPUs and 2 GiB RAM, sends SIGTERM with a 45-second stop
timeout, sets `ELIXOS_CONSOLE=0`, mounts the named `elixos_data` Fly Volume at
`/priv`, and uses `on-failure` with 10 restart retries. These are requests and
policy, not measured application capacity or an HA guarantee. Exit 75 is a
nonzero restart request; clean 0 is not a failure.

Build the app image successfully first, then explicitly tag/push it to your
own registry using your normal authenticated workflow. The image task never
publishes it. With `FLY_APP` set to your existing app and `FLY_IMAGE` to that
pushed native runtime reference, run from the Elixos checkout:

```sh
fly volumes create elixos_data --app "$FLY_APP" --region iad --size 1
fly deploy --config docker/fly.toml --app "$FLY_APP" \
  --image "$FLY_IMAGE" --ha=false
```

The 1 GiB volume size is an example request; choose capacity for your real
data. Create the volume only for a new deployment; retain and reuse an
existing deployment's volume. Each stateful Machine needs its own volume;
`--ha=false` makes this an explicit single-Machine deployment, not HA.
Confirm that the provider Machine architecture matches the image. Use
short-lived app-scoped deployment/registry credentials, and set application
secrets through Fly Secrets at runtime, never image build arguments.

The profile intentionally has **no HTTP service or health-check section**.
For an HTTP app, add an `[http_service]` for its actual `0.0.0.0` listener and
port, plus application-owned checks. The verified trial added
`internal_port = 8080` and a `GET /health` check served by the app. For a
background app, do not invent an HTTP endpoint. Fly does not apply Docker's
read-only and tmpfs flags.

Each start counts as a boot attempt until auto-commit commits after 30 s of
healthy uptime. Repeated restarts inside that window can make the shim fall
back to `last_good`. The verified trial covers one Machine and one volume. It
does not cover HA, backups, volume snapshots, scaling or ARM64; see
[the limits](../docs/TESTING.md#fly-application-proof).

## The signing key

`hex/keys/elixos.pub` is the repository's public key (**RSA PUBLIC KEY**, PEM,
the format Hex serves as `public_key`), committed on purpose: the factory ships
this exact file, and `build-repo.sh` refuses to publish a registry signed by
anything else, because every Elixos box would refuse it.

The private half is **not** in this repository. It lives in

  * the GitHub Actions secret `ELIXOS_HEX_PRIVATE_KEY` (CI signs with it), and
  * whoever holds the backup of it, off the machine.

Losing it means the repository can never be updated again for the machines that
shipped with this public key: they would refuse the new registry. Keep a backup.

    # verify a repository's key by fingerprint (sha256 of the DER):
    openssl rsa -pubin -in hex/keys/elixos.pub -outform DER | sha256sum
    # 43164f77e5381b27a2673c022107250dcf15c49c61bdf66eac0a8c46c0191922

## One-time setup on GitHub

1. **Settings → Pages → Source: GitHub Actions.**
2. **Settings → Secrets and variables → Actions → New repository secret:**
   `ELIXOS_HEX_PRIVATE_KEY`, the contents of the private key file.
3. Push a change under `hex/` (or run the workflow manually) and check the
   deployment URL serves `names`, `versions` and `public_key`.
