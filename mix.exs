defmodule DoiDayo.MixProject do
  use Mix.Project

  def project do
    [
      app: :doi_dayo,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {DoiDayo.Application, []}
    ]
  end

  defp deps do
    [
      {:websockex, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:req, "~> 0.6"},
      {:ecto_sql, "~> 3.14"},
      {:myxql, "~> 0.9"},
      {:plug, "~> 1.0", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
