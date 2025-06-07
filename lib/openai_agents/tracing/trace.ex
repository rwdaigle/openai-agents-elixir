defmodule OpenAI.Agents.Tracing.Trace do
  @moduledoc """
  Represents a conversation trace that can contain multiple spans.

  Based on the Python OpenAI agents library trace implementation.
  """

  @derive Jason.Encoder
  defstruct [
    :id,
    :group_id,
    :agent_module,
    :started_at,
    :ended_at,
    :spans,
    :context,
    :result
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          group_id: String.t(),
          agent_module: module(),
          started_at: DateTime.t(),
          ended_at: DateTime.t() | nil,
          spans: list(),
          context: map(),
          result: any()
        }

  @doc """
  Exports the trace to OpenAI-compatible format.
  """
  def export(%__MODULE__{} = trace) do
    %{
      "object" => "trace",
      "id" => trace.id,
      "group_id" => trace.group_id,
      "agent_module" => to_string(trace.agent_module),
      "started_at" => DateTime.to_iso8601(trace.started_at),
      "ended_at" => if(trace.ended_at, do: DateTime.to_iso8601(trace.ended_at)),
      "spans" => Enum.map(trace.spans, &OpenAI.Agents.Tracing.Span.export/1),
      "context" => trace.context,
      "result" => trace.result
    }
  end
end
