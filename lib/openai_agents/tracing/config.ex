defmodule OpenAI.Agents.Tracing.Config do
  @moduledoc """
  Configuration for OpenAI Agents tracing system.

  Provides default configuration and environment-based setup.
  """

  @doc """
  Gets the default tracing configuration.
  """
  def default_config do
    %{
      enabled: tracing_enabled?(),
      processors: [],
      exporters: default_exporters(),
      batch_size: 100,
      batch_timeout: 5000
    }
  end

  @doc """
  Gets the production tracing configuration with OpenAI exporter.
  """
  def production_config do
    %{
      enabled: tracing_enabled?(),
      processors: [],
      exporters: [OpenAI.Agents.Tracing.OpenAIExporter],
      batch_size: 100,
      batch_timeout: 5000
    }
  end

  @doc """
  Gets the development tracing configuration with console exporter.
  """
  def development_config do
    %{
      enabled: tracing_enabled?(),
      processors: [],
      exporters: [OpenAI.Agents.Tracing.ConsoleExporter],
      batch_size: 10,
      batch_timeout: 2000
    }
  end

  defp tracing_enabled? do
    case System.get_env("OPENAI_AGENTS_DISABLE_TRACING") do
      "true" -> false
      "1" -> false
      _ -> Application.get_env(:openai_agents, :tracing_enabled, true)
    end
  end

  defp default_exporters do
    case Mix.env() do
      :prod -> [OpenAI.Agents.Tracing.OpenAIExporter]
      :dev -> [OpenAI.Agents.Tracing.ConsoleExporter]
      :test -> []
    end
  end
end
