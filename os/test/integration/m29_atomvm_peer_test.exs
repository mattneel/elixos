defmodule Elixos.Integration.M29AtomVMPeerTest do
  @moduledoc """
  M29: AtomVM's Unix build on the host and Elixos in QEMU form one BEAM
  cluster over a virtual link. Distribution is internal-only: the listener is
  bound to the coprocessor link, the cookie lives in /priv, and nothing else
  can reach it. Coprocessor `.avm` bundles are generation content.
  """
  use ExUnit.Case, async: false

  @moduletag :qemu
  @moduletag milestone: 29
  @moduletag timeout: 900_000
  @moduletag :tmp_dir

  test "AtomVM and Elixos connect over the virtual link and spawn, send, receive, monitor and link across nodes" do
    # Behaviour: with the cookie from /priv, the host AtomVM node and Elixos in
    # QEMU connect over the virtual link; Node.list() on Elixos shows the
    # AtomVM node; a process spawned on AtomVM from IEx receives a message and
    # replies; a monitor and a link across the nodes deliver :DOWN / exit
    # signals when the remote process ends.
    Elixos.NotImplemented.raise!(29, "AtomVM peer: connect with cookie, spawn/send/receive/monitor/link")
  end

  test "killing AtomVM raises nodedown and Elixos.Coproc reconnects" do
    # Behaviour: a :net_kernel.monitor_nodes subscriber in IEx sees
    # {:nodedown, coproc} when the host AtomVM process is killed, and
    # {:nodeup, coproc} after AtomVM is restarted, without any call from IEx.
    Elixos.NotImplemented.raise!(29, "AtomVM peer: nodedown on kill, Elixos.Coproc reconnects")
  end

  test "a new coprocessor bundle deploys and runs, and fallback restores the old one" do
    # Behaviour: saving a generation with a new .avm bundle deploys it to the
    # coprocessor and restarts its VM, and a call into it answers with the new
    # value; falling back to last_good restores the matching old bundle, and
    # the same call answers with the old value.
    Elixos.NotImplemented.raise!(29, "coprocessor bundle deploy and fallback to last_good")
  end

  test "distribution is not reachable from any interface but the coprocessor link" do
    # Behaviour: the distribution listener (and epmd, if any) accepts on the
    # coprocessor link's address only; a connection attempt from the user-mode
    # network's external side to the distribution port is refused.
    Elixos.NotImplemented.raise!(29, "distribution listener bound to the coprocessor link only")
  end
end
