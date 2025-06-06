defmodule OpenAI.Agent do
  @moduledoc """
  Defines the behavior for OpenAI agents.

  An agent is a module that can process inputs, use tools, delegate to other agents,
  and produce structured outputs.

  ## Example

      defmodule MyApp.WeatherAgent do
        use OpenAI.Agent
        
        @impl true
        def configure do
          %{
            name: "weather_assistant",
            instructions: "You are a helpful weather assistant.",
            model: "gpt-4.1-mini",
            tools: [MyApp.Tools.GetWeather],
            output_schema: MyApp.Schemas.WeatherReport
          }
        end
        
        @impl true
        def on_start(context, agent_state) do
          # Optional lifecycle callback
          {:ok, agent_state}
        end
      end
  """

  @type agent_config :: %{
          required(:name) => String.t(),
          required(:instructions) => String.t() | function(),
          optional(:model) => String.t(),
          optional(:model_settings) => map(),
          optional(:tools) => [module()],
          optional(:handoffs) => [module()],
          optional(:input_guardrails) => [module()],
          optional(:output_guardrails) => [module()],
          optional(:output_schema) => module(),
          optional(:hooks) => module(),
          optional(:mcp_servers) => [map()]
        }

  @type context :: any()
  @type agent_state :: any()

  @callback configure() :: agent_config()
  @callback on_start(context, agent_state) :: {:ok, agent_state} | {:error, term()}
  @callback on_end(context, agent_state) :: {:ok, agent_state} | {:error, term()}

  @optional_callbacks on_start: 2, on_end: 2

  defmacro __using__(_opts) do
    quote do
      @behaviour OpenAI.Agent

      def on_start(_context, agent_state), do: {:ok, agent_state}
      def on_end(_context, agent_state), do: {:ok, agent_state}

      defoverridable on_start: 2, on_end: 2
    end
  end

  @doc """
  Gets the configuration for an agent module.
  """
  @spec get_config(module()) :: agent_config()
  def get_config(agent_module) do
    agent_module.configure()
  end

  @doc """
  Gets the instructions for an agent, resolving dynamic instructions if needed.
  """
  @spec get_instructions(module(), map()) :: {:ok, String.t()} | {:error, term()}
  def get_instructions(agent_module, context) do
    config = get_config(agent_module)

    case config.instructions do
      instructions when is_binary(instructions) ->
        {:ok, instructions}

      instructions_fn when is_function(instructions_fn, 1) ->
        try do
          {:ok, instructions_fn.(context)}
        rescue
          e -> {:error, e}
        end

      instructions_fn when is_function(instructions_fn, 2) ->
        try do
          {:ok, instructions_fn.(context, agent_module)}
        rescue
          e -> {:error, e}
        end

      _ ->
        {:error, "Invalid instructions type"}
    end
  end

  @doc """
  Validates an agent module has the required callbacks.
  """
  @spec validate_agent(module()) :: :ok | {:error, String.t()}
  def validate_agent(agent_module) do
    if function_exported?(agent_module, :configure, 0) do
      config = agent_module.configure()
      validate_config(config)
    else
      {:error, "Agent module must implement configure/0"}
    end
  end

  defp validate_config(config) do
    with :ok <- validate_required_field(config, :name),
         :ok <- validate_required_field(config, :instructions),
         :ok <- validate_optional_list(config, :tools),
         :ok <- validate_optional_list(config, :handoffs),
         :ok <- validate_optional_list(config, :input_guardrails),
         :ok <- validate_optional_list(config, :output_guardrails) do
      :ok
    end
  end

  defp validate_required_field(config, field) do
    if Map.has_key?(config, field) do
      :ok
    else
      {:error, "Missing required field: #{field}"}
    end
  end

  defp validate_optional_list(config, field) do
    case Map.get(config, field) do
      nil -> :ok
      list when is_list(list) -> :ok
      _ -> {:error, "Field #{field} must be a list"}
    end
  end
end
