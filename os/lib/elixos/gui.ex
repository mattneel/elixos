defmodule Elixos.GUI do
  @moduledoc """
  The GUI on the machine's own screen (M27, docs/ROADMAP.md).

  Emerge renders headless raster frames (`backend: :headless, rendering_api:
  :raster`, binary mode) into `Elixos.GUI`'s frame sink; the sink writes them
  to `/dev/fb0`. Input is Elixos's own: a small static helper grabs the evdev
  devices while the GUI owns the screen and streams events to `input/1`, and
  the dialog logic (which option, which key answers) is Elixir. `input/1` is
  also the test seam - Emerge 0.4.2 has no way to inject input into a
  renderer.

  The GUI is never boot-critical: a failure here leaves IEx on the console
  working, and rescue stays text-only. The renderer's NIF runs inside the VM,
  so a Skia crash takes the VM down with it; an ADR records that.
  """

  @doc "Starts the GUI (renderer + frame sink + input), unless it is running."
  @spec start() :: {:ok, pid()} | {:error, term()}
  def start, do: Elixos.NotImplemented.raise!(27, "Elixos.GUI.start/0")

  @doc "The running GUI: `{:ok, pid}` or `{:error, :not_running}`."
  @spec status() :: {:ok, pid()} | {:error, :not_running}
  def status, do: Elixos.NotImplemented.raise!(27, "Elixos.GUI.status/0")

  @doc "Stops the GUI and gives the console back to fbcon."
  @spec stop() :: :ok | {:error, term()}
  def stop, do: Elixos.NotImplemented.raise!(27, "Elixos.GUI.stop/0")

  @doc """
  One input event from a front-end (the evdev helper, or a test): a key, a
  pointer position, a button. Returns what the dialog did with it.
  """
  @spec input(term()) :: :ok | {:error, term()}
  def input(_event), do: Elixos.NotImplemented.raise!(27, "Elixos.GUI.input/1")

  @doc """
  Renders one Ask question as a dialog with no display:
  `{:ok, %{width: w, height: h, pixels: rgba}}`.
  """
  @spec render_dialog(Elixos.Ask.Question.t()) ::
          {:ok, %{width: pos_integer(), height: pos_integer(), pixels: binary()}}
          | {:error, term()}
  def render_dialog(_question),
    do: Elixos.NotImplemented.raise!(27, "Elixos.GUI.render_dialog/1")
end
