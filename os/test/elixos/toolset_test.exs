defmodule Elixos.ToolsetTest do
  @moduledoc """
  M21: checks the pinned inventory, deferred tools, fixture coverage, per-call
  dispatch provenance, session boundaries and QuickBEAM resource limits
  (ADR-047).

  Reference note: the inventory and think request/result shape come from OMP
  18.8.7 source. The dispatch, session, error and limit acceptance tests have
  not been checked against a reference implementation; per-tool fixtures must
  be recorded during M21 before claiming differential parity.
  """
  use ExUnit.Case, async: false

  @moduletag milestone: 21
  @moduletag :deferred
  @moduletag :tmp_dir

  alias Elixos.Toolset
  alias Elixos.Toolset.{Peer, Session}

  @fixture_root Path.expand("../fixtures/omp", __DIR__)
  @inventory_file Path.join(@fixture_root, "inventory.exs")
  @external_resource @inventory_file
  @reference @inventory_file |> Code.eval_file() |> elem(0)
  @tools Enum.map(@reference.tools, &elem(&1, 0))

  @implementation_beam elem(
                         defmodule ElixirBash do
                           @moduledoc false
                           @behaviour Elixos.Toolset.Implementation

                           @impl true
                           def call(params, session) do
                             {stdout, exit_code} =
                               System.cmd("/bin/sh", ["-c", Map.fetch!(params, "command")],
                                 cd: session.workspace,
                                 stderr_to_stdout: true
                               )

                             {:ok,
                              %{
                                "stdout" => stdout,
                                "exit_code" => exit_code,
                                "node" => node()
                              }}
                           end
                         end,
                         2
                       )

  setup do
    original = Application.fetch_env(:elixos, Toolset)
    opts = Application.get_env(:elixos, Toolset, [])
    Application.put_env(:elixos, Toolset, Keyword.delete(opts, :implementations))

    on_exit(fn ->
      case original do
        {:ok, value} -> Application.put_env(:elixos, Toolset, value)
        :error -> Application.delete_env(:elixos, Toolset)
      end
    end)

    :ok
  end

  test "inventory preserves every pinned tool name and its order" do
    assert Toolset.inventory() == @tools
  end

  test "waiting tools and milestone numbers match the recorded inventory" do
    assert Toolset.waiting() == @reference.waits
  end

  test "every non-waiting tool has at least one recorded OMP fixture" do
    missing =
      Enum.reject(@tools, fn tool ->
        Map.has_key?(@reference.waits, tool) or
          Enum.any?(Path.wildcard(Path.join([@fixture_root, tool, "*.json"])), &File.regular?/1)
      end)

    assert missing == [],
           "M21 must record OMP fixtures before this suite can pass; missing tools: " <>
             Enum.join(missing, ", ")
  end

  test "every inventory tool initially selects QuickBEAM before promotion" do
    for tool <- @tools do
      assert Toolset.implementation(tool) == :quickbeam, "initial implementation of #{tool}"
    end
  end

  test "generation selection changes the next call and executes effects once", ctx do
    session = Session.new(workspace: ctx.tmp_dir, session_dir: ctx.tmp_dir)
    assert Toolset.implementation("bash") == :quickbeam
    opts = Application.get_env(:elixos, Toolset, [])

    # This deliberately small test backend performs a real subprocess effect,
    # not an echo of its parameters. It is not a substitute OMP reference.
    assert {:module, ElixirBash} =
             :erpc.call(
               Peer.node(),
               :code,
               :load_binary,
               [ElixirBash, ~c"toolset_test.exs", @implementation_beam]
             )

    Application.put_env(
      :elixos,
      Toolset,
      Keyword.put(opts, :implementations, %{"bash" => {:elixir, ElixirBash}})
    )

    assert Toolset.implementation("bash") == :elixir
    params = %{"command" => "printf 'selected\\n' >> dispatch.log; printf 'ran\\n'"}
    cwd = File.cwd!()
    environment = System.get_env()

    assert {:ok, %{"stdout" => "ran\n", "exit_code" => 0, "node" => implementation_node}} =
             Toolset.call("bash", params, session: session)

    assert File.read!(Path.join(ctx.tmp_dir, "dispatch.log")) == "selected\n"
    assert File.cwd!() == cwd
    assert System.get_env() == environment

    assert %{tool: "bash", implementation: :elixir, revision: revision, node: recorded_node} =
             Toolset.last_run("bash")

    assert recorded_node == implementation_node
    refute recorded_node == node()
    assert is_binary(revision) and byte_size(revision) > 0

    Application.put_env(:elixos, Toolset, opts)
    assert Toolset.implementation("bash") == :quickbeam
    assert {:ok, _output} = Toolset.call("bash", params, session: session)
    assert File.read!(Path.join(ctx.tmp_dir, "dispatch.log")) == "selected\nselected\n"
    assert %{implementation: :quickbeam, node: ^recorded_node} = Toolset.last_run("bash")
  end

  test "a read records the selected implementation, revision and isolated node", ctx do
    workspace = Path.join(ctx.tmp_dir, "workspace")
    File.mkdir_p!(workspace)
    File.write!(Path.join(workspace, "hello.txt"), "m21-read-provenance\n")
    session = Session.new(workspace: workspace)

    assert %Session{workspace: ^workspace, session_dir: session_dir} = session
    assert session_dir == Elixos.Session.cwd()
    assert Toolset.implementation("read") == :quickbeam
    # OMP 18.8.7 src/tools/read.ts, readSchema: the input is %{ "path" => string }.
    assert {:ok, output} = Toolset.call("read", %{"path" => "hello.txt"}, session: session)
    assert inspect(output) =~ "m21-read-provenance"

    assert %{tool: "read", implementation: :quickbeam, revision: revision, node: peer_node} =
             Toolset.last_run("read")

    assert is_binary(revision) and byte_size(revision) > 0
    assert is_atom(peer_node)
    refute peer_node == node()
  end

  test "the peer sandbox exposes no Node or browser APIs and cannot change VM environment" do
    environment = System.get_env()
    {peer, context, opts} = sandbox_context!()
    peer_environment = :erpc.call(peer, System, :get_env, [])
    call_opts = Keyword.take(opts, [:timeout])

    assert {:ok, ["undefined", "undefined", "undefined"]} =
             :erpc.call(peer, QuickBEAM.Context, :eval, [
               context,
               "[typeof process, typeof Bun, typeof fetch]",
               call_opts
             ])

    assert {:ok, "blocked"} =
             :erpc.call(peer, QuickBEAM.Context, :eval, [
               context,
               "try { process.env.M21_SANDBOX = 'changed'; 'changed' } catch (_) { 'blocked' }",
               call_opts
             ])

    assert System.get_env() == environment
    assert :erpc.call(peer, System, :get_env, []) == peer_environment
  end

  test "the configured reduction budget interrupts an infinite loop without a wall-clock deadline" do
    {peer, context, _opts} = sandbox_context!()

    assert {:error, reason} =
             :erpc.call(peer, QuickBEAM.Context, :eval, [context, "while (true) {}", []], 10_000)

    assert inspect(reason) =~ "interrupted"
    assert {:ok, 42} = :erpc.call(peer, QuickBEAM.Context, :eval, [context, "6 * 7"])
  end

  test "the configured per-call deadline interrupts a loop even with the reduction budget disabled" do
    {peer, context, opts} = sandbox_context!(max_reductions: 0)

    assert {:error, reason} =
             :erpc.call(
               peer,
               QuickBEAM.Context,
               :eval,
               [context, "while (true) {}", Keyword.take(opts, [:timeout])],
               10_000
             )

    assert inspect(reason) =~ "interrupted"
    assert {:ok, 42} = :erpc.call(peer, QuickBEAM.Context, :eval, [context, "6 * 7"])
  end

  test "the context heap budget refuses an allocation beyond its quota" do
    {peer, context, opts} = sandbox_context!()
    bytes = Keyword.fetch!(opts, :memory_limit) + 1

    assert {:error, reason} =
             :erpc.call(
               peer,
               QuickBEAM.Context,
               :eval,
               [context, "new ArrayBuffer(#{bytes})", Keyword.take(opts, [:timeout])],
               10_000
             )

    assert inspect(reason) =~ "out of memory"
    assert {:ok, 42} = :erpc.call(peer, QuickBEAM.Context, :eval, [context, "6 * 7"])
  end

  test "think accepts the pinned thoughts parameter without exposing the scratchpad", ctx do
    session = Session.new(workspace: ctx.tmp_dir, session_dir: ctx.tmp_dir)

    assert Toolset.call("think", %{"thoughts" => "private Unicode scratchpad: λ𐐷"},
             session: session
           ) ==
             {:ok,
              %{
                "content" => [%{"type" => "text", "text" => "------"}],
                "details" => %{"recorded" => true}
              }}
  end

  test "concurrent workspaces isolate writes, subprocess cwd and environment", ctx do
    cwd = File.cwd!()
    environment = System.get_env()
    roots = for name <- ["first", "second"], do: Path.join(ctx.tmp_dir, name)

    sessions =
      Enum.map(roots, fn root ->
        File.mkdir_p!(root)
        Session.new(workspace: root, session_dir: root)
      end)

    results =
      sessions
      |> Enum.with_index()
      |> Enum.map(fn {session, index} ->
        Task.async(fn ->
          params = %{
            "command" => "export M21_TOOL_LOCAL=#{index}; printf '#{index}\\n' >> once.txt"
          }

          Toolset.call("bash", params, session: session, timeout: 10_000)
        end)
      end)
      |> Enum.map(&Task.await(&1, 15_000))

    assert Enum.all?(results, &match?({:ok, _}, &1))
    assert File.read!(Path.join(Enum.at(roots, 0), "once.txt")) == "0\n"
    assert File.read!(Path.join(Enum.at(roots, 1), "once.txt")) == "1\n"
    assert File.cwd!() == cwd
    assert System.get_env() == environment
  end

  test "absolute, traversing and symlinked reads and writes cannot escape both roots", ctx do
    workspace = Path.join(ctx.tmp_dir, "workspace")
    session_dir = Path.join(ctx.tmp_dir, "session")
    outside = Path.join(ctx.tmp_dir, "outside.txt")
    File.mkdir_p!(workspace)
    File.mkdir_p!(session_dir)
    File.write!(outside, "outside-session-secret\n")
    File.ln_s!(outside, Path.join(workspace, "escape.txt"))
    session = Session.new(workspace: workspace, session_dir: session_dir)

    for path <- [outside, "../outside.txt", "escape.txt"] do
      assert {:error, _reason} = Toolset.call("read", %{"path" => path}, session: session)

      assert {:error, _reason} =
               Toolset.call("write", %{"path" => path, "content" => "escaped\n"},
                 session: session
               )

      assert File.read!(outside) == "outside-session-secret\n"
    end

    File.write!(Path.join(session_dir, "allowed.txt"), "session-directory-readable\n")

    assert {:ok, output} =
             Toolset.call("read", %{"path" => Path.join(session_dir, "allowed.txt")},
               session: session
             )

    assert Enum.any?(Map.fetch!(output, "content"), fn block ->
             block["type"] == "text" and
               String.contains?(block["text"], "session-directory-readable")
           end)
  end

  test "unknown tools and deferred tools return distinct failures", ctx do
    session = Session.new(workspace: ctx.tmp_dir)

    assert {:error, unknown_reason} =
             Toolset.call("not-an-omp-tool", %{}, session: session)

    for {waiting_tool, _milestone} <- @reference.waits do
      assert {:error, waiting_reason} = Toolset.call(waiting_tool, %{}, session: session)
      refute unknown_reason == waiting_reason
    end
  end

  defp sandbox_context!(overrides \\ []) do
    peer = Peer.node()
    opts = Keyword.merge(Peer.quickbeam_options(), overrides)
    # RPC workers are short-lived. Start unlinked, then explicitly stop both
    # owners on exit; a trapping start_link child could die with its RPC parent.
    assert {:ok, pool} =
             :erpc.call(peer, GenServer, :start, [
               QuickBEAM.ContextPool,
               [size: 1, memory_limit: Keyword.fetch!(opts, :memory_limit)],
               []
             ])

    assert {:ok, context} =
             :erpc.call(peer, GenServer, :start, [
               QuickBEAM.Context,
               Keyword.put(opts, :pool, pool),
               []
             ])

    on_exit(fn ->
      :erpc.call(peer, QuickBEAM.Context, :stop, [context])
      :erpc.call(peer, GenServer, :stop, [pool])
    end)

    {peer, context, opts}
  end
end
