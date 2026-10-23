defmodule Elixos.Candidate.Protocol do
  @moduledoc false

  @max_log 262_144
  @counts ~w(total failures skipped excluded)

  def request(:build, [source, build_dir, opts]) do
    %{"version" => 1, "operation" => "build", "source" => source,
      "build_dir" => build_dir, "target" => Atom.to_string(opts.target),
      "deps_path" => opts.deps_path, "runtime_dir" => opts.runtime_dir}
  end

  def request(:suite, [source, ebin, files, runtime, target, config_source]) do
    %{"version" => 1, "operation" => "suite", "source" => source,
      "ebin" => ebin || :null, "files" => files, "runtime_dir" => runtime,
      "target" => Atom.to_string(target), "config_source" => config_source}
  end

  def arguments(%{"version" => 1, "operation" => "build", "source" => source,
                  "build_dir" => build, "target" => target, "deps_path" => deps,
                  "runtime_dir" => runtime}) do
    {:build, [source, build, %{target: target(target), deps_path: deps, runtime_dir: runtime}]}
  end

  def arguments(%{"version" => 1, "operation" => "suite", "source" => source,
                  "ebin" => ebin, "files" => files, "runtime_dir" => runtime,
                  "target" => target, "config_source" => config}) do
    {:suite, [source, if(ebin == :null, do: nil, else: ebin), files, runtime, target(target), config]}
  end

  def report(operation, result) do
    case result do
      {:ok, data, output} ->
        %{"version" => 1, "operation" => Atom.to_string(operation), "status" => "ok",
          "data" => data(operation, data), "output_base64" => output(output)}
      {:error, reason, log} ->
        %{"version" => 1, "operation" => Atom.to_string(operation), "status" => "error",
          "error" => error(reason), "output_base64" => output(log)}
    end
  end

  def decode_report(bytes, operation, args, stdout, os_pid) do
    report = :json.decode(bytes)
    expected = Atom.to_string(operation)

    with %{"version" => 1, "operation" => ^expected, "status" => status,
           "output_base64" => encoded} <- report,
         true <- is_binary(encoded),
         {:ok, log} <- Base.decode64(encoded),
         true <- byte_size(log) <= @max_log do
      case status do
        "ok" ->
          with true <- keys?(report, ~w(version operation status output_base64 data)),
               {:ok, value} <- decode_data(operation, report["data"], args),
               true <- value.os_pid == os_pid,
               true <- operation == :build or (value.failures == 0 and value.total > value.skipped + value.excluded) do
            {:ok, value, stdout <> log}
          else
            _ -> {:error, :invalid_child_receipt, stdout}
          end
        "error" ->
          with true <- keys?(report, ~w(version operation status output_base64 error)),
               {:ok, reason} <- decode_error(report["error"]) do
            {:error, reason, stdout <> log}
          else
            _ -> {:error, :invalid_child_receipt, stdout}
          end
        _ -> {:error, :invalid_child_receipt, stdout}
      end
    else
      _ -> {:error, :invalid_child_receipt, stdout}
    end
  rescue
    _ -> {:error, :invalid_child_receipt, stdout}
  end

  defp target("host"), do: :host
  defp target("elixos"), do: :elixos

  defp output(bytes) do
    bytes |> binary_part(0, min(byte_size(bytes), @max_log)) |> Base.encode64()
  end

  defp identity(data) do
    %{"os_pid" => data.os_pid, "node" => to_string(data.node), "architecture" => data.architecture}
  end

  defp data(:build, data), do: Map.put(identity(data), "ebin", data.ebin)
  defp data(:suite, data), do: stats(data)

  defp stats(data) do
    Map.merge(identity(data), %{"total" => data.total, "failures" => data.failures,
                               "skipped" => data.skipped, "excluded" => data.excluded})
  end

  defp error({:tests_failed, data}), do: %{"kind" => "tests_failed", "stats" => stats(data)}
  defp error({:empty_suite, data}), do: %{"kind" => "empty_suite", "stats" => stats(data)}
  defp error({:exception, message}), do: %{"kind" => "exception", "detail_base64" => output(message)}
  defp error(reason), do: %{"kind" => "operation_error", "detail_base64" => output(inspect(reason))}

  defp decode_data(:build, data, [_source, build_dir, _opts]) do
    with true <- keys?(data, ~w(os_pid node architecture ebin)),
         {:ok, identity} <- decode_identity(data),
         ebin when is_binary(ebin) <- data["ebin"],
         true <- String.starts_with?(Path.expand(ebin), Path.expand(build_dir) <> "/"),
         true <- directories?(build_dir, ebin) do
      {:ok, Map.put(identity, :ebin, ebin)}
    else
      _ -> {:error, :invalid_build_receipt}
    end
  end

  defp decode_data(:suite, data, _args), do: decode_stats(data)

  defp decode_identity(%{"os_pid" => pid, "node" => node, "architecture" => architecture})
       when is_binary(pid) and is_binary(node) and is_binary(architecture) do
    if Regex.match?(~r/\A[0-9]{1,20}\z/, pid) and byte_size(node) <= 256 and
         byte_size(architecture) in 1..256 do
      {:ok, %{os_pid: pid, node: node, architecture: architecture}}
    else
      {:error, :invalid_identity}
    end
  end
  defp decode_identity(_), do: {:error, :invalid_identity}

  defp decode_stats(data) do
    with true <- keys?(data, ~w(os_pid node architecture total failures skipped excluded)),
         {:ok, identity} <- decode_identity(data),
         true <- Enum.all?(@counts, fn name ->
           value = data[name]
           is_integer(value) and value >= 0 and value <= 1_000_000
         end),
         true <- data["failures"] <= data["total"] and data["skipped"] + data["excluded"] <= data["total"] do
      {:ok, Map.merge(identity, %{total: data["total"], failures: data["failures"],
                                 skipped: data["skipped"], excluded: data["excluded"]})}
    else
      _ -> {:error, :invalid_suite_receipt}
    end
  end

  defp decode_error(%{"kind" => kind, "stats" => stats} = error) when kind in ["tests_failed", "empty_suite"] do
    with true <- keys?(error, ~w(kind stats)), {:ok, data} <- decode_stats(stats) do
      case kind do
        "tests_failed" -> {:ok, {:tests_failed, data}}
        "empty_suite" -> {:ok, {:empty_suite, data}}
      end
    end
  end

  defp decode_error(%{"kind" => kind, "detail_base64" => detail} = error)
       when kind in ["exception", "operation_error"] and is_binary(detail) do
    with true <- keys?(error, ~w(kind detail_base64)),
         {:ok, detail} <- Base.decode64(detail),
         true <- byte_size(detail) <= @max_log do
      case kind do
        "exception" -> {:ok, {:exception, detail}}
        "operation_error" -> {:ok, {:child_operation_failed, detail}}
      end
    end
  end
  defp decode_error(_), do: {:error, :invalid_error_receipt}

  defp keys?(map, keys) when is_map(map), do: Enum.sort(Map.keys(map)) == Enum.sort(keys)
  defp keys?(_, _), do: false

  defp directories?(root, directory) do
    relative = Path.relative_to(Path.expand(directory), Path.expand(root))
    paths = Enum.scan(Path.split(relative), Path.expand(root), &Path.join(&2, &1))
    Enum.all?([Path.expand(root) | paths], fn path ->
      match?({:ok, %{type: :directory}}, File.lstat(path))
    end)
  end
end
