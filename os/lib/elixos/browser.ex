defmodule Elixos.Browser do
  @moduledoc """
  The headless browser (M25, docs/ROADMAP.md).

  The protocol is the ecosystem's: `cdp_ex` speaks CDP over a WebSocket, and
  `Elixos.Browser.CDP` is the little session/page interface around it - the same
  one `jido_browser`'s Lightpanda adapter expects, which keeps that adapter one
  line away if its dependency situation ever changes (ADR-065). The process is
  started here, as a `Port`: no launcher that wants a shell (ADR-012).

  The binary ships in the read-only system image under `/system/browser`,
  pinned and verified when the image is built, never downloaded at run time
  (ADR-064), with its private glibc at the paths glibc itself expects so the
  unmodified upstream binary runs as itself. The manifest decides the argv;
  `command/1` is that decision, pure and testable. Starting is asynchronous, so
  a slow or missing adapter never delays the prompt, and a failure leaves
  `status/0` at `{:error, :not_running}` instead of taking anything down.
  """

  use GenServer

  require Logger

  alias Elixos.Browser.CDP

  @manifest "/system/browser/manifest.json"
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
      {:ok, %{session: nil, page: nil}, {:continue, :start}}
    else
      :ignore
    end
  end

  @impl true
  def handle_continue(:start, state) do
    with {:ok, argv} <- command(),
         :ok <- check_command(argv),
         {:ok, session} <- CDP.start(command: argv) do
      {:noreply, %{state | session: session}}
    else
      {:error, reason} ->
        Logger.warning("browser: not starting: #{inspect(reason)}")
        {:noreply, state}

      other ->
        Logger.warning("browser: not starting: #{inspect(other)}")
        {:noreply, state}
    end
  end

  # The manifest's argv is what gets spawned - a loader first for a glibc
  # binary, with its libraries beside it under /system (ADR-064).
  defp check_command([exec | _args]) do
    if File.regular?(exec), do: :ok, else: {:error, {:missing_program, exec}}
  end

  @impl true
  def handle_call({kind, _payload}, _from, %{session: nil} = state)
      when kind in [:navigate, :eval],
      do: {:reply, {:error, :not_running_adapter}, state}

  def handle_call(:screenshot, _from, %{session: nil} = state),
    do: {:reply, {:error, :not_running_adapter}, state}

  def handle_call({:navigate, url}, _from, state) do
    with {:ok, page, state} <- page(state),
         :ok <- CDP.Page.navigate(page, url),
         {:ok, text} <- CDP.Page.text(page) do
      {:reply, {:ok, text}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:eval, script}, _from, state) do
    with {:ok, page, state} <- page(state),
         {:ok, value} <- CDP.Page.evaluate(page, script) do
      {:reply, {:ok, value}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:screenshot, _from, state) do
    with {:ok, page, state} <- page(state),
         {:ok, png} <- CDP.Page.screenshot(page) do
      {:reply, {:ok, png}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    if state.session, do: CDP.stop(state.session)
    :ok
  end

  # One page per session, made on first use: Lightpanda's serve mode keeps one.
  defp page(%{page: nil} = state) do
    case CDP.new_page(state.session) do
      {:ok, page} -> {:ok, page, %{state | page: page}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp page(%{page: page} = state), do: {:ok, page, state}
end
