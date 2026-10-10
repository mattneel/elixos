defmodule Elixos.SSH do
  @moduledoc """
  Remote login straight into the user's REPL (M12).

  OTP's `ssh` daemon takes a shell fun receiving the authenticated user and
  peer address and returning the shell's pid, so a per-user REPL is a lookup
  in `Elixos.User` followed by `Elixos.REPL.mfa/1`. Single user (ADR-013):
  public-key auth against `/data/home/.ssh/authorized_keys`, no passwords.

  Host keys are generated on first boot and kept in `/data/ssh/`.
  """

  @spec start(keyword()) :: {:ok, pid()} | {:error, term()}
  def start(opts \\ []),
    do: Elixos.NotImplemented.raise!(12, "Elixos.SSH.start/1 #{inspect(opts)}")
end
