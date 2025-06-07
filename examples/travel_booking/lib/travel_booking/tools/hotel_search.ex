defmodule TravelBooking.Tools.HotelSearch do
  use OpenAI.Agents.Tool

  @impl true
  def schema do
    %{
      name: "search_hotels",
      description: "Search for available hotels in a city",
      parameters: %{
        type: "object",
        properties: %{
          city: %{type: "string", description: "City to search for hotels"},
          check_in: %{type: "string", description: "Check-in date (YYYY-MM-DD)"},
          check_out: %{type: "string", description: "Check-out date (YYYY-MM-DD)"},
          guests: %{type: "integer", description: "Number of guests", minimum: 1, maximum: 8},
          max_price: %{type: "number", description: "Maximum price per night"}
        },
        required: ["city", "check_in", "check_out", "guests"]
      }
    }
  end

  @impl true
  def execute(params, _context) do
    hotels = [
      %{
        name: "Grand Plaza Hotel",
        rating: 4.5,
        price_per_night: 180,
        amenities: ["WiFi", "Pool", "Gym", "Restaurant"],
        location: "Downtown"
      },
      %{
        name: "Budget Inn",
        rating: 3.8,
        price_per_night: 89,
        amenities: ["WiFi", "Parking"],
        location: "Airport Area"
      },
      %{
        name: "Luxury Resort",
        rating: 5.0,
        price_per_night: 450,
        amenities: ["WiFi", "Pool", "Spa", "Restaurant", "Room Service"],
        location: "City Center"
      }
    ]

    filtered_hotels = if params["max_price"] do
      Enum.filter(hotels, fn hotel -> hotel.price_per_night <= params["max_price"] end)
    else
      hotels
    end

    {:ok, %{hotels: filtered_hotels, search_params: params}}
  end
end
