defmodule Elixos.ApprovalsTest do
  @moduledoc """
  Oh-My-Jido approvals are the only human-in-the-loop path (ADR-093). These run
  real Oh-My-Jido runtimes and sessions with the OS host: a question asked by an
  agent with no REPL is found and answered from another process, effects are
  approved or denied only explicitly, and expiry, session exit and restart
  never turn into consent.
  """
  use ExUnit.Case, async: false

  @moduletag milestone: 27
  @moduletag :tmp_dir

  alias Elixos.Approvals

  defp runtime(ctx, opts \\ []) do
    name = Module.concat(__MODULE__, "Runtime#{System.unique_integer([:positive])}")

    start_supervised!(
      {OhMyJido,
       [
         name: name,
         host: {Approvals.Host, []},
         storage: {Jido.Storage.File, path: Path.join(ctx.tmp_dir, "sessions")},
         question_timeout_ms: Keyword.get(opts, :timeout, 30_000)
       ]},
      id: Keyword.get(opts, :id, name)
    )

    name
  end

  defp session(runtime, ctx) do
    workspace = Path.join(ctx.tmp_dir, "workspace")
    File.mkdir_p!(workspace)

    {:ok, session} =
      OhMyJido.start_session(runtime,
        workspace: workspace,
        tools: [OhMyJido.Tools.Question],
        permissions: [:ask, :exec]
      )

    session
  end

  # A detached agent: its own process and group leader, no IEx, no caller
  # waiting on it from a REPL.
  defp detached(fun) do
    parent = self()

    spawn(fn ->
      {:ok, leader} = StringIO.open("")
      Process.group_leader(self(), leader)
      send(parent, {:detached, fun.()})
    end)
  end

  defp request do
    assert_receive {:elixos_approvals, [request | _]}, 5_000
    request
  end

  setup do
    start_supervised!({Approvals, runtime: false})
    {:ok, []} = Approvals.subscribe()
    :ok
  end

  test "a detached agent's question waits until another session answers it", ctx do
    session = session(runtime(ctx), ctx)

    detached(fn ->
      OhMyJido.execute_tool(session, "question", %{
        question: "Which environment?",
        options: [%{label: "staging"}, %{label: "production"}]
      })
    end)

    request = request()
    assert %Approvals.Request{kind: :choice, prompt: "Which environment?"} = request
    assert request.options == ["staging", "production"]
    assert request.session_id == session.id
    refute_receive {:detached, _}, 50

    assert Approvals.answer(request.id, "testing") == {:error, :invalid_answer}
    assert Approvals.pending() == [request]

    answerer = Task.async(fn -> Approvals.answer(request.id, "staging") end)
    assert Task.await(answerer) == :ok
    assert_receive {:detached, {:ok, %{answer: %{label: "staging"}}}}, 5_000
    assert_receive {:elixos_approvals, []}, 5_000
    assert Approvals.approve(request.id) == {:error, :unknown_request}
  end

  test "an effect runs only on explicit approval; anything else denies it", ctx do
    session = session(runtime(ctx), ctx)
    {:ok, context} = OhMyJido.Session.call(session, :context)
    effect = %{sensitive: true, operation: "deploy"}

    detached(fn -> OhMyJido.Tool.authorize(context, :exec, effect) end)
    request = request()
    assert %Approvals.Request{kind: :confirm, prompt: "Approve exec: deploy?"} = request
    assert Approvals.approve(request.id) == :ok
    assert_receive {:detached, :ok}, 5_000

    detached(fn -> OhMyJido.Tool.authorize(context, :exec, effect) end)
    assert Approvals.deny(request().id) == :ok
    assert_receive {:detached, {:error, :approval_denied}}, 5_000

    detached(fn -> OhMyJido.Tool.authorize(context, :exec, effect) end)
    assert Approvals.answer(request().id, false) == :ok
    assert_receive {:detached, {:error, :approval_denied}}, 5_000
  end

  test "an unanswered approval expires closed and leaves the index", ctx do
    session = session(runtime(ctx, timeout: 200), ctx)
    {:ok, context} = OhMyJido.Session.call(session, :context)

    detached(fn -> OhMyJido.Tool.authorize(context, :exec, %{sensitive: true}) end)
    request = request()
    assert_receive {:detached, {:error, :approval_timeout}}, 5_000
    assert_receive {:elixos_approvals, []}, 5_000
    assert Approvals.approve(request.id) == {:error, :unknown_request}
  end

  test "a restart withdraws open questions and never revives them as approvals", ctx do
    name = runtime(ctx, id: :restartable)
    session = session(name, ctx)

    detached(fn ->
      OhMyJido.execute_tool(session, "question", %{question: "Continue after reboot?"})
    end)

    request = request()
    assert request.kind == :text

    # The runtime stops as it would on a reboot: the question goes with it.
    stop_supervised!(:restartable)
    assert_receive {:elixos_approvals, []}, 5_000
    assert Approvals.answer(request.id, "yes") == {:error, :unknown_request}

    start_supervised!(
      {OhMyJido,
       [
         name: name,
         host: {Approvals.Host, []},
         storage: {Jido.Storage.File, path: Path.join(ctx.tmp_dir, "sessions")}
       ]},
      id: :restarted
    )

    assert {:ok, _resumed} = OhMyJido.resume_session(name, session.id)
    assert Approvals.pending() == []
  end
end
