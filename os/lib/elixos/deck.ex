defmodule Elixos.Deck do
  @moduledoc """
  The deck's panel (M33, ADR-106): a terminal view hosting the login REPL on
  the shared-memory framebuffer the coprocessor scans out
  (docs/PROTOCOL.md §12), with an on-screen keyboard driven by touch.

  The shim finds the framebuffer (`elixos.deck`, §5), grants it to the BEAM
  and passes its path as `ELIXOS_DECK` (§3). This process then:

    * runs `elixos-deck-fb` on that path as a Port: the region is mapped
      there, and every pixel reaches it as a fill, blit or move command
      followed by a commit with a damage rectangle (`Elixos.Deck.Paint`);
    * draws a status line (`rescue` in rescue mode, the generation
      otherwise), the terminal (`Elixos.Deck.Terminal`, glyphs from
      `Elixos.Deck.Font`) and the keyboard (`Elixos.Deck.Keyboard`), at the
      places `Elixos.Deck.Layout` gives;
    * is an Erlang IO server, and the group leader of a login REPL session
      started with the console's MFA (`Elixos.Boot.Login.login_repl/0`), so
      the session has its own working directory (ADR-020) and the serial
      console's session is untouched;
    * subscribes to `Elixos.Coproc.Touch` whenever the coprocessor link
      runs, and turns taps into keys;
    * keeps the coprocessor's display lease (`Elixos.Deck.Lease`), so the
      panel says `Elixos restarting` while this BEAM is away.

  The deck is a view, never boot-critical: without `ELIXOS_DECK` it does not
  start, and a helper that fails logs and stops the deck alone (the child is
  temporary). It starts in rescue mode as well; there is no coprocessor link
  in rescue, so the panel shows the session without touch input.

  Rendering is pulled from the model: writes and keys only change the
  terminal and mark damage; one commit is in flight at a time, and whatever
  changed meanwhile goes out with the next one. A keystroke commits the
  damage rectangle of the cells it changed, not the frame.

  The IO server handles `put_chars`, `get_line`, `get_chars`, `get_until`
  (with prompts), `get_password`, `setopts`/`getopts` (`binary`, `encoding`,
  `echo`, `expand_fun`), `get_geometry` and `requests`. Line editing is the
  keyboard's: characters, backspace and enter. Keys typed while no read is
  pending wait for the next one.
  """

  use GenServer
  require Logger

  alias Elixos.Deck.{Keyboard, Layout, Paint, Terminal}

  @helper "/usr/bin/elixos-deck-fb"
  @ready_timeout 5_000
  @subscribe_ms 1_000
  @restart_ms 1_000

  @doc "Supervisor child spec: temporary, so a failing deck never takes the boot tree with it."
  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, restart: :temporary}
  end

  @doc """
  Starts the deck on the region named by `ELIXOS_DECK`, or steps aside
  (`:ignore`) without one. Options (tests): `region:`, `helper:`, `shell:`
  an MFA returning the shell's pid, `status:` the status text, `name:`,
  `lease:` options for `Elixos.Deck.Lease` (`false`: no lease).
  """
  def start_link(opts \\ []) do
    case Keyword.get_lazy(opts, :region, fn -> System.get_env("ELIXOS_DECK") end) do
      nil ->
        :ignore

      "" ->
        :ignore

      region ->
        GenServer.start_link(__MODULE__, Keyword.put(opts, :region, region),
          name: Keyword.get(opts, :name, __MODULE__)
        )
    end
  end

  @doc "The terminal's rows as strings (what the panel shows)."
  @spec lines(GenServer.server()) :: [String.t()]
  def lines(server \\ __MODULE__), do: GenServer.call(server, :lines)

  @doc """
  Feeds a touch event as the coprocessor would deliver it:
  `{:touch, :down | :move | :up, x, y}`.
  """
  @spec touch(GenServer.server(), tuple()) :: :ok
  def touch(server \\ __MODULE__, {:touch, _action, _x, _y} = event) do
    send(GenServer.whereis(server), event)
    :ok
  end

  @doc """
  What the deck reports: `seq` the last commit the helper acknowledged (the
  region's `seq`), `status` the status line, `touch` whether it is
  subscribed to the coprocessor's touch events, `region` the framebuffer.
  """
  @spec info(GenServer.server()) :: map()
  def info(server \\ __MODULE__), do: GenServer.call(server, :info)

  ## GenServer

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    state = %{
      region: Keyword.fetch!(opts, :region),
      helper: Keyword.get(opts, :helper, @helper),
      shell_mfa: Keyword.get(opts, :shell),
      status: Keyword.get_lazy(opts, :status, &status_text/0),
      mode: Keyword.get_lazy(opts, :mode, &mode/0),
      port: nil,
      seq: 0,
      term: Terminal.new(Layout.columns(), Layout.rows()),
      keyboard: Keyboard.new(),
      full: false,
      in_flight: false,
      dirty: false,
      redraw_keyboard: false,
      shell: nil,
      # The IO server: queued requests that wait for input, the active one,
      # the line being edited, keys typed with no read pending, input
      # already entered but not consumed.
      reads: :queue.new(),
      reading: nil,
      line: "",
      keys: :queue.new(),
      input: "",
      binary: true,
      echo: true,
      expand_fun: nil,
      coproc: nil,
      lease: Keyword.get(opts, :lease, [])
    }

    {:ok, state, {:continue, :open}}
  end

  @impl true
  def handle_continue(:open, state) do
    case open_helper(state) do
      {:ok, port, seq} ->
        state = %{state | port: port, seq: seq} |> paint_all()
        send(self(), :subscribe)
        if state.lease, do: Elixos.Deck.Lease.start_link(state.lease)
        {:noreply, start_shell(state)}

      {:error, reason} ->
        Logger.warning("Elixos.Deck not started: #{inspect(reason)}")
        {:stop, :normal, state}
    end
  end

  defp open_helper(state) do
    if File.exists?(state.helper) do
      port =
        Port.open({:spawn_executable, state.helper}, [
          {:packet, 4},
          :binary,
          :exit_status,
          args: [state.region]
        ])

      receive do
        {^port, {:data, "READY " <> rest}} ->
          geometry = "#{Layout.width()} #{Layout.height()} "

          case rest do
            ^geometry <> seq ->
              {:ok, port, String.to_integer(seq)}

            other ->
              Port.close(port)
              {:error, {:unexpected_geometry, other}}
          end

        {^port, {:exit_status, status}} ->
          {:error, {:helper_exited, status}}
      after
        @ready_timeout ->
          Port.close(port)
          {:error, :helper_timeout}
      end
    else
      {:error, {:no_helper, state.helper}}
    end
  end

  @impl true
  def handle_call(:lines, _from, state), do: {:reply, Terminal.lines(state.term), state}

  def handle_call(:info, _from, state) do
    {:reply,
     %{seq: state.seq, status: state.status, touch: state.coproc != nil, region: state.region},
     state}
  end

  @impl true
  def handle_info({port, {:data, "COMMITTED " <> seq}}, %{port: port} = state) do
    {:noreply, flush(%{state | in_flight: false, seq: String.to_integer(seq)})}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.warning("Elixos.Deck: elixos-deck-fb exited with status #{status}")
    {:stop, :normal, %{state | port: nil}}
  end

  def handle_info({:EXIT, port, _reason}, %{port: port} = state), do: {:noreply, state}

  def handle_info({:EXIT, shell, reason}, %{shell: shell} = state) do
    state = write(%{state | shell: nil}, "\n[session ended: #{inspect(reason)}]\n")
    Process.send_after(self(), :restart_shell, @restart_ms)
    {:noreply, flush(state)}
  end

  def handle_info({:EXIT, _other, _reason}, state), do: {:noreply, state}

  def handle_info(:restart_shell, state), do: {:noreply, start_shell(state)}

  def handle_info({:io_request, from, reply_as, request}, state) do
    {:noreply, state |> io_request(from, reply_as, request) |> flush()}
  end

  def handle_info({:touch, _action, x, y} = event, state) when is_integer(x) and is_integer(y) do
    {keyboard, typed, relayer} = Keyboard.touch(state.keyboard, event)
    state = %{state | keyboard: keyboard, redraw_keyboard: state.redraw_keyboard or relayer}
    state = if typed, do: key(state, typed), else: state
    {:noreply, flush(state)}
  end

  def handle_info(:subscribe, state) do
    Process.send_after(self(), :subscribe, @subscribe_ms)
    {:noreply, subscribe(state)}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{coproc: ref} = state) do
    {:noreply, %{state | coproc: nil}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{port: port}) when is_port(port) do
    # A zero-length packet: the helper exits 0.
    Port.command(port, "")
    :ok
  catch
    :error, _ -> :ok
  end

  def terminate(_reason, _state), do: :ok

  ## Touch

  # The coprocessor link may start, stop or restart at any time (its
  # configuration is the user's): subscribe whenever a link process runs
  # that this deck is not subscribed to.
  defp subscribe(%{coproc: nil} = state) do
    with pid when is_pid(pid) <- Process.whereis(Elixos.Coproc),
         :ok <- safe_subscribe() do
      %{state | coproc: Process.monitor(pid)}
    else
      _ -> state
    end
  end

  defp subscribe(state), do: state

  defp safe_subscribe do
    Elixos.Coproc.Touch.subscribe(self())
  catch
    :exit, reason -> {:error, reason}
  end

  ## The session

  defp start_shell(state) do
    {:ok, _} = Application.ensure_all_started(:iex)

    {m, f, a} =
      case state.shell_mfa do
        nil ->
          {:ok, mfa} = Elixos.Boot.Login.login_repl()
          mfa

        mfa ->
          mfa
      end

    # As OTP's `group` does: the shell inherits its group leader from the
    # process that starts it, so this process leads it for the call.
    leader = Process.group_leader()
    Process.group_leader(self(), self())

    shell =
      try do
        apply(m, f, a)
      after
        Process.group_leader(self(), leader)
      end

    if is_pid(shell), do: Process.link(shell)
    %{state | shell: shell}
  end

  ## The IO server

  defp io_request(state, from, reply_as, request) do
    case request(state, request) do
      {:reply, value, state} ->
        send(from, {:io_reply, reply_as, value})
        state

      {:read, read, state} ->
        %{state | reads: :queue.in({from, reply_as, read}, state.reads)} |> next_read()
    end
  end

  defp request(state, {:put_chars, encoding, chars}), do: put_chars(state, encoding, chars)
  defp request(state, {:put_chars, chars}), do: put_chars(state, :latin1, chars)

  defp request(state, {:put_chars, encoding, m, f, a}) do
    put_chars(state, encoding, apply(m, f, a))
  catch
    _, _ -> {:reply, {:error, :put_chars}, state}
  end

  defp request(state, {:put_chars, m, f, a}), do: request(state, {:put_chars, :latin1, m, f, a})

  defp request(state, {:get_line, encoding, prompt}),
    do: {:read, {:line, encoding, prompt}, state}

  defp request(state, {:get_line, prompt}), do: request(state, {:get_line, :latin1, prompt})

  defp request(state, {:get_chars, encoding, prompt, n}) when is_integer(n) and n >= 0,
    do: {:read, {:chars, encoding, prompt, n}, state}

  defp request(state, {:get_chars, prompt, n}),
    do: request(state, {:get_chars, :latin1, prompt, n})

  defp request(state, {:get_until, encoding, prompt, m, f, a}),
    do: {:read, {:until, encoding, prompt, {m, f, a}, []}, state}

  defp request(state, {:get_until, prompt, m, f, a}),
    do: request(state, {:get_until, :latin1, prompt, m, f, a})

  defp request(state, {:get_password, encoding}), do: {:read, {:password, encoding}, state}

  defp request(state, {:setopts, opts}) when is_list(opts) do
    Enum.reduce_while(opts, {:reply, :ok, state}, fn opt, {:reply, :ok, state} ->
      case setopt(state, opt) do
        {:ok, state} -> {:cont, {:reply, :ok, state}}
        :error -> {:halt, {:reply, {:error, :enotsup}, state}}
      end
    end)
  end

  defp request(state, :getopts) do
    opts =
      [binary: state.binary, encoding: :unicode, echo: state.echo] ++
        if state.expand_fun, do: [expand_fun: state.expand_fun], else: []

    {:reply, opts, state}
  end

  defp request(state, {:get_geometry, :columns}), do: {:reply, Layout.columns(), state}
  defp request(state, {:get_geometry, :rows}), do: {:reply, Layout.rows(), state}

  # A batch: every request in order, answered with the last reply. A read in
  # the batch is not supported (OTP's own servers only batch output).
  defp request(state, {:requests, requests}) when is_list(requests) do
    Enum.reduce_while(requests, {:reply, :ok, state}, fn request, {:reply, _value, state} ->
      case request(state, request) do
        {:reply, {:error, _} = error, state} -> {:halt, {:reply, error, state}}
        {:reply, _value, _state} = reply -> {:cont, reply}
        {:read, _read, state} -> {:halt, {:reply, {:error, :request}, state}}
      end
    end)
  end

  defp request(state, _other), do: {:reply, {:error, :request}, state}

  defp setopt(state, :binary), do: {:ok, %{state | binary: true}}
  defp setopt(state, :list), do: {:ok, %{state | binary: false}}
  defp setopt(state, {:binary, b}) when is_boolean(b), do: {:ok, %{state | binary: b}}
  defp setopt(state, {:echo, e}) when is_boolean(e), do: {:ok, %{state | echo: e}}

  defp setopt(state, {:expand_fun, fun}) when is_function(fun),
    do: {:ok, %{state | expand_fun: fun}}

  defp setopt(state, {:encoding, e}) when e in [:unicode, :utf8, :latin1], do: {:ok, state}
  defp setopt(_state, _opt), do: :error

  defp put_chars(state, encoding, chars) do
    case to_text(chars, encoding) do
      {:ok, text} -> {:reply, :ok, write(state, text)}
      :error -> {:reply, {:error, :put_chars}, state}
    end
  end

  defp to_text(chars, encoding) do
    case :unicode.characters_to_binary(
           chars,
           if(encoding == :latin1, do: :latin1, else: :unicode)
         ) do
      text when is_binary(text) -> {:ok, text}
      _ -> :error
    end
  catch
    _, _ -> :error
  end

  # Starts the oldest waiting read if none is active: its prompt, then the
  # keys typed ahead of it.
  defp next_read(%{reading: nil} = state) do
    case :queue.out(state.reads) do
      {:empty, _} ->
        state

      {{:value, read}, reads} ->
        state = %{state | reads: reads, reading: read}
        {_from, _reply_as, request} = read
        state = state |> write(prompt(request)) |> satisfy()
        replay(state)
    end
  end

  defp next_read(state), do: state

  defp prompt({:line, encoding, prompt}), do: prompt_text(prompt, encoding)
  defp prompt({:chars, encoding, prompt, _n}), do: prompt_text(prompt, encoding)
  defp prompt({:until, encoding, prompt, _mfa, []}), do: prompt_text(prompt, encoding)
  defp prompt({:until, _encoding, _prompt, _mfa, _cont}), do: "...> "
  defp prompt({:password, _encoding}), do: ""

  defp prompt_text(prompt, encoding) do
    case to_text(prompt, encoding) do
      {:ok, text} -> text
      :error -> ""
    end
  end

  defp replay(%{reading: nil} = state), do: state

  defp replay(state) do
    case :queue.out(state.keys) do
      {:empty, _} -> state
      {{:value, key}, keys} -> %{state | keys: keys} |> key(key) |> replay()
    end
  end

  defp key(%{reading: nil} = state, key), do: %{state | keys: :queue.in(key, state.keys)}

  defp key(state, {:char, text}) do
    state = %{state | line: state.line <> text}
    if echo?(state), do: write(state, text), else: state
  end

  defp key(%{line: ""} = state, :backspace), do: state

  defp key(state, :backspace) do
    state = %{state | line: String.slice(state.line, 0..-2//1)}
    if echo?(state), do: write(state, "\b \b"), else: state
  end

  defp key(state, :enter) do
    state = write(state, "\n")
    %{state | input: state.input <> state.line <> "\n", line: ""} |> satisfy()
  end

  defp echo?(%{reading: {_, _, {:password, _}}}), do: false
  defp echo?(state), do: state.echo

  # Answers the active read from the entered input if it can; then the next
  # read starts.
  defp satisfy(%{reading: nil} = state), do: state

  defp satisfy(%{reading: {from, reply_as, request}} = state) do
    case complete(request, state) do
      {:done, value, input} ->
        send(from, {:io_reply, reply_as, value})
        %{state | reading: nil, input: input} |> next_read()

      {:more, request, input} ->
        state = %{state | reading: {from, reply_as, request}, input: input}
        write(state, prompt(request))

      :wait ->
        state
    end
  end

  defp complete({kind, encoding, _prompt}, state) when kind in [:line] do
    case String.split(state.input, "\n", parts: 2) do
      [line, rest] -> {:done, cast(line <> "\n", encoding, state), rest}
      [_partial] -> :wait
    end
  end

  defp complete({:password, encoding}, state) do
    case String.split(state.input, "\n", parts: 2) do
      [line, rest] -> {:done, cast(line, encoding, state), rest}
      [_partial] -> :wait
    end
  end

  defp complete({:chars, encoding, _prompt, n}, state) do
    if String.length(state.input) >= n do
      {taken, rest} = String.split_at(state.input, n)
      {:done, cast(taken, encoding, state), rest}
    else
      :wait
    end
  end

  # get_until: each entered line goes to the caller's function, as a
  # character list, until it is done (io protocol: `M:F(Cont, Data, ...)`).
  defp complete({:until, encoding, prompt, {m, f, a} = mfa, cont}, state) do
    case String.split(state.input, "\n", parts: 2) do
      [line, rest] ->
        case apply(m, f, [cont, String.to_charlist(line <> "\n") | a]) do
          {:done, result, left} -> {:done, result, leftover(left) <> rest}
          {:more, cont} -> {:more, {:until, encoding, prompt, mfa, cont}, rest}
        end

      [_partial] ->
        :wait
    end
  end

  defp leftover(:eof), do: ""
  defp leftover(chars) when is_list(chars) or is_binary(chars), do: IO.chardata_to_string(chars)

  # What a read returns: binaries in binary mode, character lists otherwise;
  # latin1 reads get latin1 bytes.
  defp cast(text, :latin1, %{binary: true}),
    do: :unicode.characters_to_binary(text, :unicode, :latin1)

  defp cast(text, _encoding, %{binary: true}), do: text
  defp cast(text, _encoding, _state), do: String.to_charlist(text)

  ## Rendering

  defp write(state, text), do: %{state | term: Terminal.write(state.term, text), dirty: true}

  defp flush(%{port: nil} = state), do: state
  defp flush(%{in_flight: true} = state), do: state
  defp flush(%{dirty: false, redraw_keyboard: false} = state), do: state

  defp flush(state) do
    full =
      if state.full do
        command(state, Paint.fill({0, 0, Layout.width(), Layout.height()}, Paint.background()))
        paint_status(state)
        {0, 0, Layout.width(), Layout.height()}
      end

    cursor = Terminal.cursor(state.term)
    term = Terminal.touch(state.term, cursor)
    {damage, term} = Terminal.take_damage(term)
    {x0, y0, w, h} = Layout.terminal_rect()

    moved =
      if damage.scrolled in 1..(Layout.rows() - 1)//1 do
        shift = damage.scrolled * Elixos.Deck.Font.height()
        command(state, Paint.move({x0, y0 + shift, w, h - shift}, {x0, y0}))
        Paint.union(full, {x0, y0, w, h})
      else
        full
      end

    dirty =
      if damage.scrolled >= Layout.rows(),
        do: for(row <- 0..(Layout.rows() - 1), do: {row, 0, Layout.columns() - 1}),
        else: damage.dirty

    region =
      Enum.reduce(dirty, moved, fn {row, first, last}, region ->
        {x, y, _, _} = Layout.cell_rect({row, first})
        command(state, Paint.text_run({x, y}, row_cells(term, cursor, row, first, last)))

        Paint.union(
          region,
          {x, y, (last - first + 1) * Elixos.Deck.Font.width(), Elixos.Deck.Font.height()}
        )
      end)

    region =
      if state.redraw_keyboard do
        paint_keyboard(state)
        Paint.union(region, Layout.keyboard_rect())
      else
        region
      end

    # The next flush repaints the cell the cursor leaves.
    state = %{
      state
      | term: Terminal.touch(term, cursor),
        dirty: false,
        redraw_keyboard: false,
        full: false
    }

    commit(state, region)
  end

  defp commit(state, nil), do: state

  defp commit(state, region) do
    command(state, Paint.commit(region))
    %{state | in_flight: true}
  end

  defp row_cells(term, cursor, row, first, last) do
    fg = Paint.text()
    bg = Paint.background()

    for column <- first..last do
      c = Terminal.at(term, {row, column})
      if {row, column} == cursor, do: {c, bg, fg}, else: {c, fg, bg}
    end
  end

  # The first frame: everything, committed as the whole panel.
  defp paint_all(state) do
    last = Layout.columns() - 1
    term = Enum.reduce(0..(Layout.rows() - 1), state.term, &Terminal.touch(&2, {&1, 0}))
    term = Enum.reduce(0..(Layout.rows() - 1), term, &Terminal.touch(&2, {&1, last}))
    flush(%{state | term: term, dirty: true, redraw_keyboard: true, full: true})
  end

  defp paint_status(state) do
    background = Paint.status_background(state.mode)
    command(state, Paint.fill(Layout.status_rect(), background))
    text = state.status |> String.slice(0, Layout.status_columns())

    command(
      state,
      Paint.text_run(Layout.status_origin(), Paint.cells(text, Paint.status_text(), background))
    )
  end

  defp paint_keyboard(state) do
    command(state, Paint.fill(Layout.keyboard_rect(), Paint.keyboard_background()))

    for %{label: label, action: action, rect: {x, y, w, h}} <- Keyboard.keys(state.keyboard.layer) do
      colour = if match?({:char, _}, action), do: Paint.key(), else: Paint.special_key()
      command(state, Paint.fill({x + 2, y + 2, w - 4, h - 4}, colour))
      width = String.length(label) * Elixos.Deck.Font.width()
      origin = {x + div(w - width, 2), y + div(h - Elixos.Deck.Font.height(), 2)}
      command(state, Paint.text_run(origin, Paint.cells(label, Paint.key_label(), colour)))
    end

    :ok
  end

  defp command(%{port: port}, iodata), do: Port.command(port, iodata)

  ## Status

  defp mode do
    case Elixos.Boot.Env.current() do
      {:ok, %{mode: mode}} -> mode
      _ -> :host
    end
  end

  @doc false
  def status_text do
    case Elixos.Boot.Env.current() do
      {:ok, %{mode: :rescue, generation: g, attempt: a}} ->
        "Elixos  rescue  generation #{g}, attempt #{a}"

      {:ok, %{mode: :normal, generation: g}} ->
        "Elixos  generation #{g}"

      _ ->
        "Elixos"
    end
  end
end
