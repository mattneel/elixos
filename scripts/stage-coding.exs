defmodule Elixos.FactoryCodingSource do
  @moduledoc false
  @inputs ~w(mix.exs mix.lock lib priv config vendor/jido vendor/req_llm examples/elixos)
  @excluded ~w(_build deps .git .expert tmp erl_crash.dump .venv __pycache__ .pytest_cache)

  def main([operation, source]) when operation in ["pin", "pin-eval"] do
    {receipt, _files} = inventory(Path.expand(source), operation == "pin-eval")
    IO.puts(receipt["source_sha256"])
  end

  def main([operation, source, destination, expected]) when operation in ["stage", "stage-eval"] do
    source = Path.expand(source)
    {receipt, files} = inventory(source, operation == "stage-eval")
    unless expected =~ ~r/\A[0-9a-f]{64}\z/ and receipt["source_sha256"] == expected do
      raise "coding source pin differs; review the checkout and explicitly select its new pin"
    end
    destination = Path.expand(destination)
    if File.exists?(destination), do: raise("coding staging destination already exists")
    root = Path.join(destination, "oh_my_jido")
    File.mkdir_p!(root)
    for %{path: relative, bytes: bytes, sha256: digest} <- files do
      content = File.read!(Path.join(source, relative))
      unless byte_size(content) == bytes and sha256(content) == digest,
        do: raise("coding source changed during staging: #{relative}")
      target = Path.join(root, relative)
      File.mkdir_p!(Path.dirname(target))
      File.write!(target, content, [:exclusive])
    end
    File.write!(Path.join(destination, "source.json"), :json.encode(receipt), [:exclusive])
  end

  def main(_), do: raise("usage: elixir scripts/stage-coding.exs pin[-eval] SOURCE | stage[-eval] SOURCE DEST SHA256")

  def inventory(source, eval? \\ false) do
    snakepit? = eval? or File.dir?(Path.join(source, "vendor/snakepit"))
    inputs = if snakepit?, do: @inputs ++ ["vendor/snakepit"], else: @inputs
    files = Enum.flat_map(inputs, &files(source, &1))
    notices = for name <- ~w(LICENSE NOTICE README.md), File.regular?(Path.join(source, name)),
      do: file(source, name)
    files = Enum.sort_by(files ++ notices, & &1.path)
    for package <- ~w(jido req_llm) do
      receipt = Path.join([source, "vendor", package, "UPSTREAM.json"]) |> File.read!() |> :json.decode()
      unless receipt["package"] == package and receipt["license"] == "Apache-2.0",
        do: raise("missing licensed upstream identity for #{package}")
      unless File.regular?(Path.join([source, "vendor", package, "LICENSE"])),
        do: raise("missing upstream license for #{package}")
    end
    if snakepit? do
      receipt = Path.join([source, "vendor/snakepit/UPSTREAM.json"]) |> File.read!() |> :json.decode()
      unless receipt["package"] == "snakepit" and receipt["version"] == "0.14.0" and receipt["license"] == "MIT",
        do: raise("missing licensed Snakepit 0.14.0 private-diagnostics source identity")
      unless File.regular?(Path.join(source, "vendor/snakepit/LICENSE")),
        do: raise("missing Snakepit MIT license")
    end
    pin = Enum.map(files, &"#{&1.sha256}  #{&1.path}\n") |> IO.iodata_to_binary() |> sha256()
    receipt = %{"format_version" => 1, "source_sha256" => pin,
      "files" => Enum.map(files, fn entry ->
        %{"path" => entry.path, "bytes" => entry.bytes, "sha256" => entry.sha256}
      end),
      "dependency_policy" => "canonical licensed source; OS lock authoritative; separate optional Eval profile",
      "profile" => if(eval?, do: "eval", else: "base"),
      "excluded_backends" => if(eval?, do: ["snakebridge"], else: ["quickbeam", "snakepit", "snakebridge", "python"])}
    {receipt, files}
  end

  defp files(source, relative) do
    path = Path.join(source, relative)
    case File.lstat!(path).type do
      :regular -> [file(source, relative)]
      :directory ->
        path |> File.ls!() |> Enum.reject(&(&1 in @excluded)) |> Enum.sort()
        |> Enum.flat_map(&files(source, Path.join(relative, &1)))
      type -> raise("coding input must be a regular file/directory: #{relative} (#{type})")
    end
  end

  defp file(source, relative) do
    content = File.read!(Path.join(source, relative))
    %{path: relative, bytes: byte_size(content), sha256: sha256(content)}
  end

  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
end

Elixos.FactoryCodingSource.main(System.argv())
