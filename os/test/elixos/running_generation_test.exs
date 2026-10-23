defmodule Elixos.RunningGenerationTest do
  use ExUnit.Case, async: false

  @moduletag milestone: 27
  @moduletag :tmp_dir

  alias Elixos.{Candidate, Image}

  setup %{tmp_dir: tmp} do
    priv = Path.join(tmp, "priv")
    previous = Application.fetch_env(:elixos, :priv_dir)
    Application.put_env(:elixos, :priv_dir, priv)
    {:ok, image} = Image.open(priv)

    on_exit(fn ->
      if Process.alive?(image), do: Image.close(image)

      case previous do
        {:ok, value} -> Application.put_env(:elixos, :priv_dir, value)
        :error -> Application.delete_env(:elixos, :priv_dir)
      end
    end)

    %{image: image}
  end

  defp compile(name, value) do
    [{module, bytecode}] =
      Code.compile_string("defmodule #{name} do\n  def value, do: #{inspect(value)}\nend")

    {module, bytecode}
  end

  defp unload(module) do
    :code.purge(module)
    :code.delete(module)
    :code.purge(module)
  end

  test "a saved prompt module that is loaded matches its stored generation", %{image: image} do
    {module, bytecode} = compile("Elixos.RunningGenerationProbe", :saved)
    on_exit(fn -> unload(module) end)
    {:ok, _hash} = Image.record(image, module, bytecode)
    assert {:ok, number} = Image.save(image)

    assert Candidate.verify_running_generation(number) == :ok
  end

  test "a module redefined after saving is not the stored generation", %{image: image} do
    {module, bytecode} = compile("Elixos.RunningGenerationDrift", :saved)
    on_exit(fn -> unload(module) end)
    {:ok, _hash} = Image.record(image, module, bytecode)
    assert {:ok, number} = Image.save(image)

    compile("Elixos.RunningGenerationDrift", :changed)

    assert Candidate.verify_running_generation(number) ==
             {:error, {:running_generation_mismatch, module}}
  end
end
