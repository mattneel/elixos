defmodule HelloApp do
  @moduledoc "Fixture package with a dependency."
  def greet, do: {:hello_app, HelloDep.value()}
end
