defmodule OpenAI.Agents.RunnerTest do
  use ExUnit.Case, async: true

  alias OpenAI.Agents.Runner

  defmodule TestAgent do
    use OpenAI.Agent

    @impl true
    def configure do
      %{
        name: "test_agent",
        instructions: "You are a test agent."
      }
    end
  end

  describe "Runner state management" do
    test "initializes with nil response_id" do
      {:ok, runner} = Runner.start_link(TestAgent, "test input", [])
      state = :sys.get_state(runner)
      assert state.response_id == nil
      GenServer.stop(runner)
    end

    test "response_id field exists in Runner struct" do
      runner_struct = %Runner{}
      assert Map.has_key?(runner_struct, :response_id)
    end
  end

  describe "response_id state management" do
    test "stores response_id when present in state" do
      state = %Runner{
        response_id: "test-response-id-123",
        stream_producer: nil
      }

      assert state.response_id == "test-response-id-123"
    end

    test "handles nil response_id correctly" do
      state = %Runner{
        response_id: nil,
        stream_producer: nil
      }

      assert state.response_id == nil
    end

    test "response_id can be updated in state" do
      initial_state = %Runner{response_id: nil}
      updated_state = %{initial_state | response_id: "new-response-id"}

      assert initial_state.response_id == nil
      assert updated_state.response_id == "new-response-id"
    end
  end
end
