defmodule Elixos.GUI do
  @moduledoc """
  The non-critical framebuffer view of the Ask queue (M27).

  Emerge renders headless raster RGBA frames. A libc-free Port helper owns
  `/dev/fb0` and evdev devices; a fixed privileged broker leases fbcon handover
  to that helper. Input and off-screen rendering also work through the public
  `input/1` and `render_dialog/1` seams. Rescue starts none of this.

  Renderer load/start failures leave the text console available. A native
  renderer crash can still take down the BEAM; the shim remains outside it.
  """

  use GenServer, restart: :temporary
  require Logger

  alias Elixos.{Ask, Decimal}
  alias Elixos.GUI.{Dialog, Keyboard}
  alias VideoInterop.{Binary, Format, Frame, Rect}
  alias VideoInterop.Binary.Plane

  @io_program "/usr/bin/elixos-gui-io"
  @lease_socket "/run/elixos-console.sock"
  @startup_timeout 5_000
  @call_timeout 15_000
  @dialog_size {640, 480}

  @doc "Starts the GUI under the system's supervisor, unless it is running."
  @spec start() :: {:ok, pid()} | {:error, term()}
  def start do
    case Process.whereis(__MODULE__) do
      nil ->
        with :ok <- live_available() do
          case DynamicSupervisor.start_child(Elixos.Package.Services, {__MODULE__, []}) do
            {:ok, _pid} -> status()
            {:error, {:already_started, _pid}} -> status()
            :ignore -> {:error, :no_framebuffer}
            {:error, reason} -> {:error, reason}
          end
        end

      _pid ->
        status()
    end
  catch
    :exit, _reason -> {:error, :not_running}
  end

  @doc "The initialized GUI: `{:ok, pid}` or `{:error, :not_running}`."
  @spec status() :: {:ok, pid()} | {:error, :not_running}
  def status, do: call(:status)

  @doc "Stops rendering, releases input devices and waits for fbcon handback."
  @spec stop() :: :ok | {:error, term()}
  def stop, do: call(:stop)

  @doc "Accepts a key, pointer position or button event from a front-end."
  @spec input(term()) :: :ok | {:error, term()}
  def input(event), do: call({:input, event})

  @doc "Renders an Ask dialog without a display, returning tightly packed RGBA."
  @spec render_dialog(Ask.Question.t()) ::
          {:ok, %{width: pos_integer(), height: pos_integer(), pixels: binary()}}
          | {:error, term()}
  def render_dialog(%Ask.Question{} = question) do
    with :ok <- renderer_available() do
      {width, height} = @dialog_size
      tree = Dialog.tree(Dialog.new(question), @dialog_size)

      pixels =
        EmergeSkia.TreeRenderer.render_to_pixels(
          tree,
          [otp_app: :elixos, width: width, height: height],
          @startup_timeout
        )

      {:ok, %{width: width, height: height, pixels: pixels}}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  @doc false
  def start_link(opts) do
    if Keyword.get(opts, :mode, :normal) == :rescue or not File.exists?("/dev/fb0") do
      :ignore
    else
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end
  end

  defp call(message) do
    GenServer.call(__MODULE__, message, @call_timeout)
  catch
    :exit, _reason -> {:error, :not_running}
  end

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)

    {:ok,
     %{
       io: nil,
       renderer: nil,
       tree_state: nil,
       size: @dialog_size,
       keyboard: Keyboard.new(),
       dialog: Dialog.new(nil),
       ask_monitor: nil,
       ready: false,
       status_waiters: [],
       startup_timer: nil,
       frame_in_flight: false,
       pending_pixels: nil
     }, {:continue, :initialize}}
  end

  @impl true
  def handle_continue(:initialize, state) do
    with :ok <- live_available(),
         {:ok, _broker} <- Elixos.Privileges.request("console-handover"),
         :ok <- await_socket(System.monotonic_time(:millisecond) + @startup_timeout),
         {:ok, io, size} <- open_io() do
      initialize_renderer(%{state | io: io, size: size})
    else
      {:error, reason} -> halt(state, reason)
    end
  rescue
    error -> halt(state, Exception.message(error))
  catch
    :exit, reason -> halt(state, reason)
  end

  defp initialize_renderer(state) do
    {width, height} = state.size

    with {:ok, renderer} <-
           EmergeSkia.start(
             otp_app: :elixos,
             owner: self(),
             backend: :headless,
             rendering_api: :raster,
             width: width,
             height: height,
             headless: [mode: :binary, target: self(), pixel_format: :rgba8888]
           ) do
      state = %{state | renderer: renderer}

      case Ask.subscribe() do
        {:ok, questions} ->
          monitor = Process.monitor(Process.whereis(Ask))
          timer = Process.send_after(self(), :startup_timeout, @startup_timeout)
          state = %{state | ask_monitor: monitor, startup_timer: timer}
          {:noreply, draw(select_question(state, questions))}

        {:error, reason} ->
          halt(state, reason)
      end
    else
      {:error, reason} -> halt(state, {:renderer, reason})
    end
  rescue
    error -> halt(state, Exception.message(error))
  end

  @impl true
  def handle_call(:status, _from, %{ready: true} = state), do: {:reply, {:ok, self()}, state}

  def handle_call(:status, from, state),
    do: {:noreply, %{state | status_waiters: [from | state.status_waiters]}}

  def handle_call(:stop, _from, state) do
    {result, state} = shutdown(state)
    {:stop, :normal, result, state}
  end

  def handle_call({:input, event}, _from, state) do
    case apply_event(state, event) do
      {:ok, state} ->
        {:reply, :ok, state}

      {:error, reason, state} ->
        {:reply, {:error, reason}, state}

      {:stop, state} ->
        {result, state} = shutdown(state)
        {:stop, :normal, result, state}
    end
  rescue
    error -> halt(state, Exception.message(error))
  end

  @impl true
  def handle_info({:elixos_ask, _snapshot}, state) do
    # Input can resolve a question while older notifications are queued. Read
    # the authoritative queue rather than resurrecting one from a stale view.
    {:noreply, refresh(state)}
  rescue
    error -> halt(state, Exception.message(error))
  end

  def handle_info({:emerge_skia_frame, frame}, state) do
    case pixels(frame, state.size) do
      {:ok, data} -> {:noreply, queue_frame(state, data)}
      {:error, reason} -> halt(state, reason)
    end
  rescue
    error -> halt(state, Exception.message(error))
  end

  def handle_info({io, {:data, "PRESENTED"}}, %{io: io} = state) do
    if not state.ready do
      Process.cancel_timer(state.startup_timer)
      Enum.each(state.status_waiters, &GenServer.reply(&1, {:ok, self()}))
    end

    state = %{state | ready: true, status_waiters: [], frame_in_flight: false}

    case state.pending_pixels do
      nil -> {:noreply, state}
      data -> {:noreply, queue_frame(%{state | pending_pixels: nil}, data)}
    end
  rescue
    error -> halt(state, Exception.message(error))
  end

  def handle_info({io, {:data, packet}}, %{io: io} = state) do
    case Keyboard.decode(state.keyboard, packet) do
      {:ok, events, keyboard} ->
        state = %{state | keyboard: keyboard}

        case Enum.reduce_while(events, {:ok, state}, fn event, {:ok, state} ->
               case apply_event(state, event) do
                 {:ok, state} -> {:cont, {:ok, state}}
                 {:error, _reason, state} -> {:cont, {:ok, state}}
                 {:stop, state} -> {:halt, {:stop, state}}
               end
             end) do
          {:ok, state} ->
            {:noreply, state}

          {:stop, state} ->
            {result, state} = shutdown(state)
            if result != :ok, do: Logger.warning("elixos-gui: shutdown #{inspect(result)}")
            {:stop, :normal, state}
        end

      {:error, reason} ->
        halt(state, reason)
    end
  rescue
    error -> halt(state, Exception.message(error))
  end

  def handle_info({io, {:exit_status, code}}, %{io: io} = state),
    do: halt(%{state | io: nil}, {:io_exit, code})

  def handle_info({:EXIT, io, reason}, %{io: io} = state),
    do: halt(%{state | io: nil}, {:io_exit, reason})

  def handle_info({:DOWN, monitor, :process, _pid, reason}, %{ask_monitor: monitor} = state),
    do: halt(state, {:question_queue_exit, reason})

  def handle_info(:startup_timeout, %{ready: false} = state), do: halt(state, :frame_timeout)

  def handle_info({:emerge_skia_log, level, source, message}, state) do
    if level in [:error, :warn, :warning],
      do: Logger.warning("elixos-gui: #{source}: #{message}")

    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp apply_event(state, event) do
    case Dialog.input(state.dialog, event, state.size) do
      {:continue, dialog} ->
        next = %{state | dialog: dialog}
        {:ok, if(dialog == state.dialog, do: next, else: draw(next))}

      {:answer, value, dialog} ->
        resolve(%{state | dialog: dialog}, Ask.answer(dialog.question.id, value))

      {:dismiss, dialog} ->
        resolve(state, Ask.dismiss(dialog.question.id))

      {:stop, _dialog} ->
        {:stop, state}
    end
  end

  defp resolve(state, :ok), do: {:ok, refresh(state)}
  defp resolve(state, {:error, reason}), do: {:error, reason, refresh(state)}

  defp refresh(state) do
    case Ask.pending() do
      questions when is_list(questions) ->
        next = select_question(state, questions)
        if next.dialog == state.dialog, do: next, else: draw(next)

      {:error, reason} ->
        raise "question queue unavailable: #{inspect(reason)}"
    end
  end

  defp select_question(state, questions) do
    %{state | dialog: Dialog.show(state.dialog, List.first(questions))}
  end

  defp draw(state) do
    tree = Dialog.tree(state.dialog, state.size)

    {tree_state, _assigned} =
      if state.tree_state == nil,
        do: EmergeSkia.upload_tree(state.renderer, tree),
        else: EmergeSkia.TreeRenderer.patch_tree_runtime(state.renderer, state.tree_state, tree)

    %{state | tree_state: tree_state}
  end

  defp pixels(%Frame{} = frame, {width, height}) do
    with :ok <- VideoInterop.validate(frame),
         %Frame{
           coded_width: ^width,
           coded_height: ^height,
           visible_rect: %Rect{x: 0, y: 0, width: ^width, height: ^height},
           format: %Format{storage: %Binary.Format{pixel_format: :rgba8888}},
           storage: %Binary{data: data, planes: [%Plane{offset: 0, stride: stride}]},
           acquire_sync: :implicit,
           lease: nil
         } <- frame,
         true <- stride == width * 4 and byte_size(data) == width * height * 4 do
      {:ok, data}
    else
      _ -> {:error, :unsupported_frame}
    end
  end

  defp pixels(_frame, _size), do: {:error, :unsupported_frame}

  defp queue_frame(%{frame_in_flight: true} = state, data),
    do: %{state | pending_pixels: data}

  defp queue_frame(state, data) do
    true = Port.command(state.io, data)
    %{state | frame_in_flight: true}
  end

  defp open_io do
    io = Port.open({:spawn_executable, @io_program}, [:binary, :exit_status, {:packet, 4}])

    receive do
      {^io, {:data, "READY " <> dimensions}} ->
        with [raw_width, raw_height] <- String.split(dimensions),
             {:ok, width} <- Decimal.parse_u32(raw_width),
             {:ok, height} <- Decimal.parse_u32(raw_height),
             true <- width in 1..8192 and height in 1..8192 do
          {:ok, io, {width, height}}
        else
          _ ->
            Port.close(io)
            {:error, :invalid_framebuffer_size}
        end

      {^io, {:exit_status, code}} ->
        {:error, {:io_exit, code}}

      {:EXIT, ^io, reason} ->
        {:error, {:io_exit, reason}}
    after
      @startup_timeout ->
        Port.close(io)
        {:error, :io_start_timeout}
    end
  end

  defp await_socket(deadline) do
    case File.stat(@lease_socket) do
      {:ok, %{uid: 0, gid: 1000, mode: mode}} when Bitwise.band(mode, 0o777) == 0o660 ->
        :ok

      _ ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(10)
          await_socket(deadline)
        else
          {:error, :console_broker_timeout}
        end
    end
  end

  defp live_available do
    with :ok <- renderer_available(),
         true <- File.exists?("/dev/fb0"),
         true <- File.regular?(@io_program) do
      :ok
    else
      false -> {:error, :framebuffer_io_unavailable}
      {:error, _reason} = error -> error
    end
  end

  defp renderer_available do
    case Elixos.Boot.Env.current() do
      {:ok, :host} ->
        :ok

      {:ok, %{mode: :rescue}} ->
        {:error, :rescue}

      {:ok, _env} ->
        arch = :erlang.system_info(:system_architecture) |> to_string()

        target =
          cond do
            String.starts_with?(arch, "x86_64") -> "x86_64-unknown-linux-musl"
            String.starts_with?(arch, "aarch64") -> "aarch64-unknown-linux-musl"
            true -> nil
          end

        if target && File.regular?("/system/gui/#{target}/libemerge_skia.so"),
          do: :ok,
          else: {:error, :renderer_unavailable}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp shutdown(state) do
    renderer_result = stop_renderer(state.renderer)
    io_result = stop_io(state.io)
    result = if renderer_result == :ok, do: io_result, else: renderer_result
    {result, %{state | renderer: nil, io: nil}}
  end

  defp stop_renderer(nil), do: :ok

  defp stop_renderer(renderer) do
    EmergeSkia.stop(renderer)
  rescue
    error -> {:error, {:renderer_shutdown, Exception.message(error)}}
  end

  defp stop_io(nil), do: :ok

  defp stop_io(io) do
    true = Port.command(io, <<>>)

    receive do
      {^io, {:exit_status, 0}} -> :ok
      {^io, {:exit_status, code}} -> {:error, {:io_exit, code}}
      {:EXIT, ^io, reason} -> {:error, {:io_exit, reason}}
    after
      @startup_timeout + 1_000 ->
        Port.close(io)
        {:error, :console_release_timeout}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp halt(state, reason) do
    Logger.warning("elixos-gui: unavailable (#{inspect(reason)}); retaining text console")
    Enum.each(state.status_waiters, &GenServer.reply(&1, {:error, :not_running}))
    {:stop, :normal, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.renderer != nil do
      case stop_renderer(state.renderer) do
        :ok -> :ok
        error -> Logger.warning("elixos-gui: renderer shutdown #{inspect(error)}")
      end
    end

    if state.io != nil and Port.info(state.io) != nil, do: Port.close(state.io)
    :ok
  end
end
