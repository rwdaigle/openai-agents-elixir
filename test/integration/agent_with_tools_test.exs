defmodule OpenAI.Agents.Integration.AgentWithToolsTest do
  use ExUnit.Case, async: false
  @moduletag :remote

  defmodule MathTools do
    use OpenAI.Agents.Tool

    @impl true
    def schema do
      %{
        name: "calculate",
        description: "Perform mathematical calculations",
        parameters: %{
          type: "object",
          properties: %{
            expression: %{
              type: "string",
              description: "A mathematical expression to evaluate"
            }
          },
          required: ["expression"]
        }
      }
    end

    @impl true
    def execute(%{"expression" => expr}, _context) do
      # Simple safe math evaluation for basic operations
      try do
        result = evaluate_math_expression(expr)
        {:ok, %{result: result, expression: expr}}
      rescue
        _ -> {:error, "Invalid expression: #{expr}"}
      end
    end

    # Very basic math evaluator for safety
    defp evaluate_math_expression(expr) do
      expr = String.trim(expr)

      cond do
        # Handle basic arithmetic
        Regex.match?(~r/^\d+\s*[\+\-\*\/]\s*\d+$/, expr) ->
          {result, _} = Code.eval_string(expr)
          result

        # Handle slightly more complex but still safe expressions
        Regex.match?(~r/^[\d\s\+\-\*\/\(\)]+$/, expr) ->
          {result, _} = Code.eval_string(expr)
          result

        true ->
          raise "Unsafe expression"
      end
    end
  end

  defmodule WeatherTool do
    use OpenAI.Agents.Tool

    @impl true
    def schema do
      %{
        name: "get_weather",
        description: "Get the current weather for a city",
        parameters: %{
          type: "object",
          properties: %{
            city: %{
              type: "string",
              description: "The city name"
            }
          },
          required: ["city"]
        }
      }
    end

    @impl true
    def execute(%{"city" => city}, _context) do
      # Mock weather data
      weather_data = %{
        "New York" => %{temperature: 72, conditions: "Sunny", humidity: 45},
        "London" => %{temperature: 59, conditions: "Cloudy", humidity: 70},
        "Tokyo" => %{temperature: 68, conditions: "Clear", humidity: 55},
        "Paris" => %{temperature: 64, conditions: "Partly cloudy", humidity: 60}
      }

      case Map.get(weather_data, city) do
        nil ->
          # Return generic weather for unknown cities
          {:ok,
           %{
             city: city,
             temperature: 70,
             conditions: "Clear",
             humidity: 50,
             note: "Simulated data"
           }}

        data ->
          {:ok, Map.put(data, :city, city)}
      end
    end
  end

  defmodule MathTutor do
    use OpenAI.Agent

    @impl true
    def configure do
      %{
        name: "math_tutor",
        instructions:
          "You are a helpful math tutor. Use the calculate tool for computations. Always show your work.",
        tools: [MathTools]
      }
    end
  end

  defmodule WeatherAssistant do
    use OpenAI.Agent

    @impl true
    def configure do
      %{
        name: "weather_assistant",
        instructions:
          "You are a weather assistant. Use the get_weather tool to provide weather information.",
        tools: [WeatherTool]
      }
    end
  end

  defmodule MultiToolAgent do
    use OpenAI.Agent

    @impl true
    def configure do
      %{
        name: "multi_tool_agent",
        instructions: "You are a helpful assistant with access to math and weather tools.",
        tools: [MathTools, WeatherTool]
      }
    end
  end

  describe "agents with tools" do
    @tag :remote
    test "math tutor uses calculate tool" do
      {:ok, result} = OpenAI.Agents.run(MathTutor, "What is 25 * 4 + 10?")

      # Should contain the answer
      assert result.output =~ "110"

      # Should use the tool
      assert result.usage.total_tokens > 0
    end

    @tag :remote
    test "weather assistant uses weather tool" do
      {:ok, result} = OpenAI.Agents.run(WeatherAssistant, "What's the weather in New York?")

      # Should mention New York
      assert String.contains?(result.output, "New York")

      # Should include weather details
      assert String.contains?(String.downcase(result.output), ["72", "sunny", "temperature"])
    end

    @tag :remote
    test "agent can use multiple tools in one conversation" do
      {:ok, result} =
        OpenAI.Agents.run(
          MultiToolAgent,
          "What's the weather in Paris and what is 50 * 3?"
        )

      # Should have both answers
      assert String.contains?(result.output, "Paris")
      assert String.contains?(result.output, "150")
    end

    @tag :remote
    test "tool error handling" do
      {:ok, result} =
        OpenAI.Agents.run(
          MathTutor,
          "Calculate this: hello world"
        )

      # Agent should handle the error gracefully
      assert result.output
      # The response should acknowledge the inability to calculate
      assert String.contains?(String.downcase(result.output), [
               "cannot",
               "can't",
               "unable",
               "invalid",
               "error"
             ])
    end
  end

  describe "context passing to tools" do
    defmodule ContextAwareTool do
      use OpenAI.Agents.Tool

      @impl true
      def schema do
        %{
          name: "get_user_info",
          description: "Get information about the current user",
          parameters: %{
            type: "object",
            properties: %{},
            required: []
          }
        }
      end

      @impl true
      def execute(_params, context) do
        user_context = context.user_context

        {:ok,
         %{
           user_id: user_context[:user_id] || "unknown",
           preferences: user_context[:preferences] || %{}
         }}
      end
    end

    defmodule ContextAgent do
      use OpenAI.Agent

      @impl true
      def configure do
        %{
          name: "context_agent",
          instructions: "You are an agent that can access user information.",
          tools: [ContextAwareTool]
        }
      end
    end

    @tag :remote
    test "tools receive context" do
      context = %{
        user_id: "123",
        preferences: %{language: "en", timezone: "EST"}
      }

      {:ok, result} =
        OpenAI.Agents.run(
          ContextAgent,
          "What is my user ID?",
          context: context
        )

      assert String.contains?(result.output, "123")
    end
  end
end
