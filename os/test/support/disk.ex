defmodule Elixos.Test.Disk do
  @moduledoc """
  Reads and writes files on an ext4 disk image *while QEMU is not running*,
  with e2fsprogs' `debugfs` (no root, no mounting).

  The data disk is mounted at `/priv` inside Elixos, so `/priv/boot.state`
  in the guest is `/boot.state` here.
  """

  @doc "Copies the pristine build/disk.img into `dir` and returns the copy's path."
  def fresh!(dir) do
    pristine = Elixos.Test.Paths.build("disk.img")

    unless File.exists?(pristine) do
      raise "missing #{pristine}; run `make image` first (docs/TESTING.md)"
    end

    copy = Path.join(dir, "disk.img")
    {_, 0} = System.cmd("cp", ["--sparse=always", pristine, copy])
    copy
  end

  def exists?(disk, path), do: debugfs!(disk, "stat #{path}") != ""

  @doc "File contents, or `{:error, :enoent}`."
  def read(disk, path) do
    if exists?(disk, path), do: {:ok, debugfs!(disk, "cat #{path}")}, else: {:error, :enoent}
  end

  @doc "Replaces (or creates) `path` with `contents`."
  def write!(disk, path, contents) do
    tmp = Path.join(System.tmp_dir!(), "elixos-disk-#{System.unique_integer([:positive])}")
    File.write!(tmp, contents)

    try do
      if exists?(disk, path), do: debugfs!(disk, "rm #{path}", write: true)
      debugfs!(disk, "write #{tmp} #{path}", write: true)
      :ok
    after
      File.rm(tmp)
    end
  end

  @doc "Copies a host directory tree into the image under `remote_dir`."
  def put_tree!(disk, local_dir, remote_dir) do
    commands =
      (ancestors(remote_dir) ++ dirs_under(local_dir, remote_dir))
      |> Enum.map(&"mkdir #{&1}")
      |> Kernel.++(
        for file <- Path.wildcard(Path.join(local_dir, "**/*"), match_dot: true),
            File.regular?(file),
            do: "write #{file} #{Path.join(remote_dir, Path.relative_to(file, local_dir))}"
      )

    script = Path.join(System.tmp_dir!(), "elixos-debugfs-#{System.unique_integer([:positive])}")
    File.write!(script, Enum.join(commands, "\n") <> "\n")

    try do
      {_, 0} =
        System.cmd("sh", [
          "-c",
          ~s(exec debugfs -w -f "$1" "$2" >/dev/null 2>&1),
          "sh",
          script,
          disk
        ])

      :ok
    after
      File.rm(script)
    end
  end

  # "/src/app" -> ["/src", "/src/app"]; mkdir of an existing dir is a harmless no-op.
  defp ancestors(remote_dir) do
    remote_dir
    |> Path.split()
    |> Enum.drop(1)
    |> Enum.scan(&Path.join(&2, &1))
    |> Enum.map(&("/" <> &1))
  end

  defp dirs_under(local_dir, remote_dir) do
    for dir <- Path.wildcard(Path.join(local_dir, "**/*"), match_dot: true),
        File.dir?(dir),
        do: Path.join(remote_dir, Path.relative_to(dir, local_dir))
  end

  defp debugfs!(disk, request, opts \\ []) do
    flags = if opts[:write], do: "-w", else: ""
    script = ~s(exec debugfs #{flags} -R "$1" "$2" 2>/dev/null)
    {out, 0} = System.cmd("sh", ["-c", script, "sh", request, disk])
    out
  end
end
