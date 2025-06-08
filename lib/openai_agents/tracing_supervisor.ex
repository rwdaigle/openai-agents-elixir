defmodule OpenAI.Agents.TracingSupervisor do
  @moduledoc """
  Supervisor for OpenAI-compatible tracing components.

  Updated to use the new OpenAI tracing architecture based on the Python library.
  """

  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    config = get_tracing_config()

    children =
      if config.enabled do
        [
          {OpenAI.Agents.Tracing, [config: config]}
        ]
      else
        []
      end

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp get_tracing_config do
    case Mix.env() do
      :prod ->
        OpenAI.Agents.Tracing.Config.production_config()

      :dev ->
        OpenAI.Agents.Tracing.Config.development_config()

      :test ->
        %{enabled: false, processors: [], exporters: [], batch_size: 10, batch_timeout: 1000}

      _ ->
        OpenAI.Agents.Tracing.Config.default_config()
    end
  end
end
