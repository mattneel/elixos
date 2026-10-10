defmodule Elixos.Integration.M15JidoAgentsTest do
  @moduledoc """
  M15: agents are ordinary Elixos code. A Jido agent - installed from a
  trusted repository by name, with its dependency closure - is defined at the
  prompt, started under the system's own supervisor, and then the machine is
  powered off and on again: the next boot starts it again with what it
  remembered. An action that calls a model talks to a stub over the loopback.
  """
  use ExUnit.Case, async: false

  @moduletag :qemu
  @moduletag milestone: 15
  @moduletag timeout: 900_000
  @moduletag :tmp_dir

  alias Elixos.Test.{Disk, Paths, QEMU}

  # What a prompt would define: a Jido instance, two actions (one keeps a
  # note, one asks the model), an agent wiring them, a stub provider, and two
  # helpers over the runtime.
  defp modules do
    """
    defmodule Demo.Jido do
      use Jido, otp_app: :demo_agents
    end

    defmodule Demo.Note do
      use Jido.Action,
        name: "note",
        schema: [note: [type: :string, default: ""]]

      def run(params, _ctx), do: {:ok, %{last: params.note}}
    end

    defmodule Demo.Ask do
      use Jido.Action,
        name: "ask",
        schema: [prompt: [type: :string, default: "hello"]]

      def run(params, _ctx) do
        provider = [base_url: "http://127.0.0.1:4040/v1", model: "stub-model"]

        case Elixos.Agents.LLM.complete([{"user", params.prompt}], provider) do
          {:ok, text} -> {:ok, %{answer: text}}
          {:error, reason} -> {:error, reason}
        end
      end
    end

    defmodule Demo.Agent do
      use Jido.Agent,
        name: "demo_agent",
        schema: [last: [type: :string, default: ""], answer: [type: :string, default: ""]],
        signal_routes: [{"note", Demo.Note}, {"ask", Demo.Ask}]
    end

    defmodule Demo.Stub do
      def start(port, text) do
        {:ok, listen} = :gen_tcp.listen(port, [:binary, active: false, reuseaddr: true])
        spawn_link(fn -> loop(listen, text) end)
        :ok
      end

      defp loop(listen, text) do
        {:ok, socket} = :gen_tcp.accept(listen)
        _ = :gen_tcp.recv(socket, 0, 5_000)
        body = IO.iodata_to_binary(:json.encode(%{"choices" => [%{"message" => %{"content" => text}}]}))

        :gen_tcp.send(socket, [
          "HTTP/1.1 200 OK\\r\\ncontent-type: application/json\\r\\ncontent-length: ",
          Integer.to_string(byte_size(body)),
          "\\r\\nconnection: close\\r\\n\\r\\n",
          body
        ])

        :gen_tcp.close(socket)
        loop(listen, text)
      end
    end

    defmodule Demo do
      def ask(id, type, data) do
        {:ok, _agent} =
          Jido.AgentServer.call(Elixos.Agents.whereis(id), Jido.Signal.new!(type, data))

        state(id)
      end

      def state(id) do
        {:ok, state} = Jido.AgentServer.state(Elixos.Agents.whereis(id))
        state.agent.state
      end
    end
    """
  end

  test "a jido agent is installed by name, supervised, and back after a power cycle", ctx do
    disk = Disk.fresh!(ctx.tmp_dir)
    Disk.put_tree!(disk, Path.join(Paths.fixture("hex_repo"), "public"), "/hex-repo")

    vm = QEMU.boot_to_iex(ctx, disk: disk)

    add =
      ~s|Elixos.Package.add_repo(:fixture, "/priv/hex-repo", key: File.read!("/priv/hex-repo/public_key"))|

    {out, vm} = QEMU.iex(vm, add)
    assert out =~ ":ok"

    # By name: the closure (jido and its dependencies) installs first.
    {out, vm} = QEMU.iex(vm, "Elixos.Package.install(:jido)", 600_000)
    assert out =~ "{:ok, :jido}"
    {out, vm} = QEMU.iex(vm, ~s{Map.has_key?(Elixos.Package.installed(), :jido)})
    assert out =~ ~r/^true$/m

    # The modules go in as *one* expression - the way the M6 test defines a
    # module at a prompt - because `QEMU.iex/3` waits for the next prompt and
    # several pasted expressions would move that counter on without it (M14's
    # lesson). The session's tracer sees them, so the image journals them.
    {out, vm} = QEMU.iex(vm, "(" <> modules() <> ")", 120_000)
    assert out =~ "{:module, Demo"

    {out, vm} = QEMU.iex(vm, ~s{Code.ensure_loaded?(Demo.Agent)})
    assert out =~ ~r/^true$/m

    # Two agents: one keeps a note, one asks a model - over the loopback.
    {out, vm} = QEMU.iex(vm, ~s|Elixos.Agents.start(Demo.Agent, id: "greeter", jido: Demo.Jido)|)
    assert out =~ "{:ok, #PID<"

    {out, vm} = QEMU.iex(vm, ~s|Demo.ask("greeter", "note", %{note: "hello"})|)
    assert out =~ ~s|last: "hello"|

    {out, vm} = QEMU.iex(vm, ~s|Demo.Stub.start(4040, "stub says hi")|)
    assert out =~ ":ok"

    {out, vm} = QEMU.iex(vm, ~s|Elixos.Agents.start(Demo.Agent, id: "scribe", jido: Demo.Jido)|)
    assert out =~ "{:ok, #PID<"

    {out, vm} = QEMU.iex(vm, ~s|Demo.ask("scribe", "ask", %{prompt: "hi"})|)
    assert out =~ ~s|answer: "stub says hi"|

    {out, vm} = QEMU.iex(vm, ~s{Elixos.Agents.list() |> Map.keys() |> Enum.sort()})
    assert out =~ ~s(["greeter", "scribe"])

    # Save, power off, power on.
    {out, vm} = QEMU.iex(vm, "Elixos.save()")
    assert out =~ ~r/\{:ok, \d+\}/
    vm = QEMU.send_line(vm, "Elixos.poweroff()")
    {0, _} = QEMU.expect_exit(vm)

    vm = QEMU.boot_to_iex(ctx, disk: disk)

    # Both agents are running again, and the note is still there.
    {out, vm} = QEMU.iex(vm, ~s{Elixos.Agents.list() |> Map.keys() |> Enum.sort()})
    assert out =~ ~s(["greeter", "scribe"])

    {out, vm} = QEMU.iex(vm, ~s|Demo.state("greeter")|)
    assert out =~ ~s|last: "hello"|

    # And an action can call the model again.
    {out, vm} = QEMU.iex(vm, ~s|Demo.Stub.start(4040, "back again")|)
    assert out =~ ":ok"
    {out, vm} = QEMU.iex(vm, ~s|Demo.ask("scribe", "ask", %{prompt: "again"})|)
    assert out =~ ~s|answer: "back again"|

    # The VM's working directory never moved (ADR-016).
    {out, vm} = QEMU.iex(vm, "File.cwd!()")
    assert out =~ ~s("/")

    QEMU.refute_kernel_panic(vm)
    QEMU.stop(vm)
  end
end
