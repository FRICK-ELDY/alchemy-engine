defmodule GameEngine.Component do
  @moduledoc """
  ゲームコンテンツの構成単位となるビヘイビア。

  コンテンツはコンポーネントの集合として表現される。
  各コールバックはオプションであり、必要なものだけ実装すればよい。

  ## コールバック

  - `on_ready/1`           — 初期化時（1回）
  - `on_process/1`         — 毎フレーム（Elixir 側）
  - `on_physics_process/1` — 物理フレーム（60Hz）
  - `on_event/2`           — UI アクション・エンジン内部イベント発生時
  - `on_frame_event/2`     — Rust フレームイベント発生時（ゲーム状態の更新）
  - `on_nif_sync/1`        — 毎フレームの NIF 注入（Elixir state → Rust）

  ## コンテキスト

  `context` マップには以下のフィールドが含まれる：

  - `context.world_ref`    — Rust ワールドへの参照
  - `context.now`          — 現在時刻（monotonic ms）
  - `context.elapsed`      — ゲーム開始からの経過 ms
  - `context.frame_count`  — フレームカウンタ
  - `context.tick_ms`      — 目標フレーム時間（ms）
  - `context.start_ms`     — ゲーム開始時刻（monotonic ms）

  シーン遷移 API：

  - `context.push_scene.(mod, init_arg)`     — シーンをスタックに積む
  - `context.pop_scene.()`                  — 現在のシーンをスタックから取り出す
  - `context.replace_scene.(mod, init_arg)` — 現在のシーンを置き換える

  ## コンテンツ定義

  コンテンツモジュールは `components/0` を実装し、
  使用するコンポーネントのモジュールリストを返す。

      defmodule GameContent.MyGame do
        def components do
          [
            GameContent.MyGame.SpawnComponent,
            GameContent.MyGame.LevelComponent,
          ]
        end
      end
  """

  @type world_ref :: reference()
  @type context :: map()
  @type event :: tuple()

  @callback on_ready(world_ref()) :: :ok
  @callback on_process(context()) :: :ok
  @callback on_physics_process(context()) :: :ok
  @callback on_event(event(), context()) :: :ok
  @callback on_frame_event(event(), context()) :: :ok
  @callback on_nif_sync(context()) :: :ok

  @optional_callbacks [
    on_ready: 1,
    on_process: 1,
    on_physics_process: 1,
    on_event: 2,
    on_frame_event: 2,
    on_nif_sync: 1
  ]
end
