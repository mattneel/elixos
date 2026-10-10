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
  def start_shell(env) do
    # IEx needs its application (the broker) up; a release does not start it.
    with {:ok, _apps} <- Application.ensure_all_started(:iex) do
      :shell.start_interactive({__MODULE__, :start_iex, [env]})
    end
  end

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

  defp iex_options(_boot, image) when is_pid(image) do
    [env: Elixos.Boot.Recorder.traced_env(file: "iex", line: 1)]
  end

  defp iex_options(_boot, _no_image), do: []
end
