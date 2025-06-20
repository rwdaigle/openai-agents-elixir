defmodule OpenAI.Agents.Integration.ConfigTest do
  use ExUnit.Case, async: false
  @moduletag :remote

  @tag :remote
  test "verify API configuration" do
    api_key = System.get_env("OPENAI_API_KEY")
    base_url = Application.get_env(:openai_agents, :base_url)

    # Also test runtime resolution
    resolved_key =
      System.get_env("OPENAI_API_KEY") ||
        Application.get_env(:openai_agents, :api_key)

    resolved_url =
      System.get_env("OPENAI_BASE_URL") ||
        Application.get_env(:openai_agents, :base_url) ||
        "https://api.openai.com/v1"

    assert api_key != nil, "OPENAI_API_KEY must be set for remote tests"

    assert base_url == "https://api.openai.com/v1",
           "Base URL should be OpenAI API for remote tests"

    assert resolved_key != nil, "Resolved API key should be present"
    assert resolved_url == "https://api.openai.com/v1", "Resolved URL should be OpenAI API"
  end
end
