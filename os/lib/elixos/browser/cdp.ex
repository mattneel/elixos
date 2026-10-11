defmodule Elixos.Browser.CDP do
  @moduledoc """
  `jido_browser`'s Lightpanda adapter, wired to `cdp_ex` and a Port (M25).

  The adapter expects a pair of pluggable modules: one that owns a CDP session
  (`start/1`, `new_page/1`, `stop/1`) and one that acts on a page
  (`navigate/3`, `content/1`, `evaluate/3`, `screenshot/2`, `click/3`,
  `fill/4`). Their default is `light_cdp`, which spawns the browser through
  `erlexec` - a launcher that refuses to start unless `SHELL` is set, which is
  the one thing this OS must not invent (ADR-012). So the protocol comes from
  the ecosystem (`cdp_ex`, whose dependencies are `mint_web_socket`, `jason`
  and `telemetry`) and the process is started here, as a Port, like every
  other external program on Elixos.

  The binary is `Elixos.Browser`'s business; this module is handed its path and
  the port to serve on, starts it, waits for it, and resolves the WebSocket
  endpoint through `/json/version` the way `cdp_ex` expects.
  """

  alias CDPEx.{Browser, Connect, Page}

  @ready_timeout 20_000

  @doc """
  Starts the adapter and a first page.

  Options: `:binary` (or `:binary_path`) is the program, `:port` the CDP port
  to serve on (a free one is asked of the OS when absent).
  """
  def start(opts \\ []) do
    binary = opts[:binary] || opts[:binary_path]
    port_number = Keyword.get(opts, :port) || free_port()

    with true <- is_binary(binary) or {:error, :no_binary},
         {:ok, port} <- spawn_binary(binary, port_number),
         :ok <- await_ready(port_number),
         {:ok, ws_url} <- Connect.resolve(endpoint(port_number)),
         # Connect mode: `cdp_ex` attaches to a browser it did not launch, so
         # nothing here reaches for Chrome and `terminate/2` reaps nothing.
         {:ok, browser} <- Browser.start_link(connect: ws_url) do
      # No page here on purpose: the adapter asks for one through `new_page/1`,
      # and Lightpanda's serve mode keeps one page per session - making a second
      # would answer TargetAlreadyLoaded.
      {:ok, %{port: port, browser: browser, binary: binary, port_number: port_number}}
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

  ## the process

  defp spawn_binary(binary, port_number) do
    {:ok,
     Port.open({:spawn_executable, binary}, [
       :binary,
       :exit_status,
       :stderr_to_stdout,
       args: ["serve", "--port", Integer.to_string(port_number)]
     ])}
  rescue
    error -> {:error, {:no_adapter, error}}
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

  # A free port from the OS, so two sessions never fight over 9222.
  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end

  defmodule Page do
    @moduledoc """
    The page half of `jido_browser`'s contract, over `cdp_ex` (`M25`).
    """

    alias CDPEx.Page, as: CDPPage

    @doc "Navigates and waits for the load to settle. The contract wants `:ok`."
    def navigate(%CDPPage{} = page, url, _opts \\ []) do
      case CDPPage.navigate(page, url) do
        {:ok, _page} -> :ok
        :ok -> :ok
        other -> other
      end
    end

    @doc "The page's HTML, which the adapter turns into markdown, text or HTML."
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
