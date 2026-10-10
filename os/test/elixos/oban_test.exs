defmodule Elixos.ObanTest do
  @moduledoc """
  An app declares its queues and its cron in its `elixos:` key, next to its
  services, and the declaration becomes Oban's options (M17). The running
  scheduler - jobs, retries, a power cycle - is the M17 QEMU acceptance's
  business.
  """
  use ExUnit.Case, async: true

  @moduletag milestone: 17

  alias Elixos.Package.Spec

  @project [
    elixos: [
      oban: [
        queues: [jobs: 3, mail: 1],
        cron: [{"0 3 * * *", Demo.Worker}]
      ]
    ]
  ]

  test "queues and cron parse like services do" do
    assert {:ok, spec} = Spec.from_project(@project)

    assert %Spec{oban: [queues: [jobs: 3, mail: 1], cron: [{"0 3 * * *", Demo.Worker}]]} =
             spec
  end

  test "a declaration without oban declares nothing" do
    assert {:ok, spec} = Spec.from_project(elixos: [services: []])
    assert %Spec{oban: []} = spec
  end

  test "a malformed declaration is refused, naming the key" do
    assert {:error, errors} = Spec.from_project(elixos: [oban: [queues: :many]])
    assert Keyword.get(errors, :oban) == :invalid

    assert {:error, errors} =
             Spec.from_project(elixos: [oban: [cron: [{"0 3 * * *"}]]])

    assert Keyword.get(errors, :oban) == :invalid
  end

  test "a declaration becomes Oban's options" do
    assert {:ok, spec} = Spec.from_project(@project)
    options = Elixos.Oban.options(spec)

    assert Keyword.get(options, :queues) == [jobs: 3, mail: 1]
    assert [%{crontab: [{"0 3 * * *", Demo.Worker}]}] = Keyword.get(options, :plugins)
  end
end
