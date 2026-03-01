defmodule GameEngine.Telemetry do
  @moduledoc """
  Telemetry イベントハンドラーと Metrics を定義する Supervisor。
  """

  use Supervisor

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    children = [
      {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      Telemetry.Metrics.summary("game.tick.physics_ms",
        unit: :millisecond,
        description: "Rust physics step duration per frame"
      ),
      Telemetry.Metrics.last_value("game.tick.enemy_count",
        description: "Active enemy count (current)"
      ),
      Telemetry.Metrics.summary("game.tick.enemy_count",
        description: "Active enemy count (avg/max/percentiles over report period)"
      ),
      Telemetry.Metrics.counter("game.level_up.count",
        description: "Total level-up events"
      ),
      Telemetry.Metrics.counter("game.boss_spawn.count",
        description: "Total boss spawn events"
      )
    ]
  end
end
