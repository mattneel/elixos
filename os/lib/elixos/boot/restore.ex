defmodule Elixos.Boot.Restore do
  @moduledoc """
  Brings the generation the shim launched into the running VM (M6, M7).

  `booting generation G means: load every module of G from the store, run G's
  boot spec, then start the login REPL` (docs/ARCHITECTURE.md §4.4). This is
  that step, as a supervised child that runs between the control channel and
  the REPL: its `init/1` blocks until the generation is loaded, so a failure
  stops the tree — and the VM exits non-zero, which is what makes the shim
  count the attempt and fall back (ADR-007).

  Generation 0 is the factory: its code is already loaded, and there is
  nothing to restore.
  """

  use GenServer

  alias Elixos.Boot.Env
  alias Elixos.Image

  @doc "Starts the restore for `image`, linked to the caller."
  def start_link({image, env}) do
    # The boot spec runs in init/1, so the start's own timeout bounds it. A
    # spec that never returns would otherwise wedge the box: the heartbeats
    # keep the shim happy, and neither the login shell nor a commit ever
    # starts. Bounded, it is a failed boot, and the shim counts the attempt
    # (ADR-007).
    GenServer.start_link(__MODULE__, {image, env}, name: __MODULE__, timeout: boot_timeout_ms())
  end

  defp boot_timeout_ms do
    Application.get_env(:elixos, :boot_timeout_ms, 30_000)
  end

  @impl true
  def init({image, %Env{} = env}) do
    # Rescue mode loads no user code (docs/ROADMAP.md M7): it exists to fix a
    # bad generation, so it must not run that generation's modules or boot spec.
    if env.mode == :rescue do
      {:ok, env}
    else
      with :ok <- restore_generation(image, env.generation),
           :ok <- run_boot_spec(image, env.generation) do
        {:ok, env}
      end
    end
  end

  def init({_image, :host}), do: :ignore

  defp restore_generation(_image, 0), do: :ok

  defp restore_generation(image, generation) do
    case Image.restore(image, generation) do
      {:ok, _modules} -> :ok
      {:error, reason} -> {:stop, {:restore_failed, generation, reason}}
    end
  end

  defp run_boot_spec(_image, 0), do: :ok

  defp run_boot_spec(image, generation) do
    case Image.generation(image, generation) do
      {:ok, %Elixos.Image.Generation{boot: boot}} ->
        # Boot MFAs are user code with a throw-shaped hole under them:
        # gen_server's init dispatch reads `throw(:ignore)` (and any thrown
        # value) as "skip this child", which would silently skip the rest of
        # the spec and still let AutoCommit commit the generation. Throwing is
        # a failed boot, not an omitted child.
        try do
          Enum.reduce_while(boot, :ok, fn {module, function, args}, :ok ->
            case apply(module, function, args) do
              {:error, reason} ->
                {:halt, {:stop, {:boot_spec_failed, generation, {:error, reason}}}}

              _result ->
                {:cont, :ok}
            end
          end)
        catch
          kind, reason -> {:stop, {:boot_spec_failed, generation, {kind, reason}}}
        end

      {:error, reason} ->
        {:stop, {:boot_spec_unreadable, generation, reason}}
    end
  end
end
