defmodule Server.Application do
  @moduledoc """
  Server OTP アプリケーションのエントリポイント。
  ゲームエンジンの各スーパーバイザーとワーカーを起動する。
  """

  use Application

  @impl true
  def start(_type, _args) do
    content = Application.get_env(:server, :current, Content.VampireSurvivor)

    assets_path =
      if function_exported?(content, :assets_path, 0), do: content.assets_path(), else: ""

    System.put_env("GAME_ASSETS_ID", assets_path)

    children = [
      {Registry, [keys: :unique, name: Core.RoomRegistry]},
      Core.SceneManager,
      Core.InputHandler,
      Core.EventBus,
      Core.RoomSupervisor,
      Core.StressMonitor,
      Core.Stats,
      Core.Telemetry
    ]

    opts = [strategy: :one_for_one, name: Server.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        case Core.RoomSupervisor.start_room(:main) do
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
