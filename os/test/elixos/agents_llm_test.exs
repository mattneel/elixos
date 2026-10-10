defmodule Elixos.Agents.LLMTest do
  @moduledoc """
  The provider client (M15), against a stub over the loopback: the two wire
  shapes, the three authentication modes, and the Codex sign-in - the ChatGPT
  subscription the CLI keeps in auth.json, refreshed when the token's own exp
  says so. The stub is the same thing the M15 QEMU acceptance points an
  agent's action at.
  """
  use ExUnit.Case, async: false

  @moduletag milestone: 15
  @moduletag :tmp_dir

  alias Elixos.Agents.LLM

  defmodule Stub do
    @moduledoc false

    # A one-request-at-a-time HTTP server: the handler gets the request and
    # returns {status, body}. Nothing is chunked; everything is JSON.
    def start(handler) do
      {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true])
      {:ok, port} = :inet.port(listen)
      spawn_link(fn -> loop(listen, handler) end)
      port
    end

    defp loop(listen, handler) do
      case :gen_tcp.accept(listen) do
        {:ok, socket} ->
          request = read_request(socket, "")
          {status, body} = handler.(request)

          :gen_tcp.send(socket, [
            "HTTP/1.1 ",
            Integer.to_string(status),
            " OK\r\ncontent-type: application/json\r\ncontent-length: ",
            Integer.to_string(byte_size(body)),
            "\r\nconnection: close\r\n\r\n",
            body
          ])

          :gen_tcp.close(socket)
          loop(listen, handler)

        {:error, _reason} ->
          :ok
      end
    end

    defp read_request(socket, acc) do
      case :gen_tcp.recv(socket, 0, 5_000) do
        {:ok, data} ->
          acc = acc <> data

          case complete_request(acc) do
            {:ok, request} -> request
            :more -> read_request(socket, acc)
          end

        {:error, _reason} ->
          case complete_request(acc) do
            {:ok, request} -> request
            :more -> %{headers: %{}, body: nil, path: nil}
          end
      end
    end

    defp complete_request(acc) do
      case String.split(acc, "\r\n\r\n", parts: 2) do
        [head, body] ->
          [request_line | header_lines] = String.split(head, "\r\n")
          [method, path | _] = String.split(request_line, " ")
          headers = Map.new(header_lines, &parse_header/1)
          length = String.to_integer(headers["content-length"] || "0")

          if byte_size(body) >= length do
            {:ok,
             %{
               method: method,
               path: path,
               headers: headers,
               body: decode_body(headers, binary_part(body, 0, length))
             }}
          else
            :more
          end

        _other ->
          :more
      end
    end

    defp decode_body(%{"content-type" => "application/json" <> _}, body), do: :json.decode(body)
    defp decode_body(_headers, _body), do: nil

    defp parse_header(line) do
      [name, value] = String.split(line, ":", parts: 2)
      {String.downcase(name), String.trim(value)}
    end
  end

  defp chat_response(text) do
    %{"choices" => [%{"message" => %{"role" => "assistant", "content" => text}}]}
    |> :json.encode()
    |> IO.iodata_to_binary()
  end

  defp responses_response(text) do
    %{
      "output" => [
        %{"type" => "message", "content" => [%{"type" => "output_text", "text" => text}]}
      ]
    }
    |> :json.encode()
    |> IO.iodata_to_binary()
  end

  defp jwt(exp) do
    payload =
      Base.url_encode64(IO.iodata_to_binary(:json.encode(%{"exp" => exp})), padding: false)

    "eyJhbGciOiJub25lIn0." <> payload <> ".sig"
  end

  test "chat completions, with a key: the path, the model, the bearer, the text" do
    me = self()

    port =
      Stub.start(fn request ->
        send(me, {:request, request})
        {200, chat_response("hi there")}
      end)

    provider = [base_url: "http://127.0.0.1:#{port}/v1", model: "stub-model", api_key: "sk-test"]

    assert {:ok, "hi there"} = LLM.complete([{"user", "hello"}], provider)

    assert_receive {:request, request}
    assert request.path == "/v1/chat/completions"
    assert request.headers["authorization"] == "Bearer sk-test"
    assert request.body["model"] == "stub-model"
    assert request.body["messages"] == [%{"role" => "user", "content" => "hello"}]
  end

  test "the responses shape is read the same way" do
    port = Stub.start(fn _request -> {200, responses_response("from responses")} end)

    provider = [base_url: "http://127.0.0.1:#{port}/v1", model: "stub-model", path: "/responses"]

    assert {:ok, "from responses"} = LLM.complete([%{role: "user", content: "hello"}], provider)
  end

  test "server-sent events: the last payload that carries text wins" do
    stream =
      "data: " <>
        IO.iodata_to_binary(:json.encode(%{"type" => "response.created"})) <>
        "\n\n" <>
        "data: " <>
        IO.iodata_to_binary(
          :json.encode(%{
            "response" => %{"output" => [%{"content" => [%{"text" => "streamed"}]}]}
          })
        ) <>
        "\n\ndata: [DONE]\n\n"

    port = Stub.start(fn _request -> {200, stream} end)

    provider = [base_url: "http://127.0.0.1:#{port}/v1", model: "stub-model", path: "/responses"]
    assert {:ok, "streamed"} = LLM.complete([{"user", "hello"}], provider)
  end

  test "the Codex sign-in: account id, bearer, and the Responses path", %{tmp_dir: tmp_dir} do
    auth_path = Path.join(tmp_dir, "auth.json")
    future = jwt(System.os_time(:second) + 3_600)

    File.write!(
      auth_path,
      :json.encode(%{
        "tokens" => %{
          "access_token" => future,
          "account_id" => "acct_123",
          "refresh_token" => "r1"
        }
      })
    )

    me = self()

    port =
      Stub.start(fn request ->
        send(me, {:request, request})
        {200, responses_response("codex says hi")}
      end)

    provider = [
      base_url: "http://127.0.0.1:#{port}/backend-api/codex",
      auth: :codex,
      auth_path: auth_path,
      model: "gpt-5.6-luna"
    ]

    assert {:ok, "codex says hi"} = LLM.complete([{"user", "hello"}], provider)

    assert_receive {:request, request}
    assert request.path == "/backend-api/codex/responses"
    assert request.headers["authorization"] == "Bearer " <> future
    assert request.headers["chatgpt-account-id"] == "acct_123"
    assert request.body["stream"] == true
    assert request.body["model"] == "gpt-5.6-luna"
  end

  test "an expired Codex token is refreshed and written back", %{tmp_dir: tmp_dir} do
    auth_path = Path.join(tmp_dir, "auth.json")
    expired = jwt(System.os_time(:second) - 60)

    File.write!(
      auth_path,
      :json.encode(%{
        "tokens" => %{
          "access_token" => expired,
          "account_id" => "acct_123",
          "refresh_token" => "r1"
        }
      })
    )

    me = self()

    port =
      Stub.start(fn request ->
        send(me, {:request, request})

        case request.path do
          "/token" ->
            {200,
             IO.iodata_to_binary(
               :json.encode(%{"access_token" => "fresh-token", "refresh_token" => "r2"})
             )}

          _other ->
            {200, responses_response("after refresh")}
        end
      end)

    provider = [
      base_url: "http://127.0.0.1:#{port}/backend-api/codex",
      auth: :codex,
      auth_path: auth_path,
      auth_url: "http://127.0.0.1:#{port}/token",
      model: "gpt-5.6-luna"
    ]

    assert {:ok, "after refresh"} = LLM.complete([{"user", "hello"}], provider)

    assert_receive {:request, refresh}
    assert refresh.path == "/token"
    assert refresh.headers["content-type"] == "application/x-www-form-urlencoded"

    assert_receive {:request, chat}
    assert chat.headers["authorization"] == "Bearer fresh-token"

    written = auth_path |> File.read!() |> :json.decode()
    assert written["tokens"]["access_token"] == "fresh-token"
    assert written["tokens"]["refresh_token"] == "r2"
  end

  test "failures are errors, not crashes" do
    port = Stub.start(fn _request -> {500, ~s({"error":"boom"})} end)

    assert {:error, {:http, 500, _body}} =
             LLM.complete([{"user", "hi"}], base_url: "http://127.0.0.1:#{port}/v1", model: "m")

    assert {:error, :no_provider} = LLM.complete([{"user", "hi"}])

    assert {:error, {:connect, _reason}} =
             LLM.complete([{"user", "hi"}], base_url: "http://127.0.0.1:1/v1", model: "m")
  end
end
