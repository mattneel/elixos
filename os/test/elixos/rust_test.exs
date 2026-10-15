defmodule Elixos.RustTest do
  @moduledoc """
  The Rust toolchain's API (ADR-066): `Rust.cargo/2` and `Rust.rustc/2` run the
  toolchain's own binaries in the caller's session directory, and cargo gets
  the linker named for the target - the toolchain's `cc`, the Zig bridge.

  The tools here are stubs this test writes, not the machine's Rust, so what is
  asserted is the mechanism (parsing, the environment, the directory) and not
  whichever Rust happens to be installed where the suite runs. The installed
  layout under `/priv/toolchain` is the integration tests' business.
  """
  use ExUnit.Case, async: false

  @moduletag milestone: 25
  @moduletag :tmp_dir

  @triple "x86_64-unknown-linux-musl"

  setup ctx do
    prefix = Path.join(ctx.tmp_dir, "toolchain")
    bin = Path.join([prefix, "rust", "usr", "bin"])
    cc = Path.join(prefix, "cc")
    File.mkdir_p!(bin)

    stub!(Path.join(bin, "rustc"), """
    #!/bin/sh
    case "$1" in
      --version) echo "rustc 1.97.0 (2d8144b78 2026-07-07)" ;;
      -vV)
        echo "rustc 1.97.0 (2d8144b78 2026-07-07)"
        echo "host: #{@triple}"
        echo "release: 1.97.0"
        ;;
      *) echo "rustc stub: unexpected argument" >&2; exit 1 ;;
    esac
    """)

    stub!(Path.join(bin, "cargo"), """
    #!/bin/sh
    echo "cargo 1.97.0 (c980f4866 2026-06-30)"
    echo "CARGO_HOME=$CARGO_HOME"
    echo "CC=$CC"
    echo "LINKER=$CARGO_TARGET_X86_64_UNKNOWN_LINUX_MUSL_LINKER"
    echo "PWD=$(pwd)"
    """)

    stub!(cc, "#!/bin/sh\nexit 0\n")

    previous_dir = Application.get_env(:elixos, :toolchain_dir)
    previous_home = Application.get_env(:elixos, :cargo_home)
    previous_cc = Application.get_env(:elixos, :toolchain_cc)
    Application.put_env(:elixos, :toolchain_dir, prefix)
    home = Path.join(ctx.tmp_dir, "cargo-home")
    Application.put_env(:elixos, :cargo_home, home)
    Application.put_env(:elixos, :toolchain_cc, cc)

    on_exit(fn ->
      restore(:toolchain_dir, previous_dir)
      restore(:cargo_home, previous_home)
      restore(:toolchain_cc, previous_cc)
    end)

    {:ok, prefix: prefix, cc: cc, home: home}
  end

  defp stub!(path, body) do
    File.write!(path, body)
    File.chmod!(path, 0o755)
  end

  defp restore(key, nil), do: Application.delete_env(:elixos, key)
  defp restore(key, value), do: Application.put_env(:elixos, key, value)

  test "init/1 accepts a prefix that carries the tools, and refuses one that does not", %{
    prefix: prefix
  } do
    assert :ok = Rust.init(path: prefix)
    assert {:error, {:no_rust, _path}} = Rust.init(path: Path.join(prefix, "nope"))
  end

  test "version/0 and target/0 come from the toolchain's own rustc" do
    assert :ok = Rust.init()
    assert {:ok, "1.97.0"} = Rust.version()
    assert {:ok, @triple} = Rust.target()
  end
end
