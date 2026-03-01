defmodule GameServer.MixProject do
  use Mix.Project

  def project do
    [
      app: :game_server,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {GameServer.Application, []},
    ]
  end

  defp deps do
    [
      {:game_engine, in_umbrella: true},
      {:game_content, in_umbrella: true},
      {:game_network, in_umbrella: true},
    ]
  end
end
