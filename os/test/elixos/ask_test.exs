defmodule Elixos.AskTest do
  @moduledoc """
  The question queue on the host (M21): ordering, several askers at once, a
  timeout, a dismissal, and answers checked against the question they answer.
  The REPL front-end and the Jido action run in the M21 QEMU acceptance.
  """
  use ExUnit.Case, async: false

  @moduletag milestone: 21

  alias Elixos.Ask

  setup do
    start_supervised!(Elixos.Ask)
    :ok
  end

  test "a question blocks its asker until it is answered" do
    task = Task.async(fn -> Ask.ask(:text, prompt: "your name?", default: "matt") end)

    question = await_question()
    assert question.kind == :text
    assert question.prompt == "your name?"
    assert question.default == "matt"
    assert question.asker == task.pid

    assert Ask.answer(question.id, "ada") == :ok
    assert Task.await(task) == {:ok, "ada"}
    assert Ask.pending() == []
  end

  test "two questions are both open, and the newest can be answered first" do
    first = Task.async(fn -> Ask.ask(:text, prompt: "first?") end)
    one = await_question()
    second = Task.async(fn -> Ask.ask(:text, prompt: "second?") end)
    two = await_question(fn q -> q.id != one.id end)

    assert Ask.pending() |> Enum.map(& &1.id) == [one.id, two.id]

    assert Ask.answer(two.id, "two") == :ok
    assert Task.await(second) == {:ok, "two"}
    assert Ask.answer(one.id, "one") == :ok
    assert Task.await(first) == {:ok, "one"}
  end

  test "a question times out" do
    assert Ask.ask(:text, prompt: "anyone?", timeout: 20) == {:error, :timeout}
    assert Ask.pending() == []
  end

  test "a dismissed question is not an answer" do
    task = Task.async(fn -> Ask.ask(:text, prompt: "hello?") end)
    question = await_question()

    assert Ask.dismiss(question.id) == :ok
    assert Task.await(task) == {:error, :dismissed}
    assert Ask.pending() == []
    assert Ask.answer(question.id, "too late") == {:error, :unknown_question}
  end

  test "an answer is checked against its question" do
    task =
      Task.async(fn ->
        Ask.ask(:choice, prompt: "which?", options: ["a", "b"], allow_other: false)
      end)

    question = await_question()

    assert Ask.answer(question.id, "c") == {:error, :invalid_answer}
    assert Ask.pending() |> Enum.map(& &1.id) == [question.id]

    assert Ask.answer(question.id, "a") == :ok
    assert Task.await(task) == {:ok, "a"}
  end

  test "a multi answer is a subset, and other free text is allowed when offered" do
    task =
      Task.async(fn ->
        Ask.ask(:multi, prompt: "which ones?", options: ["a", "b", "c"], allow_other: true)
      end)

    question = await_question()

    assert Ask.answer(question.id, ["a", "z"]) == {:error, :invalid_answer}
    assert Ask.answer(question.id, ["a", "c"]) == :ok
    assert Task.await(task) == {:ok, ["a", "c"]}
  end

  test "a question whose asker goes away is dismissed, not left open" do
    task = Task.async(fn -> Ask.ask(:text, prompt: "still there?") end)
    question = await_question()
    assert question.asker == task.pid

    Task.shutdown(task)

    assert Ask.pending() == []
  end

  defp await_question(match \\ fn _question -> true end, tries \\ 200) do
    found =
      Enum.reduce_while(1..tries, nil, fn _, _ ->
        case Enum.find(Ask.pending(), match) do
          nil ->
            Process.sleep(10)
            {:cont, nil}

          question ->
            {:halt, question}
        end
      end)

    found || flunk("no question appeared in the queue")
  end
end
