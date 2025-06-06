defmodule OpenAI.Agents.Guardrail do
  @moduledoc """
  Defines the behavior for guardrails that validate agent inputs and outputs.

  Guardrails can halt agent execution if they detect problematic content.

  ## Example

      defmodule MyApp.Guardrails.ContentFilter do
        use OpenAI.Agents.Guardrail
        
        @impl true
        def validate_input(input, context) do
          if contains_prohibited_content?(input) do
            {:error, "Prohibited content detected", %{reason: "content_policy"}}
          else
            :ok
          end
        end
        
        @impl true
        def validate_output(output, context) do
          :ok
        end
      end
  """

  @type input :: String.t() | [map()]
  @type output :: any()
  @type context :: any()
  @type validation_result :: :ok | {:error, String.t(), map()}

  @callback validate_input(input(), context()) :: validation_result()
  @callback validate_output(output(), context()) :: validation_result()

  @optional_callbacks validate_input: 2, validate_output: 2

  defmacro __using__(_opts) do
    quote do
      @behaviour OpenAI.Agents.Guardrail

      def validate_input(_input, _context), do: :ok
      def validate_output(_output, _context), do: :ok

      defoverridable validate_input: 2, validate_output: 2
    end
  end

  @doc """
  Runs input guardrails on the given input.
  """
  @spec run_input_guardrails([module()], input(), map()) :: :ok | {:error, term()}
  def run_input_guardrails(guardrails, input, state) do
    Enum.reduce_while(guardrails, :ok, fn guardrail, _acc ->
      case run_guardrail(guardrail, :validate_input, [input, state.context]) do
        :ok ->
          {:cont, :ok}

        {:error, reason, metadata} ->
          {:halt, {:error, {guardrail, reason, metadata}}}

        other ->
          {:halt, {:error, {:invalid_guardrail_response, guardrail, other}}}
      end
    end)
  end

  @doc """
  Runs output guardrails on the given output.
  """
  @spec run_output_guardrails([module()], output(), map()) :: {:ok, output()} | {:error, term()}
  def run_output_guardrails(guardrails, output, state) do
    Enum.reduce_while(guardrails, {:ok, output}, fn guardrail, {:ok, current_output} ->
      case run_guardrail(guardrail, :validate_output, [current_output, state.context]) do
        :ok ->
          {:cont, {:ok, current_output}}

        {:ok, modified_output} ->
          # Allow guardrails to modify output
          {:cont, {:ok, modified_output}}

        {:error, reason, metadata} ->
          {:halt, {:error, {guardrail, reason, metadata}}}

        other ->
          {:halt, {:error, {:invalid_guardrail_response, guardrail, other}}}
      end
    end)
  end

  defp run_guardrail(guardrail, function, args) do
    if function_exported?(guardrail, function, length(args)) do
      apply(guardrail, function, args)
    else
      :ok
    end
  rescue
    error ->
      {:error, Exception.message(error), %{exception: error}}
  end

  @doc """
  Validates a guardrail module has the correct structure.
  """
  @spec validate_guardrail(module()) :: :ok | {:error, String.t()}
  def validate_guardrail(guardrail_module) do
    cond do
      not is_atom(guardrail_module) ->
        {:error, "Guardrail must be a module"}

      not (function_exported?(guardrail_module, :validate_input, 2) or
               function_exported?(guardrail_module, :validate_output, 2)) ->
        {:error, "Guardrail must implement at least one of validate_input/2 or validate_output/2"}

      true ->
        :ok
    end
  end
end
