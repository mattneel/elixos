defmodule Elixos.Test.RingLink do
  @moduledoc """
  `elixos-link` (docs/PROTOCOL.md §11) under test (M31). Each helper runs in
  its own unprivileged user and network namespace (`unshare --user
  --map-root-user --net`, IPv6 off so the kernel sends nothing unasked), so it
  can create and address its TUN device without root, and two helpers on one
  region file form a complete link. `cmd/3` and `spawn/2` run programs in a
  helper's namespace through `nsenter`.

  The binary comes from `ELIXOS_LINK` if set, otherwise from `zig build
  -Drelease` into `build/link/` (cached by Zig). Missing namespaces, TUN or
  tools fail the test with the reason; nothing is skipped.
  """

  use GenServer

  @enforce_keys [:pid, :os_pid, :tun]
  defstruct [:pid, :os_pid, :tun]

  @type t :: %__MODULE__{pid: pid(), os_pid: pos_integer(), tun: String.t()}

  @doc "The `elixos-link` binary, built once per test run."
  @spec binary() :: Path.t()
  def binary do
    case :persistent_term.get({__MODULE__, :binary}, nil) do
      nil ->
        path = System.get_env("ELIXOS_LINK") || build()
        :persistent_term.put({__MODULE__, :binary}, path)
        path

      path ->
        path
    end
  end

  defp build do
    zig =
      System.find_executable("zig") ||
        ExUnit.Assertions.flunk("zig is not on PATH; cannot build elixos-link")

    root = Elixos.Test.Paths.repo_root()

    # Without this, `zig build` searches parent directories for a build.zig
    # and may build some other tree.
    File.regular?(Path.join(root, "build.zig")) ||
      ExUnit.Assertions.flunk("no build.zig in #{root}; set ELIXOS_LINK to an elixos-link binary")

    prefix = Elixos.Test.Paths.build("link")

    {output, status} =
      System.cmd(zig, ["build", "-Drelease", "--prefix", prefix],
        cd: root,
        stderr_to_stdout: true
      )

    status == 0 || ExUnit.Assertions.flunk("zig build failed:\n" <> output)
    Path.join([prefix, "bin", "elixos-link"])
  end

  @doc """
  Starts a helper on `region` (a file of `size` bytes) and waits for its
  `up` line. Options: `side:` (`:big`, the default, or `:little`),
  `address:` (`"10.9.0.1/30"`), `tun:` (default `"ring0"`). Killed when the
  test exits.
  """
  @spec start(Path.t(), pos_integer(), keyword()) :: t()
  def start(region, size, opts \\ []) do
    tun = Keyword.get(opts, :tun, "ring0")
    side = opts |> Keyword.get(:side, :big) |> Atom.to_string()

    args =
      ["--region", region, "--size", Integer.to_string(size), "--tun", tun, "--side", side] ++
        if(address = opts[:address], do: ["--address", address], else: [])

    unshare =
      System.find_executable("unshare") ||
        ExUnit.Assertions.flunk("unshare (util-linux) is not on PATH")

    script =
      "echo 1 > /proc/sys/net/ipv6/conf/default/disable_ipv6 && " <>
        "echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6 && exec \"$0\" \"$@\""

    argv = ["--user", "--map-root-user", "--net", "sh", "-c", script, binary() | args]
    {:ok, pid} = GenServer.start(__MODULE__, {unshare, argv})
    ExUnit.Callbacks.on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    os_pid = GenServer.call(pid, :os_pid)
    link = %__MODULE__{pid: pid, os_pid: os_pid, tun: tun}
    await(link, "elixos-link: up #{tun} region #{size} bytes\n", 1, 10_000)
    link
  end

  @doc "Waits until the helper has printed `line` `count` times in all."
  def await(%__MODULE__{pid: pid}, line, count \\ 1, timeout \\ 10_000) do
    case GenServer.call(pid, {:await, line, count}, :infinity) |> wait(timeout) do
      :ok ->
        :ok

      {:exited, status, output} ->
        ExUnit.Assertions.flunk(
          "elixos-link exited #{status} before #{inspect(line)}:\n" <> output
        )

      :timeout ->
        ExUnit.Assertions.flunk(
          "no #{inspect(line)} from elixos-link:\n" <>
            output(%__MODULE__{pid: pid, os_pid: 0, tun: ""})
        )
    end
  end

  defp wait(ref, timeout) do
    receive do
      {^ref, result} -> result
    after
      timeout -> :timeout
    end
  end

  @doc "Everything the helper printed."
  def output(%__MODULE__{pid: pid}), do: GenServer.call(pid, :output)

  @doc "SIGUSR1: waits for the stats line it prints and returns it parsed."
  def stats(%__MODULE__{} = link) do
    count = stats_lines(link) |> length()
    signal(link, "USR1")
    await_stats(link, count + 1)
    link |> stats_lines() |> Enum.at(count)
  end

  @doc "SIGTERM: waits for the exit, asserts status 0 and returns the final stats."
  def stop(%__MODULE__{pid: pid} = link) do
    count = stats_lines(link) |> length()
    signal(link, "TERM")
    {:exited, status, output} = GenServer.call(pid, :await_exit, :infinity) |> wait(10_000)
    status == 0 || ExUnit.Assertions.flunk("elixos-link exited #{status}:\n" <> output)
    lines = stats_lines(link)
    length(lines) == count + 1 || ExUnit.Assertions.flunk("no stats line on exit:\n" <> output)
    List.last(lines)
  end

  @doc """
  SIGSTOP, returning once the helper is stopped (`kill` returns before the
  signal lands), so the test can write frames the helper reads.
  """
  def pause(%__MODULE__{os_pid: os_pid} = link) do
    signal(link, "STOP")
    await_state(os_pid, System.monotonic_time(:millisecond) + 5_000)
  end

  def resume(link), do: signal(link, "CONT")

  # /proc/<pid>/stat: "pid (comm) state ...", comm being elixos-link.
  defp await_state(os_pid, deadline) do
    [_, after_comm] = File.read!("/proc/#{os_pid}/stat") |> String.split(") ", parts: 2)

    cond do
      String.starts_with?(after_comm, "T") ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        ExUnit.Assertions.flunk("elixos-link #{os_pid} did not stop")

      true ->
        Process.sleep(1) && await_state(os_pid, deadline)
    end
  end

  @doc "Every stats line so far, parsed."
  def stats_lines(link) do
    Regex.scan(
      ~r/^elixos-link: stats tx (\d+) rx (\d+) full (\d+) dropped (\d+)\n/m,
      output(link),
      capture: :all_but_first
    )
    |> Enum.map(fn values ->
      [:tx, :rx, :full, :dropped] |> Enum.zip(Enum.map(values, &String.to_integer/1)) |> Map.new()
    end)
  end

  defp await_stats(link, count, deadline \\ System.monotonic_time(:millisecond) + 10_000) do
    cond do
      length(stats_lines(link)) >= count ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        ExUnit.Assertions.flunk("no stats line:\n" <> output(link))

      true ->
        Process.sleep(5) && await_stats(link, count, deadline)
    end
  end

  defp signal(%__MODULE__{os_pid: os_pid}, name) do
    {_, 0} = System.cmd("kill", ["-" <> name, Integer.to_string(os_pid)])
    :ok
  end

  @doc "Runs a command in the helper's namespaces; returns its output, asserting exit 0."
  def cmd(%__MODULE__{} = link, [program | args], timeout \\ 30_000) do
    port = spawn(link, [program | args])
    {output, status} = collect(port, "", timeout)

    status == 0 ||
      ExUnit.Assertions.flunk("#{program} #{inspect(args)} exited #{status}:\n" <> output)

    output
  end

  @doc "Starts a command in the helper's namespaces as a port (stdout and stderr, binary)."
  def spawn(%__MODULE__{os_pid: os_pid}, [program | args]) do
    nsenter =
      System.find_executable("nsenter") ||
        ExUnit.Assertions.flunk("nsenter (util-linux) is not on PATH")

    executable =
      System.find_executable(program) || ExUnit.Assertions.flunk("#{program} is not on PATH")

    argv = [
      "--target",
      Integer.to_string(os_pid),
      "--user",
      "--net",
      "--preserve-credentials",
      executable | args
    ]

    Port.open({:spawn_executable, nsenter}, [:binary, :exit_status, :stderr_to_stdout, args: argv])
  end

  @doc "Collects a port's output until it exits: `{output, status}`."
  def collect(port, acc, timeout) do
    receive do
      {^port, {:data, data}} -> collect(port, acc <> data, timeout)
      {^port, {:exit_status, status}} -> {acc, status}
    after
      timeout -> ExUnit.Assertions.flunk("command timed out; output so far:\n" <> acc)
    end
  end

  ## GenServer

  @impl true
  def init({program, argv}) do
    Process.flag(:trap_exit, true)

    port =
      Port.open({:spawn_executable, program}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: argv
      ])

    {:os_pid, os_pid} = Port.info(port, :os_pid)
    {:ok, %{port: port, os_pid: os_pid, output: "", status: nil, waiting: []}}
  end

  @impl true
  def handle_call(:os_pid, _from, state), do: {:reply, state.os_pid, state}
  def handle_call(:output, _from, state), do: {:reply, state.output, state}

  def handle_call({:await, line, count}, {caller, _} = _from, state) do
    ref = make_ref()

    {:reply, ref,
     answer(%{state | waiting: [{{:line, line, count}, caller, ref} | state.waiting]})}
  end

  def handle_call(:await_exit, {caller, _}, state) do
    ref = make_ref()
    {:reply, ref, answer(%{state | waiting: [{:exit, caller, ref} | state.waiting]})}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state),
    do: {:noreply, answer(%{state | output: state.output <> data})}

  def handle_info({port, {:exit_status, status}}, %{port: port} = state),
    do: {:noreply, answer(%{state | status: status})}

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{status: nil, os_pid: os_pid}) do
    System.cmd("kill", ["-KILL", Integer.to_string(os_pid)])
    :ok
  end

  def terminate(_reason, _state), do: :ok

  defp answer(state) do
    {ready, waiting} =
      Enum.split_with(state.waiting, fn
        {{:line, line, count}, _, _} ->
          occurrences(state.output, line) >= count or state.status != nil

        {:exit, _, _} ->
          state.status != nil
      end)

    for {kind, caller, ref} <- ready do
      result =
        case kind do
          {:line, line, count} ->
            if occurrences(state.output, line) >= count,
              do: :ok,
              else: {:exited, state.status, state.output}

          :exit ->
            {:exited, state.status, state.output}
        end

      send(caller, {ref, result})
    end

    %{state | waiting: waiting}
  end

  defp occurrences(output, line), do: output |> :binary.matches(line) |> length()
end
