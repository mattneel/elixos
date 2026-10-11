defmodule Elixos.PrivilegesTest do
  @moduledoc """
  M17: helper-name boundaries, exact control requests and newline-free replies,
  and invalid requests rejected without a running shim (docs/ROADMAP.md, ADR-046).

  Reference note: none of these acceptance tests has been validated against a
  reference implementation yet; the M17 implementation does not exist yet.
  """
  use ExUnit.Case, async: true

  @moduletag milestone: 17

  alias Elixos.Privileges

  @invalid_names ["", String.duplicate("a", 33), "UPPER", "/", ".", "..", "a b", "é", "١", "a\n"]

  test "names accept exactly one to 32 lowercase ASCII letters, digits and hyphens" do
    for name <- ["a", "0", "-", "postgres-17", String.duplicate("a", 32)] do
      assert Privileges.valid_name?(name) == true, inspect(name)
    end

    for name <- @invalid_names do
      assert Privileges.valid_name?(name) == false, inspect(name)
    end
  end

  test "request encoding preserves the name and includes exactly one newline" do
    assert Privileges.encode_request("initdb") == {:ok, "HELPER initdb\n"}
    name = String.duplicate("a", 32)
    assert Privileges.encode_request(name) == {:ok, "HELPER " <> name <> "\n"}
  end

  test "request encoding rejects invalid names rather than emitting a control line" do
    for name <- @invalid_names do
      assert Privileges.encode_request(name) == {:error, :invalid_name}, inspect(name)
    end
  end

  test "replies preserve helper names and accept positive canonical u32 pids" do
    assert Privileges.parse_reply("HELPER initdb OK 1") == {:ok, "initdb", 1}
    assert Privileges.parse_reply("HELPER postgres-17 OK 42") == {:ok, "postgres-17", 42}

    assert Privileges.parse_reply("HELPER initdb OK 4294967295") ==
             {:ok, "initdb", 4_294_967_295}

    name = String.duplicate("a", 32)
    assert Privileges.parse_reply("HELPER " <> name <> " OK 7") == {:ok, name, 7}
    assert Privileges.parse_reply("HELPER no-such-helper REFUSED") == {:refused, "no-such-helper"}
  end

  test "reply parsing rejects malformed lines and invalid helper names" do
    malformed = [
      "",
      "HELPER",
      "HELPER initdb",
      "HELPER initdb OK",
      "HELPER initdb UNKNOWN",
      "helper initdb OK 1",
      " HELPER initdb OK 1",
      "HELPER  initdb OK 1",
      "HELPER initdb OK 1 ",
      "HELPER initdb OK 1 extra",
      "HELPER initdb REFUSED 1",
      "HELPER initdb REFUSED\n",
      "HELPER initdb OK 1\n",
      "HELPER initdb OK 1\r",
      "HELPER initdb OK 1\nHELPER initdb REFUSED"
    ]

    for line <- malformed do
      assert Privileges.parse_reply(line) == {:error, :invalid}, inspect(line)
    end

    for name <- @invalid_names, suffix <- [" OK 1", " REFUSED"] do
      line = "HELPER " <> name <> suffix
      assert Privileges.parse_reply(line) == {:error, :invalid}, inspect(line)
    end
  end

  test "reply pids reject zero, signs, leading zeros, non-digits and u32 overflow" do
    for pid <- ["0", "00", "01", "+1", "-1", "1.0", "0x1", "١", "4294967296", "99999999999"] do
      line = "HELPER initdb OK " <> pid
      assert Privileges.parse_reply(line) == {:error, :invalid}, inspect(line)
    end
  end

  test "invalid helper requests fail before opening either shim pipe" do
    for name <- @invalid_names do
      assert Privileges.request(name) == {:error, :invalid_name}, inspect(name)
    end
  end
end
