defmodule Elixos.GUI do
  @moduledoc """
  Planned GUI contract for M27 (docs/ROADMAP.md).

  The entry points below remain `TODO(M27)` stubs. Emerge is a dependency and
  its raster-only backend profile is configured, but the framebuffer sink,
  evdev helper, dialog logic and console handover are not implemented yet.

  The planned renderer uses `backend: :headless, rendering_api: :raster` in
  binary mode; its frames will be written to `/dev/fb0`. Input will come from
  an evdev helper through `input/1`, also the test seam: Emerge 0.4.2 has no
  input injection API for that renderer.

  The GUI must remain non-boot-critical and absent in rescue. A renderer NIF
  crash can take its VM down; the implementation's ADR must record that risk.
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
