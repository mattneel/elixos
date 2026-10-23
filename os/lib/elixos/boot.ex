defmodule Elixos.Boot do
  @moduledoc """
  Facts about the running boot, from `Elixos.Boot.Env` (M4).

      iex> Elixos.Boot.info()
      %{arch: "x86_64", attempt: 1, generation: 0, mode: :normal, version: "0.1.0"}

  On the dev host there is no shim; `info/0` then returns `%{mode: :host, ...}`.
  The QEMU tests read this from the console, so keep the keys stable. `arch` is
  the target ERTS was built for, short form (`"x86_64"`, `"aarch64"`): since M16
  Elixos builds both, and the aarch64 smoke set asks the box what it is.
  """

  @spec info() :: %{
          arch: String.t(),
          generation: non_neg_integer() | nil,
          mode: :normal | :rescue | :host,
          attempt: non_neg_integer() | nil,
          version: String.t()
        }
  def info do
    base =
      case Elixos.Boot.Env.current() do
        {:ok, :host} ->
          %{generation: nil, mode: :host, attempt: nil, version: version()}

        {:ok, env} ->
          %{generation: env.generation, mode: env.mode, attempt: env.attempt, version: version()}

        {:error, {kind, name}} ->
          # The shim sets all four variables or none (PROTOCOL.md §3); a partial
          # contract means the boot is broken, so say so loudly.
          raise "broken launch contract: #{kind} #{name} (PROTOCOL.md §3)"
      end

    Map.put(base, :arch, arch())
  end

  @doc """
  Execution boundary: `:machine` owns its kernel, `:container` shares the
  hosting kernel, and `:host` is development without a shim launch.

  This is independent of normal/rescue mode. Container generations and
  services are real, but kernel boot and host hardware are not container APIs.
  """
  @spec runtime() :: :machine | :container | :host
  def runtime do
    case Elixos.Boot.Env.runtime() do
      {:ok, runtime} -> runtime
      {:error, {kind, name}} -> raise "broken launch contract: #{kind} #{name} (PROTOCOL.md §3)"
    end
  end

  @doc """
  The target this VM was built for, short form: `"x86_64"`, `"aarch64"`.

  ERTS knows its own target triple (`aarch64-unknown-linux-musl`, say); the
  part before the first dash is what a human calls the architecture (M16).
  """
  @spec arch() :: String.t()
  def arch do
    :erlang.system_info(:system_architecture)
    |> to_string()
    |> String.split("-", parts: 2)
    |> hd()
  end

  @doc "The version of the running OS, the :elixos application's."
  @spec version() :: String.t()
  def version do
    case Application.spec(:elixos, :vsn) do
      nil -> "unknown"
      vsn -> to_string(vsn)
    end
  end
end
