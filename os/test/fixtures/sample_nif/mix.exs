# A NIF built *on the box* with the bundled zig cc (ADR-009, M11).
#
# It uses a tiny custom compiler instead of elixir_make so the acceptance test
# needs no network. (elixir_make itself needs make + sh, which only the
# toolchain package provides; docs/ARCHITECTURE.md §8.) A project cannot use a
# compiler from its own lib/, so the compiler is defined here, in mix.exs.

defmodule Mix.Tasks.Compile.SampleNif do
  @moduledoc "Compiles c_src/sample_nif.c into priv/sample_nif.so with `cc` (zig cc on Elixos)."
  use Mix.Task.Compiler

  @impl true
  def run(_args) do
    cc =
      System.find_executable("cc") ||
        Mix.raise("no `cc` on PATH (on Elixos: the toolchain package)")

    erts_include =
      Path.join([:code.root_dir(), "erts-#{:erlang.system_info(:version)}", "include"])

    File.mkdir_p!("priv")

    args = [
      "-shared",
      "-fPIC",
      "-O2",
      "-I",
      erts_include,
      "-o",
      "priv/sample_nif.so",
      "c_src/sample_nif.c"
    ]

    case System.cmd(cc, args, stderr_to_stdout: true) do
      {_, 0} -> {:ok, []}
      {out, status} -> Mix.raise("cc exited with #{status}:\n#{out}")
    end
  end
end

defmodule SampleNif.MixProject do
  use Mix.Project

  def project do
    [
      app: :sample_nif,
      version: "0.1.0",
      elixir: "~> 1.20",
      compilers: [:sample_nif | Mix.compilers()],
      deps: [],
      elixos: [boot: :manual]
    ]
  end

  def application, do: [extra_applications: [:logger]]
end
