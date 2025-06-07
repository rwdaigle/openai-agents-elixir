defmodule OpenAI.Agents.Tracing.Processor do
  @moduledoc """
  Behavior for tracing processors that handle trace and span lifecycle events.

  Based on the Python OpenAI agents library TracingProcessor interface.
  """

  @callback on_trace_start(trace :: OpenAI.Agents.Tracing.Trace.t()) :: :ok
  @callback on_trace_end(trace :: OpenAI.Agents.Tracing.Trace.t()) :: :ok
  @callback on_span_start(span :: OpenAI.Agents.Tracing.Span.t()) :: :ok
  @callback on_span_end(span :: OpenAI.Agents.Tracing.Span.t()) :: :ok

  @doc """
  Calls the on_trace_start callback for the given processor.
  """
  def on_trace_start(processor, trace) do
    if function_exported?(processor, :on_trace_start, 1) do
      processor.on_trace_start(trace)
    else
      :ok
    end
  end

  @doc """
  Calls the on_trace_end callback for the given processor.
  """
  def on_trace_end(processor, trace) do
    if function_exported?(processor, :on_trace_end, 1) do
      processor.on_trace_end(trace)
    else
      :ok
    end
  end

  @doc """
  Calls the on_span_start callback for the given processor.
  """
  def on_span_start(processor, span) do
    if function_exported?(processor, :on_span_start, 1) do
      processor.on_span_start(span)
    else
      :ok
    end
  end

  @doc """
  Calls the on_span_end callback for the given processor.
  """
  def on_span_end(processor, span) do
    if function_exported?(processor, :on_span_end, 1) do
      processor.on_span_end(span)
    else
      :ok
    end
  end
end
