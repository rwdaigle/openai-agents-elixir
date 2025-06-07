defmodule TravelBooking.Tools.PaymentProcessor do
  use OpenAI.Agents.Tool

  @impl true
  def schema do
    %{
      name: "process_payment",
      description: "Process payment for booking (simulation)",
      parameters: %{
        type: "object",
        properties: %{
          amount: %{type: "number", description: "Payment amount"},
          payment_method: %{type: "string", description: "Payment method", enum: ["credit_card", "debit_card", "paypal"]},
          booking_reference: %{type: "string", description: "Booking reference number"}
        },
        required: ["amount", "payment_method", "booking_reference"]
      }
    }
  end

  @impl true
  def execute(params, _context) do
    confirmation_number = "TRV#{:rand.uniform(999999)}"
    
    result = %{
      status: "success",
      confirmation_number: confirmation_number,
      amount_charged: params["amount"],
      payment_method: params["payment_method"],
      booking_reference: params["booking_reference"],
      transaction_id: "TXN#{:rand.uniform(9999999)}"
    }

    {:ok, result}
  end
end
