defmodule Elixos.Coproc.Bundle do
  @moduledoc """
  AtomVM `.avm` bundles: the code a coprocessor runs (M29, ADR-099).

  The format is AtomVM's own (`src/libAtomVM/avmpack.c` at the pinned commit,
  and `packbeam_api.erl` in atomvm_packbeam 0.8.2, which this mirrors):

    * a 24-byte header, `"#!/usr/bin/env AtomVM\\n"` and two zero bytes;
    * one section per file: `<<size::32, flags::32, 0::32>>`, the NUL-terminated
      name padded to 4 bytes, then the data padded to 4 bytes, `size` counting
      all of it;
    * a terminating `<<0::32, 0::32, 0::32, "end", 0>>` section.

  Every integer is big-endian. A `.beam` section carries flag 2 (code), and
  the start module also flag 1: AtomVM boots the first start-flagged module of
  the first archive on its command line by calling `start/0`.

  AtomVM loads only the chunks it understands, and only an *uncompressed*
  literal table: each module is rebuilt from the allowed chunks, with `LitT`
  inflated into `LitU`, exactly as packbeam does. Line tables are dropped.
  """

  import Bitwise

  @header <<"#!/usr/bin/env AtomVM\n", 0, 0>>

  @start_flag 1
  @code_flag 2
  @allowed ~w(AtU8 Code ExpT LocT ImpT LitU FunT StrT LitT avmN Type)c

  @typedoc "A packed archive."
  @type t :: binary()

  @doc """
  Packs `{module, bytecode}` pairs into an archive, in the given order.

  `start: module` marks that module as the archive's entry point; it must
  export `start/0`. Without it the archive is a library, as a coprocessor
  bundle is: the coprocessor's runtime starts, and the bundle supplies modules.
  """
  @spec pack([{module(), binary()}], keyword()) :: {:ok, t()} | {:error, term()}
  def pack(beams, opts \\ []) when is_list(beams) do
    start = Keyword.get(opts, :start)

    with :ok <- unique(beams),
         {:ok, sections} <- sections(beams, start) do
      {:ok, IO.iodata_to_binary([@header, sections, header(0, 0, "end")])}
    end
  end

  @doc "The modules an archive contains, in archive order, and which one starts it."
  @spec modules(t()) :: {:ok, [module()], module() | nil} | {:error, :invalid_bundle}
  def modules(<<@header, sections::binary>>), do: read(sections, [], nil)
  def modules(_other), do: {:error, :invalid_bundle}

  @doc "The archive's identity: the lowercase hex sha256 of its bytes."
  @spec digest(t()) :: String.t()
  def digest(archive) when is_binary(archive) do
    :crypto.hash(:sha256, archive) |> Base.encode16(case: :lower)
  end

  defp unique(beams) do
    modules = Enum.map(beams, &elem(&1, 0))

    case modules -- Enum.uniq(modules) do
      [] -> :ok
      [duplicate | _] -> {:error, {:duplicate_module, duplicate}}
    end
  end

  defp sections(beams, start) do
    if start != nil and not List.keymember?(beams, start, 0) do
      {:error, {:start_module_missing, start}}
    else
      Enum.reduce_while(beams, {:ok, []}, fn {module, bytecode}, {:ok, acc} ->
        case section(module, bytecode, start) do
          {:ok, section} -> {:cont, {:ok, [acc, section]}}
          {:error, _} = error -> {:halt, error}
        end
      end)
    end
  end

  defp section(module, bytecode, start) do
    with {:ok, stripped, exports} <- strip(module, bytecode),
         :ok <- startable(module, start, exports) do
      flags = if module == start, do: @code_flag ||| @start_flag, else: @code_flag
      {:ok, entry(Atom.to_string(module) <> ".beam", flags, stripped)}
    end
  end

  defp startable(module, module, exports) do
    if {:start, 0} in exports, do: :ok, else: {:error, {:no_start_function, module}}
  end

  defp startable(_module, _start, _exports), do: :ok

  defp strip(module, bytecode) do
    with {:ok, ^module, chunks} <- all_chunks(bytecode),
         {:ok, {^module, [exports: exports]}} <- :beam_lib.chunks(bytecode, [:exports]),
         {:ok, built} <- :beam_lib.build_module(filter(chunks)) do
      {:ok, built, exports}
    else
      {:ok, other, _chunks} -> {:error, {:module_mismatch, module, other}}
      _ -> {:error, {:invalid_beam, module}}
    end
  end

  defp all_chunks(bytecode) do
    :beam_lib.all_chunks(bytecode)
  rescue
    _ -> {:error, :beam_lib, :invalid}
  end

  defp filter(chunks) do
    chunks
    |> Enum.map(fn
      {~c"LitT", <<0::32, literals::binary>>} -> {~c"LitU", literals}
      {~c"LitT", <<_size::32, compressed::binary>>} -> {~c"LitU", :zlib.uncompress(compressed)}
      chunk -> chunk
    end)
    |> Enum.filter(fn {tag, _data} -> tag in @allowed end)
  end

  defp entry(name, flags, data) do
    head = header(0, flags, name)
    head_size = byte_size(head) + padding(byte_size(head))
    size = head_size + byte_size(data) + padding(byte_size(data))
    [header(size, flags, name), pad(byte_size(head)), data, pad(byte_size(data))]
  end

  defp header(size, flags, name), do: <<size::32, flags::32, 0::32, name::binary, 0>>

  defp padding(size), do: rem(4 - rem(size, 4), 4)
  defp pad(size), do: :binary.copy(<<0>>, padding(size))

  defp read(<<0::32, _rest::binary>>, acc, start), do: {:ok, Enum.reverse(acc), start}

  defp read(<<size::32, flags::32, 0::32, rest::binary>>, acc, start)
       when size >= 12 and byte_size(rest) >= size - 12 do
    body_size = size - 12
    <<body::binary-size(^body_size), next::binary>> = rest

    with [name, _data] <- :binary.split(body, <<0>>),
         true <- String.ends_with?(name, ".beam") do
      module = name |> String.trim_trailing(".beam") |> String.to_atom()
      start = if (flags &&& @start_flag) != 0 and start == nil, do: module, else: start
      read(next, [module | acc], start)
    else
      _ -> read(next, acc, start)
    end
  end

  defp read(_malformed, _acc, _start), do: {:error, :invalid_bundle}
end
