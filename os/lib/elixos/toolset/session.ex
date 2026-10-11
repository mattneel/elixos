defmodule Elixos.Toolset.Session do
  @moduledoc """
  Session-scoped tool access (M21, docs/ROADMAP.md, ADR-047).

  A tool may access its workspace and the calling session's directory, not
  VM-global state. The session directory builds on `Elixos.Session` (M9),
  whose directories are keyed by process-group leader rather than `File.cwd/0`.
  Paths escaping both roots, including traversal or symlink escapes, are
  refused. Tool subprocess cwd/environment changes remain local to the
  session; the main VM's cwd and environment never change.

  No per-tool reference fixtures exist yet; these boundaries are the future
  Elixos acceptance contract, not a claim of reference-validated OMP parity.
  """

  defstruct [:workspace, :session_dir]

  @type t :: %__MODULE__{workspace: Path.t(), session_dir: Path.t()}

  @doc """
  Creates a tool session with an absolute workspace and the calling M9 directory.

  `:workspace` is required. `:session_dir` defaults to `Elixos.Session.cwd/0`;
  an explicit root supports isolated, recorded fixture replay.
  """
  @spec new(keyword()) :: t()
  def new(_opts), do: Elixos.NotImplemented.raise!(21, "Elixos.Toolset.Session.new/1")
end
