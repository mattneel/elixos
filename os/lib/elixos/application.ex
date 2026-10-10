defmodule Elixos.Application do
  @moduledoc """
  The OS application.

  On the dev host (unit tests) `Elixos.Boot.Env.current/0` returns `{:ok, :host}`
  and nothing is started. Under the shim (M4 onward) this is where the system
  comes up, in order:

    1. `Elixos.Shim.Control` on the inherited control fd (heartbeats start).
    2. The generation's modules and boot spec (`Elixos.Image.restore/2`, M6).
    3. `Elixos.Boot.AutoCommit` in normal mode (M5).
    4. The login REPL on the console via `:shell.start_interactive/1` (M4, M9).

  A failure in steps 1-3 must exit the VM with a non-zero status so the shim
  counts the attempt and falls back (ADR-007). Never swallow it.
  """
  use Application

  # The image lives on the persistent disk, and answers to its module name so
  # the prompt can save and list generations without a handle.
  defp open_image do
    root = Application.get_env(:elixos, :priv_dir, "/priv")

    case Elixos.Image.open(root) do
      {:ok, image} ->
        Process.register(image, Elixos.Image)
        {:ok, image}

      {:error, reason} ->
        {:error, {:image_unavailable, reason}}
    end
  end

  # M11: the box builds Mix projects, and `mix release` leaves the mix
  # application out of the generated boot script. Its ebin is in the factory,
  # so the path is put right before anything can need Mix - the package
  # installer, and the elixos: reader that runs before it.
  defp os_priv, do: Application.get_env(:elixos, :priv_dir, "/priv")
  defp factory, do: Application.get_env(:elixos, :factory_dir, "/factory")

  # The stock OTP applications the factory carries beside the release (mnesia,
  # ssl, inets: what an installed package may need) are not on the release's
  # code path on their own: put them there, before anything can load.
  defp add_factory_path do
    for dir <- Path.wildcard(Path.join([factory(), "lib", "*", "ebin"])),
        do: Code.append_path(dir)

    :ok
  end

  defp add_mix_to_path do
    factory = Application.get_env(:elixos, :factory_dir, "/factory")
    path = Path.join([factory, "lib", "mix", "ebin"])

    if File.dir?(path) do
      Code.append_path(path)
      # Mix keeps its project stack in a process of its own application, and
      # Mix.Project.get/0 is a call to it.
      Application.ensure_all_started(:mix)
    end
  end

  @impl true
  def start(_type, _args) do
    add_factory_path()
    add_mix_to_path()

    # The factory's Hex trust - the official repository's key and its entry -
    # is where a machine starts (PROTOCOL.md §8); after that /priv/hex/ is the
    # owner's. Never a reason not to boot.
    _ = Elixos.Package.Repo.ensure_seeded()

    # Installed apps' code lives on the disk; put it back before anything
    # (the restore, the services) can try to load a module.
    for dir <- Path.wildcard(Path.join(os_priv(), "apps/*/ebin")), do: Code.append_path(dir)

    case Elixos.Boot.Env.current() do
      # On the dev host (unit tests) there is no shim and nothing to start.
      {:ok, :host} ->
        Supervisor.start_link([], strategy: :one_for_one, name: Elixos.Supervisor)

      {:ok, env} ->
        # Before anything can load a generation: the base stays the base.
        Elixos.Boot.Base.stick()

        with {:ok, image} <- open_image() do
          children = [
            # Services from installed apps' elixos: keys live here, under the
            # system's tree; the restore below starts the ones the image knows,
            # so this has to come first (M11).
            {DynamicSupervisor, name: Elixos.Package.Services, strategy: :one_for_one},
            # The control channel first: heartbeats start before anything can
            # hang, and the shim's boot grace is running until the first one.
            {Elixos.Shim.Control,
             sink: {Elixos.Shim.Sink.Fd, env.ctl_fd},
             heartbeat_ms: Application.get_env(:elixos, :heartbeat_ms, 1_000)},
            # The generation the shim launched, loaded before anything can use
            # it; a failure here stops the tree on purpose (ADR-007).
            {Elixos.Boot.Restore, {image, env}},
            {Elixos.Boot.Recorder, image},
            # Agents: modules the image keeps, started under their own
            # supervisor and restored with what they remembered (M15).
            {DynamicSupervisor, name: Elixos.Agents.Supervisor, strategy: :one_for_one},
            {Elixos.Agents, image},
            # Key-only SSH into the user's REPL (M12). Not boot-critical: with
            # no network, or in rescue, it logs and steps aside (the prompt
            # still comes up).
            {Elixos.SSH, []},
            {Elixos.Boot.Login, {env, image}},
            # Commits the generation once it has been healthy for a while; in
            # rescue mode the child is skipped (:ignore), so a rescue boot never
            # makes itself last_good (ADR-007).
            {Elixos.Boot.AutoCommit, env: env}
          ]

          Supervisor.start_link(children, strategy: :one_for_one, name: Elixos.Supervisor)
        end

      {:error, {kind, name}} ->
        # A partial launch contract means the boot is broken: returning an
        # error makes the VM exit non-zero, so the shim counts the attempt and
        # falls back (ADR-007, PROTOCOL.md §3). Never swallow it.
        {:error, {:launch_contract, kind, name}}
    end
  end
end
