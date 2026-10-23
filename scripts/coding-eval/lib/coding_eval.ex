defmodule Elixos.CodingEval do
  @moduledoc "Explicit optional-profile Eval frontend. No boot callback, provisioning or VM environment/cwd mutation."
  @runtime Elixos.CodingEval.Runtime
  @frontend Elixos.CodingEval.Frontend

  @doc "Verify the immutable native profile, then opt into trusted-code Eval under the OS service supervisor."
  def start(trusted: true) do
    identity = verify!()
    unless Application.get_env(:snakepit, :python_executable) == "/opt/oh-my-jido-eval/venv/bin/python3",
      do: raise("Eval Python executable was not configured by the native image profile")
    unless Application.get_env(:snakepit, :python) == [strategy: :system, managed: false],
      do: raise("Eval requires explicitly unmanaged, package-supplied Python")
    if Enum.any?(Application.started_applications(), &(elem(&1, 0) == :snakepit)),
      do: raise("do not start Snakepit.Application; use only the explicit native Eval prerequisites")
    unless Snakepit.GRPCWorker.private_diagnostics_version() == 1,
      do: raise("private Snakepit diagnostics are required")
    {:ok, _} = Application.ensure_all_started(:grpc_server)
    {:ok, _} = Application.ensure_all_started(:grpc)
    result = DynamicSupervisor.start_child(Elixos.Package.Services, {@frontend, []})
    case result do
      {:ok, pid} ->
        {:ok, _} = Snakepit.GRPC.Listener.await_ready()
        {:ok, %{supervisor: pid, runtime: @runtime, identity: identity}}
      {:error, {:already_started, pid}} -> {:ok, %{supervisor: pid, runtime: @runtime, identity: identity}}
      error -> error
    end
  end

  def start(_options), do: {:error, :explicit_trusted_code_opt_in_required}

  @doc "Open through the real Elixos session frontend; capability grants remain explicit."
  def open(options \\ []) do
    if Process.whereis(@frontend),
      do: ElixosHost.open(Keyword.put(options, :runtime, @runtime)),
      else: {:error, :eval_frontend_not_started}
  end

  def stop do
    case Process.whereis(@frontend) do
      nil -> {:error, :eval_frontend_not_started}
      pid -> DynamicSupervisor.terminate_child(Elixos.Package.Services, pid)
    end
  end

  def runtime, do: @runtime

  @doc "Fail closed on missing, empty, foreign or changed source/BEAM/NIF/link receipts."
  def verify! do
    source = json!("/factory/coding/source.json")
    beams = json!("/factory/coding/beams.json")
    build = json!("/factory/coding/eval-build.json")
    unless source["profile"] == "eval" and beams["profile"] == "eval" and build["profile"] == "eval",
      do: raise("this is not the optional Eval factory")
    unless source["source_sha256"] == beams["source_sha256"] and
        source["source_sha256"] == build["source_sha256"] and
        sha256(File.read!("/factory/coding/source.json")) == beams["source_receipt_sha256"],
      do: raise("Eval source identity differs")
    verify_files!("/factory/source/oh_my_jido", source["files"])
    unless pin(source["files"]) == source["source_sha256"], do: raise("Eval source content pin differs")
    for key <- ~w(files applications system_files licenses), do: verify_files!("/factory", beams[key])
    unless pin(beams["system_files"]) == beams["system_source_sha256"], do: raise("Eval assembly source content pin differs")
    unless sha256(File.read!("/factory/coding/inputs/eval.lock")) == build["resolved_lock_sha256"],
      do: raise("Eval resolved dependency lock differs")
    unless sha256(File.read!("/factory/source/os/mix.lock")) == beams["os_lock_sha256"] and
        beams["os_lock_sha256"] == build["os_lock_sha256"], do: raise("Eval OS lock differs")
    unless System.version() == "1.20.4" and beams["elixir"] == System.version() and beams["otp"] == "29.1.1" and
        to_string(:erlang.system_info(:otp_release)) == "29" and
        beams["erts"] == to_string(:erlang.system_info(:version)) and
        beams["architecture"] == to_string(:erlang.system_info(:system_architecture)),
      do: raise("Eval target runtime differs from the builder")
    for app <- ~w(quickbeam snakepit oxc oh_my_jido elixos_host) do
      unless Enum.count(beams["applications"], &(&1["app"] == app)) == 1,
        do: raise("incomplete native Eval application closure")
    end
    for module <- [OhMyJido.Runtime, OhMyJido.Eval.Python, OhMyJido.Eval.Peer, OhMyJido.Eval.PortKernel,
        ElixosHost.Host, __MODULE__, Snakepit.GRPCWorker] do
      {:module, ^module} = Code.ensure_loaded(module)
      {^module, bytes, filename} = :code.get_object_code(module)
      entry = Enum.find(beams["files"], &(&1["path"] == Path.relative_to(to_string(filename), "/factory")))
      unless is_map(entry) and sha256(bytes) == entry["sha256"], do: raise("loaded Eval module differs: #{module}")
      {:ok, [{^module, md5}]} = :beam_lib.md5(bytes)
      unless module.module_info(:md5) == md5, do: raise("active Eval code differs: #{module}")
    end
    native = for path <- ["/factory/coding/native.json", "/opt/oh-my-jido-eval/native.json"] do
      bytes = File.read!(path)
      [expected | _] = File.read!(path <> ".sha256") |> String.split()
      unless expected == sha256(bytes), do: raise("Eval native receipt digest differs")
      receipt = :json.decode(bytes)
      unless receipt["libc"] == "musl" and receipt["architecture"] in ["x86_64", "aarch64"] and
          String.starts_with?(beams["architecture"], receipt["architecture"]),
        do: raise("Eval native artifact architecture/libc differs")
      verify_files!("/", receipt["files"])
      for item <- receipt["elf"] do
        verify_absolute!(item)
        Enum.each(item["needed"], &verify_absolute!/1)
      end
      for link <- receipt["symlinks"] do
        unless File.read_link!(link["path"]) == link["target"], do: raise("Eval native symlink differs")
        if link["resolved"], do: verify_absolute!(link["resolved"])
      end
      if receipt["erts"], do: verify_absolute!(receipt["erts"])
      %{"path" => path, "sha256" => expected}
    end
    Map.take(beams, ~w(source_sha256 system_source_sha256 os_lock_sha256 architecture elixir otp erts))
    |> Map.put("native_receipts", native)
  end

  defp json!(path), do: path |> File.read!() |> :json.decode()
  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
  defp pin(files), do: files |> Enum.sort_by(& &1["path"]) |> Enum.map(&"#{&1["sha256"]}  #{&1["path"]}\n") |> IO.iodata_to_binary() |> sha256()
  defp verify_files!(root, files) when is_list(files) and files != [] do
    for item <- files do
      path = Path.join(root, String.trim_leading(item["path"], "/"))
      unless not (".." in Path.split(item["path"])) and sha256(File.read!(path)) == item["sha256"],
        do: raise("Eval immutable file differs: #{path}")
    end
  end
  defp verify_files!(_root, _files), do: raise("empty Eval inventory")
  defp verify_absolute!(%{"path" => path, "sha256" => digest}) do
    unless Path.type(path) == :absolute and sha256(File.read!(path)) == digest,
      do: raise("Eval native link/artifact differs: #{path}")
  end
