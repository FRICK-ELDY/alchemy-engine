defmodule GameContent.SimpleBox3D.SpawnComponent do
  @moduledoc """
  SimpleBox3D のワールド初期化コンポーネント。

  Phase R-6: SimpleBox3D は Rust 物理エンジン（ECS）を使用しない。
  ゲームロジックは Elixir 側のシーン state で完結するため、
  `on_ready/1` では最小限のワールドサイズ設定のみ行う。
  """
  @behaviour GameEngine.Component

  # Rust 物理エンジンの PLAYER_SIZE は 64.0 px。
  # map_width - PLAYER_SIZE が負にならないよう、十分大きな値を設定する。
  # SimpleBox3D は物理エンジンを実際には使わないが、ループは常に動いているため
  # clamp(0.0, map_size - PLAYER_SIZE) がパニックしないよう最低 128.0 以上が必要。
  @map_size 2048.0

  @impl GameEngine.Component
  def on_ready(world_ref) do
    GameEngine.NifBridge.set_world_size(world_ref, @map_size, @map_size)
    :ok
  end
end
