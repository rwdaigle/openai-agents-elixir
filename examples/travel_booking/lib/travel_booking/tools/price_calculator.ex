defmodule TravelBooking.Tools.PriceCalculator do
  use OpenAI.Agents.Tool

  @impl true
  def schema do
    %{
      name: "calculate_total_price",
      description: "Calculate total trip cost including flights, hotels, and fees",
      parameters: %{
        type: "object",
        properties: %{
          flight_price: %{type: "number", description: "Flight price per person"},
          hotel_price: %{type: "number", description: "Hotel price per night"},
          nights: %{type: "integer", description: "Number of nights"},
          passengers: %{type: "integer", description: "Number of passengers"},
          include_taxes: %{type: "boolean", description: "Include taxes and fees", default: true}
        },
        required: ["flight_price", "hotel_price", "nights", "passengers"]
      }
    }
  end

  @impl true
  def execute(params, _context) do
    flight_total = params["flight_price"] * params["passengers"]
    hotel_total = params["hotel_price"] * params["nights"]
    subtotal = flight_total + hotel_total

    taxes_and_fees = if params["include_taxes"] != false do
      subtotal * 0.15
    else
      0
    end

    total = subtotal + taxes_and_fees

    breakdown = %{
      flight_cost: flight_total,
      hotel_cost: hotel_total,
      subtotal: subtotal,
      taxes_and_fees: taxes_and_fees,
      total: total
    }

    {:ok, breakdown}
  end
end
