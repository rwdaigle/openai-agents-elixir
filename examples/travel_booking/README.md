# Travel Booking Example

This example demonstrates all major features of the OpenAI Agents Elixir framework through a realistic travel booking workflow.

## Features Demonstrated

- **Multi-Agent Handoffs**: Main agent delegates to specialized agents (flight, hotel, payment)
- **Dynamic Instructions**: Context-aware prompts that adapt based on user preferences and booking stage
- **Tool Integration**: Search flights/hotels, calculate prices, process payments
- **Guardrails**: Input validation for dates, budget limits, output validation for bookings
- **Context Management**: User profile, booking state, and preferences flow through all agents

## Setup

1. **Install dependencies from the parent directory:**
   ```bash
   cd ../..  # Go to openai-agents-elixir root
   mix deps.get
   ```

2. **Set up your OpenAI API key in the parent .env file:**
   ```bash
   cd ../..  # Go to openai-agents-elixir root
   cp .env.example .env
   # Edit .env and add your OPENAI_API_KEY
   ```

3. **Install example dependencies:**
   ```bash
   cd examples/travel_booking
   mix deps.get
   ```

## Running the Example

### Demo Mode (Recommended)
```bash
mix run -e "TravelBooking.main()"
```

### Interactive Mode
```bash
mix run -e "TravelBooking.main(['--interactive'])"
```

### Single Query
```bash
mix run -e "TravelBooking.main(['I want to book a flight to Tokyo'])"
```

### Help
```bash
mix run -e "TravelBooking.main(['--help'])"
```

## Example Interactions

Try these sample inputs to see different features:

- **Basic booking**: "I want to plan a trip from New York to Paris"
- **Budget constraints**: "Find me cheap flights under $500"
- **Date validation**: "Book me a flight for yesterday" (triggers guardrail)
- **Handoff to specialist**: "I need help with hotel bookings"
- **Complex planning**: "Plan a 7-day trip to Tokyo for 2 people with a $3000 budget"

## Architecture

### Agents
- `TravelBookingAgent`: Main coordinator with dynamic instructions
- `FlightAgent`: Specialized flight search and booking
- `HotelAgent`: Hotel search and booking specialist  
- `PaymentAgent`: Secure payment processing

### Tools
- `FlightSearch`: Search available flights
- `HotelSearch`: Find hotels and accommodations
- `PriceCalculator`: Calculate total trip costs
- `PaymentProcessor`: Process booking payments
- `UserProfileManager`: Update user context and preferences

### Guardrails
- `DateValidator`: Ensures dates are valid and not in the past
- `BudgetValidator`: Validates bookings stay within budget limits
- `BookingConfirmation`: Validates booking details before confirmation

## Code Structure

```
lib/travel_booking/
├── agents/           # Agent modules
│   ├── travel_booking_agent.ex  # Main coordinator
│   ├── flight_agent.ex         # Flight specialist
│   ├── hotel_agent.ex          # Hotel specialist
│   └── payment_agent.ex        # Payment processor
├── tools/            # Tool implementations  
│   ├── flight_search.ex        # Flight search API
│   ├── hotel_search.ex         # Hotel search API
│   ├── price_calculator.ex     # Cost calculations
│   ├── payment_processor.ex    # Payment processing
│   └── user_profile_manager.ex # Context management
├── guardrails/       # Validation modules
│   ├── date_validator.ex       # Date validation
│   ├── budget_validator.ex     # Budget compliance
│   └── booking_confirmation.ex # Booking validation
└── application.ex    # OTP application
```

## How It Works

1. **Initial Request**: User makes a travel request to the main `TravelBookingAgent`
2. **Dynamic Instructions**: Agent adapts its behavior based on user context and booking stage
3. **Input Validation**: Guardrails check for valid dates and other constraints
4. **Tool Usage**: Agent uses tools to search flights, hotels, and calculate prices
5. **Handoffs**: For specialized tasks, agent hands off to `FlightAgent`, `HotelAgent`, or `PaymentAgent`
6. **Context Flow**: User preferences and booking state flow through all agents
7. **Output Validation**: Guardrails ensure responses meet budget and confirmation requirements

## Customization

You can extend this example by:

- Adding new tools (car rentals, activities, etc.)
- Creating additional guardrails (content filtering, compliance checks)
- Implementing new agents (customer service, itinerary planning)
- Enhancing dynamic instructions with more context factors
- Adding real API integrations instead of mock data

## Troubleshooting

**Error: Missing OPENAI_API_KEY**
- Make sure you've set up the `.env` file in the parent directory with your OpenAI API key

**Error: Module not found**
- Run `mix deps.get` in both the parent directory and the example directory

**Error: Permission denied**
- Ensure you have read access to the parent `.env` file

**Slow responses**
- This is normal for the first request as the application starts up
- Subsequent requests should be faster
