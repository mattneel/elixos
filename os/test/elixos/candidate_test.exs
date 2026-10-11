defmodule Elixos.CandidateTest do
  @moduledoc """
  M23: candidate provenance is manifest content, child-ERTS builds never
  hot-load agent code, and health evaluates real, named checks.

  Reference note: none of these acceptance tests has been checked against a
  reference implementation; M23 is not implemented yet.
  """
  use ExUnit.Case, async: false

  @moduletag milestone: 23
  @moduletag :deferred
  @moduletag :tmp_dir
  @moduletag timeout: 1_200_000

  alias Elixos.{Candidate, Health}
  alias Elixos.Image.Generation

  setup %{tmp_dir: tmp_dir} do
    priv = Path.join(tmp_dir, "priv")
    File.mkdir_p!(priv)
    previous_priv = Application.fetch_env(:elixos, :priv_dir)
    previous_checks = Application.fetch_env(:elixos, :health_checks)
    Application.put_env(:elixos, :priv_dir, priv)
    Application.delete_env(:elixos, :health_checks)

    on_exit(fn ->
      restore_env(:priv_dir, previous_priv)
      restore_env(:health_checks, previous_checks)
    end)

    %{priv: priv}
  end

  @tag :host_orchestration
  test "a built manifest records provenance and reads it back unchanged", %{priv: priv} do
    {:ok, source} = Candidate.checkout(Path.join(priv, "work/provenance"))

    provenance = %{
      session: "m23-host-session",
      model: "scripted-m23",
      tools: %{
        "edit" => %{
          tool: "edit",
          implementation: :quickbeam,
          revision: String.duplicate("a", 64),
          node: node()
        }
      },
      parent: 0
    }

    assert {:ok, candidate} = Candidate.build(source, provenance: provenance)
    manifest = Map.fetch!(candidate, :manifest)
    assert Map.fetch!(manifest, :provenance) == provenance
    assert manifest.parent == provenance.parent
    assert {:ok, stored} = Generation.read(Path.join(priv, "generations"), manifest.number)
    assert Map.fetch!(stored, :provenance) == provenance
    assert Candidate.provenance(manifest.number) == {:ok, provenance}
  end

  @tag :host_orchestration
  test "building agent-written code never loads it in the calling VM", %{priv: priv} do
    {:ok, source} = Candidate.checkout(Path.join(priv, "work/no-hot-load"))
    name = "Elixos.M23Unloaded#{System.unique_integer([:positive])}"
    module = String.to_atom("Elixir." <> name)
    file = Path.join(source, "lib/m23_unloaded.ex")
    File.mkdir_p!(Path.dirname(file))
    File.write!(file, "defmodule #{name} do\n  def value, do: :child_only\nend\n")

    assert :code.is_loaded(module) == false
    assert :code.which(module) == :non_existing

    assert {:ok, candidate} =
             Candidate.build(source,
               provenance: %{session: "no-hot-load", model: "scripted-m23", tools: %{}, parent: 0}
             )

    assert Map.has_key?(Map.fetch!(candidate, :manifest).modules, module)
    assert :ok = Candidate.test(candidate)
    assert :code.is_loaded(module) == false
    assert :code.which(module) == :non_existing
  end

  @tag :host_orchestration
  test "the real system suite rejects a candidate with a broken decimal parser", %{priv: priv} do
    {:ok, source} = Candidate.checkout(Path.join(priv, "work/broken-system"))

    File.write!(
      Path.join(source, "lib/elixos/decimal.ex"),
      "defmodule Elixos.Decimal do\n  def parse_u32(_), do: {:ok, 7}\nend\n"
    )

    assert {:ok, candidate} =
             Candidate.build(source,
               provenance: %{
                 session: "broken-system",
                 model: "scripted-m23",
                 tools: %{},
                 parent: 0
               }
             )

    assert {:error, failures} = Candidate.test(candidate)
    assert Keyword.has_key?(failures, :system_suite)
    assert Elixos.Decimal.parse_u32("42") == {:ok, 42}
  end

  @tag :host_orchestration
  test "the real tool smoke rejects a selected implementation with the wrong SDK result",
       %{priv: priv} do
    {:ok, source} = Candidate.checkout(Path.join(priv, "work/broken-tool"))

    File.write!(Path.join(source, "lib/m23_broken_think.ex"), """
    defmodule Elixos.M23BrokenThink do
      @behaviour Elixos.Toolset.Implementation
      @impl true
      def call(_params, _session) do
        {:ok, %{"content" => [%{"type" => "text", "text" => "wrong scratchpad result"}],
                "details" => %{"recorded" => true}}}
      end
    end
    """)

    File.write!(
      Path.join(source, "config/config.exs"),
      """

      config :elixos, Elixos.Toolset,
        implementations: %{"think" => {:elixir, Elixos.M23BrokenThink}}
      """,
      [:append]
    )

    assert {:ok, candidate} =
             Candidate.build(source,
               provenance: %{session: "broken-tool", model: "scripted-m23", tools: %{}, parent: 0}
             )

    assert {:error, failures} = Candidate.test(candidate)
    assert Keyword.has_key?(failures, :toolset_smoke)
  end

  test "health runs every check and reports each failing check by name" do
    caller = self()

    Application.put_env(:elixos, :health_checks,
      system_suite: fn ->
        send(caller, :suite_ran)
        {:error, {:test_failed, "self_modification"}}
      end,
      liveness: fn ->
        send(caller, :liveness_ran)
        :ok
      end,
      toolset_smoke: fn ->
        send(caller, :smoke_ran)
        {:error, {:fixture_mismatch, "think"}}
      end
    )

    assert Health.run() ==
             {:error,
              [
                system_suite: {:test_failed, "self_modification"},
                toolset_smoke: {:fixture_mismatch, "think"}
              ]}

    assert_received :suite_ran
    assert_received :liveness_ran
    assert_received :smoke_ran
  end

  test "health succeeds only when every named check succeeds" do
    Application.put_env(:elixos, :health_checks,
      system_suite: fn -> :ok end,
      toolset_smoke: fn -> :ok end
    )

    assert Health.run() == :ok
  end

  test "evidence directories use persistent storage and distinguish generation boundaries", %{
    priv: priv
  } do
    for generation <- [0, 1, 23, 4_294_967_295] do
      assert Candidate.evidence_dir(generation) ==
               Path.join([priv, "evidence", Integer.to_string(generation)])
    end
  end

  defp restore_env(key, {:ok, value}), do: Application.put_env(:elixos, key, value)
  defp restore_env(key, :error), do: Application.delete_env(:elixos, key)
end
