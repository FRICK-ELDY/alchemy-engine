defmodule Network.Application do
  @moduledoc """
  `network` アプリケーションの Supervisor。

  起動するプロセス:
  - `Cluster.Supervisor` — libcluster（複数ノードクラスタリング、topologies が空の場合は待機）。
    戦略は `:one_for_one` のため、Cluster がクラッシュしても他プロセスには影響しない。
  - `Network.PubSub` — Phoenix.PubSub（ルーム間ブロードキャスト）
  - `Network.Local` — ローカルマルチルーム管理 GenServer
  - `Network.Endpoint` — Phoenix Endpoint（WebSocket + HTTP）
  - `Network.UDP` — UDP トランスポートサーバー（デフォルトポート 4001）

  ## 起動パターン

  ### アンブレラ全体起動（`mix run` / `iex -S mix` at root）
  アンブレラの依存順序により `network` は `server` より先に起動する。
  `Network.Local` はここで起動される。
  `Server.Application` は後から `Core.RoomRegistry` と
  `Core.RoomSupervisor` を起動する。

  **`open_room/1` が安全に使えるのは `Server.Application` の起動完了後**。
  起動直後（`Network.Application.start/2` 内）に `open_room/1` を呼ぶと
  `Core.RoomRegistry` がまだ存在せず失敗する。
  アプリケーション起動後のリクエスト処理（Channel join 等）から呼ぶのが正しい使い方。

  ### スタンドアロン起動（`iex -S mix` in `apps/network`）
  `core` アプリが自動起動するが `Core.RoomRegistry` は
  `Server.Application` が起動するため存在しない。
  `Network.Local` は起動するが `open_room/1` は使用不可。
  `register_room/1` でプロセスを手動登録すれば `broadcast/2` は動作する。
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    topologies = Application.get_env(:libcluster, :topologies, [])

    children = [
      {Cluster.Supervisor, [topologies, [name: Network.ClusterSupervisor]]},
      {Phoenix.PubSub, name: Network.PubSub},
      Network.Local,
      Network.Endpoint,
      Network.UDP
    ]

    opts = [strategy: :one_for_one, name: Network.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        port =
          Application.get_env(:network, Network.Endpoint, [])
          |> Keyword.get(:http, [])
          |> Keyword.get(:port, 4000)

        Logger.info("[Network] Endpoint started on port #{port}")
        {:ok, pid}

      {:error, reason} = err ->
        Logger.error("[Network] Failed to start: #{inspect(reason)}")
        err
    end
  end
end
