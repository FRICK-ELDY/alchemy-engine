defmodule Content.VampireSurvivor.Scenes.BossAlert do
  @moduledoc """
  ボス出現警告シーン。一定時間後に Elixir SSoT でボスをスポーンして Playing に戻る。

  spawn_special_entity は呼ばず、Playing state を直接更新する。
  """
  @behaviour Contents.SceneBehaviour

  alias Content.VampireSurvivor.BossSystem
  alias Content.VampireSurvivor.Scenes.Playing

  require Logger

  @map_width 4096.0
  @map_height 4096.0

  @impl Contents.SceneBehaviour
  def init(%{boss_kind: boss_kind, boss_name: boss_name, alert_ms: alert_ms}) do
    {:ok, %{boss_kind: boss_kind, boss_name: boss_name, alert_ms: alert_ms}}
  end

  @impl Contents.SceneBehaviour
  def render_type, do: :boss_alert

  @impl Contents.SceneBehaviour
  def update(context, %{boss_kind: boss_kind, boss_name: boss_name, alert_ms: alert_ms} = state) do
    now = context.now
    elapsed = now - alert_ms

    if elapsed >= BossSystem.alert_duration_ms() do
      do_spawn_boss(context, boss_kind, boss_name)
      {:transition, :pop, state}
    else
      {:continue, state}
    end
  end

  defp do_spawn_boss(context, boss_kind, boss_name) do
    kind_id =
      Content.VampireSurvivor.entity_registry().bosses[boss_kind] ||
        raise "Unknown boss kind: #{inspect(boss_kind)}"

    {px, py} = Core.NifBridge.get_player_pos(context.world_ref)
    runner = Core.Config.current().flow_runner(:main)

    if runner do
      Contents.SceneStack.update_by_module(
        runner,
        Playing,
        &Playing.apply_boss_spawn_full(&1, kind_id, px, py, @map_width, @map_height)
      )
    end

    Logger.info("[BOSS] Spawned: #{boss_name}")
  end
end
