import Config

# Production configuration
# In production, you should set environment variables directly
# rather than using a .env file

config :openai_agents,
  api_key: System.get_env("OPENAI_API_KEY"),
  base_url: System.get_env("OPENAI_BASE_URL") || "https://api.openai.com/v1"

# Configure logging for production
config :logger, level: :info