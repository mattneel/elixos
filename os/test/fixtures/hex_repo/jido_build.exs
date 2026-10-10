# Assemble the prebuilt jido closure as fixture packages.
#
# Usage: elixir jido_build.exs <lib-dir> <out-dir>
#
# <lib-dir> holds one directory per application with ebin/ (and priv/): the
# compiled closure, built on this host from the published Hex packages. The
# packages go into the fixture repository *already built* (no mix.exs, just
# ebin/) because building them on the box needs tools Elixos does not ship yet
# (rebar3, and a rebar plugin that fetches from the network) - see
# docs/notes/jido.md. The tarballs are written by Hex's own writer, so their
# checksums are the ones the registry builder recomputes; the original
# metadata travels unchanged, so each release still carries its real
# requirements and the M15 closure resolution is exercised for real.
#
# The writer lives in the installed Hex archive; a plain `elixir` does not
# load it, so it is put on the code path first.
for ebin <- Path.wildcard(Path.expand("~/.mix/archives/hex-*/hex-*/ebin")), do: Code.append_path(ebin)

defmodule JidoFixture do
  def run([lib_dir, out_dir]) do
    File.mkdir_p!(out_dir)

    for app <- lib_dir |> File.ls!() |> Enum.sort(), app != "jido_only" do
      dir = Path.join(lib_dir, app)
      if File.dir?(Path.join(dir, "ebin")), do: package(app, dir, out_dir)
    end
  end

  defp package(app, dir, out_dir) do
    {name, version} = identity(app, dir)
    metadata = metadata(app, version)
    files = files(dir)
    {:ok, result} = :mix_hex_tarball.create(metadata, files)

    tar = Path.join(out_dir, "#{name}-#{version}.tar")
    File.write!(tar, result[:tarball])
    IO.puts("jido fixture: #{name}-#{version} (built, #{length(files)} files)")
  end

  # name and version from the built application resource.
  defp identity(app, dir) do
    {:ok, terms} = :file.consult(String.to_charlist(Path.join([dir, "ebin", "#{app}.app"])))
    {:application, name, props} = Enum.find(terms, &match?({:application, _, _}, &1))
    {to_string(name), to_string(props[:vsn])}
  end

  # The published metadata, so the registry carries the real requirements.
  defp metadata(name, version) do
    tarball = cached(name, version)
    IO.puts("meta: #{name}-#{version} <- #{tarball}")
    {:ok, members} = :erl_tar.extract({:binary, File.read!(tarball)}, [:memory])
    {_member, bytes} = Enum.find(members, fn {member, _} -> to_string(member) == "metadata.config" end)

    path = Path.join(System.tmp_dir!(), "elixos-jido-meta-#{System.unique_integer([:positive])}")
    File.write!(path, bytes)

    terms =
      case :file.consult(String.to_charlist(path)) do
        {:ok, terms} -> terms
        other -> raise "metadata consult failed for #{name}-#{version}: #{inspect(other)}"
      end

    File.rm(path)
    Map.new(terms, fn {key, value} -> {to_string(key), value} end)
  end

  defp cached(name, version) do
    path = Path.expand("~/.hex/packages/hexpm/#{name}-#{version}.tar")
    File.regular?(path) || raise "no cached tarball for #{name}-#{version}"
    path
  end

  defp files(dir) do
    for sub <- ["ebin", "priv"],
        File.dir?(Path.join(dir, sub)),
        path <- Path.wildcard(Path.join([dir, sub, "**"]), match_dot: true),
        File.regular?(path) do
      {Path.relative_to(path, dir) |> String.to_charlist(), File.read!(path)}
    end
  end
end

JidoFixture.run(System.argv())
