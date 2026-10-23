defmodule Elixos.Test.QEMU do
  @moduledoc """
  Boots Elixos in QEMU and drives its serial console, expect-style.

  One `boot/2` is one QEMU process is one power-on. QEMU runs with
  `-no-reboot`, so a guest reboot *ends* the process; a test reboots by
  calling `boot/2` again with the same disk. Every boot is therefore bounded
  and observable, and persistence is tested the honest way: across power cycles.

  Functions thread the `%QEMU{}` through because output arrives as messages
  to the test process:

      vm = QEMU.boot(context, disk: disk)
      {_, vm} = QEMU.expect(vm, ~r/iex\\(\\d+\\)> /)
      {out, vm} = QEMU.iex(vm, "1 + 1")
      assert out =~ "2"

  Artifacts default to build/bzImage and build/initramfs.cpio.gz on x86_64,
  build/aarch64/Image and build/aarch64/initramfs.cpio.gz on aarch64, and the
  same under build/riscv64/ on riscv64
  (`:arch`), each overridable with its environment variable
  (ELIXOS_KERNEL / ELIXOS_INITRAMFS, ELIXOS_AARCH64_IMAGE /
  ELIXOS_AARCH64_INITRAMFS). Timeouts scale with ELIXOS_QEMU_SLOWDOWN
  (default 1; raise it without KVM, and for aarch64 under TCG).
  """

  import ExUnit.Assertions

  # iex_prompt: number of the last `iex(N)>` prompt seen, so `iex/3` can tell
  # the next prompt from IEx redrawing the current one (it does, on every line).
  defstruct [:port, :os_pid, :iex_prompt, :qmp, :qmp_path, buffer: "", transcript: ""]

  @type t :: %__MODULE__{}

  @iex_prompt ~r/iex\(\d+\)> /

  @doc "The IEx prompt pattern."
  def iex_prompt, do: @iex_prompt

  @doc """
  Starts QEMU. Registers an `on_exit` that kills it, so call from a test process.

  Options:

    * `:disk` (required) - data disk image (see `Elixos.Test.Disk.fresh!/1`)
    * `:append` - extra kernel command line words, e.g. `["elixos.safe"]`
    * `:memory_mb` - default 1024
    * `:initramfs` - explicit initramfs file for a distinct boot profile
    * `:ssh_port` - forward host 127.0.0.1:<port> to guest port 22 (virtio-net, ip=dhcp)
    * `:hostfwd` - more `{host_port, guest_port}` forwards on that user-mode NIC
    * `:coproc` - `{guest_port, host_port}`: a second, restricted user-mode NIC
      (M29), the coprocessor link. The guest is 10.0.3.15 on 10.0.3.0/24 and
      reaches nothing but 10.0.3.9:<guest_port>, relayed per connection (socat)
      to the host's 127.0.0.1:<host_port>. The external NIC is then always
      present too, so the link is the guest's eth1.
    * `:arch` - `:x86_64` (default), `:aarch64` or `:riscv64`: which QEMU binary, machine,
      console and artifacts the guest gets
    * `:uefi` - `{esp_image, ovmf_code, ovmf_vars_copy}`: boot through firmware
      instead of `-kernel`/`-initrd`
    * `:gpu` - add a virtio framebuffer, virtio keyboard and private QMP socket
    * `:deck` - a host file of 2 MiB (`Elixos.Test.DeckScreen.region/2`):
      the deck framebuffer (M33, docs/PROTOCOL.md §12) as an `ivshmem-plain`
      PCI device (1af4:1110) whose BAR 2 is that file, shared with the
      guest, plus `elixos.deck=pci:0x1af4:0x1110` on the kernel command line
  """
  @spec boot(map(), keyword()) :: t()
  def boot(_context, opts) do
    disk = Keyword.fetch!(opts, :disk)
    arch = Keyword.get(opts, :arch, :x86_64)
    binary = qemu_binary(arch)
    qemu = System.find_executable(binary) || flunk("#{binary} not found")

    qmp_path =
      if Keyword.get(opts, :gpu, false),
        do: "/tmp/exq-#{System.pid()}-#{System.unique_integer([:positive])}.sock"

    args =
      [
        machine_args(arch),
        ["-m", to_string(Keyword.get(opts, :memory_mb, 1024)), "-smp", "2"],
        ["-display", "none", "-monitor", "none", "-serial", "stdio", "-no-reboot"],
        ["-drive", "file=#{drive_path(disk)},if=virtio,format=raw"],
        ["-device", "virtio-rng-pci"],
        boot_args(arch, opts),
        net_args(opts),
        graphics_args(qmp_path),
        deck_args(Keyword.get(opts, :deck))
      ]
      |> Enum.concat()

    port =
      Port.open({:spawn_executable, qemu}, [:binary, :exit_status, :stderr_to_stdout, args: args])

    {:os_pid, os_pid} = Port.info(port, :os_pid)

    ExUnit.Callbacks.on_exit(fn ->
      kill(os_pid)
      if qmp_path, do: File.rm(qmp_path)
    end)

    qmp = if qmp_path, do: Elixos.Test.QMP.connect(qmp_path, scale(10_000))
    if qmp, do: ExUnit.Callbacks.on_exit(fn -> Elixos.Test.QMP.close(qmp) end)
    %__MODULE__{port: port, os_pid: os_pid, qmp: qmp, qmp_path: qmp_path}
  end

  defp boot_args(arch, opts) do
    case Keyword.get(opts, :uefi) do
      nil ->
        # `quiet`: the kernel log is noise on a console whose lines the tests
        # match byte for byte (docs/PROTOCOL.md §6), and on a serial port
        # printk can interleave with them. Emergencies ("reboot: Power down")
        # still print, which is what the tests that check them need.
        append =
          Enum.join(
            [
              console(arch),
              "panic=-1",
              "quiet" | deck_append(opts) ++ Keyword.get(opts, :append, [])
            ],
            " "
          )

        {kernel_env, kernel_name} = kernel_artifact(arch)
        {initramfs_env, initramfs_name} = initramfs_artifact(arch)

        [
          "-kernel",
          artifact(kernel_env, kernel_name),
          "-initrd",
          Keyword.get_lazy(opts, :initramfs, fn -> artifact(initramfs_env, initramfs_name) end),
          "-append",
          append
        ]

      {esp, code, vars} ->
        [
          "-drive",
          "if=pflash,format=raw,readonly=on,file=#{drive_path(code)}",
          "-drive",
          "if=pflash,format=raw,file=#{drive_path(vars)}",
          "-drive",
          "file=#{drive_path(esp)},format=raw,if=virtio"
        ]
    end
  end

  # ExUnit's tmp_dir paths contain the test name, commas and all, and QEMU's
  # option parser treats a comma in `file=` as a separator. Doubling it is
  # QEMU's escape (verified: `-drive file=/a,,b,if=none` opens "/a,b").
  defp drive_path(path), do: String.replace(path, ",", ",,")

  # The architectures Elixos builds for (ADR-041, ADR-097). aarch64 and
  # riscv64 under TCG on an x86_64 host are slow and need no KVM: QEMU tries
  # each -accel in order and falls back to the next. riscv64 virt boots through
  # QEMU's bundled OpenSBI firmware, which jumps to the -kernel Image.
  defp qemu_binary(:x86_64), do: "qemu-system-x86_64"
  defp qemu_binary(:aarch64), do: "qemu-system-aarch64"
  defp qemu_binary(:riscv64), do: "qemu-system-riscv64"

  defp machine_args(:x86_64) do
    ["-machine", "q35", "-accel", "kvm", "-accel", "tcg", "-cpu", "max"]
  end

  defp machine_args(:aarch64) do
    ["-machine", "virt", "-accel", "kvm", "-accel", "tcg", "-cpu", "cortex-a72"]
  end

  defp machine_args(:riscv64) do
    ["-machine", "virt", "-accel", "kvm", "-accel", "tcg", "-cpu", "rv64", "-bios", "default"]
  end

  defp console(:x86_64), do: "console=ttyS0"
  defp console(:aarch64), do: "console=ttyAMA0"
  defp console(:riscv64), do: "console=ttyS0"

  defp kernel_artifact(:x86_64), do: {"ELIXOS_KERNEL", "bzImage"}
  defp kernel_artifact(:aarch64), do: {"ELIXOS_AARCH64_IMAGE", "aarch64/Image"}
  defp kernel_artifact(:riscv64), do: {"ELIXOS_RISCV64_IMAGE", "riscv64/Image"}

  defp initramfs_artifact(:x86_64), do: {"ELIXOS_INITRAMFS", "initramfs.cpio.gz"}

  defp initramfs_artifact(:aarch64),
    do: {"ELIXOS_AARCH64_INITRAMFS", "aarch64/initramfs.cpio.gz"}

  defp initramfs_artifact(:riscv64),
    do: {"ELIXOS_RISCV64_INITRAMFS", "riscv64/initramfs.cpio.gz"}

  defp net_args(opts) do
    forwards =
      Enum.map(
        List.wrap(if port = Keyword.get(opts, :ssh_port), do: {port, 22}) ++
          Keyword.get(opts, :hostfwd, []),
        fn {host, guest} -> ",hostfwd=tcp:127.0.0.1:#{host}-:#{guest}" end
      )

    coproc = Keyword.get(opts, :coproc)

    external =
      if forwards == [] and coproc == nil do
        ["-nic", "none"]
      else
        ["-netdev", "user,id=n0" <> Enum.join(forwards), "-device", "virtio-net-pci,netdev=n0"]
      end

    external ++ coproc_args(coproc)
  end

  # restrict=on isolates the guest from the host and the outside; the
  # guestfwd rule is its only way out. cmd: starts one relay per connection,
  # so the link survives the coprocessor restarting.
  defp coproc_args(nil), do: []

  defp coproc_args({guest_port, host_port}) do
    socat = System.find_executable("socat") || flunk("socat not found (make check-tools)")

    [
      "-netdev",
      "user,id=n1,net=10.0.3.0/24,restrict=on," <>
        "guestfwd=tcp:10.0.3.9:#{guest_port}-cmd:#{socat} - TCP:127.0.0.1:#{host_port}",
      "-device",
      "virtio-net-pci,netdev=n1"
    ]
  end

  # ivshmem-plain exposes a memory backend as BAR 2; share=on maps the host
  # file itself, so the host reads what the guest writes. Its size must be a
  # power of two.
  defp deck_args(nil), do: []

  defp deck_args(path) do
    [
      "-object",
      "memory-backend-file,id=deckfb,size=#{File.stat!(path).size},mem-path=#{drive_path(path)},share=on",
      "-device",
      "ivshmem-plain,memdev=deckfb"
    ]
  end

  defp deck_append(opts) do
    if Keyword.get(opts, :deck), do: ["elixos.deck=pci:0x1af4:0x1110"], else: []
  end

  defp graphics_args(nil), do: []

  defp graphics_args(path) do
    [
      "-vga",
      "none",
      "-device",
      "virtio-gpu-pci",
      "-device",
      "virtio-keyboard-pci",
      "-qmp",
      "unix:#{path},server=on,wait=off"
    ]
  end

  @doc "Sends a real keyboard key (QEMU qcode, e.g. y, ret, tab) through QMP."
  def send_key(%__MODULE__{qmp: qmp} = vm, qcode) when not is_nil(qmp) do
    Elixos.Test.QMP.key(qmp, qcode, scale(10_000))
    vm
  end

  @doc "Saves the actual graphics display as a PPM and returns the VM."
  def screendump(%__MODULE__{qmp: qmp} = vm, path) when not is_nil(qmp) do
    Elixos.Test.QMP.screendump(qmp, path, scale(10_000))
    vm
  end

  defp artifact(env, name) do
    path = System.get_env(env) || Elixos.Test.Paths.build(name)
    File.exists?(path) || flunk("missing #{path}; run `make image` first (docs/TESTING.md)")
    path
  end

  @doc """
  Waits until `pattern` appears in the (ANSI-stripped) console output.
  Returns `{matched_text, vm}`; output up to the end of the match is consumed.
  """
  @spec expect(t(), Regex.t(), non_neg_integer()) :: {String.t(), t()}
  def expect(vm, pattern, timeout \\ 60_000) do
    {matched, _before, vm} = expect_with_before(vm, pattern, timeout)
    {matched, vm}
  end

  @doc "Like `expect/3` but also returns the consumed text before the match."
  @spec expect_with_before(t(), Regex.t(), non_neg_integer()) :: {String.t(), String.t(), t()}
  def expect_with_before(vm, pattern, timeout \\ 60_000) do
    deadline = System.monotonic_time(:millisecond) + scale(timeout)
    do_expect(vm, pattern, deadline)
  end

  defp do_expect(vm, pattern, deadline) do
    clean = strip(vm.buffer)

    case Regex.run(pattern, clean, return: :index) do
      [{start, length} | _] ->
        matched = binary_part(clean, start, length)
        before = binary_part(clean, 0, start)
        rest = binary_part(clean, start + length, byte_size(clean) - start - length)

        {matched, before,
         %{vm | buffer: rest, iex_prompt: last_prompt(before <> matched, vm.iex_prompt)}}

      nil ->
        port = vm.port
        remaining = max(deadline - System.monotonic_time(:millisecond), 0)

        receive do
          {^port, {:data, data}} ->
            do_expect(
              %{vm | buffer: vm.buffer <> data, transcript: vm.transcript <> data},
              pattern,
              deadline
            )

          {^port, {:exit_status, status}} ->
            flunk(
              "QEMU exited (status #{status}) while waiting for #{inspect(pattern)}\n" <> tail(vm)
            )
        after
          remaining ->
            flunk("timed out waiting for #{inspect(pattern)}\n" <> tail(vm))
        end
    end
  end

  @doc """
  Waits until `pattern` has appeared anywhere in this boot's console output,
  including text that earlier expectations already consumed. Use it for shim
  log lines, which can arrive while a test is waiting for something else
  (a commit that lands before the first prompt, say). Consumes nothing.
  """
  @spec await_log(t(), Regex.t(), non_neg_integer()) :: t()
  def await_log(vm, pattern, timeout \\ 60_000) do
    deadline = System.monotonic_time(:millisecond) + scale(timeout)
    do_await_log(vm, pattern, deadline)
  end

  defp do_await_log(vm, pattern, deadline) do
    if transcript(vm) =~ pattern do
      vm
    else
      port = vm.port
      remaining = max(deadline - System.monotonic_time(:millisecond), 0)

      receive do
        {^port, {:data, data}} ->
          vm = %{vm | buffer: vm.buffer <> data, transcript: vm.transcript <> data}
          do_await_log(vm, pattern, deadline)

        {^port, {:exit_status, status}} ->
          flunk("QEMU exited (status #{status}) while awaiting #{inspect(pattern)}\n" <> tail(vm))
      after
        remaining -> flunk("timed out awaiting #{inspect(pattern)}\n" <> tail(vm))
      end
    end
  end

  @doc "Waits for QEMU to exit (the guest powered off, rebooted, or panicked)."
  @spec expect_exit(t(), non_neg_integer()) :: {non_neg_integer(), t()}
  def expect_exit(vm, timeout \\ 60_000) do
    port = vm.port
    deadline = System.monotonic_time(:millisecond) + scale(timeout)
    wait_exit(vm, port, deadline)
  end

  defp wait_exit(vm, port, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, data}} ->
        wait_exit(
          %{vm | buffer: vm.buffer <> data, transcript: vm.transcript <> data},
          port,
          deadline
        )

      {^port, {:exit_status, status}} ->
        {status, vm}
    after
      remaining -> flunk("timed out waiting for QEMU to exit\n" <> tail(vm))
    end
  end

  @doc "Types a line (terminated with a carriage return, as a terminal would)."
  @spec send_line(t(), String.t()) :: t()
  def send_line(vm, line), do: send_raw(vm, line <> "\r")

  @spec send_raw(t(), iodata()) :: t()
  def send_raw(vm, bytes) do
    Port.command(vm.port, bytes)
    vm
  end

  @doc """
  Evaluates `expr` at an IEx prompt and returns everything printed from the
  echo of the line to the *next* prompt (the echoed input, then the result).

  Multiline input is one parenthesized block: the next completed prompt must
  follow the whole supplied expression, not its first top-level statement.

  The console must be sitting at a prompt that has already been consumed.
  IEx redraws the current prompt with the input after Enter (verified on
  OTP 29 / Elixir 1.20), and that redraw can be numbered like the next prompt
  before the result is printed; the echo of the line just sent is what marks
  this expression's output, so this waits for that first.
  """
  @spec iex(t(), String.t(), non_neg_integer()) :: {String.t(), t()}
  def iex(vm, expr, timeout \\ 30_000) do
    current = vm.iex_prompt
    expr = if String.contains?(expr, "\n"), do: "(\n" <> expr <> "\n)", else: expr
    vm = send_line(vm, expr)
    deadline = System.monotonic_time(:millisecond) + scale(timeout)

    # The echo arrives as soon as the console reads the line, so it gets a
    # short window: a multi-line expression's redraws can split the echoed
    # text, and then the prompt-number wait below is the best there is.
    echo_deadline = min(deadline, System.monotonic_time(:millisecond) + scale(5_000))

    case soft_expect(vm, echo_pattern(expr), echo_deadline) do
      {:ok, vm} -> next_prompt(vm, current, "", deadline)
      {:timeout, vm} -> next_prompt(vm, current, "", deadline)
    end
  end

  # The console echoes what was typed, so the line comes back as `send_line/2`
  # wrote it. A line wider than the terminal wraps, adding its own newlines
  # anywhere it had a space, hence `\s*` between the words.
  defp echo_pattern(expr) do
    expr
    |> String.split()
    |> Enum.map_join("\\s*", &Regex.escape/1)
    |> then(&Regex.compile!(&1))
  end

  # Like `expect_with_before/3`, but a timeout is a value, not a failure: for
  # waits whose answer may legitimately never come.
  defp soft_expect(vm, pattern, deadline) do
    clean = strip(vm.buffer)

    case Regex.run(pattern, clean, return: :index) do
      [{start, length} | _] ->
        rest = binary_part(clean, start + length, byte_size(clean) - start - length)
        {:ok, %{vm | buffer: rest}}

      nil ->
        port = vm.port
        remaining = max(deadline - System.monotonic_time(:millisecond), 0)

        receive do
          {^port, {:data, data}} ->
            soft_expect(
              %{vm | buffer: vm.buffer <> data, transcript: vm.transcript <> data},
              pattern,
              deadline
            )

          {^port, {:exit_status, status}} ->
            flunk(
              "QEMU exited (status #{status}) while waiting for #{inspect(pattern)}\n" <> tail(vm)
            )
        after
          remaining -> {:timeout, vm}
        end
    end
  end

  defp next_prompt(vm, current, acc, deadline) do
    {matched, before, vm} = do_expect(vm, @iex_prompt, deadline)

    # The number of the prompt just matched - not the highest number ever
    # seen: a redrawn prompt can carry a number ahead of the result that is
    # still to be printed.
    if current == nil or prompt_number(matched) > current do
      {acc <> before, vm}
    else
      next_prompt(vm, current, acc <> before <> matched, deadline)
    end
  end

  defp prompt_number(matched) do
    [_, n] = Regex.run(~r/iex\((\d+)\)> /, matched)
    String.to_integer(n)
  end

  defp last_prompt(text, previous) do
    case Regex.scan(~r/iex\((\d+)\)> /, text) do
      [] -> previous
      matches -> matches |> List.last() |> Enum.at(1) |> String.to_integer()
    end
  end

  @doc "Boots and waits for the first IEx prompt."
  @spec boot_to_iex(map(), keyword()) :: t()
  def boot_to_iex(context, opts) do
    vm = boot(context, opts)
    {_, vm} = expect(vm, @iex_prompt, 180_000)
    vm
  end

  @doc "The full console output so far, ANSI escapes removed."
  def transcript(vm), do: strip(vm.transcript)

  @doc "Every QEMU test should end with this: PID 1 must never take the kernel down."
  def refute_kernel_panic(vm) do
    refute transcript(vm) =~ "Kernel panic", "kernel panic on the console\n" <> tail(vm)
    vm
  end

  @doc "Kills QEMU now."
  def stop(vm) do
    try do
      Port.close(vm.port)
    catch
      :error, _ -> :ok
    after
      kill(vm.os_pid)
      if vm.qmp, do: Elixos.Test.QMP.close(vm.qmp)
      if vm.qmp_path, do: File.rm(vm.qmp_path)
    end
  end

  defp kill(os_pid), do: System.cmd("kill", ["-KILL", to_string(os_pid)], stderr_to_stdout: true)

  defp strip(text) do
    text
    |> String.replace(~r/\e\[[0-?]*[ -\/]*[@-~]/, "")
    |> String.replace(~r/\e[()][A-Za-z0-9]/, "")
    |> String.replace("\r", "")
  end

  defp tail(vm) do
    text = transcript(vm)
    size = byte_size(text)
    keep = min(size, 4_000)
    "--- last console output ---\n" <> binary_part(text, size - keep, keep)
  end

  defp scale(ms) when is_integer(ms) do
    factor = String.to_integer(System.get_env("ELIXOS_QEMU_SLOWDOWN", "1"))
    ms * factor
  end
end
