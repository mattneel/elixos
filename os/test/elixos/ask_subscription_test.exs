defmodule Elixos.AskSubscriptionTest do
  use ExUnit.Case, async: false

  @moduletag milestone: 27

  alias Elixos.Ask

  setup do
    start_supervised!(Ask)
    :ok
  end

  test "a view gets an atomic snapshot, additions and successful resolution, not invalid answers" do
    assert Ask.subscribe() == {:ok, []}
    asker = Task.async(fn -> Ask.ask(:confirm, prompt: "proceed?") end)
    assert_receive {:elixos_ask, [question]}, 1_000
    assert question.kind == :confirm
    assert question.prompt == "proceed?"
    assert Ask.subscribe() == {:ok, [question]}

    assert Ask.answer(question.id, "yes") == {:error, :invalid_answer}
    assert Ask.pending() == [question]
    refute_receive {:elixos_ask, _}, 20

    assert Ask.answer(question.id, true) == :ok
    assert_receive {:elixos_ask, []}, 1_000
    assert Task.await(asker) == {:ok, true}
  end

  test "a later question does not replace the oldest, and closing it advances the view" do
    assert Ask.subscribe() == {:ok, []}
    first = Task.async(fn -> Ask.ask(:text, prompt: "first") end)
    assert_receive {:elixos_ask, [one]}, 1_000
    second = Task.async(fn -> Ask.ask(:text, prompt: "second") end)
    assert_receive {:elixos_ask, [^one, two]}, 1_000
    assert two.prompt == "second"

    assert Ask.answer(one.id, "one") == :ok
    assert_receive {:elixos_ask, [^two]}, 1_000
    assert Task.await(first) == {:ok, "one"}
    assert Ask.dismiss(two.id) == :ok
    assert_receive {:elixos_ask, []}, 1_000
    assert Task.await(second) == {:error, :dismissed}
  end

  test "timeouts and an asker dying remove the dialog from subscribed views" do
    assert Ask.subscribe() == {:ok, []}
    timed = Task.async(fn -> Ask.ask(:text, prompt: "expires", timeout: 30) end)
    assert_receive {:elixos_ask, [question]}, 1_000
    assert question.prompt == "expires"
    assert_receive {:elixos_ask, []}, 1_000
    assert Task.await(timed) == {:error, :timeout}

    abandoned = Task.async(fn -> Ask.ask(:text, prompt: "abandoned") end)
    assert_receive {:elixos_ask, [question]}, 1_000
    assert question.prompt == "abandoned"
    Task.shutdown(abandoned)
    assert_receive {:elixos_ask, []}, 1_000
    assert Ask.pending() == []
  end
end
