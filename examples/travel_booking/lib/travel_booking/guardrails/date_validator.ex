defmodule TravelBooking.Guardrails.DateValidator do
  use OpenAI.Agents.Guardrail

  @impl true
  def validate_input(input, _context) do
    input_text = case input do
      text when is_binary(text) -> text
      messages when is_list(messages) ->
        messages
        |> Enum.map(fn msg -> Map.get(msg, "content", "") end)
        |> Enum.join(" ")
      _ -> ""
    end
    
    date_regex = ~r/\b\d{4}-\d{2}-\d{2}\b/
    
    case Regex.scan(date_regex, input_text) do
      [] -> :ok
      dates ->
        case validate_dates(dates) do
          :ok -> :ok
          {:error, reason} -> {:error, reason, %{invalid_dates: dates}}
        end
    end
  end

  defp validate_dates(dates) do
    today = Date.utc_today()
    
    Enum.reduce_while(dates, :ok, fn [date_str], _acc ->
      case Date.from_iso8601(date_str) do
        {:ok, date} ->
          if Date.compare(date, today) == :lt do
            {:halt, {:error, "Cannot book travel for past dates: #{date_str}"}}
          else
            {:cont, :ok}
          end
        {:error, _} ->
          {:halt, {:error, "Invalid date format: #{date_str}"}}
      end
    end)
  end
end
