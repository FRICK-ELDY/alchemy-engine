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
       last_ufo_spawn_ms: 0,
       # nil の場合は update/2 内で context.start_ms にフォールバックする
       # （init 時点では start_ms が不明なため nil で初期化）
       last_spawn_ms: nil,
       player_hp: 100.0,
       player_max_hp: 100.0
     }}
  end

  @impl GameEngine.SceneBehaviour
  def render_type, do: :playing

  @impl GameEngine.SceneBehaviour
  def update(context, state) do
    elapsed = context.elapsed
    player_hp = Map.get(state, :player_hp, 100.0)

    if player_hp <= 0.0 do
      Logger.info("[GAME OVER] Player HP reached 0 at #{div(elapsed, 1000)}s")
      {:transition, {:replace, GameContent.AsteroidArena.Scenes.GameOver, %{}}, state}
    else
      last_spawn_ms = Map.get(state, :last_spawn_ms) || context.start_ms
      new_last_spawn = SpawnSystem.maybe_spawn(context.world_ref, elapsed, last_spawn_ms)
      new_last_ufo = SpawnSystem.maybe_spawn_ufo(context.world_ref, elapsed, state.last_ufo_spawn_ms)

      new_state = %{state | last_ufo_spawn_ms: new_last_ufo, last_spawn_ms: new_last_spawn}

      {:continue, new_state}
    end
  end

  def accumulate_exp(state, exp_gain) do
    %{state | exp: state.exp + exp_gain}
  end
end
