defmodule Elixos.Boot.RestoreTest do
  @moduledoc """
  Boot specifications must not hang, throw, or return an ignored service
  startup error into a half-started system (M6). Failure stops the child and
  makes the shim count the attempt and fall back (ADR-007).
  """
  use ExUnit.Case, async: false

  @moduletag milestone: 6
  @moduletag :tmp_dir

  alias Elixos.Boot.{Env, Restore}
  alias Elixos.Image
  alias Elixos.Image.Generation

  defmodule NeedsState do
    use GenServer

    def start_link(path), do: GenServer.start_link(__MODULE__, path)

    @impl true
    def init(path) do
      case File.read(path) do
        {:ok, contents} -> {:ok, contents}
        {:error, reason} -> {:stop, {:state_unavailable, reason}}
      end
    end
  end

  setup %{tmp_dir: tmp_dir} do
    root = Path.join(tmp_dir, "image")
    {:ok, image} = Image.open(root)
    %{image: image, root: root}
  end

  defp write_generation(root, boot) do
    Generation.write(Path.join(root, "generations"), %Generation{
      number: 1,
      parent: 0,
      modules: %{},
      boot: boot,
      created_at: DateTime.utc_now()
    })
  end

  defp env, do: %Env{generation: 1, mode: :normal, attempt: 1, ctl_fd: 0}

  test "a boot spec that throws fails the boot instead of skipping itself", %{
    image: image,
    root: root
  } do
    # gen_server's init dispatch reads a thrown value as its return, and
    # `throw(:ignore)` means "skip this child": the rest of the spec would be
    # skipped and the half-started generation could still be committed.
    :ok = write_generation(root, [{Kernel, :throw, [:ignore]}])
    Process.flag(:trap_exit, true)

    assert {:error, {:boot_spec_failed, 1, {:throw, :ignore}}} =
             Restore.start_link({image, env()})
  end

  test "an automatic service that cannot open its state fails boot before later actions", %{
    image: image,
    root: root
  } do
    start_supervised!({DynamicSupervisor, name: Elixos.Package.Services, strategy: :one_for_one})
    missing = Path.join(root, "missing-service-state")
    later = Path.join(root, "later-boot-action")

    :ok =
      write_generation(root, [
        {Elixos.Package, :start_service, [{NeedsState, missing}]},
        {File, :write, [later, "must not run"]}
      ])

    Process.flag(:trap_exit, true)

    assert {:error, {:boot_spec_failed, 1, _reason}} = Restore.start_link({image, env()})
    refute File.exists?(later)
  end

  test "rescue mode loads no user code, so it can fix a bad generation", %{
    image: image,
    root: root
  } do
    # The same hostile generation that fails a normal boot is skipped here.
    :ok = write_generation(root, [{Kernel, :throw, [:ignore]}])

    assert {:ok, pid} = Restore.start_link({image, %{env() | mode: :rescue}})
    assert Process.alive?(pid)
  end

  test "a boot spec that never returns is bounded, not a wedged box", %{
    image: image,
    root: root
  } do
    # Heartbeats keep the shim happy while this hangs, so without a deadline
    # the box would sit with no prompt, no exit and no attempt counted.
    :ok = write_generation(root, [{Process, :sleep, [60_000]}])
    Application.put_env(:elixos, :boot_timeout_ms, 100)
    on_exit(fn -> Application.delete_env(:elixos, :boot_timeout_ms) end)
    Process.flag(:trap_exit, true)

    assert {:error, :timeout} = Restore.start_link({image, env()})
  end
end
