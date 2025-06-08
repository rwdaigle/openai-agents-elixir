defmodule OpenAI.Agents.MixProject do
  use Mix.Project

  def project do
    [
      app: :openai_agents,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],
      docs: [
        main: "readme",
        extras: ["README.md"]
      ],
      description: description(),
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger] ++ extra_applications(Mix.env()),
      mod: {OpenAI.Agents.Application, []}
    ]
  end

  defp extra_applications(:dev), do: [:dotenv]
  defp extra_applications(:test), do: [:dotenv]
  defp extra_applications(_), do: []

  defp deps do
    [
      {:finch, "~> 0.18"},
      {:jason, "~> 1.4"},
      {:gen_stage, "~> 1.2"},
      {:telemetry, "~> 1.2"},
      {:nimble_options, "~> 1.1"},

      # Dev and test dependencies
      {:dotenv, "~> 3.0", only: [:dev, :test]},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:mock, "~> 0.3", only: :test},
      {:bypass, "~> 2.1", only: :test},
      {:mix_test_watch, "~> 1.1", only: :dev, runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      setup: ["deps.get", "compile"],
      test: ["test"],
      "test.watch": ["test.watch"],
      "test.coverage": ["coveralls.html"],
      lint: ["format --check-formatted", "credo --strict"],
      "format.all": ["format"]
    ]
  end

  defp description do
    "Build powerful AI agents in Elixir using OpenAI's Responses API. This library provides an idiomatic Elixir framework for creating agents that can use tools, delegate tasks to specialized agents, and maintain conversations with full type safety and fault tolerance."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/rwdaigle/openai-agents-elixir",
        "Documentation" => "https://hexdocs.pm/openai_agents"
      }
    ]
  end
end
