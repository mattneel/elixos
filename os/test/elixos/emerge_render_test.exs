defmodule Elixos.EmergeRenderTest do
  @moduledoc """
  The Ask dialogs render with no display (M21): the renderer is headless
  raster, and `Elixos.GUI.render_dialog/1` hands the pixels back, so every
  kind of question is tested on the host, not only on the machine's screen.
  """
  use ExUnit.Case, async: true

  @moduletag milestone: 21

  alias Elixos.Ask.Question
  alias Elixos.GUI

  defp question(kind) do
    %Question{
      id: "q1",
      kind: kind,
      prompt: "pick one",
      options: ["alpha", "beta", "gamma"],
      asker: self(),
      default: nil,
      timeout: nil,
      allow_other: kind in [:choice, :multi]
    }
  end

  for kind <- [:text, :choice, :multi, :confirm] do
    test "#{kind} renders off-screen" do
      assert {:ok, %{width: width, height: height, pixels: pixels}} =
               GUI.render_dialog(question(unquote(kind)))

      assert width > 0 and height > 0
      assert byte_size(pixels) == width * height * 4

      # A dialog was drawn: the corners share a background, and something
      # (text, an option row, a border) differs from it.
      background = pixel(pixels, width, 0, 0)
      assert pixel(pixels, width, width - 1, 0) == background
      assert pixel(pixels, width, 0, height - 1) == background

      assert Enum.any?(0..(height - 1), fn y ->
               Enum.any?(0..(width - 1), fn x -> pixel(pixels, width, x, y) != background end)
             end)
    end
  end

  defp pixel(pixels, width, x, y) do
    <<r, g, b, a>> = binary_part(pixels, (y * width + x) * 4, 4)
    {r, g, b, a}
  end
end
