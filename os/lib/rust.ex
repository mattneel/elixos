defmodule Rust do
  @moduledoc """
  The toolchain package's Rust API (ADR-066, M25): `cargo` and `rustc` as the
  build tools a Rustler NIF needs.

  Programs are packages and commands are functions (ADR-019): Rust is not a CLI
  to shell out to, it is this module. The Rust the box runs is its own
  architecture's, from the distribution, installed beside Zig in the toolchain
  directory (`/priv/toolchain/rust`) - `apk add --root`, so its libraries
  travel with it. Its linker is the toolchain's own `cc`, the Zig bridge
  (ADR-009): on the box there is no system `cc`, and both are musl, so the pair
  agrees.

      iex> Rust.init()
      :ok
      iex> Rust.cargo(["build", "--release"])
      {:ok, %{status: 0, output: "..."}}

  `cargo/2` runs `cargo` with the given arguments; `rustc/2` runs `rustc`.
  """

  @doc """
  Makes Rust available to this session (`CARGO_HOME=/priv/cache/cargo`).

  Options:

    * `:path` - use a toolchain already unpacked at this directory instead of
      the installed one (an offline mirror, or a test).

  Installing once is enough for every session: the toolchain lives in
  `/priv/toolchain/`, not in a session.
  """
  @spec init(keyword()) :: :ok | {:error, term()}
  def init(opts \\ []) do
    path = Keyword.get(opts, :path, root())

    if Keyword.has_key?(opts, :path), do: Application.put_env(:elixos, :toolchain_dir, path)

    cond do
      File.regular?(binary(path, "cargo")) and File.regular?(binary(path, "rustc")) ->
        # One cache for the whole machine, like the toolchain itself: a build
        # in any session reuses what another already compiled.
        File.mkdir_p(cargo_home())
        :ok

      Keyword.has_key?(opts, :path) ->
        {:error, {:no_rust, path}}

      true ->
        # A package would un-pack here (M14), exactly as Zig's does.
        {:error, {:not_installed, path}}
    end
  end

  @doc "Runs `cargo` with `args`, in the calling session's directory."
  @spec cargo([String.t()], keyword()) :: {:ok, map()} | {:error, term()}
  def cargo(args, opts \\ []), do: run("cargo", args, opts, linker: true)

  @doc "Runs `rustc` with `args`, in the calling session's directory."
  @spec rustc([String.t()], keyword()) :: {:ok, map()} | {:error, term()}
  def rustc(args, opts \\ []), do: run("rustc", args, opts, linker: false)

  @doc "The installed Rust version, or `{:error, :not_installed}`."
  @spec version() :: {:ok, String.t()} | {:error, :not_installed}
  def version do
    case rustc(["--version"], []) do
      {:ok, %{status: 0, output: output}} ->
        {:ok, output |> String.split() |> Enum.at(1, String.trim(output))}

      _other ->
        {:error, :not_installed}
    end
  end

  @doc "The target triple this machine builds for, as rustc reports it."
  @spec target() :: {:ok, String.t()} | {:error, term()}
  def target do
    case rustc(["-vV"], []) do
      {:ok, %{status: 0, output: output}} ->
        case Regex.run(~r/^host: (.+)$/m, output) do
          [_, host] -> {:ok, String.trim(host)}
          _other -> {:error, :unknown_target}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Exec'd directly - never through a shell (ADR-012) - with the working
  # directory of the *session* that asked (ADR-020), so a build lands where the
  # prompt is and the VM's own directory never moves (ADR-016). The linker is
  # named for the target in cargo's own environment-variable form, so a build
  # works without depending on a config file being found.
  defp run(name, args, _opts, run_opts) do
    path = binary(root(), name)

    unless File.regular?(path) do
      throw({:error, {:not_installed, root()}})
    end

    home = cargo_home()
    File.mkdir_p(home)

    env =
      if Keyword.get(run_opts, :linker, false), do: cargo_env(home), else: base_env(home)

    {output, status} =
      System.cmd(path, args,
        cd: session_dir(),
        env: env,
        stderr_to_stdout: true
      )

    {:ok, %{status: status, output: output}}
  catch
    {:error, reason} -> {:error, reason}
  end

  # Enough for rustc to run and to link: the toolchain's own `cc` (the Zig
  # bridge, ADR-009) is on PATH, and named as CC, because on the box there is
  # no system compiler to fall back to.
  defp base_env(home) do
    [
      {"CARGO_HOME", home},
      # The toolchain's own compiler, so a cargo that runs a NIF's build script
      # never looks for a system one.
      {"RUSTC", binary(root(), "rustc")},
      {"CC", cc()},
      {"PATH", "#{root()}:#{Path.dirname(binary(root(), "cargo"))}:#{System.get_env("PATH", "")}"}
    ]
  end

  # Cargo gets the linker named for the target as well, in cargo's own
  # environment-variable form, so a build works without depending on a config
  # file being found. Reading the target runs rustc with the base environment,
  # which is what keeps this from asking itself the same question forever.
  defp cargo_env(home) do
    case target() do
      {:ok, triple} ->
        var = "CARGO_TARGET_#{triple |> String.upcase() |> String.replace("-", "_")}_LINKER"
        [{var, cc()} | base_env(home)]

      {:error, _reason} ->
        base_env(home)
    end
  end

  # The Zig bridge (ADR-009) is the C compiler the toolchain already has.
  defp cc, do: Application.get_env(:elixos, :toolchain_cc, Path.join(root(), "cc"))

  # The session's directory, which is where a build lands (ADR-020). On a host
  # that directory does not exist - there is no /priv there - so the VM's own
  # is the honest stand-in; nothing here ever *changes* it (ADR-016).
  defp session_dir do
    dir = Elixos.Session.cwd()
    if File.dir?(dir), do: dir, else: File.cwd!()
  end

  defp root, do: Application.get_env(:elixos, :toolchain_dir, "/priv/toolchain")

  # PROTOCOL.md §7: the cache lives with the rest of the machine's state, so a
  # build in any session reuses what another already compiled.
  defp cargo_home, do: Application.get_env(:elixos, :cargo_home, "/priv/cache/cargo")

  # Rust arrives from the distribution, so it sits in a prefix of its own under
  # the toolchain directory: rust/usr/bin/. A package payload (ADR-019) is laid
  # out the same way, so bin/ is the other candidate.
  defp binary(path, name) do
    candidates = [
      Path.join([path, "rust", "usr", "bin", name]),
      Path.join([path, "rust", "bin", name]),
      Path.join([path, "bin", name])
    ]

    case Enum.find(candidates, &File.regular?/1) do
      nil -> Path.join([path, "rust", "usr", "bin", name])
      found -> found
    end
  end
end
