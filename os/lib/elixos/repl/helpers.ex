defmodule Elixos.REPL.Helpers do
  @moduledoc """
  The session-aware `cd/1`, `pwd/0` and `ls/0,1` a login IEx gets (ADR-020, M9).

  IEx's own helpers are built on `File.cd/1` and `File.cwd/0`, which would move
  the whole VM (ADR-016; verified on Elixir 1.20.4: `IEx.Helpers.cd/1` calls
  `File.cd/1`). The login IEx therefore imports this module instead, so these
  are what a prompt has:

      iex(1)> pwd()
      "/priv/home"
      iex(2)> cd("/tmp")
      "/tmp"
      iex(3)> ls()
      ["boot.state", "home", "journal.log", ...]

  `ls/0` lists the session's directory, `ls/1` a path inside it, and `cd/1`
  accepts anything `Elixos.Session.expand/1` understands.

  Every open Oh-My-Jido approval or question on the machine, including those of
  detached agents, is answered from any prompt (ADR-093):

      iex(4)> approvals()
      iex(5)> approve(1)    # or deny(1), or answer(2, "staging")
  """

  @doc "The session's working directory."
  @spec pwd() :: Path.t()
  def pwd, do: Elixos.Session.cwd()

  @doc "Changes the session's directory, like a shell's `cd`."
  @spec cd(Path.t()) :: Path.t() | {:error, term()}
  def cd(path) do
    case Elixos.Session.cd(path) do
      {:ok, dir} -> dir
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Lists the session's directory, or `path` inside it."
  @spec ls() :: [String.t()] | {:error, term()}
  def ls, do: ls(".")

  @spec ls(Path.t()) :: [String.t()] | {:error, term()}
  def ls(path), do: Elixos.Session.ls(path)

  @doc "Open Oh-My-Jido approvals and questions from every session, oldest first."
  @spec approvals() :: [Elixos.Approvals.Request.t()] | {:error, term()}
  def approvals, do: Elixos.Approvals.pending()

  @doc "Approves request `id` (see `approvals/0`)."
  @spec approve(pos_integer()) :: :ok | {:error, term()}
  def approve(id), do: Elixos.Approvals.approve(id)

  @doc "Denies request `id`; the waiting effect does not run."
  @spec deny(pos_integer()) :: :ok | {:error, term()}
  def deny(id), do: Elixos.Approvals.deny(id)

  @doc "Answers a clarification request with one of its options or text."
  @spec answer(pos_integer(), term()) :: :ok | {:error, term()}
  def answer(id, value), do: Elixos.Approvals.answer(id, value)
end
