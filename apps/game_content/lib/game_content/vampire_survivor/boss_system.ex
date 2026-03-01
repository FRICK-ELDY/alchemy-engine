defmodule GameContent.VampireSurvivor.BossSystem do
  @moduledoc """
  ボスエネミーの出現スケジュールを管理する純粋関数モジュール（ヴァンサバ固有）。
  """

  @boss_schedule [
    {180, :slime_king, "Slime King"},
    {360, :bat_lord, "Bat Lord"},
    {540, :stone_golem, "Stone Golem"}
  ]

  @boss_alert_duration_ms 3_000

  def check_spawn(elapsed_sec, spawned_bosses) when is_list(spawned_bosses) do
    @boss_schedule
    |> Enum.find(fn {trigger_sec, kind, _name} ->
      elapsed_sec >= trigger_sec and kind not in spawned_bosses
    end)
    |> case do
      {_sec, kind, name} -> {:spawn, kind, name}
      nil -> :no_boss
    end
  end

  def alert_duration_ms, do: @boss_alert_duration_ms

  def boss_label(:slime_king), do: "Slime King"
  def boss_label(:bat_lord), do: "Bat Lord"
  def boss_label(:stone_golem), do: "Stone Golem"
  def boss_label(other), do: to_string(other)
end
