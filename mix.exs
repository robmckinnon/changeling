defmodule Changeling.MixProject do
  use Mix.Project

  def project do
    [
      app: :changeling,
      version: "0.0.1",
      elixir: "~> 1.14",
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
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false},
      {:sourceror, "~> 0.11.1"}
    ]
  end
end
