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
  def execute(params, _context) do
    # Tools cannot directly modify agent context during execution.
    # Instead, this tool provides a way for the agent to acknowledge
    # user preferences and booking stage changes.
    
    updates = []
    
    updates = if Map.has_key?(params, "booking_stage") do
      ["Updated booking stage to #{params["booking_stage"]}" | updates]
    else
      updates
    end
    
    updates = if Map.has_key?(params, "budget_limit") do
      ["Set budget limit to $#{params["budget_limit"]}" | updates]
    else
      updates
    end
    
    updates = if Map.has_key?(params, "preferences") do
      prefs = params["preferences"]
      if is_map(prefs) and map_size(prefs) > 0 do
        pref_updates = Enum.map(prefs, fn {k, v} -> "#{k}: #{v}" end)
        ["Updated preferences (#{Enum.join(pref_updates, ", ")})" | updates]
      else
        updates
      end
    else
      updates
    end
    
    message = if Enum.empty?(updates) do
      "No updates specified"
    else
      "Profile updated: " <> Enum.join(Enum.reverse(updates), "; ")
    end
    
    {:ok, %{
      message: message,
      status: "success"
    }}
  end
end
