defmodule Elixos.Coproc.Epmd do
  @moduledoc """
  The distribution address book while Elixos is a node (M29, ADR-098): no epmd
  daemon, fixed ports, one known peer.

  OTP reads the kernel parameter `epmd_module` when distribution starts
  (OTP 29 `net_kernel:epmd_module/0`), and `inet_tcp_dist` asks it for
  everything it would otherwise ask epmd:

    * `listen_port_please/2` - the fixed port Elixos listens on;
    * `register_node/2,3` - nothing to register with, so only a creation;
    * `address_please/3` - the coprocessor's address and fixed port, and an
      error for any other node, so Elixos cannot dial anything else;
    * `port_please/2,3` - the same answer for callers that ask for a port.

  `start_link/0` returns `:ignore`: no process is needed. The configuration is
  a `:persistent_term`, written by `Elixos.Coproc` before it starts
  distribution and erased when it stops.
  """

  @key {__MODULE__, :config}
  # Distribution protocol version 6 (OTP 23+), which AtomVM speaks.
  @version 6

  @type peer :: {node(), :inet.ip4_address(), :inet.port_number()}

  @doc "Sets the listen port and the single dialable peer."
  @spec configure(:inet.port_number(), peer()) :: :ok
  def configure(listen_port, {node, address, port} = peer)
      when is_integer(listen_port) and is_atom(node) and tuple_size(address) == 4 and
             is_integer(port) do
    :persistent_term.put(@key, %{listen_port: listen_port, peer: peer})
  end

  @doc "Forgets the configuration."
  @spec clear() :: :ok
  def clear do
    :persistent_term.erase(@key)
    :ok
  end

  @doc false
  def start_link, do: :ignore

  @doc false
  def register_node(_name, _port), do: {:ok, creation()}

  @doc false
  def register_node(_name, _port, _family), do: {:ok, creation()}

  @doc false
  def listen_port_please(_name, _host) do
    case config() do
      %{listen_port: port} -> {:ok, port}
      nil -> {:ok, 0}
    end
  end

  @doc false
  def address_please(name, host, _family) do
    case lookup(name, host) do
      {address, port} -> {:ok, address, port, @version}
      nil -> {:error, :nxdomain}
    end
  end

  @doc false
  def port_please(name, host), do: port_please(name, host, :infinity)

  @doc false
  def port_please(name, host, _timeout) do
    case lookup(name, host) do
      {_address, port} -> {:port, port, @version}
      nil -> :noport
    end
  end

  @doc false
  def names(_host), do: {:error, :address}

  defp lookup(name, host) do
    with %{peer: {node, address, port}} <- config(),
         true <- node == :"#{name}@#{host_string(host)}" or matches_address?(node, name, host, address) do
      {address, port}
    else
      _ -> nil
    end
  end

  # inet_tcp_dist passes the host part of the node name; callers of
  # port_please/2 may pass the resolved address instead.
  defp matches_address?(node, name, host, address) when is_tuple(host) do
    host == address and String.starts_with?(Atom.to_string(node), "#{name}@")
  end

  defp matches_address?(_node, _name, _host, _address), do: false

  defp host_string(host) when is_tuple(host), do: :inet.ntoa(host) |> List.to_string()
  defp host_string(host), do: to_string(host)

  defp config, do: :persistent_term.get(@key, nil)

  defp creation, do: :rand.uniform(0xFFFF_FFF0) + 3
end
