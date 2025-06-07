defmodule OpenAI.Agents.Integration.MultiTurnConversationTest do
  use ExUnit.Case, async: false
  @moduletag :remote

  defmodule ConversationAgent do
    use OpenAI.Agent

    @impl true
    def configure do
      %{
        name: "conversation_agent",
        instructions:
          "You are a helpful assistant. Keep responses brief and remember the conversation context."
      }
    end
  end

  defmodule StatefulAgent do
    use OpenAI.Agent

    @impl true
    def configure do
      %{
        name: "stateful_agent",
        instructions:
          "You are an assistant that remembers previous interactions. When asked about previous messages, refer to them specifically."
      }
    end
  end

  describe "multi-turn conversations" do
    @tag :remote
    test "maintains conversation context across multiple turns" do
      {:ok, result1} = OpenAI.Agents.run(ConversationAgent, "My name is Alice. What's 2+2?")
      assert result1.output =~ "4"
      assert result1.response_id != nil

      {:ok, result2} =
        OpenAI.Agents.run(ConversationAgent, "What's my name?",
          previous_response_id: result1.response_id
        )

      assert String.contains?(String.downcase(result2.output), "alice")
    end

    @tag :remote
    test "conversation context works with streaming" do
      # First get response_id from non-streaming call
      {:ok, result1} = OpenAI.Agents.run(ConversationAgent, "I like cats. Tell me a cat fact.")
      assert result1.response_id != nil

      # Then use streaming with previous_response_id
      stream2 =
        OpenAI.Agents.stream(ConversationAgent, "What did I say I like?",
          previous_response_id: result1.response_id
        )

      events2 = Enum.to_list(stream2)

      text2 =
        events2
        |> Enum.filter(&match?(%OpenAI.Agents.Events.TextDelta{}, &1))
        |> Enum.map(& &1.text)
        |> Enum.join("")

      assert String.contains?(String.downcase(text2), "cat")
    end

    @tag :remote
    test "response_id is captured and used in subsequent requests" do
      {:ok, result1} = OpenAI.Agents.run(StatefulAgent, "Remember this number: 42")

      assert result1.response_id != nil
      assert is_binary(result1.response_id)

      {:ok, result2} =
        OpenAI.Agents.run(StatefulAgent, "What number did I ask you to remember?",
          previous_response_id: result1.response_id
        )

      assert String.contains?(result2.output, "42")

      assert result2.response_id != nil
      assert result2.response_id != result1.response_id
    end

    @tag :remote
    test "multiple conversation turns maintain context" do
      {:ok, result1} = OpenAI.Agents.run(ConversationAgent, "I'm planning a trip to Paris.")
      assert result1.output
      assert result1.response_id != nil

      {:ok, result2} =
        OpenAI.Agents.run(ConversationAgent, "What's the weather like there?",
          previous_response_id: result1.response_id
        )

      assert String.contains?(String.downcase(result2.output), "paris")
      assert result2.response_id != nil

      {:ok, result3} =
        OpenAI.Agents.run(ConversationAgent, "What city are we talking about?",
          previous_response_id: result2.response_id
        )

      assert String.contains?(String.downcase(result3.output), "paris")
    end

    @tag :remote
    test "conversation context persists through tool usage" do
      defmodule TestTool do
        use OpenAI.Agents.Tool

        @impl true
        def schema do
          %{
            name: "get_info",
            description: "Get information about a topic",
            parameters: %{
              type: "object",
              properties: %{
                topic: %{type: "string", description: "The topic to get info about"}
              },
              required: ["topic"]
            }
          }
        end

        @impl true
        def execute(%{"topic" => topic}, _context) do
          {:ok, %{info: "Information about #{topic}"}}
        end
      end

      defmodule ToolAgent do
        use OpenAI.Agent

        @impl true
        def configure do
          %{
            name: "tool_agent",
            instructions:
              "You are an assistant with access to tools. Remember conversation context.",
            tools: [TestTool]
          }
        end
      end

      {:ok, result1} =
        OpenAI.Agents.run(ToolAgent, "My favorite color is blue. Get info about colors.")

      assert result1.output
      assert result1.response_id != nil

      {:ok, result2} =
        OpenAI.Agents.run(ToolAgent, "What's my favorite color?",
          previous_response_id: result1.response_id
        )

      assert String.contains?(String.downcase(result2.output), "blue")
    end
  end
end
