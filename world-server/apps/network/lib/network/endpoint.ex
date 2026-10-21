defmodule Network.Endpoint do
  @moduledoc """
  Phoenix Endpoint。

  WebSocket (`/socket`) と HTTP ヘルスチェック (`/health`) を提供する。

  ## 設定（config/config.exs または config/dev.exs）

      config :network, Network.Endpoint,
        http: [port: 4000],
        pubsub_server: Network.PubSub

  デフォルトポートは 4000。
  """

  use Phoenix.Endpoint, otp_app: :network

  socket("/socket", Network.UserSocket,
    websocket: true,
    longpoll: false
  )

  plug(Plug.RequestId)
  plug(Plug.Logger)

  plug(Plug.Parsers,
    parsers: [:urlencoded, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Network.Router)
end
