defmodule Core.FrameCache do
  @moduledoc """
  ルーム別のフレームスナップショットを ETS に書き込む。

  キーは `room_id`。値は診断用の汎用マップで、エンジンが解釈するのは
  `:physics_ms`（必須）のみ。`:label` / `:counters` / `:meta` 等は contents が
  注入するメタデータであり、core はコンテンツ語彙を持たない。

  ETS テーブルは本 GenServer（アプリ寿命の OTP 子）が所有する。
  ルーム GenServer から `init/0` してはならない（所有プロセス終了で
  テーブルごと消えるため）。
  """

  use GenServer

  @table :frame_cache

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    :ok = ensure_table()
    {:ok, %{}}
  end

  @doc """
  名前付き ETS テーブルを用意する。既に存在する場合は何もしない（冪等）。

  本番では `start_link/1` 経由でのみ呼ぶこと。テスト用に公開している。
  """
  def init_table, do: ensure_table()

  # 後方互換エイリアス（テスト）
  def init, do: ensure_table()

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        try do
          :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
          :ok
        rescue
          ArgumentError -> :ok
        end

      _tid ->
        :ok
    end
  end

  @doc """
  ルームの診断スナップショットを書き込む。

  ## 必須キー
  - `:physics_ms` — 直近 tick の処理時間（ms）

  ## 任意キー（エンジンは意味を解釈しない）
  - `:label` — ログ用ラベル（contents が注入）
  - `:counters` — `%{term => number}` 任意カウンタ
  - `:meta` — 任意マップ
  - `:render_type` — シーン種別など
  - その他のキーはそのまま保持される
  """
  def put(room_id, attrs) when is_map(attrs) do
    unless Map.has_key?(attrs, :physics_ms) do
      raise ArgumentError, "FrameCache.put/2 requires :physics_ms"
    end

    data = Map.put(attrs, :updated_at, System.monotonic_time(:millisecond))
    true = :ets.insert(@table, {room_id, data})
    :ok
  end

  def get(room_id) do
    case :ets.lookup(@table, room_id) do
      [{^room_id, data}] -> {:ok, data}
      [] -> :empty
    end
  rescue
    ArgumentError -> :empty
  end

  @doc "ルームのスナップショットを削除する（冪等）。"
  def delete(room_id) do
    case :ets.whereis(@table) do
      :undefined ->
        :ok

      _tid ->
        :ets.delete(@table, room_id)
        :ok
    end
  end

  @doc "全ルームの `{room_id, snapshot}` リストを返す。"
  def list do
    case :ets.whereis(@table) do
      :undefined -> []
      _tid -> :ets.tab2list(@table)
    end
  end
end
