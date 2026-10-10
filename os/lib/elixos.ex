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
  def info, do: Elixos.Boot.info()

  @doc "Ask the shim to reboot once the VM has stopped. (M4)"
  def reboot, do: request_shutdown(&Elixos.Shim.Control.reboot/0)

  @doc "Ask the shim to power off once the VM has stopped. (M4)"
  def poweroff, do: request_shutdown(&Elixos.Shim.Control.poweroff/0)

  @doc "Ask the shim to halt once the VM has stopped. (M4)"
  def halt, do: request_shutdown(&Elixos.Shim.Control.halt/0)

  # The shim remembers the request and carries it out when we are gone
  # (PROTOCOL.md §2), so the last thing we do is stop the VM. PID 1 is the
  # only thing that can power the machine off; we just ask.
  defp request_shutdown(request) do
    case request.() do
      :ok -> :init.stop()
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Mark the running generation healthy now instead of waiting for auto-commit. (M5)"
  def commit do
    case Elixos.Boot.Env.current() do
      {:ok, %Elixos.Boot.Env{generation: generation}} -> Elixos.Shim.Control.commit(generation)
      {:ok, :host} -> {:error, :not_under_the_shim}
      {:error, reason} -> {:error, reason}
    end
  end

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
