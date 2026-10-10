defmodule Elixos do
  @moduledoc """
  Elixos: the Elixir operating system. This module is the API you use at the prompt.

      iex(1)> Elixos.info()
      %{generation: 3, mode: :normal, attempt: 1, version: "0.1.0"}
      iex(2)> defmodule Hello, do: def(hi, do: :persisted)
      iex(3)> Elixos.save()
      {:ok, 4}
      iex(4)> Elixos.reboot()

  Everything here delegates to the modules that implement it; each stub names
  the milestone that builds it (docs/ROADMAP.md).
  """

  @doc "Boot facts: generation, mode (:normal | :rescue), attempt, OS version. (M4)"
  def info, do: Elixos.NotImplemented.raise!(4, "Elixos.info/0")

  @doc "Ask the shim to reboot once the VM has stopped. (M4)"
  def reboot, do: Elixos.NotImplemented.raise!(4, "Elixos.reboot/0")

  @doc "Ask the shim to power off once the VM has stopped. (M4)"
  def poweroff, do: Elixos.NotImplemented.raise!(4, "Elixos.poweroff/0")

  @doc "Ask the shim to halt once the VM has stopped. (M4)"
  def halt, do: Elixos.NotImplemented.raise!(4, "Elixos.halt/0")

  @doc "Mark the running generation healthy now instead of waiting for auto-commit. (M5)"
  def commit, do: Elixos.NotImplemented.raise!(5, "Elixos.commit/0")

  @doc """
  Save the live image as a new generation and select it for the next boot. (M6)

  Options: `boot: [{module, function, args}]` to run at boot in that generation.
  """
  def save(opts \\ []), do: Elixos.NotImplemented.raise!(6, "Elixos.save/1 #{inspect(opts)}")

  @doc "Saved generation numbers, oldest first. (M6)"
  def generations, do: Elixos.NotImplemented.raise!(6, "Elixos.generations/0")

  @doc "Modules defined since generation `n` that were never saved. (M7)"
  def unsaved(n), do: Elixos.NotImplemented.raise!(7, "Elixos.unsaved/1 #{n}")

  @doc "Load unsaved modules back from the journal (Smalltalk's recover lost changes). (M7)"
  def recover(modules),
    do: Elixos.NotImplemented.raise!(7, "Elixos.recover/1 #{inspect(modules)}")
end
