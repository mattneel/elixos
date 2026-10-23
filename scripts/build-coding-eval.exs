# Runs only in the target melange builder. Native Mix post_config selects optional
# dependencies before compilation without editing either source checkout/OS lock.
defmodule Elixos.CodingEvalBuild do
  @os "/home/build/os"
  @coding "/home/build/coding/oh_my_jido"
  @lock "/home/build/coding/eval.lock"

  def main do
    Mix.start()
    os_lock = lock(Path.join(@os, "mix.lock"))
    canonical_lock = lock(Path.join(@coding, "mix.lock"))
    merged = Map.merge(canonical_lock, os_lock)
    File.write!(@lock, inspect(merged, pretty: true, limit: :infinity, printable_limit: :infinity) <> "\n", [:exclusive])
    approved = sha256(File.read!(@lock))
    os_approved = sha256(File.read!(Path.join(@os, "mix.lock")))
    optional = [
      {:quickbeam, "== 0.11.3", runtime: false},
      {:snakepit, path: Path.join(@coding, "vendor/snakepit"), override: true, runtime: false},
      {:oxc, "== 0.19.0", override: true}
    ]
    config = Mix.Project.in_project(:elixos, @os, fn _ -> Mix.Project.config() end)
    release = config[:releases][:elixos] |> Keyword.put(:applications, [quickbeam: :load, snakepit: :load])
    overrides = [deps: config[:deps] ++ optional, lockfile: @lock,
      elixirc_paths: config[:elixirc_paths] ++ ["/home/build/scripts/coding-eval/lib"],
      releases: [elixos: release]]
    Mix.Project.in_project(:elixos, @os, overrides, fn _ ->
      Mix.Task.run("loadconfig", ["/home/build/scripts/coding-eval/config.exs"])
      Mix.Task.run("deps.get", ["--check-locked"])
      unchanged!(@lock, approved)
      # Source Cargo locks are authority. Fetch with --locked first; Rustler's
      # native build may not resolve another version even if upstream permits it.
      locks = for relative <- ["Cargo.lock", "native/oxc_fmt_nif/Cargo.lock", "native/oxc_lint_nif/Cargo.lock"] do
        path = Path.join([@os, "deps/oxc", relative])
        {path, sha256(File.read!(path))}
      end
      for relative <- ["Cargo.toml", "native/oxc_fmt_nif/Cargo.toml", "native/oxc_lint_nif/Cargo.toml"] do
        command!("cargo", ["fetch", "--locked", "--manifest-path", Path.join([@os, "deps/oxc", relative])])
      end
      for module <- [OXC.Native, OXC.Format.Native, OXC.Lint.Native] do
        Application.put_env(:oxc, module, target: System.fetch_env!("RUSTLER_TARGET"),
          cargo: :system, mode: :release, env: [{"CARGO_NET_OFFLINE", "true"}])
      end
      Mix.Task.run("release", ["--overwrite", "--path", "/tmp/rel"])
      for {path, digest} <- locks, do: unchanged!(path, digest)
      unless Snakepit.GRPCWorker.private_diagnostics_version() == 1,
        do: raise("licensed Snakepit private-diagnostics snapshot was not compiled")
    end)
    adapter = Path.join(@coding, "examples/elixos")
    adapter_config = Mix.Project.in_project(:elixos_host, adapter, fn _ -> Mix.Project.config() end)
    Mix.Project.in_project(:elixos_host, adapter, [deps: adapter_config[:deps] ++ optional, lockfile: @lock], fn _ ->
      Mix.Task.reenable("deps.get")
      Mix.Task.run("deps.get", ["--check-locked"])
      Mix.Task.reenable("loadconfig")
      Mix.Task.run("loadconfig", ["/home/build/scripts/coding-eval/config.exs"])
      Mix.Task.reenable("compile")
      Mix.Task.run("compile", ["--warnings-as-errors"])
    end)
    unchanged!(@lock, approved)
    unchanged!(Path.join(@os, "mix.lock"), os_approved)
    checksum_file = Path.join(@os, "deps/quickbeam/checksum-QuickBEAM.Native.exs")
    {checksums, _} = Code.eval_file(checksum_file)
    archive_name = "Elixir.QuickBEAM.Native-v0.11.3-#{System.fetch_env!("TARGET_ARCH")}-linux-musl.so.tar.gz"
    "sha256:" <> expected = Map.new(checksums) |> Map.fetch!(archive_name)
    [archive] = Path.wildcard(Path.join(System.fetch_env!("ZIGLER_PRECOMPILED_GLOBAL_CACHE_PATH"), "**/#{archive_name}"))
    unless sha256(File.read!(archive)) == expected, do: raise("QuickBEAM upstream native artifact digest differs")
    File.mkdir!("/home/build/coding/eval-artifacts")
    File.cp!(archive, Path.join("/home/build/coding/eval-artifacts", archive_name))
    source = File.read!("/home/build/coding/source.json") |> :json.decode()
    unless source["profile"] == "eval", do: raise("Eval needs an explicitly selected Eval source pin")
    receipt = %{
      "format_version" => 1, "profile" => "eval", "source_sha256" => source["source_sha256"],
      "os_lock_sha256" => os_approved, "canonical_lock_sha256" => sha256(File.read!(Path.join(@coding, "mix.lock"))),
      "resolved_lock_sha256" => approved, "lock_policy" => "OS entries authoritative; add absent canonical entries only",
      "elixir" => System.version(), "otp" => to_string(:erlang.system_info(:otp_release)),
      "erts" => to_string(:erlang.system_info(:version)), "architecture" => to_string(:erlang.system_info(:system_architecture)),
      "quickbeam_archive" => %{"filename" => archive_name, "sha256" => expected,
        "checksum_manifest_sha256" => sha256(File.read!(checksum_file))},
      "oxc_build" => "native locked upstream Rust crates; OS-pinned Rustler; no runtime Rust helper",
      "cargo" => command!("cargo", ["--version"]), "rustc" => command!("rustc", ["--version"]),
      "runtime_provisioning" => false
    }
    File.write!("/home/build/coding/eval-build.json", :json.encode(receipt), [:exclusive])
  end

  defp lock(path), do: path |> Code.eval_file() |> elem(0)
  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
  defp unchanged!(path, expected) do
    unless sha256(File.read!(path)) == expected, do: raise("approved lock changed during Eval build: #{path}")
  end
  defp command!(program, args) do
    case System.cmd(program, args, stderr_to_stdout: true) do
      {text, 0} -> text
      {text, code} -> raise("#{program} failed (#{code}): #{text}")
    end
  end
end

Elixos.CodingEvalBuild.main()
