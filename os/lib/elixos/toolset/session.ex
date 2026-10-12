defmodule Elixos.Toolset.Session do
  @moduledoc """
  Session-scoped tool access (M21, docs/ROADMAP.md, ADR-047).

  A tool may access its workspace and the calling session's directory, not
  VM-global state. The session directory builds on `Elixos.Session` (M9),
  whose directories are keyed by process-group leader rather than `File.cwd/0`.
  Paths escaping both roots, including traversal or symlink escapes, are
  refused. Tool subprocess cwd/environment changes remain local to the
  session; the main VM's cwd and environment never change.

  These roots are Elixos's isolation policy. OMP output/error parity is checked
  independently by the recorded reference corpus.
  """

  defstruct [:workspace, :session_dir, :session_file, :id, :owner]

  @type t :: %__MODULE__{
          workspace: Path.t(),
          session_dir: Path.t(),
          session_file: Path.t() | nil,
          id: reference(),
          owner: pid()
        }

  @doc """
  Creates a tool session with an absolute workspace and the calling M9 directory.

  `:workspace` is required. `:session_dir` defaults to `Elixos.Session.cwd/0`;
  an explicit root supports isolated, recorded fixture replay. The creating
  process owns the cached peer context; its exit releases that context.
  `:session_file` identifies an optional session journal inside the allowed
  roots; the calling lifecycle owns its persistence.
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    directory = opts |> Keyword.get_lazy(:session_dir, &Elixos.Session.cwd/0) |> root!()
    workspace = opts |> Keyword.fetch!(:workspace) |> Path.expand(directory) |> root!()

    session = %__MODULE__{
      workspace: workspace,
      session_dir: directory,
      id: make_ref(),
      owner: self()
    }

    case Keyword.get(opts, :session_file) do
      nil ->
        session

      path ->
        case resolve(session, path) do
          {:ok, path} -> %{session | session_file: path}
          {:error, reason} -> raise ArgumentError, "invalid session journal: #{inspect(reason)}"
        end
    end
  end

  @doc """
  Resolves a local path against the workspace, rejecting escapes from both roots.

  Every existing component is checked for symlinks, including the parent of a
  not-yet-existing write target. The returned path is the canonical path that
  the effect handler must use, not the unchecked input.
  """
  @spec resolve(t(), Path.t()) :: {:ok, Path.t()} | {:error, term()}
  def resolve(%__MODULE__{} = session, path) when is_binary(path) do
    with {:ok, resolved} <- real_path(Path.expand(path, session.workspace)) do
      if within?(resolved, session.workspace) or within?(resolved, session.session_dir),
        do: {:ok, resolved},
        else: {:error, :path_outside_session}
    end
  end

  defp root!(path) do
    case real_path(Path.expand(path)) do
      {:ok, resolved} ->
        resolved

      {:error, reason} ->
        raise ArgumentError, "invalid tool session root #{inspect(path)}: #{inspect(reason)}"
    end
  end

  defp within?(path, root),
    do: path == root or root == "/" or String.starts_with?(path, root <> "/")

  defp real_path(path, remaining_links \\ 40) do
    [root | components] = Path.split(path)
    walk(root, components, remaining_links)
  end

  defp walk(resolved, [], _remaining_links), do: {:ok, resolved}

  defp walk(resolved, [component | rest], remaining_links) do
    candidate = Path.join(resolved, component)

    case File.lstat(candidate) do
      {:ok, %File.Stat{type: :symlink}} when remaining_links > 0 ->
        with {:ok, target} <- File.read_link(candidate) do
          target = Path.expand(target, resolved)
          real_path(Path.join([target | rest]), remaining_links - 1)
        end

      {:ok, %File.Stat{type: :symlink}} ->
        {:error, :eloop}

      {:ok, _stat} ->
        walk(candidate, rest, remaining_links)

      {:error, :enoent} ->
        {:ok, Path.join([candidate | rest])}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
