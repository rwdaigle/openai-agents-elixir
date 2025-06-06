defmodule OpenAI.Agents.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Load .env file in dev/test if available
    load_dotenv()

    children = [
      # Registry for agent processes
      {Registry, keys: :unique, name: OpenAI.Agents.Registry},

      # Registry for MCP servers
      {Registry, keys: :unique, name: OpenAI.Agents.MCP.Registry},

      # Dynamic supervisor for agent runs
      {DynamicSupervisor, name: OpenAI.Agents.RunSupervisor, strategy: :one_for_one},

      # Supervisor for tracing
      {OpenAI.Agents.TracingSupervisor, []},

      # Finch HTTP client
      {Finch, name: OpenAI.Agents.Finch}
    ]

    opts = [strategy: :one_for_one, name: OpenAI.Agents.Supervisor]

    # Set up telemetry handlers
    OpenAI.Agents.Telemetry.setup()

    Supervisor.start_link(children, opts)
  end

  defp load_dotenv do
    if Mix.env() in [:dev, :test] do
      case Code.ensure_loaded(Dotenv) do
        {:module, _} ->
          if File.exists?(".env") do
            Dotenv.load!()
          end

        _ ->
          :ok
      end
    end
  end
end
