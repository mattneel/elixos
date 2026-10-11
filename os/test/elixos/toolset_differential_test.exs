defmodule Elixos.ToolsetDifferentialTest do
  @moduledoc """
  M21: replays every recorded non-waiting SDK tool fixture in an isolated
  workspace/session directory and compares exact output or error kind/message,
  plus complete final filesystem effects (ADR-047). Effects execute once;
  no second implementation is invoked to manufacture an expected result.

  Reference note: OMP 18.8.7 is the reference, not another Elixos implementation.
  No per-tool fixtures exist yet. Recording them during M21 is required before
  these scenarios can be reference-validated; a missing tool fails loudly.
  Each fixture records the pin, coverage categories, initial file maps, params,
  exactly one outcome, and final effects. `roots` records distinct absolute
  workspace/session roots: only those literal prefixes are rebound for replay,
  preserving path-bearing SDK output fields rather than dropping them.
  Hashline edit fixtures record ordered read calls and exact outcomes, replayed
  in the same session. File maps use text or %{ "base64" => encoded_bytes } for
  binary media.
  """
  use ExUnit.Case, async: false

  @moduletag milestone: 21
  @moduletag :tmp_dir

  @fixture_root Path.expand("../fixtures/omp", __DIR__)
  @inventory_file Path.join(@fixture_root, "inventory.exs")
  @external_resource @inventory_file
  @reference @inventory_file |> Code.eval_file() |> elem(0)
  @ready_tools @reference.tools
               |> Enum.map(&elem(&1, 0))
               |> Enum.reject(&Map.has_key?(@reference.waits, &1))
  @fixtures Enum.flat_map(@ready_tools, fn tool ->
              @fixture_root
              |> Path.join(tool)
              |> Path.join("*.json")
              |> Path.wildcard()
              |> Enum.filter(&File.regular?/1)
              |> Enum.sort()
              |> Enum.map(&{tool, &1})
            end)
  @missing_tools Enum.reject(@ready_tools, fn tool ->
                   Enum.any?(@fixtures, fn {recorded_tool, _file} -> recorded_tool == tool end)
                 end)

  if @missing_tools != [] do
    test "M21 must record fixtures for every non-waiting SDK factory tool" do
      flunk("M21 must record OMP fixtures; missing tools: " <> Enum.join(@missing_tools, ", "))
    end
  end

  if @fixtures != [] do
    alias Elixos.Toolset
    alias Elixos.Toolset.Session

    @pin Map.take(@reference.reference, [:package, :version, :integrity])
         |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
    @coverage ["nominal", "unicode", "malformed", "numeric_boundaries", "large_payload"]
    @large_payload_bytes 65_536

    test "recorded cases cover Unicode, malformed input, boundaries and large payloads" do
      covered =
        Enum.flat_map(@fixtures, fn {tool, file} ->
          fixture = file |> File.read!() |> :json.decode()
          assert_fixture!(tool, fixture)
          Map.fetch!(fixture, "coverage")
        end)

      for category <- @coverage do
        assert category in covered, "M21 reference fixtures lack #{category} coverage"
      end
    end

    for {tool, file} <- @fixtures do
      @external_resource file
      @tag tool: tool, fixture: file
      test "OMP #{tool}/#{Path.basename(file)} matches outcomes and effects once", ctx do
        fixture = ctx.fixture |> File.read!() |> :json.decode()
        assert_fixture!(ctx.tool, fixture)
        workspace = Path.join(ctx.tmp_dir, "workspace")
        session_dir = Path.join(ctx.tmp_dir, "session")
        fixture = bind_roots!(fixture, workspace, session_dir)
        restore_files!(workspace, Map.fetch!(fixture, "workspace"))
        restore_files!(session_dir, Map.fetch!(fixture, "session_dir"))
        session = Session.new(workspace: workspace, session_dir: session_dir)
        cwd = File.cwd!()
        environment = System.get_env()
        # Stateful SDK tools (for example checkpoint/rewind) may record real
        # prerequisite calls. They run once, in order, in this same session.
        for setup <- Map.get(fixture, "setup_calls", []) do
          assert_result!(
            Toolset.call(Map.fetch!(setup, "tool"), Map.fetch!(setup, "params"),
              session: session
            ),
            setup
          )
        end

        # Reads authorize the recorded hashline TAG and visible lines. Do not
        # rebuild the session or workspace between these reads and the edit.
        for read <- Map.get(fixture, "reads", []) do
          assert_result!(Toolset.call("read", Map.fetch!(read, "params"), session: session), read)
        end

        actual = Toolset.call(ctx.tool, Map.fetch!(fixture, "params"), session: session)
        assert_result!(actual, fixture)
        effects = Map.fetch!(fixture, "effects")
        assert snapshot_files!(workspace) == decode_files!(Map.fetch!(effects, "workspace"))
        assert snapshot_files!(session_dir) == decode_files!(Map.fetch!(effects, "session_dir"))
        assert File.cwd!() == cwd
        assert System.get_env() == environment

        assert %{tool: recorded_tool, implementation: :quickbeam, revision: revision, node: peer} =
                 Toolset.last_run(ctx.tool)

        assert recorded_tool == ctx.tool
        assert is_binary(revision) and byte_size(revision) > 0
        refute peer == node()
      end
    end

    defp assert_fixture!(tool, fixture) do
      assert Map.fetch!(fixture, "reference") == @pin
      assert is_map(Map.fetch!(fixture, "params"))
      assert_outcome!(fixture)
      roots = Map.fetch!(fixture, "roots")
      workspace = Map.fetch!(roots, "workspace")
      session_dir = Map.fetch!(roots, "session_dir")
      assert is_binary(workspace) and Path.type(workspace) == :absolute
      assert is_binary(session_dir) and Path.type(session_dir) == :absolute
      assert Path.expand(workspace) == workspace and workspace != "/"
      assert Path.expand(session_dir) == session_dir and session_dir != "/"
      refute workspace == session_dir
      refute String.starts_with?(workspace, session_dir <> "/")
      refute String.starts_with?(session_dir, workspace <> "/")

      for key <- ["workspace", "session_dir"] do
        assert is_map(Map.fetch!(fixture, key))
        assert is_map(Map.fetch!(Map.fetch!(fixture, "effects"), key))
      end

      coverage = Map.fetch!(fixture, "coverage")
      assert is_list(coverage) and coverage != []
      assert Enum.uniq(coverage) == coverage
      assert Enum.all?(coverage, &(&1 in @coverage))
      inputs = [fixture["params"], fixture["workspace"], fixture["session_dir"]]

      if "nominal" in coverage, do: assert(Map.has_key?(fixture, "output"))
      if "malformed" in coverage, do: assert(Map.has_key?(fixture, "error"))

      if "unicode" in coverage do
        assert Enum.any?(input_strings(inputs), fn value ->
                 String.valid?(value) and String.match?(value, ~r/[^\x00-\x7F]/u)
               end),
               "Unicode coverage needs a non-ASCII input or workspace payload"
      end

      if "large_payload" in coverage do
        assert Enum.any?(input_strings(inputs), &(byte_size(&1) >= @large_payload_bytes)),
               "large-payload coverage needs at least #{@large_payload_bytes} input bytes"
      end

      if "numeric_boundaries" in coverage do
        boundary = Map.fetch!(fixture, "numeric_boundary")
        path = Map.fetch!(boundary, "path")
        assert is_list(path) and path != []
        value = Enum.reduce(path, fixture["params"], &fetch_input!/2)
        limit = Map.fetch!(boundary, "limit")
        assert is_number(value) and is_number(limit)

        case Map.fetch!(boundary, "relation") do
          "below" -> assert value < limit
          "at" -> assert value == limit
          "above" -> assert value > limit
          other -> flunk("invalid numeric-boundary relation: #{inspect(other)}")
        end
      end

      reads = Map.get(fixture, "reads", [])
      assert is_list(reads)

      if tool == "edit" do
        assert Enum.any?(reads, &Map.has_key?(&1, "output")),
               "hashline edit fixtures must record successful prior reads"
      end

      for read <- reads do
        assert %{"path" => path} = Map.fetch!(read, "params")
        assert is_binary(path)
        assert_outcome!(read)
      end

      setup_calls = Map.get(fixture, "setup_calls", [])
      assert is_list(setup_calls)

      for setup <- setup_calls do
        assert Map.fetch!(setup, "tool") in @ready_tools
        assert is_map(Map.fetch!(setup, "params"))
        assert_outcome!(setup)
      end
    end

    defp assert_outcome!(recorded) do
      assert Map.has_key?(recorded, "output") != Map.has_key?(recorded, "error"),
             "a recorded call needs exactly one output or error"

      if Map.has_key?(recorded, "error") do
        assert %{"kind" => kind, "message" => message} = Map.fetch!(recorded, "error")
        assert is_binary(kind) and byte_size(kind) > 0
        assert is_binary(message)
      end
    end

    defp assert_result!(actual, %{"error" => %{"kind" => kind, "message" => message}}) do
      assert {:error, reason} = actual
      assert error_fields(reason) == {kind, message}
    end

    defp assert_result!(actual, %{"output" => output}), do: assert(actual === {:ok, output})

    defp bind_roots!(fixture, workspace, session_dir) do
      roots = Map.fetch!(fixture, "roots")
      bindings = %{roots["workspace"] => workspace, roots["session_dir"] => session_dir}
      pattern = bindings |> Map.keys() |> :binary.compile_pattern()
      bind_strings(fixture, pattern, bindings)
    end

    defp bind_strings(value, pattern, bindings) when is_binary(value),
      do: String.replace(value, pattern, &Map.fetch!(bindings, &1))

    defp bind_strings(value, pattern, bindings) when is_map(value) do
      Map.new(value, fn {key, item} ->
        {bind_strings(key, pattern, bindings), bind_strings(item, pattern, bindings)}
      end)
    end

    defp bind_strings(value, pattern, bindings) when is_list(value),
      do: Enum.map(value, &bind_strings(&1, pattern, bindings))

    defp bind_strings(value, _pattern, _bindings), do: value

    defp restore_files!(root, files) do
      File.mkdir_p!(root)

      for {relative, bytes} <- decode_files!(files) do
        destination = fixture_path!(root, relative)
        File.mkdir_p!(Path.dirname(destination))
        File.write!(destination, bytes)
      end
    end

    defp decode_files!(files) do
      Map.new(files, fn
        {relative, text} when is_binary(text) -> {relative, text}
        {relative, %{"base64" => bytes}} -> {relative, Base.decode64!(bytes)}
        other -> flunk("invalid recorded file: #{inspect(other)}")
      end)
    end

    defp fixture_path!(root, relative) do
      assert is_binary(relative) and Path.type(relative) == :relative
      destination = Path.expand(relative, root)
      assert String.starts_with?(destination, root <> "/")
      assert Path.relative_to(destination, root) == relative
      destination
    end

    defp snapshot_files!(root), do: snapshot_files!(root, root)

    defp snapshot_files!(directory, root) do
      directory
      |> File.ls!()
      |> Enum.flat_map(fn name ->
        path = Path.join(directory, name)

        case File.lstat!(path).type do
          :directory -> Map.to_list(snapshot_files!(path, root))
          :regular -> [{Path.relative_to(path, root), File.read!(path)}]
          type -> flunk("unrecorded filesystem effect #{type} at #{path}")
        end
      end)
      |> Map.new()
    end

    defp input_strings(value) when is_binary(value), do: [value]
    defp input_strings(%{"base64" => bytes}), do: [Base.decode64!(bytes)]

    defp input_strings(value) when is_map(value),
      do: Enum.flat_map(value, fn {key, item} -> input_strings([key, item]) end)

    defp input_strings(value) when is_list(value), do: Enum.flat_map(value, &input_strings/1)
    defp input_strings(_value), do: []

    defp fetch_input!(key, value) when is_map(value), do: Map.fetch!(value, key)

    defp fetch_input!(index, value) when is_list(value) and is_integer(index) and index >= 0,
      do: Enum.fetch!(value, index)

    # Error envelope representation is open; recorded kind/message are not.
    defp error_fields(%{"kind" => kind, "message" => message}),
      do: {normalize_kind(kind), message}

    defp error_fields(%{kind: kind, message: message}), do: {normalize_kind(kind), message}
    defp error_fields({kind, message}), do: {normalize_kind(kind), message}

    defp error_fields(reason),
      do: flunk("tool error lacks recorded kind/message: #{inspect(reason)}")

    defp normalize_kind(kind) when is_atom(kind), do: Atom.to_string(kind)
    defp normalize_kind(kind), do: kind
  end
end
