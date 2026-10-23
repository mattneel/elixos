defmodule Mix.Tasks.Elixos.Image do
  use Mix.Task

  @shortdoc "Builds a native Elixos application OCI image using real saved-generation boots"
  @moduledoc """
  Builds an application image from the current project's source, without
  compiling it on the host or running a VM:

      mix elixos.image --tag my_app:latest
      mix elixos.image --tag my_app:latest --sdk-image elixos:sdk --runtime-image elixos:runtime
      mix elixos.image --tag my_app:latest \\
        --repo team --repo-url https://packages.example.org --repo-key /path/to/team.pub \\
        --install dependency_one --install dependency_two

  `--tag IMAGE` is required. The actual native base images default to
  `elixos:sdk` and `elixos:runtime`. Docker, Elixir, a POSIX shell, and Hex 2.5
  or later must be installed on the host; install this SDK as a Mix archive.
  Both images must already be built or pulled locally and must be Linux images
  matching the actual Docker daemon's architecture (amd64/x86_64 or
  arm64/aarch64). The task rejects architecture mismatches before packaging
  and explicitly selects that native platform for both boots and the final
  build; Docker Desktop/binfmt/QEMU cross-architecture execution is not used.

  Source packaging uses `elixos.package --unpack` in a fresh production Elixos
  Mix process. It never fetches dependencies or compiles on the host. The
  source is bound read-only outside `/priv`, copied into a writable native
  workspace, and installed by the real `Elixos.Package.install/1` API.
  Dependencies are installed only when explicitly named with repeatable
  `--install PACKAGE`; existing official repository trust is unchanged.

  A custom repository requires all of `--repo NAME`, `--repo-url URL` and
  `--repo-key PATH`. The key must be a PEM RSA public key, never a signing key.
  Remote URLs must be public HTTP(S) URLs without credentials, query or
  fragment. No URL implicitly supplies its own trust.

  For a signed offline repository, additionally pass `--repo-dir PUBLIC_TREE`
  and set `--repo-url /priv/hex/mirrors/NAME`. The tree must contain only the
  public static Hex resources `names`, `versions`, `public_key`, `packages/`
  and `tarballs/`, without links or unrelated files. These resources are copied
  into that persistent native mirror before the explicitly trusted repository
  is added. Never point this option at a directory containing signing keys.

  Two real native SDK containers share a fresh, invocation-owned named volume.
  The first installs and saves, then cleanly reboots (exit 75). The second
  restores exactly that generation, requires the default `Elixos.Health.run/0`
  checks, commits, exports an immutable deployment seed, and cleanly powers
  off (exit 0). Success requires those actual exits plus owned file receipts
  and the exported seed, not console markers. Failures never reach the final
  image build; native console diagnostics are included in the failure report.

  Both SDK boots use read-only container roots, `/run` and `/tmp` tmpfs mounts,
  ordinary container capabilities and no host ports, devices, privileged mode
  or host namespaces. Caller environment values and deployment secrets are
  not forwarded into the native containers.

  Only the exported seed is sent as the final Docker build context. The image
  derives directly from the selected runtime image, with a root-owned,
  read-only seed at `/usr/share/elixos/seed/`; it contains no source workspace,
  build tools, database files, host credentials, kernel or VM. A new `/priv`
  volume is initialized once by the existing native shim. Populated volumes
  always retain their existing generation and data, rather than being replaced
  by a later image's seed.

  This task cleans only its own named containers, volume and temporary files
  on success, failure or interruption. It does not publish images, alter other
  Docker resources, or overwrite any existing deployment volume.
  """

  @impl true
  def run(arguments) do
    {options, positional} =
      OptionParser.parse!(arguments,
        strict: [
          tag: :keep,
          sdk_image: :keep,
          runtime_image: :keep,
          repo: :keep,
          repo_url: :keep,
          repo_key: :keep,
          repo_dir: :keep,
          install: :keep
        ]
      )

    if positional != [] do
      Mix.raise(
        "Expected mix elixos.image --tag IMAGE [--sdk-image IMAGE] [--runtime-image IMAGE] [--repo NAME --repo-url URL --repo-key PATH] [--repo-dir PUBLIC_TREE] [--install PACKAGE ...]"
      )
    end

    ElixosSDK.Image.build(options)
  end
end
