defmodule Bee.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/fosferon/bee"

  def project do
    [
      app: :bee,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      docs: docs(),
      description: description()
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
      {:nimble_pool, "~> 1.1"},
      {:ex_doc, "~> 0.36", only: :dev, runtime: false},
      {:earmark, "~> 1.4", only: :dev, runtime: false}
    ]
  end

  defp description do
    "A dependency-aware work-coordination engine for Elixir: a work DAG, an allocation tree, " <>
      "and a query language that reports what it withheld — over SQLite."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => @source_url <> "/blob/master/CHANGELOG.md"
      },
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: ["README.md"],
      skip_undefined_reference_warnings_on_extras: ["README.md"]
    ]
  end
end
