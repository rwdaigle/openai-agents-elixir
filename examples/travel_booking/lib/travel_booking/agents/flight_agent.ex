defmodule TravelBooking.Agents.FlightAgent do
  use OpenAI.Agent

  @impl true
  def configure do
    %{
      name: "flight_agent",
      instructions: """
      You are a flight booking specialist. Help users search for and book flights.
      Use the flight search tool to find available options.
      Present flight options clearly with prices, times, and airlines.
      Ask for confirmation before proceeding with booking.
      Always provide multiple options when available.
      """,
      tools: [
        TravelBooking.Tools.FlightSearch,
        TravelBooking.Tools.PriceCalculator
      ],
      output_guardrails: [TravelBooking.Guardrails.BookingConfirmation]
    }
  end
end