end

defmodule Elixos.CodingEval.Frontend do
  @moduledoc false
  use Supervisor

  def start_link(options), do: Supervisor.start_link(__MODULE__, options, name: __MODULE__)

  @impl true
  def init(_options) do
    prerequisites = [
      {Task.Supervisor, name: Snakepit.TaskSupervisor},
      {Snakepit.Bridge.SessionStore, []}, {Snakepit.Bridge.ToolRegistry, []},
      {Snakepit.Pool.Registry, []}, {Snakepit.Pool.ProcessRegistry, []},
      {Snakepit.ETSOwner, []}, {Snakepit.GRPC.Listener, []},
      {Snakepit.Pool.Worker.StarterRegistry, []}, {Snakepit.WorkerProfile.Thread.CapacityStore, []},
      {Snakepit.Pool.WorkerSupervisor, []}, {Snakepit.Worker.LifecycleManager, []}
    ]
    |> Enum.reject(fn {module, options} -> Process.whereis(Keyword.get(options, :name, module)) end)
    |> Enum.map(fn {module, options} = child ->
      Supervisor.child_spec(child, id: Keyword.get(options, :name, module))
    end)
    options = [name: Elixos.CodingEval.Runtime,
      host: {ElixosHost.Host, [approval_tasks: Elixos.CodingEval.Approvals, deployment_enabled: false]},
      storage: {Jido.Storage.File, path: "/priv/oh_my_jido/eval/sessions"},
      eval: Application.fetch_env!(:oh_my_jido, :eval)]
    approvals = Supervisor.child_spec({Task.Supervisor, name: Elixos.CodingEval.Approvals}, id: Elixos.CodingEval.Approvals)
    children = prerequisites ++ [approvals, {OhMyJido.Runtime, options}]
    Supervisor.init(children, strategy: :rest_for_one)
  end
end
