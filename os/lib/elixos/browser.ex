defmodule Elixos.Browser do
  @moduledoc """
  The headless browser (M25, docs/ROADMAP.md).

  The stack is the ecosystem's, not ours (ADR-065): `jido_browser`'s Lightpanda
  adapter speaks CDP through `light_cdp`, which owns the process. What this
  module owns is the trust decision - *which* binary, pinned and verified - and
  the two facts a caller should not have to know: the adapter starts only in
  normal mode, and it must not keep the prompt waiting or take it down with it.

  The binary ships in the read-only system image under `/system/browser`,
  verified when the image is built, never downloaded at run time (ADR-064). Its
  manifest decides the argv: a musl-clean binary is exec'd directly, a glibc one
  through glibc's own loader - and the image installs the private glibc at the
  standard paths, so in practice the upstream binary runs directly and the
  adapter can spawn it by path. `command/1` is that decision, pure and testable.
  """

  use GenServer

  require Logger

  alias Jido.Browser, as: JidoBrowser

  @adapter Jido.Browser.Adapters.Lightpanda
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
      {:ok, %{session: nil}, {:continue, :start}}
    else
      :ignore
    end
  end

  # Starting is asynchronous on purpose: a slow or missing adapter never delays
  # the prompt, and a failure leaves `status/0` at not_running instead of taking
  # anything down with it. Calls that arrive first simply queue.
  @impl true
  def handle_continue(:start, state) do
    with {:ok, [exec | _args]} <- command(),
         :ok <- check_binary(exec),
         {:ok, session} <-
           JidoBrowser.start_session(
             adapter: @adapter,
             binary_path: exec,
             # The adapter's own defaults are `light_cdp`, which would spawn the
             # browser through `erlexec` and wants SHELL set (ADR-012). These
             # two are the same contract over `cdp_ex` and a Port.
             light_cdp_module: Elixos.Browser.CDP,
             page_module: Elixos.Browser.CDP.Page
           ) do
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

  # The ecosystem's server spawns the binary itself, so the manifest must name
  # the binary - not a loader that would need arguments of ours (ADR-065: the
  # private glibc lives at the standard paths for exactly this reason).
  defp check_binary(exec) do
    cond do
      not File.regular?(exec) -> {:error, {:missing_binary, exec}}
      Path.basename(exec) =~ "ld-linux" -> {:error, {:loader_manifest, exec}}
      true -> :ok
    end
  end

  @impl true
  def handle_call({kind, _payload}, _from, %{session: nil} = state)
      when kind in [:navigate, :eval],
      do: {:reply, {:error, :not_running_adapter}, state}

  def handle_call(:screenshot, _from, %{session: nil} = state),
    do: {:reply, {:error, :not_running_adapter}, state}

  def handle_call({:navigate, url}, _from, state) do
    with {:ok, session, _nav} <- JidoBrowser.navigate(session(state), url),
         {:ok, session, %{content: text}} <- JidoBrowser.extract_content(session, format: :text) do
      {:reply, {:ok, text}, %{state | session: session}}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:eval, script}, _from, state) do
    case JidoBrowser.evaluate(session(state), script) do
      {:ok, session, %{result: value}} -> {:reply, {:ok, value}, %{state | session: session}}
      {:ok, session, other} -> {:reply, {:ok, other}, %{state | session: session}}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:screenshot, _from, state) do
    case JidoBrowser.screenshot(session(state)) do
      {:ok, session, %{bytes: png}} -> {:reply, {:ok, png}, %{state | session: session}}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    if state.session, do: JidoBrowser.end_session(state.session)
    :ok
  end

  defp session(%{session: session}), do: session
end
