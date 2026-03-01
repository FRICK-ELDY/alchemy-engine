defmodule GameContent.AsteroidArena.Scenes.Playing do
  @moduledoc """
  AsteroidArena のプレイ中シーン。

  武器・ボス・レベルアップの概念を持たない。
  小惑星と UFO のスポーン、プレイヤー死亡判定のみを行う。
  """
  @behaviour GameEngine.SceneBehaviour

  require Logger

  alias GameContent.AsteroidArena.SpawnSystem

  @impl GameEngine.SceneBehaviour
  def init(_init_arg) do
    {:ok,
     %{
       exp: 0,
       last_ufo_spawn_ms: 0
     }}
  end

  @impl GameEngine.SceneBehaviour
  def render_type, do: :playing

  @impl GameEngine.SceneBehaviour
  def update(context, state) do
    %{
      world_ref: world_ref,
      elapsed: elapsed,
      last_spawn_ms: last_spawn_ms,
      player_hp: player_hp
    } = context

    if player_hp <= 0.0 do
      Logger.info("[GAME OVER] Player HP reached 0 at #{div(elapsed, 1000)}s")
      {:transition, {:replace, GameContent.AsteroidArena.Scenes.GameOver, %{}}, state}
    else
      new_last_spawn = SpawnSystem.maybe_spawn(world_ref, elapsed, last_spawn_ms)
      new_last_ufo = SpawnSystem.maybe_spawn_ufo(world_ref, elapsed, state.last_ufo_spawn_ms)

      new_state = %{state | last_ufo_spawn_ms: new_last_ufo}

      {:continue, new_state, %{context_updates: %{last_spawn_ms: new_last_spawn}}}
    end
  end

  # ── GameEvents から SceneManager 経由で呼ばれるヘルパー ────────────

  @doc "EXP を加算する（GameEvents の apply_event から呼ばれる）"
  def accumulate_exp(state, exp_gain) do
    %{state | exp: state.exp + exp_gain}
  end

  @doc "ボスなし: 何もしない（GameEvents の apply_event から呼ばれる）"
  def apply_boss_spawn(state, _boss_kind), do: state

  @doc "ボスなし: 何もしない（GameEvents の apply_event から呼ばれる）"
  def apply_boss_damaged(state, _damage), do: state

  @doc "ボスなし: 何もしない（GameEvents の apply_event から呼ばれる）"
  def apply_boss_defeated(state), do: state
end
