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

  @spec parse(%{optional(String.t()) => String.t()}) ::
          {:ok, t() | :host} | {:error, {:missing | :invalid, String.t()}}
  def parse(env) when is_map(env) do
    Elixos.NotImplemented.raise!(2, "Elixos.Boot.Env.parse/1")
  end

  @doc "Parses the running VM's environment."
  @spec current() :: {:ok, t() | :host} | {:error, {:missing | :invalid, String.t()}}
  def current, do: parse(System.get_env())
end
