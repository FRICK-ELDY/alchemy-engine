defmodule Contents.Components.Category.Spawner do
  @moduledoc """
  ワールド初期化の共通コンポーネント。

  Content がオプショナルコールバックを実装している場合に初期化を行う。
  - `world_size/0` → `Core.NifBridge.set_world_size/3`
  - `entity_params_for_nif/0` → `Core.NifBridge.set_entity_params/5`
    （enemies, weapons, bosses の 3 要素タプルを返すこと）

  physics_scenes を持つコンテンツは、Rust 物理エンジンの physics_step が
  map_size < PLAYER_SIZE でパニックしないよう、十分なサイズを指定すること。

  ## 専用 SpawnComponent を維持するコンテンツ
  VampireSurvivor 等、武器フォーミュラ等の追加初期化が必要なコンテンツは
  従来通り専用 SpawnComponent を使用する。
  """
  @behaviour Core.Component

  @impl Core.Component
  def on_ready(world_ref) do
    content = Core.Config.current()

    if function_exported?(content, :world_size, 0) do
      {width, height} = content.world_size()
      Core.NifBridge.set_world_size(world_ref, width, height)
    end

    if function_exported?(content, :entity_params_for_nif, 0) do
      case content.entity_params_for_nif() do
        {enemies, weapons, bosses} when is_list(enemies) and is_list(weapons) and is_list(bosses) ->
          Core.NifBridge.set_entity_params(world_ref, enemies, weapons, bosses, nil)

        other ->
          raise ArgumentError,
            "entity_params_for_nif/0 must return {enemies, weapons, bosses}, got: #{inspect(other)}"
      end
    end

    :ok
  end
end
