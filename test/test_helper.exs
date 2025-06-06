ExUnit.start()

# Configure test environment
Application.put_env(:openai_agents, :api_key, "test-api-key")
Application.put_env(:openai_agents, :base_url, "http://localhost:4001")