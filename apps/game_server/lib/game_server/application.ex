defmodule GameServer.Application do
  use Application

  @impl true
  def start(_type, _args) do
    game = Application.get_env(:game_server, :current_game, GameContent.VampireSurvivor)
    assets_path = if function_exported?(game, :assets_path, 0), do: game.assets_path(), else: ""
    System.put_env("GAME_ASSETS_ID", assets_path)

    children = [
      {Registry, [keys: :unique, name: GameEngine.RoomRegistry]},
      GameEngine.SceneManager,
      GameEngine.InputHandler,
      GameEngine.EventBus,
      GameEngine.RoomSupervisor,
      GameEngine.StressMonitor,
      GameEngine.Stats,
      GameEngine.Telemetry,
    ]

    opts = [strategy: :one_for_one, name: GameServer.Supervisor]
    result = Supervisor.start_link(children, opts)

    if elem(result, 0) == :ok do
      case GameEngine.RoomSupervisor.start_room(:main) do
        {:ok, _} -> :ok
        {:error, :already_started} -> :ok
        {:error, reason} -> raise "Failed to start main room: #{inspect(reason)}"
      end
    end

    result
  end
end
