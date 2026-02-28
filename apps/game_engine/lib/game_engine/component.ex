defmodule GameEngine.Component do
  @moduledoc """
  ゲームコンテンツの構成単位となるビヘイビア。

  コンテンツはコンポーネントの集合として表現される。
  各コールバックはオプションであり、必要なものだけ実装すればよい。

  ## コールバック

  - `on_ready/1`           — 初期化時（1回）
  - `on_process/1`         — 毎フレーム（Elixir 側）
  - `on_physics_process/1` — 物理フレーム（60Hz）
  - `on_event/2`           — イベント発生時

  ## コンテキスト

  `context` マップには以下のシーン遷移 API が含まれる：

  - `context.push_scene.(mod, init_arg)`  — シーンをスタックに積む
  - `context.pop_scene.()`               — 現在のシーンをスタックから取り出す
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

  @callback on_ready(world_ref())          :: :ok
  @callback on_process(context())          :: :ok
  @callback on_physics_process(context())  :: :ok
  @callback on_event(event(), context())   :: :ok

  @optional_callbacks [on_ready: 1, on_process: 1, on_physics_process: 1, on_event: 2]
end
