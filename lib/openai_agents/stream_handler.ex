defmodule OpenAI.Agents.StreamHandler do
  @moduledoc """
  Handles streaming responses using GenStage for backpressure management.
  """

  use GenStage
  require Logger

  defstruct [:buffer, :completed, :subscribers]

  # Client API

  @doc """
  Starts a new stream handler.
  """
  def start_link(opts \\ []) do
    GenStage.start_link(__MODULE__, opts)
  end

  @doc """
  Emits an event to the stream.
  """
  def emit(handler, event) do
    GenStage.cast(handler, {:emit, event})
  end

  @doc """
  Marks the stream as complete.
  """
  def complete(handler) do
    GenStage.cast(handler, :complete)
  end

  @doc """
  Gets the next event from the stream.
  """
  def next_event(handler, timeout \\ 5000) do
    GenStage.call(handler, :next_event, timeout)
  end

  # GenStage callbacks

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      buffer: :queue.new(),
      completed: false,
      subscribers: []
    }

    {:producer, state, dispatcher: GenStage.BroadcastDispatcher}
  end

  @impl true
  def handle_cast({:emit, event}, state) do
    normalized_event = normalize_event(event)

    # Skip nil events
    new_buffer =
      case normalized_event do
        nil -> state.buffer
        event -> :queue.in(event, state.buffer)
      end

    # Emit events if we have demand
    {events, new_state} = dispatch_events(%{state | buffer: new_buffer})

    {:noreply, events, new_state}
  end

  @impl true
  def handle_cast(:complete, state) do
    new_state = %{state | completed: true}

    # Emit any remaining events
    {events, final_state} = dispatch_events(new_state)

    {:noreply, events, final_state}
  end

  @impl true
  def handle_call(:next_event, from, state) do
    case :queue.out(state.buffer) do
      {{:value, event}, new_queue} ->
        {:reply, {:ok, event}, [], %{state | buffer: new_queue}}

      {:empty, _} ->
        if state.completed do
          {:reply, :done, [], state}
        else
          # Store the caller to reply when we get an event
          new_subscribers = [from | state.subscribers]
          {:noreply, [], %{state | subscribers: new_subscribers}}
        end
    end
  end

  @impl true
  def handle_demand(_demand, state) do
    # We don't use GenStage demand, only direct subscribers via next_event
    {:noreply, [], state}
  end

  # Private functions

  defp dispatch_events(state, _max_demand \\ :infinity) do
    # Only reply to waiting subscribers - don't use GenStage demand
    {remaining_subscribers, final_buffer} =
      reply_to_subscribers(state.subscribers, state.buffer, state.completed)

    # Return empty events for GenStage since we're not using demand
    {[], %{state | buffer: final_buffer, subscribers: remaining_subscribers}}
  end

  defp reply_to_subscribers([], buffer, _completed), do: {[], buffer}

  defp reply_to_subscribers(subscribers, buffer, completed) do
    {remaining, new_buffer} =
      Enum.reduce(subscribers, {[], buffer}, fn from, {subs, buf} ->
        case :queue.out(buf) do
          {{:value, event}, new_queue} ->
            GenStage.reply(from, {:ok, event})
            # Don't add this subscriber back to the list!
            {subs, new_queue}

          {:empty, _} ->
            if completed do
              GenStage.reply(from, :done)
              {subs, buf}
            else
              {[from | subs], buf}
            end
        end
      end)

    # Return the updated buffer
    {Enum.reverse(remaining), new_buffer}
  end

  defp normalize_event(%{type: "done"}), do: %OpenAI.Agents.Events.StreamComplete{}

  # Handle the simple "done" event type from [DONE] SSE events
  defp normalize_event(%{type: "done", data: _data}) do
    %OpenAI.Agents.Events.ResponseCompleted{usage: %{}}
  end

  defp normalize_event(%{type: "response.created", data: data}) do
    response = data["response"] || data

    %OpenAI.Agents.Events.ResponseCreated{
      response_id: response["id"],
      model: response["model"],
      created_at: response["created_at"]
    }
  end

  defp normalize_event(%{type: "response.output_text.delta", data: data}) do
    %OpenAI.Agents.Events.TextDelta{
      text: data["delta"],
      index: data["content_index"]
    }
  end

  defp normalize_event(%{type: "response.function_call.arguments.delta", data: data}) do
    %OpenAI.Agents.Events.FunctionCallArgumentsDelta{
      arguments: data["arguments"],
      call_id: data["call_id"],
      index: data["index"]
    }
  end

  # Handle tool calls during streaming
  defp normalize_event(%{type: "response.output_item.added", data: data}) do
    item = data["item"]

    case item["type"] do
      "function_call" ->
        %OpenAI.Agents.Events.ToolCall{
          name: item["name"],
          call_id: item["id"],
          arguments: item["arguments"]
        }

      _ ->
        %OpenAI.Agents.Events.Unknown{data: data}
    end
  end

  defp normalize_event(%{type: "response.completed", data: data}) do
    response = data["response"] || data
    usage = response["usage"] || %{}

    # Normalize usage to have atom keys
    normalized_usage = %{
      total_tokens: usage["total_tokens"] || 0,
      input_tokens: usage["input_tokens"] || 0,
      output_tokens: usage["output_tokens"] || 0
    }

    %OpenAI.Agents.Events.ResponseCompleted{
      usage: normalized_usage
    }
  end

  defp normalize_event(%{type: "response.in_progress", data: _data}) do
    # Skip in_progress events - they don't need to be exposed to users
    nil
  end

  defp normalize_event(%{type: "response.function_call_arguments.delta", data: data}) do
    %OpenAI.Agents.Events.FunctionCallArgumentsDelta{
      arguments: data["delta"],
      call_id: data["item_id"],
      index: data["output_index"]
    }
  end

  defp normalize_event(%{type: "response.function_call_arguments.done", data: _data}) do
    # Skip function call arguments done events
    nil
  end

  defp normalize_event(%{type: "response.output_item.done", data: _data}) do
    # Skip output item done events
    nil
  end

  defp normalize_event(%{type: "response.done", data: data}) do
    response = data["response"] || data

    %OpenAI.Agents.Events.ResponseCompleted{
      usage: response["usage"]
    }
  end

  defp normalize_event(event) do
    %OpenAI.Agents.Events.Unknown{data: event}
  end
end
