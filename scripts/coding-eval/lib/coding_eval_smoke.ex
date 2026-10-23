defmodule Elixos.CodingEval.Hold do
  @moduledoc false
  use Jido.Action, name: "eval_guest_hold", description: "An observable, cancellable native guest callback", schema: Zoi.object(%{})
  def capability, do: :read
  @impl true
  def run(_parameters, %{oh_my_jido: context} = execution) do
    with :ok <- OhMyJido.Tool.authorize(execution, :read) do
      send(context.metadata.observer, {:eval_guest_hold, context.session_id, self()})
      receive do
        :release -> {:ok, %{released: true}}
      after
        30_000 -> {:error, :guest_callback_not_cancelled}
      end
    end
  end
end

defmodule Elixos.CodingEval.Smoke do
  @moduledoc "Finite, explicit real no-NIC guest evidence. Never a package-build or provider-inference claim."
  alias OhMyJido.{Context, Eval}
  @languages [:elixir, :javascript, :python]

  @doc "Run only in a normal no-NIC guest; writes a new immutable JSON receipt or fails closed."
  def run!(directory, trusted: true) do
    {:ok, %{mode: :normal}} = Elixos.Boot.Env.current()
    {:ok, ["lo"]} = File.ls("/sys/class/net")
    require!(Path.type(directory) == :absolute and String.starts_with?(directory, "/priv/"), :private_evidence_directory_required)
    :ok = File.mkdir(directory)
    cwd = File.cwd!()
    environment = System.get_env()
    owned_frontend = is_nil(Process.whereis(Elixos.CodingEval.Frontend))
    {:ok, %{identity: identity}} = Elixos.CodingEval.start(trusted: true)
    runtime = Elixos.CodingEval.runtime()
    eval = OhMyJido.Runtime.eval(runtime)
    before_workers = Snakepit.Pool.WorkerSupervisor.list_workers() |> Enum.sort()
    session = "target-eval-" <> Integer.to_string(System.unique_integer([:positive]))
    workspace = Path.join(directory, "workspace")
    :ok = File.mkdir(workspace)
    :ok = File.write(Path.join(workspace, "evidence.txt"), "target-native-marker-42\n", [:exclusive])
    context = %Context{session_id: session, workspace: workspace,
      permissions: MapSet.new([:eval, :read]), host: {ElixosHost.Host, []},
      tools: [OhMyJido.Tools.Read, Elixos.CodingEval.Hold],
      metadata: %{eval: eval, observer: self()}}
    try do
      observations = for language <- @languages, do: exercise!(eval, context, language)
      :ok = Eval.close_session(eval, context.session_id)
      :ok = Eval.close_session(eval, context.session_id <> "-other")
      after_workers = Snakepit.Pool.WorkerSupervisor.list_workers() |> Enum.sort()
      require!(before_workers == after_workers, :snakepit_worker_leak)
      require!(File.cwd!() == cwd and System.get_env() == environment, :host_cwd_or_environment_changed)
      require!(Process.alive?(eval), :host_eval_supervisor_lost)
      receipt = %{"format_version" => 1, "result" => "verified", "profile" => "eval",
        "host_pid" => System.pid(), "node" => Atom.to_string(node()), "identity" => identity,
        "observations" => observations, "host_environment_unchanged" => true,
        "host_cwd_unchanged" => true, "snakepit_worker_cleanup" => "confirmed",
        "provider_inference" => false, "sandbox_claim" => false}
      bytes = :json.encode(receipt) |> IO.iodata_to_binary()
      :ok = File.write(Path.join(directory, "verified.json"), bytes, [:exclusive])
      :ok = File.write(Path.join(directory, "verified.json.sha256"), sha256(bytes) <> "  verified.json\n", [:exclusive])
      {:ok, receipt}
    after
      Eval.close_session(eval, context.session_id)
      Eval.close_session(eval, context.session_id <> "-other")
      if owned_frontend, do: Elixos.CodingEval.stop()
    end
  end

  defp exercise!(eval, context, language) do
    sources = sources(language)
    successful!(cell(context, language, sources.first), :first_cell)
    require!(successful!(cell(context, language, "value + 2"), :second_cell).display == "42", :retained_state)
    {:ok, info} = Eval.info(eval, context.session_id, language)
    native = native_identity!(context, language, info)
    other = %{context | session_id: context.session_id <> "-other"}
    require!(result!(cell(other, language, "value")).status == :error, :session_isolation)
    {:ok, other_info} = Eval.info(eval, other.session_id, language)
    other_native = native_identity!(other, language, other_info)
    :ok = Eval.close_session(eval, other.session_id)
    gone!(other_native)
    require!(String.contains?(successful!(cell(context, language, sources.read), :granted_tool).display, "target-native-marker-42"), :actual_file_read)
    denied = %{context | permissions: MapSet.new([:eval])}
    result = result!(cell(denied, language, sources.read))
    require!(result.status == :error and String.contains?(inspect(result.error), "permission_denied"), :denied_tool)
    require!(result!(cell(context, language, sources.error)).status == :error, :language_exception)
    output = result!(cell(context, language, sources.output, output_limit: 128))
    require!(output.truncated and byte_size(output.stdout) + byte_size(output.stderr) + byte_size(output.display) <= 128, :output_quota)
    display = successful!(cell(context, language, sources.display), :display_and_artifact)
    require!(display.displays == ["shown"] and Enum.any?(display.artifacts, &(&1.name == "answer.txt" and &1.data == "42")), :real_artifact)
    deadline = result!(cell(context, language, sources.wait, timeout: 150))
    require!(deadline.status == :timeout and deadline.kernel_state == :invalidated and deadline.effects == :uncertain, :deadline_invalidation)
    invalidated!(eval, context, language)
    gone!(native)
    {:ok, _} = Eval.reset(eval, context, language)
    require!(result!(cell(context, language, "value")).status == :error, :reset_does_not_retain_old_state)
    {:ok, info} = Eval.info(eval, context.session_id, language)
    cancelled_native = native_identity!(context, language, info)
    {task, callback, callback_ref} = hold!(context, language, sources.hold)
    :ok = Eval.interrupt(eval, context.session_id, language)
    cancelled = task |> Task.await(15_000) |> result!()
    require!(cancelled.status == :cancelled and cancelled.kernel_state == :invalidated, :hard_cancellation)
    down!(callback_ref, callback)
    invalidated!(eval, context, language)
    gone!(cancelled_native)
    {:ok, _} = Eval.reset(eval, context, language)
    successful!(cell(context, language, sources.first), :post_cancel_reset)
    {:ok, info} = Eval.info(eval, context.session_id, language)
    crashed_native = native_identity!(context, language, info)
    crash = if language == :javascript do
      {task, callback, monitor} = hold!(context, language, sources.hold)
      :ok = OhMyJido.Process.terminate_group(crashed_native.pid, crashed_native.identity)
      result = Task.await(task, 15_000) |> result!()
      down!(monitor, callback)
      result
    else
      result!(cell(context, language, sources.crash))
    end
    require!(crash.status == :crashed and crash.kernel_state == :invalidated and crash.effects == :uncertain, :actual_native_crash)
    require!(Process.alive?(eval), :host_survives_native_crash)
    invalidated!(eval, context, language)
    gone!(crashed_native)
    {:ok, _} = Eval.reset(eval, context, language)
    require!(result!(cell(context, language, "value")).status == :error, :crash_never_rebinds_state)
    {:ok, info} = Eval.info(eval, context.session_id, language)
    closing_native = native_identity!(context, language, info)
    :ok = Eval.close(eval, context.session_id, language)
    {:error, :not_open} = Eval.info(eval, context.session_id, language)
    gone!(closing_native)
    receive do
      {:eval_guest_hold, _, _} -> raise("guest callback was replayed")
    after
      0 -> :ok
    end
    %{"language" => Atom.to_string(language), "two_retained_cells" => true,
      "independent_session" => true, "actual_read_tool_granted_and_denied" => true,
      "exception" => true, "output_quota_bytes" => 128, "display_and_artifact" => true,
      "timeout_invalidates" => true, "cancel_stops_callback" => true,
      "actual_native_crash" => if(language == :javascript, do: "owned ERTS process-group SIGKILL", else: "worker exit 71"),
      "explicit_reset_required" => true, "close_and_native_process_cleanup" => "confirmed",
      "native_processes" => Enum.map([native, other_native, cancelled_native, crashed_native, closing_native], fn native ->
        %{"pid" => native.pid, "identity" => Map.new(native.identity, fn {key, value} -> {Atom.to_string(key), value} end)}
      end)}
  end

  defp cell(context, language, source, options \\ []) do
    Jido.Exec.run(OhMyJido.Tools.Eval,
      %{language: Atom.to_string(language), source: source,
        timeout: Keyword.get(options, :timeout, 30_000), output_limit: Keyword.get(options, :output_limit, 4096)},
      %{oh_my_jido: context}, max_retries: 0, timeout: 45_000)
  end
  defp result!({:ok, result}) when is_map(result), do: result
  defp result!(_result), do: raise("native unified Eval Action did not return a real result")
  defp successful!(result, step) do
    result = result!(result)
    require!(result.status == :ok, step)
    result
  end
  defp require!(true, _step), do: :ok
  defp require!(_condition, step), do: raise("native Eval smoke failed: #{step}")
  defp invalidated!(eval, context, language) do
    case Eval.execute(eval, context, language, "value") do
      {:error, {:kernel_invalidated, _}} -> :ok
      _ -> raise("native worker state was silently reopened")
    end
  end
  defp hold!(context, language, source) do
    task = Task.Supervisor.async_nolink(Elixos.CodingEval.Approvals, fn -> cell(context, language, source, timeout: 25_000) end)
    session = context.session_id
    receive do
      {:eval_guest_hold, ^session, callback} -> {task, callback, Process.monitor(callback)}
    after
      30_000 -> raise("real guest callback was not reached")
    end
  end
  defp down!(monitor, pid) do
    receive do
      {:DOWN, ^monitor, :process, ^pid, _} -> :ok
    after
      15_000 -> raise("guest callback process survived cancellation/crash")
    end
  end
  defp native_identity!(context, :python, _info) do
    result = successful!(cell(context, :python, "import os, sys, grpc, google.protobuf, numpy\nassert sys.version_info[:2] == (3, 14)\nassert grpc.__version__ == '1.84.0'\nassert google.protobuf.__version__ == '7.35.1'\nassert numpy.__version__ == '2.5.4'\nos.getpid()"), :real_python_runtime)
    identity!(String.to_integer(result.display))
  end
  defp native_identity!(_context, _language, %{worker: worker}) do
    launchers = for port <- Port.list(), Port.info(port, :connected) == {:connected, worker},
      {:os_pid, pid} <- [Port.info(port, :os_pid)], do: pid
    candidates = Enum.flat_map(launchers, &descendants(&1, 0))
    pids = Enum.filter(candidates, fn pid ->
      case File.read("/proc/#{pid}/cmdline") do
        {:ok, bytes} -> String.contains?(bytes, "Elixir.OhMyJido.Eval.PortKernel") and String.contains?(bytes, "beam")
        _ -> false
      end
    end) |> Enum.uniq()
    [pid] = pids
    identity!(pid)
  end
  defp descendants(pid, depth) when depth < 16 do
    children = case File.read("/proc/#{pid}/task/#{pid}/children") do
      {:ok, bytes} -> bytes |> String.split() |> Enum.map(&String.to_integer/1)
      _ -> []
    end
    [pid | Enum.flat_map(children, &descendants(&1, depth + 1))]
  end
  defp descendants(_pid, _depth), do: []
  defp identity!(pid) do
    require!(Integer.to_string(pid) != System.pid(), :worker_is_not_host)
    {:ok, identity} = OhMyJido.Process.capture_identity(pid)
    %{pid: pid, identity: identity}
  end
  defp gone!(native), do: gone!(native, System.monotonic_time(:millisecond) + 10_000)
  defp gone!(%{pid: pid, identity: identity} = native, deadline) do
    gone = case File.read("/proc/#{pid}/stat") do
      {:error, :enoent} -> true
      {:ok, bytes} ->
        Regex.match?(~r/\) Z /, bytes) or
          case OhMyJido.Process.capture_identity(pid) do
            {:ok, current} -> current.start != identity.start
            {:error, reason} when reason in [:enoent, :esrch] -> true
            _ -> false
          end
      _ -> false
    end
    if gone do
      :ok
    else
      require!(System.monotonic_time(:millisecond) < deadline, :native_process_leak)
      receive do after 20 -> gone!(native, deadline) end
    end
  end
  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

  defp sources(:elixir), do: %{
    first: "value = 40", read: "Eval.tool(\"read\", %{\"path\" => \"evidence.txt\"})",
    hold: "Eval.tool(\"eval_guest_hold\", %{})", error: "raise \"target-native-cell-error\"",
    output: "IO.write(String.duplicate(\"x\", 4096))", wait: "receive do :never -> :ok end",
    display: "Eval.display(\"shown\"); Eval.artifact(\"answer.txt\", \"text/plain\", \"42\"); 42", crash: "System.halt(71)"}
  defp sources(:javascript), do: %{
    first: "var value = 40", read: "tools.call('read', {path: 'evidence.txt'})",
    hold: "tools.call('eval_guest_hold', {})", error: "throw new Error('target-native-cell-error')",
    output: "console.log('x'.repeat(4096))", wait: "while (true) {}",
    display: "display('shown'); artifact('answer.txt', 'text/plain', '42'); 42"}
  defp sources(:python), do: %{
    first: "value = 40", read: "tools.call('read', {'path': 'evidence.txt'})",
    hold: "tools.call('eval_guest_hold', {})", error: "raise ValueError('target-native-cell-error')",
    output: "print('x' * 4096)", wait: "while True: pass",
    display: "display('shown')\nartifact('answer.txt', 'text/plain', '42')\n42", crash: "import os\nos._exit(71)"}
end
