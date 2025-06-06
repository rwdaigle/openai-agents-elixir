defmodule OpenAI.Agents.Models.ResponsesAdapter do
  @moduledoc """
  Adapter for the OpenAI Responses API.
  
  Handles communication with the /v1/responses endpoint, including
  both standard and streaming requests.
  """

  @behaviour OpenAI.Agents.Models.Adapter

  require Logger

  @base_url "https://api.openai.com/v1"
  @responses_path "/responses"
  @timeout 60_000

  @impl true
  def create_completion(request, config) do
    url = build_url(config)
    headers = build_headers(config)
    body = Jason.encode!(request)
    
    case Finch.build(:post, url, headers, body)
         |> Finch.request(OpenAI.Agents.Finch, receive_timeout: @timeout) do
      {:ok, %{status: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, decoded} -> {:ok, normalize_response(decoded)}
          {:error, error} -> {:error, {:json_decode_error, error}}
        end
        
      {:ok, %{status: status, body: body}} ->
        {:error, {:api_error, status, body}}
        
      {:error, error} ->
        {:error, {:network_error, error}}
    end
  end

  @impl true
  def create_stream(request, config) do
    url = build_url(config)
    headers = build_headers(config)
    body = Jason.encode!(Map.put(request, :stream, true))
    
    Stream.resource(
      fn -> start_streaming(url, headers, body) end,
      &stream_next/1,
      &cleanup_stream/1
    )
  end

  defp build_url(config) do
    base = config[:base_url] || @base_url
    "#{base}#{@responses_path}"
  end

  defp build_headers(config) do
    [
      {"Authorization", "Bearer #{config.api_key}"},
      {"Content-Type", "application/json"},
      {"Accept", "text/event-stream"}
    ] ++ build_extra_headers(config)
  end

  defp build_extra_headers(config) do
    extra = config[:extra_headers] || %{}
    
    Enum.map(extra, fn {k, v} -> {to_string(k), to_string(v)} end)
  end

  defp normalize_response(response) do
    %{
      output: response["output"] || [],
      usage: response["usage"] || %{},
      response_id: response["response_id"],
      created: response["created"],
      model: response["model"]
    }
  end

  defp start_streaming(url, headers, body) do
    ref = Finch.build(:post, url, headers, body)
          |> Finch.stream_while(
            OpenAI.Agents.Finch,
            nil,
            fn
              {:status, status}, acc when status == 200 -> {:cont, acc}
              {:status, status}, _acc -> {:halt, {:error, status}}
              {:headers, _headers}, acc -> {:cont, acc}
              {:data, data}, _acc -> {:cont, {:data, data}}
            end
          )
    
    {ref, ""}
  end

  defp stream_next({:error, _} = error) do
    {:halt, error}
  end

  defp stream_next({ref, buffer}) do
    receive do
      {:data, chunk} ->
        {events, new_buffer} = parse_sse_chunk(buffer <> chunk)
        
        case events do
          [] -> stream_next({ref, new_buffer})
          _ -> {events, {ref, new_buffer}}
        end
        
      {:done, _ref} ->
        {:halt, {ref, buffer}}
        
    after
      @timeout ->
        {:halt, {:error, :timeout}}
    end
  end

  defp cleanup_stream({_ref, _buffer}) do
    # Ensure the stream is properly closed
    :ok
  end

  defp parse_sse_chunk(chunk) do
    lines = String.split(chunk, "\n")
    
    {events, remaining} = parse_lines(lines, [], "")
    
    {Enum.reverse(events), remaining}
  end

  defp parse_lines([], events, buffer), do: {events, buffer}
  
  defp parse_lines([line | rest], events, buffer) do
    cond do
      # Empty line marks end of event
      line == "" and buffer != "" ->
        case parse_event(buffer) do
          {:ok, event} -> parse_lines(rest, [event | events], "")
          {:error, _} -> parse_lines(rest, events, "")
        end
        
      # Data line
      String.starts_with?(line, "data: ") ->
        data = String.trim_leading(line, "data: ")
        parse_lines(rest, events, buffer <> data)
        
      # Skip other SSE fields for now
      true ->
        parse_lines(rest, events, buffer)
    end
  end

  defp parse_event("[DONE]"), do: {:ok, %{type: "done"}}
  
  defp parse_event(data) do
    case Jason.decode(data) do
      {:ok, decoded} -> {:ok, normalize_stream_event(decoded)}
      error -> error
    end
  end

  defp normalize_stream_event(event) do
    %{
      type: event["type"],
      data: event["data"],
      created: event["created"]
    }
  end
end

defmodule OpenAI.Agents.Models.Adapter do
  @moduledoc """
  Behavior for model adapters.
  """

  @callback create_completion(request :: map(), config :: map()) ::
              {:ok, map()} | {:error, term()}

  @callback create_stream(request :: map(), config :: map()) ::
              Enumerable.t()
end