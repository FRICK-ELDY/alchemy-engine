defmodule Server.Application do
  @moduledoc """
  Server OTP アプリケーションのエントリポイント。
  ゲームエンジンの各スーパーバイザーとワーカーを起動する。
  """

  use Application

  @impl true
  def start(_type, _args) do
    content =
      Application.get_env(:server, :current) ||
        raise "config :server, :current is required"

    assets_path =
      if function_exported?(content, :assets_path, 0), do: content.assets_path(), else: ""

    System.put_env("ASSETS_ID", assets_path)

    children = [
      # FrameCache ETS の所有者（ルームより先に起動し、アプリ寿命で保持する）
      Core.FrameCache,
      {Registry, [keys: :unique, name: Core.RoomRegistry]},
      Core.FormulaStore.LocalBackend,
      {Registry, [keys: :unique, name: Contents.Scenes.Registry]},
      Core.EventBus,
      Server.Rooms,
      Core.StressMonitor,
      Core.Stats,
      Core.Telemetry
    ]

    opts = [strategy: :one_for_one, name: Server.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
