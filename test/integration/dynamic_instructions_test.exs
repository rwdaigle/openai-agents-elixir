defmodule OpenAI.Agents.Integration.DynamicInstructionsTest do
  use ExUnit.Case, async: false
  @moduletag :remote

  defmodule PersonalizedAgent do
    use OpenAI.Agent

    @impl true
    def configure do
      %{
        name: "personalized_assistant",
        instructions: &dynamic_instructions/1
      }
    end

    defp dynamic_instructions(context) do
      user_name = get_in(context.user_context, [:name]) || "there"
      preferences = get_in(context.user_context, [:preferences]) || %{}

      base = "You are a helpful assistant. Address the user as #{user_name}."

      style =
        case preferences[:communication_style] do
          "formal" -> " Use formal language."
          "casual" -> " Use casual, friendly language."
          _ -> ""
        end

      interests =
        case preferences[:interests] do
          interests when is_list(interests) and length(interests) > 0 ->
            " You know the user is interested in: #{Enum.join(interests, ", ")}."

          _ ->
            ""
        end

      base <> style <> interests
    end
  end

  defmodule TimeAwareAgent do
    use OpenAI.Agent

    @impl true
    def configure do
      %{
        name: "time_aware_agent",
        instructions: &time_based_instructions/1
      }
    end

    defp time_based_instructions(context) do
      hour =
        get_in(context.user_context, [:current_hour]) ||
          DateTime.utc_now().hour

      greeting =
        cond do
          hour >= 5 and hour < 12 -> "Good morning"
          hour >= 12 and hour < 17 -> "Good afternoon"
          hour >= 17 and hour < 22 -> "Good evening"
          true -> "Hello"
        end

      "You are a helpful assistant. Start your response with '#{greeting}'. Keep responses brief."
    end
  end

  defmodule RoleBasedAgent do
    use OpenAI.Agent

    @impl true
    def configure do
      %{
        name: "role_based_agent",
        instructions: &role_based_instructions/1
      }
    end

    defp role_based_instructions(context) do
      role = get_in(context.user_context, [:role]) || "student"

      case role do
        "teacher" ->
          "You are an educational assistant for teachers. Provide detailed explanations and teaching strategies."

        "student" ->
          "You are a study buddy for students. Explain concepts simply and encourage learning."

        "researcher" ->
          "You are a research assistant. Provide detailed, accurate information with sources when possible."

        _ ->
          "You are a helpful general assistant."
      end
    end
  end

  describe "personalized dynamic instructions" do
    @tag :remote
    test "agent addresses user by name" do
      context = %{name: "Alice", preferences: %{}}

      {:ok, result} =
        OpenAI.Agents.run(
          PersonalizedAgent,
          "How are you?",
          context: context
        )

      assert String.contains?(result.output, "Alice")
    end

    @tag :remote
    test "agent uses formal communication style" do
      context = %{
        name: "Dr. Smith",
        preferences: %{communication_style: "formal"}
      }

      {:ok, result} =
        OpenAI.Agents.run(
          PersonalizedAgent,
          "What's the weather like?",
          context: context
        )

      # Should address formally
      assert String.contains?(result.output, "Dr. Smith")
      # Less likely to use contractions or casual language
      refute String.contains?(result.output, "What's up")
    end

    @tag :remote
    test "agent references user interests" do
      context = %{
        name: "Bob",
        preferences: %{
          interests: ["cooking", "travel", "photography"]
        }
      }

      {:ok, result} =
        OpenAI.Agents.run(
          PersonalizedAgent,
          "Give me a fun weekend activity suggestion",
          context: context
        )

      # Should potentially reference one of the interests
      assert String.contains?(
               String.downcase(result.output),
               ["cook", "travel", "photo", "bob", "cuisine", "trip", "camera"]
             )
    end
  end

  describe "time-aware instructions" do
    @tag :remote
    test "agent uses morning greeting" do
      context = %{current_hour: 9}

      {:ok, result} =
        OpenAI.Agents.run(
          TimeAwareAgent,
          "Hello!",
          context: context
        )

      assert String.contains?(result.output, "Good morning")
    end

    @tag :remote
    test "agent uses evening greeting" do
      context = %{current_hour: 19}

      {:ok, result} =
        OpenAI.Agents.run(
          TimeAwareAgent,
          "Hello!",
          context: context
        )

      assert String.contains?(result.output, "Good evening")
    end

    @tag :remote
    test "agent defaults to current time when not provided" do
      # Run without specific hour
      {:ok, result} =
        OpenAI.Agents.run(
          TimeAwareAgent,
          "Hello!",
          context: %{}
        )

      # Should have some greeting
      assert String.contains?(result.output, [
               "Good morning",
               "Good afternoon",
               "Good evening",
               "Hello"
             ])
    end
  end

  describe "role-based instructions" do
    @tag :remote
    test "teacher role provides detailed explanations" do
      context = %{role: "teacher"}

      {:ok, result} =
        OpenAI.Agents.run(
          RoleBasedAgent,
          "What is photosynthesis?",
          context: context
        )

      # Teacher response should be detailed
      assert String.length(result.output) > 100
      assert String.contains?(String.downcase(result.output), ["teach", "explain", "student"])
    end

    @tag :remote
    test "student role provides simple explanations" do
      context = %{role: "student"}

      {:ok, result} =
        OpenAI.Agents.run(
          RoleBasedAgent,
          "What is photosynthesis?",
          context: context
        )

      # Should be encouraging and simple
      assert String.contains?(String.downcase(result.output), ["plant", "sunlight", "energy"])
    end

    @tag :remote
    test "researcher role provides detailed information" do
      context = %{role: "researcher"}

      {:ok, result} =
        OpenAI.Agents.run(
          RoleBasedAgent,
          "What is the Krebs cycle?",
          context: context
        )

      # Should be technical and detailed
      assert String.contains?(String.downcase(result.output), [
               "cycle",
               "cell",
               "atp",
               "mitochondria"
             ])
    end
  end

  describe "complex dynamic instructions" do
    defmodule ComplexDynamicAgent do
      use OpenAI.Agent

      @impl true
      def configure do
        %{
          name: "complex_dynamic_agent",
          instructions: &complex_instructions/1
        }
      end

      defp complex_instructions(context) do
        user = context.user_context || %{}

        # Build complex instructions based on multiple factors
        parts = [
          "You are an AI assistant",
          if(user[:expert_mode], do: " with expert-level knowledge", else: ""),
          ".",
          if(user[:emoji_mode], do: " Use emojis in your responses.", else: ""),
          if(user[:concise_mode], do: " Keep responses very brief.", else: ""),
          if(user[:language], do: " Respond in #{user[:language]}.", else: "")
        ]

        Enum.join(parts)
      end
    end

    @tag :remote
    test "multiple dynamic parameters work together" do
      context = %{
        expert_mode: true,
        emoji_mode: true,
        concise_mode: true
      }

      {:ok, result} =
        OpenAI.Agents.run(
          ComplexDynamicAgent,
          "What is quantum computing?",
          context: context
        )

      # Should be brief due to concise_mode
      assert String.length(result.output) < 200

      # Should include emojis
      assert String.match?(result.output, ~r/[\p{So}\p{Cn}]/u)
    end
  end
end
