defmodule Elixos.Candidate do
  @moduledoc """
  Generation-only self-modification (M23, docs/ROADMAP.md, ADR-049).

  A working tree is built in a child ERTS and tested in a peer node. Neither
  step loads its modules into the caller's VM. A proposal requests NEXT; only
  boot-time system and toolset health checks can commit it.

  Candidates are opaque maps containing their generation manifest. `build/2`
  accepts `:provenance`, a map containing `:session`, `:model`, `:tools` (the
  dispatcher's revision records), and `:parent`. This is stored in the manifest
  and is read back unchanged by `provenance/1`. Host storage follows the
  existing `:elixos, :priv_dir` setting; on the machine it is `/priv`.
  """

  @type provenance :: %{
          session: term(),
          model: String.t(),
          tools: map(),
          parent: non_neg_integer()
        }
  @opaque t :: %{required(:manifest) => Elixos.Image.Generation.t(), optional(atom()) => term()}

  @doc "Checks out the running generation's source into a working tree."
  @spec checkout(Path.t()) :: {:ok, Path.t()} | {:error, term()}
  def checkout(_path), do: Elixos.NotImplemented.raise!(23, "Elixos.Candidate.checkout/1")

  @doc "Builds a working tree in a child ERTS, recording its provenance."
  @spec build(Path.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def build(_source, _opts), do: Elixos.NotImplemented.raise!(23, "Elixos.Candidate.build/2")

  @doc "Runs the full portable system and recorded-tool suites in a peer, returning named failures."
  @spec test(t()) :: :ok | {:error, term()}
  def test(_candidate), do: Elixos.NotImplemented.raise!(23, "Elixos.Candidate.test/1")

  @doc "Proposes the candidate as NEXT and returns its generation; the caller reboots."
  @spec propose(t()) :: {:ok, pos_integer()} | {:error, term()}
  def propose(_candidate), do: Elixos.NotImplemented.raise!(23, "Elixos.Candidate.propose/1")

  @doc "Reads the producing session, model, tool revisions and parent from a manifest."
  @spec provenance(non_neg_integer()) :: {:ok, provenance()} | {:error, term()}
  def provenance(_generation),
    do: Elixos.NotImplemented.raise!(23, "Elixos.Candidate.provenance/1")

  @doc "Returns `/priv/evidence/<generation>`, retained even after fallback."
  @spec evidence_dir(non_neg_integer()) :: Path.t()
  def evidence_dir(_generation),
    do: Elixos.NotImplemented.raise!(23, "Elixos.Candidate.evidence_dir/1")
end
