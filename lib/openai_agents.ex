defmodule OpenAI.Agents do
  @moduledoc """
  OpenAI Agents is an Elixir library for building AI agents using OpenAI's Responses API.

  This library provides a powerful, idiomatic Elixir framework for creating agents that can:
  - Use tools to perform actions
  - Hand off conversations to other specialized agents
  - Validate inputs and outputs with guardrails
  - Stream responses in real-time
  - Maintain conversation context

  ## Quick Start

      defmodule MyApp.Assistant do
        use OpenAI.Agent
        
        @impl true
        def configure do
          %{
            name: "assistant",
            instructions: "You are a helpful assistant.",
            tools: [MyApp.Tools.Calculator]
          }
        end
      end
      
      # Run the agent
      {:ok, result} = OpenAI.Agents.run(MyApp.Assistant, "What is 2 + 2?")
      IO.puts(result.output)
  """

  alias OpenAI.Agents.Runner

  @doc """
  Runs an agent synchronously with the given input.

  ## Options

    * `:context` - Application-specific context to pass through execution
    * `:config` - Runtime configuration overrides
    * `:timeout` - Maximum time to wait for completion (default: 60000ms)
    * `:previous_response_id` - Response ID from previous turn to continue conversation (handled automatically)

  ## Examples

      OpenAI.Agents.run(MyAgent, "Hello")
      OpenAI.Agents.run(MyAgent, "Hello", context: %{user_id: "123"})
      
      # Multi-turn conversation
      {:ok, result1} = OpenAI.Agents.run(MyAgent, "My name is Alice")
      {:ok, result2} = OpenAI.Agents.run(MyAgent, "What's my name?")
  """
  @spec run(module(), String.t() | list(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(agent_module, input, opts \\ []) do
    Runner.run(agent_module, input, opts)
  end

  @doc """
  Runs an agent asynchronously, returning a Task.

  ## Options

  Same as `run/3`.

  ## Examples

      task = OpenAI.Agents.run_async(MyAgent, "Hello")
      {:ok, result} = Task.await(task)
  """
  @spec run_async(module(), String.t() | list(), keyword()) :: Task.t()
  def run_async(agent_module, input, opts \\ []) do
    Runner.run_async(agent_module, input, opts)
  end

  @doc """
  Streams an agent's responses in real-time.

  Returns a Stream that emits events as the agent processes the input.

  ## Options

  Same as `run/3`.

  ## Examples

      MyAgent
      |> OpenAI.Agents.stream("Tell me a story")
      |> Enum.each(fn event ->
        case event do
          %TextDelta{text: text} -> IO.write(text)
          %ToolCall{name: name} -> IO.puts("\\nCalling tool: \#{name}")
          _ -> :ok
        end
      end)
  """
  @spec stream(module(), String.t() | list(), keyword()) :: Enumerable.t()
  def stream(agent_module, input, opts \\ []) do
    Runner.stream(agent_module, input, opts)
  end
end
