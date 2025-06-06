# OpenAI Agents for Elixir

Build powerful AI agents in Elixir using OpenAI's Responses API. This library provides an idiomatic Elixir framework for creating agents that can use tools, delegate tasks to specialized agents, and maintain conversations with full type safety and fault tolerance.

## Table of Contents
- [Installation](#installation)
- [Setup](#setup)
- [Basic Usage](#basic-usage)
- [Core Concepts](#core-concepts)
- [Examples](#examples)
- [Elixir-Specific Features](#elixir-specific-features)
- [API Reference](#api-reference)
- [Configuration](#configuration)

## Installation

Add `openai_agents` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:openai_agents, "~> 0.1.0"}
  ]
end
```

Then run:
```bash
mix deps.get
```

## Setup

### 1. Configure your OpenAI API key

Set your API key as an environment variable:
```bash
export OPENAI_API_KEY="your-api-key"
```

Or configure it in your `config/config.exs`:
```elixir
config :openai_agents,
  api_key: System.get_env("OPENAI_API_KEY"),
  default_model: "gpt-4o"
```

### 2. Start the application

If you're using Phoenix or another OTP application, the library will start automatically. For standalone usage, add to your application's supervision tree:

```elixir
def start(_type, _args) do
  children = [
    # ... your other children
    {OpenAI.Agents.Application, []}
  ]
  
  Supervisor.start_link(children, strategy: :one_for_one)
end
```

## Basic Usage

### Creating Your First Agent

```elixir
defmodule MyApp.Assistant do
  use OpenAI.Agent
  
  @impl true
  def configure do
    %{
      name: "assistant",
      instructions: "You are a helpful assistant that responds concisely."
    }
  end
end

# Run the agent
{:ok, result} = OpenAI.Agents.run(MyApp.Assistant, "What is the capital of France?")
IO.puts(result.output)
# => "The capital of France is Paris."
```

### Core Functions

The library provides three main ways to interact with agents:

```elixir
# 1. Synchronous execution (blocking)
{:ok, result} = OpenAI.Agents.run(agent_module, input, opts \\ [])

# 2. Asynchronous execution (returns a Task)
task = OpenAI.Agents.run_async(agent_module, input, opts \\ [])
{:ok, result} = Task.await(task)

# 3. Streaming execution (returns a Stream)
stream = OpenAI.Agents.stream(agent_module, input, opts \\ [])
```

## Core Concepts

### Agents

Agents are modules that implement the `OpenAI.Agent` behaviour:

```elixir
defmodule MyApp.HaikuAgent do
  use OpenAI.Agent
  
  @impl true
  def configure do
    %{
      name: "haiku_bot",
      instructions: "You only respond in haikus.",
      model: "gpt-4o",
      model_settings: %{
        temperature: 0.7,
        max_tokens: 100
      }
    }
  end
  
  # Optional lifecycle callbacks
  @impl true
  def on_start(context, state) do
    IO.puts("Agent starting...")
    {:ok, state}
  end
end
```

### Tools

Tools are functions that agents can call:

```elixir
defmodule MyApp.Tools.Weather do
  use OpenAI.Agents.Tool
  
  @impl true
  def schema do
    %{
      name: "get_weather",
      description: "Get the current weather for a city",
      parameters: %{
        type: "object",
        properties: %{
          city: %{type: "string", description: "City name"}
        },
        required: ["city"]
      }
    }
  end
  
  @impl true
  def execute(%{"city" => city}, _context) do
    # In real usage, call a weather API
    {:ok, %{temperature: 72, conditions: "Sunny", city: city}}
  end
end
```

### Context

Pass application state through the execution:

```elixir
# Define your context
context = %{
  user_id: "123",
  session_id: "abc",
  preferences: %{language: "en"}
}

# Pass it to the agent
{:ok, result} = OpenAI.Agents.run(MyApp.Assistant, "Hello", context: context)

# Access it in tools
defmodule MyApp.Tools.UserPreferences do
  use OpenAI.Agents.Tool
  
  @impl true
  def execute(_params, context) do
    user_id = context.user_context.user_id
    # Use the context data
    {:ok, %{user_id: user_id}}
  end
end
```

## Examples

### Example 1: Simple Q&A Agent

```elixir
defmodule MyApp.QAAgent do
  use OpenAI.Agent
  
  @impl true
  def configure do
    %{
      name: "qa_agent",
      instructions: """
      You are a helpful Q&A assistant. 
      Provide clear, accurate answers to questions.
      If you don't know something, say so.
      """
    }
  end
end

# Usage
{:ok, result} = OpenAI.Agents.run(MyApp.QAAgent, "What is Elixir?")
```

### Example 2: Agent with Tools

```elixir
defmodule MyApp.MathTools do
  use OpenAI.Agents.Tool
  
  @impl true
  def schema do
    %{
      name: "calculate",
      description: "Perform mathematical calculations",
      parameters: %{
        type: "object",
        properties: %{
          expression: %{type: "string"}
        },
        required: ["expression"]
      }
    }
  end
  
  @impl true
  def execute(%{"expression" => expr}, _context) do
    # BE CAREFUL: In production, use a safe math parser!
    try do
      {result, _} = Code.eval_string(expr)
      {:ok, %{result: result}}
    rescue
      _ -> {:error, "Invalid expression"}
    end
  end
end

defmodule MyApp.MathTutor do
  use OpenAI.Agent
  
  @impl true
  def configure do
    %{
      name: "math_tutor",
      instructions: "You are a helpful math tutor. Use the calculate tool for computations.",
      tools: [MyApp.MathTools]
    }
  end
end

# Usage
{:ok, result} = OpenAI.Agents.run(MyApp.MathTutor, "What is 25 * 4 + 10?")
```

### Example 3: Multi-Agent System with Handoffs

```elixir
defmodule MyApp.SpanishAgent do
  use OpenAI.Agent
  
  @impl true
  def configure do
    %{
      name: "spanish_agent",
      instructions: "You only speak Spanish. Respond to all queries in Spanish."
    }
  end
end

defmodule MyApp.FrenchAgent do
  use OpenAI.Agent
  
  @impl true
  def configure do
    %{
      name: "french_agent", 
      instructions: "You only speak French. Respond to all queries in French."
    }
  end
end

defmodule MyApp.TriageAgent do
  use OpenAI.Agent
  
  @impl true
  def configure do
    %{
      name: "triage_agent",
      instructions: """
      You are a triage agent that routes conversations to the right language expert.
      If the user wants Spanish, transfer to the Spanish agent.
      If the user wants French, transfer to the French agent.
      Otherwise, respond in English.
      """,
      handoffs: [MyApp.SpanishAgent, MyApp.FrenchAgent]
    }
  end
end

# Usage
{:ok, result} = OpenAI.Agents.run(MyApp.TriageAgent, "I need help in Spanish")
# Agent will hand off to SpanishAgent
```

### Example 4: Streaming Responses

```elixir
defmodule MyApp.StoryTeller do
  use OpenAI.Agent
  
  @impl true
  def configure do
    %{
      name: "storyteller",
      instructions: "You are a creative storyteller."
    }
  end
end

# Stream the response
MyApp.StoryTeller
|> OpenAI.Agents.stream("Tell me a story about a brave rabbit")
|> Stream.each(fn event ->
  case event do
    %OpenAI.Agents.Events.TextDelta{text: text} -> 
      # Print text as it arrives
      IO.write(text)
      
    %OpenAI.Agents.Events.ToolCall{name: name} -> 
      IO.puts("\n[Calling tool: #{name}]")
      
    %OpenAI.Agents.Events.ResponseCompleted{usage: usage} ->
      IO.puts("\n\nTokens used: #{usage.total_tokens}")
      
    _ -> 
      :ok
  end
end)
|> Stream.run()
```

### Example 5: Agents with Guardrails

```elixir
defmodule MyApp.Guardrails.MathOnly do
  use OpenAI.Agents.Guardrail
  
  @impl true
  def validate_input(input, _context) do
    if String.match?(input, ~r/math|calculate|number|equation/i) do
      :ok
    else
      {:error, "I only help with math questions", %{reason: "off_topic"}}
    end
  end
end

defmodule MyApp.MathHelper do
  use OpenAI.Agent
  
  @impl true
  def configure do
    %{
      name: "math_helper",
      instructions: "You are a math helper. Only answer math-related questions.",
      input_guardrails: [MyApp.Guardrails.MathOnly]
    }
  end
end

# This will work
{:ok, result} = OpenAI.Agents.run(MyApp.MathHelper, "What is 2+2?")

# This will be rejected by the guardrail
{:error, {:guardrail_triggered, _}} = OpenAI.Agents.run(MyApp.MathHelper, "Tell me about dogs")
```

## Elixir-Specific Features

### 1. Process-Based Isolation

Each agent run is isolated in its own process, providing fault tolerance:

```elixir
# If an agent crashes, it doesn't affect your application
task1 = OpenAI.Agents.run_async(MyAgent, "Query 1")
task2 = OpenAI.Agents.run_async(MyAgent, "Query 2") 

# Even if task1 crashes, task2 continues
```

### 2. Concurrent Tool Execution

Tools are executed in parallel automatically:

```elixir
defmodule MyApp.SlowTool do
  use OpenAI.Agents.Tool
  
  @impl true
  def execute(_params, _context) do
    # These will run concurrently if the agent calls multiple tools
    Process.sleep(1000)
    {:ok, %{data: "result"}}
  end
end
```

### 3. GenStage-Based Streaming

The streaming implementation uses GenStage for proper backpressure handling:

```elixir
# The stream automatically handles backpressure
stream = OpenAI.Agents.stream(MyAgent, "Generate a long response")

# Process in batches with Flow (optional)
stream
|> Flow.from_enumerable(max_demand: 10)
|> Flow.map(&process_event/1)
|> Flow.run()
```

### 4. Telemetry Integration

Built-in telemetry for monitoring:

```elixir
# Attach to telemetry events
:telemetry.attach_many(
  "my-app-handler",
  [
    [:openai_agents, :run, :start],
    [:openai_agents, :run, :stop],
    [:openai_agents, :tool, :start],
    [:openai_agents, :tool, :stop]
  ],
  &MyApp.TelemetryHandler.handle_event/4,
  nil
)
```

### 5. Supervision and Fault Tolerance

The library uses OTP supervision for reliability:

```elixir
# Agents run under a DynamicSupervisor
# If a run fails, it's isolated and won't crash your system

# You can also configure restart strategies
config :openai_agents,
  runner_restart_strategy: :transient,
  max_restarts: 3
```

### 6. Registry-Based Agent Discovery

Agents can be discovered dynamically:

```elixir
# Register agents with custom names
defmodule MyApp.DynamicAgent do
  use OpenAI.Agent
  
  def start_link(opts) do
    name = Keyword.get(opts, :name)
    Registry.register(MyApp.AgentRegistry, name, __MODULE__)
    {:ok, self()}
  end
end

# Find and run agents dynamically
[{pid, module}] = Registry.lookup(MyApp.AgentRegistry, "custom_agent")
OpenAI.Agents.run(module, "Hello")
```

## API Reference

### Main Functions

- `OpenAI.Agents.run/3` - Run an agent synchronously
- `OpenAI.Agents.run_async/3` - Run an agent asynchronously  
- `OpenAI.Agents.stream/3` - Stream an agent's response

### Options

All functions accept these options:

- `:context` - Application-specific context
- `:timeout` - Maximum execution time (default: 60000ms)
- `:max_turns` - Maximum conversation turns (default: 10)
- `:trace_id` - Custom trace ID for debugging

### Behaviors

- `OpenAI.Agent` - Define an agent
- `OpenAI.Agents.Tool` - Define a tool
- `OpenAI.Agents.Guardrail` - Define a guardrail

## Configuration

Full configuration options in `config/config.exs`:

```elixir
config :openai_agents,
  # Required
  api_key: System.get_env("OPENAI_API_KEY"),
  
  # Optional
  base_url: "https://api.openai.com/v1",
  default_model: "gpt-4o",
  max_turns: 10,
  timeout: 60_000,
  
  # Telemetry and tracing
  trace_processors: [
    OpenAI.Agents.Tracing.ConsoleProcessor,
    {OpenAI.Agents.Tracing.FileProcessor, path: "/tmp/traces"}
  ],
  
  # Pool configuration for HTTP client
  pool_size: 10,
  pool_timeout: 5_000
```

## Common Patterns

### Error Handling

```elixir
case OpenAI.Agents.run(MyAgent, "Hello") do
  {:ok, result} -> 
    IO.puts(result.output)
    
  {:error, {:guardrail_triggered, {guardrail, reason, metadata}}} ->
    IO.puts("Guardrail #{guardrail} blocked: #{reason}")
    
  {:error, {:max_turns_exceeded, turns}} ->
    IO.puts("Agent exceeded #{turns} turns")
    
  {:error, {:api_error, status, body}} ->
    IO.puts("API error #{status}: #{body}")
    
  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end
```

### Testing Agents

```elixir
# In your tests
defmodule MyApp.AgentTest do
  use ExUnit.Case
  
  test "agent responds correctly" do
    # Use Bypass for mocking API calls
    bypass = Bypass.open()
    
    Application.put_env(:openai_agents, :base_url, "http://localhost:#{bypass.port}")
    
    Bypass.expect_once(bypass, "POST", "/responses", fn conn ->
      Plug.Conn.resp(conn, 200, Jason.encode!(%{
        output: [%{type: "text", text: "Hello!"}],
        usage: %{total_tokens: 10}
      }))
    end)
    
    assert {:ok, result} = OpenAI.Agents.run(MyApp.Assistant, "Hi")
    assert result.output == "Hello!"
  end
end
```

## Learn More

- [Full API Documentation](https://hexdocs.pm/openai_agents)
- [GitHub Repository](https://github.com/yourusername/openai_agents)
- [OpenAI Responses API Docs](https://platform.openai.com/docs)

## License

MIT License - see LICENSE file for details.