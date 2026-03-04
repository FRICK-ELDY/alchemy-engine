defmodule Content.SimpleBox3D.SpawnComponent do
  @moduledoc """
  SimpleBox3D のワールド初期化コンポーネント。

  Phase R-6: SimpleBox3D は Rust 物理エンジン（ECS）を使用しない。
  ゲームロジックは Elixir 側のシーン state で完結するため、
  `on_ready/1` では最小限のワールドサイズ設定のみ行う。
  """
  @behaviour Core.Component

  # SimpleBox3D は Rust 物理エンジンを使わないが、エンジンループは常に動いている。
  # game_physics の physics_step.rs が `clamp(0.0, map_width - PLAYER_SIZE)` を呼ぶため、
  # map_size < PLAYER_SIZE になるとパニックする（PLAYER_SIZE は Rust 側の定数で現在 64.0 px）。
  # この値は Rust 側の定数変更に追従できないため、将来的には NIF 経由で定数を取得するか
  # Rust 側でフォールバック処理を追加することが望ましい（残課題）。
  @map_size 2048.0

  @impl Core.Component
  def on_ready(world_ref) do
    Core.NifBridge.set_world_size(world_ref, @map_size, @map_size)
    :ok
  end
end
