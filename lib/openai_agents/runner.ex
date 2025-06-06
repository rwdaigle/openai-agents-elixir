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
    :start_time,
    :caller_pid
  ]

  @default_max_turns 10
  @default_timeout 60_000

  # Public API

  @doc """
  Runs an agent synchronously.
  """
  def run(agent_module, input, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    # Pass the calling process so agent callbacks can send messages
    opts_with_caller = Keyword.put(opts, :caller_pid, self())
    {:ok, runner} = start_link(agent_module, input, opts_with_caller)

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

    # Start the agent execution asynchronously
    Task.start_link(fn ->
      GenServer.call(runner, :run, 60_000)
    end)

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
      start_time: System.monotonic_time(),
      caller_pid: Keyword.get(opts, :caller_pid, self())
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

  @impl true
  def handle_info(:agent_started, state) do
    # Forward agent lifecycle messages to the caller
    if state.caller_pid && Process.alive?(state.caller_pid) do
      send(state.caller_pid, :agent_started)
    end

    {:noreply, state}
  end

  # Private functions

  defp execute_agent_loop(state) do
    with {:ok, state} <- check_turn_limit(state),
         {:ok, state} <- run_agent_lifecycle(:on_start, state),
         {:ok, instructions} <- Agent.get_instructions(state.agent_module, state.context),
         {:ok, state} <- run_input_guardrails(state),
         model_result <- call_model(instructions, state) do
      case model_result do
        {:ok, response, state} ->
          # Both streaming and non-streaming flow
          case process_response(response, state) do
            {:ok, result, state} ->
              if result.is_final do
                # Complete the stream if we have a producer
                if state.stream_producer do
                  StreamHandler.complete(state.stream_producer)
                end

                {:ok, finalize_result(result, state), state}
              else
                # Continue the loop
                state = %{
                  state
                  | conversation: state.conversation ++ result.new_items,
                    current_turn: state.current_turn + 1
                }

                execute_agent_loop(state)
              end

            {:error, reason, error_state} ->
              # Complete the stream on error if we have a producer
              if error_state.stream_producer do
                StreamHandler.complete(error_state.stream_producer)
              end

              {:error, reason, error_state}
          end

        {:error, reason, error_state} ->
          # Complete the stream on error if we have a producer
          if error_state.stream_producer do
            StreamHandler.complete(error_state.stream_producer)
          end

          {:error, reason, error_state}
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
      # Pass runner pid to agent so it can send messages back
      agent_state = %{runner_pid: self()}

      case apply(agent_module, callback, [state.context, agent_state]) do
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
        # Streaming call - start the stream asynchronously but continue execution
        stream_events =
          adapter.create_stream(request, get_api_config(state))
          |> Enum.to_list()

        # Emit all events to the stream handler
        Enum.each(stream_events, fn event ->
          StreamHandler.emit(producer, event)
        end)

        # Extract the final response from the stream events
        response =
          Enum.reduce(stream_events, %{output: [], usage: %{}}, fn event, acc ->
            case event do
              %{type: "response.completed", data: data} ->
                response = data["response"] || data

                %{
                  output: response["output"] || [],
                  usage: response["usage"] || %{},
                  response_id: response["id"],
                  created: response["created_at"],
                  model: response["model"]
                }

              _ ->
                acc
            end
          end)

        # Handle completed function calls in streaming responses
        response = handle_streaming_completed_function_calls(response, state, producer)

        # Continue with the accumulated response like non-streaming
        usage = update_usage(state.usage, response.usage)
        {:ok, response, %{state | usage: usage}}
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
    handoffs = Map.get(config, :handoffs, [])

    # Separate regular tool calls from handoff calls
    {handoff_calls, tool_calls} =
      Enum.split_with(function_calls, fn call ->
        function_name = call[:name] || call["name"]
        String.starts_with?(function_name, "handoff_to_")
      end)

    # If we have a handoff call, process it immediately
    case handoff_calls do
      [handoff_call | _] ->
        # Process the first handoff (ignore multiple handoffs)
        case Handoff.execute(handoff_call, handoffs, state) do
          {:ok, target_agent, filtered_conversation} ->
            # Execute the target agent
            execute_handoff_agent(target_agent, filtered_conversation, state)

          {:error, reason} ->
            {:error, {:handoff_error, reason}, state}
        end

      [] ->
        # Execute regular tool calls in parallel
        results = ToolExecutor.execute_parallel(tool_calls, tools, state.context)

        # First add the function calls to the conversation, then add the results
        function_call_items =
          Enum.map(tool_calls, fn call ->
            %{
              type: "function_call",
              call_id: call.id || call["id"],
              name: call.name || call["name"],
              arguments: call.arguments || call["arguments"] || "{}"
            }
          end)

        # Convert results to conversation items
        result_items =
          Enum.map(results, fn {call_id, result} ->
            %{
              type: "function_call_output",
              call_id: call_id,
              output: encode_result(result)
            }
          end)

        all_new_items = function_call_items ++ result_items
        {:ok, %{is_final: false, output: nil, new_items: all_new_items}, state}
    end
  end

  defp execute_handoff_agent(target_agent, filtered_conversation, state) do
    # Switch to the new agent
    new_state = %{
      state
      | agent_module: target_agent,
        conversation: filtered_conversation,
        # Reset turn counter for new agent
        current_turn: 0
    }

    # Execute the new agent and return the result directly
    # This is the final result from the handoff
    case execute_agent_loop(new_state) do
      {:ok, final_result, _final_state} ->
        # Return as a final result since handoff completes the execution
        {:ok, %{is_final: true, output: final_result.output, new_items: []}, state}

      {:error, reason, error_state} ->
        {:error, reason, error_state}
    end
  end

  defp process_handoff(handoff, state) do
    config = Agent.get_config(state.agent_module)
    handoffs = Map.get(config, :handoffs, [])

    case Handoff.execute(handoff, handoffs, state) do
      {:ok, new_agent_module, filtered_conversation} ->
        execute_handoff_agent(new_agent_module, filtered_conversation, state)

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

    base_request = %{
      model: Map.get(config, :model, "gpt-4.1-mini"),
      instructions: instructions,
      input: conversation,
      tools: tools,
      temperature: get_in(config, [:model_settings, :temperature]),
      top_p: get_in(config, [:model_settings, :top_p]),
      tool_choice: get_in(config, [:model_settings, :tool_choice]) || "auto",
      parallel_tool_calls: get_in(config, [:model_settings, :parallel_tool_calls]) != false,
      stream: state.stream_producer != nil
    }

    # Add response format if configured
    base_request =
      case Map.get(config, :output_schema) do
        nil ->
          base_request

        schema_module ->
          # Extract just the module name from the full module path
          module_name =
            schema_module
            |> to_string()
            |> String.split(".")
            |> List.last()
            |> String.replace(~r/[^a-zA-Z0-9_]/, "_")

          Map.put(base_request, :text, %{
            format: %{
              type: "json_schema",
              name: module_name,
              schema: schema_module.json_schema()
            }
          })
      end

    base_request
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp prepare_tools(config, _state) do
    tools = Map.get(config, :tools, [])
    handoffs = Map.get(config, :handoffs, [])

    tool_schemas =
      Enum.map(tools, fn tool_module ->
        schema = apply(tool_module, :schema, [])
        Map.put(schema, :type, "function")
      end)

    handoff_schemas =
      Enum.map(handoffs, fn handoff ->
        schema = Handoff.to_tool_schema(handoff)
        Map.put(schema, :type, "function")
      end)

    tool_schemas ++ handoff_schemas
  end

  # This function is no longer needed - format is handled in build_request
  # defp build_response_format(config) do
  #   case Map.get(config, :output_schema) do
  #     nil -> nil
  #     schema_module -> 
  #       %{
  #         type: "json_schema",
  #         json_schema: %{
  #           name: to_string(schema_module),
  #           schema: schema_module.json_schema()
  #         }
  #       }
  #   end
  # end

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
    # Priority order: runtime env var > config > error
    System.get_env("OPENAI_API_KEY") ||
      Application.get_env(:openai_agents, :api_key) ||
      raise "OpenAI API key not configured. Set OPENAI_API_KEY environment variable or configure in config files."
  end

  defp get_base_url do
    # For tests with real API key, use real OpenAI endpoint
    cond do
      System.get_env("OPENAI_BASE_URL") ->
        System.get_env("OPENAI_BASE_URL")

      Mix.env() == :test and System.get_env("OPENAI_API_KEY") ->
        # In test mode with real API key, use real endpoint
        "https://api.openai.com/v1"

      true ->
        Application.get_env(:openai_agents, :base_url, "https://api.openai.com/v1")
    end
  end

  defp init_context(nil), do: Context.new()
  defp init_context(context), do: Context.wrap(context)

  defp normalize_input(input) when is_binary(input) do
    [%{type: "message", role: "user", content: input}]
  end

  defp normalize_input(input) when is_list(input), do: input

  defp generate_trace_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp update_usage(current_usage, new_usage) do
    # The Responses API uses different field names for usage
    prompt_tokens = new_usage["input_tokens"] || new_usage[:prompt_tokens] || 0
    completion_tokens = new_usage["output_tokens"] || new_usage[:completion_tokens] || 0

    total_tokens =
      new_usage["total_tokens"] || new_usage[:total_tokens] || prompt_tokens + completion_tokens

    %Usage{
      prompt_tokens: current_usage.prompt_tokens + prompt_tokens,
      completion_tokens: current_usage.completion_tokens + completion_tokens,
      total_tokens: current_usage.total_tokens + total_tokens
    }
  end

  defp combine_text_items(text_items) do
    text_items
    |> Enum.map(& &1.text)
    |> Enum.join("\n")
  end

  defp encode_result({:ok, result}), do: Jason.encode!(result)
  defp encode_result({:error, error}), do: Jason.encode!(%{error: to_string(error)})

  defp handle_streaming_completed_function_calls(response, state, producer) do
    # Check if response contains completed function calls
    completed_function_calls =
      Enum.filter(response.output, fn item ->
        item["type"] == "function_call" && item["status"] == "completed"
      end)

    if length(completed_function_calls) > 0 do
      # Execute the tools to get actual results (even though API marked them completed)
      config = Agent.get_config(state.agent_module)
      tools = Map.get(config, :tools, [])

      # Convert to the format expected by ToolExecutor
      tool_calls =
        Enum.map(completed_function_calls, fn call ->
          %{
            id: call["id"],
            name: call["name"],
            arguments: call["arguments"] || "{}"
          }
        end)

      # Execute the tools to get results
      results = ToolExecutor.execute_parallel(tool_calls, tools, state.context)

      # Build conversation with function calls and results
      function_call_items =
        Enum.map(tool_calls, fn call ->
          %{
            type: "function_call",
            call_id: call.id,
            name: call.name,
            arguments: call.arguments
          }
        end)

      result_items =
        Enum.map(results, fn {call_id, result} ->
          %{
            type: "function_call_output",
            call_id: call_id,
            output: encode_result(result)
          }
        end)

      # Add tool results to conversation and make follow-up API call
      new_conversation = state.conversation ++ function_call_items ++ result_items

      # Make a follow-up streaming API call to let agent respond to tool results
      {:ok, instructions} = Agent.get_instructions(state.agent_module, state.context)
      follow_up_request = build_request(instructions, new_conversation, config, state)

      adapter = get_model_adapter(config)

      follow_up_events =
        adapter.create_stream(follow_up_request, get_api_config(state))
        |> Enum.to_list()

      # Emit follow-up events to the stream handler
      Enum.each(follow_up_events, fn event ->
        StreamHandler.emit(producer, event)
      end)

      # Extract the follow-up response
      follow_up_response =
        Enum.reduce(follow_up_events, %{output: [], usage: %{}}, fn event, acc ->
          case event do
            %{type: "response.completed", data: data} ->
              response = data["response"] || data

              %{
                output: response["output"] || [],
                usage: response["usage"] || %{},
                response_id: response["id"],
                created: response["created_at"],
                model: response["model"]
              }

            _ ->
              acc
          end
        end)

      # Return the follow-up response instead of the original
      follow_up_response
    else
      # No completed function calls, return original response
      response
    end
  end

  defp finalize_result(result, state) do
    %{
      output: result.output,
      usage: state.usage,
      trace_id: state.trace_id,
      duration_ms:
        System.convert_time_unit(
          System.monotonic_time() - state.start_time,
          :native,
          :millisecond
        )
    }
  end
end
