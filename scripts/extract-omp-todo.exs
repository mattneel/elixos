# Build-time extraction, not a runtime tool or a rewritten state machine.
# Only /todo's filesystem-path helper and its import leave the pure bundle;
# all schema, execution, transition, rendering and validation bytes stay intact.
[source_file] = System.argv()
source = File.read!(source_file)
peer = Elixos.Toolset.Peer.node()
{:ok, ast} = :erpc.call(peer, OXC, :parse, [source, source_file])

spans =
  Enum.flat_map(ast.body, fn node ->
    declaration = Map.get(node, :declaration)

    cond do
      node.type == :import_declaration and node.source.value == "./path-utils" ->
        [{node.start, node.end}]

      is_map(declaration) and get_in(declaration, [:id, :name]) == "resolveTodoMarkdownPath" ->
        [{node.start, node.end}]

      true ->
        []
    end
  end)
  |> Enum.sort()

2 = length(spans)

{pieces, cursor} =
  Enum.reduce(spans, {[], 0}, fn {first, last}, {pieces, cursor} ->
    {[binary_part(source, cursor, first - cursor) | pieces], last}
  end)

pure = [Enum.reverse(pieces), binary_part(source, cursor, byte_size(source) - cursor)]
false = :code.is_loaded(QuickBEAM.Native)
false = :code.is_loaded(OXC.Native)

IO.write(
  IO.iodata_to_binary(
    :json.encode(%{
      source: IO.iodata_to_binary(pure),
      upstream_sha256: :crypto.hash(:sha256, source) |> Base.encode16(case: :lower),
      excluded: ["./path-utils", "resolveTodoMarkdownPath"]
    })
  )
)
