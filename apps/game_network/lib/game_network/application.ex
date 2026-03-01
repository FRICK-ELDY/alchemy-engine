defmodule GameNetwork.Application do
  @moduledoc """
  `game_network` アプリケーションの Supervisor。

  起動するプロセス:
  - `GameNetwork.PubSub` — Phoenix.PubSub（ルーム間ブロードキャスト）
  - `GameNetwork.Local` — ローカルマルチルーム管理 GenServer
  - `GameNetwork.Endpoint` — Phoenix Endpoint（WebSocket + HTTP）
  - `GameNetwork.UDP` — UDP トランスポートサーバー（デフォルトポート 4001）

  ## 起動パターン

  ### アンブレラ全体起動（`mix run` / `iex -S mix` at root）
  アンブレラの依存順序により `game_network` は `game_server` より先に起動する。
  `GameNetwork.Local` はここで起動される。
  `GameServer.Application` は後から `GameEngine.RoomRegistry` と
  `GameEngine.RoomSupervisor` を起動する。

  **`open_room/1` が安全に使えるのは `GameServer.Application` の起動完了後**。
  起動直後（`GameNetwork.Application.start/2` 内）に `open_room/1` を呼ぶと
  `GameEngine.RoomRegistry` がまだ存在せず失敗する。
  アプリケーション起動後のリクエスト処理（Channel join 等）から呼ぶのが正しい使い方。

  ### スタンドアロン起動（`iex -S mix` in `apps/game_network`）
  `game_engine` アプリが自動起動するが `GameEngine.RoomRegistry` は
  `GameServer.Application` が起動するため存在しない。
  `GameNetwork.Local` は起動するが `open_room/1` は使用不可。
  `register_room/1` でプロセスを手動登録すれば `broadcast/2` は動作する。
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: GameNetwork.PubSub},
      GameNetwork.Local,
      GameNetwork.Endpoint,
      GameNetwork.UDP
    ]

    opts = [strategy: :one_for_one, name: GameNetwork.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        port =
          Application.get_env(:game_network, GameNetwork.Endpoint, [])
          |> Keyword.get(:http, [])
          |> Keyword.get(:port, 4000)

        Logger.info("[GameNetwork] Endpoint started on port #{port}")
        {:ok, pid}

      {:error, reason} = err ->
        Logger.error("[GameNetwork] Failed to start: #{inspect(reason)}")
        err
    end
  end
end
