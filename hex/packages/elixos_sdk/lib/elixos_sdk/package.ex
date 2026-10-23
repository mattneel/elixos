defmodule ElixosSDK.Package do
  @moduledoc false

  def dependencies(dependencies) do
    Enum.filter(dependencies, fn dependency ->
      {_app, _requirement, options} = normalize(dependency)
      includes?(options, :only, :prod) and includes?(options, :targets, :elixos)
    end)
  end

  def require_os!(dependencies) do
    os = Enum.find(dependencies, &(elem(&1, 0) == :elixos))

    case os && normalize(os) do
      {:elixos, requirement, options} when is_binary(requirement) ->
        unless Version.parse_requirement(requirement) != :error and
                 not Keyword.get(options, :optional, false) and
                 not Enum.any?(
                   [:path, :git, :github, :in_umbrella],
                   &Keyword.has_key?(options, &1)
                 ) and
                 Keyword.get(options, :hex, :elixos) in [:elixos, "elixos"] do
          invalid_os!()
        end

        :ok

      _ ->
        invalid_os!()
    end
  end

  defp includes?(options, key, value) do
    case Keyword.fetch(options, key) do
      :error -> true
      {:ok, values} -> value in List.wrap(values)
    end
  end

  defp normalize({app, requirement}) when is_binary(requirement), do: {app, requirement, []}
  defp normalize({app, options}) when is_list(options), do: {app, nil, options}
  defp normalize({app, requirement, options}), do: {app, requirement, options}

  defp invalid_os! do
    Mix.raise(
      "An Elixos source package requires a non-optional Hex dependency {:elixos, \"~> 0.1\", targets: :elixos}; the running OS supplies it, never a path or git checkout"
    )
  end
end
