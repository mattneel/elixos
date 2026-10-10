defmodule Elixos.Boot.Login do
  @moduledoc """
  The login REPL on the console (M4, ADR-012).

  `:shell.start_interactive/1` takes an MFA whose call starts a shell and
  returns its pid; `start_iex/1` here is that MFA. The same shape serves the
  SSH daemon's per-user shell (M12) and Ctrl-G's `s shell` (M9), which is what
  makes "REPLs are the login shells" true rather than three implementations.

  The VM runs with `-noshell` (the shim execs erlexec that way), so no shell
  exists until this asks user_drv for one.
  """

  use GenServer

  @doc "Supervisor child: starts the login REPL once the tree is up."
  def start_link({env, image}) do
    GenServer.start_link(__MODULE__, {env, image}, name: __MODULE__)
  end

  def start_link(env), do: start_link({env, nil})

  @impl true
  def init(env) do
    # After init/1 returns the supervisor considers this child started, so the
    # control channel is already alive when the first prompt appears.
    {:ok, env, {:continue, :start_shell}}
  end

  @impl true
  def handle_continue(:start_shell, env) do
    case start_shell(env) do
      :ok -> {:noreply, env}
      {:error, reason} -> {:stop, {:login_shell_failed, reason}, env}
    end
  end

  @doc "Starts the interactive shell, with the user's REPL as its shell."
  @spec start_shell(Elixos.Boot.Env.t() | :host) :: :ok | {:error, term()}
  def start_shell(_env) do
    # IEx needs its application (the broker) up; a release does not start it.
    with {:ok, _apps} <- Application.ensure_all_started(:iex),
         {:ok, mfa} <- login_repl() do
      :shell.start_interactive(mfa)
    end
  end

  @doc "The user's chosen REPL as an MFA (`/priv/user.exs`, ADR-013)."
  @spec login_repl() :: {:ok, {module(), atom(), list()}}
  def login_repl do
    # A user file that cannot be read or parsed is not a reason to have no
    # prompt: the default REPL is the fallback, and the file is the user's.
    repl =
      case Elixos.User.read(user_path()) do
        {:ok, %{repl: repl}} -> repl
        {:error, _reason} -> Elixos.REPL.default()
      end

    Elixos.REPL.mfa(repl)
  end

  @doc "Where the user's settings live (PROTOCOL.md §7)."
  def user_path, do: "/priv/user.exs"

  @doc """
  The shell MFA without arguments, for `Elixos.REPL.mfa/1`: the same session,
  with the boot environment and the image read from this VM.
  """
  @spec start_iex() :: pid()
  def start_iex, do: start_iex({Elixos.Boot.Env.current(), Process.whereis(Elixos.Image)})

  @doc """
  The shell MFA: starts an IEx session and returns its pid, as
  `:shell.start_interactive/1` requires. `IEx.Server.run/1` blocks for the
  whole session, so it runs in a process of its own.
  """
  @spec start_iex(Elixos.Boot.Env.t() | :host) :: pid()
  def start_iex({_env, image} = boot) do
    # The console's shell, and the pid a break lands on: `+Bc` (PROTOCOL.md §3)
    # makes user_drv exit the group with `interrupt`, and the group forwards it
    # to this pid as an exit signal. IEx.Server handles exactly that itself —
    # `** (EXIT) interrupted`, the evaluator killed, a fresh prompt, the same
    # input path — so the console spawns the session and stays out of it.
    spawn_link(fn -> IEx.Server.run(iex_options(boot, image)) end)
  end

  # What a prompt evaluates with: the recorder's tracer, so every module typed
  # at the prompt is journaled (M6), and the session-aware helpers, so a
  # prompt's `cd/1`, `pwd/0` and `ls/0,1` move the session and never the VM
  # (ADR-016, ADR-020). The helpers travel as `:dot_iex`, a file the evaluator
  # loads after its own import of IEx.Helpers and whose environment it keeps -
  # which also means they survive an interrupt, where the env does not.
  defp iex_options(_boot, _image) do
    [env: Elixos.Boot.Recorder.traced_env(file: "iex", line: 1), dot_iex: helpers_path()]
  end

  @doc "The file a login IEx loads for its session-aware helpers."
  def helpers_path, do: Application.app_dir(:elixos, "priv/iex_helpers.exs")
end
