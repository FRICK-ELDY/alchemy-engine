defmodule Contents.Components.Category.PhysicsEntity do
  @moduledoc """
  physics_scenes を持つコンテンツ向けのエンティティイベントアダプタ。

  Content がオプショナルコールバックを実装している場合に処理を行う。
  - `enemy_damage_this_frame/1` → on_nif_sync で frame_injection に注入
  - `handle_enemy_killed/4` → on_frame_event で enemy_killed イベント時に呼ぶ
  - player_snapshot → physics_scenes を持つ Content の playing_state から注入
  - player_damaged → playing_state の player_hp 減算・invincible_until_ms 設定

  NIF 物理エンジンと連携するコンテンツで使用する（残存コンテンツでは未使用。フェーズ 2 で整理予定）。
  """
  @behaviour Core.Component

  @impl Core.Component
  def on_nif_sync(context) do
    content = Core.Config.current()
    inj = Process.get(:frame_injection, %{})

    inj =
      inj
      |> merge_player_snapshot(content, context)
      |> merge_enemy_damage_this_frame(content, context)

    Process.put(:frame_injection, inj)
    :ok
  end

  @impl Core.Component
  def on_frame_event({:enemy_killed, kind_id, x_bits, y_bits, _}, context) do
    content = Core.Config.current()

    if function_exported?(content, :handle_enemy_killed, 4) and context[:world_ref] do
      x = bits_to_f32(x_bits)
      y = bits_to_f32(y_bits)
      content.handle_enemy_killed(context.world_ref, kind_id, x, y)
    end

    :ok
  end

  def on_frame_event({:player_damaged, damage_x1000, _, _, _}, context) do
    damage = damage_x1000 / 1000.0
    content = Core.Config.current()
    runner = content.flow_runner(Map.get(context, :room_id, :main))

    if runner and context[:world_ref] do
      invincible_until_ms = context.now + invincible_duration_ms(content)

      Contents.Scenes.Stack.update_by_scene_type(
        runner,
        content.playing_scene(),
        &apply_player_damage(&1, damage, invincible_until_ms)
      )
    end

    :ok
  end

  def on_frame_event(_event, _context), do: :ok

  defp merge_player_snapshot(inj, content, context) do
    if content.physics_scenes() == [] do
      inj
    else
      runner = content.flow_runner(Map.get(context, :room_id, :main))

      playing_state =
        (runner && Contents.Scenes.Stack.get_scene_state(runner, content.playing_scene())) || %{}

      player_hp = Map.get(playing_state, :player_hp, 100.0)
      invincible_until_ms = Map.get(playing_state, :invincible_until_ms)
      now_ms = context.now

      invincible_timer =
        case invincible_until_ms do
          nil -> 0.0
          until when until > now_ms -> (until - now_ms) / 1000.0
          _ -> 0.0
        end

      Map.put(inj, :player_snapshot, {player_hp, invincible_timer})
    end
  end

  defp merge_enemy_damage_this_frame(inj, content, context) do
    if function_exported?(content, :enemy_damage_this_frame, 1) do
      list = content.enemy_damage_this_frame(context)
      Map.put(inj, :enemy_damage_this_frame, list)
    else
      inj
    end
  end

  defp apply_player_damage(state, damage, invincible_until_ms) do
    state
    |> Map.update(:player_hp, 100.0, fn hp -> max(0.0, hp - damage) end)
    |> Map.put(:invincible_until_ms, invincible_until_ms)
  end

  defp invincible_duration_ms(content) do
    if function_exported?(content, :invincible_duration_ms, 0) do
      content.invincible_duration_ms()
    else
      500
    end
  end

  defp bits_to_f32(bits) when is_integer(bits) do
    <<f::float-32>> = <<bits::unsigned-32>>
    f
  end
end
