defmodule GameContent.AsteroidArena.SpawnComponent do
  @moduledoc """
  ワールド初期化・エンティティ登録を担うコンポーネント。

  AsteroidArena は武器・ボスの概念を持たないため、
  weapons / bosses は空マップとして登録する。
  """
  @behaviour GameEngine.Component

  @map_width  2048.0
  @map_height 2048.0

  @doc "アセットファイルのベースパスを返す"
  def assets_path, do: "asteroid_arena"

  @doc """
  エンティティ種別の ID マッピングを返す。

  weapons / bosses は空マップ（AsteroidArena は武器・ボスを持たない）。
  """
  def entity_registry do
    %{
      enemies: %{
        asteroid_large:  0,
        asteroid_medium: 1,
        asteroid_small:  2,
        ufo:             3,
      },
      weapons: %{},
      bosses:  %{},
    }
  end

  @impl GameEngine.Component
  def on_ready(world_ref) do
    GameEngine.NifBridge.set_world_size(world_ref, @map_width, @map_height)
    GameEngine.NifBridge.set_entity_params(
      world_ref,
      enemy_params(),
      [],
      []
    )
    :ok
  end

  # ── エンティティパラメータ定義 ────────────────────────────────────

  defp enemy_params do
    [
      # 0: Asteroid Large — 大型、低速、分裂する
      %{max_hp: 3.0,  speed: 0.0,  radius: 40.0, damage_per_sec: 15.0, render_kind: 20, particle_color: [0.7, 0.6, 0.5, 1.0], passes_obstacles: false},
      # 1: Asteroid Medium — 中型
      %{max_hp: 2.0,  speed: 0.0,  radius: 24.0, damage_per_sec: 10.0, render_kind: 21, particle_color: [0.65, 0.55, 0.45, 1.0], passes_obstacles: false},
      # 2: Asteroid Small — 小型、消滅のみ
      %{max_hp: 1.0,  speed: 0.0,  radius: 12.0, damage_per_sec: 5.0,  render_kind: 22, particle_color: [0.6, 0.5, 0.4, 1.0], passes_obstacles: false},
      # 3: UFO — 高速、プレイヤーを追跡
      %{max_hp: 5.0,  speed: 100.0, radius: 18.0, damage_per_sec: 20.0, render_kind: 23, particle_color: [0.2, 0.9, 0.8, 1.0], passes_obstacles: false},
    ]
  end
end
