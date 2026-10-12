defmodule Elixos.ToolsetCapabilitiesTest do
  use ExUnit.Case, async: false

  @moduletag milestone: 21
  @moduletag :tmp_dir

  alias Elixos.Toolset
  alias Elixos.Toolset.{Peer, Session}

  test "discovery cannot load peer NIFs or grant unscoped Beam effects", ctx do
    :ok = Jido.Discovery.refresh()
    assert :code.is_loaded(QuickBEAM.Native) == false
    assert :code.is_loaded(OXC.Native) == false

    session = Session.new(workspace: ctx.tmp_dir, session_dir: ctx.tmp_dir)
    assert {:ok, _} = Toolset.call("think", %{"thoughts" => "private"}, session: session)
    peer = Peer.node()
    assert peer != node()
    assert {:file, _} = :erpc.call(peer, :code, :is_loaded, [QuickBEAM.Native])
    host = :erpc.call(peer, :sys, :get_state, [Elixos.Toolset.Host])
    context = host.contexts[session.id].context

    assert {:error, error} =
             :erpc.call(peer, QuickBEAM.Context, :eval, [
               context,
               "Beam.callSync('__beam_rpc', 'forbidden', 'forbidden', 'forbidden')",
               [timeout: 5000]
             ])

    assert error.message =~ "Unscoped Beam APIs are disabled"
    assert :code.is_loaded(QuickBEAM.Native) == false
    assert :code.is_loaded(OXC.Native) == false
  end
end
