defmodule Elixos.Candidate.Runner do
  @moduledoc false

  alias Elixos.Candidate.Protocol

  def main do
    [request, receipt] = Enum.map(:init.get_plain_arguments(), &to_string/1)
    {operation, args} = request |> File.read!() |> :json.decode() |> Protocol.arguments()
    result = execute(operation, args)
    :ok = File.write(receipt, :json.encode(Protocol.report(operation, result)))
    :erlang.halt(0)
  end

  def execute(operation, args) when operation in [:build, :suite] do
    {:ok, io} = StringIO.open("")
    previous = Process.group_leader()
    Process.group_leader(self(), io)

    result =
      try do
        apply(__MODULE__, operation, args)
      rescue
        error -> {:error, {:exception, Exception.message(error)}}
      catch
        kind, reason -> {:error, {kind, reason}}
      end

    Process.group_leader(self(), previous)
    {_, output} = StringIO.contents(io)
    StringIO.close(io)

    case result do
      {:ok, value} -> {:ok, value, output}
      {:error, reason} -> {:error, reason, output}
    end
  end

  def build(source, build_dir, opts) do
    Mix.start()
    Mix.env(:prod)
    Mix.target(opts.target)
    Mix.SCM.prepend(Elixos.Package.SCM)

    Mix.Project.in_project(
      :elixos_candidate,
      source,
      [build_path: build_dir, deps_path: opts.deps_path, consolidate_protocols: false],
      fn _project ->
        Mix.Task.run("loadconfig")
        isolate_config(opts.runtime_dir)
        link_dependencies(opts.runtime_dir)

        case Mix.Task.run("compile", ["--no-deps-check", "--no-archives-check", "--no-listeners"]) do
          {:error, diagnostics} ->
            {:error, {:compile, Enum.map(diagnostics, & &1.message)}}

          _success ->
            ebin = Mix.Project.compile_path()

            if Path.wildcard(Path.join(ebin, "*.beam")) == [] do
              {:error, :no_build_output}
            else
              {:ok, Map.merge(identity(), %{ebin: ebin, app: Mix.Project.config()[:app]})}
            end
        end
      end
    )
  end

  def suite(source, ebin, files, runtime_dir, target, config_source) do
    with true <- Code.ensure_loaded?(ExUnit),
         true <- files != [] do
      File.cd!(source, fn ->
        Mix.start()
        Mix.env(:test)
        Mix.target(target)
        config = Path.join(config_source, "config/config.exs")

        if File.regular?(config) do
          config
          |> Config.Reader.read!(env: :test, target: target)
          |> Application.put_all_env()
        end

        isolate_config(runtime_dir)
        {:ok, _} = Application.ensure_all_started(:logger)
        load_artifacts(ebin)
        ExUnit.start(autorun: false)

        for file <- Path.wildcard("test/support/**/*.ex"), do: Code.compile_file(file)
        if File.regular?("test/test_helper.exs"), do: Code.require_file("test/test_helper.exs")

        # The child has no inherited shim descriptors. Even a test which starts
        # Elixos.Application sees a host boot and writes only its private state.
        isolate_config(runtime_dir)
        {:ok, _} = Application.ensure_all_started(:elixos)
        configuration = ExUnit.configuration()

        ExUnit.configure(
          autorun: false,
          seed: 0,
          max_cases: 2,
          include: [],
          exclude:
            Enum.uniq(Keyword.get(configuration, :exclude, []) ++ [:qemu, :host_orchestration])
        )

        for file <- files, do: Code.require_file(file)
        result = ExUnit.run()
        executed = result.total - result.excluded - result.skipped
        data = Map.merge(result, identity())

        cond do
          executed == 0 -> {:error, {:empty_suite, data}}
          result.failures > 0 -> {:error, {:tests_failed, data}}
          true -> {:ok, data}
        end
      end)
    else
      false -> {:error, if(files == [], do: :suite_missing, else: :ex_unit_missing)}
    end
  end

  defp load_artifacts(nil), do: :ok

  defp load_artifacts(ebin) do
    Code.prepend_path(ebin)

    for path <- Path.wildcard(Path.join(ebin, "*.beam")) do
      bytes = File.read!(path)
      module = Keyword.fetch!(:beam_lib.info(bytes), :module)
      {:module, ^module} = :code.load_binary(module, String.to_charlist(path), bytes)
    end
  end

  defp link_dependencies(directory) do
    apps = Path.join(directory, "apps")
    File.mkdir_p!(apps)
    # Mix keeps one build tree per environment under the configured
    # build_path (`<build>/prod/lib`): dependencies must be linked there, or
    # it prunes the runtime's own paths and the OS cannot see its deps.
    libs = Path.join(Mix.Project.build_path(), "lib")
    File.mkdir_p!(libs)
    current_app = Mix.Project.config()[:app]

    for ebin <- :code.get_path(),
        app_file <- Path.wildcard(Path.join(to_string(ebin), "*.app")) do
      {:ok, [{:application, app, _properties}]} = :file.consult(String.to_charlist(app_file))
      destination = Path.join(apps, Atom.to_string(app))
      unless File.exists?(destination), do: File.ln_s!(Path.dirname(to_string(ebin)), destination)

      if app != current_app do
        build = Path.join(libs, Atom.to_string(app))
        unless File.exists?(build), do: File.ln_s!(Path.dirname(to_string(ebin)), build)
      end
    end
  end

  defp isolate_config(directory) do
    File.mkdir_p!(directory)
    Application.put_env(:elixos, :priv_dir, directory)
    Application.put_env(:elixos, :agents_dir, Path.join(directory, "agents"))
    Application.put_env(:mnesia, :dir, String.to_charlist(Path.join(directory, "mnesia")))
  end

  defp identity do
    %{
      os_pid: System.pid(),
      node: node(),
      architecture: to_string(:erlang.system_info(:system_architecture))
    }
  end
end
