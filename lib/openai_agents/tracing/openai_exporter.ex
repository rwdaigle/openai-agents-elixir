defmodule OpenAI.Agents.Tracing.OpenAIExporter do
  @moduledoc """
  Exports traces and spans to the undocumented OpenAI tracing API.

  Based on the Python OpenAI agents library BackendSpanExporter implementation.
  Uses the /v1/traces/ingest endpoint with "OpenAI-Beta: traces=v1" header.
  """

  @behaviour OpenAI.Agents.Tracing.Exporter

  require Logger

  @openai_traces_endpoint "https://api.openai.com/v1/traces/ingest"
  @timeout 30_000
  @max_retries 3
  @base_backoff_ms 1000

  @impl true
  def export(items) do
    config = get_config()

    if config.api_key do
      export_batch(items, config)
    else
      Logger.warning("OpenAI API key not configured, skipping trace export")
      :ok
    end
  end

  defp export_batch(items, config) do
    payload = build_payload(items)
    headers = build_headers(config)

    case send_with_retry(payload, headers, @max_retries) do
      {:ok, _response} ->
        Logger.debug("Successfully exported #{length(items)} trace items to OpenAI")
        :ok

      {:error, reason} ->
        Logger.error("Failed to export traces to OpenAI: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_payload(items) do
    exported_items =
      items
      |> Enum.map(&export_item/1)
      |> Enum.reject(&is_nil/1)

    %{
      "traces" => exported_items,
      "exported_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp export_item(%OpenAI.Agents.Tracing.Trace{} = trace) do
    OpenAI.Agents.Tracing.Trace.export(trace)
  end

  defp export_item(%OpenAI.Agents.Tracing.Span{} = span) do
    OpenAI.Agents.Tracing.Span.export(span)
  end

  defp export_item(_unknown), do: nil

  defp build_headers(config) do
    base_headers = [
      {"Authorization", "Bearer #{config.api_key}"},
      {"Content-Type", "application/json"},
      {"OpenAI-Beta", "traces=v1"},
      {"User-Agent", "openai-agents-elixir/#{get_version()}"}
    ]

    extra_headers = []

    extra_headers =
      if config.organization do
        [{"OpenAI-Organization", config.organization} | extra_headers]
      else
        extra_headers
      end

    extra_headers =
      if config.project do
        [{"OpenAI-Project", config.project} | extra_headers]
      else
        extra_headers
      end

    base_headers ++ extra_headers
  end

  defp send_with_retry(payload, headers, retries_left) do
    body = Jason.encode!(payload)

    case Finch.build(:post, @openai_traces_endpoint, headers, body)
         |> Finch.request(OpenAI.Agents.Finch, receive_timeout: @timeout) do
      {:ok, %{status: status}} when status in 200..299 ->
        {:ok, :success}

      {:ok, %{status: status, body: response_body}} when status in 400..499 ->
        Logger.error("OpenAI tracing API client error (#{status}): #{response_body}")
        {:error, {:client_error, status, response_body}}

      {:ok, %{status: status, body: response_body}} when status >= 500 ->
        if retries_left > 0 do
          backoff_ms = @base_backoff_ms * 2 ** (@max_retries - retries_left)

          Logger.warning(
            "OpenAI tracing API server error (#{status}), retrying in #{backoff_ms}ms"
          )

          Process.sleep(backoff_ms)
          send_with_retry(payload, headers, retries_left - 1)
        else
          Logger.error(
            "OpenAI tracing API server error (#{status}) after #{@max_retries} retries: #{response_body}"
          )

          {:error, {:server_error, status, response_body}}
        end

      {:error, error} ->
        if retries_left > 0 do
          backoff_ms = @base_backoff_ms * 2 ** (@max_retries - retries_left)

          Logger.warning(
            "Network error sending traces to OpenAI, retrying in #{backoff_ms}ms: #{inspect(error)}"
          )

          Process.sleep(backoff_ms)
          send_with_retry(payload, headers, retries_left - 1)
        else
          Logger.error(
            "Network error sending traces to OpenAI after #{@max_retries} retries: #{inspect(error)}"
          )

          {:error, {:network_error, error}}
        end
    end
  end

  defp get_config do
    %{
      api_key: System.get_env("OPENAI_API_KEY") || Application.get_env(:openai_agents, :api_key),
      organization:
        System.get_env("OPENAI_ORGANIZATION") ||
          Application.get_env(:openai_agents, :organization),
      project: System.get_env("OPENAI_PROJECT") || Application.get_env(:openai_agents, :project)
    }
  end

  defp get_version do
    case Application.spec(:openai_agents, :vsn) do
      nil -> "unknown"
      version -> to_string(version)
    end
  end
end
