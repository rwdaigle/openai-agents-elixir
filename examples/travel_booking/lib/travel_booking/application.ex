defmodule TravelBooking.Application do
  use Application

  @impl true
  def start(_type, _args) do
    if Code.ensure_loaded?(Dotenv) and File.exists?("../../.env") do
      Dotenv.load!("../../.env")
    end

    children = []

    opts = [strategy: :one_for_one, name: TravelBooking.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
