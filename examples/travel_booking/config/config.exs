import Config

if Code.ensure_loaded?(Dotenv) and File.exists?("../../.env") do
  Dotenv.load!("../../.env")
end

config :openai_agents,
  api_key: System.get_env("OPENAI_API_KEY"),
  base_url: System.get_env("OPENAI_BASE_URL") || "https://api.openai.com/v1"
