defmodule GameServer.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    content = Application.get_env(:game_server, :current, GameContent.VampireSurvivor)

    assets_path =
      if function_exported?(content, :assets_path, 0), do: content.assets_path(), else: ""

    System.put_env("GAME_ASSETS_ID", assets_path)

    children = [
      {Registry, [keys: :unique, name: GameEngine.RoomRegistry]},
      GameEngine.SceneManager,
      GameEngine.InputHandler,
      GameEngine.EventBus,
      GameEngine.RoomSupervisor,
      GameEngine.StressMonitor,
      GameEngine.Stats,
      GameEngine.Telemetry
    ]

    opts = [strategy: :one_for_one, name: GameServer.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        case GameEngine.RoomSupervisor.start_room(:main) do
          {:ok, _} -> :ok
          {:error, :already_started} -> :ok
          {:error, reason} -> raise "Failed to start main room: #{inspect(reason)}"
        end

        {:ok, pid}

      {:error, _} = err ->
        err
    end
  end
end
