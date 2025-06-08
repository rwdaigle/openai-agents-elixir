defmodule OpenAI.Agents.Tracing.ConsoleExporter do
  @moduledoc """
  Console exporter for debugging tracing functionality.

  Based on the Python OpenAI agents library ConsoleSpanExporter implementation.
  """

  @behaviour OpenAI.Agents.Tracing.Exporter

  require Logger

  @impl true
  def export(items) do
    Logger.info("=== OpenAI Agents Tracing Export ===")

    Enum.each(items, fn item ->
      case item do
        %OpenAI.Agents.Tracing.Trace{} = trace ->
          export_trace(trace)

        %OpenAI.Agents.Tracing.Span{} = span ->
          export_span(span)

        _ ->
          Logger.info("Unknown trace item: #{inspect(item)}")
      end
    end)

    Logger.info("=== End Tracing Export ===")
    :ok
  end

  defp export_trace(trace) do
    Logger.info("[Exporter] Export trace_id=#{trace.id}, name=#{trace.agent_module}")

    if trace.spans && length(trace.spans) > 0 do
      Enum.each(trace.spans, &export_span/1)
    end
  end

  defp export_span(span) do
    duration =
      if span.ended_at do
        DateTime.diff(span.ended_at, span.started_at, :millisecond)
      else
        "ongoing"
      end

    Logger.info("[Exporter] Export span: #{span.type} (#{duration}ms) - #{inspect(span.data)}")
  end
end
