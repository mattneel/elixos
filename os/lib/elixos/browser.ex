defmodule Elixos.Browser do
  @moduledoc """
  The headless browser (M18, docs/ROADMAP.md).

  The adapter ships in the read-only system image on `/system`, pinned and
  verified when the image is built - never downloaded at run time. Its
  manifest decides how it starts: a musl-clean binary is exec'd directly, a
  glibc one is started through a private glibc with glibc's own loader
  (`ld-linux-x86-64.so.2 --library-path <dir> ...`), still directly as a port.
  `command/1` is that decision, pure and testable.

  The adapter is deliberately limited (no element refs, no saved state, no
  tabs, no console capture): `navigate/1`, `eval/1` and `screenshot/0` are the
  surface. It is not boot-critical and does not run in rescue;
  `Elixos.poweroff/0` stops it like any other service.
  """

  @doc "The installed adapter's argv, from the manifest baked into the image."
  @spec command() :: {:ok, [String.t()]} | {:error, term()}
  def command, do: Elixos.NotImplemented.raise!(18, "Elixos.Browser.command/0")

  @doc """
  The argv for one adapter manifest:

      {:ok, [binary | args]}                        # a musl-clean binary
      {:ok, [ld, "--library-path", lib, binary | args]}   # a glibc one
  """
  @spec command(map()) :: {:ok, [String.t()]} | {:error, term()}
  def command(_manifest), do: Elixos.NotImplemented.raise!(18, "Elixos.Browser.command/1")

  @doc "The running adapter: `{:ok, pid}` or `{:error, :not_running}`."
  @spec status() :: {:ok, pid()} | {:error, :not_running}
  def status, do: Elixos.NotImplemented.raise!(18, "Elixos.Browser.status/0")

  @doc "Navigates to `url` and returns the page's text."
  @spec navigate(String.t()) :: {:ok, String.t()} | {:error, term()}
  def navigate(_url), do: Elixos.NotImplemented.raise!(18, "Elixos.Browser.navigate/1")

  @doc "Evaluates `script` in the current page and returns its value."
  @spec eval(String.t()) :: {:ok, term()} | {:error, term()}
  def eval(_script), do: Elixos.NotImplemented.raise!(18, "Elixos.Browser.eval/1")

  @doc "A PNG of the current page."
  @spec screenshot() :: {:ok, binary()} | {:error, term()}
  def screenshot, do: Elixos.NotImplemented.raise!(18, "Elixos.Browser.screenshot/0")
end
