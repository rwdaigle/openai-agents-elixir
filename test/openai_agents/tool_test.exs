defmodule OpenAI.Agents.ToolTest do
  use ExUnit.Case, async: true

  defmodule TestTool do
    use OpenAI.Agents.Tool

    @impl true
    def schema do
      %{
        name: "test_tool",
        description: "A test tool",
        parameters: %{
          type: "object",
          properties: %{
            input: %{type: "string"}
          },
          required: ["input"]
        }
      }
    end

    @impl true
    def execute(%{"input" => input}, _context) do
      {:ok, %{output: "Processed: #{input}"}}
    end
  end

  defmodule ErrorTool do
    use OpenAI.Agents.Tool

    @impl true
    def schema do
      %{
        name: "error_tool",
        description: "A tool that errors",
        parameters: %{type: "object", properties: %{}}
      }
    end

    @impl true
    def execute(_params, _context) do
      raise "Tool error!"
    end

    @impl true
    def on_error(error, _params, _context) do
      {:error, "Handled: #{Exception.message(error)}"}
    end
  end

  describe "validate_tool/1" do
    test "validates a correct tool module" do
      assert :ok = OpenAI.Agents.Tool.validate_tool(TestTool)
    end

    test "validates schema structure" do
      defmodule InvalidSchemaTool do
        use OpenAI.Agents.Tool

        @impl true
        def schema do
          %{name: "invalid"}  # Missing required fields
        end

        @impl true
        def execute(_, _), do: {:ok, nil}
      end

      assert {:error, "Missing required field: description"} = 
        OpenAI.Agents.Tool.validate_tool(InvalidSchemaTool)
    end
  end

  describe "to_openai_format/1" do
    test "converts tool to OpenAI format" do
      result = OpenAI.Agents.Tool.to_openai_format(TestTool)

      assert result == %{
        type: "function",
        name: "test_tool",
        description: "A test tool",
        function: %{
          parameters: %{
            type: "object",
            properties: %{
              input: %{type: "string"}
            },
            required: ["input"]
          }
        }
      }
    end
  end

  describe "tool execution" do
    test "executes tool successfully" do
      assert {:ok, %{output: "Processed: hello"}} = 
        TestTool.execute(%{"input" => "hello"}, %{})
    end

    test "handles errors with on_error callback" do
      assert {:error, "Handled: Tool error!"} = 
        ErrorTool.on_error(%RuntimeError{message: "Tool error!"}, %{}, %{})
    end
  end
end