defmodule Contents.Components.Category.Spawner do
  @moduledoc """
  ワールド初期化の共通コンポーネント。

  Content がオプショナルコールバック `world_size/0` を実装している場合、
  `on_ready/1` で `Core.NifBridge.set_world_size/3` を呼び出す。
  physics_scenes を持つコンテンツは、Rust 物理エンジンの physics_step が
  map_size < PLAYER_SIZE でパニックしないよう、十分なサイズを指定すること。

  ## 実装が必要な Content
  - `world_size/0` を実装し、`{width, height}` を返す
  - physics_scenes が空でないコンテンツは、本コンポーネントまたは
    専用 SpawnComponent のいずれかで set_world_size を行うこと

  ## 専用 SpawnComponent を維持するコンテンツ
  VampireSurvivor, AsteroidArena 等、entity_params 等の追加初期化が必要な
  コンテンツは従来通り専用 SpawnComponent を使用する。
  """
  @behaviour Core.Component

  @impl Core.Component
  def on_ready(world_ref) do
    content = Core.Config.current()

    if function_exported?(content, :world_size, 0) do
      {width, height} = content.world_size()
      Core.NifBridge.set_world_size(world_ref, width, height)
    end

    :ok
  end
end
