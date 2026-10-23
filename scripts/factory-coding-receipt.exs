defmodule Elixos.FactoryCodingReceipt do
  @moduledoc false

  def main([factory]), do: main([factory, "0"])

  def main([factory, profile]) when profile in ["0", "1"] do
    unless System.version() == "1.20.4", do: raise("factory coding compiler must be Elixir 1.20.4")
    otp_file = Path.join([to_string(:code.root_dir()), "releases", to_string(:erlang.system_info(:otp_release)), "OTP_VERSION"])
    otp = otp_file |> File.read!() |> String.trim()
    unless otp == "29.1.1", do: raise("factory coding runtime must be OTP 29.1.1")
    source = Path.join(factory, "coding/source.json") |> File.read!() |> :json.decode()
    apps = Path.wildcard(Path.join(factory, "lib/*/ebin/*.app")) |> Enum.sort()
    identities = Enum.map(apps, fn path ->
      {:ok, [{:application, app, properties}]} = :file.consult(String.to_charlist(path))
      %{"app" => Atom.to_string(app), "version" => to_string(Keyword.fetch!(properties, :vsn)),
        "path" => Path.relative_to(path, factory), "sha256" => sha256(File.read!(path)),
        "applications" => Enum.map(Keyword.get(properties, :applications, []), &Atom.to_string/1)}
    end)
    for app <- ~w(oh_my_jido elixos_host jido jido_ai req_llm) do
      unless Enum.count(identities, &(&1["app"] == app)) == 1,
        do: raise("factory must contain exactly one native #{app} application")
    end
    optional = ~w(quickbeam snakepit oxc)
    if profile == "1" do
      for app <- optional do
        unless Enum.count(identities, &(&1["app"] == app)) == 1,
          do: raise("Eval factory must contain exactly one native #{app} application")
      end
      for path <- ~w(coding/eval-build.json coding/native.json coding/inputs/eval.lock) do
        unless File.regular?(Path.join(factory, path)),
          do: raise("Eval factory receipt missing: #{path}")
      end
    else
      for app <- optional ++ ["snakebridge"] do
        if Enum.any?(identities, &(&1["app"] == app)),
          do: raise("optional backend #{app} was selected as an OS dependency")
      end
    end
    beams = Path.wildcard(Path.join(factory, "lib/*/ebin/*.beam")) |> Enum.sort()
    files = inventory(beams, factory)
    system_paths = Enum.flat_map(~w(source/os source/spec coding/inputs), fn directory ->
      Path.wildcard(Path.join([factory, directory, "**/*"]), match_dot: true) |> Enum.filter(&File.regular?/1)
    end) ++ [Path.join(factory, "source/MILESTONE")]
    system_files = inventory(Enum.sort(system_paths), factory)
    system_pin = Enum.map(system_files, &"#{&1["sha256"]}  #{&1["path"]}\n") |> IO.iodata_to_binary() |> sha256()
    licenses = Path.wildcard(Path.join(factory, "lib/*/priv/licenses/**/*"))
      |> Enum.filter(&File.regular?/1) |> Enum.sort() |> inventory(factory)
    receipt = %{"format_version" => 1, "source_sha256" => source["source_sha256"],
      "source_receipt_sha256" => sha256(File.read!(Path.join(factory, "coding/source.json"))),
      "os_lock_sha256" => sha256(File.read!("/home/build/os/mix.lock")),
      "system_source_sha256" => system_pin, "system_files" => system_files, "licenses" => licenses,
      "profile" => if(profile == "1", do: "eval", else: "base"),
      "elixir" => System.version(), "otp" => otp,
      "erts" => to_string(:erlang.system_info(:version)),
      # A cross-built factory (ADR-094) runs this on the build host's BEAM; the
      # receipt names the target the bytecode is configured for, which is the
      # system architecture the target's own ERTS reports.
      "architecture" => System.get_env("FACTORY_SYSTEM_ARCHITECTURE") || to_string(:erlang.system_info(:system_architecture)),
      "applications" => identities, "files" => files}
    File.write!(Path.join(factory, "coding/beams.json"), :json.encode(receipt), [:exclusive])
  end

  defp inventory(paths, root) do
    Enum.map(paths, fn path ->
      bytes = File.read!(path)
      %{"path" => Path.relative_to(path, root), "bytes" => byte_size(bytes), "sha256" => sha256(bytes)}
    end)
  end

  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
end

Elixos.FactoryCodingReceipt.main(System.argv())
