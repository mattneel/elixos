Code.require_file("../os/test/support/qmp.ex", __DIR__)

defmodule Elixos.Demo.Capture do
  alias Elixos.Test.QMP

  def run(socket_path, directory) do
    File.mkdir_p!(directory)
    socket = QMP.connect(socket_path)
    owner = self()
    spawn(fn -> read_commands(owner) end)
    IO.puts("CAPTURE READY")

    try do
      loop(socket, directory, 0, System.monotonic_time(:millisecond))
    after
      QMP.close(socket)
    end
  end

  defp read_commands(owner) do
    case IO.gets("") do
      :eof ->
        send(owner, :stop)

      {:error, _reason} ->
        send(owner, :stop)

      line when is_binary(line) ->
        send(owner, {:command, String.trim(line)})
        read_commands(owner)
    end
  end

  defp loop(socket, directory, index, next_frame) do
    receive do
      :stop ->
        IO.puts("CAPTURE STOPPED #{index}")

      {:command, "STOP"} ->
        IO.puts("CAPTURE STOPPED #{index}")

      {:command, "KEY " <> qcode} ->
        QMP.key(socket, qcode)
        IO.puts("KEY SENT #{qcode}")
        loop(socket, directory, index, next_frame)

      {:command, other} ->
        raise "unknown capture command: #{inspect(other)}"
    after
      max(next_frame - System.monotonic_time(:millisecond), 0) ->
        path =
          Path.join(
            directory,
            "frame-#{String.pad_leading(Integer.to_string(index), 6, "0")}.ppm"
          )

        QMP.screendump(socket, path)
        loop(socket, directory, index + 1, next_frame + 250)
    end
  end
end

case System.argv() do
  [socket, directory] -> Elixos.Demo.Capture.run(socket, directory)
  _ -> raise "usage: elixir demos/gui-capture.exs <QMP socket> <frames directory>"
end
