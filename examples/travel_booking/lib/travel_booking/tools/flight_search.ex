defmodule TravelBooking.Tools.FlightSearch do
  use OpenAI.Agents.Tool

  @impl true
  def schema do
    %{
      name: "search_flights",
      description: "Search for available flights between cities",
      parameters: %{
        type: "object",
        properties: %{
          origin: %{type: "string", description: "Origin city"},
          destination: %{type: "string", description: "Destination city"},
          departure_date: %{type: "string", description: "Departure date (YYYY-MM-DD)"},
          return_date: %{type: "string", description: "Return date (YYYY-MM-DD), optional"},
          passengers: %{type: "integer", description: "Number of passengers", minimum: 1, maximum: 9}
        },
        required: ["origin", "destination", "departure_date", "passengers"]
      }
    }
  end

  @impl true
  def execute(params, _context) do
    flights = [
      %{
        flight_number: "AA123",
        airline: "American Airlines",
        departure_time: "08:00",
        arrival_time: "11:30",
        price: 299,
        duration: "3h 30m"
      },
      %{
        flight_number: "DL456",
        airline: "Delta Airlines",
        departure_time: "14:15",
        arrival_time: "17:45",
        price: 349,
        duration: "3h 30m"
      },
      %{
        flight_number: "UA789",
        airline: "United Airlines",
        departure_time: "19:20",
        arrival_time: "22:50",
        price: 275,
        duration: "3h 30m"
      }
    ]

    {:ok, %{flights: flights, search_params: params}}
  end
end
