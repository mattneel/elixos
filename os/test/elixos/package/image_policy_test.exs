defmodule Elixos.Package.ImagePolicyTest do
  use ExUnit.Case, async: false

  @moduletag milestone: 27
  @moduletag :tmp_dir

  alias Elixos.Boot.{Env, Restore}
  alias Elixos.Image
  alias Elixos.Image.{Generation, Journal}
  alias Elixos.Package
  alias Elixos.Package.Spec

  defmodule Service do
    use GenServer

    def start_link(app), do: GenServer.start_link(__MODULE__, app, name: app)

    @impl true
    def init(app) do
      state = Application.fetch_env!(app, :state_dir)
      if File.dir?(state), do: {:ok, state}, else: {:stop, {:missing_state_directory, state}}
    end

    @impl true
    def handle_call(:state, _from, state), do: {:reply, state, state}
  end

  setup %{tmp_dir: tmp_dir} do
    previous = Application.fetch_env(:elixos, :priv_dir)
    Application.put_env(:elixos, :priv_dir, Path.join(tmp_dir, "priv"))
    start_supervised!({DynamicSupervisor, name: Elixos.Package.Services, strategy: :one_for_one})
    root = Path.join(tmp_dir, "image")
    {:ok, image} = Image.open(root)
    Process.register(image, Image)

    on_exit(fn ->
      Application.delete_env(:policy_auto_consumer, :state_dir, persistent: true)
      Application.delete_env(:policy_manual_consumer, :state_dir, persistent: true)
      if Process.alive?(image), do: Image.close(image)

      case previous do
        {:ok, value} -> Application.put_env(:elixos, :priv_dir, value)
        :error -> Application.delete_env(:elixos, :priv_dir)
      end
    end)

    %{image: image, root: root}
  end

  test "saved generation restores config and directories before auto services, never manual services",
       %{image: image, root: root} do
    auto = :policy_auto_consumer
    manual = :policy_manual_consumer
    auto_state = Path.join(Package.data_dir(auto), "state")
    manual_state = Path.join(Package.data_dir(manual), "state")

    auto_spec = %Spec{
      services: [{Service, auto}],
      oban: [queues: [auto_jobs: 2]],
      persist: ["state"],
      min_os: "~> 0.1"
    }

    manual_spec = %Spec{
      services: [{Service, manual}],
      oban: [queues: [manual_jobs: 3]],
      persist: ["state"],
      boot: :manual
    }

    :ok =
      Image.record_app(image, auto, "1.0.0", auto_spec, %{elixos: "~> 0.1"}, [
        {auto, [state_dir: auto_state]}
      ])

    :ok =
      Image.record_app(image, manual, "1.0.0", manual_spec, %{}, [
        {manual, [state_dir: manual_state]}
      ])

    assert {:ok, records, :clean} = Journal.read(Path.join(root, "journal.log"))
    assert {_seq, {:app, ^manual, metadata}} = List.last(records)
    assert metadata.boot == :manual
    assert metadata.persist == ["state"]
    assert metadata.config == [{manual, [state_dir: manual_state]}]
    assert metadata.services == manual_spec.services
    assert metadata.oban == manual_spec.oban
    assert {:ok, 1} = Image.save(image)
    :ok = Image.close(image)

    {:ok, reopened} = Image.open(root)
    on_exit(fn -> if Process.alive?(reopened), do: Image.close(reopened) end)
    assert {:ok, 2} = Image.save(reopened)
    assert {:ok, first} = Image.generation(reopened, 1)
    assert {:ok, second} = Image.generation(reopened, 2)
    assert first.boot == second.boot
    refute File.exists?(auto_state)
    refute Process.whereis(auto)
    refute Process.whereis(manual)

    start_supervised!({Elixos.Oban, mode: :rescue})
    env = %Env{generation: 1, mode: :normal, attempt: 1, ctl_fd: 0}
    assert {:ok, restore} = Restore.start_link({reopened, env})
    on_exit(fn -> if Process.alive?(restore), do: GenServer.stop(restore) end)

    assert GenServer.call(auto, :state) == auto_state
    assert Application.fetch_env!(manual, :state_dir) == manual_state
    assert File.dir?(manual_state)
    refute Process.whereis(manual)
  end

  test "state directories survive replacement metadata, removal and a later installation", %{
    image: image
  } do
    app = :policy_auto_consumer
    entry = %{persist: ["state/nested"], config: [], boot: :auto}
    :ok = Package.restore_app!(app, entry)
    state_file = Path.join([Package.data_dir(app), "state", "nested", "kept"])
    File.write!(state_file, "durable app state")
    installed = Package.installed_dir(app)
    File.mkdir_p!(Path.join(installed, "ebin"))
    File.write!(Path.join(installed, "replaceable"), "old code")
    :ok = Image.record_app(image, app, "1.0.0", %Spec{persist: entry.persist}, %{}, [])
    :ok = Image.record_app(image, app, "2.0.0", %Spec{persist: entry.persist}, %{}, [])
    :ok = Package.restore_app!(app, entry)
    assert File.read!(state_file) == "durable app state"

    assert :ok = Package.remove(app)
    refute File.exists?(installed)
    assert File.read!(state_file) == "durable app state"
    :ok = Image.record_app(image, app, "3.0.0", %Spec{persist: entry.persist}, %{}, [])
    :ok = Package.restore_app!(app, entry)
    assert File.read!(state_file) == "durable app state"
  end

  test "persist creation refuses symlinks and traversal without touching their destination", %{
    tmp_dir: tmp_dir
  } do
    app = :policy_auto_consumer
    outside = Path.join(tmp_dir, "outside")
    File.mkdir_p!(outside)
    File.mkdir_p!(Package.data_dir(app))
    File.ln_s!(outside, Path.join(Package.data_dir(app), "escape"))

    assert_raise File.Error, fn ->
      Package.restore_app!(app, %{persist: ["escape/new"], config: []})
    end

    refute File.exists?(Path.join(outside, "new"))

    assert_raise ArgumentError, fn ->
      Package.restore_app!(app, %{persist: ["../outside/new"], config: []})
    end

    refute File.exists?(Path.join(outside, "new"))

    File.rm_rf!(Package.data_dir(app))
    File.ln_s!(outside, Package.data_dir(app))

    assert_raise File.Error, fn ->
      Package.restore_app!(app, %{persist: ["new"], config: []})
    end

    refute File.exists?(Path.join(outside, "new"))
  end

  test "historical journal app formats migrate with explicit automatic-boot defaults", %{
    tmp_dir: tmp_dir
  } do
    root = Path.join(tmp_dir, "legacy")
    File.mkdir_p!(root)
    {:ok, journal} = Journal.open(Path.join(root, "journal.log"))

    {:ok, _} =
      Journal.append(journal, {:app, :legacy_services, "1.0.0", [{Service, :legacy_services}]})

    {:ok, _} = Journal.append(journal, {:app_deps, :legacy_services, %{elixos: "~> 0.1"}})
    declaration = [queues: [legacy_jobs: 2]]
    {:ok, _} = Journal.append(journal, {:app, :legacy_scheduler, "2.0.0", [], %{}, declaration})
    :ok = Journal.close(journal)
    {:ok, image} = Image.open(root)
    on_exit(fn -> if Process.alive?(image), do: Image.close(image) end)
    assert {:ok, 1} = Image.save(image)
    assert {:ok, %Generation{boot: boot}} = Image.generation(image, 1)
    assert {Package, :start_service, [{Service, :legacy_services}]} in boot
    assert {Elixos.Oban, :configure_app!, [:legacy_scheduler, declaration]} in boot

    assert %{app: :legacy_services, version: "1.0.0", deps: %{elixos: "~> 0.1"}} in Image.packages(
             image
           )

    for {Package, :restore_app!, [_app, metadata]} <- boot do
      assert metadata.boot == :auto
      assert metadata.persist == []
      assert metadata.config == []
    end
  end

  test "version-one generation files keep their historical boot list unchanged", %{
    tmp_dir: tmp_dir
  } do
    directory = Path.join(tmp_dir, "old_generations")
    File.mkdir_p!(directory)
    boot = [{Package, :start_service, [{Service, :legacy_services}]}]
    old = %{number: 1, parent: 0, modules: %{}, boot: boot, created_at: nil}

    File.write!(
      Generation.path(directory, 1),
      :erlang.term_to_binary({:elixos_generation, 1, old})
    )

    assert {:ok, %Generation{number: 1, boot: ^boot, provenance: nil}} =
             Generation.read(directory, 1)
  end
end
