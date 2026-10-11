defmodule Elixos.Oban.ConfigurationError do
  @moduledoc """
  Raised by `Elixos.Oban.configure_app!/2` when an app's `oban:`
  declaration is rejected (M19).

  `configure_app!/2` is the generation's boot MFA, and `Elixos.Boot.Restore`
  ignores ordinary return values - a rejected declaration has to be an
  exception, or a broken generation would boot half-configured.
  """

  defexception [:message]

  @impl true
  def exception({app, reason}) do
    %__MODULE__{
      message: "oban: declaration of #{inspect(app)} was rejected (#{inspect(reason)})"
    }
  end
end
