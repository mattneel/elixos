defmodule Elixos.Boot.AutoCommitSpecTest do
  @moduledoc """
  The child spec of a one-shot (added while fixing M5's review findings).

  `AutoCommit.commit` once and exits `:normal`; under a supervisor a
  `:permanent` restart would commit on every restart, and with a short
  `elixos.commit_after` those restarts would exceed the supervisor's restart
  limit and take the tree down. The shipped test starts the process directly,
  so only the spec can catch it.
  """
  use ExUnit.Case, async: true

  @moduletag milestone: 5

  alias Elixos.Boot.AutoCommit

  test "the commit child does not restart after it has committed" do
    assert %{restart: :transient} = AutoCommit.child_spec([])
  end
end
