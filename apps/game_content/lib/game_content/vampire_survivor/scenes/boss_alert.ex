defmodule GameContent.VampireSurvivor.Scenes.BossAlert do
  @moduledoc """
  ボス出現警告シーン。一定時間後にボスをスポーンして Playing に戻る。
  """
  @behaviour GameEngine.SceneBehaviour

  require Logger

  @impl GameEngine.SceneBehaviour
  def init(%{boss_kind: boss_kind, boss_name: boss_name, alert_ms: alert_ms}) do
    {:ok, %{boss_kind: boss_kind, boss_name: boss_name, alert_ms: alert_ms}}
  end

  @impl GameEngine.SceneBehaviour
  def render_type, do: :boss_alert

  @impl GameEngine.SceneBehaviour
  def update(context, %{boss_kind: boss_kind, boss_name: boss_name, alert_ms: alert_ms} = state) do
    world_ref = context.world_ref
    now = context.now
    elapsed = now - alert_ms

    if elapsed >= GameContent.VampireSurvivor.BossSystem.alert_duration_ms() do
      GameEngine.spawn_boss(world_ref, boss_kind)
      Logger.info("[BOSS] Spawned: #{boss_name}")
      {:transition, :pop, state}
    else
      {:continue, state}
    end
  end
end
