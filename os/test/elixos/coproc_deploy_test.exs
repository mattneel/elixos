defmodule Elixos.CoprocDeployTest do
  @moduledoc """
  M29: the coprocessor runs the bundle Elixos wants (ADR-099). On connect,
  Elixos.Coproc compares the bundle the peer reports with the wanted one and
  deploys on a difference; the runtime stores it and restarts AtomVM, which
  then reports it. Against the host AtomVM stand-in.
  """
  use ExUnit.Case, async: false

  alias Elixos.Test.AtomVM

  @moduletag milestone: 29
  @moduletag :tmp_dir

  setup ctx do
    %{a: bundle(1), b: bundle(2), cookie: Base.encode16(:crypto.strong_rand_bytes(16)), dir: ctx.tmp_dir}
  end

  test "the wanted bundle is deployed when the coprocessor comes up running another", ctx do
    vm = AtomVM.start(ctx.dir, cookie: ctx.cookie)
    assert AtomVM.await_up(vm) == "none"

    start_link!(vm, ctx.cookie, bundle: ctx.a)

    # Deployed, AtomVM restarted on it, and it reports the bundle.
    assert AtomVM.await_up(vm, 2) == Elixos.Coproc.Bundle.digest(ctx.a)
    assert AtomVM.bundle_digest(vm) == Elixos.Coproc.Bundle.digest(ctx.a)
    assert eventually(fn -> Elixos.Coproc.status().digest == Elixos.Coproc.Bundle.digest(ctx.a) end)
    assert Elixos.Coproc.call(Elixos.CoprocDeployTest.Version, :value, []) == {:ok, 1}
  end

  test "deploy/1 switches bundles and returns once the coprocessor runs the new one", ctx do
    vm = AtomVM.start(ctx.dir, cookie: ctx.cookie, bundle: ctx.a)
    AtomVM.await_up(vm)
    start_link!(vm, ctx.cookie, bundle: ctx.a)
    assert eventually(fn -> Elixos.Coproc.status().connected end)
    # Already the wanted bundle: nothing to deploy, no restart.
    assert Elixos.Coproc.deploy(ctx.a) == {:ok, Elixos.Coproc.Bundle.digest(ctx.a)}

    assert Elixos.Coproc.deploy(ctx.b) == {:ok, Elixos.Coproc.Bundle.digest(ctx.b)}
    assert Elixos.Coproc.call(Elixos.CoprocDeployTest.Version, :value, []) == {:ok, 2}

    assert Elixos.Coproc.deploy(nil) == {:ok, :none}
    assert AtomVM.bundle_digest(vm) == nil
    assert {:error, {:exception, :undef, _}} = Elixos.Coproc.call(Elixos.CoprocDeployTest.Version, :value, [])
  end

  test "a bundle the coprocessor cannot take is refused before anything restarts", ctx do
    vm = AtomVM.start(ctx.dir, cookie: ctx.cookie, bundle: ctx.a)
    AtomVM.await_up(vm)
    start_link!(vm, ctx.cookie)
    assert eventually(fn -> Elixos.Coproc.status().connected end)

    assert {:error, {:deploy, {:error, :invalid_bundle}}} = Elixos.Coproc.deploy("not an archive", 10_000)
    assert AtomVM.bundle_digest(vm) == Elixos.Coproc.Bundle.digest(ctx.a)
  end

  defp bundle(value) do
    [{module, beam}] =
      Code.compile_string("""
      defmodule Elixos.CoprocDeployTest.Version do
        def value, do: #{value}
      end
      """)

    :code.purge(module)
    :code.delete(module)
    {:ok, bundle} = Elixos.Coproc.Bundle.pack([{module, beam}])
    bundle
  end

  defp start_link!(vm, cookie, opts \\ []) do
    start_supervised!(
      {Elixos.Coproc,
       [node: vm.node, port: vm.port, listen: {{127, 0, 0, 1}, AtomVM.free_port()},
        cookie: cookie, reconnect_ms: 200] ++ opts}
    )
  end

  defp eventually(fun, deadline \\ System.monotonic_time(:millisecond) + 15_000) do
    cond do
      fun.() -> true
      System.monotonic_time(:millisecond) > deadline -> false
      true -> Process.sleep(50) && eventually(fun, deadline)
    end
  end
end
