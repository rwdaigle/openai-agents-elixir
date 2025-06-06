defmodule OpenAI.Agents.Events do
  @moduledoc """
  Event types emitted during streaming operations.
  """

  defmodule ResponseCreated do
    @moduledoc "Emitted when a response starts"
    defstruct [:response_id, :model, :created_at]
  end

  defmodule TextDelta do
    @moduledoc "Emitted for text chunks"
    defstruct [:text, :index]
  end

  defmodule FunctionCallArgumentsDelta do
    @moduledoc "Emitted for function call argument chunks"
    defstruct [:arguments, :call_id, :index]
  end

  defmodule ToolCall do
    @moduledoc "Emitted when a tool is called"
    defstruct [:name, :call_id, :arguments]
  end

  defmodule ResponseCompleted do
    @moduledoc "Emitted when a response completes"
    defstruct [:usage]
  end

  defmodule StreamComplete do
    @moduledoc "Emitted when the stream ends"
    defstruct []
  end

  defmodule UsageUpdate do
    @moduledoc "Emitted with token usage updates"
    defstruct [:prompt_tokens, :completion_tokens, :total_tokens]
  end

  defmodule Unknown do
    @moduledoc "Emitted for unrecognized event types"
    defstruct [:data]
  end
end
