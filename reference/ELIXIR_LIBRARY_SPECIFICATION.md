# Elixir OpenAI Agents Library Specification

This specification outlines the design of an idiomatic Elixir library that provides the same agentic functionality as the Python openai-agents library.

## Overview

The Elixir library will leverage OTP patterns and Elixir's strengths in concurrency, fault tolerance, and real-time systems to provide a robust framework for building AI agents.

## Core Architecture

### 1. Agent Definition

Agents will be defined using Elixir modules with specific behaviors:

```elixir
defmodule MyApp.WeatherAgent do
  use OpenAI.Agent

  @impl true
  def configure do
    %{
      name: "weather_assistant",
      instructions: "You are a helpful weather assistant.",
      model: "gpt-4o",
      model_settings: %{
        temperature: 0.7,
        max_tokens: 1000
      },
      tools: [
        MyApp.Tools.GetWeather,
        MyApp.Tools.GetForecast
      ],
      handoffs: [
        MyApp.SpanishAgent
      ],
      output_schema: MyApp.Schemas.WeatherReport
    }
  end

  @impl true
  def on_start(context, agent_state) do
    # Optional lifecycle callback
    {:ok, agent_state}
  end
end
```

### 2. Agent Supervision Tree

Each agent run will be managed by a supervision tree:

```
OpenAI.Agents.Supervisor
├── OpenAI.Agents.Registry (Registry for agent processes)
├── OpenAI.Agents.RunSupervisor (DynamicSupervisor)
│   ├── OpenAI.Agents.Runner (GenServer for each run)
│   │   ├── OpenAI.Agents.ContextServer (Agent for context state)
│   │   ├── OpenAI.Agents.ToolExecutor (Task.Supervisor)
│   │   └── OpenAI.Agents.StreamHandler (GenStage producer)
│   └── ...
└── OpenAI.Agents.TracingSupervisor
    └── OpenAI.Agents.TraceCollector (GenServer)
```

### 3. Context Management

Context will be managed using Elixir's Agent for thread-safe state:

```elixir
defmodule MyApp.AgentContext do
  defstruct [:user_id, :database, :session_data]
  
  @behaviour OpenAI.Agents.Context
  
  @impl true
  def init(opts) do
    %__MODULE__{
      user_id: opts[:user_id],
      database: MyApp.Repo,
      session_data: %{}
    }
  end
end
```

### 4. Tool System

Tools will be defined as modules with a specific behavior:

```elixir
defmodule MyApp.Tools.GetWeather do
  use OpenAI.Agents.Tool

  @impl true
  def schema do
    %{
      name: "get_weather",
      description: "Get weather for a city",
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
  def execute(%{"city" => city}, context) do
    # Tool implementation
    case WeatherAPI.get_weather(city) do
      {:ok, weather} -> {:ok, weather}
      {:error, reason} -> {:error, "Failed to get weather: #{reason}"}
    end
  end
end
```

### 5. Streaming with GenStage

Streaming responses will use GenStage for backpressure and flow control:

```elixir
defmodule OpenAI.Agents.StreamProducer do
  use GenStage

  def start_link(opts) do
    GenStage.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    {:producer, opts}
  end

  @impl true
  def handle_demand(demand, state) when demand > 0 do
    events = fetch_events(state, demand)
    {:noreply, events, state}
  end
end

defmodule OpenAI.Agents.StreamConsumer do
  use GenStage

  @impl true
  def handle_events(events, _from, state) do
    Enum.each(events, fn event ->
      handle_stream_event(event, state)
    end)
    {:noreply, [], state}
  end
end
```

### 6. Runner Implementation

The runner will be a GenServer managing agent execution:

```elixir
defmodule OpenAI.Agents.Runner do
  use GenServer

  defstruct [
    :agent_module,
    :context,
    :conversation,
    :current_turn,
    :max_turns,
    :trace_id,
    :stream_producer
  ]

  def run(agent_module, input, opts \\ []) do
    {:ok, runner} = start_link(agent_module, input, opts)
    GenServer.call(runner, :run, :infinity)
  end

  def run_async(agent_module, input, opts \\ []) do
    {:ok, runner} = start_link(agent_module, input, opts)
    Task.async(fn ->
      GenServer.call(runner, :run, :infinity)
    end)
  end

  def stream(agent_module, input, opts \\ []) do
    {:ok, runner} = start_link(agent_module, input, opts)
    {:ok, producer} = GenServer.call(runner, :get_stream_producer)
    
    Stream.resource(
      fn -> producer end,
      fn producer ->
        case GenStage.call(producer, :next_event, 5000) do
          {:ok, event} -> {[event], producer}
          :done -> {:halt, producer}
        end
      end,
      fn producer -> GenStage.stop(producer) end
    )
  end
end
```

### 7. Guardrails

Guardrails will be implemented as pluggable modules:

```elixir
defmodule MyApp.Guardrails.ContentFilter do
  use OpenAI.Agents.Guardrail

  @impl true
  def validate_input(input, context) do
    if contains_prohibited_content?(input) do
      {:error, "Content policy violation", %{reason: "prohibited_content"}}
    else
      :ok
    end
  end

  @impl true
  def validate_output(output, context) do
    # Similar validation for outputs
    :ok
  end
end
```

### 8. Handoffs

Handoffs will be implemented as special tools with Registry-based agent discovery:

```elixir
defmodule OpenAI.Agents.Handoff do
  defmacro handoff(target_agent, opts \\ []) do
    quote do
      %OpenAI.Agents.HandoffTool{
        target: unquote(target_agent),
        description: unquote(opts[:description]),
        input_filter: unquote(opts[:input_filter]),
        input_schema: unquote(opts[:input_schema])
      }
    end
  end
end
```

