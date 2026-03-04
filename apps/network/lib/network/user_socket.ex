defmodule Network.UserSocket do
  @moduledoc """
  Phoenix WebSocket ソケット。

  `/socket` エンドポイントに接続したクライアントが
  `Network.Channel` の各トピックに join できるようにする。

  ## 認証

  現フェーズでは認証なし（開発・ローカル用途）。
  フェーズ3以降でトークン検証を追加する想定。
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
