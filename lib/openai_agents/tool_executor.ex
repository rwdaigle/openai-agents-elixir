defmodule OpenAI.Agents.ToolExecutor do
  @moduledoc """
  Executes tools in parallel or serially based on their type.
  Handles error recovery and telemetry.
  """

  require Logger
  alias OpenAI.Agents.{Tool, Telemetry}

  @doc """
  Executes multiple function calls in parallel.
  
  Returns a list of {call_id, result} tuples.
  """
  @spec execute_parallel([map()], [module()], any()) :: [{String.t(), any()}]
  def execute_parallel(function_calls, available_tools, context) do
    # Build a map of tool names to modules
    tool_map = build_tool_map(available_tools)
    
    # Start all executions in parallel
    tasks = Enum.map(function_calls, fn call ->
      Task.async(fn ->
        execute_single(call, tool_map, context)
      end)
    end)
    
    # Collect results with a timeout
    Enum.map(tasks, fn task ->
      case Task.yield(task, 30_000) || Task.shutdown(task, :brutal_kill) do
        {:ok, result} -> result
        nil -> 
          {call_id(task), {:error, "Tool execution timeout"}}
      end
    end)
  end

  @doc """
  Executes a single function call.
  """
  @spec execute_single(map(), map(), any()) :: {String.t(), any()}
  def execute_single(function_call, tool_map, context) do
    call_id = function_call.id || function_call["id"]
    tool_name = function_call.name || function_call["name"]
    arguments = parse_arguments(function_call.arguments || function_call["arguments"])
    
    Telemetry.start_tool(tool_name, call_id)
    
    result = case Map.get(tool_map, tool_name) do
      nil ->
        {:error, "Unknown tool: #{tool_name}"}
        
      tool_module ->
        try do
          tool_module.execute(arguments, context)
        rescue
          error ->
            if function_exported?(tool_module, :on_error, 3) do
              tool_module.on_error(error, arguments, context)
            else
              {:error, Exception.message(error)}
            end
        end
    end
    
    Telemetry.stop_tool(tool_name, call_id, result)
    
    {call_id, result}
  end

  defp build_tool_map(tools) do
    Enum.reduce(tools, %{}, fn tool_module, acc ->
      schema = tool_module.schema()
      Map.put(acc, schema.name, tool_module)
    end)
  end

  defp parse_arguments(args) when is_binary(args) do
    case Jason.decode(args) do
      {:ok, parsed} -> parsed
      {:error, _} -> %{}
    end
  end
  defp parse_arguments(args) when is_map(args), do: args
  defp parse_arguments(_), do: %{}

  defp call_id(task) do
    "task_#{inspect(task.ref)}"
  end
end