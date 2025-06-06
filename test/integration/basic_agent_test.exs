defmodule OpenAI.Agents.Integration.BasicAgentTest do
  use ExUnit.Case, async: false
  @moduletag :remote

  defmodule Assistant do
    use OpenAI.Agent

    @impl true
    def configure do
      %{
        name: "assistant",
        instructions: "You are a helpful assistant that responds concisely."
      }
    end
  end

  defmodule HaikuAgent do
    use OpenAI.Agent

    @impl true
    def configure do
      %{
        name: "haiku_bot",
        instructions: "You only respond in haikus.",
        model: "gpt-4.1-mini",
        model_settings: %{
          temperature: 0.7,
          max_tokens: 100
        }
      }
    end

    @impl true
    def on_start(_context, state) do
      # Test lifecycle callback
      send(self(), :agent_started)
      {:ok, state}
    end
  end

  defmodule QAAgent do
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

  describe "basic agent operations" do
    @tag :remote
    test "simple Q&A agent responds to questions" do
      {:ok, result} =
        OpenAI.Agents.run(Assistant, "What is the capital of France? Answer in one word.")

      assert result.output =~ "Paris"
      assert result.usage.total_tokens > 0
      assert result.trace_id
      assert result.duration_ms > 0
    end

    @tag :remote
    test "haiku agent responds in haiku format" do
      {:ok, result} = OpenAI.Agents.run(HaikuAgent, "Write about recursion")

      # Haikus typically have 3 lines
      lines = String.split(result.output, "\n") |> Enum.reject(&(&1 == ""))
      assert length(lines) >= 3
      assert result.usage.total_tokens > 0
    end

    @tag :remote
    test "agent lifecycle callbacks are called" do
      {:ok, _result} = OpenAI.Agents.run(HaikuAgent, "Hello")

      assert_receive :agent_started, 5000
    end

    @tag :remote
    test "QA agent provides informative responses" do
      {:ok, result} = OpenAI.Agents.run(QAAgent, "What is Elixir programming language?")

      # Should mention key Elixir concepts
      output_lower = String.downcase(result.output)
      assert String.contains?(output_lower, "elixir")

      assert Enum.any?(
               ["functional", "erlang", "beam", "concurrent"],
               &String.contains?(output_lower, &1)
             )
    end

    @tag :remote
    test "agent with custom model settings" do
      {:ok, result} = OpenAI.Agents.run(HaikuAgent, "Describe the moon")

      # With max_tokens: 100, response should be relatively short
      assert String.length(result.output) < 500
    end
  end

  describe "async execution" do
    @tag :remote
    test "run_async returns a Task" do
      task = OpenAI.Agents.run_async(Assistant, "Count to 3")

      assert %Task{} = task
      {:ok, result} = Task.await(task)

      assert result.output
      assert result.usage.total_tokens > 0
    end

    @tag :remote
    test "multiple async runs can execute concurrently" do
      task1 = OpenAI.Agents.run_async(Assistant, "What is 2+2?")
      task2 = OpenAI.Agents.run_async(Assistant, "What is 3+3?")

      {:ok, result1} = Task.await(task1)
      {:ok, result2} = Task.await(task2)

      assert result1.output =~ "4"
      assert result2.output =~ "6"
    end
  end
end
