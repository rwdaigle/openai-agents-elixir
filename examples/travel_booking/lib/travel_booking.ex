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
    case args do
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

    interactive_loop(context)
  end

  defp interactive_loop(context) do
    input = IO.gets("\n💬 You: ") |> String.trim()
    
    case input do
      "quit" -> 
        IO.puts("👋 Goodbye! Thanks for using Travel Booking Assistant!")
      "help" ->
        print_interactive_help()
        interactive_loop(context)
      _ ->
        case OpenAI.Agents.run(TravelBookingAgent, input, context: context) do
          {:ok, result} ->
            IO.puts("🤖 Assistant: #{result.output}")
            interactive_loop(context)
          {:error, reason} ->
            IO.puts("❌ Error: #{inspect(reason)}")
            interactive_loop(context)
        end
    end
  end

  defp run_single(input) do
    context = %{
      user_context: %{
        name: "User", 
        booking_stage: "initial",
        preferences: %{}
      }
    }
    
    case OpenAI.Agents.run(TravelBookingAgent, input, context: context) do
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
      
    Example queries:
      "I want to plan a trip from New York to Paris"
      "Find me budget flights under $500"
      "I need help with hotel bookings"
      "Book me a flight for tomorrow" (will trigger date validation)
    """)
  end
end
