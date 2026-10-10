# What a login IEx prompt evaluates with (M9, ADR-020).
#
# IEx imports IEx.Helpers itself, and those helpers are built on File.cd/1 and
# File.cwd/0, which would move the whole VM (ADR-016). Re-importing it here
# without the three session-aware names, and then importing
# Elixos.REPL.Helpers, is what makes a prompt's cd/1, pwd/0 and ls/0,1 move the
# session instead. IEx.Evaluator loads this file after its own import and
# keeps the environment it returns.
import IEx.Helpers, except: [cd: 1, pwd: 0, ls: 0, ls: 1]
import Elixos.REPL.Helpers
