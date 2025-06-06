defmodule OpenAI.Agents.Runner do
  @moduledoc """
  Manages the execution of agents, handling the conversation loop,
  tool execution, handoffs, and streaming.
  """

  use GenServer
  require Logger

  alias OpenAI.Agent
  alias OpenAI.Agents.{
    Context,
    Models.ResponsesAdapter,
    StreamHandler,
    ToolExecutor,
    Guardrail,
    Handoff,
    Telemetry,
    Usage
  }

  defstruct [
    :agent_module,
    :context,
    :conversation,
    :current_turn,
    :max_turns,
    :trace_id,
    :stream_producer,
    :config,
    :usage,
    :start_time
  ]

  @default_max_turns 10
  @default_timeout 60_000

  # Public API

  @doc """
  Runs an agent synchronously.
  """
  def run(agent_module, input, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    
    {:ok, runner} = start_link(agent_module, input, opts)
    
    try do
      GenServer.call(runner, :run, timeout)
    after
      GenServer.stop(runner, :normal)
    end
  end

  @doc """
  Runs an agent asynchronously.
  """
  def run_async(agent_module, input, opts \\ []) do
    Task.async(fn ->
      run(agent_module, input, opts)
    end)
  end

  @doc """
  Streams agent responses.
  """
  def stream(agent_module, input, opts \\ []) do
    {:ok, runner} = start_link(agent_module, input, opts)
    {:ok, producer} = GenServer.call(runner, :get_stream_producer)
    
    Stream.resource(
      fn -> {runner, producer} end,
      fn {runner, producer} ->
        case StreamHandler.next_event(producer) do
          {:ok, event} -> {[event], {runner, producer}}
          :done -> {:halt, {runner, producer}}
        end
      end,
      fn {runner, _producer} -> GenServer.stop(runner, :normal) end
    )
  end

  # GenServer callbacks

  def start_link(agent_module, input, opts) do
    GenServer.start_link(__MODULE__, {agent_module, input, opts})
  end

  @impl true
  def init({agent_module, input, opts}) do
    trace_id = Keyword.get(opts, :trace_id, generate_trace_id())
    
    state = %__MODULE__{
      agent_module: agent_module,
      context: init_context(opts[:context]),
      conversation: normalize_input(input),
      current_turn: 0,
      max_turns: Keyword.get(opts, :max_turns, @default_max_turns),
      trace_id: trace_id,
      config: Keyword.get(opts, :config, %{}),
      usage: %Usage{},
      start_time: System.monotonic_time()
    }
    
    # Start telemetry span
    Telemetry.start_run(state)
    
    {:ok, state}
  end

  @impl true
  def handle_call(:run, _from, state) do
    case execute_agent_loop(state) do
      {:ok, result, final_state} ->
        Telemetry.stop_run(final_state, :ok)
        {:reply, {:ok, result}, final_state}
        
      {:error, reason, final_state} ->
        Telemetry.stop_run(final_state, {:error, reason})
        {:reply, {:error, reason}, final_state}
    end
  end

  @impl true
  def handle_call(:get_stream_producer, _from, state) do
    {:ok, producer} = StreamHandler.start_link(trace_id: state.trace_id)
    state = %{state | stream_producer: producer}
    {:reply, {:ok, producer}, state}
  end

  # Private functions

  defp execute_agent_loop(state) do
    with {:ok, state} <- check_turn_limit(state),
         {:ok, state} <- run_agent_lifecycle(:on_start, state),
         {:ok, instructions} <- Agent.get_instructions(state.agent_module, state.context),
         {:ok, state} <- run_input_guardrails(state),
         {:ok, response, state} <- call_model(instructions, state),
         {:ok, result, state} <- process_response(response, state) do
      
      if result.is_final do
        {:ok, finalize_result(result, state), state}
      else
        # Continue the loop
        state = %{state | 
          conversation: state.conversation ++ result.new_items,
          current_turn: state.current_turn + 1
        }
        execute_agent_loop(state)
      end
    end
  end

  defp check_turn_limit(%{current_turn: turn, max_turns: max} = state) when turn >= max do
    {:error, {:max_turns_exceeded, turn}, state}
  end
  defp check_turn_limit(state), do: {:ok, state}

  defp run_agent_lifecycle(callback, state) do
    agent_module = state.agent_module
    
    if function_exported?(agent_module, callback, 2) do
      case apply(agent_module, callback, [state.context, %{}]) do
        {:ok, _} -> {:ok, state}
        {:error, reason} -> {:error, reason, state}
      end
    else
      {:ok, state}
    end
  end

  defp run_input_guardrails(state) do
    config = Agent.get_config(state.agent_module)
    guardrails = Map.get(config, :input_guardrails, [])
    
    case Guardrail.run_input_guardrails(guardrails, state.conversation, state) do
      :ok -> {:ok, state}
      {:error, reason} -> {:error, {:guardrail_triggered, reason}, state}
    end
  end

  defp call_model(instructions, state) do
    config = Agent.get_config(state.agent_module)
    
    request = build_request(instructions, state.conversation, config, state)
    
    adapter = get_model_adapter(config)
    
    case state.stream_producer do
      nil ->
        # Non-streaming call
        case adapter.create_completion(request, get_api_config(state)) do
          {:ok, response} ->
            usage = update_usage(state.usage, response.usage)
            {:ok, response, %{state | usage: usage}}
            
          {:error, reason} ->
            {:error, {:api_error, reason}, state}
        end
        
      producer ->
        # Streaming call
        Task.start_link(fn ->
          adapter.create_stream(request, get_api_config(state))
          |> Stream.each(&StreamHandler.emit(producer, &1))
          |> Stream.run()
          
          StreamHandler.complete(producer)
        end)
        
        # For streaming, we return a placeholder response
        {:ok, %{output: [], usage: %{}}, state}
    end
  end

  defp process_response(response, state) do
    output_items = response.output || []
    
    # Group items by type
    {text_items, function_calls, handoffs} = categorize_output_items(output_items)
    
    cond do
      # Check if we have a final text response
      length(text_items) > 0 and length(function_calls) == 0 and length(handoffs) == 0 ->
        final_output = combine_text_items(text_items)
        
        # Run output guardrails
        case run_output_guardrails(final_output, state) do
          {:ok, validated_output} ->
            {:ok, %{is_final: true, output: validated_output, new_items: []}, state}
            
          {:error, reason} ->
            {:error, {:output_guardrail_triggered, reason}, state}
        end
        
      # Execute function calls
      length(function_calls) > 0 ->
        execute_function_calls(function_calls, state)
        
      # Process handoff
      length(handoffs) > 0 ->
        process_handoff(hd(handoffs), state)
        
      true ->
        {:error, {:unexpected_response, "No actionable items in response"}, state}
    end
  end

  defp categorize_output_items(items) do
    Enum.reduce(items, {[], [], []}, fn item, {texts, functions, handoffs} ->
      case item do
        %{type: "text", text: _} = text_item ->
          {[text_item | texts], functions, handoffs}
          
        %{type: "function_call"} = function_call ->
          {texts, [function_call | functions], handoffs}
          
        %{type: "handoff"} = handoff ->
          {texts, functions, [handoff | handoffs]}
          
        _ ->
          {texts, functions, handoffs}
      end
    end)
    |> then(fn {texts, functions, handoffs} ->
      {Enum.reverse(texts), Enum.reverse(functions), Enum.reverse(handoffs)}
    end)
  end

  defp execute_function_calls(function_calls, state) do
    config = Agent.get_config(state.agent_module)
    tools = Map.get(config, :tools, [])
    
    # Execute all function calls in parallel
    results = ToolExecutor.execute_parallel(function_calls, tools, state.context)
    
    # Convert results to conversation items
    new_items = Enum.map(results, fn {call_id, result} ->
      %{
        type: "function_call_result",
        call_id: call_id,
        result: encode_result(result)
      }
    end)
    
    {:ok, %{is_final: false, output: nil, new_items: new_items}, state}
  end

  defp process_handoff(handoff, state) do
    config = Agent.get_config(state.agent_module)
    handoffs = Map.get(config, :handoffs, [])
    
    case Handoff.execute(handoff, handoffs, state) do
      {:ok, new_agent_module, filtered_conversation} ->
        # Switch to the new agent
        new_state = %{state |
          agent_module: new_agent_module,
          conversation: filtered_conversation,
          current_turn: 0  # Reset turn counter for new agent
        }
        
        # Continue execution with new agent
        execute_agent_loop(new_state)
        
      {:error, reason} ->
        {:error, {:handoff_failed, reason}, state}
    end
  end

  defp run_output_guardrails(output, state) do
    config = Agent.get_config(state.agent_module)
    guardrails = Map.get(config, :output_guardrails, [])
    
    Guardrail.run_output_guardrails(guardrails, output, state)
  end

  defp build_request(instructions, conversation, config, state) do
    tools = prepare_tools(config, state)
    
    %{
      model: Map.get(config, :model, "gpt-4o"),
      instructions: instructions,
      input: conversation,
      tools: tools,
      temperature: get_in(config, [:model_settings, :temperature]),
      top_p: get_in(config, [:model_settings, :top_p]),
      max_tokens: get_in(config, [:model_settings, :max_tokens]),
      tool_choice: get_in(config, [:model_settings, :tool_choice]) || "auto",
      parallel_tool_calls: get_in(config, [:model_settings, :parallel_tool_calls]) != false,
      response_format: build_response_format(config),
      stream: state.stream_producer != nil
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp prepare_tools(config, _state) do
    tools = Map.get(config, :tools, [])
    handoffs = Map.get(config, :handoffs, [])
    
    tool_schemas = Enum.map(tools, &apply(&1, :schema, []))
    handoff_schemas = Enum.map(handoffs, &Handoff.to_tool_schema/1)
    
    tool_schemas ++ handoff_schemas
  end

  defp build_response_format(config) do
    case Map.get(config, :output_schema) do
      nil -> nil
      schema_module -> 
        %{
          type: "json_schema",
          json_schema: %{
            name: to_string(schema_module),
            schema: schema_module.json_schema()
          }
        }
    end
  end

  defp get_model_adapter(_config) do
    # For now, we only support the Responses API adapter
    ResponsesAdapter
  end

  defp get_api_config(state) do
    %{
      api_key: get_api_key(),
      base_url: get_base_url(),
      trace_id: state.trace_id
    }
  end

  defp get_api_key do
    System.get_env("OPENAI_API_KEY") || 
      Application.get_env(:openai_agents, :api_key) ||
      raise "OpenAI API key not configured"
  end

  defp get_base_url do
    System.get_env("OPENAI_BASE_URL") || 
      Application.get_env(:openai_agents, :base_url) ||
      "https://api.openai.com/v1"
  end

  defp init_context(nil), do: Context.new()
  defp init_context(context), do: Context.wrap(context)

  defp normalize_input(input) when is_binary(input) do
    [%{type: "user_text", text: input}]
  end
  defp normalize_input(input) when is_list(input), do: input

  defp generate_trace_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp update_usage(current_usage, new_usage) do
    %Usage{
      prompt_tokens: current_usage.prompt_tokens + (new_usage[:prompt_tokens] || 0),
      completion_tokens: current_usage.completion_tokens + (new_usage[:completion_tokens] || 0),
      total_tokens: current_usage.total_tokens + (new_usage[:total_tokens] || 0)
    }
  end

  defp combine_text_items(text_items) do
    text_items
    |> Enum.map(& &1.text)
    |> Enum.join("\n")
  end

  defp encode_result({:ok, result}), do: Jason.encode!(result)
  defp encode_result({:error, error}), do: Jason.encode!(%{error: to_string(error)})

  defp finalize_result(result, state) do
    %{
      output: result.output,
      usage: state.usage,
      trace_id: state.trace_id,
      duration_ms: System.convert_time_unit(
        System.monotonic_time() - state.start_time,
        :native,
        :millisecond
      )
    }
  end
end