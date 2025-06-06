defmodule OpenAI.Agents.Telemetry do
  @moduledoc """
  Telemetry integration for OpenAI Agents.
  
  Emits telemetry events for agent execution, tool calls, and API requests.
  
  ## Events
  
  * `[:openai_agents, :run, :start]` - Emitted when an agent run starts
  * `[:openai_agents, :run, :stop]` - Emitted when an agent run completes
  * `[:openai_agents, :agent, :start]` - Emitted when an agent starts processing
  * `[:openai_agents, :agent, :stop]` - Emitted when an agent completes processing
  * `[:openai_agents, :tool, :start]` - Emitted when a tool execution starts
  * `[:openai_agents, :tool, :stop]` - Emitted when a tool execution completes
  * `[:openai_agents, :handoff, :start]` - Emitted when a handoff starts
  * `[:openai_agents, :api, :request, :start]` - Emitted when an API request starts
  * `[:openai_agents, :api, :request, :stop]` - Emitted when an API request completes
  
  ## Measurements
  
  All `:stop` events include a `:duration` measurement in native time units.
  
  ## Metadata
  
  Events include relevant metadata such as:
  * `:agent_module` - The agent module
  * `:trace_id` - The trace ID for the run
  * `:tool_name` - The name of the tool being executed
  * `:status` - `:ok` or `:error`
  """

  require Logger

  @doc """
  Sets up default telemetry handlers.
  """
  def setup do
    events = [
      [:openai_agents, :run, :start],
      [:openai_agents, :run, :stop],
      [:openai_agents, :agent, :start],
      [:openai_agents, :agent, :stop],
      [:openai_agents, :tool, :start],
      [:openai_agents, :tool, :stop],
      [:openai_agents, :handoff, :start],
      [:openai_agents, :api, :request, :start],
      [:openai_agents, :api, :request, :stop]
    ]

    :telemetry.attach_many(
      "openai-agents-default-handler",
      events,
      &handle_event/4,
      nil
    )
  end

  @doc """
  Emits a run start event.
  """
  def start_run(state) do
    metadata = %{
      agent_module: state.agent_module,
      trace_id: state.trace_id,
      max_turns: state.max_turns
    }

    :telemetry.execute(
      [:openai_agents, :run, :start],
      %{system_time: System.system_time()},
      metadata
    )
  end

  @doc """
  Emits a run stop event.
  """
  def stop_run(state, status) do
    metadata = %{
      agent_module: state.agent_module,
      trace_id: state.trace_id,
      status: status,
      turns: state.current_turn,
      usage: state.usage
    }

    duration = System.monotonic_time() - state.start_time

    :telemetry.execute(
      [:openai_agents, :run, :stop],
      %{duration: duration, system_time: System.system_time()},
      metadata
    )
  end

  @doc """
  Emits an agent start event.
  """
  def start_agent(agent_module, trace_id) do
    metadata = %{
      agent_module: agent_module,
      trace_id: trace_id
    }

    :telemetry.execute(
      [:openai_agents, :agent, :start],
      %{system_time: System.system_time()},
      metadata
    )

    System.monotonic_time()
  end

  @doc """
  Emits an agent stop event.
  """
  def stop_agent(agent_module, trace_id, start_time, status) do
    metadata = %{
      agent_module: agent_module,
      trace_id: trace_id,
      status: status
    }

    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:openai_agents, :agent, :stop],
      %{duration: duration, system_time: System.system_time()},
      metadata
    )
  end

  @doc """
  Emits a tool start event.
  """
  def start_tool(tool_name, call_id) do
    metadata = %{
      tool_name: tool_name,
      call_id: call_id
    }

    :telemetry.execute(
      [:openai_agents, :tool, :start],
      %{system_time: System.system_time()},
      metadata
    )

    System.monotonic_time()
  end

  @doc """
  Emits a tool stop event.
  """
  def stop_tool(tool_name, call_id, result) do
    {status, error} = case result do
      {:ok, _} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end

    metadata = %{
      tool_name: tool_name,
      call_id: call_id,
      status: status,
      error: error
    }

    :telemetry.execute(
      [:openai_agents, :tool, :stop],
      %{system_time: System.system_time()},
      metadata
    )
  end

  @doc """
  Emits a handoff event.
  """
  def handoff(from_agent, to_agent, trace_id) do
    metadata = %{
      from_agent: from_agent,
      to_agent: to_agent,
      trace_id: trace_id
    }

    :telemetry.execute(
      [:openai_agents, :handoff, :start],
      %{system_time: System.system_time()},
      metadata
    )
  end

  @doc """
  Emits an API request start event.
  """
  def start_api_request(method, endpoint, trace_id) do
    metadata = %{
      method: method,
      endpoint: endpoint,
      trace_id: trace_id
    }

    :telemetry.execute(
      [:openai_agents, :api, :request, :start],
      %{system_time: System.system_time()},
      metadata
    )

    System.monotonic_time()
  end

  @doc """
  Emits an API request stop event.
  """
  def stop_api_request(method, endpoint, trace_id, start_time, status, response_data \\ nil) do
    metadata = %{
      method: method,
      endpoint: endpoint,
      trace_id: trace_id,
      status: status,
      response_data: response_data
    }

    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:openai_agents, :api, :request, :stop],
      %{duration: duration, system_time: System.system_time()},
      metadata
    )
  end

  # Default event handler
  defp handle_event(event, measurements, metadata, _config) do
    case event do
      [:openai_agents, :run, :start] ->
        Logger.info("Agent run started", 
          agent: metadata.agent_module,
          trace_id: metadata.trace_id
        )

      [:openai_agents, :run, :stop] ->
        duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
        
        Logger.info("Agent run completed",
          agent: metadata.agent_module,
          trace_id: metadata.trace_id,
          duration_ms: duration_ms,
          status: metadata.status,
          turns: metadata.turns
        )

      [:openai_agents, :tool, :start] ->
        Logger.debug("Tool execution started",
          tool: metadata.tool_name,
          call_id: metadata.call_id
        )

      [:openai_agents, :tool, :stop] ->
        Logger.debug("Tool execution completed",
          tool: metadata.tool_name,
          call_id: metadata.call_id,
          status: metadata.status
        )

      [:openai_agents, :api, :request, :stop] ->
        duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
        
        Logger.debug("API request completed",
          method: metadata.method,
          endpoint: metadata.endpoint,
          duration_ms: duration_ms,
          status: metadata.status
        )

      _ ->
        :ok
    end
  end
end