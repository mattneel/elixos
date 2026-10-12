defmodule Elixos.CoderTest do
  @moduledoc """
  M22: scripted OpenAI turns exercise tool result round-trips, termination,
  supervised subagents, human questions, project instructions and redacted
  credentials. HTTP requests, including authentication, are observed on the wire.

  Reference note: none of these acceptance tests has been checked against a
  reference M22 implementation. Tool names and Task/Ask request schemas come
  from pinned OMP 18.8.7 source, not recorded conversation fixtures.
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  @moduletag milestone: 22
  @moduletag :tmp_dir
  @moduletag timeout: 60_000

  alias Elixos.Coder
  alias Elixos.Coder.Credentials

  setup ctx do
    workspace = Path.join(ctx.tmp_dir, "work")
    credentials = Path.join(ctx.tmp_dir, "credentials")
    File.mkdir_p!(workspace)
    File.mkdir_p!(credentials)
    File.write!(Path.join(workspace, "AGENTS.md"), "Use marker coder-project-7331.\n")
    secret = "sk-host-coder-#{System.unique_integer([:positive])}"
    File.write!(Path.join(credentials, "stub"), secret)
    previous = Application.fetch_env(:elixos, :credentials_dir)
    Application.put_env(:elixos, :credentials_dir, credentials)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:elixos, :credentials_dir, value)
        :error -> Application.delete_env(:elixos, :credentials_dir)
      end
    end)

    %{workspace: workspace, secret: secret}
  end

  test "calls and results round-trip in order, then the model yields", ctx do
    File.write!(Path.join(ctx.workspace, "note.txt"), "original-note")

    script = [
      calls([{"read-1", "read", %{"path" => "note.txt"}}]),
      calls([{"write-2", "write", %{"path" => "note.txt", "content" => "changed"}}]),
      final("completed-note")
    ]

    model = server(script)

    assert {:ok, %{result: "completed-note", transcript: transcript}} =
             Coder.run("Update note.txt", opts(ctx, model))

    assert File.read!(Path.join(ctx.workspace, "note.txt")) == "changed"

    assert tool_turns(transcript) == ["read", "write"]
    assert_receive {:request, 1, first, _headers, _server}, 5_000
    assert encode(first["messages"]) =~ "coder-project-7331"
    assert_receive {:request, 2, second, _headers, _server}, 5_000
    assert tool_result(second, "read-1") =~ "original-note"
    assert_receive {:request, 3, third, _headers, _server}, 5_000

    assert Enum.any?(
             third["messages"],
             &(&1["role"] == "tool" and &1["tool_call_id"] == "write-2")
           )

    refute_receive {:request, 4, _, _, _}, 100
  end

  test "a task tool starts a live subagent under the coder supervisor", ctx do
    child_task = "child-probe-8817: report child-ready"

    model =
      server(fn request ->
        child? =
          Enum.any?(request["messages"], fn message ->
            message["role"] == "user" and encode(message["content"]) =~ child_task
          end)

        started? = Enum.any?(request["messages"], &(&1["tool_call_id"] == "task-1"))

        cond do
          child? ->
            {:child, {:hold, final("child-ready")}}

          started? ->
            {:parent_done, final("parent-ready")}

          true ->
            {:parent_start,
             {:hold,
              calls([
                {"task-1", "task",
                 %{
                   "context" => "Return the probe result without changing files.",
                   "tasks" => [
                     %{"task" => child_task, "solutionSpace" => "One fix: return child-ready."}
                   ]
                 }}
              ])}}
        end
      end)

    runner = Task.async(fn -> Coder.run("Delegate a probe", opts(ctx, model)) end)
    assert_receive {:request, :parent_start, _, _, parent_server}, 5_000
    before = DynamicSupervisor.which_children(Elixos.Coder.Supervisor) |> Enum.map(&elem(&1, 1))
    send(parent_server, :release)
    assert_receive {:request, :child, request, _, server}, 10_000
    assert encode(request["messages"]) =~ child_task

    children = DynamicSupervisor.which_children(Elixos.Coder.Supervisor)
    agents = for {_, pid, :worker, _} <- children, is_pid(pid), pid not in before, do: pid
    assert length(agents) >= 1
    assert Enum.all?(agents, &Process.alive?/1)

    assert Enum.any?(agents, fn pid ->
             case Jido.AgentServer.state(pid) do
               {:ok, %{agent: %{state: state}}} when is_map(state) -> true
               _ -> false
             end
           end)

    send(server, :release)
    assert {:ok, %{result: "parent-ready", transcript: transcript}} = Task.await(runner, 20_000)
    assert "task" in tool_turns(transcript)
  end

  test "the ask tool waits for a human and returns that answer to the model", ctx do
    model =
      server([
        calls([
          {"ask-1", "ask",
           %{"questions" => [%{"id" => "name", "question" => "coder name?", "options" => []}]}}
        ]),
        final("human answered")
      ])

    runner = Task.async(fn -> Coder.run("Ask the human for a name", opts(ctx, model)) end)
    question = await_question("coder name?")
    assert question.kind == :text
    refute_receive {:request, 2, _, _, _}, 100
    assert :ok = Elixos.Ask.answer(question.id, "human-marker-4488")
    assert {:ok, %{result: "human answered", transcript: transcript}} = Task.await(runner, 15_000)
    assert "ask" in tool_turns(transcript)
    assert_receive {:request, 2, request, _, _}, 5_000
    assert tool_result(request, "ask-1") =~ "human-marker-4488"
    refute Enum.any?(Elixos.Ask.pending(), &(&1.id == question.id))
  end

  test "credentials authenticate but redact values, session state, logs and transcript", ctx do
    model = server([final("safe-completion")])

    logs =
      capture_log(fn ->
        assert {:ok, credential} = Credentials.fetch("stub")
        refute inspect(credential) =~ ctx.secret
        assert {:error, :missing} = Credentials.fetch("absent")
        assert {:ok, session} = Coder.start(opts(ctx, model))
        assert Process.info(session, :group_leader) == {:group_leader, Process.group_leader()}
        refute inspect(:sys.get_state(session), limit: :infinity) =~ ctx.secret
        on_exit(fn -> if Process.alive?(session), do: GenServer.stop(session) end)

        assert {:ok, %{result: "safe-completion", transcript: transcript}} =
                 Coder.run("Complete without leaking credentials", opts(ctx, model))

        refute inspect(transcript, limit: :infinity) =~ ctx.secret
      end)

    refute logs =~ ctx.secret
    assert_receive {:request, _, _, headers, _}, 5_000
    assert headers["authorization"] == "Bearer " <> ctx.secret
  end

  defp opts(ctx, model), do: [workspace: ctx.workspace, model: model]

  # Some transcripts record both invocation and result; retain first use order.
  defp tool_turns(transcript) do
    transcript |> Enum.map(& &1.tool) |> Enum.reject(&is_nil/1) |> Enum.dedup()
  end

  defp tool_result(request, id) do
    message = Enum.find(request["messages"], &(&1["role"] == "tool" and &1["tool_call_id"] == id))
    assert is_map(message), "missing result for #{id}"
    encode(message["content"])
  end

  defp await_question(prompt, attempts \\ 200)
  defp await_question(_prompt, 0), do: flunk("coder never opened its Ask question")

  defp await_question(prompt, attempts) do
    case Enum.find(Elixos.Ask.pending(), &(&1.prompt == prompt)) do
      nil ->
        Process.sleep(25)
        await_question(prompt, attempts - 1)

      question ->
        question
    end
  end

  defp calls(calls) do
    %{
      "role" => "assistant",
      "content" => nil,
      "tool_calls" =>
        Enum.map(calls, fn {id, name, params} ->
          %{
            "id" => id,
            "type" => "function",
            "function" => %{"name" => name, "arguments" => encode(params)}
          }
        end)
    }
  end

  defp final(text), do: %{"role" => "assistant", "content" => text}
  defp encode(value), do: IO.iodata_to_binary(:json.encode(value))

  defp server(script) do
    owner = self()

    {:ok, listen} =
      :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}, reuseaddr: true])

    {:ok, {_, port}} = :inet.sockname(listen)
    pid = spawn_link(fn -> serve(listen, script, owner, 1) end)

    on_exit(fn ->
      :gen_tcp.close(listen)
      if Process.alive?(pid), do: Process.exit(pid, :kill)
    end)

    [base_url: "http://127.0.0.1:#{port}/v1", model: "stub", credential: "stub"]
  end

  # Subagent and parent requests can arrive in either order; serve independently.
  defp serve(listen, script, owner, index) when is_function(script, 1) do
    {:ok, socket} = :gen_tcp.accept(listen)

    spawn_link(fn ->
      {headers, body} = request(socket, "")
      request = :json.decode(body)
      {label, response} = script.(request)
      send(owner, {:request, label, request, headers, self()})
      respond(socket, response)
    end)

    serve(listen, script, owner, index + 1)
  end

  defp serve(listen, [response | rest], owner, index) do
    {:ok, socket} = :gen_tcp.accept(listen)
    {headers, body} = request(socket, "")
    send(owner, {:request, index, :json.decode(body), headers, self()})
    respond(socket, response)
    serve(listen, rest, owner, index + 1)
  end

  defp serve(listen, [], owner, index) do
    # Unexpected extra turns remain observable rather than silently succeeding.
    serve(listen, [final("UNEXPECTED EXTRA TURN")], owner, index)
  end

  defp respond(socket, response) do
    message =
      case response do
        {:hold, message} ->
          receive do
            :release -> message
          after
            20_000 -> exit(:release_timeout)
          end

        message ->
          message
      end

    body =
      encode(%{
        "choices" => [
          %{
            "index" => 0,
            "message" => message,
            "finish_reason" => if(message["tool_calls"], do: "tool_calls", else: "stop")
          }
        ]
      })

    :ok =
      :gen_tcp.send(socket, [
        "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: ",
        Integer.to_string(byte_size(body)),
        "\r\nconnection: close\r\n\r\n",
        body
      ])

    :gen_tcp.close(socket)
  end

  defp request(socket, bytes) do
    case :binary.split(bytes, "\r\n\r\n") do
      [head, body] ->
        ["POST /v1/chat/completions HTTP/1.1" | lines] = String.split(head, "\r\n")

        headers =
          Map.new(lines, fn line ->
            [name, value] = String.split(line, ":", parts: 2)
            {String.downcase(name), String.trim(value)}
          end)

        size = String.to_integer(Map.fetch!(headers, "content-length"))
        {headers, receive_body(socket, body, size)}

      [_] ->
        {:ok, more} = :gen_tcp.recv(socket, 0, 10_000)
        request(socket, bytes <> more)
    end
  end

  defp receive_body(_socket, body, size) when byte_size(body) >= size,
    do: binary_part(body, 0, size)

  defp receive_body(socket, body, size) do
    {:ok, more} = :gen_tcp.recv(socket, 0, 10_000)
    receive_body(socket, body <> more, size)
  end
end
