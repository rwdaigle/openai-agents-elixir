defmodule TravelBooking.Agents.TravelBookingAgent do
  use OpenAI.Agent

  @impl true
  def configure do
    %{
      name: "travel_booking_agent",
      instructions: &dynamic_instructions/1,
      tools: [TravelBooking.Tools.UserProfileManager],
      handoffs: [
        TravelBooking.Agents.FlightAgent,
        TravelBooking.Agents.HotelAgent,
        TravelBooking.Agents.PaymentAgent
      ],
      input_guardrails: [TravelBooking.Guardrails.DateValidator],
      output_guardrails: [TravelBooking.Guardrails.BudgetValidator]
    }
  end

  defp dynamic_instructions(context) do
    user_name = get_in(context.user_context, [:name]) || "there"
    booking_stage = get_in(context.user_context, [:booking_stage]) || "initial"
    preferences = get_in(context.user_context, [:preferences]) || %{}

    base = "You are a travel booking assistant. Address the user as #{user_name}."

    stage_instructions = case booking_stage do
      "initial" -> " Help them plan their trip and gather requirements. Ask about destinations, dates, budget, and preferences."
      "searching" -> " Focus on finding the best options for their needs. Use handoffs to specialized agents for detailed searches."
      "booking" -> " Guide them through the booking process carefully. Ensure all details are confirmed before proceeding."
      "confirmation" -> " Provide booking confirmation and next steps. Include all relevant details and confirmation numbers."
      _ -> " Help them with their travel planning needs."
    end

    preference_instructions = case preferences do
      %{budget_conscious: true} -> " Prioritize budget-friendly options and highlight savings."
      %{luxury: true} -> " Focus on premium options and comfort. Emphasize quality and amenities."
      %{business: true} -> " Recommend business-class options and convenient schedules."
      _ -> ""
    end

    budget_instructions = case get_in(context.user_context, [:budget_limit]) do
      nil -> ""
      budget -> " Keep recommendations within their budget of $#{budget}."
    end

    base <> stage_instructions <> preference_instructions <> budget_instructions
  end
end
