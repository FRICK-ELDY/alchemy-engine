defmodule Contents.Components.Category.Spawner do
  @moduledoc """
  ワールド初期化の共通コンポーネント。

  Content がオプショナルコールバックを実装している場合に NIF へ初期値を渡す。
  - `world_size/0` → `Core.NifBridge.set_world_size/3`
  - `world_params_for_nif/0` → `Core.NifBridge.set_world_params/2`（オプション）
  - `entity_params_for_nif/0` → `Core.NifBridge.set_entity_params/5`（オプション。未実装ならスキップ）

  `physics_scenes` を持つコンテンツで `world_size/0` を実装する場合、
  Rust 側ゲームループの `physics_step` が期待するマップ寸法に合わせること。
  """
  @behaviour Core.Component

  @impl Core.Component
  def on_ready(world_ref) do
    content = Core.Config.current()

    if function_exported?(content, :world_size, 0) do
      {width, height} = content.world_size()
      Core.NifBridge.set_world_size(world_ref, width, height)
    end

    if function_exported?(content, :world_params_for_nif, 0) do
      params = content.world_params_for_nif()
      Core.NifBridge.set_world_params(world_ref, params)
    end

    if function_exported?(content, :entity_params_for_nif, 0) do
      case content.entity_params_for_nif() do
        {enemies, weapons, bosses}
        when is_list(enemies) and is_list(weapons) and is_list(bosses) ->
          Core.NifBridge.set_entity_params(world_ref, enemies, weapons, bosses, nil)

        other ->
          raise ArgumentError,
                "entity_params_for_nif/0 must return {enemies, weapons, bosses}, got: #{inspect(other)}"
      end
    end

    :ok
  end
end
