defmodule TravelBooking.Tools.UserProfileManager do
  use OpenAI.Agents.Tool

  @impl true
  def schema do
    %{
      name: "update_user_context",
      description: "Update user context and booking stage",
      parameters: %{
        type: "object",
        properties: %{
          booking_stage: %{type: "string", description: "Current booking stage", enum: ["initial", "searching", "booking", "confirmation"]},
          preferences: %{type: "object", description: "User preferences"},
          budget_limit: %{type: "number", description: "User's budget limit"}
        },
        required: []
      }
    }
  end

  @impl true
  def execute(params, context) do
    updated_context = Map.merge(context, params)
    {:ok, %{message: "User context updated", context: updated_context}}
  end
end
