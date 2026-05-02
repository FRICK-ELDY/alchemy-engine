defmodule Content.BulletHell3D.Playing do
  @moduledoc """
  BulletHell3D のプレイ中シーン。

  Elixir 側で3D座標・弾・敵・HP を管理する。
  Rust 物理エンジンは使用しない。

  Phase 4 移行: プレイヤー・敵・弾を Contents.Objects.Core.Struct で表現。
  transform.position で座標を保持。弾は Object + vel のペアで管理。

  ## 描画と当たり判定

  敵のメッシュは円錐だが、プレイヤーとの衝突は従来どおり **XZ 平面の距離**と半径定数（円／円柱近似）のみ。
  見た目のシルエットと当たりは一致しない。弾・敵とも **Y 座標は判定に使わない**。

  ## 状態フィールド
  - `origin`          — 空間の原点 Transform（3D コンテンツ共通 state として保持、本コンテンツでは未使用）
  - `landing_object`  — プレイヤー Object への参照（同上）
  - `player_object`   — プレイヤー Object（Contents.Objects.Core.Struct）
  - `enemy_objects`   — 敵 Object リスト [%{id: int, object: Struct}]
  - `bullet_objects`  — 弾 Object リスト [%{id: int, object: Struct, vel: {vx,vy,vz}}]
  - `hp`              — 残り HP（0 でゲームオーバー）
  - `elapsed_sec`     — 経過秒数
  - `move_input`      — 移動入力 {dx, dz}
  - `invincible_ms`   — 無敵時間残り（ms）
  - `next_enemy_id`   — 敵 ID カウンタ
  - `next_bullet_id`  — 弾 ID カウンタ
  - `spawn_timer_ms`  — 敵スポーンタイマー
  - `shoot_timer_ms`  — 弾発射タイマー
  """
  @behaviour Contents.SceneBehaviour

  alias Contents.Components.Category.Procedural.Meshes.Cone
  alias Contents.Components.Category.Procedural.Meshes.Sphere
  alias Contents.Objects.Core.Struct, as: ObjectStruct
  alias Structs.Category.Space.Transform

  @tick_ms 1000.0 / 60.0
  @tick_sec 1.0 / 60.0

  # フィールドサイズ
  @field_half 10.0

  # プレイヤー・敵・弾の半径（XZ 当たりと描画スケール。敵見た目は円錐だが当たりはこの半径の円近似）
  @player_radius 0.5
  @enemy_radius 0.5
  @bullet_radius 0.15

  # プレイヤー設定
  @player_speed 6.0
  @player_initial_hp 3
  @invincible_duration_ms 1500

  # 敵設定
  @enemy_spawn_interval_ms 1000

  # 弾設定
  @bullet_speed 7.0

  # 難易度テーブル: {経過秒, 敵数上限, 発射間隔ms}
  @difficulty_table [
    {90, 30, 500},
    {60, 20, 750},
    {30, 12, 1000},
    {0, 6, 2000}
  ]

  # 描画用（プレイヤーは box_3d、敵は cone_3d、弾は sphere_3d）
  @player_half @player_radius
  @enemy_half @enemy_radius
  @camera_eye {0.0, 18.0, 14.0}
  @camera_target {0.0, 0.0, 0.0}
  @camera_up {0.0, 1.0, 0.0}
  @camera_fov 45.0
  @camera_near 0.1
  @camera_far 100.0
  @color_player {0.2, 0.4, 0.9, 1.0}
  @color_enemy {0.9, 0.2, 0.2, 1.0}
  @color_bullet {0.95, 0.85, 0.1, 1.0}
  @color_grid {0.3, 0.3, 0.3, 1.0}
  @color_sky_top {0.4, 0.6, 0.9, 1.0}
  @color_sky_bottom {0.7, 0.85, 1.0, 1.0}
  @grid_size 20.0
  @grid_divisions 20
  @max_hp 3

  # クライアントが `ASSETS_PATH` 等で解決するリポジトリ相対パス（ワイヤ上の識別子）
  @player_damage_audio_path "assets/audio/player_hurt.wav"

  @impl Contents.SceneBehaviour
  def init(_init_arg) do
    origin = Transform.new()

    player_object =
      ObjectStruct.new(
        name: "Player",
        transform: %Transform{position: {0.0, 0.0, 0.0}}
      )

    {:ok,
     %{
       origin: origin,
       landing_object: player_object,
       player_object: player_object,
       enemy_objects: [],
       bullet_objects: [],
       hp: @player_initial_hp,
       elapsed_sec: 0.0,
       move_input: {0.0, 0.0},
       invincible_ms: 0,
       next_enemy_id: 0,
       next_bullet_id: 0,
       spawn_timer_ms: 0,
       shoot_timer_ms: 1500,
       pending_audio_urls: []
     }}
  end

  @impl Contents.SceneBehaviour
  def render_type, do: :playing

  @impl Contents.SceneBehaviour
  def update(_context, state) do
    if state.hp <= 0 do
      {:transition, {:replace, Content.BulletHell3D.GameOver, %{elapsed_sec: state.elapsed_sec}},
       state}
    else
      new_state = tick(state)
      {:continue, new_state}
    end
  end

  @doc """
  1 フレーム分の描画データを組み立てる。Rendering.Render が Content.build_frame 経由で呼ぶ。
  """
  def build_frame(playing_state, context) do
    content = Core.Config.current()
    current_scene = Map.get(context, :current_scene, content.playing_scene())

    commands = build_frame_commands(playing_state)
    camera = build_frame_camera()
    ui = build_frame_ui(current_scene, content, playing_state, context)
    {commands, camera, ui}
  end

  # ── 描画組み立て ──────────────────────────────────────────────────

  defp build_frame_commands(scene_state) do
    player_object = Map.get(scene_state, :player_object)
    enemy_objects = Map.get(scene_state, :enemy_objects, [])
    bullet_objects = Map.get(scene_state, :bullet_objects, [])
    invincible_ms = Map.get(scene_state, :invincible_ms, 0)

    player = position_from_object(player_object)

    {sky_top_r, sky_top_g, sky_top_b, sky_top_a} = @color_sky_top
    {sky_bot_r, sky_bot_g, sky_bot_b, sky_bot_a} = @color_sky_bottom
    {grid_r, grid_g, grid_b, grid_a} = @color_grid
    {pr, pg, pb, _pa} = @color_player
    {er, eg, eb, ea} = @color_enemy
    {br, bg, bb, ba} = @color_bullet

    skybox_cmd =
      {:skybox, {sky_top_r, sky_top_g, sky_top_b, sky_top_a},
       {sky_bot_r, sky_bot_g, sky_bot_b, sky_bot_a}}

    grid_vertices =
      Contents.Components.Category.Procedural.Meshes.Grid.grid_plane(
        size: @grid_size,
        divisions: @grid_divisions,
        color: {grid_r, grid_g, grid_b, grid_a}
      )[:vertices]

    grid_cmd = {:grid_plane_verts, grid_vertices}

    alpha =
      if invincible_ms > 0 do
        frame = div(invincible_ms, 100)
        if rem(frame, 2) == 0, do: 0.3, else: 1.0
      else
        1.0
      end

    {px, py, pz} = player

    player_cmd =
      {:box_3d, px, py + @player_half, pz, @player_half, @player_half,
       {@player_half, pr, pg, pb, alpha}}

    enemy_cmds =
      Enum.map(enemy_objects, fn %{object: obj} ->
        {ex, ey, ez} = position_from_object(obj)

        Cone.cone_3d_command(
          ex,
          ey + @enemy_half,
          ez,
          @enemy_half,
          @enemy_half,
          @enemy_half,
          {er, eg, eb, ea}
        )
      end)

    bullet_cmds =
      Enum.map(bullet_objects, fn %{object: obj} ->
        {bx, by, bz} = position_from_object(obj)

        Sphere.sphere_3d_command(bx, by + @bullet_radius, bz, @bullet_radius, {br, bg, bb, ba})
      end)

    [skybox_cmd, grid_cmd, player_cmd] ++ enemy_cmds ++ bullet_cmds
  end

  defp position_from_object(nil), do: {0.0, 0.0, 0.0}
  defp position_from_object(%{transform: %{position: pos}}), do: pos
  defp position_from_object(_), do: {0.0, 0.0, 0.0}

  defp build_frame_camera do
    {ex, ey, ez} = @camera_eye
    {tx, ty, tz} = @camera_target
    {ux, uy, uz} = @camera_up

    {:camera_3d, {ex, ey, ez}, {tx, ty, tz}, {ux, uy, uz},
     {@camera_fov, @camera_near, @camera_far}}
  end

  defp build_frame_ui(current_scene, content, playing_state, context) do
    is_game_over = current_scene == content.game_over_scene()

    hp = Map.get(playing_state, :hp, @max_hp)
    elapsed_sec = Map.get(playing_state, :elapsed_sec, 0.0)

    room_id = Map.get(context, :room_id, :main)
    runner = content.flow_runner(room_id)

    game_over_state =
      (runner && Contents.Scenes.Stack.get_scene_state(runner, content.game_over_scene())) || %{}

    final_elapsed = Map.get(game_over_state, :elapsed_sec, elapsed_sec)
    display_elapsed = if is_game_over, do: final_elapsed, else: elapsed_sec

    elapsed_s = trunc(display_elapsed)
    m = div(elapsed_s, 60)
    s = rem(elapsed_s, 60)

    nodes =
      if is_game_over do
        [
          {:node, {:center, {0.0, 0.0}, :wrap},
           {:rect, {0.08, 0.02, 0.02, 0.92}, 16.0, {{0.78, 0.24, 0.24, 1.0}, 2.0}},
           [
             {:node, {:top_left, {0.0, 0.0}, :wrap},
              {:vertical_layout, 8.0, {50.0, 35.0, 50.0, 35.0}},
              [
                {:node, {:top_left, {0.0, 0.0}, :wrap},
                 {:text, "GAME OVER", {1.0, 0.31, 0.31, 1.0}, 40.0, true}, []},
                {:node, {:top_left, {0.0, 0.0}, :wrap},
                 {:text,
                  "Survived: #{String.pad_leading(to_string(m), 2, "0")}:#{String.pad_leading(to_string(s), 2, "0")}",
                  {0.86, 0.86, 1.0, 1.0}, 18.0, false}, []},
                {:node, {:top_left, {0.0, 0.0}, :wrap},
                 {:button, "  RETRY  ", "__retry__", {0.63, 0.16, 0.16, 1.0}, 160.0, 44.0}, []}
              ]}
           ]}
        ]
      else
        [
          {:node, {:top_left, {8.0, 8.0}, :wrap}, {:rect, {0.0, 0.0, 0.0, 0.71}, 6.0, :none},
           [
             {:node, {:top_left, {0.0, 0.0}, :wrap},
              {:horizontal_layout, 8.0, {12.0, 8.0, 12.0, 8.0}},
              [
                {:node, {:top_left, {0.0, 0.0}, :wrap},
                 {:text, "HP", {1.0, 0.39, 0.39, 1.0}, 14.0, true}, []},
                {:node, {:top_left, {0.0, 0.0}, :wrap},
                 {:progress_bar, hp * 1.0, @max_hp * 1.0, 120.0, 18.0,
                  {{0.31, 0.86, 0.31, 1.0}, {0.86, 0.71, 0.0, 1.0}, {0.86, 0.24, 0.24, 1.0},
                   {0.24, 0.08, 0.08, 1.0}, 4.0}}, []},
                {:node, {:top_left, {0.0, 0.0}, :wrap},
                 {:text, "#{hp}/#{@max_hp}", {1.0, 1.0, 1.0, 1.0}, 13.0, false}, []},
                {:node, {:top_left, {0.0, 0.0}, :wrap}, :separator, []},
                {:node, {:top_left, {0.0, 0.0}, :wrap},
                 {:text,
                  "#{String.pad_leading(to_string(m), 2, "0")}:#{String.pad_leading(to_string(s), 2, "0")}",
                  {1.0, 1.0, 1.0, 1.0}, 14.0, false}, []}
              ]}
           ]}
        ]
      end

    {:canvas, nodes}
  end

  # ── メインティック ────────────────────────────────────────────────

  defp tick(state) do
    {dx, dz} = Map.get(state, :move_input, {0.0, 0.0})
    elapsed_sec = state.elapsed_sec + @tick_sec
    {max_enemies, shoot_interval_ms} = difficulty(elapsed_sec)

    player_pos = position_from_object(state.player_object)
    new_player_pos = move_player(player_pos, dx, dz)

    bullet_objects = move_bullets(state.bullet_objects)

    enemy_positions = extract_positions(state.enemy_objects)
    new_enemy_positions = move_enemies(enemy_positions, new_player_pos)
    enemy_objects = put_positions(state.enemy_objects, new_enemy_positions)

    {enemy_objects, next_enemy_id, spawn_timer_ms} =
      update_spawn_timer(enemy_objects, state.spawn_timer_ms, state.next_enemy_id, max_enemies)

    {bullet_objects, next_bullet_id, shoot_timer_ms} =
      update_shoot_timer(
        bullet_objects,
        state.shoot_timer_ms,
        state.next_bullet_id,
        enemy_objects,
        new_player_pos,
        shoot_interval_ms
      )

    {hp, invincible_ms} =
      if state.invincible_ms > 0 do
        {state.hp, state.invincible_ms - trunc(@tick_ms)}
      else
        bullet_pos_list = Enum.map(bullet_objects, fn %{object: o} -> position_from_object(o) end)
        check_damage(state.hp, new_player_pos, new_enemy_positions, bullet_pos_list)
      end

    pending_audio_urls =
      if state.invincible_ms == 0 and hp < state.hp do
        Map.get(state, :pending_audio_urls, []) ++ [@player_damage_audio_path]
      else
        Map.get(state, :pending_audio_urls, [])
      end

    new_player_object = put_position(state.player_object, new_player_pos)

    %{
      state
      | player_object: new_player_object,
        landing_object: new_player_object,
        enemy_objects: enemy_objects,
        bullet_objects: bullet_objects,
        hp: max(0, hp),
        elapsed_sec: elapsed_sec,
        invincible_ms: max(0, invincible_ms),
        next_enemy_id: next_enemy_id,
        next_bullet_id: next_bullet_id,
        spawn_timer_ms: spawn_timer_ms,
        shoot_timer_ms: shoot_timer_ms,
        pending_audio_urls: pending_audio_urls
    }
  end

  defp extract_positions(enemy_objects) do
    Enum.map(enemy_objects, fn %{object: obj} -> position_from_object(obj) end)
  end

  defp put_position(object, {x, _y, z}) do
    %{object | transform: %{object.transform | position: {x, 0.0, z}}}
  end

  defp put_positions(enemy_objects, positions) do
    Enum.zip(enemy_objects, positions)
    |> Enum.map(fn {%{id: id, object: obj}, pos} ->
      %{id: id, object: put_position(obj, pos)}
    end)
  end

  # ── 難易度計算 ────────────────────────────────────────────────────

  defp difficulty(elapsed_sec) do
    fallback = {6, 2000}

    case Enum.find(@difficulty_table, fn {threshold, _max, _interval} ->
           elapsed_sec >= threshold
         end) do
      {_threshold, max_enemies, shoot_interval_ms} -> {max_enemies, shoot_interval_ms}
      nil -> fallback
    end
  end

  # ── プレイヤー移動 ────────────────────────────────────────────────

  defp move_player({px, _py, pz}, dx, dz) do
    speed = @player_speed * @tick_sec
    len = :math.sqrt(dx * dx + dz * dz)

    {nx, nz} =
      if len > 0.001 do
        {px + dx / len * speed, pz + dz / len * speed}
      else
        {px, pz}
      end

    {clamp(nx, -@field_half, @field_half), 0.0, clamp(nz, -@field_half, @field_half)}
  end

  # ── 弾移動 ────────────────────────────────────────────────────────

  defp move_bullets(bullet_objects) do
    bullet_objects
    |> Enum.map(fn %{id: id, object: obj, vel: {vx, _vy, vz}} ->
      {bx, by, bz} = position_from_object(obj)
      new_obj = put_position(obj, {bx + vx * @tick_sec, by, bz + vz * @tick_sec})
      %{id: id, object: new_obj, vel: {vx, 0.0, vz}}
    end)
    |> Enum.filter(fn %{object: obj} ->
      {bx, _by, bz} = position_from_object(obj)
      abs(bx) <= @field_half + 2.0 and abs(bz) <= @field_half + 2.0
    end)
  end

  @enemy_diameter @enemy_radius * 2

  # ── 敵移動 ────────────────────────────────────────────────────────

  defp move_enemies(positions, {px, _py, pz}) do
    speed = 2.5 * @tick_sec

    positions
    |> Enum.map(fn {ex, ey, ez} ->
      ddx = px - ex
      ddz = pz - ez
      len = :math.sqrt(ddx * ddx + ddz * ddz)

      if len > 0.001 do
        {ex + ddx / len * speed, ey, ez + ddz / len * speed}
      else
        {ex, ey, ez}
      end
    end)
    |> separate_positions()
  end

  defp separate_positions([]), do: []
  defp separate_positions([p]), do: [p]

  defp separate_positions(positions) do
    indexed = Enum.with_index(positions)
    deltas = collect_separation_deltas(indexed, %{})

    Enum.map(indexed, fn {{ex, ey, ez}, i} ->
      case Map.get(deltas, i) do
        nil -> {ex, ey, ez}
        {ddx, ddz} -> {ex + ddx, ey, ez + ddz}
      end
    end)
  end

  defp collect_separation_deltas([], acc), do: acc

  defp collect_separation_deltas([{pos_i, i} | tail], acc) do
    acc =
      Enum.reduce(tail, acc, fn {pos_j, j}, a ->
        push_apart_positions(pos_i, i, pos_j, j, a)
      end)

    collect_separation_deltas(tail, acc)
  end

  defp push_apart_positions({ix, _iy, iz}, i, {jx, _jy, jz}, j, acc) do
    dx = ix - jx
    dz = iz - jz
    d2 = dx * dx + dz * dz

    if d2 < @enemy_diameter * @enemy_diameter and d2 > 0.0001 do
      d = :math.sqrt(d2)
      overlap = (@enemy_diameter - d) * 0.5
      nx = dx / d * overlap
      nz = dz / d * overlap

      acc
      |> Map.update(i, {nx, nz}, fn {ax, az} -> {ax + nx, az + nz} end)
      |> Map.update(j, {-nx, -nz}, fn {ax, az} -> {ax - nx, az - nz} end)
    else
      acc
    end
  end

  # ── スポーンタイマー ──────────────────────────────────────────────

  defp update_spawn_timer(enemy_objects, timer_ms, next_id, max_enemies) do
    new_timer = timer_ms - trunc(@tick_ms)

    if new_timer <= 0 and length(enemy_objects) < max_enemies do
      {new_entry, new_id} = spawn_enemy(next_id)
      {enemy_objects ++ [new_entry], new_id, @enemy_spawn_interval_ms}
    else
      {enemy_objects, next_id, max(0, new_timer)}
    end
  end

  defp spawn_enemy(id) do
    angle = :rand.uniform() * 2.0 * :math.pi()
    dist = @field_half + 1.5
    x = :math.cos(angle) * dist
    z = :math.sin(angle) * dist

    object =
      ObjectStruct.new(
        name: "Enemy_#{id}",
        transform: %Transform{position: {x, 0.0, z}}
      )

    {%{id: id, object: object}, id + 1}
  end

  # ── 発射タイマー ──────────────────────────────────────────────────

  defp update_shoot_timer(
         bullet_objects,
         timer_ms,
         next_id,
         enemy_objects,
         player_pos,
         shoot_interval_ms
       ) do
    new_timer = timer_ms - trunc(@tick_ms)

    if new_timer <= 0 and enemy_objects != [] do
      {new_bullets, new_id} = fire_bullets(enemy_objects, player_pos, next_id)
      {bullet_objects ++ new_bullets, new_id, shoot_interval_ms}
    else
      {bullet_objects, next_id, max(0, new_timer)}
    end
  end

  defp fire_bullets(enemy_objects, {px, _py, pz}, next_id) do
    Enum.reduce(enemy_objects, {[], next_id}, fn %{object: e_obj}, {acc, id} ->
      {ex, _ey, ez} = position_from_object(e_obj)
      ddx = px - ex
      ddz = pz - ez
      len = :math.sqrt(ddx * ddx + ddz * ddz)

      if len > 0.001 do
        vx = ddx / len * @bullet_speed
        vz = ddz / len * @bullet_speed

        bullet_obj =
          ObjectStruct.new(
            name: "Bullet_#{id}",
            transform: %Transform{position: position_from_object(e_obj)}
          )

        bullet = %{id: id, object: bullet_obj, vel: {vx, 0.0, vz}}
        {acc ++ [bullet], id + 1}
      else
        {acc, id}
      end
    end)
  end

  # ── 衝突判定（XZ のみ・Y は無視。敵は円錐表示だがヒットボックスは円近似）────────

  defp check_damage(hp, {px, _py, pz}, enemy_positions, bullet_positions) do
    enemy_hit =
      Enum.any?(enemy_positions, fn {ex, _ey, ez} ->
        dist2(px, pz, ex, ez) <
          (@player_radius + @enemy_radius) * (@player_radius + @enemy_radius)
      end)

    bullet_hit =
      Enum.any?(bullet_positions, fn {bx, _by, bz} ->
        dist2(px, pz, bx, bz) <
          (@player_radius + @bullet_radius) * (@player_radius + @bullet_radius)
      end)

    if enemy_hit or bullet_hit do
      {hp - 1, @invincible_duration_ms}
    else
      {hp, 0}
    end
  end

  defp dist2(ax, az, bx, bz) do
    dx = ax - bx
    dz = az - bz
    dx * dx + dz * dz
  end

  defp clamp(v, lo, hi), do: max(lo, min(hi, v))
end
