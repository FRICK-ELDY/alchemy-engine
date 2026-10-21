defmodule Network.UserSocket do
  @moduledoc """
  Phoenix WebSocket ソケット。

  `/socket` エンドポイントに接続したクライアントが
  `Network.Channel` の各トピックに join できるようにする。

  ## 認証

  `connect/3` ではパラメータ検証を行わない（ソケット接続のみ許可）。
  **ルーム参加は `Network.Channel` 側で必須** — `room:<id>` への join には
  `POST /api/room_token` で取得した `token` を渡す（期限・room スコープ付き）。
  詳細は `Network.Channel` の moduledoc を参照。
  """

  use Phoenix.Socket

  channel("room:*", Network.Channel)

  @impl true
  def connect(_params, socket, _connect_info) do
    {:ok, socket}
  end

  @impl true
  def id(_socket), do: nil
end
