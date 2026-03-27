defmodule Network.MixProject do
  use Mix.Project

  def project do
    [
      app: :network,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger],
      mod: {Network.Application, []}
    ]
  end

  defp deps do
    [
      {:core, in_umbrella: true},
      {:phoenix, "~> 1.8"},
      {:phoenix_pubsub, "~> 2.2"},
      {:plug_cowboy, "~> 2.7"},
      {:libcluster, "~> 3.5"},
      {:zenohex, "~> 0.7.2"},
      {:msgpax, "~> 2.4"},
      {:protobuf, "~> 0.16"}
    ]
  end
end
