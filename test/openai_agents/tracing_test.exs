defmodule OpenAI.Agents.TracingTest do
  use ExUnit.Case, async: true

  alias OpenAI.Agents.Tracing
  alias OpenAI.Agents.Tracing.{Trace, Span, ConsoleExporter}

  describe "tracing_enabled?/0" do
    test "returns true by default" do
      assert Tracing.tracing_enabled?()
    end

    test "returns false when OPENAI_AGENTS_DISABLE_TRACING is set to true" do
      System.put_env("OPENAI_AGENTS_DISABLE_TRACING", "true")
      refute Tracing.tracing_enabled?()
      System.delete_env("OPENAI_AGENTS_DISABLE_TRACING")
    end

    test "returns false when OPENAI_AGENTS_DISABLE_TRACING is set to 1" do
      System.put_env("OPENAI_AGENTS_DISABLE_TRACING", "1")
      refute Tracing.tracing_enabled?()
      System.delete_env("OPENAI_AGENTS_DISABLE_TRACING")
    end
  end

  describe "start_conversation_trace/3" do
    test "returns nil when tracing is disabled" do
      System.put_env("OPENAI_AGENTS_DISABLE_TRACING", "true")
      
      result = Tracing.start_conversation_trace(TestAgent, "test input")
      assert is_nil(result)
      
      System.delete_env("OPENAI_AGENTS_DISABLE_TRACING")
    end

    test "returns nil when trace provider is not running" do
      # Ensure no trace provider is running
      if pid = Process.whereis(OpenAI.Agents.Tracing) do
        GenServer.stop(pid)
      end
      
      result = Tracing.start_conversation_trace(TestAgent, "test input")
      assert is_nil(result)
    end
  end

  describe "record_span/3" do
    test "returns nil when tracing is disabled" do
      System.put_env("OPENAI_AGENTS_DISABLE_TRACING", "true")
      
      result = Tracing.record_span(:agent, %{test: "data"})
      assert is_nil(result)
      
      System.delete_env("OPENAI_AGENTS_DISABLE_TRACING")
    end

    test "returns nil when trace provider is not running" do
      # Ensure no trace provider is running
      if pid = Process.whereis(OpenAI.Agents.Tracing) do
        GenServer.stop(pid)
      end
      
      result = Tracing.record_span(:agent, %{test: "data"})
      assert is_nil(result)
    end
  end

  describe "end_span/2" do
    test "handles nil span_id gracefully" do
      # Should not crash
      Tracing.end_span(nil, "result")
    end
  end

  describe "end_conversation_trace/2" do
    test "handles nil trace_id gracefully" do
      # Should not crash
      Tracing.end_conversation_trace(nil, "result")
    end
  end
end

defmodule OpenAI.Agents.Tracing.TraceTest do
  use ExUnit.Case, async: true

  alias OpenAI.Agents.Tracing.Trace

  describe "export/1" do
    test "exports trace to OpenAI-compatible format" do
      trace = %Trace{
        id: "trace_123",
        group_id: "group_456",
        agent_module: TestAgent,
        started_at: ~U[2023-01-01 00:00:00Z],
        ended_at: ~U[2023-01-01 00:01:00Z],
        spans: [],
        context: %{user_id: "user_123"},
        result: "success"
      }

      exported = Trace.export(trace)

      assert exported["object"] == "trace"
      assert exported["id"] == "trace_123"
      assert exported["group_id"] == "group_456"
      assert exported["agent_module"] == "Elixir.TestAgent"
      assert exported["started_at"] == "2023-01-01T00:00:00Z"
      assert exported["ended_at"] == "2023-01-01T00:01:00Z"
      assert exported["spans"] == []
      assert exported["context"] == %{user_id: "user_123"}
      assert exported["result"] == "success"
    end
  end
end

defmodule OpenAI.Agents.Tracing.SpanTest do
  use ExUnit.Case, async: true

  alias OpenAI.Agents.Tracing.Span

  describe "agent_span/3" do
    test "creates agent span data" do
      data = Span.agent_span(TestAgent, "test input", trace_id: "trace_123")

      assert data.type == :agent
      assert data.agent_module == TestAgent
      assert data.input == "test input"
      assert data.trace_id == "trace_123"
    end
  end

  describe "function_span/3" do
    test "creates function span data" do
      data = Span.function_span("test_function", %{arg: "value"}, call_id: "call_123")

      assert data.type == :function
      assert data.function_name == "test_function"
      assert data.arguments == %{arg: "value"}
      assert data.call_id == "call_123"
    end
  end

  describe "generation_span/3" do
    test "creates generation span data" do
      request = %{"model" => "gpt-4", "messages" => []}
      data = Span.generation_span("gpt-4", request, trace_id: "trace_123")

      assert data.type == :generation
      assert data.model == "gpt-4"
      assert data.request == request
      assert data.trace_id == "trace_123"
    end
  end

  describe "response_span/2" do
    test "creates response span data" do
      response = %{
        "id" => "resp_123",
        "model" => "gpt-4",
        "usage" => %{"total_tokens" => 100}
      }
      data = Span.response_span(response, trace_id: "trace_123")

      assert data.type == :response
      assert data.response == response
      assert data.response_id == "resp_123"
      assert data.model == "gpt-4"
      assert data.usage == %{"total_tokens" => 100}
      assert data.trace_id == "trace_123"
    end
  end

  describe "handoff_span/3" do
    test "creates handoff span data" do
      data = Span.handoff_span(AgentA, AgentB, trace_id: "trace_123")

      assert data.type == :handoff
      assert data.from_agent == AgentA
      assert data.to_agent == AgentB
      assert data.trace_id == "trace_123"
    end
  end

  describe "guardrail_span/4" do
    test "creates guardrail span data" do
      data = Span.guardrail_span(TestGuardrail, :input, "test input", trace_id: "trace_123")

      assert data.type == :guardrail
      assert data.guardrail_module == TestGuardrail
      assert data.validation_type == :input
      assert data.input == "test input"
      assert data.trace_id == "trace_123"
    end
  end

  describe "export/1" do
    test "exports span to OpenAI-compatible format" do
      span = %Span{
        id: "span_123",
        trace_id: "trace_456",
        type: :agent,
        data: %{test: "data"},
        started_at: ~U[2023-01-01 00:00:00Z],
        ended_at: ~U[2023-01-01 00:01:00Z],
        result: "success"
      }

      exported = Span.export(span)

      assert exported["object"] == "trace.span"
      assert exported["id"] == "span_123"
      assert exported["trace_id"] == "trace_456"
      assert exported["type"] == "agent"
      assert exported["data"] == %{test: "data"}
      assert exported["started_at"] == "2023-01-01T00:00:00Z"
      assert exported["ended_at"] == "2023-01-01T00:01:00Z"
      assert exported["result"] == "success"
    end
  end
end

defmodule OpenAI.Agents.Tracing.ConsoleExporterTest do
  use ExUnit.Case, async: true

  alias OpenAI.Agents.Tracing.{ConsoleExporter, Trace, Span}

  describe "export/1" do
    test "exports traces and spans to console" do
      trace = %Trace{
        id: "trace_123",
        agent_module: TestAgent,
        spans: []
      }

      span = %Span{
        id: "span_123",
        type: :agent,
        data: %{test: "data"},
        started_at: ~U[2023-01-01 00:00:00Z],
        ended_at: ~U[2023-01-01 00:01:00Z]
      }

      # Test that export function completes without error
      assert :ok = ConsoleExporter.export([trace, span])
    end
  end
end
