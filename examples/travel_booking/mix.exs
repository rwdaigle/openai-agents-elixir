defmodule TravelBooking.MixProject do
  use Mix.Project

  def project do
    [
      app: :travel_booking,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  def application do
    [
      extra_applications: [:logger] ++ extra_applications(Mix.env()),
      mod: {TravelBooking.Application, []}
    ]
  end

  defp extra_applications(:dev), do: [:dotenv]
  defp extra_applications(:test), do: [:dotenv]
  defp extra_applications(_), do: []

  defp deps do
    [
      {:openai_agents, path: "../.."},
      {:dotenv, "~> 3.0", only: [:dev, :test]}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
