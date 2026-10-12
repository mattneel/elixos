defmodule Elixos.Toolset.Core do
  @moduledoc """
  The image-owned OMP pure core (M21, ADR-047/ADR-048).

  `scripts/build-omp-core.ts` compiles the pinned upstream implementations and
  argument-validation pipeline. The compiled JavaScript is a module literal,
  not a mutable runtime file: saving this BEAM module saves the tool code with
  the generation. It is evaluated only inside the supervised peer.
  """

  @source_file Path.expand("../../../priv/toolset/core.js", __DIR__)
  @notice_file Path.expand("../../../priv/toolset/THIRD-PARTY-NOTICES", __DIR__)
  @external_resource @source_file
  @external_resource @notice_file
  @source File.read!(@source_file)
  @notices File.read!(@notice_file)
  @revision :crypto.hash(:sha256, @source) |> Base.encode16(case: :lower)

  @doc "The compiled generation's JavaScript, for a peer context only."
  def source, do: @source

  @doc "The content digest of this generation's pure core."
  def revision, do: @revision

  @doc "Copyright and license notices accompanying the compiled source."
  def notices, do: @notices

  @doc "Executes the upstream validator and tool, retaining its raw result/error envelope."
  def call(context, tool, params, timeout) do
    case QuickBEAM.Context.call(context, "__ompCoreCall", [tool, params], timeout: timeout) do
      {:ok, wire} when is_binary(wire) ->
        case :json.decode(wire) do
          %{"output" => output} -> {:ok, output}
          %{"error" => error} -> {:error, error}
        end

      {:error, error} ->
        {:error, error}
    end
  end
end
