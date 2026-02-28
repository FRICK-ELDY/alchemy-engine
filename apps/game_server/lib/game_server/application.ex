defmodule GameServer.Application do
  use Application

  @impl true
  def start(_type, _args) do
    content = Application.get_env(:game_server, :current, GameContent.VampireSurvivor)
    assets_path =
      content.components()
      |> Enum.find_value("", fn comp ->
        if function_exported?(comp, :assets_path, 0), do: comp.assets_path()
      end)
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
