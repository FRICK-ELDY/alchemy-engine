defmodule GameContent.VampireSurvivor.RenderComponent do
  @moduledoc """
  毎フレーム DrawCommand リストを組み立てて push_render_frame NIF に送るコンポーネント。

  Phase R-2: render_snapshot.rs の責務を Elixir 側（game_content）に移した。
  GameWorldInner への直接依存を排除し、get_render_entities NIF 経由で
  描画用データを取得する。

  ## on_nif_sync
  1. `get_render_entities/1` で物理ワールドのスナップショットを取得する
  2. Playing シーン state から HUD データを組み立てる
  3. `push_render_frame/4` で RenderFrameBuffer に書き込む
  """
  @behaviour GameEngine.Component

  # Rust 側の constants.rs と同値
  @screen_width 1280.0
  @screen_height 720.0
  @player_size 64.0

  # 武器レジストリ（atom → kind_id）をコンパイル時定数として保持する。
  # entity_registry/0 は静的マップを返すため、毎フレームの GenServer 呼び出しを避ける。
  @weapon_registry GameContent.VampireSurvivor.SpawnComponent.entity_registry().weapons

  @impl GameEngine.Component
  def on_nif_sync(context) do
    content = GameEngine.Config.current()
    playing_state = GameEngine.SceneManager.get_scene_state(content.playing_scene()) || %{}

    {{player_x, player_y, frame_id, enemy_count, bullet_count}, {enemies, bullets, particles},
     {items, obstacles, boss, score_popups}} =
      GameEngine.NifBridge.get_render_entities(context.world_ref)

    anim_frame = rem(div(frame_id, 4), 4)

    commands =
      build_commands(
        player_x,
        player_y,
        anim_frame,
        enemies,
        bullets,
        particles,
        items,
        obstacles,
        boss
      )

    camera = build_camera(player_x, player_y)
    hud = build_hud(context, playing_state, enemy_count, bullet_count, boss, score_popups)

    GameEngine.NifBridge.push_render_frame(
      context.render_buf_ref,
      commands,
      camera,
      hud
    )

    :ok
  end

  # ── DrawCommand 組み立て ──────────────────────────────────────────

  defp build_commands(
         player_x,
         player_y,
         anim_frame,
         enemies,
         bullets,
         particles,
         items,
         obstacles,
         boss
       ) do
    []
    |> push_player(player_x, player_y, anim_frame)
    |> push_boss(boss)
    |> push_enemies(enemies, anim_frame)
    |> push_bullets(bullets)
    |> push_particles(particles)
    |> push_items(items)
    |> push_obstacles(obstacles)
    |> Enum.reverse()
  end

  defp push_player(acc, x, y, frame) do
    [{:player_sprite, x, y, frame} | acc]
  end

  defp push_boss(acc, {:alive, x, y, radius, render_kind}) do
    sprite_size = radius * 2.0
    [{:sprite, x - sprite_size / 2.0, y - sprite_size / 2.0, render_kind, 0} | acc]
  end

  defp push_boss(acc, {:none, _, _, _, _}), do: acc

  defp push_enemies(acc, enemies, anim_frame) do
    Enum.reduce(enemies, acc, fn {x, y, kind_id}, a ->
      [{:sprite, x, y, kind_id, anim_frame} | a]
    end)
  end

  defp push_bullets(acc, bullets) do
    Enum.reduce(bullets, acc, fn {x, y, render_kind}, a ->
      [{:sprite, x, y, render_kind, 0} | a]
    end)
  end

  defp push_particles(acc, particles) do
    Enum.reduce(particles, acc, fn {x, y, r, g, b, alpha, size}, a ->
      [{:particle, x, y, r, g, b, {alpha, size}} | a]
    end)
  end

  defp push_items(acc, items) do
    Enum.reduce(items, acc, fn {x, y, render_kind}, a ->
      [{:item, x, y, render_kind} | a]
    end)
  end

  defp push_obstacles(acc, obstacles) do
    Enum.reduce(obstacles, acc, fn {x, y, radius, kind}, a ->
      [{:obstacle, x, y, radius, kind} | a]
    end)
  end

  # ── カメラ組み立て ─────────────────────────────────────────────────

  defp build_camera(player_x, player_y) do
    cam_x = player_x + @player_size / 2.0 - @screen_width / 2.0
    cam_y = player_y + @player_size / 2.0 - @screen_height / 2.0
    {:camera_2d, cam_x, cam_y}
  end

  # ── HUD 組み立て ───────────────────────────────────────────────────

  defp build_hud(context, playing_state, enemy_count, bullet_count, boss, score_popups) do
    hp = Map.get(playing_state, :player_hp, 100.0)
    max_hp = Map.get(playing_state, :player_max_hp, 100.0)
    score = Map.get(playing_state, :score, 0)
    elapsed_ms = Map.get(playing_state, :elapsed_ms) || context.elapsed
    elapsed_seconds = elapsed_ms / 1000.0
    level = Map.get(playing_state, :level, 1)
    exp = Map.get(playing_state, :exp, 0)
    exp_to_next = Map.get(playing_state, :exp_to_next, 10)
    level_up_pending = Map.get(playing_state, :level_up_pending, false)
    weapon_choices = Map.get(playing_state, :weapon_choices, []) |> Enum.map(&to_string/1)
    weapon_levels = build_weapon_levels(playing_state)
    # TODO(Phase R-3): magnet_timer を get_render_entities の戻り値に含めるか、
    # playing_state で管理して push_render_frame に渡す。
    # 現状は磁石エフェクトの HUD 表示（残り時間バー）が機能しない。
    magnet_timer = 0.0
    kill_count = Map.get(playing_state, :kill_count, 0)

    # TODO(Phase R-3): screen_flash_alpha（無敵フラッシュ）は GameWorldInner.player.invincible_timer
    # を参照していたが、get_render_entities に含まれていないため 0.0 固定。
    # invincible_timer を get_render_entities に追加するか、Elixir 側で
    # player_damaged イベントをトリガーにタイマーを管理する方針を決定する。
    screen_flash_alpha = 0.0

    boss_info = build_boss_info(boss, playing_state)

    weapon_upgrade_descs =
      if weapon_choices != [] do
        slots = weapon_slots_for_nif(playing_state)

        GameEngine.NifBridge.get_weapon_upgrade_descs(
          context.world_ref,
          weapon_choices,
          slots
        )
      else
        []
      end

    {
      {hp, max_hp, score, elapsed_seconds, level, exp, exp_to_next},
      {enemy_count, bullet_count, 0.0, level_up_pending},
      {weapon_choices, weapon_upgrade_descs, weapon_levels},
      {magnet_timer, 0, boss_info, :playing, screen_flash_alpha, score_popups, kill_count}
    }
  end

  defp build_boss_info({:alive, _x, _y, _radius, _render_kind}, playing_state) do
    boss_hp = Map.get(playing_state, :boss_hp)
    boss_max_hp = Map.get(playing_state, :boss_max_hp)

    if boss_hp != nil and boss_max_hp != nil do
      {"Boss", boss_hp, boss_max_hp}
    else
      :none
    end
  end

  defp build_boss_info({:none, _, _, _, _}, _playing_state), do: :none

  defp build_weapon_levels(playing_state) do
    weapon_levels = Map.get(playing_state, :weapon_levels, %{})

    Enum.map(weapon_levels, fn {weapon_name, level} ->
      {"weapon_#{weapon_name}", level}
    end)
  end

  defp weapon_slots_for_nif(playing_state) do
    weapon_levels = Map.get(playing_state, :weapon_levels, %{})

    Enum.flat_map(weapon_levels, fn {weapon_name, level} ->
      case Map.get(@weapon_registry, weapon_name) do
        nil -> []
        kind_id -> [{kind_id, level}]
      end
    end)
  end
end
