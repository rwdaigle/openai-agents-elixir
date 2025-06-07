defmodule TravelBooking.Agents.PaymentAgent do
  use OpenAI.Agent

  @impl true
  def configure do
    %{
      name: "payment_agent",
      instructions: """
      You are a secure payment processing specialist. Handle payment transactions safely.
      Always confirm payment details before processing.
      Provide clear confirmation numbers and transaction details.
      Ensure all payment information is handled securely.
      Never store or log sensitive payment information.
      """,
      tools: [
        TravelBooking.Tools.PaymentProcessor,
        TravelBooking.Tools.PriceCalculator
      ],
      output_guardrails: [TravelBooking.Guardrails.BookingConfirmation]
    }
  end
end
