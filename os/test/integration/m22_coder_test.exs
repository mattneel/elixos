defmodule Elixos.Integration.M22CoderTest do
  @moduledoc """
  M22: the console's coder edits a real workspace through M21's toolset, reads
  project instructions, and authenticates to a scripted loopback model without
  leaking the credential to the console or image journal.

  Reference note: none of these acceptance tests has been checked against a
  reference M22 implementation. Recorded OMP inventory supplies the tool names,
  not a reference for the coding loop or credential redaction.
  """
  use ExUnit.Case, async: false

  @moduletag :qemu
  @moduletag milestone: 22
  @moduletag timeout: 900_000
  @moduletag :tmp_dir

  alias Elixos.Test.{Disk, QEMU}

  @source "defmodule Greeter do\n  def greet, do: :hello\nend\n"
  @secret "sk-elixos-test-0000"

  test "a coding conversation writes the file and keeps the key out of durable output", ctx do
    disk = Disk.fresh!(ctx.tmp_dir)
    credentials = Path.join(ctx.tmp_dir, "credentials")
    File.mkdir_p!(credentials)
    File.write!(Path.join(credentials, "stub"), @secret)
    # Seed the key while powered off: typing it would itself leak it in the echo.
    Disk.put_tree!(disk, credentials, "/credentials")
    vm = QEMU.boot_to_iex(ctx, disk: disk)

    {out, vm} = QEMU.iex(vm, ~s|File.mkdir_p!("/priv/work/demo/lib")|)
    assert out =~ ":ok"
    {out, vm} = QEMU.iex(vm, ~s|p = "/priv/work/demo/AGENTS.md"|)
    assert out =~ "AGENTS.md"
    {out, vm} = QEMU.iex(vm, ~s|File.write!(p, "coder-guest-project-9173\\n")|)
    assert out =~ ":ok"

    {out, vm} = QEMU.iex(vm, "(" <> server_module() <> ")", 120_000)
    assert out =~ "{:module, Demo.CoderModel"
    {out, vm} = QEMU.iex(vm, ~s|source = #{inspect(@source)}|)
    assert out =~ "Greeter"
    {out, vm} = QEMU.iex(vm, "port = Demo.CoderModel.start(source)")
    assert out =~ ~r/^\d+$/m
    {out, vm} = QEMU.iex(vm, ~s|url = "http://127.0.0.1:" <> to_string(port) <> "/v1"|)
    assert out =~ "127.0.0.1"
    {out, vm} = QEMU.iex(vm, ~s|model = [base_url: url, model: "stub", credential: "stub"]|)
    assert out =~ "stub"
    {out, vm} = QEMU.iex(vm, ~s|opts = [workspace: "/priv/work/demo", model: model]|)
    assert out =~ "/priv/work/demo"

    {out, vm} =
      QEMU.iex(vm, ~s|result = Elixos.Coder.run("Write and check Greeter", opts)|, 180_000)

    assert out =~ "{:ok,"
    {out, vm} = QEMU.iex(vm, ~s|match?({:ok, %{result: "greeter complete"}}, result)|)
    assert out =~ ~r/^true$/m
    {out, vm} = QEMU.iex(vm, "{:ok, data} = result; :ok")
    assert out =~ ":ok"
    {out, vm} = QEMU.iex(vm, "Enum.map(data.transcript, & &1.tool) |> Enum.reject(&is_nil/1)")
    assert out =~ ~r/"write".*"read"/s
    {out, vm} = QEMU.iex(vm, ~s|File.read!("/priv/work/demo/lib/greeter.ex") == source|)
    assert out =~ ~r/^true$/m
    {out, vm} = QEMU.iex(vm, "Demo.CoderModel.project_seen?()")
    assert out =~ ~r/^true$/m
    {out, vm} = QEMU.iex(vm, "Demo.CoderModel.authenticated?()")
    assert out =~ ~r/^true$/m
    {out, vm} = QEMU.iex(vm, "Demo.CoderModel.round_trip?()")
    assert out =~ ~r/^true$/m

    # Only booleans leave the guest; reading the key at the prompt would leak it.
    {out, vm} = QEMU.iex(vm, ~s|key = Elixos.Coder.Credentials.fetch("stub"); :ok|)
    assert out =~ ":ok"
    {out, vm} = QEMU.iex(vm, "Demo.CoderModel.redacted?(inspect(key))")
    assert out =~ ~r/^true$/m
    {out, vm} = QEMU.iex(vm, ~s|Demo.CoderModel.redacted?(File.read!("/priv/journal.log"))|)
    assert out =~ ~r/^true$/m
    refute QEMU.transcript(vm) =~ @secret
    QEMU.refute_kernel_panic(vm)
    vm = QEMU.send_line(vm, "Elixos.poweroff()")
    {0, vm} = QEMU.expect_exit(vm)
    refute QEMU.transcript(vm) =~ @secret
    assert {:ok, journal} = Disk.read(disk, "/journal.log")
    refute journal =~ @secret
    assert {:ok, @source} = Disk.read(disk, "/work/demo/lib/greeter.ex")
  end

  defp server_module do
    ~S'''
    defmodule Demo.CoderModel do
      def start(source) do
        {:ok, _} = Agent.start_link(fn -> [] end, name: __MODULE__)
        {:ok, listener} = :gen_tcp.listen(0,
          [:binary, active: false, ip: {127, 0, 0, 1}, reuseaddr: true])
        {:ok, {_, port}} = :inet.sockname(listener)
        script = [
          call("write-1", "write", %{
            "path" => "/priv/work/demo/lib/greeter.ex", "content" => source}),
          call("read-2", "read", %{"path" => "/priv/work/demo/lib/greeter.ex"}),
          %{"role" => "assistant", "content" => "greeter complete"}
        ]
        spawn_link(fn -> serve(listener, script) end)
        port
      end

      def project_seen? do
        Agent.get(__MODULE__, fn requests ->
          Enum.any?(requests, fn {_, body} ->
            encode(body["messages"]) =~ "coder-guest-project-9173"
          end)
        end)
      end

      def authenticated? do
        key = File.read!("/priv/credentials/stub")
        Agent.get(__MODULE__, fn requests ->
          length(requests) == 3 and
            Enum.all?(requests, fn {headers, _} ->
              headers["authorization"] == "Bearer " <> key
            end)
        end)
      end

      def round_trip? do
        Agent.get(__MODULE__, fn requests ->
          case requests do
            [_, {_, second}, {_, third}] ->
              tool_result?(second, "write-1") and
                Enum.any?(third["messages"], fn message ->
                  message["role"] == "tool" and
                    message["tool_call_id"] == "read-2" and
                    encode(message["content"]) =~ "defmodule Greeter"
                end)
            _ -> false
          end
        end)
      end

      def redacted?(text) do
        not String.contains?(text, File.read!("/priv/credentials/stub"))
      end

      defp tool_result?(body, id) do
        Enum.any?(body["messages"], fn message ->
          message["role"] == "tool" and message["tool_call_id"] == id
        end)
      end

      defp call(id, name, params) do
        %{"role" => "assistant", "content" => nil, "tool_calls" => [
          %{"id" => id, "type" => "function", "function" => %{
            "name" => name, "arguments" => encode(params)}}
        ]}
      end

      defp encode(value), do: IO.iodata_to_binary(:json.encode(value))

      defp serve(listener, [message | rest]) do
        {:ok, socket} = :gen_tcp.accept(listener)
        {headers, body} = request(socket, "")
        Agent.update(__MODULE__, &(&1 ++ [{headers, :json.decode(body)}]))
        body = encode(%{"choices" => [%{"index" => 0, "message" => message,
          "finish_reason" => if(message["tool_calls"], do: "tool_calls", else: "stop")} ]})
        :ok = :gen_tcp.send(socket, [
          "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: ",
          Integer.to_string(byte_size(body)), "\r\nconnection: close\r\n\r\n", body
        ])
        :gen_tcp.close(socket)
        serve(listener, rest)
      end
      defp serve(listener, []), do: :gen_tcp.close(listener)

      defp request(socket, bytes) do
        case :binary.split(bytes, "\r\n\r\n") do
          [head, body] ->
            ["POST /v1/chat/completions HTTP/1.1" | lines] = String.split(head, "\r\n")
            headers = Map.new(lines, fn line ->
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

      defp receive_body(_socket, body, size) when byte_size(body) >= size do
        binary_part(body, 0, size)
      end
      defp receive_body(socket, body, size) do
        {:ok, more} = :gen_tcp.recv(socket, 0, 10_000)
        receive_body(socket, body <> more, size)
      end
    end
    '''
  end
end
