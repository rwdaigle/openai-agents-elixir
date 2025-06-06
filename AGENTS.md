# Testing Guide

## Running Tests

This project has two types of tests:

### Default Tests (Unit Tests)

```bash
mix test
```
Runs all unit tests that use mocked API calls. These tests are fast and don't require an API key.

### Remote Tests (Integration Tests)

```bash
# Run integration tests that call OpenAI API
mix test --include remote

# Run only remote/integration tests
mix test --only remote
```

**Important:** Integration tests require a valid `OPENAI_API_KEY` environment variable and will make real API calls to OpenAI. They are excluded by default to prevent accidental API usage and costs.

## Before Committing

**All tests must pass before committing any changes.**

Run default unit tests as you make changes to confirm that your changes are working as expected.

```bash
# Run unit tests
mix test
```

When you've finalized your changes, run the integration tests to ensure that your changes work as expected.

```bash
# Run integration tests (requires OPENAI_API_KEY)
mix test --include remote
```

Additionally, run the linting and formatting checks:

```bash
# Run linting and formatting checks
mix lint

# Format code if needed
mix format
```

## Test Structure

- `test/openai_agents/` - Unit tests for core modules
- `test/integration/` - Integration tests that require API access
- Tests are tagged with `@moduletag :remote` for integration tests