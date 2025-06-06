# OpenAI API Interaction Document

This document describes how the openai-agents-python library interacts with the OpenAI Responses API for agentic flows.

## Overview

The library uses the OpenAI Responses API (`/v1/responses`), which is OpenAI's newer and more flexible API designed specifically for agentic workflows. This API provides better support for complex agent interactions, tool usage, and structured outputs.

## API Request Structure

### Request Parameters

All Responses API requests include these parameters:

```json
{
  "model": "gpt-4o",
  "instructions": "You are a helpful assistant.",
  "input": [
    {
      "type": "user_text",
      "text": "Hello, how are you?"
    }
  ],
  "temperature": 0.7,
  "top_p": 1.0,
  "max_tokens": null,
  "tool_choice": "auto",
  "parallel_tool_calls": true,
  "stream": false,
  "tools": [
    {
      "type": "function",
      "name": "get_weather",
      "description": "Get the weather for a city",
      "function": {
        "parameters": {
          "type": "object",
          "properties": {
            "city": {"type": "string"}
          },
          "required": ["city"]
        }
      }
    }
  ],
  "extra_headers": {},
  "extra_query": {},
  "extra_body": {}
}
```

## Tool Calling Flow

### 1. Initial Request
The agent sends a request with available tools defined.

### 2. Tool Call Response
When the model decides to use a tool:
```json
{
  "output": [{
    "type": "function_call",
    "id": "call_abc123",
    "name": "get_weather",
    "arguments": "{\"city\": \"San Francisco\"}"
  }]
}
```

### 3. Tool Execution
The library executes the tool locally and prepares the result.

### 4. Tool Result Submission
The tool result is sent back to the API:
```json
{
  "input": [
    // ... previous items ...
    {
      "type": "function_call_result",
      "call_id": "call_abc123",
      "result": "{\"temperature\": \"72F\", \"conditions\": \"Sunny\"}"
    }
  ]
}
```

## Streaming

The Responses API supports streaming responses. The library handles streaming by:

1. Setting `stream: true` in the request
2. Processing server-sent events (SSE)
3. Accumulating deltas into complete responses
4. Emitting appropriate events to the client

### Stream Event Types

- `ResponseCreatedEvent`: Start of response
- `ResponseTextDeltaEvent`: Text chunk
- `ResponseFunctionCallArgumentsDeltaEvent`: Tool call argument chunk
- `ResponseCompletedEvent`: End of response

## Special Features

### 1. Handoffs
Handoffs are implemented as special function tools that transfer control to another agent:

```json
{
  "type": "function",
  "function": {
    "name": "handoff_to_spanish_agent",
    "description": "Transfer to Spanish-speaking assistant",
    "parameters": {
      "type": "object",
      "properties": {
        "input": {"type": "string"}
      },
      "required": ["input"]
    }
  }
}
```

### 2. Structured Output
When an output schema is defined, the library uses response format:

```json
{
  "response_format": {
    "type": "json_schema",
    "json_schema": {
      "name": "FinalResult",
      "schema": {
        "type": "object",
        "properties": {
          "answer": {"type": "string"},
          "confidence": {"type": "number"}
        },
        "required": ["answer", "confidence"]
      }
    }
  }
}
```

### 3. OpenAI-Hosted Tools
Certain tools are executed on OpenAI's infrastructure:

- **File Search**: Vector store search
- **Code Interpreter**: Python execution
- **Web Search**: Internet search
- **Image Generation**: DALL-E integration

These are specified with additional parameters:

```json
{
  "tools": [
    {
      "type": "file_search",
      "file_search": {
        "vector_store_ids": ["vs_abc123"]
      }
    },
    {
      "type": "code_interpreter"
    }
  ]
}
```

## Error Handling

The library handles various API errors:

1. **Rate Limits**: Captured and re-raised with request_id
2. **Invalid Requests**: Proper error messages with debugging info
3. **Network Errors**: Retry logic (handled by OpenAI client)
4. **Model Errors**: Special handling for unexpected model behavior

## Usage Tracking

The library tracks token usage from API responses:

```json
{
  "usage": {
    "prompt_tokens": 150,
    "completion_tokens": 50,
    "total_tokens": 200
  }
}
```

This is aggregated across multiple API calls in a single agent run.

## Model-Specific Features

### Reasoning Models (o1, o3)
For reasoning models, the library adds:
```json
{
  "reasoning_effort": "medium"  // low, medium, high
}
```

### Store Integration
For persistent conversation history:
```json
{
  "store": "thread_abc123"
}
```

## Security Considerations

1. **API Keys**: Handled by the OpenAI client library
2. **Sensitive Data**: Tracing can be configured to exclude data
3. **Tool Approval**: MCP tools can require user approval
4. **Guardrails**: Input/output validation before API calls

## Performance Optimizations

1. **Parallel Tool Calls**: Multiple tools can be called in one turn
2. **Streaming**: Reduces time to first token
3. **Context Window Management**: Automatic truncation of old messages
4. **Caching**: MCP responses can be cached

This architecture provides a clean abstraction over the OpenAI Responses API while maintaining flexibility for advanced use cases.