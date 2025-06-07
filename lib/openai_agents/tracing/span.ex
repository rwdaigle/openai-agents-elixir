defmodule OpenAI.Agents.Tracing.Span do
  @moduledoc """
  Represents a span within a trace.

  Based on the Python OpenAI agents library span implementation with support
  for multiple span types: agent, function, generation, response, handoff, etc.
  """

  @derive Jason.Encoder
  defstruct [
    :id,
    :trace_id,
    :type,
    :data,
    :started_at,
    :ended_at,
    :result
  ]

  @type span_type ::
          :agent
          | :function
          | :generation
          | :response
          | :handoff
          | :guardrail
          | :tool
          | :api_request

  @type t :: %__MODULE__{
          id: String.t(),
          trace_id: String.t(),
          type: span_type(),
          data: map(),
          started_at: DateTime.t(),
          ended_at: DateTime.t() | nil,
          result: any()
        }

  @doc """
  Creates a new agent span.
  """
  def agent_span(agent_module, input, opts \\ []) do
    %{
      type: :agent,
      agent_module: agent_module,
      input: input,
      trace_id: Keyword.get(opts, :trace_id),
      group_id: Keyword.get(opts, :group_id)
    }
  end

  @doc """
  Creates a new function/tool span.
  """
  def function_span(function_name, arguments, opts \\ []) do
    %{
      type: :function,
      function_name: function_name,
      arguments: arguments,
      call_id: Keyword.get(opts, :call_id),
      trace_id: Keyword.get(opts, :trace_id)
    }
  end

  @doc """
  Creates a new generation span for API requests.
  """
  def generation_span(model, request, opts \\ []) do
    %{
      type: :generation,
      model: model,
      request: request,
      trace_id: Keyword.get(opts, :trace_id)
    }
  end

  @doc """
  Creates a new response span for API responses.
  """
  def response_span(response, opts \\ []) do
    %{
      type: :response,
      response: response,
      response_id: response["id"],
      model: response["model"],
      usage: response["usage"],
      trace_id: Keyword.get(opts, :trace_id)
    }
  end

  @doc """
  Creates a new handoff span for agent transitions.
  """
  def handoff_span(from_agent, to_agent, opts \\ []) do
    %{
      type: :handoff,
      from_agent: from_agent,
      to_agent: to_agent,
      trace_id: Keyword.get(opts, :trace_id)
    }
  end

  @doc """
  Creates a new guardrail span for input/output validation.
  """
  def guardrail_span(guardrail_module, validation_type, input, opts \\ []) do
    %{
      type: :guardrail,
      guardrail_module: guardrail_module,
      validation_type: validation_type,
      input: input,
      trace_id: Keyword.get(opts, :trace_id)
    }
  end

  @doc """
  Exports the span to OpenAI-compatible format.
  """
  def export(%__MODULE__{} = span) do
    %{
      "object" => "trace.span",
      "id" => span.id,
      "trace_id" => span.trace_id,
      "type" => to_string(span.type),
      "data" => span.data,
      "started_at" => DateTime.to_iso8601(span.started_at),
      "ended_at" => if(span.ended_at, do: DateTime.to_iso8601(span.ended_at)),
      "result" => span.result
    }
  end
end
