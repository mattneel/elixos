defmodule Elixos.Boot.Env do
  @moduledoc """
  The environment contract the shim sets when it execs ERTS (docs/PROTOCOL.md §3).

  | variable            | value                                      |
  |---------------------|--------------------------------------------|
  | `ELIXOS_GENERATION` | generation being booted (0 = factory)      |
  | `ELIXOS_MODE`       | `normal` or `rescue`                       |
  | `ELIXOS_ATTEMPT`    | this launch's attempt count (boot.state)   |
  | `ELIXOS_CTL_FD`     | fd number of the control pipe's write end  |

  Numbers are canonical decimal u32 (PROTOCOL.md §1).

  `parse/1` rules, in order:

    1. none of the four variables present: `{:ok, :host}` (dev host, unit tests)
    2. some present, some absent: `{:error, {:missing, name}}`, first absent in table order
    3. any malformed value: `{:error, {:invalid, name}}`, first malformed in table order
    4. otherwise `{:ok, %Elixos.Boot.Env{}}`; other variables are ignored
  """

  defstruct [:generation, :mode, :attempt, :ctl_fd]

  @type t :: %__MODULE__{
          generation: non_neg_integer(),
          mode: :normal | :rescue,
          attempt: non_neg_integer(),
          ctl_fd: non_neg_integer()
        }

  # Table order is the contract: the first name reported is the first one here.
  @names ["ELIXOS_GENERATION", "ELIXOS_MODE", "ELIXOS_ATTEMPT", "ELIXOS_CTL_FD"]

  @spec parse(%{optional(String.t()) => String.t()}) ::
          {:ok, t() | :host} | {:error, {:missing | :invalid, String.t()}}
  def parse(env) when is_map(env) do
    present = Enum.filter(@names, &Map.has_key?(env, &1))

    cond do
      # Rule 1: no ELIXOS_* at all means we are not running under the shim.
      present == [] ->
        {:ok, :host}

      # Rule 2: absence is decided for every name before any value is looked at.
      (missing = @names -- present) != [] ->
        {:error, {:missing, hd(missing)}}

      # Rule 3: the first malformed value, in table order.
      true ->
        parsed(env)
    end
  end

  defp parsed(env) do
    with {:ok, generation} <- number(env, "ELIXOS_GENERATION"),
         {:ok, mode} <- mode(env["ELIXOS_MODE"]),
         {:ok, attempt} <- number(env, "ELIXOS_ATTEMPT"),
         {:ok, ctl_fd} <- number(env, "ELIXOS_CTL_FD") do
      {:ok, %__MODULE__{generation: generation, mode: mode, attempt: attempt, ctl_fd: ctl_fd}}
    end
  end

  defp number(env, name) do
    case Elixos.Decimal.parse_u32(env[name]) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:invalid, name}}
    end
  end

  defp mode("normal"), do: {:ok, :normal}
  defp mode("rescue"), do: {:ok, :rescue}
  defp mode(_other), do: {:error, {:invalid, "ELIXOS_MODE"}}

  @doc "Parses the running VM's environment."
  @spec current() :: {:ok, t() | :host} | {:error, {:missing | :invalid, String.t()}}
  def current, do: parse(System.get_env())
end
