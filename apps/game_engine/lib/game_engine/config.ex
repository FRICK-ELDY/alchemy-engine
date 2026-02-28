defmodule GameEngine.Config do
  @moduledoc """
  ゲームエンジンの設定解決ヘルパー。

  `:current` の設定キーを使用する。
  コンテンツモジュールは `components/0` を実装し、
  使用する `GameEngine.Component` モジュールのリストを返す。
  """

  @default_content GameContent.VampireSurvivor

  @doc "コンテンツモジュールを返す（`components/0` を実装したモジュール）"
  def current do
    Application.get_env(:game_server, :current, @default_content)
  end

  @doc "コンテンツが提供するコンポーネントモジュールのリストを返す"
  def components do
    current().components()
  end
end
