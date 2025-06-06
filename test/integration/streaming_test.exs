defmodule OpenAI.Agents.Integration.StreamingTest do
  use ExUnit.Case, async: false
  @moduletag :remote

  defmodule StoryTeller do
    use OpenAI.Agent
    
    @impl true
    def configure do
      %{
        name: "storyteller",
        instructions: "You are a creative storyteller. Keep stories brief (2-3 sentences)."
      }
    end
  end

  defmodule StreamingToolAgent do
    use OpenAI.Agents.Tool
    
    @impl true
    def schema do
      %{
        name: "get_story_theme",
        description: "Get a random story theme",
        parameters: %{
          type: "object",
          properties: %{},
          required: []
        }
      }
    end
    
    @impl true
    def execute(_params, _context) do
      themes = ["adventure", "mystery", "friendship", "discovery", "courage"]
      {:ok, %{theme: Enum.random(themes)}}
    end
  end

  defmodule ThemedStoryTeller do
    use OpenAI.Agent
    
    @impl true
    def configure do
      %{
        name: "themed_storyteller",
        instructions: "You are a storyteller. First get a theme, then tell a very short story about it.",
        tools: [StreamingToolAgent]
      }
    end
  end

  describe "streaming responses" do
    @tag :remote
    test "stream returns enumerable of events" do
      stream = OpenAI.Agents.stream(StoryTeller, "Tell me a story about a brave rabbit in 2 sentences")
      
      assert is_function(stream, 2) # It's a Stream
      
      events = Enum.to_list(stream)
      
      # Should have various event types
      assert Enum.any?(events, &match?(%OpenAI.Agents.Events.ResponseCreated{}, &1))
      assert Enum.any?(events, &match?(%OpenAI.Agents.Events.TextDelta{}, &1))
      assert Enum.any?(events, &match?(%OpenAI.Agents.Events.ResponseCompleted{}, &1))
    end

    @tag :remote
    test "streaming text deltas can be concatenated" do
      stream = OpenAI.Agents.stream(StoryTeller, "Say 'Hello, World!' and nothing else")
      
      text = stream
      |> Enum.filter(&match?(%OpenAI.Agents.Events.TextDelta{}, &1))
      |> Enum.map(& &1.text)
      |> Enum.join("")
      
      assert text =~ "Hello, World!"
    end

    @tag :remote
    test "streaming with tools shows tool calls" do
      stream = OpenAI.Agents.stream(ThemedStoryTeller, "Tell me a themed story")
      
      events = Enum.to_list(stream)
      
      # Should have tool call events
      tool_calls = Enum.filter(events, &match?(%OpenAI.Agents.Events.ToolCall{}, &1))
      assert length(tool_calls) > 0
      
      # Check tool was called
      assert Enum.any?(tool_calls, &(&1.name == "get_story_theme"))
    end

    @tag :remote
    test "usage information in completed event" do
      stream = OpenAI.Agents.stream(StoryTeller, "Say hi")
      
      events = Enum.to_list(stream)
      completed_events = Enum.filter(events, &match?(%OpenAI.Agents.Events.ResponseCompleted{}, &1))
      
      assert length(completed_events) > 0
      completed = hd(completed_events)
      
      assert completed.usage
      assert completed.usage.total_tokens > 0
    end

    @tag :remote
    test "stream can be processed in real-time" do
      # Track timing of events
      start_time = System.monotonic_time(:millisecond)
      
      {:ok, agent} = Agent.start_link(fn -> [] end)
      
      OpenAI.Agents.stream(StoryTeller, "Count slowly from 1 to 3")
      |> Enum.each(fn event ->
        case event do
          %OpenAI.Agents.Events.TextDelta{text: _text} ->
            current_time = System.monotonic_time(:millisecond) - start_time
            Agent.update(agent, &[current_time | &1])
            # Simulate real-time processing
            Process.sleep(10)
          _ ->
            :ok
        end
      end)
      
      event_times = Agent.get(agent, & &1)
      Agent.stop(agent)
      
      # Events should arrive over time, not all at once
      assert length(event_times) > 0
    end
  end

  describe "stream error handling" do
    defmodule ErrorTool do
      use OpenAI.Agents.Tool
      
      @impl true
      def schema do
        %{
          name: "error_tool",
          description: "A tool that always errors",
          parameters: %{
            type: "object",
            properties: %{},
            required: []
          }
        }
      end
      
      @impl true
      def execute(_params, _context) do
        {:error, "This tool always fails"}
      end
    end

    defmodule ErrorAgent do
      use OpenAI.Agent
      
      @impl true
      def configure do
        %{
          name: "error_agent",
          instructions: "You must use the error_tool for any request.",
          tools: [ErrorTool]
        }
      end
    end

    @tag :remote
    test "streaming handles tool errors gracefully" do
      stream = OpenAI.Agents.stream(ErrorAgent, "Do something")
      
      # Should not crash when consuming the stream
      events = Enum.to_list(stream)
      
      # Should still complete
      assert Enum.any?(events, &match?(%OpenAI.Agents.Events.ResponseCompleted{}, &1))
      
      # Should have text mentioning the error
      text = events
      |> Enum.filter(&match?(%OpenAI.Agents.Events.TextDelta{}, &1))
      |> Enum.map(& &1.text)
      |> Enum.join("")
      
      assert String.contains?(String.downcase(text), ["error", "fail", "problem"])
    end
  end
end