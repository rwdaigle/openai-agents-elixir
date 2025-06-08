defmodule TravelBooking do
  @moduledoc """
  Travel Booking Example - Demonstrates OpenAI Agents Elixir Framework

  This example showcases:
  - Multi-agent handoffs between specialized agents
  - Dynamic instructions based on user context and booking stage
  - Tool integration for flight/hotel search and booking
  - Guardrails for input validation and safety
  - Context management throughout the booking process
  """

  alias TravelBooking.Agents.TravelBookingAgent

  def main(args \\ []) do
    normalized_args = normalize_args(args)
    
    case normalized_args do
      ["--help"] -> print_help()
      ["--interactive"] -> run_interactive()
      [input] -> run_single(input)
      [] -> run_demo()
      _ -> print_help()
    end
  end

  defp run_demo do
    IO.puts("🧳 Travel Booking Assistant Demo")
    IO.puts("================================")
    
    context = %{
      user_context: %{
        name: "Alice",
        booking_stage: "initial",
        preferences: %{budget_conscious: true},
        budget_limit: 2000
      }
    }

    input = "I want to plan a trip from New York to Paris for 2 people, departing March 15th and returning March 22nd. My budget is $2000 total."

    IO.puts("\n📝 User Input:")
    IO.puts(input)
    IO.puts("\n🤖 Assistant Response:")

    case OpenAI.Agents.run(TravelBookingAgent, input, context: context) do
      {:ok, result} ->
        IO.puts(result.output)
        IO.puts("\n✅ Demo completed successfully!")
        IO.puts("\nTry running with --interactive for a full conversation!")
      {:error, reason} ->
        IO.puts("❌ Error: #{inspect(reason)}")
        IO.puts("\nMake sure you have set OPENAI_API_KEY in the parent .env file")
    end
  end

  defp run_interactive do
    IO.puts("🧳 Interactive Travel Booking Assistant")
    IO.puts("=====================================")
    IO.puts("Type 'quit' to exit, 'help' for commands")
    
    context = %{
      user_context: %{
        name: "User",
        booking_stage: "initial",
        preferences: %{}
      }
    }

    # Initialize conversation state
    conversation_state = %{context: context, previous_response_id: nil}
    interactive_loop(conversation_state)
  end

  defp interactive_loop(%{context: context, previous_response_id: previous_response_id} = conversation_state) do
    input = IO.gets("\n💬 You: ") |> String.trim()
    
    case input do
      "quit" -> 
        IO.puts("👋 Goodbye! Thanks for using Travel Booking Assistant!")
      "help" ->
        print_interactive_help()
        interactive_loop(conversation_state)
      "new" ->
        IO.puts("🔄 Starting a new conversation...")
        new_state = %{conversation_state | previous_response_id: nil}
        interactive_loop(new_state)
      _ ->
        case run_agent_with_conversation(TravelBookingAgent, input, context, previous_response_id) do
          {:ok, result} ->
            IO.puts("🤖 Assistant: #{result.output}")
            new_state = %{conversation_state | previous_response_id: result.response_id}
            interactive_loop(new_state)
          {:error, reason} ->
            IO.puts("❌ Error: #{inspect(reason)}")
            interactive_loop(conversation_state)
        end
    end
  end

  # Helper function to encapsulate the conversation continuation pattern
  # 
  # IMPORTANT: For multi-turn conversations, you must manually track and pass
  # the previous_response_id to maintain conversation context. The OpenAI Agents
  # library does not automatically handle conversation state - each run() call
  # is independent unless you explicitly chain them together.
  #
  # Best Practice Pattern:
  # 1. Capture result.response_id from each agent response
  # 2. Pass it as previous_response_id in the next call
  # 3. Store conversation state in your application logic
  #
  defp run_agent_with_conversation(agent_module, input, context, previous_response_id) do
    opts = [context: context]
    opts = if previous_response_id, do: Keyword.put(opts, :previous_response_id, previous_response_id), else: opts
    OpenAI.Agents.run(agent_module, input, opts)
  end

  defp run_single(input) do
    normalized_input = normalize_input(input)
    
    context = %{
      user_context: %{
        name: "User", 
        booking_stage: "initial",
        preferences: %{}
      }
    }
    
    case OpenAI.Agents.run(TravelBookingAgent, normalized_input, context: context) do
      {:ok, result} -> IO.puts(result.output)
      {:error, reason} -> IO.puts("Error: #{inspect(reason)}")
    end
  end

  defp print_help do
    IO.puts("""
    Travel Booking Example Usage:

      mix run -e "TravelBooking.main()"                    # Run demo
      mix run -e "TravelBooking.main(['--interactive'])"   # Interactive mode
      mix run -e "TravelBooking.main(['your message'])"    # Single query
      mix run -e "TravelBooking.main(['--help'])"          # Show this help

    Example queries:
      "I want to book a flight to Tokyo"
      "Find me cheap hotels in Paris"
      "Plan a trip from NYC to LA for 2 people"
    """)
  end

  defp print_interactive_help do
    IO.puts("""
    
    Interactive Commands:
      quit  - Exit the assistant
      help  - Show this help
      new   - Start a new conversation (resets conversation history)
      
    Example queries:
      "I want to plan a trip from New York to Paris"
      "Find me budget flights under $500"
      "I need help with hotel bookings"
      "Book me a flight for tomorrow" (will trigger date validation)
    """)
  end

  defp normalize_args(args) when is_list(args) do
    Enum.map(args, &normalize_input/1)
  end

  defp normalize_args(args), do: args

  defp normalize_input(input) when is_list(input) and length(input) > 0 do
    if Enum.all?(input, &is_integer/1) and Enum.all?(input, &(&1 >= 0 and &1 <= 1_114_111)) do
      List.to_string(input)
    else
      input
    end
  end

  defp normalize_input(input), do: input
end
