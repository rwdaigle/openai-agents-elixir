defmodule TravelBooking.Guardrails.BudgetValidator do
  use OpenAI.Agents.Guardrail

  @impl true
  def validate_output(output, context) do
    budget_limit = get_in(context.user_context, [:budget_limit])
    
    if budget_limit do
      price_regex = ~r/\$(\d+(?:,\d{3})*(?:\.\d{2})?)/
      
      case Regex.scan(price_regex, output) do
        [] -> :ok
        prices ->
          case check_budget_compliance(prices, budget_limit) do
            :ok -> :ok
            {:error, reason} -> {:error, reason, %{budget_limit: budget_limit}}
          end
      end
    else
      :ok
    end
  end

  defp check_budget_compliance(prices, budget_limit) do
    max_price = prices
    |> Enum.map(fn [_, price_str] -> 
      price_str
      |> String.replace(",", "")
      |> case do
        str when str != "" ->
          case Float.parse(str) do
            {float_val, _} -> float_val
            :error -> 0.0
          end
        _ -> 0.0
      end
    end)
    |> Enum.max(fn -> 0.0 end)

    if max_price > budget_limit do
      {:error, "Suggested price $#{max_price} exceeds budget limit of $#{budget_limit}"}
    else
      :ok
    end
  end
end
