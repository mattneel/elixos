defmodule Elixos.Browser.CDP do
  @moduledoc """
  The CDP session and page the browser service drives (M25).

  The protocol is `cdp_ex` - a Hex package whose dependencies are
  `mint_web_socket`, `jason` and `telemetry` - attached in *connect mode*: it
  talks to a browser it did not launch, so nothing here reaches for Chrome.
  The process is started here, as a `Port`, from the argv the image's manifest
  decides. That argv may be a loader (`ld-linux-x86-64.so.2 --library-path
  <dir> lightpanda serve --port 9222`), which is why the whole argv is taken
  rather than a binary and arguments of our own: the private glibc lives beside
  the binary under `/system/browser`, and this musl system has no glibc paths to
  put it in (ADR-064).

  The interface is deliberately the same one `jido_browser`'s Lightpanda
  adapter expects (`start/1`, `new_page/1`, `stop/1`, and the page functions
  below), so that adapter is one line away if its dependency situation changes
  (ADR-065).
  """

  alias CDPEx.{Browser, Connect, Page}

  @ready_timeout 20_000

  @doc """
  Starts the adapter and attaches to it.

  `:command` is the whole argv (the manifest's), or `:binary` with optional
  `:args` for a plain program. `:port` is used only when the argv names none.
  """
  def start(opts \\ []) do
    with {:ok, exec, args} <- spawn_spec(opts),
         port_number = port_of(args) || Keyword.get(opts, :port) || free_port(),
         {:ok, port} <- spawn(exec, args),
         :ok <- await_ready(port_number),
         {:ok, ws_url} <- Connect.resolve(endpoint(port_number)),
         # Connect mode: `cdp_ex` attaches to a browser it did not launch, so
         # nothing here reaches for Chrome and `terminate/2` reaps nothing.
         {:ok, browser} <- Browser.start_link(connect: ws_url) do
      # No page here on purpose: the service asks for one through `new_page/1`,
      # and Lightpanda's serve mode keeps one page per session - making a
      # second would answer TargetAlreadyLoaded.
      {:ok, %{port: port, browser: browser, exec: exec, port_number: port_number}}
    end
  end

  @doc "A page (CDP target) in the running session."
  def new_page(%{browser: browser}), do: Browser.new_page(browser)

  @doc "Stops the session: the browser process goes and the port closes."
  def stop(%{browser: browser} = session) do
    if Process.alive?(browser), do: Browser.stop(browser)
    if session[:port], do: Port.close(session.port)
    :ok
  rescue
    _error -> :ok
  end

  def stop(_session), do: :ok

  # A manifest argv, or a program with arguments.
  defp spawn_spec(opts) do
    case opts[:command] do
      [exec | args] ->
        {:ok, exec, args}

      nil ->
        binary = opts[:binary] || opts[:binary_path]

        if is_binary(binary) do
          {:ok, binary, opts[:args] || []}
        else
          {:error, :no_binary}
        end
    end
  end

  ## the process

  defp spawn(exec, args) do
    {:ok, Port.open({:spawn_executable, exec}, [:binary, :exit_status, :stderr_to_stdout, args: args])}
  rescue
    error -> {:error, {:no_adapter, error}}
  end

  defp port_of(args) do
    case Enum.drop_while(args, &(&1 != "--port")) do
      ["--port", value | _rest] -> String.to_integer(value)
      _other -> nil
    end
  end

  defp endpoint(port_number), do: "http://127.0.0.1:#{port_number}"

  defp await_ready(port_number, deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + @ready_timeout

    case :gen_tcp.connect({127, 0, 0, 1}, port_number, [:binary, active: false], 200) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        :ok

      {:error, _reason} ->
        if System.monotonic_time(:millisecond) > deadline do
          {:error, :adapter_timeout}
        else
          Process.sleep(50)
          await_ready(port_number, deadline)
        end
    end
  end

  # A free port from the OS, for a program that does not name one.
  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end

  defmodule Page do
    @moduledoc """
    The page half of the same interface, over `cdp_ex` (M25).
    """

    alias CDPEx.Page, as: CDPPage

    @doc "Navigates and waits for the load to settle. The interface wants `:ok`."
    def navigate(%CDPPage{} = page, url, _opts \\ []) do
      case CDPPage.navigate(page, url) do
        {:ok, _page} -> :ok
        :ok -> :ok
        other -> other
      end
    end

    @doc "The page's visible text - what `Elixos.Browser.navigate/1` returns."
    def text(%CDPPage{} = page, selector \\ "body") do
      case CDPPage.text(page, selector) do
        {:ok, nil} -> {:ok, ""}
        other -> other
      end
    end

    @doc "The page's HTML."
    def content(%CDPPage{} = page), do: CDPPage.html(page)

    @doc "Evaluates JavaScript in the page."
    def evaluate(%CDPPage{} = page, script, opts \\ []), do: CDPPage.evaluate(page, script, opts)

    @doc "A PNG of the page."
    def screenshot(%CDPPage{} = page, opts \\ []), do: CDPPage.screenshot(page, opts)

    @doc "Clicks an element."
    def click(%CDPPage{} = page, selector, opts \\ []), do: CDPPage.click(page, selector, opts)

    @doc "Types into an element."
    def fill(%CDPPage{} = page, selector, text, opts \\ []),
      do: CDPPage.type(page, selector, text, opts)
  end
end