### 9. Model Adapter

The OpenAI Responses API adapter:

```elixir
defmodule OpenAI.Agents.Models.ResponsesAdapter do
  @behaviour OpenAI.Agents.ModelAdapter

  @impl true
  def create_completion(request, config) do
    client = OpenAI.Client.new(api_key: config.api_key)
    OpenAI.Responses.create(client, request)
  end

  @impl true
  def create_stream(request, config) do
    client = OpenAI.Client.new(api_key: config.api_key)
    OpenAI.Responses.create_stream(client, request)
  end
end
```

### 10. Tracing with Telemetry

The library will use Telemetry for instrumentation:

```elixir
defmodule OpenAI.Agents.Telemetry do
  def setup do
    events = [
      [:openai, :agents, :run, :start],
      [:openai, :agents, :run, :stop],
      [:openai, :agents, :tool, :start],
      [:openai, :agents, :tool, :stop],
      [:openai, :agents, :handoff, :start],
      [:openai, :agents, :api, :request, :start],
      [:openai, :agents, :api, :request, :stop]
    ]

    :telemetry.attach_many(
      "openai-agents-handler",
      events,
      &handle_event/4,
      nil
    )
  end

  defp handle_event(event, measurements, metadata, _config) do
    # Handle telemetry events
  end
end
```

### 11. Schema Validation with Ecto

Output schemas will use Ecto changesets for validation:

```elixir
defmodule MyApp.Schemas.WeatherReport do
  use Ecto.Schema
  import Ecto.Changeset

  @derive Jason.Encoder
  embedded_schema do
    field :temperature, :integer
    field :conditions, :string
    field :humidity, :integer
    field :wind_speed, :float
  end

  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:temperature, :conditions, :humidity, :wind_speed])
    |> validate_required([:temperature, :conditions])
    |> validate_number(:humidity, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
  end
end
```

### 12. MCP Support

MCP servers will be managed as separate processes:

```elixir
defmodule OpenAI.Agents.MCP.Server do
  use GenServer

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: via_tuple(config.name))
  end

  defp via_tuple(name) do
    {:via, Registry, {OpenAI.Agents.MCP.Registry, name}}
  end

  @impl true
  def handle_call({:list_tools}, _from, state) do
    {:reply, {:ok, state.tools}, state}
  end

  @impl true
  def handle_call({:execute_tool, tool_name, params}, _from, state) do
    # Execute MCP tool
  end
end
```

### 13. Configuration

Configuration will use Elixir's config system:

```elixir
# config/config.exs
config :openai_agents,
  default_model: "gpt-4o",
  api_key: {:system, "OPENAI_API_KEY"},
  max_turns: 10,
  timeout: 60_000,
  trace_processors: [
    OpenAI.Agents.Tracing.ConsoleProcessor,
    {OpenAI.Agents.Tracing.FileProcessor, path: "/tmp/traces"}
  ]
```

### 14. Error Handling

Custom exceptions for different failure modes:

```elixir
defmodule OpenAI.Agents.Errors do
  defmodule GuardrailError do
    defexception [:message, :type, :metadata]
  end

  defmodule MaxTurnsExceeded do
    defexception [:message, :turns, :agent]
  end

  defmodule ToolExecutionError do
    defexception [:message, :tool, :params, :error]
  end
end
```

### 15. Testing Support

Test helpers and mocks:

```elixir
defmodule OpenAI.Agents.Test do
  def mock_agent(name, responses) do
    # Create a mock agent for testing
  end

  def assert_tool_called(tool_module, params) do
    # Assert a tool was called with specific params
  end

  def capture_stream_events(stream) do
    # Capture all events from a stream for testing
  end
end
```

## API Examples

### Basic Usage

```elixir
# Define an agent
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

# Stream responses
MyApp.Assistant
|> OpenAI.Agents.stream("Tell me a story")
|> Enum.each(fn event ->
  case event do
    %TextDelta{text: text} -> IO.write(text)
    %ToolCall{name: name} -> IO.puts("\nCalling tool: #{name}")
    _ -> :ok
  end
end)
```

### With Context

```elixir
context = %MyApp.Context{
  user_id: "123",
  preferences: %{language: "es"}
}

{:ok, result} = OpenAI.Agents.run(
  MyApp.Assistant, 
  "Hello",
  context: context
)
```

### Multi-Agent with Handoffs

```elixir
defmodule MyApp.Orchestrator do
  use OpenAI.Agent

  @impl true
  def configure do
    %{
      name: "orchestrator",
      instructions: "Route requests to appropriate specialists.",
      handoffs: [
        MyApp.MathExpert,
        MyApp.WritingAssistant,
        MyApp.CodeHelper
      ]
    }
  end
end
```

## Benefits of Elixir Implementation

1. **Concurrency**: Natural handling of parallel tool execution
2. **Fault Tolerance**: Supervisor trees ensure resilience
3. **Real-time**: GenStage provides excellent streaming capabilities
4. **Scalability**: Process-based architecture scales naturally
5. **Observability**: Built-in tracing with Telemetry
6. **Type Safety**: Specs and dialyzer support
7. **Hot Code Reloading**: Update agents without downtime
8. **Pattern Matching**: Clean handling of different response types

## Migration Path

Python users can migrate by:
1. Converting Python tool functions to Elixir modules
2. Replacing decorators with module attributes
3. Using Ecto schemas for validation
4. Leveraging GenServers for stateful operations

This specification provides a foundation for building a powerful, idiomatic Elixir library that provides the same agentic capabilities using the OpenAI Responses API while leveraging Elixir's unique strengths in concurrency, fault tolerance, and real-time processing.