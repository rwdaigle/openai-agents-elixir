defmodule OpenAI.Agents.Tool do
  @moduledoc """
  Defines the behavior for tools that agents can use.

  Tools are modules that implement specific functionality that agents can call
  during their execution.

  ## Example

      defmodule MyApp.Tools.GetWeather do
        use OpenAI.Agents.Tool
        
        @impl true
        def schema do
          %{
            name: "get_weather",
            description: "Get the current weather for a city",
            parameters: %{
              type: "object",
              properties: %{
                city: %{type: "string", description: "The city name"}
              },
              required: ["city"]
            }
          }
        end
        
        @impl true
        def execute(%{"city" => city}, context) do
          case WeatherAPI.get_weather(city) do
            {:ok, data} -> {:ok, data}
            {:error, reason} -> {:error, "Failed to get weather: \#{reason}"}
          end
        end
      end
  """

  @type schema :: %{
          name: String.t(),
          description: String.t(),
          parameters: map()
        }

  @type params :: map()
  @type context :: any()
  @type result :: {:ok, any()} | {:error, String.t()}

  @callback schema() :: schema()
  @callback execute(params(), context()) :: result()
  @callback on_error(Exception.t(), params(), context()) :: result()

  @optional_callbacks on_error: 3

  defmacro __using__(_opts) do
    quote do
      @behaviour OpenAI.Agents.Tool

      def on_error(error, _params, _context) do
        {:error, Exception.message(error)}
      end

      defoverridable on_error: 3
    end
  end

  @doc """
  Validates a tool module has the required callbacks and schema structure.
  """
  @spec validate_tool(module()) :: :ok | {:error, String.t()}
  def validate_tool(tool_module) do
    with :ok <- validate_callbacks(tool_module),
         :ok <- validate_schema(tool_module) do
      :ok
    end
  end

  defp validate_callbacks(module) do
    if function_exported?(module, :schema, 0) and function_exported?(module, :execute, 2) do
      :ok
    else
      {:error, "Tool module must implement schema/0 and execute/2"}
    end
  end

  defp validate_schema(module) do
    schema = module.schema()

    with :ok <- validate_field(schema, :name, &is_binary/1),
         :ok <- validate_field(schema, :description, &is_binary/1),
         :ok <- validate_field(schema, :parameters, &is_map/1) do
      :ok
    end
  end

  defp validate_field(map, field, validator) do
    case Map.get(map, field) do
      nil ->
        {:error, "Missing required field: #{field}"}

      value ->
        if validator.(value) do
          :ok
        else
          {:error, "Invalid type for field: #{field}"}
        end
    end
  end

  @doc """
  Converts a tool module to the OpenAI tool schema format.
  """
  @spec to_openai_format(module()) :: map()
  def to_openai_format(tool_module) do
    schema = tool_module.schema()

    %{
      type: "function",
      name: schema.name,
      description: schema.description,
      function: %{
        parameters: schema.parameters
      }
    }
  end
end
