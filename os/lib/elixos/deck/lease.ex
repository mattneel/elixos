defmodule Elixos.Deck.Lease do
  @moduledoc """
  Keeps the coprocessor's display lease (M33, `Elixos.Coproc.Display.lease/2`,
  os/src/coproc_display.erl): every #{2_000} ms, while the coprocessor link
  runs, it renews a lease of #{6_000} ms carrying what this BEAM knows of
  itself (`text/0`: mode, generation and boot attempt). When this BEAM goes
  away - a crash, a hang the shim kills, a restart - the lease lapses and the
  coprocessor shows `Elixos restarting, was <text>` over the last frame; the
  next BEAM's first renewal clears it.

  A separate process, linked to `Elixos.Deck`, so that a renewal that waits
  on a dead link never stalls the deck's IO server.
  """

  @renew_ms 2_000
  @ttl_ms 6_000

  @doc "The renewal interval and the lease's lifetime, in milliseconds."
  def renew_ms, do: @renew_ms
  def ttl_ms, do: @ttl_ms

  @doc """
  Starts the renewer, linked to the caller. Options (tests): `text:`,
  `renew_ms:`, `ttl_ms:`, `lease:` a `fn ttl_ms, text -> term end`.
  """
  @spec start_link(keyword()) :: pid()
  def start_link(opts \\ []) do
    text = Keyword.get_lazy(opts, :text, &text/0)
    renew_ms = Keyword.get(opts, :renew_ms, @renew_ms)
    ttl_ms = Keyword.get(opts, :ttl_ms, @ttl_ms)
    lease = Keyword.get(opts, :lease, &renew/2)
    owner = self()
    spawn_link(fn -> loop(owner, lease, ttl_ms, text, renew_ms) end)
  end

  @doc "What the lease says about this BEAM, e.g. `gen 3 attempt 1`."
  @spec text() :: String.t()
  def text do
    case Elixos.Boot.Env.current() do
      {:ok, %{mode: :rescue, generation: g, attempt: a}} -> "rescue gen #{g} attempt #{a}"
      {:ok, %{mode: :normal, generation: g, attempt: a}} -> "gen #{g} attempt #{a}"
      _ -> "host"
    end
  end

  # A deck that stops normally sends no exit signal that kills a linked
  # process, so the renewer ends with it by checking.
  defp loop(owner, lease, ttl_ms, text, renew_ms) do
    if Process.alive?(owner) do
      lease.(ttl_ms, text)
      Process.sleep(renew_ms)
      loop(owner, lease, ttl_ms, text, renew_ms)
    end
  end

  # Only while a link process runs; any failure waits for the next round.
  defp renew(ttl_ms, text) do
    if Process.whereis(Elixos.Coproc), do: Elixos.Coproc.Display.lease(ttl_ms, text)
  catch
    _, _ -> :error
  end
end
