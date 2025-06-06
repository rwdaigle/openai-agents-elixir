import Config

# Load environment variables from .env file in development
# Note: This will only work after deps are compiled
if Code.ensure_loaded?(Dotenv) and File.exists?(".env") do
  Dotenv.load!()
end

# Development-specific configuration
config :openai_agents,
  api_key: System.get_env("OPENAI_API_KEY"),
  base_url: System.get_env("OPENAI_BASE_URL") || "https://api.openai.com/v1"

# Configure logging for development
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :agent, :trace_id]