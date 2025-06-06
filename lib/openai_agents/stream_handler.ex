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
  def init(opts) do
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
    new_buffer = :queue.in(normalized_event, state.buffer)
    
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
  def handle_demand(demand, state) when demand > 0 do
    {events, new_state} = dispatch_events(state, demand)
    {:noreply, events, new_state}
  end

  # Private functions

  defp dispatch_events(state, max_demand \\ :infinity) do
    {events, new_buffer} = take_events(state.buffer, max_demand, [])
    
    # Reply to any waiting subscribers
    {remaining_subscribers, more_events} = 
      reply_to_subscribers(state.subscribers, new_buffer, state.completed)
    
    all_events = events ++ more_events
    
    {all_events, %{state | buffer: new_buffer, subscribers: remaining_subscribers}}
  end

  defp take_events(queue, 0, acc), do: {Enum.reverse(acc), queue}
  defp take_events(queue, max_demand, acc) do
    case :queue.out(queue) do
      {{:value, event}, new_queue} ->
        new_max = if max_demand == :infinity, do: :infinity, else: max_demand - 1
        take_events(new_queue, new_max, [event | acc])
        
      {:empty, _} ->
        {Enum.reverse(acc), queue}
    end
  end

  defp reply_to_subscribers([], buffer, _completed), do: {[], []}
  defp reply_to_subscribers(subscribers, buffer, completed) do
    {remaining, events} = 
      Enum.reduce(subscribers, {[], []}, fn from, {subs, evts} ->
        case :queue.out(buffer) do
          {{:value, event}, _new_queue} ->
            GenStage.reply(from, {:ok, event})
            {subs, evts}
            
          {:empty, _} ->
            if completed do
              GenStage.reply(from, :done)
              {subs, evts}
            else
              {[from | subs], evts}
            end
        end
      end)
    
    {Enum.reverse(remaining), events}
  end

  defp normalize_event(%{type: "done"}), do: %OpenAI.Agents.Events.StreamComplete{}
  
  defp normalize_event(%{type: "response.created", data: data}) do
    %OpenAI.Agents.Events.ResponseCreated{
      response_id: data["response_id"],
      model: data["model"]
    }
  end
  
  defp normalize_event(%{type: "response.text.delta", data: data}) do
    %OpenAI.Agents.Events.TextDelta{
      text: data["text"],
      index: data["index"]
    }
  end
  
  defp normalize_event(%{type: "response.function_call.arguments.delta", data: data}) do
    %OpenAI.Agents.Events.FunctionCallArgumentsDelta{
      arguments: data["arguments"],
      call_id: data["call_id"],
      index: data["index"]
    }
  end
  
  defp normalize_event(%{type: "response.completed", data: data}) do
    %OpenAI.Agents.Events.ResponseCompleted{
      usage: data["usage"]
    }
  end
  
  defp normalize_event(event) do
    %OpenAI.Agents.Events.Unknown{data: event}
  end
end