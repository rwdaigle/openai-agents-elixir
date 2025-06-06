defmodule OpenAI.Agents.Usage do
  @moduledoc """
  Tracks token usage throughout agent execution.
  """

  defstruct prompt_tokens: 0,
            completion_tokens: 0,
            total_tokens: 0

  @type t :: %__MODULE__{
          prompt_tokens: non_neg_integer(),
          completion_tokens: non_neg_integer(),
          total_tokens: non_neg_integer()
        }

  @doc """
  Creates a new usage struct.
  """
  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @doc """
  Adds usage from an API response to existing usage.
  """
  @spec add(t(), map()) :: t()
  def add(usage, new_usage) when is_map(new_usage) do
    %__MODULE__{
      prompt_tokens: usage.prompt_tokens + (new_usage[:prompt_tokens] || 0),
      completion_tokens: usage.completion_tokens + (new_usage[:completion_tokens] || 0),
      total_tokens: usage.total_tokens + (new_usage[:total_tokens] || 0)
    }
  end

  @doc """
  Converts usage to a plain map.
  """
  @spec to_map(t()) :: map()
  def to_map(usage) do
    %{
      prompt_tokens: usage.prompt_tokens,
      completion_tokens: usage.completion_tokens,
      total_tokens: usage.total_tokens
    }
  end
end
