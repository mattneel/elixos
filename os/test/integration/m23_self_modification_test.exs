defmodule Elixos.Integration.M23SelfModificationTest do
  @moduledoc """
  M23: the real agent edits generation source through its tools; peer-tested
  candidates become live only after NEXT, boot health and COMMIT. Failed health
  falls back without losing evidence, and factory rescue restores the factory
  agent, prompt and tool implementation.

  Reference note: none of these acceptance tests has been checked against a
  reference Elixos implementation. The think tool's result and strict parameter
  schema are taken from the pinned OMP 18.8.7 source, not a recorded fixture;
  candidate testing must also run the M21 recorded differential fixtures.
  """
  use ExUnit.Case, async: false

  @moduletag :qemu
  @moduletag milestone: 23
  @moduletag :deferred
  @moduletag timeout: 3_600_000
  @moduletag :tmp_dir

  alias Elixos.Test.{Disk, QEMU}

  @workspace "/priv/work/m23"
  @think_result %{
    "content" => [%{"type" => "text", "text" => "------"}],
    "details" => %{"recorded" => true}
  }

  test "the agent improves its own tool, commits it and keeps it across power cycles", ctx do
    disk = disk_with_credential(ctx.tmp_dir)
    vm = boot(ctx, disk)
    vm = assert_think(vm, :quickbeam)
    vm = checkout(vm)
    vm = run_agent(vm, improvement_turns(), "Port the think tool to Elixir.")
    {_, vm} = QEMU.iex(vm, "revision = Elixos.Toolset.last_run(\"edit\").revision")
    {_, vm} = QEMU.iex(vm, "File.write!(\"/priv/m23-edit-revision\", revision)")
    vm = assert_think(vm, :quickbeam)
    vm = build_test_propose(vm)
    power_off(vm)

    vm = boot(ctx, disk)
    vm = QEMU.await_log(vm, ~r/^elixos-shim: commit generation=1\r?$/m, 180_000)
    vm = assert_think(vm, :elixir)
    {_, vm} = QEMU.iex(vm, "{:ok, p} = Elixos.Candidate.provenance(1)")
    {out, vm} = QEMU.iex(vm, "p.parent")
    assert out =~ ~r/^0$/m
    {out, vm} = QEMU.iex(vm, "p.model == \"scripted-m23\" and p.session == \"m23-agent\"")
    assert out =~ ~r/^true$/m
    {out, vm} = QEMU.iex(vm, "p.tools[\"edit\"].tool == \"edit\"")
    assert out =~ ~r/^true$/m
    {_, vm} = QEMU.iex(vm, "recorded = File.read!(\"/priv/m23-edit-revision\")")
    {out, vm} = QEMU.iex(vm, "p.tools[\"edit\"].revision == recorded")
    assert out =~ ~r/^true$/m
    power_off(vm)

    vm = boot(ctx, disk)
    vm = assert_think(vm, :elixir)
    {_, vm} = QEMU.iex(vm, "{:ok, p} = Elixos.Candidate.provenance(1)")
    {out, vm} = QEMU.iex(vm, "p.parent")
    assert out =~ ~r/^0$/m
    power_off(vm)
  end

  test "a candidate that boots but fails health falls back and retains its evidence", ctx do
    disk = disk_with_credential(ctx.tmp_dir)
    vm = boot(ctx, disk)
    vm = checkout(vm)

    # The extra check passes in the build/test peers, then fails only after
    # the marker is created for the actual boot. This tests boot health, not
    # a syntax error, boot-spec crash, or a rejected pre-boot test run.
    {_, vm} = QEMU.iex(vm, "path = Path.join(src, \"lib/elixos/health.ex\")")
    {_, vm} = QEMU.iex(vm, "broken = M23.Script.wrap(path, :health)")
    {_, vm} = QEMU.iex(vm, "turns = [{\"write\", %{\"path\" => path, \"content\" => broken}}]")
    vm = run_prepared_agent(vm, "Add a boot-only failing health check.")
    vm = build_test_propose(vm)
    {out, vm} = QEMU.iex(vm, "File.write!(\"/priv/m23-fail-health\", \"fail after boot\")")
    assert out =~ ~r/^:ok$/m
    power_off(vm)

    vm =
      Enum.reduce(1..2, nil, fn attempt, _previous_vm ->
        vm = boot(ctx, disk, ["elixos.max_attempts=2"])

        vm =
          QEMU.await_log(
            vm,
            Regex.compile!(
              "^elixos-shim: plan generation=1 mode=normal attempt=#{attempt}\\r?$",
              "m"
            )
          )

        {out, vm} = QEMU.iex(vm, "{:error, failures} = Elixos.Health.run()", 900_000)
        assert out =~ "m23_boot_failure"
        refute QEMU.transcript(vm) =~ "elixos-shim: commit generation=1"
        power_off(vm)
      end)

    QEMU.refute_kernel_panic(vm)
    vm = boot(ctx, disk, ["elixos.max_attempts=2"])

    vm =
      QEMU.await_log(
        vm,
        ~r/^elixos-shim: fallback to last_good=0 after 2 attempts of generation=1\r?$/m
      )

    vm = QEMU.await_log(vm, ~r/^elixos-shim: plan generation=0 mode=normal attempt=1\r?$/m)
    {out, vm} = QEMU.iex(vm, "Elixos.info().generation")
    assert out =~ ~r/^0$/m
    {_, vm} = QEMU.iex(vm, "e = Elixos.Candidate.evidence_dir(1)")
    {out, vm} = QEMU.iex(vm, "File.dir?(e)")
    assert out =~ ~r/^true$/m
    {_, vm} = QEMU.iex(vm, "files = Path.wildcard(Path.join(e, \"**/*\"))")
    {_, vm} = QEMU.iex(vm, "files = Enum.filter(files, &File.regular?/1)")
    {out, vm} = QEMU.iex(vm, "Enum.any?(files, &(Path.extname(&1) in [\".dump\", \".log\"]))")
    assert out =~ ~r/^true$/m
    {out, vm} = QEMU.iex(vm, "Enum.any?(files, &(File.read!(&1) =~ \"m23_boot_failure\"))")
    assert out =~ ~r/^true$/m
    power_off(vm)

    vm = boot(ctx, disk, ["elixos.max_attempts=2"])
    {out, vm} = QEMU.iex(vm, "File.dir?(Elixos.Candidate.evidence_dir(1))")
    assert out =~ ~r/^true$/m
    power_off(vm)
  end

  test "factory rescue runs the factory agent, prompt and tools rather than the candidate", ctx do
    disk = disk_with_credential(ctx.tmp_dir)
    vm = boot(ctx, disk)
    vm = assert_think(vm, :quickbeam)
    {out, vm} = QEMU.iex(vm, "Elixos.Coder.prompt_hash()")
    factory_hash = prompt_hash(out)
    vm = checkout(vm)

    # A separate prompt change makes the factory/suspect distinction visible;
    # it is not the tool improvement, which remains the pure think port.
    {_, vm} = QEMU.iex(vm, "path = Path.join(src, \"lib/elixos/coder.ex\")")
    {_, vm} = QEMU.iex(vm, "prompt = M23.Script.wrap(path, :prompt)")
    vm = put_value(vm, "turns", improvement_turns())

    {_, vm} =
      QEMU.iex(vm, "turns = turns ++ [{\"write\", %{\"path\" => path, \"content\" => prompt}}]")

    vm = run_prepared_agent(vm, "Port think and clarify the agent's prompt.")
    vm = build_test_propose(vm)
    power_off(vm)

    vm = boot(ctx, disk)
    vm = QEMU.await_log(vm, ~r/^elixos-shim: commit generation=1\r?$/m, 180_000)
    vm = assert_think(vm, :elixir)
    {out, vm} = QEMU.iex(vm, "Elixos.Coder.prompt_hash()")
    improved_hash = prompt_hash(out)
    refute improved_hash == factory_hash
    {out, vm} = QEMU.iex(vm, "Elixos.Coder.system_prompt() =~ \"M23 generation-only edits\"")
    assert out =~ ~r/^true$/m
    power_off(vm)

    vm = boot(ctx, disk, ["elixos.safe"])
    vm = QEMU.await_log(vm, ~r/^elixos-shim: plan generation=0 mode=rescue attempt=0\r?$/m)
    {out, vm} = QEMU.iex(vm, "{Elixos.info().generation, Elixos.info().mode}")
    assert out =~ "{0, :rescue}"
    {out, vm} = QEMU.iex(vm, "Elixos.Coder.prompt_hash()")
    assert prompt_hash(out) == factory_hash
    refute prompt_hash(out) == improved_hash
    vm = assert_think(vm, :quickbeam)

    vm =
      run_agent(vm, [{"think", %{"thoughts" => "factory rescue"}}], "Use the factory think tool.")

    refute QEMU.transcript(vm) =~ "elixos-shim: commit generation=0"
    power_off(vm)
  end

  defp boot(ctx, disk, append \\ []) do
    vm =
      QEMU.boot_to_iex(ctx,
        disk: disk,
        memory_mb: 2048,
        append: ["elixos.commit_after=2" | append]
      )

    {out, vm} = QEMU.iex(vm, "(" <> script_module() <> ")", 120_000)
    assert out =~ "{:module, M23.Script"
    vm
  end

  defp disk_with_credential(tmp_dir) do
    disk = Disk.fresh!(tmp_dir)
    credentials = Path.join(tmp_dir, "credentials")
    File.mkdir_p!(credentials)
    File.write!(Path.join(credentials, "stub"), "m23-local-model-key")
    Disk.put_tree!(disk, credentials, "/credentials")
    disk
  end

  defp checkout(vm) do
    {out, vm} = QEMU.iex(vm, "{:ok, src} = Elixos.Candidate.checkout(\"#{@workspace}\")", 180_000)
    assert out =~ @workspace
    vm
  end

  defp assert_think(vm, implementation) do
    {out, vm} = QEMU.iex(vm, "Elixos.Toolset.implementation(\"think\")")
    assert out =~ Regex.compile!("^:#{implementation}\\r?$", "m")
    {_, vm} = QEMU.iex(vm, "workspace = \"/priv/work/check-think\"")
    {_, vm} = QEMU.iex(vm, "s = Elixos.Toolset.Session.new(workspace: workspace)")
    {_, vm} = QEMU.iex(vm, "params = %{\"thoughts\" => \"a private thought\"}")
    {_, vm} = QEMU.iex(vm, "result = Elixos.Toolset.call(\"think\", params, session: s)")
    vm = put_value(vm, "expected", {:ok, @think_result})
    {out, vm} = QEMU.iex(vm, "result == expected")
    assert out =~ ~r/^true$/m
    {out, vm} = QEMU.iex(vm, "Elixos.Toolset.last_run(\"think\").implementation")
    assert out =~ Regex.compile!("^:#{implementation}\\r?$", "m")
    {_, vm} = QEMU.iex(vm, "invalid = Map.put(params, \"extra\", true)")
    {_, vm} = QEMU.iex(vm, "result = Elixos.Toolset.call(\"think\", invalid, session: s)")
    {out, vm} = QEMU.iex(vm, "match?({:error, _}, result)")
    assert out =~ ~r/^true$/m
    vm
  end

  defp build_test_propose(vm) do
    {_, vm} = QEMU.iex(vm, "names = [\"write\", \"read\", \"edit\"]")
    {_, vm} = QEMU.iex(vm, "tools = Map.new(names, &{&1, Elixos.Toolset.last_run(&1)})")
    {_, vm} = QEMU.iex(vm, "tools = Map.reject(tools, fn {_, record} -> is_nil(record) end)")
    {_, vm} = QEMU.iex(vm, "p = %{session: \"m23-agent\", model: \"scripted-m23\", parent: 0}")
    {_, vm} = QEMU.iex(vm, "p = Map.put(p, :tools, tools)")
    {out, vm} = QEMU.iex(vm, "{:ok, c} = Elixos.Candidate.build(src, provenance: p)", 900_000)
    refute out =~ "** ("
    {out, vm} = QEMU.iex(vm, "Elixos.Candidate.test(c)", 900_000)
    assert out =~ ~r/^:ok$/m
    {out, vm} = QEMU.iex(vm, "Elixos.Candidate.propose(c)", 180_000)
    assert out =~ "{:ok, 1}"
    QEMU.await_log(vm, ~r/^elixos-shim: next generation=1\r?$/m)
  end

  defp run_agent(vm, turns, task) do
    vm = put_value(vm, "turns", turns)
    run_prepared_agent(vm, task)
  end

  defp run_prepared_agent(vm, task) do
    {out, vm} = QEMU.iex(vm, "M23.Script.start(4040, turns)")
    assert out =~ ~r/^:ok$/m

    {_, vm} =
      QEMU.iex(vm, "model = [base_url: \"http://127.0.0.1:4040/v1\", model: \"scripted-m23\"]")

    {_, vm} = QEMU.iex(vm, "model = Keyword.put(model, :credential, \"stub\")")
    {_, vm} = QEMU.iex(vm, "opts = [workspace: \"#{@workspace}\", model: model]")
    vm = put_value(vm, "task", task)
    {out, vm} = QEMU.iex(vm, "{:ok, run} = Elixos.Coder.run(task, opts)", 300_000)
    refute out =~ "** ("
    {out, vm} = QEMU.iex(vm, "run.result == \"m23 scripted edits complete\"")
    assert out =~ ~r/^true$/m
    {_, vm} = QEMU.iex(vm, "called = Enum.map(run.transcript, & &1.tool)")
    {out, vm} = QEMU.iex(vm, "Enum.all?(M23.Script.names(turns), &(&1 in called))")
    assert out =~ ~r/^true$/m
    vm
  end

  # Long values travel as short assignments; every call, including each chunk,
  # threads vm instead of leaving unread prompts in the mailbox (ADR-042).
  defp put_value(vm, variable, value) do
    bytes = value |> :erlang.term_to_binary() |> Base.encode64()
    {_, vm} = QEMU.iex(vm, "encoded = \"\"")

    vm =
      bytes
      |> String.codepoints()
      |> Enum.chunk_every(40)
      |> Enum.reduce(vm, fn chunk, vm ->
        {_, vm} = QEMU.iex(vm, "encoded = encoded <> #{inspect(Enum.join(chunk))}")
        vm
      end)

    {_, vm} = QEMU.iex(vm, "#{variable} = :erlang.binary_to_term(Base.decode64!(encoded))")
    vm
  end

  defp power_off(vm) do
    vm = QEMU.send_line(vm, "Elixos.poweroff()")
    {0, vm} = QEMU.expect_exit(vm)
    QEMU.refute_kernel_panic(vm)
    vm
  end

  defp prompt_hash(out) do
    [_, hash] = Regex.run(~r/^"([a-f0-9]{64})"\r?$/m, out)
    hash
  end

  defp improvement_turns do
    # Pure think is a deliberately small port: it removes the QuickBEAM hop
    # without changing OMP's content/details or strict thoughts-only schema.
    # The path is the candidate's choice, not an assumed factory module path.
    source = """
    defmodule Elixos.Toolset.Elixir.Think do
      @behaviour Elixos.Toolset.Implementation
      @impl true
      def call(%{"thoughts" => thoughts} = params, _session)
          when is_binary(thoughts) and map_size(params) == 1 do
        {:ok, %{"content" => [%{"type" => "text", "text" => "------"}],
                "details" => %{"recorded" => true}}}
      end
      def call(_params, _session), do: {:error, :invalid_params}
    end
    """

    [
      {"write",
       %{"path" => "#{@workspace}/lib/elixos/toolset/elixir/think.ex", "content" => source}},
      {"read", %{"path" => "#{@workspace}/config/config.exs"}},
      {:edit_config, "#{@workspace}/config/config.exs"}
    ]
  end

  defp script_module do
    ~S"""
    defmodule M23.Script do
      def names(turns) do
        Enum.map(turns, fn
          {:edit_config, _} -> "edit"
          {name, _} -> name
        end)
      end

      def start(port, turns) do
        {:ok, listen} = :gen_tcp.listen(port, [:binary, active: false, reuseaddr: true])
        spawn(fn -> serve(listen, turns, 1) end)
        :ok
      end

      defp serve(listen, turns, number) do
        {:ok, socket} = :gen_tcp.accept(listen)
        request = receive_request(socket, "")
        {message, finish, remaining} = next(turns, request, number)
        body = :json.encode(%{"choices" => [%{"message" => message,
                                              "finish_reason" => finish}]})
        body = IO.iodata_to_binary(body)
        :ok = :gen_tcp.send(socket, [
          "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: ",
          Integer.to_string(byte_size(body)), "\r\nconnection: close\r\n\r\n", body
        ])
        :gen_tcp.close(socket)
        if remaining == :done do
          :gen_tcp.close(listen)
        else
          serve(listen, remaining, number + 1)
        end
      end

      defp receive_request(socket, bytes) do
        case :binary.split(bytes, "\r\n\r\n") do
          [headers, body] ->
            [_, length] = Regex.run(~r/content-length:\s*(\d+)/i, headers)
            length = String.to_integer(length)
            if byte_size(body) >= length do
              :json.decode(binary_part(body, 0, length))
            else
              {:ok, more} = :gen_tcp.recv(socket, 0, 30_000)
              receive_request(socket, bytes <> more)
            end
          [_] ->
            {:ok, more} = :gen_tcp.recv(socket, 0, 30_000)
            receive_request(socket, bytes <> more)
        end
      end

      defp next([], _request, _number) do
        {%{"role" => "assistant", "content" => "m23 scripted edits complete"},
         "stop", :done}
      end

      defp next([turn | rest], request, number) do
        {name, params} = params(turn, request)
        args = params |> :json.encode() |> IO.iodata_to_binary()
        message = %{"role" => "assistant", "content" => nil, "tool_calls" => [
          %{"id" => "m23-#{number}", "type" => "function",
            "function" => %{"name" => name, "arguments" => args}}
        ]}
        {message, "tool_calls", rest}
      end

      defp params({:edit_config, path}, request) do
        # Still a scripted model: only the four-hex snapshot changes. Take it
        # from the preceding real read result rather than inventing a TAG.
        tool = request["messages"] |> Enum.filter(&(&1["role"] == "tool")) |> List.last()
        content = tool["content"]
        [_, tag] = Regex.run(~r/\[[^\]\n]*config\.exs#([A-Fa-f0-9]{4})\]/, content)
        input = "[#{path}##{tag}]\nPUT >$:\n" <>
          "+\n+config :elixos, Elixos.Toolset,\n" <>
          "+  implementations: %{\"think\" => {:elixir, Elixos.Toolset.Elixir.Think}}\n"
        {"edit", %{"input" => input}}
      end
      defp params({name, params}, _request), do: {name, params}

      def wrap(path, kind) do
        {:defmodule, meta, [name, [do: body]]} = Code.string_to_quoted!(File.read!(path))
        target = if kind == :health, do: :checks, else: :system_prompt
        renamed = if kind == :health, do: :m23_original_checks, else: :m23_original_prompt
        body = Macro.prewalk(body, fn
          {:def, m, [{^target, h, args}, clauses]} ->
            {:def, m, [{renamed, h, args}, clauses]}
          other -> other
        end)
        addition = if kind == :health do
          quote do
            def checks do
              configured = Application.get_env(:elixos, :health_checks)
              if configured do
                configured
              else
                m23_original_checks() ++ [m23_boot_failure: fn ->
                  if File.exists?("/priv/m23-fail-health"),
                    do: {:error, :deliberate_boot_failure}, else: :ok
                end]
              end
            end
          end
        else
          quote do
            def system_prompt do
              m23_original_prompt() <> "\nM23 generation-only edits: never hot-load agent code.\n"
            end
          end
        end
        forms = case body do
          {:__block__, _, forms} -> forms
          form -> [form]
        end
        Macro.to_string({:defmodule, meta, [name, [do: {:__block__, [], forms ++ [addition]}]]}) <> "\n"
      end
    end
    """
  end
end
