defmodule OpenAI.Agents.TracingSupervisor do
  @moduledoc """
  Supervisor for tracing components.
  """

  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # Trace collector for aggregating trace data
      {OpenAI.Agents.TraceCollector, []},

      # Dynamic supervisor for trace processors
      {DynamicSupervisor, name: OpenAI.Agents.TraceProcessorSupervisor, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

defmodule OpenAI.Agents.TraceCollector do
  @moduledoc """
  Collects and manages trace data for agent runs.
  """

  use GenServer
  require Logger

  defstruct traces: %{}, processors: []

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def start_trace(trace_id, metadata) do
    GenServer.cast(__MODULE__, {:start_trace, trace_id, metadata})
  end

  def add_span(trace_id, span) do
    GenServer.cast(__MODULE__, {:add_span, trace_id, span})
  end

  def end_trace(trace_id) do
    GenServer.cast(__MODULE__, {:end_trace, trace_id})
  end

  def get_trace(trace_id) do
    GenServer.call(__MODULE__, {:get_trace, trace_id})
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    processors = Application.get_env(:openai_agents, :trace_processors, [])

    state = %__MODULE__{
      traces: %{},
      processors: start_processors(processors)
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:start_trace, trace_id, metadata}, state) do
    trace = %{
      id: trace_id,
      metadata: metadata,
      spans: [],
      started_at: DateTime.utc_now(),
      status: :active
    }

    new_traces = Map.put(state.traces, trace_id, trace)

    # Notify processors
    notify_processors(state.processors, {:trace_started, trace})

    {:noreply, %{state | traces: new_traces}}
  end

  @impl true
  def handle_cast({:add_span, trace_id, span}, state) do
    case Map.get(state.traces, trace_id) do
      nil ->
        Logger.warning("Attempted to add span to non-existent trace: #{trace_id}")
        {:noreply, state}

      trace ->
        updated_trace = %{trace | spans: [span | trace.spans]}
        new_traces = Map.put(state.traces, trace_id, updated_trace)

        # Notify processors
        notify_processors(state.processors, {:span_added, trace_id, span})

        {:noreply, %{state | traces: new_traces}}
    end
  end

  @impl true
  def handle_cast({:end_trace, trace_id}, state) do
    case Map.get(state.traces, trace_id) do
      nil ->
        Logger.warning("Attempted to end non-existent trace: #{trace_id}")
        {:noreply, state}

      trace ->
        completed_trace = %{trace | status: :completed, ended_at: DateTime.utc_now()}

        # Notify processors
        notify_processors(state.processors, {:trace_completed, completed_trace})

        # Remove trace after processing (or keep based on config)
        new_traces = Map.delete(state.traces, trace_id)

        {:noreply, %{state | traces: new_traces}}
    end
  end

  @impl true
  def handle_call({:get_trace, trace_id}, _from, state) do
    {:reply, Map.get(state.traces, trace_id), state}
  end

  # Private functions

  defp start_processors(processor_configs) do
    Enum.map(processor_configs, fn
      {module, opts} ->
        {:ok, pid} =
          DynamicSupervisor.start_child(
            OpenAI.Agents.TraceProcessorSupervisor,
            {module, opts}
          )

        pid

      module when is_atom(module) ->
        {:ok, pid} =
          DynamicSupervisor.start_child(
            OpenAI.Agents.TraceProcessorSupervisor,
            {module, []}
          )

        pid
    end)
  end

  defp notify_processors(processors, event) do
    Enum.each(processors, fn processor ->
      GenServer.cast(processor, {:process_event, event})
    end)
  end
end
