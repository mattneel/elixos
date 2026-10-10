defmodule HelloDep do
  @moduledoc "Fixture dependency: proves a closure installs in order."
  def value, do: :from_hello_dep
end
