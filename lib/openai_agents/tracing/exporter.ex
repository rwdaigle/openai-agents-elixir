defmodule OpenAI.Agents.Tracing.Exporter do
  @moduledoc """
  Behavior for tracing exporters that send trace data to external systems.

  Based on the Python OpenAI agents library TracingExporter interface.
  """

  @callback export(items :: list()) :: :ok | {:error, term()}

  @doc """
  Exports items using the given exporter.
  """
  def export(exporter, items) do
    if function_exported?(exporter, :export, 1) do
      exporter.export(items)
    else
      {:error, :not_implemented}
    end
  end
end
