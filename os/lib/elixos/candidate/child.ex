defmodule Elixos.Candidate.Child do
  @moduledoc false

  alias Elixos.Candidate.Protocol

  @max_stdout 1_048_576
  @max_receipt 1_048_576
  @unset ~w(ELIXOS_GENERATION ELIXOS_MODE ELIXOS_ATTEMPT ELIXOS_CTL_FD ELIXOS_REPLY_FD
            MIX_ENV MIX_TARGET MIX_BUILD_PATH MIX_DEPS_PATH MIX_PATH ERL_FLAGS ERL_AFLAGS
            ELIXIR_ERL_OPTIONS ERL_CRASH_DUMP ERL_CRASH_DUMP_BYTES ERL_CRASH_DUMP_SECONDS ERL_COOKIE
            OPENAI_API_KEY ANTHROPIC_API_KEY AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN)

  def run(operation, args, opts) do
    timeout = Keyword.get(opts, :timeout, 120_000)
    directory = Keyword.fetch!(opts, :evidence_dir)
    request = Path.join(directory, "request.json")
    receipt = Path.join(directory, "receipt.json")

    with :ok <- File.mkdir_p(directory),
         :ok <- File.mkdir_p(Path.join(directory, "home")),
         :ok <- File.write(request, :json.encode(Protocol.request(operation, args))),
         {:ok, executable, launch_args, env} <-
           launch_options(directory, request, receipt, Keyword.get(opts, :env, [])) do
      port =
        Port.open(
          {:spawn_executable, executable},
          [
            :binary,
            :exit_status,
            :use_stdio,
            :hide,
            :stderr_to_stdout,
            {:args, launch_args},
            {:env, env},
            {:cd, directory}
          ]
        )

      deadline = System.monotonic_time(:millisecond) + timeout
      {:os_pid, os_pid} = Port.info(port, :os_pid)

      try do
        case collect(port, deadline, [], 0) do
          {:ok, 0, stdout} ->
            with {:ok, bytes} <- read_receipt(receipt) do
              Protocol.decode_report(bytes, operation, args, stdout, Integer.to_string(os_pid))
            else
              {:error, reason} -> {:error, {:child_receipt_failed, reason}, stdout}
            end

          {:ok, status, stdout} ->
            {:error, {:child_exit, status}, stdout}

          {:error, reason, stdout} ->
            {:error, reason, stdout}
        end
      after
        if Port.info(port), do: Port.close(port)
      end
    else
      {:error, reason} -> {:error, reason, ""}
    end
  rescue
    error -> {:error, {:child_failed, Exception.message(error)}, ""}
  catch
    kind, reason -> {:error, {:child_failed, kind, reason}, ""}
  end

  defp collect(port, deadline, output, size) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, bytes}} ->
        next_size = size + byte_size(bytes)

        if next_size <= @max_stdout do
          collect(port, deadline, [bytes | output], next_size)
        else
          {:error, :child_output_limit, IO.iodata_to_binary(Enum.reverse(output))}
        end

      {^port, {:exit_status, status}} ->
        {:ok, status, IO.iodata_to_binary(Enum.reverse(output))}
    after
      remaining -> {:error, :child_timeout, IO.iodata_to_binary(Enum.reverse(output))}
    end
  end

  defp read_receipt(path) do
    with {:ok, %{type: :regular, size: size}} when size <= @max_receipt <- File.lstat(path),
         {:ok, file} <- :file.open(path, [:read, :raw, :binary]) do
      try do
        with {:ok, bytes} when byte_size(bytes) <= @max_receipt <-
               :file.read(file, @max_receipt + 1),
             :eof <- :file.read(file, 1) do
          {:ok, bytes}
        else
          _ -> {:error, :invalid_child_receipt}
        end
      after
        :file.close(file)
      end
    else
      _ -> {:error, :invalid_child_receipt}
    end
  end

  defp launch_options(directory, request, receipt, extra_env) do
    root = to_string(:code.root_dir())
    bindir = Path.join([root, "erts-#{:erlang.system_info(:version)}", "bin"])
    executable = Path.join(bindir, "erlexec")
    factory = Application.get_env(:elixos, :factory_dir, "/factory")

    boots = [
      Path.join(root, "bin/start_clean"),
      Path.join(factory, "releases/current/start_clean")
    ]

    boot = Enum.find(boots, &File.regular?(&1 <> ".boot"))
    extra = Path.wildcard(Path.join(factory, "lib/{mix,ex_unit}*/ebin"))
    paths = Enum.uniq(Enum.map(:code.get_path(), &to_string/1) ++ extra)

    cond do
      not File.regular?(executable) ->
        {:error, {:erts_missing, executable}}

      is_nil(boot) ->
        {:error, {:clean_boot_missing, boots}}

      true ->
        cookie = Base.encode16(:crypto.strong_rand_bytes(32), case: :lower)

        args =
          [
            "+S",
            "2:2",
            "+A",
            "2",
            "-noshell",
            "-noinput",
            "-setcookie",
            cookie,
            "-boot",
            boot,
            "-boot_var",
            "RELEASE_LIB",
            Path.join(factory, "lib"),
            "-pa"
          ] ++
            paths ++
            ["-user", "Elixir.Elixos.Candidate.ChildIO", "-extra", request, receipt]

        env =
          Enum.map(@unset, &{String.to_charlist(&1), false}) ++
            [
              {~c"ROOTDIR", String.to_charlist(root)},
              {~c"BINDIR", String.to_charlist(bindir)},
              {~c"ELIXIR_ERL_OPTIONS", ~c"+S 2:2 +A 2"},
              {~c"HOME", String.to_charlist(Path.join(directory, "home"))},
              {~c"ERL_CRASH_DUMP", String.to_charlist(Path.join(directory, "erl_crash.dump"))},
              {~c"ERL_CRASH_DUMP_BYTES", ~c"1048576"},
              {~c"ERL_CRASH_DUMP_SECONDS", ~c"30"}
            ] ++
            Enum.map(extra_env, fn {name, value} ->
              {String.to_charlist(name), String.to_charlist(value)}
            end)

        {:ok, executable, args, env}
    end
  end
end
