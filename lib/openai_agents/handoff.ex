defmodule OpenAI.Agents.Handoff do
  @moduledoc """
  Manages handoffs between agents.
  
  Handoffs allow one agent to delegate control to another agent,
  optionally filtering the conversation history.
  """

  @type handoff_config :: %{
          target: module(),
          description: String.t() | nil,
          input_filter: function() | nil,
          input_schema: map() | nil
        }

  @doc """
  Creates a handoff configuration.
  """
  @spec create(module(), keyword()) :: handoff_config()
  def create(target_agent, opts \\ []) do
    %{
      target: target_agent,
      description: Keyword.get(opts, :description),
      input_filter: Keyword.get(opts, :input_filter),
      input_schema: Keyword.get(opts, :input_schema)
    }
  end

  @doc """
  Converts a handoff to a tool schema for use in the API.
  """
  @spec to_tool_schema(module() | handoff_config()) :: map()
  def to_tool_schema(target_agent) when is_atom(target_agent) do
    to_tool_schema(create(target_agent))
  end

  def to_tool_schema(%{target: target} = handoff) do
    agent_config = OpenAI.Agent.get_config(target)
    
    %{
      type: "function",
      name: "handoff_to_#{agent_config.name}",
      description: handoff.description || "Transfer to #{agent_config.name}",
      function: %{
        parameters: handoff.input_schema || default_handoff_schema()
      }
    }
  end

  @doc """
  Executes a handoff.
  """
  @spec execute(map(), [module() | handoff_config()], map()) :: 
    {:ok, module(), list()} | {:error, term()}
  def execute(handoff_call, available_handoffs, state) do
    tool_name = handoff_call[:name] || handoff_call["name"]
    
    # Find the matching handoff
    case find_handoff(tool_name, available_handoffs) do
      nil ->
        {:error, "Unknown handoff: #{tool_name}"}
        
      handoff ->
        # Get the target agent
        target = if is_atom(handoff), do: handoff, else: handoff.target
        
        # Filter conversation if needed
        filtered_conversation = 
          if is_map(handoff) and handoff.input_filter do
            apply_filter(handoff.input_filter, state.conversation, state)
          else
            state.conversation
          end
        
        {:ok, target, filtered_conversation}
    end
  end

  defp find_handoff(tool_name, handoffs) do
    Enum.find(handoffs, fn handoff ->
      expected_name = case handoff do
        module when is_atom(module) ->
          config = OpenAI.Agent.get_config(module)
          "handoff_to_#{config.name}"
          
        %{target: target} ->
          config = OpenAI.Agent.get_config(target)
          "handoff_to_#{config.name}"
      end
      
      tool_name == expected_name
    end)
  end

  defp apply_filter(filter, conversation, _state) when is_function(filter, 1) do
    filter.(conversation)
  end

  defp apply_filter(filter, conversation, state) when is_function(filter, 2) do
    filter.(conversation, state.context)
  end

  defp default_handoff_schema do
    %{
      type: "object",
      properties: %{
        input: %{
          type: "string",
          description: "Context or message to pass to the agent"
        }
      },
      required: ["input"]
    }
  end

  @doc """
  Creates a handoff tool module dynamically.
  """
  defmacro handoff(target_agent, opts \\ []) do
    quote do
      OpenAI.Agents.Handoff.create(unquote(target_agent), unquote(opts))
    end
  end
end