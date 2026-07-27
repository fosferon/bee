defmodule Bee.MixProject do
  use Mix.Project

  def project do
    [
      app: :bee,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:exqlite, "~> 0.34"},
      {:jason, "~> 1.4"},
      {:nimble_pool, "~> 1.1"}
    ]
  end
end
