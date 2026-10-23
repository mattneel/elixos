defmodule Elixos.CandidateProtectedFixture do
  def value, do: :host
end

defmodule Elixos.CandidateTest do
  use ExUnit.Case, async: false

  @moduletag milestone: 27
  @moduletag :host_orchestration
  @moduletag :tmp_dir
  @moduletag timeout: 120_000

  alias Elixos.{Candidate, Health, Image}
  alias Elixos.Image.{Generation, Store}

  setup %{tmp_dir: tmp} do
    priv = Path.join(tmp, "priv")
    previous = Application.fetch_env(:elixos, :priv_dir)
    Application.put_env(:elixos, :priv_dir, priv)
    {:ok, image} = Image.open(priv)

    control =
      start_supervised!(
        {Elixos.Shim.Control,
         name: nil, sink: {Elixos.Test.ProcessSink, self()}, heartbeat_ms: 60_000}
      )

    assert_receive {:shim_write, "HB\n"}

    on_exit(fn ->
      if Process.alive?(image), do: Image.close(image)
      restore_env(:priv_dir, previous)
    end)

    %{priv: priv, image: image, control: control, source: fixture(tmp)}
  end

  test "checkout copies source without generated output or changing VM state", %{
    source: source,
    tmp_dir: tmp
  } do
    previous = Application.fetch_env(:elixos, :candidate_source)
    Application.put_env(:elixos, :candidate_source, source)
    on_exit(fn -> restore_env(:candidate_source, previous) end)
    File.mkdir_p!(Path.join(source, "_build"))
    File.write!(Path.join(source, "_build/old.beam"), "old")
    cwd = File.cwd!()
    env = System.get_env()

    assert {:ok, checkout} = Candidate.checkout(Path.join(tmp, "checkout"))

    assert File.read!(Path.join(checkout, "lib/sentinel.ex")) ==
             File.read!(Path.join(source, "lib/sentinel.ex"))

    refute File.exists?(Path.join(checkout, "_build"))
    assert Candidate.checkout(Path.join(tmp, "checkout")) == {:error, :exists}
    nested = Path.join(source, "nested-checkout")
    assert Candidate.checkout(nested) == {:error, :nested_source_destination}
    refute File.exists?(nested)
    assert File.cwd!() == cwd
    assert System.get_env() == env
  end

  test "real child build and suite workers never load candidate sentinel in host", context do
    cwd = File.cwd!()
    env = System.get_env()
    refute :code.is_loaded(Elixos.CandidateSentinel)
    assert :code.which(Elixos.CandidateSentinel) == :non_existing

    assert {:ok, candidate} = build(context)
    assert candidate.manifest.number == nil
    assert Map.has_key?(candidate.manifest.modules, Elixos.CandidateSentinel)
    assert Image.generations(context.image) == []
    assert :ok = Candidate.test(candidate)
    assert {:ok, receipt} = Candidate.evidence(candidate, :test)
    assert receipt.result == :ok
    assert receipt.suites.system_suite.total > 0
    assert receipt.suites.toolset_smoke.total > 0
    assert receipt.suites.system_suite.os_pid != System.pid()
    assert receipt.suites.toolset_smoke.os_pid != System.pid()

    assert receipt.suites.system_suite.architecture ==
             to_string(:erlang.system_info(:system_architecture))

    refute :code.is_loaded(Elixos.CandidateSentinel)
    assert :code.which(Elixos.CandidateSentinel) == :non_existing
    assert File.cwd!() == cwd
    assert System.get_env() == env
  end

  test "authored origin messages, fun payloads and raw OTP peer frames cannot reach host processes",
       context do
    test = self()
    previous = Application.fetch_env(:elixos, :candidate_origin_compromised)
    Application.delete_env(:elixos, :candidate_origin_compromised)

    probe =
      spawn_link(fn ->
        receive do
          {:invoke, fun, args} ->
            apply(fun, args)
            send(test, :origin_compromised)
        end
      end)

    Process.register(probe, Elixos.CandidateOriginProbe)

    on_exit(fn ->
      if Process.alive?(probe), do: Process.exit(probe, :kill)
      restore_env(:candidate_origin_compromised, previous)
    end)

    File.write!(Path.join(context.source, "lib/origin_attack.ex"), """
    defmodule Elixos.CandidateOriginAttack do
      @on_load :attack
      def attack do
        payload = {:message, Elixos.CandidateOriginProbe,
          {:invoke, Function.capture(Application, :put_env, 3),
           [:elixos, :candidate_origin_compromised, true]}}
        send(:user, payload)
        bytes = :erlang.term_to_binary(payload)
        framed = <<byte_size(bytes)::32, bytes::binary, :erlang.crc32(bytes)::32>>
        wire = for <<upper::4, lower::4 <- framed>>, into: <<>> do
          <<3::2, upper::4, 3::2, 3::2, lower::4, 3::2>>
        end
        for port <- Port.list(), Port.info(port, :name) == {:name, ~c"0/1"} do
          Port.command(port, wire <> "\\norigin_frame_emitted\\n")
        end
        :ok
      end
    end
    """)

    # Elixir 1.20's compiler never loads (or runs @on_load for) the modules it
    # compiles; candidate code first executes when a suite child loads its
    # beams, so that is where the attack happens.
    assert {:ok, candidate} = build(context)
    assert :ok = Candidate.test(candidate)
    assert {:ok, receipt} = Candidate.evidence(candidate, :test)
    assert receipt.suites.system_suite.output =~ "origin_frame_emitted"
    refute_receive :origin_compromised, 20
    refute Application.get_env(:elixos, :candidate_origin_compromised, false)
    refute :code.is_loaded(Elixos.CandidateOriginAttack)
    assert :code.which(Elixos.CandidateOriginAttack) == :non_existing
  end

  test "counterfeit JSON success and executable payload fields cannot validate a build",
       context do
    File.write!(Path.join(context.source, "lib/counterfeit.ex"), """
    defmodule Elixos.CandidateCounterfeit do
      @on_load :forge
      def forge do
        receipt = :init.get_plain_arguments() |> List.last() |> to_string()
        forged = %{"version" => 1, "operation" => "build", "status" => "ok",
          "output_base64" => "",
          "data" => %{"os_pid" => System.pid(), "node" => "nonode@nohost",
            "architecture" => "forged", "ebin" => "/outside-candidate/ebin"},
          "message" => Base.encode64(:erlang.term_to_binary(
            {:message, Elixos.CandidateOriginProbe,
             {:invoke, Function.capture(Application, :put_env, 3),
              [:elixos, :candidate_origin_compromised, true]}}))}
        File.write!(receipt, :json.encode(forged))
        :erlang.halt(0)
      end
    end
    """)

    assert {:ok, candidate} = build(context)
    assert {:error, failures} = Candidate.test(candidate)

    for suite <- [:system_suite, :toolset_smoke] do
      assert failures[suite] == :invalid_child_receipt
    end

    assert {:error, :not_validated} = Candidate.propose(candidate)
    assert Image.generations(context.image) == []
    refute_receive {:shim_write, "NEXT " <> _}, 20
    refute :code.is_loaded(Elixos.CandidateCounterfeit)
  end

  test "syntax errors fail the real child build without a generation", context do
    File.write!(
      Path.join(context.source, "lib/sentinel.ex"),
      "defmodule Broken do\n def broken(\nend"
    )

    assert {:error, {:build_failed, _, evidence}} = build(context)
    assert File.regular?(Path.join(evidence, "build.term"))
    assert Image.generations(context.image) == []
    refute_receive {:shim_write, "NEXT " <> _}, 20
    refute :code.is_loaded(Broken)
  end

  test "failed system and tool suites both reject proposal and preserve failure evidence",
       context do
    File.write!(Path.join(context.source, "lib/sentinel.ex"), """
    defmodule Elixos.CandidateSentinel do
      def value, do: :broken
    end
    """)

    assert {:ok, candidate} = build(context)
    assert {:error, failures} = Candidate.test(candidate)
    assert Keyword.has_key?(failures, :system_suite)
    assert Keyword.has_key?(failures, :toolset_smoke)
    assert {:error, :not_validated} = Candidate.propose(candidate)
    assert {:ok, %{result: {:error, ^failures}}} = Candidate.evidence(candidate, :test)
    assert Image.generations(context.image) == []
    refute_receive {:shim_write, "NEXT " <> _}, 20
    refute :code.is_loaded(Elixos.CandidateSentinel)
  end

  test "the installed OS source's real portable suite detects a broken core parser", context do
    assert {:ok, source} = Candidate.checkout(Path.join(context.tmp_dir, "os-checkout"))

    File.write!(Path.join(source, "lib/elixos/decimal.ex"), """
    defmodule Elixos.Decimal do
      def parse_u32(_value), do: {:ok, 7}
    end
    """)

    assert {:ok, candidate} =
             build(%{context | source: source}, system_source: Candidate.source_root())

    assert {:error, failures} = Candidate.test(candidate)
    assert Keyword.has_key?(failures, :system_suite)
    assert {:tests_failed, %{failures: failed}} = failures[:system_suite]
    assert failed > 0
    assert {:ok, receipt} = Candidate.evidence(candidate, :test)
    assert receipt.suites.system_suite.output =~ "Elixos.DecimalTest"
    assert Elixos.Decimal.parse_u32("42") == {:ok, 42}
    assert {:error, :not_validated} = Candidate.propose(candidate)
    assert Image.generations(context.image) == []
    refute_receive {:shim_write, "NEXT " <> _}, 20
  end

  test "an empty suite cannot validate a candidate", context do
    File.rm_rf!(Path.join(context.source, "test"))
    assert {:ok, candidate} = build(context)
    assert {:error, failures} = Candidate.test(candidate)
    assert Keyword.has_key?(failures, :system_suite)
    assert Keyword.has_key?(failures, :toolset_smoke)
    assert {:error, :not_validated} = Candidate.propose(candidate)
  end

  test "test receipt binds immutable built bytes and source", context do
    assert {:ok, candidate} = build(context)
    assert :ok = Candidate.test(candidate)
    File.write!(Path.join(candidate.source, "lib/sentinel.ex"), "changed after tests")
    assert {:error, :candidate_changed} = Candidate.propose(candidate)
    assert Image.generations(context.image) == []
    refute_receive {:shim_write, "NEXT " <> _}, 20
  end

  test "durable candidate identity reloads without persisting service handles", context do
    assert {:ok, candidate} = build(context)
    assert :ok = Candidate.test(candidate)

    assert {:ok, reopened} =
             Candidate.open(candidate.id, image: context.image, control: context.control)

    assert reopened.manifest == candidate.manifest
    assert {:ok, metadata} = Elixos.Candidate.Evidence.read(candidate.evidence_dir, "candidate")
    refute Map.has_key?(metadata, :image)
    refute Map.has_key?(metadata, :control)
    assert {:ok, number} = Candidate.propose(reopened)
    assert_receive {:shim_write, line}
    assert line == "NEXT #{number}\n"
    assert Candidate.provenance(number) == {:ok, candidate.manifest.provenance}
    assert Candidate.open("../escape") == {:error, :invalid_candidate}
    refute :code.is_loaded(Elixos.CandidateSentinel)
  end

  test "successful proposal writes normal manifest provenance and NEXT without active journal changes",
       context do
    assert {:ok, parent} =
             Image.save(context.image, boot: [{Elixos.CandidateSentinel, :value, []}])

    assert {:ok, candidate} = build(context, parent: parent)
    assert {:error, :not_validated} = Candidate.propose(candidate)
    assert :ok = Candidate.test(candidate)
    before_modules = Image.modules(context.image)
    assert {:ok, number} = Candidate.propose(candidate)
    assert_receive {:shim_write, line}
    assert line == "NEXT #{number}\n"
    assert {:ok, manifest} = Image.generation(context.image, number)
    assert manifest.parent == parent
    assert manifest.provenance == candidate.manifest.provenance
    assert manifest.boot == [{Elixos.CandidateSentinel, :value, []}]
    assert {:ok, manifest.provenance} == Candidate.provenance(number)
    assert Image.modules(context.image) == before_modules
    refute :code.is_loaded(Elixos.CandidateSentinel)
    assert {:ok, store} = Store.open(Path.join(context.priv, "store"))
    assert {:ok, _beam} = Store.get(store, manifest.modules[Elixos.CandidateSentinel])
    assert File.regular?(Path.join(Candidate.evidence_dir(number), "proposal.term"))
    # NEXT is only a protocol write, not a shim acknowledgment of promotion.
    refute_receive {:shim_write, "COMMIT " <> _}, 20
  end

  test "boot health tests stored generation bytes and evidence survives returning to parent",
       context do
    assert {:ok, parent} = Image.save(context.image)
    assert {:ok, candidate} = build(context, parent: parent)
    assert :ok = Candidate.test(candidate)
    assert {:ok, number} = Candidate.propose(candidate)
    assert_receive {:shim_write, _}
    assert :ok = Health.run_generation(number)
    evidence = Candidate.evidence_dir(number)
    assert File.regular?(Path.join(evidence, "health.term"))
    assert {:ok, []} = Image.restore(context.image, parent)
    assert Candidate.provenance(number) == {:ok, candidate.manifest.provenance}
    assert File.regular?(Path.join(evidence, "proposal.term"))
    assert File.regular?(Path.join(evidence, "health.term"))
    assert File.regular?(Path.join(candidate.evidence_dir, "test.term"))
  end

  test "damaged stored generation bytes fail real boot health and retain evidence", context do
    assert {:ok, candidate} = build(context)
    assert :ok = Candidate.test(candidate)
    assert {:ok, number} = Candidate.propose(candidate)
    assert_receive {:shim_write, _}
    assert {:ok, manifest} = Image.generation(context.image, number)
    assert {:ok, store} = Store.open(Path.join(context.priv, "store"))
    blob = Store.path_for(store, manifest.modules[Elixos.CandidateSentinel])
    File.write!(blob, "isolated fixture damage")

    assert {:error, failures} = Health.run_generation(number)
    assert failures[:system_suite] == {:invalid_generation_blob, Elixos.CandidateSentinel}
    assert failures[:toolset_smoke] == {:invalid_generation_blob, Elixos.CandidateSentinel}
    assert File.regular?(Path.join(Candidate.evidence_dir(number), "health.term"))
    assert File.regular?(Path.join(Candidate.evidence_dir(number), "proposal.term"))
    refute_receive {:shim_write, "COMMIT " <> _}, 20
    refute :code.is_loaded(Elixos.CandidateSentinel)
  end

  test "protected factory module cannot be proposed even after its candidate tests pass",
       context do
    File.write!(Path.join(context.source, "lib/protected.ex"), """
    defmodule Elixos.CandidateProtectedFixture do
      def value, do: :candidate
    end
    """)

    true = :code.stick_mod(Elixos.CandidateProtectedFixture)
    on_exit(fn -> :code.unstick_mod(Elixos.CandidateProtectedFixture) end)

    assert {:ok, candidate} = build(context)
    assert :ok = Candidate.test(candidate)

    assert {:error, {:protected_modules, [Elixos.CandidateProtectedFixture]}} =
             Candidate.propose(candidate)

    assert Image.generations(context.image) == []
    refute_receive {:shim_write, "NEXT " <> _}, 20
  end

  test "tested boot policy, provenance and module contract cannot be replaced after validation",
       context do
    assert {:ok, candidate} = build(context)
    assert :ok = Candidate.test(candidate)
    path = Path.join(candidate.evidence_dir, "candidate.term")
    original = path |> File.read!() |> :erlang.binary_to_term()

    changes = [
      %{
        original
        | settings: %{original.settings | boot: [{Elixos.CandidateSentinel, :value, []}]}
      },
      %{
        original
        | manifest: %{original.manifest | boot: [{Elixos.CandidateSentinel, :value, []}]}
      },
      %{
        original
        | manifest: %{
            original.manifest
            | provenance: %{original.manifest.provenance | model: "unapproved:model"}
          }
      }
    ]

    for changed <- changes do
      File.write!(path, :erlang.term_to_binary(changed))
      assert Candidate.test(candidate) == {:error, :candidate_changed}
      assert Candidate.propose(candidate) == {:error, :candidate_changed}
      assert Image.generations(context.image) == []
      refute_receive {:shim_write, "NEXT " <> _}, 20
    end
  end

  test "verified store bytes alone are not evidence of loaded live-generation code", context do
    assert {:ok, candidate} = build(context)
    assert :ok = Candidate.test(candidate)
    assert {:ok, number} = Candidate.propose(candidate)
    assert_receive {:shim_write, _line}
    refute :code.is_loaded(Elixos.CandidateSentinel)

    assert Candidate.verify_running_generation(number) ==
             {:error, {:running_generation_mismatch, Elixos.CandidateSentinel}}

    # Explicit offline generation validation remains distinct from the live
    # gate automatically required by normal guest Health/AutoCommit.
    assert Health.run_generation(number) == :ok
  end

  defp build(context, opts \\ []) do
    Candidate.build(context.source,
      provenance: %{
        session: "durable-session-42",
        model: "network-free-fixture",
        tools: %{"test" => %{revision: "fixture-revision", implementation: :elixir}},
        parent: Keyword.get(opts, :parent, 0)
      },
      image: context.image,
      control: context.control,
      target: :host,
      system_source: Keyword.get(opts, :system_source, context.source)
    )
  end

  defp fixture(tmp) do
    source = Path.join(tmp, "source/os")
    File.mkdir_p!(Path.join(source, "lib"))
    File.mkdir_p!(Path.join(source, "test/tools"))

    File.write!(Path.join(source, "mix.exs"), """
    defmodule CandidateFixture.MixProject do
      use Mix.Project
      def project, do: [app: :candidate_fixture, version: "0.1.0", elixir: ">= 1.17.0", deps: []]
      def application, do: [extra_applications: [:logger]]
    end
    """)

    File.write!(Path.join(source, "lib/sentinel.ex"), """
    defmodule Elixos.CandidateSentinel do
      def value, do: :child_only
    end
    """)

    File.write!(Path.join(source, "test/sentinel_test.exs"), """
    defmodule CandidateFixture.SystemTest do
      use ExUnit.Case
      @moduletag milestone: 0
      test "runs actual candidate code in another ERTS" do
        assert Elixos.CandidateSentinel.value() == :child_only
      end
    end
    """)

    File.write!(Path.join(source, "test/tools/smoke_test.exs"), """
    defmodule CandidateFixture.ToolTest do
      use ExUnit.Case
      @moduletag milestone: 0
      test "tool result uses candidate implementation" do
        assert Elixos.CandidateSentinel.value() == :child_only
      end
    end
    """)

    source
  end

  defp restore_env(key, {:ok, value}), do: Application.put_env(:elixos, key, value)
  defp restore_env(key, :error), do: Application.delete_env(:elixos, key)
end
