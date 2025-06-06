defmodule OpenAI.Agents.Context do
  @moduledoc """
  Manages context state throughout agent execution.

  Context provides a way to pass application-specific state through
  the entire agent execution pipeline, accessible to tools, guardrails,
  and lifecycle hooks.
  """

  use Agent

  defstruct [:user_context, :usage, :metadata]

  @type t :: %__MODULE__{
          user_context: any(),
          usage: map(),
          metadata: map()
        }

  @doc """
  Creates a new context with default values.
  """
  @spec new() :: t()
  def new do
    %__MODULE__{
      user_context: nil,
      usage: %{},
      metadata: %{}
    }
  end

  @doc """
  Wraps user-provided context.
  """
  @spec wrap(any()) :: t()
  def wrap(user_context) do
    %__MODULE__{
      user_context: user_context,
      usage: %{},
      metadata: %{}
    }
  end

  @doc """
  Starts a context server for managing mutable state during execution.
  """
  @spec start_link(t()) :: {:ok, pid()}
  def start_link(initial_context) do
    Agent.start_link(fn -> initial_context end)
  end

  @doc """
  Gets the current context from the server.
  """
  @spec get(pid()) :: t()
  def get(server) do
    Agent.get(server, & &1)
  end

  @doc """
  Updates the context in the server.
  """
  @spec update(pid(), (t() -> t())) :: :ok
  def update(server, fun) do
    Agent.update(server, fun)
  end

  @doc """
  Gets the user context.
  """
  @spec get_user_context(pid() | t()) :: any()
  def get_user_context(server) when is_pid(server) do
    Agent.get(server, & &1.user_context)
  end

  def get_user_context(%__MODULE__{user_context: context}), do: context

  @doc """
  Updates usage statistics.
  """
  @spec update_usage(pid(), map()) :: :ok
  def update_usage(server, new_usage) do
    Agent.update(server, fn context ->
      updated_usage =
        Map.merge(context.usage, new_usage, fn _k, v1, v2 ->
          v1 + v2
        end)

      %{context | usage: updated_usage}
    end)
  end

  @doc """
  Sets metadata.
  """
  @spec set_metadata(pid(), String.t() | atom(), any()) :: :ok
  def set_metadata(server, key, value) do
    Agent.update(server, fn context ->
      %{context | metadata: Map.put(context.metadata, key, value)}
    end)
  end

  @doc """
  Gets metadata.
  """
  @spec get_metadata(pid(), String.t() | atom(), any()) :: any()
  def get_metadata(server, key, default \\ nil) do
    Agent.get(server, fn context ->
      Map.get(context.metadata, key, default)
    end)
  end
end

defmodule OpenAI.Agents.Context.Behaviour do
  @moduledoc """
  Optional behavior for custom context implementations.
  """

  @callback init(keyword()) :: any()
  @callback validate(any()) :: :ok | {:error, String.t()}
end
