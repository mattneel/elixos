defmodule Elixos.Integration.M25BrowserTest do
  @moduledoc """
  M25: a headless browser, shipped with the system. Its argv comes from the
  read-only `/system` mount; it comes up, navigates to a stub HTTP server on
  the loopback, returns the page's text, evaluates JavaScript, produces a
  PNG, and rescue mode starts none of it. Nothing is downloaded at run time.
  """
  use ExUnit.Case, async: false

  @moduletag :qemu
  @moduletag milestone: 25
  @moduletag timeout: 900_000
  @moduletag :tmp_dir

  alias Elixos.Test.{Disk, QEMU}

  # A page on the loopback, served by a module the prompt defines - the M15
  # stub pattern again.
  defp page do
    """
    defmodule Demo.Page do
      def start(port) do
        {:ok, listen} = :gen_tcp.listen(port, [:binary, active: false, reuseaddr: true])
        spawn_link(fn -> loop(listen) end)
        :ok
      end

      defp loop(listen) do
        {:ok, socket} = :gen_tcp.accept(listen)
        _ = :gen_tcp.recv(socket, 0, 5_000)
        body = "<html><head><title>stub page</title></head><body>hello from the stub</body></html>"

        :gen_tcp.send(socket, [
          "HTTP/1.1 200 OK\\r\\ncontent-type: text/html\\r\\ncontent-length: ",
          Integer.to_string(byte_size(body)),
          "\\r\\nconnection: close\\r\\n\\r\\n",
          body
        ])

        :gen_tcp.close(socket)
        loop(listen)
      end
    end
    """
  end

  test "the browser navigates, evaluates and screenshots, from /system", ctx do
    disk = Disk.fresh!(ctx.tmp_dir)
    vm = QEMU.boot_to_iex(ctx, disk: disk)

    {out, vm} = QEMU.iex(vm, "Elixos.Browser.status()")
    assert out =~ "{:ok, "

    # The binary the OS would exec exists, and lives in the read-only system
    # image: nothing is fetched at run time.
    {out, vm} =
      QEMU.iex(vm, """
      case Elixos.Browser.command() do
        {:ok, [exec | _]} -> {File.exists?(exec), String.starts_with?(exec, "/system/")}
        other -> other
      end
      """)

    assert out =~ "{true, true}"

    {out, vm} = QEMU.iex(vm, "(" <> page() <> ")", 120_000)
    assert out =~ "{:module, Demo.Page"

    {out, vm} = QEMU.iex(vm, "Demo.Page.start(4040)")
    assert out =~ ":ok"

    {out, vm} = QEMU.iex(vm, ~s|Elixos.Browser.navigate("http://127.0.0.1:4040/")|, 180_000)
    assert out =~ "hello from the stub"

    {out, vm} = QEMU.iex(vm, ~s|Elixos.Browser.eval("document.title")|, 120_000)
    assert out =~ ~s|"stub page"|

    {out, vm} =
      QEMU.iex(
        vm,
        ~s|case Elixos.Browser.screenshot() do {:ok, png} -> :binary.part(png, 0, 4) == <<137, 80, 78, 71>>; other -> other end|,
        120_000
      )

    assert out =~ ~r/^true$/m

    # The system image is mounted read-only, which is what makes "shipped,
    # never downloaded" a property and not a promise.
    {out, _vm} =
      QEMU.iex(vm, """
      File.read!("/proc/mounts")
      |> String.split("\\n")
      |> Enum.find(&String.contains?(&1, " /system "))
      """)

    assert out =~ ~r{/system\s+\S+\s+ro[, ]}, out

    # Rescue is the factory with /priv mounted: no browser. The first VM has to
    # go first - the disk is one file, and its mount is a running qemu's
    # (ADR-067).
    QEMU.stop(vm)
    vm = QEMU.boot(ctx, disk: disk, append: ["elixos.safe"])
    {_, vm} = QEMU.expect(vm, QEMU.iex_prompt(), 300_000)

    {out, vm} = QEMU.iex(vm, "Elixos.Browser.status()")
    assert out =~ "{:error, :not_running}"

    QEMU.refute_kernel_panic(vm)
    QEMU.stop(vm)
  end
end
