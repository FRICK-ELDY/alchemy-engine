defmodule GameNetwork.Endpoint do
  @moduledoc """
  Phoenix Endpoint。

  WebSocket (`/socket`) と HTTP ヘルスチェック (`/health`) を提供する。

  ## 設定（config/config.exs または config/dev.exs）

      config :game_network, GameNetwork.Endpoint,
        http: [port: 4000],
        pubsub_server: GameNetwork.PubSub

  デフォルトポートは 4000。
  """

  use Phoenix.Endpoint, otp_app: :game_network

  socket "/socket", GameNetwork.UserSocket,
    websocket: true,
    longpoll: false

  plug Plug.RequestId
  plug Plug.Logger

  plug Plug.Parsers,
    parsers: [:urlencoded, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug GameNetwork.Router
end
