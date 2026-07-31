defmodule Core.Config do
  @moduledoc """
  ゲームエンジンの設定解決ヘルパー。

  `:current` の設定キーを使用する。
  コンテンツモジュールは `components/0` を実装し、
  使用する `Core.Component` モジュールのリストを返す。

  権威 tick（主時間）は `:tick_hz`（許容 10 / 20 / 30 / 60、デフォルト 20）。
  """

  @default_content Content.BulletHell3D
  @allowed_tick_hz [10, 20, 30, 60]
  @default_tick_hz 20

  @doc "コンテンツモジュールを返す（`components/0` を実装したモジュール）"
  def current do
    Application.get_env(:server, :current, @default_content)
  end

  @doc "コンテンツが提供するコンポーネントモジュールのリストを返す"
  def components do
    current().components()
  end

  @doc """
  権威 tick の Hz（主時間）。

  `config :server, :tick_hz, 20`。許容外はデフォルト #{@default_tick_hz} にフォールバックする。
  60Hz は設定可能だが非推奨（ハードリアルタイム保証はない）。
  """
  def tick_hz do
    case Application.get_env(:server, :tick_hz, @default_tick_hz) do
      hz when hz in @allowed_tick_hz -> hz
      _ -> @default_tick_hz
    end
  end

  @doc "権威 tick 間隔（ミリ秒）。`div(1000, tick_hz())`。"
  def tick_ms, do: div(1000, tick_hz())

  @doc "許容される tick_hz のリスト"
  def allowed_tick_hz, do: @allowed_tick_hz
end
