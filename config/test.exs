import Config

# Load environment variables from .env file in test
# Note: This will only work after deps are compiled
if Code.ensure_loaded?(Dotenv) and File.exists?(".env") do
  Dotenv.load!()
end

# Test-specific configuration
config :openai_agents,
  api_key: System.get_env("OPENAI_API_KEY") || "test-api-key",
  base_url: System.get_env("OPENAI_BASE_URL") || "http://localhost:4001",
  max_turns: 5,
  timeout: 5_000

# Configure logging for tests
config :logger, level: :warning