defmodule Elixos.Agents.LLM do
  @moduledoc """
  The LLM is a provider, not the definition (M15): an agent without one still
  works, and an action that wants a model calls `complete/2`.

  Nothing sits between the two: the client is OTP's own (`:gen_tcp`, `:ssl`
  where the machine has it, `:json`), and the wire format is the one every
  provider speaks. Providers are configuration, read from `/priv/llm.exs` (a
  keyword list, like the hex repositories) or given per call:

      [
        stub: [base_url: "http://127.0.0.1:4040/v1", model: "test-model"],
        openai: [base_url: "https://api.openai.com/v1", model: "gpt-5", api_key: "sk-..."],
        codex: [model: "gpt-5.6-luna"]
      ]

  Three shapes of authentication, in `:auth`:

    * `:none` - a local stub, or anything with no credentials (the default)
    * `:api_key` - `Authorization: Bearer <api_key>`, OpenAI's chat
      completions at `<base_url>/chat/completions`
    * `:codex` - the ChatGPT subscription sign-in the Codex CLI keeps in
      `~/.codex/auth.json`: the OAuth access token and the account id go to
      the Responses API at `<base_url>/responses`, and the token is refreshed
      with the refresh token when its own `exp` says it is time (the file is
      rewritten, the way the CLI does). `:codex` therefore works with a
      ChatGPT plan and no API key.

  Both response shapes are read: chat completions
  (`choices[0].message.content`) and responses (`output[].content[].text`),
  including the server-sent-events framing a streaming response arrives in.
  """

  require Logger

  @default_base_url "https://api.openai.com/v1"
  @codex_base_url "https://chatgpt.com/backend-api/codex"
  @auth_url "https://auth.openai.com/oauth/token"
  # OpenAI's own public client id, the one the Codex CLI signs in with.
  @codex_client_id "app_EMoamEEZ73f0CkXaXp7hrann"

  @type message :: %{required(String.t()) => String.t()} | {String.t(), String.t()}

  @doc """
  One completion. `messages` is the chat history (`%{role: ..., content: ...}`
  or `{role, content}` pairs); options override the provider's configuration.
  """
  @spec complete([message()], keyword()) :: {:ok, String.t()} | {:error, term()}
  def complete(messages, opts \\ []) do
    with {:ok, provider} <- provider(opts),
         {:ok, body} <- request_body(messages, provider),
         {:ok, status, response} <- request(provider, body),
         {:ok, text} <- parse(status, response) do
      {:ok, text}
    end
  end

  @doc "Every configured provider, from `/priv/llm.exs`."
  @spec providers() :: [{atom(), keyword()}]
  def providers do
    file = llm_file()

    case File.regular?(file) do
      true ->
        case Code.eval_file(file) do
          {list, _binding} when is_list(list) -> list
          _other -> []
        end

      false ->
        []
    end
  rescue
    error ->
      Logger.error("llm: #{llm_file()} is unreadable (#{Exception.message(error)}); no provider")
      []
  end

  ## Configuration

  defp provider(opts) do
    configured = opts |> Keyword.get(:provider) |> configured()
    provider = Keyword.merge(configured, Keyword.drop(opts, [:provider]))

    if provider[:base_url] || provider[:model] do
      {:ok, provider}
    else
      {:error, :no_provider}
    end
  end

  defp configured(nil), do: []
  defp configured(name), do: Keyword.get(providers(), name, [])

  ## The request

  # `:codex` speaks the Responses API, everything else chat completions - the
  # format both OpenAI-compatible servers and a test stub answer.
  defp request_body(messages, provider) do
    model = provider[:model] || "gpt-4o-mini"

    if provider[:auth] == :codex do
      {:ok,
       %{
         "model" => model,
         "input" => Enum.map(messages, &responses_message/1),
         # The ChatGPT backend always streams (verified: stream false is a
         # 400), so the response is server-sent events - read below.
         "stream" => true,
         "store" => false
       }}
    else
      {:ok, %{"model" => model, "messages" => Enum.map(messages, &chat_message/1)}}
    end
  end

  defp chat_message({role, content}), do: %{"role" => to_string(role), "content" => content}

  defp chat_message(%{role: role, content: content}),
    do: %{"role" => to_string(role), "content" => content}

  defp responses_message(message) do
    {role, content} =
      case message do
        {role, content} -> {to_string(role), content}
        %{role: role, content: content} -> {to_string(role), content}
      end

    %{"role" => role, "content" => [%{"type" => "input_text", "text" => content}]}
  end

  defp request(provider, body) do
    url = String.trim_trailing(provider[:base_url] || default_base_url(provider), "/")

    path =
      provider[:path] ||
        if(provider[:auth] == :codex, do: "/responses", else: "/chat/completions")

    payload = :json.encode(body)

    with {:ok, headers} <- headers(provider) do
      http(url <> path, headers, IO.iodata_to_binary(payload))
    end
  end

  # Providers are keyword lists (from the file or the call), so these match on
  # the value of :auth rather than on a map pattern.
  defp default_base_url(provider) do
    if provider[:auth] == :codex, do: @codex_base_url, else: @default_base_url
  end

  defp headers(provider) do
    cond do
      provider[:auth] == :codex -> codex_headers(provider)
      provider[:api_key] -> {:ok, [{"authorization", "Bearer #{provider[:api_key]}"}]}
      true -> {:ok, []}
    end
  end

  defp codex_headers(provider) do
    with {:ok, auth} <- codex_auth(provider) do
      {:ok,
       [
         {"authorization", "Bearer #{auth.access_token}"},
         {"chatgpt-account-id", auth.account_id},
         {"openai-beta", "responses=experimental"},
         {"originator", "elixos"},
         {"session_id", session_id()},
         {"user-agent", "elixos (Elixos.Agents.LLM)"}
       ]}
    end
  end

  defp session_id do
    <<a::4-binary, b::2-binary, c::2-binary, d::2-binary, e::6-binary>> =
      :crypto.strong_rand_bytes(16)

    Enum.join([hex(a), hex(b), hex(c), hex(d), hex(e)], "-")
  end

  defp hex(binary), do: Base.encode16(binary, case: :lower)

  ## HTTP, over OTP's own sockets

  defp http(url, headers, body) do
    uri = URI.parse(url)

    with :ok <- supported_scheme(uri),
         {:ok, socket, transport} <- connect(uri),
         :ok <- send_request(socket, transport, uri, headers, body),
         {:ok, status, response_headers, body} <- read_response(socket, transport, "") do
      {:ok, status, dechunk(response_headers, body)}
    end
  end

  # A hosted provider answers chunked as often as not: the frames are
  # hex-length lines and the body is their concatenation.
  defp dechunk(headers, body) do
    if Map.get(headers, "transfer-encoding", "") =~ "chunked", do: unchunk(body, []), else: body
  end

  defp unchunk(<<>>, acc), do: IO.iodata_to_binary(Enum.reverse(acc))

  defp unchunk(binary, acc) do
    case :binary.split(binary, "\r\n") do
      [size_line, rest] ->
        case Integer.parse(String.trim(size_line), 16) do
          {0, _} ->
            IO.iodata_to_binary(Enum.reverse(acc))

          {size, _} ->
            case rest do
              <<chunk::binary-size(^size), "\r\n", tail::binary>> -> unchunk(tail, [chunk | acc])
              _other -> IO.iodata_to_binary(Enum.reverse([binary | acc]))
            end

          :error ->
            IO.iodata_to_binary(Enum.reverse([binary | acc]))
        end

      [_single] ->
        IO.iodata_to_binary(Enum.reverse(acc))
    end
  end

  defp supported_scheme(%URI{scheme: "http"}), do: :ok

  defp supported_scheme(%URI{scheme: "https"}) do
    # The image ships no TLS today (M15 scope): a local provider works, a
    # hosted one waits for :ssl in the factory. Where it exists it has to be
    # running, and a hosted provider needs the machine's CA store.
    with true <- Code.ensure_loaded?(:ssl),
         {:ok, _apps} <- Application.ensure_all_started(:ssl),
         {:ok, _certs} <- cacerts() do
      :ok
    else
      _other -> {:error, :no_tls}
    end
  end

  defp supported_scheme(_uri), do: {:error, :bad_url}

  # `:public_key.cacerts_get/0` reads the OS trust store; a machine without
  # one cannot verify a hosted provider, and that is the honest answer.
  defp cacerts do
    case :public_key.cacerts_get() do
      certs when is_list(certs) and certs != [] -> {:ok, certs}
      _other -> {:error, :no_cacerts}
    end
  rescue
    _error -> {:error, :no_cacerts}
  end

  defp connect(%URI{scheme: "http", host: host, port: port}) do
    case :gen_tcp.connect(String.to_charlist(host), port || 80, [:binary, active: false], 5_000) do
      {:ok, socket} -> {:ok, socket, :gen_tcp}
      {:error, reason} -> {:error, {:connect, reason}}
    end
  end

  defp connect(%URI{scheme: "https", host: host, port: port}) do
    with {:ok, certs} <- cacerts() do
      options = [:binary, active: false, verify: :verify_peer, cacerts: certs, depth: 3]
      # apply/3: the compiler does not need :ssl on its path to call it, and
      # the image's ERTS may not carry it at all (the caller checked).
      case apply(:ssl, :connect, [String.to_charlist(host), port || 443, options, 10_000]) do
        {:ok, socket} -> {:ok, socket, :ssl}
        {:error, reason} -> {:error, {:connect, reason}}
      end
    end
  end

  defp send_request(socket, transport, uri, headers, body) do
    path = (uri.path || "/") <> if(uri.query, do: "?" <> uri.query, else: "")

    request = [
      "POST ",
      path,
      " HTTP/1.1\r\n",
      "host: ",
      uri.host,
      "\r\n",
      "content-type: application/json\r\n",
      "content-length: ",
      Integer.to_string(byte_size(body)),
      "\r\n",
      "connection: close\r\n",
      "accept: application/json\r\n",
      Enum.map(headers, fn {name, value} -> [name, ": ", value, "\r\n"] end),
      "\r\n",
      body
    ]

    transport.send(socket, request)
  end

  defp read_response(socket, transport, acc) do
    case transport.recv(socket, 0, 60_000) do
      {:ok, data} -> read_response(socket, transport, acc <> data)
      {:error, :closed} -> split_response(acc)
      {:error, reason} -> {:error, {:read, reason}}
    end
  end

  defp split_response(response) do
    case String.split(response, "\r\n\r\n", parts: 2) do
      [head, body] ->
        [status_line | header_lines] = String.split(head, "\r\n")

        with [_, code | _] <- String.split(status_line, " "),
             headers = Map.new(header_lines, &parse_header/1) do
          {:ok, String.to_integer(code), headers, body}
        else
          _other -> {:error, {:bad_response, head}}
        end

      _other ->
        {:error, {:bad_response, response}}
    end
  end

  defp parse_header(line) do
    case String.split(line, ":", parts: 2) do
      [name, value] -> {String.downcase(String.trim(name)), String.trim(value)}
      [_single] -> {"", ""}
    end
  end

  ## The response

  defp parse(status, body) when status in 200..299 do
    decoded = decode_body(body)

    case text_of(decoded) do
      nil -> {:error, {:no_text, decoded}}
      text -> {:ok, text}
    end
  end

  defp parse(status, body), do: {:error, {:http, status, body}}

  # A streaming response arrives as `data: {...}` lines even with stream:
  # false on some backends; the last JSON that carries text wins.
  defp decode_body(body) do
    if String.contains?(body, "data:") do
      body
      |> String.split("\n")
      |> Enum.filter(&String.starts_with?(&1, "data:"))
      |> Enum.map(&(&1 |> String.replace_prefix("data:", "") |> String.trim()))
      |> Enum.reject(&(&1 == "[DONE]"))
      |> Enum.map(&safe_decode/1)
      |> Enum.reject(&is_nil/1)
      |> List.last()
    else
      safe_decode(body)
    end
  end

  defp safe_decode(json) do
    :json.decode(json)
  rescue
    _error -> nil
  end

  # Chat completions and the Responses API, from the same map.
  defp text_of(%{"choices" => [%{"message" => %{"content" => content}} | _]})
       when is_binary(content),
       do: content

  defp text_of(%{"output_text" => text}) when is_binary(text), do: text

  defp text_of(%{"output" => output}) when is_list(output) do
    output
    |> Enum.flat_map(fn
      %{"content" => content} when is_list(content) -> content
      _other -> []
    end)
    |> Enum.find_value(fn
      %{"text" => text} when is_binary(text) -> text
      _other -> nil
    end)
  end

  # A wrapped event (streaming): the payload is the same map one level down.
  defp text_of(%{"response" => response}) when is_map(response), do: text_of(response)
  defp text_of(_other), do: nil

  ## The Codex sign-in

  # ~/.codex/auth.json, as the CLI keeps it: the ChatGPT tokens of a
  # subscription sign-in. Read, refreshed when the access token's own exp says
  # so, and written back the way the CLI writes it.
  defp codex_auth(provider) do
    path = provider[:auth_path] || default_auth_path()

    case path |> File.read!() |> :json.decode() do
      %{"tokens" => %{"access_token" => access, "account_id" => account} = tokens} ->
        if expires_soon?(access) do
          refresh(provider, path, tokens)
        else
          {:ok, %{access_token: access, account_id: account}}
        end

      _other ->
        {:error, :no_codex_tokens}
    end
  rescue
    error -> {:error, {:codex_auth, Exception.message(error)}}
  end

  defp default_auth_path do
    case System.user_home() do
      nil -> "/.codex/auth.json"
      home -> Path.join(home, ".codex/auth.json")
    end
  end

  # The access token is a JWT; its exp is all we need (verifying it is the
  # provider's business).
  defp expires_soon?(jwt) do
    with [_header, payload | _] <- String.split(jwt, "."),
         {:ok, json} <- Base.url_decode64(payload, padding: false),
         decoded when is_map(decoded) <- :json.decode(json) do
      exp = decoded["exp"] || 0
      exp - 60 < System.os_time(:second)
    else
      _other -> true
    end
  rescue
    _error -> true
  end

  defp refresh(provider, path, tokens) do
    form =
      URI.encode_query(%{
        "grant_type" => "refresh_token",
        "refresh_token" => tokens["refresh_token"],
        "client_id" => @codex_client_id
      })

    with {:ok, status, body} <-
           http(
             provider[:auth_url] || @auth_url,
             [{"content-type", "application/x-www-form-urlencoded"}],
             form
           ),
         true <- status in 200..299 do
      fresh = :json.decode(body)
      tokens = Map.merge(tokens, Map.take(fresh, ["access_token", "refresh_token", "id_token"]))
      _ = write_auth(path, tokens)
      {:ok, %{access_token: tokens["access_token"], account_id: tokens["account_id"]}}
    else
      false -> {:error, :refresh_failed}
      {:error, reason} -> {:error, {:refresh_failed, reason}}
    end
  end

  defp write_auth(path, tokens) do
    auth = %{
      "tokens" => tokens,
      "last_refresh" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    tmp = path <> ".tmp"

    with :ok <- File.write(tmp, :json.encode(auth)),
         :ok <- File.rename(tmp, path) do
      :ok
    end
  end

  defp llm_file, do: Application.get_env(:elixos, :llm_file, Path.join(priv(), "llm.exs"))
  defp priv, do: Application.get_env(:elixos, :priv_dir, "/priv")
end
