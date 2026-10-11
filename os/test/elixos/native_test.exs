defmodule Elixos.NativeTest do
  @moduledoc """
  M24 (ADR-050): edit promotion preserves the complete recorded OMP
  differential suite, earns strictly lower concurrent dispatcher p99, can be
  reverted, isolates crashing candidates in the peer, and retains exact
  content-addressed generation pins whose hashes match actual file bytes.

  Reference note: edit results use the pinned OMP fixtures recorded during M21.
  Those fixtures are not present yet. None of the promotion, latency, crash
  isolation or library-pinning acceptance tests has been checked against a
  reference M24 implementation.
  """
  use ExUnit.Case, async: false

  @moduletag milestone: 24
  @moduletag :tmp_dir
  @moduletag timeout: 900_000

  alias Elixos.{Image, Native, Toolset}
  alias Elixos.Image.{Generation, Store}
  alias Elixos.Toolset.{Peer, Session}

  @fixture_glob Path.expand("../fixtures/omp/edit/*.json", __DIR__)
  @inventory Path.expand("../fixtures/omp/inventory.exs", __DIR__)
  @sessions 16
  @runs 4096

  setup %{tmp_dir: tmp_dir} do
    root = Path.join(tmp_dir, "image")
    %{image: open_image!(root), image_root: root}
  end

  test "every recorded edit output and failure is unchanged after promotion", ctx do
    fixtures = fixtures!()
    assert :ok = Native.promote("edit")
    on_exit(fn -> Native.revert("edit") end)

    Enum.each(fixtures, fn {name, fixture} ->
      {session, fixture} = fixture_session!(ctx.tmp_dir, name, fixture)
      prime_reads!(session, fixture)

      assert Toolset.call("edit", fixture["params"], session: session) === expected(fixture),
             "native edit diverged from recorded OMP fixture #{name}"

      assert %{tool: "edit", implementation: :native} = Toolset.last_run("edit")
      assert_effects!(session, fixture)
    end)
  end

  test "reverting changes the next call without changing the pinned environment", ctx do
    {name, fixture} = successful_fixture!()
    environment = {File.cwd!(), System.get_env()}
    assert :ok = Native.promote("edit")
    pins = Native.library_pins()
    on_exit(fn -> Native.revert("edit") end)

    {native_session, native_fixture} = fixture_session!(ctx.tmp_dir, "native-#{name}", fixture)
    prime_reads!(native_session, native_fixture)

    assert Toolset.call("edit", native_fixture["params"], session: native_session) ===
             expected(native_fixture)

    assert %{implementation: :native} = Toolset.last_run("edit")
    assert_effects!(native_session, native_fixture)

    assert :ok = Native.revert("edit")

    {fallback_session, fallback_fixture} =
      fixture_session!(ctx.tmp_dir, "fallback-#{name}", fixture)

    prime_reads!(fallback_session, fallback_fixture)

    assert Toolset.call("edit", fallback_fixture["params"], session: fallback_session) ===
             expected(fallback_fixture)

    assert %{implementation: :quickbeam} = Toolset.last_run("edit")
    assert Native.library_pins() == pins
    assert_effects!(fallback_session, fallback_fixture)
    assert {File.cwd!(), System.get_env()} == environment
  end

  test "native p99 wins with sixteen concurrent sessions including dispatcher overhead", ctx do
    fixture = successful_fixture!() |> elem(1)
    on_exit(fn -> Native.revert("edit") end)

    # 4096 samples leave about 40 observations in the top percentile, not one
    # scheduler outlier. Warmup is discarded, each session has its own tree,
    # and three paired rounds alternate order to limit cache/thermal bias.
    # Compare medians, not the best run. No fixed microsecond budget or invented
    # percentage margin: ADR-050 requires a strict p99 win, not a particular
    # speedup. Preparation/read and reset run outside each edit's timer; the
    # timer encloses the whole Toolset.call, never just the native function.
    rounds =
      Enum.map(1..3, fn round ->
        order = if rem(round, 2) == 1, do: [:quickbeam, :native], else: [:native, :quickbeam]

        Map.new(order, fn implementation ->
          measured =
            Native.benchmark("edit",
              implementation: implementation,
              sessions: @sessions,
              runs: @runs
            )

          assert %{implementation: ^implementation, runs: @runs, p50: p50, p99: p99} = measured
          assert is_number(p50) and p50 >= 0
          assert is_number(p99) and p99 >= p50

          replay_p99 = dispatcher_p99!(ctx.tmp_dir, fixture, implementation, round)
          {implementation, %{reported: p99, replay: replay_p99}}
        end)
      end)

    for measurement <- [:reported, :replay] do
      native = Enum.map(rounds, &get_in(&1, [:native, measurement])) |> median()
      quickbeam = Enum.map(rounds, &get_in(&1, [:quickbeam, measurement])) |> median()

      assert native < quickbeam,
             "#{measurement} dispatcher p99: native=#{native}, QuickBEAM=#{quickbeam}"
    end
  end

  test "a crashing candidate kills only the peer and a fresh peer serves the next call", ctx do
    assert :ok = Native.revert("edit")

    workspace = Path.join(ctx.tmp_dir, "crash-workspace")
    session_dir = Path.join(ctx.tmp_dir, "crash-session")
    File.mkdir_p!(workspace)
    File.mkdir_p!(session_dir)
    File.write!(Path.join(workspace, "probe.txt"), "alive\n")
    session = Session.new(workspace: workspace, session_dir: session_dir)

    {:ok, _} = Toolset.call("read", %{"path" => "probe.txt"}, session: session)
    peer_node = Peer.node()
    peer_init = :rpc.call(peer_node, :erlang, :whereis, [:init])
    assert is_pid(peer_init)
    peer_monitor = Process.monitor(peer_init)
    refute peer_node == node()

    main_node = node()
    main_init = Process.whereis(:init)
    sentinel = start_supervised!({Agent, fn -> :untouched end})
    assert Native.run_in_peer(Elixos.Native.CrashProbe, :crash, []) == {:error, :tool_host_down}
    assert_receive {:DOWN, ^peer_monitor, :process, ^peer_init, _reason}, 120_000
    assert Process.alive?(main_init)
    assert Process.alive?(sentinel)
    assert Agent.get(sentinel, & &1) == :untouched
    assert node() == main_node

    assert {:ok, output} = Toolset.call("read", %{"path" => "probe.txt"}, session: session)
    assert json_text(output) =~ "alive"
    assert %{tool: "read", node: fresh_node} = Toolset.last_run("read")
    refute fresh_node == main_node
    fresh_init = :rpc.call(fresh_node, :erlang, :whereis, [:init])
    assert is_pid(fresh_init)
    refute fresh_init == peer_init
  end

  test "generation pins hash actual library bytes and persist exact target/toolchain", ctx do
    assert :ok = Native.promote("edit")
    on_exit(fn -> Native.revert("edit") end)
    pins = library_pins!()

    assert {:ok, number} = Image.save(ctx.image)
    assert {:ok, manifest} = Image.generation(ctx.image, number)
    assert manifest.native_libraries == pins
    assert {:ok, on_disk} = Generation.read(Path.join(ctx.image_root, "generations"), number)
    assert on_disk.native_libraries == pins

    assert :ok = Image.close(ctx.image)
    reopened = open_image!(ctx.image_root)
    assert {:ok, restored} = Image.generation(reopened, number)
    assert restored.native_libraries == pins
    assert {:ok, _modules} = Image.restore(reopened, number)
    assert library_pins!() == pins
  end

  test "byte-distinct artifacts coexist and each saved generation retains its exact pins", ctx do
    assert :ok = Native.promote("edit")
    on_exit(fn -> Native.revert("edit") end)
    [original | _] = library_pins!()
    bytes = File.read!(original.file)
    source = Path.join(ctx.tmp_dir, "candidate.so")
    opts = [target: original.target, toolchain: original.toolchain]

    File.write!(source, bytes)
    assert {:ok, first} = Native.pin_library(source, opts)
    assert first.sha256 == Store.hash(bytes)
    assert first.target == original.target
    assert first.toolchain == original.toolchain
    first_pins = library_pins!()
    assert first in first_pins
    assert {:ok, first_generation} = Image.save(ctx.image)

    # This is opaque content-addressing/storage acceptance, not proof that a
    # second patch algorithm or a modified artifact is a valid loadable NIF.
    # The original comes from the future real native build; a byte-distinct
    # trailer exercises filename/version retention without executing new code.
    changed_bytes = bytes <> "\nM24 opaque storage variant\n"
    File.write!(source, changed_bytes)
    assert {:ok, second} = Native.pin_library(source, opts)
    assert second.sha256 == Store.hash(changed_bytes)
    refute second.sha256 == first.sha256
    refute second.file == first.file
    refute Path.basename(second.file) == Path.basename(first.file)
    assert File.read!(first.file) == bytes
    assert File.read!(second.file) == changed_bytes
    assert first.target == second.target
    assert first.toolchain == second.toolchain

    second_pins = library_pins!()
    assert first in second_pins
    assert second in second_pins
    assert {:ok, second_generation} = Image.save(ctx.image)
    assert {:ok, first_manifest} = Image.generation(ctx.image, first_generation)
    assert first_manifest.native_libraries == first_pins
    assert {:ok, second_manifest} = Image.generation(ctx.image, second_generation)
    assert second_manifest.native_libraries == second_pins

    assert {:ok, _modules} = Image.restore(ctx.image, first_generation)
    assert library_pins!() == first_pins
    assert File.read!(second.file) == changed_bytes
    assert {:ok, _modules} = Image.restore(ctx.image, second_generation)
    assert library_pins!() == second_pins
  end

  test "restore rejects fabricated and hash-mismatched pins without changing the live pins",
       ctx do
    assert :ok = Native.promote("edit")
    on_exit(fn -> Native.revert("edit") end)
    pins = library_pins!()
    [real | _] = pins
    assert {:ok, number} = Image.save(ctx.image)
    assert {:ok, manifest} = Image.generation(ctx.image, number)
    dir = Path.join(ctx.image_root, "generations")

    missing = %{real | file: Path.join(ctx.tmp_dir, "missing-#{real.sha256}.so")}
    mismatched = %{real | file: Path.join(ctx.tmp_dir, "mismatch-#{real.sha256}.so")}
    File.write!(mismatched.file, File.read!(real.file) <> "\nchanged bytes\n")
    refute Store.hash(File.read!(mismatched.file)) == mismatched.sha256

    Enum.each(Enum.with_index([missing, mismatched], number + 1), fn {invalid, bad_number} ->
      bad_manifest =
        struct!(manifest, number: bad_number, parent: number, native_libraries: [invalid])

      assert :ok = Generation.write(dir, bad_manifest)
      assert {:error, _reason} = Image.restore(ctx.image, bad_number)
      assert Process.alive?(ctx.image)
      assert library_pins!() == pins
    end)

    assert {:ok, _modules} = Image.restore(ctx.image, number)
    assert library_pins!() == pins
  end

  defp fixtures! do
    files = Path.wildcard(@fixture_glob) |> Enum.sort()
    assert files != [], "M21 recorded edit fixtures are missing: #{@fixture_glob}"
    {inventory, _bindings} = Code.eval_file(@inventory)

    Enum.map(files, fn file ->
      fixture = :json.decode(File.read!(file))
      reference = Map.fetch!(fixture, "reference")

      for field <- [:package, :version, :integrity] do
        assert Map.fetch!(reference, Atom.to_string(field)) ==
                 Map.fetch!(inventory.reference, field),
               "#{file} is not recorded from the pinned OMP reference"
      end

      assert is_map(Map.fetch!(fixture, "workspace"))
      assert is_map(Map.fetch!(fixture, "session_dir"))
      roots = Map.fetch!(fixture, "roots")

      for field <- ["workspace", "session_dir"] do
        root = Map.fetch!(roots, field)
        assert is_binary(root) and Path.type(root) == :absolute
      end

      refute roots["workspace"] == roots["session_dir"]
      workspace_root = String.trim_trailing(roots["workspace"], "/")
      session_root = String.trim_trailing(roots["session_dir"], "/")
      refute String.starts_with?(workspace_root, session_root <> "/")
      refute String.starts_with?(session_root, workspace_root <> "/")
      assert is_map(Map.fetch!(fixture, "params"))
      assert Map.has_key?(fixture, "output") != Map.has_key?(fixture, "error")
      effects = Map.fetch!(fixture, "effects")
      assert is_map(Map.fetch!(effects, "workspace"))
      assert is_map(Map.fetch!(effects, "session_dir"))
      assert [_ | _] = reads = Map.fetch!(fixture, "reads")
      assert Enum.any?(reads, &Map.has_key?(&1, "output"))

      Enum.each(reads, fn read ->
        assert is_map(Map.fetch!(read, "params"))
        assert Map.has_key?(read, "output") != Map.has_key?(read, "error")
      end)

      {Path.basename(file, ".json"), fixture}
    end)
  end

  defp successful_fixture! do
    fixtures = Enum.filter(fixtures!(), fn {_name, fixture} -> is_nil(fixture["error"]) end)
    assert fixtures != [], "M21 edit fixtures must include a successful patch application"

    # The largest successful recorded workload exposes the hot path rather
    # than timing a trivial edit dominated by fixed dispatch costs.
    Enum.max_by(fixtures, fn {_name, fixture} ->
      Enum.reduce(decode_files(Map.fetch!(fixture, "workspace")), 0, fn {_path, text}, size ->
        size + byte_size(text)
      end)
    end)
  end

  defp expected(%{"error" => error}) when not is_nil(error), do: {:error, error}
  defp expected(%{"output" => output}), do: {:ok, output}

  defp fixture_session!(root, name, fixture) do
    workspace = Path.join(root, name)
    session_dir = Path.join(root, name <> "-session")
    session = Session.new(workspace: workspace, session_dir: session_dir)
    fixture = bind_fixture(fixture, session)
    restore_workspace!(session, fixture)
    {session, fixture}
  end

  defp restore_workspace!(session, fixture) do
    for {root, initial} <- [
          {session.workspace, Map.fetch!(fixture, "workspace")},
          {session.session_dir, Map.fetch!(fixture, "session_dir")}
        ] do
      File.rm_rf!(root)
      File.mkdir_p!(root)

      Enum.each(decode_files(initial), fn {relative, text} ->
        path = Path.join(root, relative)
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, text)
      end)
    end
  end

  defp prime_reads!(session, fixture) do
    # Replay exact stateful prerequisites and reads in their recorded order:
    # ad hoc calls could change the reference's seen-line/hashline state.
    Enum.each(Map.get(fixture, "setup_calls", []), fn setup ->
      assert Toolset.call(Map.fetch!(setup, "tool"), Map.fetch!(setup, "params"),
               session: session
             ) ===
               expected(setup)
    end)

    Enum.each(Map.fetch!(fixture, "reads"), fn read ->
      assert Toolset.call("read", Map.fetch!(read, "params"), session: session) === expected(read)
    end)
  end

  defp dispatcher_p99!(root, fixture, implementation, round) do
    case implementation do
      :quickbeam -> assert :ok = Native.revert("edit")
      :native -> assert :ok = Native.promote("edit")
    end

    owner = self()
    barrier = make_ref()

    workers =
      Enum.map(1..@sessions, fn index ->
        Task.async(fn ->
          name = "bench-#{round}-#{implementation}-#{index}"
          {session, fixture} = fixture_session!(root, name, fixture)
          restore_workspace!(session, fixture)
          prime_reads!(session, fixture)
          replay_once!(session, fixture)

          Enum.map(1..div(@runs, @sessions), fn sample ->
            restore_workspace!(session, fixture)
            prime_reads!(session, fixture)
            send(owner, {barrier, sample, self()})

            receive do
              {^barrier, ^sample, :go} -> :ok
            end

            replay_once!(session, fixture)
          end)
        end)
      end)

    # Every measured wave starts only after all sixteen sessions finish their
    # untimed reset/read work, so preparation cannot serialize the timed calls.
    Enum.each(1..div(@runs, @sessions), fn sample ->
      Enum.each(workers, fn worker ->
        pid = worker.pid
        assert_receive {^barrier, ^sample, ^pid}, 120_000
      end)

      Enum.each(workers, &send(&1.pid, {barrier, sample, :go}))
    end)

    samples = Enum.flat_map(workers, &Task.await(&1, 300_000)) |> Enum.sort()
    assert length(samples) == @runs
    assert %{tool: "edit", implementation: ^implementation} = Toolset.last_run("edit")
    Enum.at(samples, ceil(@runs * 0.99) - 1)
  end

  defp replay_once!(session, fixture) do
    start = System.monotonic_time(:nanosecond)
    result = Toolset.call("edit", fixture["params"], session: session)
    elapsed = System.monotonic_time(:nanosecond) - start
    assert result === expected(fixture)
    assert_effects!(session, fixture)
    elapsed
  end

  defp assert_effects!(session, fixture) do
    effects = Map.fetch!(fixture, "effects")
    assert directory_snapshot(session.workspace) == decode_files(Map.fetch!(effects, "workspace"))

    assert directory_snapshot(session.session_dir) ==
             decode_files(Map.fetch!(effects, "session_dir"))
  end

  defp decode_files(files) do
    Map.new(files, fn
      {path, text} when is_binary(text) -> {path, text}
      {path, %{"base64" => encoded}} -> {path, Base.decode64!(encoded)}
    end)
  end

  defp bind_fixture(fixture, session) do
    roots = Map.fetch!(fixture, "roots")

    bindings = %{
      Map.fetch!(roots, "workspace") => session.workspace,
      Map.fetch!(roots, "session_dir") => session.session_dir
    }

    relocate(fixture, :binary.compile_pattern(Map.keys(bindings)), bindings)
  end

  defp relocate(value, pattern, bindings) when is_binary(value),
    do: String.replace(value, pattern, &Map.fetch!(bindings, &1))

  defp relocate(value, pattern, bindings) when is_map(value) do
    Map.new(value, fn {key, item} ->
      {relocate(key, pattern, bindings), relocate(item, pattern, bindings)}
    end)
  end

  defp relocate(value, pattern, bindings) when is_list(value),
    do: Enum.map(value, &relocate(&1, pattern, bindings))

  defp relocate(value, _pattern, _bindings), do: value

  defp directory_snapshot(root) do
    root
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.filter(&File.regular?/1)
    |> Map.new(fn path -> {Path.relative_to(path, root), File.read!(path)} end)
  end

  defp library_pins! do
    pins = Native.library_pins()
    assert [_ | _] = pins
    assert length(Enum.uniq_by(pins, & &1.file)) == length(pins)

    Enum.each(pins, fn pin ->
      assert %{file: file, sha256: sha256, target: target, toolchain: toolchain} = pin
      assert is_binary(file) and File.regular?(file)
      assert sha256 == Store.hash(File.read!(file))
      assert String.contains?(Path.basename(file), sha256)
      assert is_binary(target) and String.trim(target) != ""
      assert is_binary(toolchain) and String.trim(toolchain) != ""
    end)

    pins
  end

  defp open_image!(root) do
    assert {:ok, image} = Image.open(root)
    assert Process.register(image, Image)
    on_exit(fn -> if Process.alive?(image), do: Image.close(image) end)
    image
  end

  defp median(values), do: values |> Enum.sort() |> Enum.at(div(length(values), 2))
  defp json_text(value), do: value |> :json.encode() |> IO.iodata_to_binary()
end
