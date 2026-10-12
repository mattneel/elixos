defmodule Elixos.ToolsetSessionTest do
  use ExUnit.Case, async: true

  @moduletag milestone: 21
  @moduletag :tmp_dir

  alias Elixos.Toolset.Session

  setup ctx do
    workspace = Path.join(ctx.tmp_dir, "workspace")
    session_dir = Path.join(ctx.tmp_dir, "session")
    File.mkdir_p!(workspace)
    File.mkdir_p!(session_dir)
    session = Session.new(workspace: workspace, session_dir: session_dir)
    {:ok, workspace: workspace, session_dir: session_dir, session: session}
  end

  test "a root-name prefix does not grant access to a sibling", ctx do
    sibling = ctx.workspace <> "-outside"
    File.mkdir_p!(sibling)
    path = Path.join(sibling, "secret.txt")
    File.write!(path, "outside both roots")

    assert Session.resolve(ctx.session, path) == {:error, :path_outside_session}

    assert Session.resolve(ctx.session, "../workspace-outside/secret.txt") ==
             {:error, :path_outside_session}
  end

  test "a missing write target cannot traverse a symlinked parent", ctx do
    outside = Path.join(ctx.tmp_dir, "outside")
    File.mkdir_p!(outside)
    File.ln_s!(outside, Path.join(ctx.workspace, "escape"))

    assert Session.resolve(ctx.session, "escape/new/draft.txt") ==
             {:error, :path_outside_session}

    refute File.exists?(Path.join(outside, "new"))
  end

  test "a symlink into the other authorized root resolves to that root", ctx do
    destination = Path.join(ctx.session_dir, "λ.txt")
    File.write!(destination, "allowed session content")
    File.ln_s!(ctx.session_dir, Path.join(ctx.workspace, "session-link"))

    assert {:ok, ^destination} = Session.resolve(ctx.session, "session-link/λ.txt")
    assert File.read!(destination) == "allowed session content"
  end

  test "a cyclic symlink refuses access without treating the target as a new file", ctx do
    File.ln_s!("second", Path.join(ctx.workspace, "first"))
    File.ln_s!("first", Path.join(ctx.workspace, "second"))

    assert Session.resolve(ctx.session, "first/new.txt") == {:error, :eloop}
  end
end
