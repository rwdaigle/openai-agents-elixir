defmodule OpenAI.AgentTest do
  use ExUnit.Case, async: true

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

  defmodule DynamicInstructionsAgent do
    use OpenAI.Agent

    @impl true
    def configure do
      %{
        name: "dynamic_agent",
        instructions: fn context ->
          "Hello #{context.user_context.name}"
        end
      }
    end
  end

  describe "get_config/1" do
    test "returns agent configuration" do
      config = OpenAI.Agent.get_config(TestAgent)
      
      assert config.name == "test_agent"
      assert config.instructions == "You are a test agent."
    end
  end

  describe "get_instructions/2" do
    test "returns static instructions" do
      {:ok, instructions} = OpenAI.Agent.get_instructions(TestAgent, %{})
      assert instructions == "You are a test agent."
    end

    test "resolves dynamic instructions" do
      context = %{user_context: %{name: "Alice"}}
      {:ok, instructions} = OpenAI.Agent.get_instructions(DynamicInstructionsAgent, context)
      assert instructions == "Hello Alice"
    end
  end

  describe "validate_agent/1" do
    test "validates a correct agent module" do
      assert :ok = OpenAI.Agent.validate_agent(TestAgent)
    end

    test "rejects module without configure/0" do
      defmodule InvalidAgent do
      end

      assert {:error, "Agent module must implement configure/0"} = 
        OpenAI.Agent.validate_agent(InvalidAgent)
    end
  end
end