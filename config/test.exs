import Config

# Load environment variables from .env file in test
# Note: This will only work after deps are compiled
if Code.ensure_loaded?(Dotenv) and File.exists?(".env") do
  Dotenv.load!()
end

# Test-specific configuration
# For remote tests, we'll use the real OpenAI API if OPENAI_API_KEY is set
config :openai_agents,
  api_key: System.get_env("OPENAI_API_KEY") || "test-api-key",
  base_url: System.get_env("OPENAI_BASE_URL") || "https://api.openai.com/v1",
  max_turns: 5,
  # Increased timeout for remote tests
  timeout: 30_000

# Configure logging for tests
config :logger, level: :warning
