defmodule Elixos.Integration.M17PostgresTest do
  @moduledoc """
  M17: Postgres as a system service. It answers from the prompt; it runs as
  its own uid - never root - with `/etc/passwd` naming that uid and the data
  directory owned by it, mode 0700; pgvector and TimescaleDB's Apache-only
  build load and answer; the binaries come from the read-only `/system`
  mount; rescue mode starts none of it; and the boot after a power cycle logs
  a *clean* shutdown, not crash recovery.
  """
  use ExUnit.Case, async: false

  @moduletag :qemu
  @moduletag milestone: 17
  @moduletag timeout: 900_000
  @moduletag :tmp_dir

  alias Elixos.Test.{Disk, QEMU}

  defp power_off(vm) do
    vm = QEMU.send_line(vm, "Elixos.poweroff()")
    {0, vm} = QEMU.expect_exit(vm)
    QEMU.refute_kernel_panic(vm)
  end

  test "a real Postgres runs as the postgres uid, from /system, on /priv", ctx do
    disk = Disk.fresh!(ctx.tmp_dir)
    vm = QEMU.boot_to_iex(ctx, disk: disk)

    # The prompt's interface to the database.
    {out, vm} = QEMU.iex(vm, ~s|Elixos.Postgres.query("select 42")|, 120_000)
    assert out =~ ~r/^\s*42\s*$/m

    # Not root; /etc/passwd names the uid it runs as (initdb looks itself up
    # with getpwuid); the data directory is that uid's, mode 0700; and the
    # binaries come from the read-only system image.
    {out, vm} =
      QEMU.iex(vm, """
      {:ok, pid} = Elixos.Postgres.status()

      proc_uid =
        ("/proc/" <> Integer.to_string(pid) <> "/status")
        |> File.read!()
        |> String.split("\\n")
        |> Enum.find(&String.starts_with?(&1, "Uid:"))
        |> String.split()
        |> List.last()
        |> String.to_integer()

      passwd_uid =
        "/etc/passwd"
        |> File.read!()
        |> String.split("\\n")
        |> Enum.find(&String.starts_with?(&1, "postgres:"))
        |> String.split(":")
        |> Enum.at(2)
        |> String.to_integer()

      stat = File.stat!("/priv/postgres/data")
      mount = File.read!("/proc/mounts") |> String.split("\\n") |> Enum.find(&String.contains?(&1, " /system "))

      %{
        not_root: proc_uid != 0,
        same_uid: proc_uid == passwd_uid and stat.uid == passwd_uid,
        mode: Integer.to_string(Bitwise.band(stat.mode, 0o777), 8),
        system_mount: mount
      }
      """)

    assert out =~ "not_root: true", out
    assert out =~ "same_uid: true", out
    assert out =~ ~s|mode: "700"|, out
    assert out =~ ~r{/system\s+\S+\s+ro[, ]}, out

    # pgvector: PostgreSQL-licensed, so it just ships.
    {out, vm} =
      QEMU.iex(vm, ~s|Elixos.Postgres.query("create extension if not exists vector")|, 300_000)

    assert out =~ "CREATE EXTENSION"

    {out, vm} =
      QEMU.iex(
        vm,
        ~s|Elixos.Postgres.query("select '[1,2,3]'::vector <-> '[3,2,1]'::vector")|,
        120_000
      )

    assert out =~ "2.828"

    # TimescaleDB, Apache-only build: hypertables and time_bucket, no
    # licensing question. Compression and continuous aggregates are the
    # Timescale License and get their own ADR.
    {out, vm} =
      QEMU.iex(
        vm,
        ~s|Elixos.Postgres.query("create extension if not exists timescaledb")|,
        300_000
      )

    assert out =~ "CREATE EXTENSION"

    {out, vm} =
      QEMU.iex(
        vm,
        ~s|Elixos.Postgres.query("create table m16_metrics (at timestamptz not null, value double precision); select create_hypertable('m16_metrics', 'at'); select count(*) from m16_metrics; select time_bucket('1 hour', now()) = time_bucket('1 hour', now())")|,
        300_000
      )

    assert out =~ "m16_metrics"
    assert out =~ ~r/^\s*0\s*$/m
    assert out =~ ~r/^\s*t\s*$/m

    # Power off, power on. The server comes back, and - the point of the
    # shutdown hook - its log says the system was shut down, not interrupted.
    power_off(vm)
    vm = QEMU.boot_to_iex(ctx, disk: disk)

    {out, vm} = QEMU.iex(vm, ~s|Elixos.Postgres.query("select 1")|, 120_000)
    assert out =~ ~r/^\s*1\s*$/m

    {out, _vm} =
      QEMU.iex(
        vm,
        """
        Path.wildcard("/priv/postgres/log/*.log")
        |> Enum.max_by(&File.stat!(&1).mtime)
        |> File.read!()
        """,
        120_000
      )

    assert out =~ "database system was shut down at", out
    refute out =~ "database system was interrupted"

    # Rescue is the factory with /priv mounted: the database is not part of
    # the minimum.
    vm = QEMU.boot(ctx, disk: disk, append: ["elixos.safe"])
    {_, vm} = QEMU.expect(vm, QEMU.iex_prompt(), 300_000)

    {out, vm} = QEMU.iex(vm, "Elixos.Postgres.status()")
    assert out =~ "{:error, :not_running}"

    QEMU.refute_kernel_panic(vm)
    QEMU.stop(vm)
  end
end
