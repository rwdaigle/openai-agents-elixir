defmodule TravelBooking.Agents.HotelAgent do
  use OpenAI.Agent

  @impl true
  def configure do
    %{
      name: "hotel_agent",
      instructions: """
      You are a hotel booking specialist. Help users find and book accommodations.
      Use the hotel search tool to find available options.
      Present hotel options with ratings, amenities, and prices.
      Consider the user's budget and preferences when making recommendations.
      Ask for confirmation before proceeding with booking.
      """,
      tools: [
        TravelBooking.Tools.HotelSearch,
        TravelBooking.Tools.PriceCalculator
      ],
      output_guardrails: [TravelBooking.Guardrails.BookingConfirmation]
    }
  end
end
