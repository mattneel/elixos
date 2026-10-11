defmodule Elixos.Privileges do
  @moduledoc """
  Named privileged helpers and the BEAM's real uid (M17, docs/ROADMAP.md).

  The shim reads the image's allow-list once and executes helpers directly.
  The unprivileged BEAM can request a name, never a command or another uid.
  """

  @doc "Requests an allow-listed helper, validating its name before using the control pipe."
  @spec request(String.t()) ::
          {:ok, pos_integer()} | {:error, :refused | :invalid_name | :timeout}
  def request(_name), do: Elixos.NotImplemented.raise!(17, "Elixos.Privileges.request/1")

  @doc "Whether the name is one to 32 ASCII lowercase letters, digits or hyphens."
  @spec valid_name?(String.t()) :: boolean()
  def valid_name?(_name), do: Elixos.NotImplemented.raise!(17, "Elixos.Privileges.valid_name?/1")

  @doc "Encodes a valid name as a HELPER request including its trailing newline."
  @spec encode_request(String.t()) :: {:ok, binary()} | {:error, :invalid_name}
  def encode_request(_name),
    do: Elixos.NotImplemented.raise!(17, "Elixos.Privileges.encode_request/1")

  @doc "Parses a newline-free HELPER reply; successful pids are positive canonical u32 values."
  @spec parse_reply(binary()) ::
          {:ok, String.t(), pos_integer()} | {:refused, String.t()} | {:error, :invalid}
  def parse_reply(_line), do: Elixos.NotImplemented.raise!(17, "Elixos.Privileges.parse_reply/1")

  @doc "Returns the running BEAM's real operating-system uid."
  @spec uid() :: non_neg_integer()
  def uid, do: Elixos.NotImplemented.raise!(17, "Elixos.Privileges.uid/0")
end
