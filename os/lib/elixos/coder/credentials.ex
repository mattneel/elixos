defmodule Elixos.Coder.Credentials do
  @moduledoc """
  Model credentials outside generations (M22, docs/ROADMAP.md; ADR-048).

  Credentials are redacted values, not inspectable secret strings, and never
  enter logs, the journal, session state formatting or transcripts.
  """

  @doc """
  Reads a provider's credential from `/priv/credentials/<provider>`.

  The `:elixos` application environment key `:credentials_dir` overrides that
  directory for host tests. The returned value never inspects or logs as the
  secret; only the model client's Authorization header exposes the key.
  A missing provider returns `{:error, :missing}`.
  """
  @spec fetch(String.t()) :: {:ok, term()} | {:error, :missing}
  def fetch(_provider), do: Elixos.NotImplemented.raise!(22, "Elixos.Coder.Credentials.fetch/1")
end
