# OpenAI Agents for Elixir

A powerful, idiomatic Elixir library for building AI agents using OpenAI's Responses API. This library provides a comprehensive framework for creating agents that can use tools, delegate to other agents, validate inputs/outputs, and stream responses in real-time.

## Features

- 🤖 **Agent Definition** - Define agents with instructions, tools, and behaviors using Elixir modules
- 🔧 **Tool System** - Create custom tools that agents can use during execution
- 🔄 **Handoffs** - Enable agents to delegate tasks to specialized sub-agents
- 🛡️ **Guardrails** - Validate inputs and outputs with custom guardrail modules
- 📡 **Streaming** - Real-time response streaming with GenStage for backpressure management
- 📊 **Telemetry** - Built-in instrumentation for monitoring and debugging
- 🎯 **Type Safety** - Structured output validation with Ecto schemas
- 💪 **Fault Tolerance** - Supervision trees ensure resilience
- ⚡ **Concurrent** - Parallel tool execution leveraging Elixir's concurrency

## Installation

Add `openai_agents` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:openai_agents, "~> 0.1.0"}
  ]
end
```

## Quick Start

### 1. Define an Agent

```elixir
defmodule MyApp.Assistant do
  use OpenAI.Agent
  
  @impl true
  def configure do
    %{
      name: "assistant",
      instructions: "You are a helpful assistant.",
      model: "gpt-4o",
      tools: [MyApp.Tools.Calculator]
    }
  end
end
```

### 2. Create a Tool

```elixir
defmodule MyApp.Tools.Calculator do
  use OpenAI.Agents.Tool
  
  @impl true
  def schema do
    %{
      name: "calculate",
      description: "Perform mathematical calculations",
      parameters: %{
        type: "object",
        properties: %{
          expression: %{type: "string", description: "Math expression to evaluate"}
        },
        required: ["expression"]
      }
    }
  end
  
  @impl true
  def execute(%{"expression" => expr}, _context) do
    try do
      result = Code.eval_string(expr)
      {:ok, %{result: elem(result, 0)}}
    rescue
      _ -> {:error, "Invalid expression"}
    end
  end
end
```

### 3. Run the Agent

```elixir
# Simple execution
{:ok, result} = OpenAI.Agents.run(MyApp.Assistant, "What is 25 * 4?")
IO.puts(result.output)

# With context
context = %{user_id: "123", session: "abc"}
{:ok, result} = OpenAI.Agents.run(MyApp.Assistant, "Hello", context: context)

# Streaming
MyApp.Assistant
|> OpenAI.Agents.stream("Tell me a story")
|> Enum.each(fn event ->
  case event do
    %OpenAI.Agents.Events.TextDelta{text: text} -> IO.write(text)
    %OpenAI.Agents.Events.ToolCall{name: name} -> IO.puts("\nCalling tool: #{name}")
    _ -> :ok
  end
end)
```

## Advanced Features

### Guardrails

Protect your agents with input and output validation:

```elixir
defmodule MyApp.Guardrails.ContentFilter do
  use OpenAI.Agents.Guardrail
  
  @impl true
  def validate_input(input, _context) do
    if String.contains?(input, ~w[inappropriate offensive]) do
      {:error, "Content policy violation", %{reason: "inappropriate_content"}}
    else
      :ok
    end
  end
end

defmodule MyApp.SafeAssistant do
  use OpenAI.Agent
  
  @impl true
  def configure do
    %{
      name: "safe_assistant",
      instructions: "You are a helpful, safe assistant.",
      input_guardrails: [MyApp.Guardrails.ContentFilter]
    }
  end
end
```

### Multi-Agent Systems with Handoffs

Build complex workflows with specialized agents:

```elixir
defmodule MyApp.Orchestrator do
  use OpenAI.Agent
  
  @impl true
  def configure do
    %{
      name: "orchestrator",
      instructions: "Route requests to the appropriate specialist.",
      handoffs: [
        MyApp.MathExpert,
        MyApp.WritingAssistant,
        MyApp.CodeHelper
      ]
    }
  end
end
```

### Structured Output

Ensure agents return data in the expected format:

```elixir
defmodule MyApp.Schemas.WeatherReport do
  use Ecto.Schema
  
  @derive Jason.Encoder
  embedded_schema do
    field :temperature, :integer
    field :conditions, :string
    field :humidity, :integer
  end
  
  def json_schema do
    %{
      type: "object",
      properties: %{
        temperature: %{type: "integer"},
        conditions: %{type: "string"},
        humidity: %{type: "integer"}
      },
      required: ["temperature", "conditions"]
    }
  end
end

defmodule MyApp.WeatherAgent do
  use OpenAI.Agent
  
  @impl true
  def configure do
    %{
      name: "weather_agent",
      instructions: "Provide weather information.",
      output_schema: MyApp.Schemas.WeatherReport
    }
  end
end
```

### Dynamic Instructions

Generate instructions based on runtime context:

```elixir
defmodule MyApp.PersonalizedAgent do
  use OpenAI.Agent
  
  @impl true
  def configure do
    %{
      name: "personalized_assistant",
      instructions: &dynamic_instructions/1
    }
  end
  
  defp dynamic_instructions(context) do
    user_name = context.user_context[:name] || "there"
    "You are a helpful assistant. Address the user as #{user_name}."
  end
end
```

## Configuration

Configure the library in your `config.exs`:

```elixir
config :openai_agents,
  api_key: System.get_env("OPENAI_API_KEY"),
  default_model: "gpt-4o",
  max_turns: 10,
  timeout: 60_000,
  trace_processors: [
    OpenAI.Agents.Tracing.ConsoleProcessor,
    {OpenAI.Agents.Tracing.FileProcessor, path: "/tmp/traces"}
  ]
```

## Telemetry Events

The library emits the following telemetry events:

- `[:openai_agents, :run, :start]` - Agent run started
- `[:openai_agents, :run, :stop]` - Agent run completed
- `[:openai_agents, :tool, :start]` - Tool execution started
- `[:openai_agents, :tool, :stop]` - Tool execution completed
- `[:openai_agents, :api, :request, :start]` - API request started
- `[:openai_agents, :api, :request, :stop]` - API request completed

Subscribe to events:

```elixir
:telemetry.attach(
  "my-handler",
  [:openai_agents, :run, :stop],
  fn event, measurements, metadata, _config ->
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    IO.puts("Agent run took #{duration_ms}ms")
  end,
  nil
)
```

## Architecture

The library uses OTP patterns for reliability and scalability:

- **GenServer** for managing agent execution state
- **GenStage** for streaming with backpressure control
- **Registry** for process discovery
- **DynamicSupervisor** for fault tolerance
- **Agent** for thread-safe context management

## Requirements

- Elixir 1.15+
- Erlang/OTP 25+
- OpenAI API key

## License

This library is released under the MIT License. See the LICENSE file for details.