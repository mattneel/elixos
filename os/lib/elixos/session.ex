defmodule Elixos.Session do
  @moduledoc """
  The working directory of a REPL session (ADR-020, M9).

  Every process on Elixos shares one VM, so the VM's working directory cannot
  be a shell's working directory (ADR-016). A session's directory is therefore
  kept here, keyed by the session's **process-group leader**: everything
  spawned from a REPL inherits its group leader, so a console job, an SSH
  channel and any task they start all resolve relative paths the same way.

      iex(1)> pwd()
      "/priv/home"
      iex(2)> cd("src")
      iex(3)> Elixos.Session.cwd()
      "/priv/home/src"

  The login REPLs carry session-aware `cd/1`, `pwd/0` and `ls/0,1`
  (`Elixos.REPL.Helpers` for IEx, `:user_default` for erl). Nothing here ever
  calls `File.cd/1` or `file:set_cwd/1`: the VM's directory stays `/`.
  """

  @default_dir "/priv/home"

  @table :elixos_sessions

  @doc "The calling session's working directory."
  @spec cwd() :: Path.t()
  def cwd, do: cwd_for(Process.group_leader())

  @doc """
  Changes the calling session's directory to `path`, expanded against the
  session's current directory. `{:error, :enoent}` when it does not exist.
  """
  @spec cd(Path.t()) :: {:ok, Path.t()} | {:error, term()}
  def cd(path) do
    target = expand(path)
    leader = Process.group_leader()

    case File.stat(target) do
      {:ok, %{type: :directory}} ->
        table()
        :ets.insert(@table, {leader, target})
        watch(leader)
        {:ok, target}

      {:ok, _file} ->
        {:error, :enotdir}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Lists `path` inside the calling session's directory, sorted."
  @spec ls(Path.t()) :: [String.t()] | {:error, term()}
  def ls(path) do
    case File.ls(expand(path)) do
      {:ok, names} -> Enum.sort(names)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Expands `path` against the calling session's directory."
  @spec expand(Path.t()) :: Path.t()
  def expand("~"), do: @default_dir
  def expand("~/" <> rest), do: Path.expand(Path.join(@default_dir, rest))
  def expand(path), do: Path.expand(path, cwd())

  @doc "Where a session starts before anything changes it."
  @spec default() :: Path.t()
  def default, do: @default_dir

  @doc "The directory of the session whose group leader is `pid` (tests, tooling)."
  @spec cwd_for(pid()) :: Path.t()
  def cwd_for(leader) do
    case :ets.lookup(table(), leader) do
      [{^leader, dir}] -> dir
      [] -> @default_dir
    end
  end

  # The key is a group leader, so entries are as short-lived as the sessions
  # they belong to and there are a handful of them on a machine. The table is
  # created on first use, by whichever process gets there first.
  defp table do
    if :ets.whereis(@table) == :undefined do
      ensure_table()
    end

    @table
  end

  # The table must outlive every session that uses it, and a session is a
  # process that comes and goes, so a process that stays owns it. That process
  # also watches the group leaders it holds entries for, so a session that ends
  # takes its directory with it instead of sitting in the table for the rest of
  # the boot.
  defp ensure_table do
    parent = self()

    spawn(fn ->
      created =
        try do
          :ets.new(@table, [:named_table, :public, :set])
          true
        rescue
          ArgumentError -> false
        end

      send(parent, :session_table)
      # A process that lost the race owns nothing and has nothing left to do.
      if created, do: keeper_loop()
    end)

    receive do
      :session_table -> :ok
    after
      1_000 -> :ok
    end
  end

  defp keeper_loop do
    receive do
      {:watch, leader} when is_pid(leader) ->
        Process.monitor(leader)
        keeper_loop()

      {:DOWN, _ref, :process, leader, _reason} ->
        :ets.delete(@table, leader)
        keeper_loop()
    end
  end

  # The table's owner is the keeper: it is the process that can act on a
  # session ending.
  defp watch(leader) do
    case :ets.info(@table, :owner) do
      :undefined -> :ok
      keeper -> send(keeper, {:watch, leader})
    end
  end
end
