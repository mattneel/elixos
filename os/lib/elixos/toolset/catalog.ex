defmodule Elixos.Toolset.Catalog do
  @moduledoc """
  The revision-pinned OMP descriptor catalog (M21, docs/ROADMAP.md, ADR-047).

  `scripts/build-omp-catalog.ts` constructs each tool of the pinned
  Oh-My-Pi 18.10.1 inventory through its real upstream factory or class and
  records the wire schema `toolWireSchema/1` returns, the live description,
  `strict` flag, presentation fields and the settings/session inputs that
  selected each schema variant. The result is compiled into this module as a
  literal, so a generation carries the catalog without reading the working
  tree at runtime:

      os/priv/toolset/catalog.json   →  @catalog  (external_resource)

  ## Membership is not enablement

  `tools/0` is *descriptive* membership of the recorded inventory: a tool listed
  here is not thereby enabled for a session, implemented, or reachable.
  `constructs_in_plain_session/0` reports which factories produced a tool in a
  plain session during the build, and `implemented/0` reflects which recorded
  Jido target modules are actually loaded in this VM and implement the Jido
  action contract. Neither list registers anything; `Elixos.Toolset` owns
  dispatch.

  ## Schemas

  Every `parameters` map is the exact `toolWireSchema/1` value of the pinned
  checkout at `reference.revision`, not a hand-written schema. A tool may carry
  several variants because its schema follows settings or session state (bash
  async/service launch, the five `edit` modes, eval backends, the task plan
  matrix, yield output schemas, memory scopes). `inventory_variants` maps each
  recorded inventory variant to the captured schema that satisfies it; the
  builder refuses to write a catalog with an uncovered variant.
  """

  @catalog_file Path.expand("../../../priv/toolset/catalog.json", __DIR__)
  @external_resource @catalog_file
  @catalog @catalog_file |> File.read!() |> Jason.decode!()

  @tools @catalog["tools"]
  @names Enum.map(@tools, & &1["name"])
  @by_name Map.new(@tools, &{&1["name"], &1})
  @aliases @catalog["name_normalization"]["aliases"]
  @canonical Map.new(@catalog["name_normalization"]["canonical_names"], &{&1, true})

  @variants_by_name Map.new(@tools, fn tool ->
                      {tool["name"], Map.new(tool["variants"], &{&1["id"], &1})}
                    end)

  @type variant :: %{required(String.t()) => term()}
  @type descriptor :: %{required(String.t()) => term()}

  @doc "The pinned upstream revision every schema and description was read from."
  @spec revision() :: String.t()
  def revision, do: @catalog["reference"]["revision"]

  @doc "The pinned upstream package version."
  @spec version() :: String.t()
  def version, do: @catalog["reference"]["version"]

  @doc "Repository, revision, version, license digest and the readers the catalog used."
  @spec reference() :: map()
  def reference, do: @catalog["reference"]

  @doc "Recorded tool, captured-variant and inventory-coverage counts."
  @spec counts() :: map()
  def counts, do: @catalog["counts"]

  @doc "Recorded canonical-name and alias normalization, as the pinned normalizer produced it."
  @spec name_normalization() :: map()
  def name_normalization, do: @catalog["name_normalization"]

  @doc "All 56 inventory descriptors, in recorded inventory order."
  @spec tools() :: [descriptor()]
  def tools, do: @tools

  @doc "The 56 canonical inventory tool IDs, in recorded inventory order."
  @spec names() :: [String.t()]
  def names, do: @names

  @doc """
  Normalizes a tool name the way the pinned SDK does: canonical IDs and the
  legacy `search` alias are matched case-insensitively; any other spelling is
  a custom name and is returned unchanged.
  """
  @spec canonical_name(String.t()) :: String.t()
  def canonical_name(name) when is_binary(name) do
    lower = String.downcase(name)

    cond do
      Map.has_key?(@canonical, lower) -> lower
      Map.has_key?(@aliases, lower) -> Map.fetch!(@aliases, lower)
      true -> name
    end
  end

  @doc "The descriptor for a canonical or aliased tool name, or nil when unknown."
  @spec descriptor(String.t()) :: descriptor() | nil
  def descriptor(name) when is_binary(name), do: Map.get(@by_name, canonical_name(name))

  @doc "The descriptor for a canonical or aliased tool name; raises for an unknown name."
  @spec descriptor!(String.t()) :: descriptor()
  def descriptor!(name) do
    case descriptor(name) do
      nil -> raise ArgumentError, "unknown OMP tool: #{inspect(name)}"
      descriptor -> descriptor
    end
  end

  @doc "True when the name is one of the recorded inventory IDs."
  @spec known?(String.t()) :: boolean()
  def known?(name), do: Map.has_key?(@by_name, canonical_name(name))

  @doc "Every captured schema variant of a tool, in build order."
  @spec variants(String.t()) :: [variant()]
  def variants(name) do
    name |> descriptor!() |> Map.fetch!("variants")
  end

  @doc "The variant IDs of a tool."
  @spec variant_ids(String.t()) :: [String.t()]
  def variant_ids(name), do: name |> variants() |> Enum.map(& &1["id"])

  @doc "One captured variant by ID, or nil."
  @spec variant(String.t(), String.t()) :: variant() | nil
  def variant(name, id) when is_binary(name) and is_binary(id) do
    case Map.get(@variants_by_name, canonical_name(name)) do
      nil -> nil
      index -> Map.get(index, id)
    end
  end

  @doc """
  The exact wire schema of one variant. Raises `ArgumentError` for an unknown
  tool or variant.
  """
  @spec schema(String.t(), String.t()) :: map()
  def schema(name, id) do
    case variant(name, id) do
      %{"parameters" => parameters} -> parameters
      nil -> raise ArgumentError, "unknown OMP schema variant: #{name}/#{id}"
    end
  end

  @doc "The variant the build captured first for a tool; the SDK-default shape."
  @spec default_variant(String.t()) :: variant()
  def default_variant(name) do
    descriptor = descriptor!(name)
    id = Map.fetch!(descriptor, "canonical_variant")

    Enum.find(Map.fetch!(descriptor, "variants"), &(&1["id"] == id)) ||
      raise ArgumentError, "catalog descriptor #{name} has no canonical variant #{id}"
  end

  @doc "The default variant's exact wire schema."
  @spec default_schema(String.t()) :: map()
  def default_schema(name) do
    name |> default_variant() |> Map.fetch!("parameters")
  end

  @doc """
  Build-time evidence that the pinned factory constructs the tool in a plain
  session — no settings overrides, no extra session fields. This is factory
  potential, not the session plan's enabled selection.
  """
  @spec constructs_in_plain_session(String.t()) :: boolean()
  def constructs_in_plain_session(name),
    do: name |> descriptor!() |> Map.fetch!("constructs_in_plain_session")

  @doc "The gate recorded when the plain session did not construct the tool."
  @spec plain_session_gate(String.t()) :: String.t() | nil
  def plain_session_gate(name), do: name |> descriptor!() |> Map.fetch!("plain_session_gate")

  @doc "Inventory names whose factories construct in a plain session."
  @spec constructs_in_plain_session() :: [String.t()]
  def constructs_in_plain_session, do: Enum.filter(@names, &constructs_in_plain_session/1)

  @doc "The recorded claim layering this catalog keeps explicit."
  @spec claims() :: map()
  def claims, do: @catalog["claims"]

  @doc """
  The recorded Jido target module for a tool, when that module is loaded in
  this VM and implements the `Jido.Action` contract (`run/2`, plus the
  `validate_params/1` that `use Jido.Action` generates). Descriptive inventory
  membership alone never returns a module: an unloaded, stubbed or
  non-dispatching target is nil.
  """
  @spec dispatch_module(String.t()) :: module() | nil
  def dispatch_module(name) do
    case descriptor(name) do
      %{"jido_target" => target} when is_binary(target) ->
        module = Module.concat(String.split(target, "."))

        if Code.ensure_loaded?(module) and function_exported?(module, :run, 2) and
             function_exported?(module, :validate_params, 1),
           do: module

      _ ->
        nil
    end
  end

  @doc "Inventory names whose recorded Jido target is loaded and implements the action contract."
  @spec implemented() :: [String.t()]
  def implemented, do: Enum.filter(@names, &(dispatch_module(&1) != nil))

  @doc """
  The inventory-coverage report: every recorded variant row and the captured
  schema that satisfies it. `uncovered/0` is always empty for a catalog the
  builder wrote.
  """
  @spec coverage() :: [map()]
  def coverage do
    Enum.flat_map(@tools, fn tool ->
      Enum.map(tool["inventory_variants"], &Map.put(&1, "tool", tool["name"]))
    end)
  end

  @doc "Recorded inventory variants without captured schema data (empty when complete)."
  @spec uncovered() :: [map()]
  def uncovered, do: Enum.filter(coverage(), &(&1["mode"] == "uncovered"))

  @doc "Descriptive membership plus the real enablement/implementation view."
  @spec summary() :: map()
  def summary do
    %{
      revision: revision(),
      version: version(),
      tools: length(@names),
      captured_variants: @catalog["counts"]["captured_variants"],
      inventory_variants: @catalog["counts"]["inventory_variants"],
      uncovered_variants: length(uncovered()),
      constructs_in_plain_session: constructs_in_plain_session(),
      implemented: implemented()
    }
  end
end
