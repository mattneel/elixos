defmodule Elixos.CoprocBoardK230Test do
  @moduledoc """
  M33: the board backends of the coprocessor's touch, LoRa, power and
  console drivers (os/src/coproc_{touch,lora,power,console}_k230.erl), on
  AtomVM's Unix build with `ELIXOS_COPROC_DRIVERS=sim,touch=k230,...`.

  On the board they call the firmware's NIFs (`coproc_k230:*`,
  coproc/src/platform_nifs.c), whose drivers are checked on the build host
  against device models and LilyGO's code (coproc/test/board_trace/run.sh).
  Here a bundle carries a `coproc_k230` module of the test's own that plays
  those NIFs: it answers from queues the test fills and logs what it was
  asked (`Elixos.Coproc.call(:coproc_k230, :push | :log, ...)`), and the
  backends' events must reach Elixos as the simulated backends' do. What
  this cannot show: anything the hardware does (docs/notes/coproc-firmware.md,
  "Board drivers").
  """
  use ExUnit.Case, async: false

  alias Elixos.Coproc
  alias Elixos.Coproc.{Console, LoRa, Power, Touch}
  alias Elixos.Test.AtomVM

  @moduletag milestone: 33
  @moduletag :tmp_dir

  @drivers "sim,touch=k230,lora=k230,power=k230,console=k230"

  # The firmware's NIFs as the backends see them. touch_open/0 and the
  # LoRa frequency come from the environment, since the drivers start
  # before the test can reach the coprocessor.
  @fake ~S"""
  -module(coproc_k230).
  -export([touch_open/0, touch_read/0, lora_open/1, lora_send/1, lora_poll/0,
           power_open/0, power_poll/0, power_off/0, console_read/0, console_write/1,
           push/2, log/1]).

  touch_open() ->
      case os:getenv("ELIXOS_TEST_TOUCH_OPEN") of
          false -> ok;
          Reason -> {error, list_to_atom(Reason)}
      end.
  touch_read() -> take(touch, []).
  lora_open(Hz) -> record(lora_open, Hz), ok.
  lora_send(Packet) -> record(lora_send, Packet), take(lora_send, ok).
  lora_poll() -> take(lora, none).
  power_open() -> ok.
  power_poll() -> take(power, none).
  power_off() -> record(power_off, true), {error, still_on}.
  console_read() -> take(console, <<>>).
  console_write(Bytes) -> record(console_write, Bytes), ok.

  push(Queue, Item) -> call({push, Queue, Item}).
  log(Key) -> call({log, Key}).

  take(Queue, Default) -> call({take, Queue, Default}).
  record(Key, Item) -> call({record, Key, Item}).

  call(Request) ->
      Ref = make_ref(),
      server() ! {Request, self(), Ref},
      receive {Ref, Reply} -> Reply after 5000 -> erlang:error(timeout) end.

  server() ->
      case whereis(coproc_k230_fake) of
          undefined ->
              Pid = spawn(fun() -> loop(#{}) end),
              try register(coproc_k230_fake, Pid) of
                  true -> Pid
              catch
                  error:badarg -> exit(Pid, kill), server()
              end;
          Pid ->
              Pid
      end.

  loop(State) ->
      receive
          {{take, Queue, Default}, From, Ref} ->
              case maps:get({queue, Queue}, State, []) of
                  [Item | Rest] ->
                      From ! {Ref, Item},
                      loop(State#{{queue, Queue} => Rest});
                  [] ->
                      From ! {Ref, Default},
                      loop(State)
              end;
          {{push, Queue, Item}, From, Ref} ->
              From ! {Ref, ok},
              loop(State#{{queue, Queue} => maps:get({queue, Queue}, State, []) ++ [Item]});
          {{record, Key, Item}, From, Ref} ->
              From ! {Ref, ok},
              loop(State#{{log, Key} => maps:get({log, Key}, State, []) ++ [Item]});
          {{log, Key}, From, Ref} ->
              From ! {Ref, maps:get({log, Key}, State, [])},
              loop(State)
      end.
  """

  setup ctx do
    %{cookie: :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower), bundle: fake(ctx.tmp_dir)}
  end

  test "the board backends report the firmware's events and drive its devices", ctx do
    vm = start!(ctx, [{"ELIXOS_COPROC_LORA_FREQUENCY", "868000000"}])

    for subsystem <- [:touch, :lora, :power, :console] do
      assert %{backend: backend} = Coproc.driver_call(:coproc_driver, :info, [:"coproc_#{subsystem}"])
      assert backend == :"coproc_#{subsystem}_k230"
    end

    # The display stays as the set says.
    assert %{backend: :coproc_display_sim} = Coproc.driver_call(:coproc_driver, :info, [:coproc_display])

    # Touch: each report the firmware decoded is an event; off-panel ones
    # are dropped. Hardware takes no stimuli.
    assert Touch.subscribe() == :ok
    push(:touch, [{:down, 10, 20}])
    push(:touch, [{:move, 11, 21}, {:down, 568, 0}])
    push(:touch, [{:up, 11, 21}])
    assert_receive {:touch, :down, 10, 20}, 5_000
    assert_receive {:touch, :move, 11, 21}, 5_000
    assert_receive {:touch, :up, 11, 21}, 5_000
    assert Coproc.simulate(:touch, {:down, 1, 1}) == {:error, :badarg}
    assert eventually(fn -> match?(%{touch: :ok, touches: 3, errors: 0}, Touch.info()) end)

    # LoRa: opened on the configured frequency; a packet with its RSSI and
    # SNR (quarter dB from the firmware); sends go to the radio.
    assert Coproc.call(:coproc_k230, :log, [:lora_open]) == {:ok, [868_000_000]}
    assert LoRa.subscribe() == :ok
    push(:lora, {:packet, "from the air", -41, 29})
    assert_receive {:lora, "from the air", %{rssi: -41, snr: 7.25}}, 5_000
    assert LoRa.send("ping") == :ok
    push(:lora_send, {:error, :busy})
    assert LoRa.send("pong") == {:error, :busy}
    assert LoRa.send(:binary.copy("x", 256)) == {:error, :badarg}
    assert Coproc.call(:coproc_k230, :log, [:lora_send]) == {:ok, ["ping", "pong"]}
    push(:lora, :sent)
    push(:lora, :crc_error)
    assert eventually(fn -> match?(%{lora: :ok, frequency: 868_000_000, sent: 1, received: 1, crc_errors: 1}, LoRa.info()) end)

    # The power key, and a power-off the firmware could not complete.
    assert Power.subscribe() == :ok
    push(:power, :pressed)
    push(:power, :released)
    assert_receive {:power_key, :pressed}, 5_000
    assert_receive {:power_key, :released}, 5_000
    assert Power.poweroff() == :ok
    assert Coproc.call(:coproc_k230, :log, [:power_off]) == {:ok, [true]}
    assert %{poweroff: {:error, :still_on}, presses: 1} = Power.info()

    # UART3: lines out with a line end; typed bytes become lines, across
    # reads, either line end, no empty ones.
    assert Console.subscribe() == :ok
    assert Console.write("hello from Elixos") == :ok
    assert Coproc.call(:coproc_k230, :log, [:console_write]) == {:ok, ["hello from Elixos\n"]}
    push(:console, "he")
    push(:console, "lp\r\nwor")
    push(:console, "ld\n\n")
    assert_receive {:console, "help"}, 5_000
    assert_receive {:console, "world"}, 5_000
    assert eventually(fn -> match?(%{lines: 1, typed: 2}, Console.info()) end)

    refute_received _
    assert AtomVM.starts(vm) == 1
  end

  test "a device the firmware cannot open leaves its backend idle", ctx do
    start!(ctx, [{"ELIXOS_TEST_TOUCH_OPEN", "no_answer"}, {"ELIXOS_COPROC_LORA_FREQUENCY", "915 MHz"}])

    assert %{touch: {:error, :no_answer}, touches: 0} = Touch.info()
    assert %{lora: {:error, {:bad_frequency, ~c"915 MHz"}}} = LoRa.info()
    assert Coproc.call(:coproc_k230, :log, [:lora_open]) == {:ok, []}
    assert LoRa.send("ping") == {:error, :not_open}
  end

  ## Helpers

  defp fake(dir) do
    path = Path.join(dir, "coproc_k230.erl")
    File.write!(path, @fake)
    {:ok, :coproc_k230, beam} = :compile.file(String.to_charlist(path), [:binary, :return_errors])
    {:ok, bundle} = Coproc.Bundle.pack([{:coproc_k230, beam}])
    bundle
  end

  defp start!(ctx, env) do
    vm =
      AtomVM.start(Path.join(ctx.tmp_dir, "atomvm"),
        cookie: ctx.cookie,
        bundle: ctx.bundle,
        drivers: @drivers,
        env: env
      )

    AtomVM.await_up(vm)

    start_supervised!(
      {Coproc,
       [
         node: vm.node,
         port: vm.port,
         listen: {{127, 0, 0, 1}, AtomVM.free_port()},
         cookie: ctx.cookie,
         reconnect_ms: 200
       ]}
    )

    assert eventually(fn -> Coproc.status().connected end)
    vm
  end

  defp push(queue, item) do
    assert Coproc.call(:coproc_k230, :push, [queue, item]) == {:ok, :ok}
  end

  defp eventually(fun, deadline \\ System.monotonic_time(:millisecond) + 15_000) do
    cond do
      fun.() -> true
      System.monotonic_time(:millisecond) > deadline -> false
      true -> Process.sleep(50) && eventually(fun, deadline)
    end
  end
end
