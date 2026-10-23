defmodule Elixos do
  @moduledoc """
  Elixos: the Elixir operating system. This module is the API you use at the prompt.

      iex(1)> Elixos.info()
      %{arch: "x86_64", attempt: 1, generation: 3, mode: :normal, version: "0.1.0"}
      iex(2)> defmodule Hello, do: def(hi, do: :persisted)
      iex(3)> Elixos.save()
      {:ok, 4}
      iex(4)> Elixos.reboot()

  Everything here delegates to the modules that implement it; each stub names
  the milestone that builds it (docs/ROADMAP.md).
  """

  @doc "Boot facts: arch, generation, mode (:normal | :rescue), attempt, OS version. (M4; arch M16)"
  def info, do: Elixos.Boot.info()

  @doc "Execution boundary: :machine (own kernel), :container (shared kernel), or :host."
  def runtime, do: Elixos.Boot.runtime()

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
    # Recording is asynchronous and the journal is what the next boot replays:
    # like save/1, a graceful exit waits for everything typed so far, so a
    # defmodule entered just before Elixos.poweroff() cannot be lost in a cast
    # that never ran (M7: nothing typed is ever lost). If that wait, or an
    # agent's memory, cannot be written down, the power-off is refused: the
    # caller sees the error instead of a boot that quietly lost work.
    with :ok <- sync_recorder(),
         :ok <- snapshot_agents() do
      case request.() do
        :ok -> :init.stop()
        {:error, reason} -> {:error, reason}
      end
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
  def save(opts \\ []) do
    # Everything traced so far is recorded before the working set is written,
    # and every agent's memory is written with it: one durable moment (M15).
    # Anything that cannot be written down fails the save - a generation with
    # stale memory must not be recorded as the good one.
    with :ok <- sync_recorder(),
         :ok <- snapshot_agents(),
         {:ok, image} <- image(),
         {:ok, number} <- Elixos.Image.save(image, opts),
         :ok <- Elixos.Shim.Control.next(number) do
      # The shim boots this generation next time, provisionally, until it
      # commits (ADR-007).
      {:ok, number}
    end
  end

  # What an agent remembers survives exactly what the image does: nothing
  # else writes it, so a save (or a graceful poweroff) writes it here.
  defp snapshot_agents do
    case Process.whereis(Elixos.Agents) do
      nil -> :ok
      _pid -> Elixos.Agents.snapshot_all()
    end
  end

  @doc "Saved generation numbers, oldest first. (M6)"
  def generations do
    case image() do
      {:ok, image} -> Elixos.Image.generations(image)
      {:error, reason} -> {:error, reason}
    end
  end

  defp sync_recorder do
    case Process.whereis(Elixos.Boot.Recorder) do
      nil -> :ok
      _recorder -> Elixos.Boot.Recorder.sync()
    end
  end

  # The image is registered by Elixos.Application when the shim runs us.
  defp image do
    case Process.whereis(Elixos.Image) do
      nil -> {:error, :no_image}
      image -> {:ok, image}
    end
  end

  @doc """
  Modules defined since generation `n` that were never saved. (M7)

  The working set comes from the journal, so anything typed at a prompt is in
  it whether or not it was ever saved.
  """
  @spec unsaved(non_neg_integer()) :: [module()] | {:error, term()}
  def unsaved(n) do
    :ok = sync_recorder()

    with {:ok, image} <- image(), do: Elixos.Image.unsaved(image, n)
  end

  @doc """
  Loads unsaved modules back from the journal (Smalltalk's recover lost
  changes). (M7)
  """
  @spec recover([module()]) :: {:ok, [module()]} | {:error, term()}
  def recover(modules) do
    # A module defined a moment ago must be recorded before its blob is wanted.
    :ok = sync_recorder()

    with {:ok, image} <- image(), do: Elixos.Image.recover(image, modules)
  end
end
