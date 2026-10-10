defmodule Elixos.Boot.Base do
  @moduledoc """
  The factory's code is the base, and the base is sticky (M7,
  docs/ROADMAP.md).

  Everything in the release's code path is loaded from directories we own, and
  a saved generation may not quietly replace any of it: a user module is free
  to shadow another *user* module, but not Elixos itself, or a bad generation
  could make the system unable to boot far enough to notice.

  `:code.stick_dir/1` sticks every module it finds in a directory: they cannot
  be purged, deleted or reloaded afterwards. Sticking is per-VM and is what
  makes the guarantee hold for the whole boot, so this runs once, early.
  """

  @doc "Makes the base sticky. Returns the number of code-path directories."
  @spec stick() :: non_neg_integer()
  def stick do
    directories = for dir <- :code.get_path(), is_list(dir), do: to_string(dir)

    # A sticky directory makes `:code.load_binary/3` refuse the module. That
    # is the path a generation's restore takes, so a saved generation cannot
    # shadow the base; it is also where a REPL slip dies, because Elixir
    # compiles the replacement and the *load* is what is refused - the module
    # stays as it was, and the recorder skips the refused bytecode.
    for dir <- directories, File.dir?(dir), do: :code.stick_dir(String.to_charlist(dir))

    # Not a guard, a diagnostic: with this, a redefinition is warned about
    # rather than silently replacing a module. Legitimate redefinitions of the
    # user's own modules still work - which is the point of a live image.
    Code.compiler_options(ignore_module_conflict: false)

    length(directories)
  end
end
