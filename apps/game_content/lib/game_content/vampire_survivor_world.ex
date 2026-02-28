defmodule GameContent.VampireSurvivorWorld do
  @moduledoc """
  ヴァンパイアサバイバーの WorldBehaviour 実装。

  マップ・エンティティ種別・アセットパスを定義する。
  同じ World に対して複数の Rule を適用できる。
  """
  @behaviour GameEngine.WorldBehaviour

  @impl GameEngine.WorldBehaviour
  def assets_path, do: "vampire_survivor"

  @impl GameEngine.WorldBehaviour
  def entity_registry do
    %{
      enemies: %{slime: 0, bat: 1, golem: 2, skeleton: 3, ghost: 4},
      weapons: %{
        magic_wand: 0, axe: 1, cross: 2, whip: 3, fireball: 4, lightning: 5, garlic: 6
      },
      bosses: %{slime_king: 0, bat_lord: 1, stone_golem: 2},
    }
  end
end
