defmodule OpenAI.Agents.Tracing do
  @moduledoc """
  OpenAI-compatible tracing for agent interactions.

  Based on the Python OpenAI agents library tracing implementation,
  this module provides comprehensive tracing capabilities including:

  - Conversation-level trace management with group_id support
  - Multiple span types (agent, function, generation, response, handoff, etc.)
  - OpenAI API integration via undocumented /v1/traces/ingest endpoint
  - Batch processing with background export
  - Context management for multi-turn conversations
  """

  use GenServer
  require Logger

  alias OpenAI.Agents.Tracing.{Span, Trace, Processor, Exporter}

  @global_trace_provider __MODULE__

  # Configuration
  @default_config %{
    enabled: true,
    processors: [],
    exporters: [],
    batch_size: 100,
    batch_timeout: 5000
  }

  ## Public API

  @doc """
  Starts the global trace provider.
  """
  def start_link(opts \\ []) do
    config = Keyword.get(opts, :config, @default_config)
    GenServer.start_link(__MODULE__, config, name: @global_trace_provider)
  end

  @doc """
  Starts a new conversation trace with optional group_id for linking multi-turn conversations.
  """
  def start_conversation_trace(agent_module, _input, opts \\ []) do
    if tracing_enabled?() and Process.whereis(@global_trace_provider) do
      trace_id = Keyword.get(opts, :trace_id, generate_trace_id())
      group_id = Keyword.get(opts, :group_id, generate_group_id())

      trace = %Trace{
        id: trace_id,
        group_id: group_id,
        agent_module: agent_module,
        started_at: DateTime.utc_now(),
        spans: [],
        context: Keyword.get(opts, :context, %{})
      }

      GenServer.call(@global_trace_provider, {:start_trace, trace})

      trace_id
    else
      nil
    end
  end

  @doc """
  Records a span within the current trace context.
  """
  def record_span(span_type, span_data, opts \\ []) do
    if tracing_enabled?() and Process.whereis(@global_trace_provider) do
      trace_id = Keyword.get(opts, :trace_id)

      if trace_id do
        span = %Span{
          id: generate_span_id(),
          trace_id: trace_id,
          type: span_type,
          data: span_data,
          started_at: DateTime.utc_now(),
          ended_at: nil
        }

        GenServer.cast(@global_trace_provider, {:record_span, span})
        span.id
      end
    end
  end

  @doc """
  Ends a span with optional result data.
  """
  def end_span(span_id, result \\ nil) do
    if tracing_enabled?() and not is_nil(span_id) and Process.whereis(@global_trace_provider) do
      GenServer.cast(@global_trace_provider, {:end_span, span_id, result, DateTime.utc_now()})
    end
  end

  @doc """
  Ends the current conversation trace.
  """
  def end_conversation_trace(trace_id, result \\ nil) do
    if tracing_enabled?() and not is_nil(trace_id) and Process.whereis(@global_trace_provider) do
      GenServer.cast(@global_trace_provider, {:end_trace, trace_id, result, DateTime.utc_now()})
    end
  end

  @doc """
  Checks if tracing is enabled.
  """
  def tracing_enabled? do
    case System.get_env("OPENAI_AGENTS_DISABLE_TRACING") do
      "true" -> false
      "1" -> false
      _ -> Application.get_env(:openai_agents, :tracing_enabled, true)
    end
  end

  ## GenServer Implementation

  @impl true
  def init(config) do
    state = %{
      config: config,
      traces: %{},
      spans: %{},
      pending_exports: []
    }

    # Schedule periodic batch export
    if config.batch_timeout > 0 do
      Process.send_after(self(), :export_batch, config.batch_timeout)
    end

    {:ok, state}
  end

  @impl true
  def handle_call({:start_trace, trace}, _from, state) do
    new_state = %{state | traces: Map.put(state.traces, trace.id, trace)}

    # Notify processors
    Enum.each(state.config.processors, fn processor ->
      Processor.on_trace_start(processor, trace)
    end)

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_cast({:record_span, span}, state) do
    new_state = %{state | spans: Map.put(state.spans, span.id, span)}

    # Notify processors
    Enum.each(state.config.processors, fn processor ->
      Processor.on_span_start(processor, span)
    end)

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:end_span, span_id, result, ended_at}, state) do
    case Map.get(state.spans, span_id) do
      nil ->
        {:noreply, state}

      span ->
        updated_span = %{span | ended_at: ended_at, result: result}
        new_state = %{state | spans: Map.put(state.spans, span_id, updated_span)}

        # Notify processors
        Enum.each(state.config.processors, fn processor ->
          Processor.on_span_end(processor, updated_span)
        end)

        # Add to pending exports
        new_state = %{new_state | pending_exports: [updated_span | new_state.pending_exports]}

        {:noreply, new_state}
    end
  end

  @impl true
  def handle_cast({:end_trace, trace_id, result, ended_at}, state) do
    case Map.get(state.traces, trace_id) do
      nil ->
        {:noreply, state}

      trace ->
        # Get all spans for this trace
        trace_spans =
          state.spans
          |> Enum.filter(fn {_id, span} -> span.trace_id == trace_id end)
          |> Enum.map(fn {_id, span} -> span end)

        updated_trace = %{trace | ended_at: ended_at, result: result, spans: trace_spans}
        new_state = %{state | traces: Map.put(state.traces, trace_id, updated_trace)}

        # Notify processors
        Enum.each(state.config.processors, fn processor ->
          Processor.on_trace_end(processor, updated_trace)
        end)

        # Add to pending exports
        new_state = %{new_state | pending_exports: [updated_trace | new_state.pending_exports]}

        {:noreply, new_state}
    end
  end

  @impl true
  def handle_info(:export_batch, state) do
    # Export pending items in batches
    if length(state.pending_exports) > 0 do
      batches = Enum.chunk_every(state.pending_exports, state.config.batch_size)

      Enum.each(batches, fn batch ->
        Enum.each(state.config.exporters, fn exporter ->
          Task.start(fn -> Exporter.export(exporter, batch) end)
        end)
      end)

      new_state = %{state | pending_exports: []}

      # Schedule next export
      Process.send_after(self(), :export_batch, state.config.batch_timeout)

      {:noreply, new_state}
    else
      # Schedule next export
      Process.send_after(self(), :export_batch, state.config.batch_timeout)
      {:noreply, state}
    end
  end

  ## Private Functions

  defp generate_trace_id do
    uuid = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    "trace_#{uuid}"
  end

  defp generate_span_id do
    uuid = :crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower)
    "span_#{uuid}"
  end

  defp generate_group_id do
    uuid = :crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower)
    "group_#{uuid}"
  end
end
