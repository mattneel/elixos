import Config

# ADR-047: Jido discovery enumerates loaded application specs and calls
# Code.ensure_loaded?/1 on their modules. Merely leaving these apps stopped
# would still load their NIFs in the main VM. The release ships them as :none;
# Mix loads dependency specs before this runtime hook, so remove those specs
# before applications (including Jido's discovery task) start.
for app <- [:quickbeam, :oxc] do
  case Application.unload(app) do
    :ok ->
      :ok

    {:error, {:not_loaded, ^app}} ->
      :ok

    {:error, reason} ->
      raise "peer-only application #{app} is active in the main VM: #{inspect(reason)}"
  end
end

[]
