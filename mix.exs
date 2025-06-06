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
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {OpenAI.Agents.Application, []}
    ]
  end

  defp deps do
    [
      {:finch, "~> 0.18"},
      {:jason, "~> 1.4"},
      {:gen_stage, "~> 1.2"},
      {:ecto, "~> 3.11"},
      {:telemetry, "~> 1.2"},
      {:nimble_options, "~> 1.1"},
      
      # Dev and test dependencies
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:mock, "~> 0.3", only: :test},
      {:bypass, "~> 2.1", only: :test}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      setup: ["deps.get", "compile"],
      test: ["test"],
      "test.coverage": ["coveralls.html"],
      lint: ["format --check-formatted", "credo --strict"],
      "format.all": ["format"]
    ]
  end
end