defmodule TravelBooking.Guardrails.BookingConfirmation do
  use OpenAI.Agents.Guardrail

  @impl true
  def validate_output(output, _context) do
    required_elements = [
      ~r/confirmation/i,
      ~r/booking/i,
      ~r/\$\d+/,
      ~r/\d{4}-\d{2}-\d{2}/
    ]

    missing_elements = Enum.filter(required_elements, fn regex ->
      not Regex.match?(regex, output)
    end)

    if length(missing_elements) > 0 do
      {:error, "Booking confirmation missing required elements", %{missing_count: length(missing_elements)}}
    else
      :ok
    end
  end
end
