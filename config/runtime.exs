import Config

# This file is executed at runtime and can read system environment variables.
# It's useful for secrets and other runtime configuration.

if config_env() == :prod do
  # Validate required environment variables in production
  api_key = System.get_env("OPENAI_API_KEY") ||
    raise """
    Environment variable OPENAI_API_KEY is missing.
    Please set it to your OpenAI API key.
    """

  config :openai_agents,
    api_key: api_key
end