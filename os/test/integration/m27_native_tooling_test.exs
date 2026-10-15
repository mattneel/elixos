defmodule Elixos.Integration.NativeToolingTest do
  use ExUnit.Case, async: false

  @moduletag :qemu
  @moduletag milestone: 27
  @moduletag timeout: 600_000
  @moduletag :tmp_dir

  alias Elixos.Test.{Disk, QEMU}

  test "the packaged Elixir CLI runs without changing the OS VM's launch state", ctx do
    vm = QEMU.boot_to_iex(ctx, disk: Disk.fresh!(ctx.tmp_dir), memory_mb: 2048)

    {out, vm} =
      QEMU.iex(
        vm,
        ~s|(fn -> before = {File.cwd!(), System.get_env(), Elixos.info()}; {output, status} = System.cmd("elixir", ["-e", "IO.write(Integer.to_string(6 * 7))"], env: [{"ELIXIR_ERL_OPTIONS", "+S 2:2 +A 2"}], stderr_to_stdout: true); {output, status, before == {File.cwd!(), System.get_env(), Elixos.info()}} end).()|,
        30_000
      )

    assert out =~ ~s|{"42", 0, true}|
    vm = QEMU.send_line(vm, "Elixos.poweroff()")
    {0, _} = QEMU.expect_exit(vm)
  end

  test "offline Cargo compiles and executes a program in the caller's session", ctx do
    vm = QEMU.boot_to_iex(ctx, disk: Disk.fresh!(ctx.tmp_dir), memory_mb: 2048)

    manifest = "[package]\nname = \"session_contract\"\nversion = \"0.1.0\"\nedition = \"2024\"\n"

    source = """
    fn main() {
        let input = std::fs::read_to_string("input.txt").unwrap();
        let result = input.trim().parse::<i32>().unwrap() * 7;
        std::fs::write("result.txt", result.to_string()).unwrap();
        print!("{result}");
    }
    """

    script =
      ~s|(fn -> before = {File.cwd!(), System.get_env()}; root = "/priv/home/session_contract"; File.mkdir_p!(root <> "/src"); File.write!(root <> "/Cargo.toml", #{inspect(manifest)}); File.write!(root <> "/src/main.rs", #{inspect(source)}); File.write!(root <> "/input.txt", "6"); {:ok, ^root} = Elixos.Session.cd(root); :ok = Rust.init(); case Rust.cargo(["run", "--offline", "--quiet"]) do {:ok, %{status: 0, output: "42"}} -> {File.read(root <> "/result.txt"), before == {File.cwd!(), System.get_env()}}; error -> {:build_failed, error} end end).()|

    {out, vm} = QEMU.iex(vm, script, 300_000)
    assert out =~ ~s|{{:ok, "42"}, true}|
    vm = QEMU.send_line(vm, "Elixos.poweroff()")
    {0, _} = QEMU.expect_exit(vm)
  end
end
