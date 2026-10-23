defmodule Elixos.Container.ImageTest do
  use ExUnit.Case, async: false

  @moduletag milestone: 27
  @moduletag :tmp_dir

  alias Elixos.Container.Image, as: ContainerImage
  alias Elixos.Image
  alias Elixos.Image.{Generation, Journal, Store}
  alias Elixos.Package
  alias Elixos.Package.{Repo, Spec}

  @launch %{
    "ELIXOS_RUNTIME" => "container",
    "ELIXOS_GENERATION" => "1",
    "ELIXOS_MODE" => "normal",
    "ELIXOS_ATTEMPT" => "1",
    "ELIXOS_CTL_FD" => "3"
  }

  # Launch variables belong to an OS boot, never to the concurrently running
  # suite VM. Each scenario exercises the public API in a separate real ERTS.
  def run_scenario(name, tmp_dir) do
    root = Path.join(tmp_dir, "priv")
    Application.put_env(:elixos, :priv_dir, root)
    Application.put_env(:elixos, :hex_dir, Path.join(root, "hex"))
    Application.put_env(:elixos, :factory_dir, Path.join(tmp_dir, "factory"))
    {:ok, image} = Image.open(root)
    Process.register(image, Image)

    try do
      apply(__MODULE__, name, [
        %{
          tmp_dir: tmp_dir,
          root: root,
          image: image,
          destination: Path.join(root, "container-export")
        }
      ])
    after
      if Process.alive?(image), do: Image.close(image)
      make_writable(tmp_dir)
    end
  end

  test "exports real installed code and ordinary restore metadata, not private state or source",
       ctx do
    isolated(:deployable_files, ctx)
  end

  def deployable_files(ctx) do
    metadata = %Spec{persist: ["uploads"], boot: :manual}
    install(ctx.image, :export_fixture, "1.2.3", metadata, export_fixture: [port: 4321])
    app = Package.installed_dir(:export_fixture)
    put(Path.join(app, "priv/static/index.html"), "public app resource")
    put(Path.join(app, "priv/bin/helper"), "#!/bin/sh\nexit 0\n")
    File.chmod!(Path.join(app, "priv/bin/helper"), 0o755)
    put(Path.join(app, ".mix/compile.elixir"), "build cache")
    put(Path.join(app, "src/source.ex"), "source workspace")
    put(Path.join(ctx.root, "apps/export_fixture-1.2.3/mix.exs"), "versioned source")
    put(Path.join(ctx.root, "apps/not_installed/ebin/not_installed.beam"), "uninstalled code")

    for relative <- [
          "data/export_fixture/uploads/private",
          "postgres/PG_VERSION",
          "home/.ssh/id_ed25519",
          "home/.ssh/authorized_keys",
          "ssh/ssh_host_ed25519_key",
          "cache/private",
          "crash/evidence",
          "toolchain/bin/cc",
          ".elixos-image/source/mix.exs"
        ] do
      put(Path.join(ctx.root, relative), "private build machine data")
    end

    {:ok, ignored} = Store.open(Path.join(ctx.root, "store"))
    {:ok, private_hash} = Store.put(ignored, "unreferenced private history")

    [{Elixos.Container.ExportFixture, bytecode}] =
      Code.compile_string(
        "defmodule Elixos.Container.ExportFixture, do: def(value, do: :deployed)"
      )

    {:ok, required_hash} = Image.record(ctx.image, Elixos.Container.ExportFixture, bytecode)
    save_committed(ctx)
    original = File.read!(Path.join(ctx.root, "boot.state"))
    manifest = File.read!(Generation.path(Path.join(ctx.root, "generations"), 1))

    assert ContainerImage.export(ctx.destination) ==
             {:ok, %{generation: 1, apps: %{export_fixture: "1.2.3"}}}

    assert File.read!(Path.join(ctx.destination, ".container.boot.state")) == original
    assert File.read!(Generation.path(Path.join(ctx.destination, "generations"), 1)) == manifest

    assert File.read!(Path.join(ctx.destination, "apps/export_fixture/priv/static/index.html")) ==
             "public app resource"

    assert File.read!(Path.join(ctx.root, "boot.state")) == original

    assert Store.get(%Store{root: Path.join(ctx.destination, "store")}, required_hash) ==
             {:ok, bytecode}

    refute File.exists?(
             Store.path_for(%Store{root: Path.join(ctx.destination, "store")}, private_hash)
           )

    assert {:ok, entries, :clean} = Journal.read(Path.join(ctx.destination, "journal.log"))

    assert [
             {1, {:module, Elixos.Container.ExportFixture, ^required_hash}},
             {2, {:app, :export_fixture, entry}},
             {3, {:generation, 1}}
           ] = entries

    assert entry.persist == ["uploads"]
    assert entry.boot == :manual
    assert entry.config == [export_fixture: [port: 4321]]

    assert {:ok, %Generation{boot: [{Package, :restore_app!, [:export_fixture, ^entry]}]}} =
             Generation.read(Path.join(ctx.destination, "generations"), 1)

    assert Enum.sort(File.ls!(ctx.destination)) ==
             [".container.boot.state", "apps", "generations", "journal.log", "store"]

    assert Enum.sort(File.ls!(Path.join(ctx.destination, "apps/export_fixture"))) == [
             "ebin",
             "priv"
           ]

    refute File.exists?(Path.join(ctx.destination, "boot.state"))
    assert mode(ctx.destination) == 0o555
    assert mode(Path.join(ctx.destination, "journal.log")) == 0o444
    assert mode(Path.join(ctx.destination, "apps/export_fixture/priv/bin/helper")) == 0o555

    runtime = Path.join(ctx.tmp_dir, "fresh-runtime")
    File.cp_r!(ctx.destination, runtime)
    make_writable(runtime)
    Application.put_env(:elixos, :priv_dir, runtime)
    {:ok, restored} = Image.open(runtime)

    try do
      assert Image.apps(restored) == %{export_fixture: "1.2.3"}
      :code.purge(Elixos.Container.ExportFixture)
      :code.delete(Elixos.Container.ExportFixture)
      assert {:ok, [Elixos.Container.ExportFixture]} = Image.restore(restored, 1)
      assert apply(Elixos.Container.ExportFixture, :value, []) == :deployed
      assert :ok = Package.restore_app!(:export_fixture, entry)
      assert File.ls!(Package.data_dir(:export_fixture)) == ["uploads"]
      assert File.ls!(Path.join(Package.data_dir(:export_fixture), "uploads")) == []
      assert Application.get_env(:export_fixture, :port) == 4321
      refute File.exists?(Path.join(runtime, "postgres"))
      refute File.exists?(Path.join(runtime, "home"))
    after
      Image.close(restored)
    end
  end

  test "exports only explicitly trusted RSA public repository resources", ctx do
    isolated(:public_repositories, ctx)
  end

  def public_repositories(ctx) do
    install(ctx.image, :export_fixture, "1.0.0")
    mirror = Path.join(ctx.root, "hex/mirrors/team")
    File.mkdir_p!(Path.dirname(mirror))
    File.cp_r!(Path.join(Elixos.Test.Paths.fixture("hex_repo"), "public"), mirror)
    key = File.read!(Path.join(mirror, "public_key"))
    assert :ok = Repo.add(:team, mirror, key: key)
    put(Path.join(mirror, "private_key.pem"), "private signing material")
    put(Path.join(ctx.root, "hex/keys/not_trusted.pub"), "unapproved key")
    put(Path.join(ctx.root, "hex/cache/credentials"), "private cache")
    save_committed(ctx)

    assert {:ok, %{apps: %{export_fixture: "1.0.0"}}} = ContainerImage.export(ctx.destination)
    hex = Path.join(ctx.destination, "hex")
    assert File.read!(Path.join(hex, "keys/team.pub")) == key

    assert File.read!(Path.join(hex, "mirrors/team/names")) ==
             File.read!(Path.join(mirror, "names"))

    assert File.read!(Path.join(hex, "mirrors/team/tarballs/hello_app-0.1.0.tar")) ==
             File.read!(Path.join(mirror, "tarballs/hello_app-0.1.0.tar"))

    assert Enum.sort(File.ls!(Path.join(hex, "mirrors/team"))) ==
             ["names", "packages", "public_key", "tarballs", "versions"]

    assert File.ls!(Path.join(hex, "keys")) == ["team.pub"]
    refute File.exists?(Path.join(hex, "cache"))
  end

  test "refuses non-container, factory, rescue and malformed launch contracts", ctx do
    isolated(:launch_boundaries, ctx)
  end

  def launch_boundaries(ctx) do
    for {changes, expected} <- [
          {%{"ELIXOS_RUNTIME" => "machine"}, :not_container},
          {%{"ELIXOS_GENERATION" => "0"}, :factory_generation},
          {%{"ELIXOS_MODE" => "rescue"}, :not_normal_boot},
          {%{"ELIXOS_GENERATION" => "01"}, {:launch_contract, {:invalid, "ELIXOS_GENERATION"}}}
        ] do
      System.put_env(Map.merge(@launch, changes))
      assert ContainerImage.export(ctx.destination) == {:error, expected}
      refute File.exists?(ctx.destination)
    end

    for {key, _value} <- @launch, do: System.delete_env(key)
    assert ContainerImage.export(ctx.destination) == {:error, :not_container}
  end

  @tag timeout: 10_000
  test "does not export an uncommitted generation or modify original boot state", ctx do
    isolated(:uncommitted, ctx)
  end

  def uncommitted(ctx) do
    install(ctx.image, :export_fixture, "1.0.0")
    assert {:ok, 1} = Image.save(ctx.image)
    state = "current=1\nlast_good=0\nattempts=1\n"
    File.write!(Path.join(ctx.root, "boot.state"), state)

    assert {:error, {:uncommitted_generation, 1, %{current: 1, last_good: 0, attempts: 1}}} =
             ContainerImage.export(ctx.destination)

    assert File.read!(Path.join(ctx.root, "boot.state")) == state
    refute File.exists?(ctx.destination)
  end

  test "accepts an asynchronously persisted COMMIT without manufacturing state", ctx do
    isolated(:asynchronous_commit, ctx)
  end

  def asynchronous_commit(ctx) do
    install(ctx.image, :export_fixture, "1.0.0")
    assert {:ok, 1} = Image.save(ctx.image)
    path = Path.join(ctx.root, "boot.state")
    File.write!(path, "current=1\nlast_good=0\nattempts=1\n")
    task = Task.async(fn -> ContainerImage.export(ctx.destination) end)
    committed = "attempts=0\nlast_good=1\ncurrent=1"
    File.write!(path <> ".committed", committed)
    File.rename!(path <> ".committed", path)

    assert {:ok, %{generation: 1}} = Task.await(task)
    assert File.read!(Path.join(ctx.destination, ".container.boot.state")) == committed
  end

  test "requires current original state and a saved running generation", ctx do
    isolated(:original_state, ctx)
  end

  def original_state(ctx) do
    install(ctx.image, :export_fixture, "1.0.0")
    File.write!(Path.join(ctx.root, "boot.state"), "current=1\nlast_good=1\nattempts=0\n")
    assert {:error, {:generation, 1, :not_found}} = ContainerImage.export(ctx.destination)
    assert {:ok, 1} = Image.save(ctx.image)
    File.write!(Path.join(ctx.root, "boot.state"), "current=2\nlast_good=1\nattempts=0\n")
    assert {:error, {:running_generation_mismatch, 1, 2}} = ContainerImage.export(ctx.destination)

    for state <- [
          "current=1\nlast_good=1\nattempts=00\n",
          "current=1\nlast_good=1\nattempts=0\nextra=0\n",
          "current=1\nlast_good=1\nattempts=0\n\n"
        ] do
      File.write!(Path.join(ctx.root, "boot.state"), state)
      assert {:error, {:boot_state, _reason}} = ContainerImage.export(ctx.destination)
    end

    refute File.exists?(ctx.destination)
  end

  test "never overwrites an existing destination or follows output links", ctx do
    isolated(:destination_safety, ctx)
  end

  def destination_safety(ctx) do
    install(ctx.image, :export_fixture, "1.0.0")
    save_committed(ctx)
    File.mkdir!(ctx.destination)
    put(Path.join(ctx.destination, "keep"), "keep")
    assert {:error, {:destination_exists, _}} = ContainerImage.export(ctx.destination)
    assert File.read!(Path.join(ctx.destination, "keep")) == "keep"

    link = Path.join(ctx.tmp_dir, "output-link")
    File.ln_s!(ctx.tmp_dir, link)

    assert {:error, {:unsafe_artifact, ^link, :symlink}} =
             ContainerImage.export(Path.join(link, "new"))

    assert {:error, {:unsafe_destination, _}} =
             ContainerImage.export(Path.join(ctx.root, "apps/new-export"))

    assert {:error, {:unsafe_destination, _}} =
             ContainerImage.export(ctx.root <> "/../new-export")
  end

  test "fails closed on linked, unreadable or version-mismatched deployed code", ctx do
    isolated(:artifact_safety, ctx)
  end

  def artifact_safety(ctx) do
    install(ctx.image, :export_fixture, "1.0.0")
    save_committed(ctx)
    resource = Path.join(Package.installed_dir(:export_fixture), "priv/linked")
    File.mkdir_p!(Path.dirname(resource))
    secret = Path.join(ctx.root, "private")
    File.write!(secret, "private")
    File.ln_s!(secret, resource)

    assert {:error, {:unsafe_artifact, ^resource, :symlink}} =
             ContainerImage.export(ctx.destination)

    refute File.exists?(Path.join(ctx.destination, ".container.boot.state"))
    make_writable(ctx.destination)
    File.rm_rf!(ctx.destination)
    File.rm!(resource)
    File.write!(resource, "not readable")
    File.chmod!(resource, 0o000)
    assert {:error, {:artifact, ^resource, :eacces}} = ContainerImage.export(ctx.destination)
    refute File.exists?(Path.join(ctx.destination, ".container.boot.state"))
    File.chmod!(resource, 0o644)
    make_writable(ctx.destination)
    File.rm_rf!(ctx.destination)
    File.rm!(resource)
    File.ln!(secret, resource)

    assert {:error, {:unsafe_artifact, ^resource, :hardlink}} =
             ContainerImage.export(ctx.destination)

    refute File.exists?(Path.join(ctx.destination, ".container.boot.state"))
    make_writable(ctx.destination)
    File.rm_rf!(ctx.destination)
    File.rm!(resource)
    app_file(:export_fixture, "9.0.0")

    assert {:error, {:installed_version_mismatch, :export_fixture, "1.0.0", "9.0.0"}} =
             ContainerImage.export(ctx.destination)
  end

  test "refuses private keys hidden in a selected app resource", ctx do
    isolated(:private_resources, ctx)
  end

  def private_resources(ctx) do
    install(ctx.image, :export_fixture, "1.0.0")
    save_committed(ctx)

    for {name, bytes} <- [
          {"id_ed25519", "private SSH identity"},
          {"innocent.txt", "-----BEGIN RSA PRIVATE KEY-----\nnot public\n"}
        ] do
      path = Path.join(Package.installed_dir(:export_fixture), "priv/#{name}")
      put(path, bytes)
      assert {:error, {:private_artifact, ^path}} = ContainerImage.export(ctx.destination)
      refute File.exists?(Path.join(ctx.destination, ".container.boot.state"))
      make_writable(ctx.destination)
      File.rm_rf!(ctx.destination)
      File.rm!(path)
    end
  end

  test "fails on damaged required blobs rather than exporting a broken seed", ctx do
    isolated(:corrupt_blob, ctx)
  end

  def corrupt_blob(ctx) do
    install(ctx.image, :export_fixture, "1.0.0")
    {:ok, hash} = Image.record(ctx.image, Elixos.Container.ExportFixture, "original")
    save_committed(ctx)
    blob = Store.path_for(%Store{root: Path.join(ctx.root, "store")}, hash)
    File.write!(blob, "damaged")
    assert {:error, {:blob, ^hash, :corrupt}} = ContainerImage.export(ctx.destination)
    refute File.exists?(Path.join(ctx.destination, ".container.boot.state"))
  end

  test "rejects unsaved installs and modules but permits identical metadata preparation", ctx do
    isolated(:unsaved_changes, ctx)
  end

  def unsaved_changes(ctx) do
    install(ctx.image, :export_fixture, "1.0.0", %Spec{boot: :manual})
    save_committed(ctx)
    :ok = Image.record_app(ctx.image, :export_fixture, "1.0.0", %Spec{boot: :manual}, %{}, [])
    assert {:ok, _receipt} = ContainerImage.export(ctx.destination)
    make_writable(ctx.destination)
    File.rm_rf!(ctx.destination)
    :ok = Image.record_app(ctx.image, :export_fixture, "2.0.0", %Spec{boot: :manual}, %{}, [])
    assert ContainerImage.export(ctx.destination) == {:error, :unsaved_apps}
    :ok = Image.record_app(ctx.image, :export_fixture, "1.0.0", %Spec{boot: :manual}, %{}, [])
    assert {:ok, _hash} = Image.record(ctx.image, Elixos.Container.UnsavedFixture, "unsaved")
    assert ContainerImage.export(ctx.destination) == {:error, :unsaved_modules}
  end

  test "rejects agent state and boot MFAs outside ordinary package restore", ctx do
    isolated(:non_deployable_boot, ctx)
  end

  def non_deployable_boot(ctx) do
    install(ctx.image, :export_fixture, "1.0.0")

    :ok =
      Image.record_agent(ctx.image, "private-agent", Elixos.Container.AgentFixture,
        memory: "private"
      )

    save_committed(ctx)
    assert ContainerImage.export(ctx.destination) == {:error, :agent_state_not_exportable}
    :ok = Image.forget_agent(ctx.image, "private-agent")
    assert {:ok, 2} = Image.save(ctx.image, boot: [{File, :read!, ["/priv/data/private"]}])
    System.put_env("ELIXOS_GENERATION", "2")
    File.write!(Path.join(ctx.root, "boot.state"), "current=2\nlast_good=2\nattempts=0\n")

    assert {:error, {:non_deployable_boot_entry, {File, :read!, ["/priv/data/private"]}}} =
             ContainerImage.export(ctx.destination)
  end

  test "refuses unsafe public trust instead of silently dropping repositories", ctx do
    isolated(:unsafe_trust, ctx)
  end

  def unsafe_trust(ctx) do
    install(ctx.image, :export_fixture, "1.0.0")
    key = File.read!(Path.join(Elixos.Test.Paths.fixture("hex_repo"), "public/public_key"))
    assert :ok = Repo.add(:team, "https://example.invalid", key: key)
    save_committed(ctx)
    path = Path.join(ctx.root, "hex/repos.exs")
    File.write!(path, "[team: [url: \"https://example.invalid\", key: \"private key\"]]\n")

    assert {:error, {:repository, :team, :bad_public_key}} =
             ContainerImage.export(ctx.destination)

    refute File.exists?(Path.join(ctx.destination, ".container.boot.state"))
  end

  defp isolated(name, %{tmp_dir: tmp_dir}) do
    paths = Enum.flat_map(:code.get_path(), fn path -> ["-pa", to_string(path)] end)

    script = """
    ExUnit.start(autorun: false)
    Code.require_file(#{inspect(Path.expand("../../support/paths.ex", __DIR__))})
    Code.require_file(#{inspect(__ENV__.file)})
    #{inspect(__MODULE__)}.run_scenario(#{inspect(name)}, #{inspect(tmp_dir)})
    """

    {output, status} =
      System.cmd(System.find_executable("elixir"), paths ++ ["-e", script],
        env: Map.to_list(Map.put(@launch, "ELIXIR_ERL_OPTIONS", "+S 2:2 +A 2")),
        stderr_to_stdout: true
      )

    assert status == 0, output
  end

  defp install(image, app, version, spec \\ %Spec{}, config \\ []) do
    app_file(app, version)
    :ok = Image.record_app(image, app, version, spec, %{}, config)
  end

  defp app_file(app, version) do
    props = [vsn: String.to_charlist(version), modules: [], applications: [:kernel, :stdlib]]

    put(
      Path.join(Package.installed_dir(app), "ebin/#{app}.app"),
      :io_lib.format(~c"~p.~n", [{:application, app, props}])
    )
  end

  defp save_committed(ctx) do
    assert {:ok, 1} = Image.save(ctx.image)
    File.write!(Path.join(ctx.root, "boot.state"), "current=1\nlast_good=1\nattempts=0\n")
  end

  defp put(path, bytes) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, bytes)
  end

  defp mode(path), do: Bitwise.band(File.stat!(path).mode, 0o777)

  defp make_writable(path) do
    case File.lstat(path) do
      {:ok, %{type: :directory}} ->
        File.chmod!(path, 0o700)
        for entry <- File.ls!(path), do: make_writable(Path.join(path, entry))

      {:ok, %{type: :regular}} ->
        File.chmod!(path, 0o600)

      _other ->
        :ok
    end
  end
end
