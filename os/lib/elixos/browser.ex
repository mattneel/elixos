defmodule Elixos.Browser do
  @moduledoc """
  The headless browser (M25, docs/ROADMAP.md).

  The adapter ships in the read-only system image under `/system/browser`,
  pinned and verified when the image is built - never downloaded at run time.
  Its manifest decides how it starts: a musl-clean binary is exec'd directly, a
  glibc one is started through a private glibc with glibc's own loader
  (`ld-linux-x86-64.so.2 --library-path <dir> ...`), still directly as a port
  (ADR-012: no shell). `command/1` is that decision, pure and testable; ADR-064
  records which arm this system took, and why.

  The adapter is Lightpanda's `serve` mode: a WebSocket CDP endpoint on the
  loopback, one page session, and the three verbs the milestone promised -
  `navigate/1`, `eval/1`, `screenshot/0`. Starting is asynchronous, so a slow
  or missing adapter never delays the prompt; the process starts only in normal
  mode, and a failure leaves `status/0` at `{:error, :not_running}` rather than
  taking anything down with it.
  """

  use GenServer

  require Logger

  alias Elixos.Browser.CDP

  @manifest "/system/browser/manifest.json"
  @default_port 9222
  @ready_timeout 20_000
  @load_timeout 60_000
  @call_timeout 120_000

  ## the manifest, and the argv it decides

  @doc "The installed adapter's argv, from the manifest baked into the image."
  @spec command() :: {:ok, [String.t()]} | {:error, term()}
  def command do
    case File.read(@manifest) do
      {:ok, text} ->
        case JSON.decode(text) do
          {:ok, manifest} when is_map(manifest) -> command(manifest)
          {:ok, _other} -> {:error, :bad_manifest}
          {:error, _reason} -> {:error, :bad_manifest}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  The argv for one adapter manifest:

      {:ok, [binary | args]}                        # a musl-clean binary
      {:ok, [ld, "--library-path", lib, binary | args]}   # a glibc one
  """
  @spec command(map()) :: {:ok, [String.t()]} | {:error, term()}
  def command(%{"binary" => binary} = manifest) when is_binary(binary) and binary != "" do
    args = Map.get(manifest, "args", [])

    with :ok <- check_args(args),
         :ok <- check_loader(manifest) do
      case manifest do
        %{"loader" => %{"ld" => ld, "lib" => lib}} ->
          {:ok, [ld, "--library-path", lib, binary | args]}

        _ ->
          {:ok, [binary | args]}
      end
    end
  end

  def command(_manifest), do: {:error, :no_binary}

  defp check_args(args) when is_list(args) do
    if Enum.all?(args, &is_binary/1), do: :ok, else: {:error, :bad_args}
  end

  defp check_args(_args), do: {:error, :bad_args}

  # A loader that is present but unusable is refused rather than ignored: the
  # binary would fail at run time instead, and this is the cheaper failure.
  defp check_loader(%{"loader" => %{"ld" => ld, "lib" => lib}})
       when is_binary(ld) and ld != "" and is_binary(lib) and lib != "",
       do: :ok

  defp check_loader(%{"loader" => _other}), do: {:error, :bad_loader}
  defp check_loader(_manifest), do: :ok

  ## the surface

  @doc "The running adapter: `{:ok, pid}` or `{:error, :not_running}`."
  @spec status() :: {:ok, pid()} | {:error, :not_running}
  def status do
    case Process.whereis(__MODULE__) do
      nil -> {:error, :not_running}
      pid -> {:ok, pid}
    end
  end

  @doc "Navigates to `url` and returns the page's text."
  @spec navigate(String.t()) :: {:ok, String.t()} | {:error, term()}
  def navigate(url) when is_binary(url), do: call({:navigate, url})

  @doc "Evaluates `script` in the current page and returns its value."
  @spec eval(String.t()) :: {:ok, term()} | {:error, term()}
  def eval(script) when is_binary(script), do: call({:eval, script})

  @doc "A PNG of the current page."
  @spec screenshot() :: {:ok, binary()} | {:error, term()}
  def screenshot, do: call(:screenshot)

  @doc "Stops the adapter; the process leaves `status/0` at not running."
  @spec stop() :: :ok
  def stop do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal, 5_000)
    end
  end

  defp call(request) do
    case Process.whereis(__MODULE__) do
      nil -> {:error, :not_running}
      pid -> GenServer.call(pid, request, @call_timeout)
    end
  end

  ## the process

  @doc false
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      # A browser that failed is not worth a restart loop: the prompt always
      # matters more than the adapter (the same rule as the SSH service).
      restart: :temporary,
      type: :worker
    }
  end

  @doc false
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    if Keyword.get(opts, :mode, :normal) == :normal do
      {:ok, %{port: nil, cdp: nil, session: nil}, {:continue, :start}}
    else
      :ignore
    end
  end

  @impl true
  def handle_continue(:start, state) do
    case start_adapter() do
      {:ok, port, cdp, session} ->
        {:noreply, %{state | port: port, cdp: cdp, session: session}}

      {:error, reason} ->
        Logger.warning("browser: not starting: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_call({:navigate, url}, _from, state) do
    with {:ok, session, cdp} <- ensure_session(state),
         {:ok, result, cdp} <-
           CDP.call(cdp, "Page.navigate", %{"url" => url}, @load_timeout, session),
         :ok <- check_navigation(result),
         {:ok, cdp} <- await_load(cdp, session),
         {:ok, text, cdp} <- evaluate(cdp, session, body_expression()) do
      {:reply, {:ok, text_or_empty(text)}, %{state | cdp: cdp}}
    else
      {:error, reason, _cdp} -> {:reply, {:error, reason}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:eval, script}, _from, state) do
    with {:ok, session, cdp} <- ensure_session(state),
         {:ok, value, cdp} <- evaluate(cdp, session, script) do
      {:reply, {:ok, value}, %{state | cdp: cdp}}
    else
      {:error, reason, _cdp} -> {:reply, {:error, reason}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:screenshot, _from, state) do
    with {:ok, session, cdp} <- ensure_session(state),
         {:ok, %{"data" => data}, cdp} <-
           CDP.call(cdp, "Page.captureScreenshot", %{}, @load_timeout, session),
         {:ok, png} <- decode_png(data) do
      {:reply, {:ok, png}, %{state | cdp: cdp}}
    else
      {:error, reason, _cdp} -> {:reply, {:error, reason}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.warning("browser: the adapter exited with status #{status}")
    {:noreply, %{state | port: nil, cdp: nil, session: nil}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    if state.cdp, do: CDP.close(state.cdp)
    if state.port, do: Port.close(state.port)
    :ok
  end

  ## starting the adapter

  defp start_adapter do
    with {:ok, [exec | args]} <- command(),
         {:ok, port} <- open_port(exec, args),
         port_number = port_of(args),
         :ok <- await_ready(port_number),
         {:ok, cdp} <- CDP.connect("ws://127.0.0.1:#{port_number}/"),
         {:ok, session, cdp} <- new_page(cdp) do
      {:ok, port, cdp, session}
    end
  end

  defp open_port(exec, args) do
    {:ok,
     Port.open({:spawn_executable, exec}, [
       :binary,
       :exit_status,
       :stderr_to_stdout,
       args: args
     ])}
  rescue
    error -> {:error, {:no_adapter, error}}
  end

  defp port_of(args) do
    case Enum.drop_while(args, &(&1 != "--port")) do
      ["--port", value | _rest] -> String.to_integer(value)
      _other -> @default_port
    end
  end

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
          Process.sleep(100)
          await_ready(port_number, deadline)
        end
    end
  end

  # Lightpanda's serve starts no page until one is asked for, and every later
  # command carries the session id that attaching to it returns.
  defp new_page(cdp) do
    with {:ok, %{"targetId" => target}, cdp} <- CDP.call(cdp, "Target.createTarget", %{}),
         {:ok, %{"sessionId" => session}, cdp} <-
           CDP.call(cdp, "Target.attachToTarget", %{"targetId" => target, "flatten" => true}) do
      {:ok, session, cdp}
    else
      {:error, reason, cdp} -> {:error, reason, cdp}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_session(%{cdp: nil}), do: {:error, :not_running_adapter}
  defp ensure_session(%{cdp: cdp, session: nil}), do: new_page(cdp)
  defp ensure_session(%{cdp: cdp, session: session}), do: {:ok, session, cdp}

  defp check_navigation(%{"errorText" => text}), do: {:error, {:navigation, text}}
  defp check_navigation(_result), do: :ok

  defp body_expression, do: "document.body ? document.body.innerText : ''"

  defp await_load(cdp, session, deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + @load_timeout

    case evaluate(cdp, session, "document.readyState") do
      {:ok, "complete", cdp} ->
        {:ok, cdp}

      {:ok, _other, cdp} ->
        if System.monotonic_time(:millisecond) > deadline do
          {:error, :load_timeout, cdp}
        else
          Process.sleep(50)
          await_load(cdp, session, deadline)
        end

      {:error, reason, cdp} ->
        {:error, reason, cdp}
    end
  end

  defp evaluate(cdp, session, expression) do
    case CDP.call(cdp, "Runtime.evaluate", %{"expression" => expression}, @load_timeout, session) do
      {:ok, %{"result" => %{"value" => value}}, cdp} -> {:ok, value, cdp}
      {:ok, %{"exceptionDetails" => details}, cdp} -> {:error, {:script, details}, cdp}
      {:ok, other, cdp} -> {:error, {:script, other}, cdp}
      {:error, reason, cdp} -> {:error, reason, cdp}
    end
  end

  defp text_or_empty(text) when is_binary(text), do: text
  defp text_or_empty(nil), do: ""
  defp text_or_empty(other), do: to_string(other)

  defp decode_png(data) when is_binary(data) do
    case Base.decode64(data) do
      {:ok, png} -> {:ok, png}
      :error -> {:error, :bad_png}
    end
  end
end
