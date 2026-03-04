defmodule Content.BulletHell3D.Scenes.Playing do
  @moduledoc """
  BulletHell3D のプレイ中シーン。

  Elixir 側で3D座標・弾・敵・HP を管理する。
  Rust 物理エンジンは使用しない。

  ## 状態フィールド
  - `player`        — プレイヤー座標 {x, y, z}
  - `enemies`       — 敵リスト [%{pos: {x,y,z}, id: integer}]
  - `bullets`       — 弾リスト [%{pos: {x,y,z}, vel: {vx,vy,vz}, id: integer}]
  - `hp`            — 残り HP（0 でゲームオーバー）
  - `elapsed_sec`   — 経過秒数（難易度スケーリングに使用）
  - `move_input`    — 移動入力 {dx, dz}
  - `invincible_ms` — ダメージ後の無敵時間残り（ms）
  - `next_enemy_id` — 敵 ID カウンタ
  - `next_bullet_id`— 弾 ID カウンタ
  - `spawn_timer_ms`— 次の敵スポーンまでの残り時間（ms）
  - `shoot_timer_ms`— 次の弾発射までの残り時間（ms）
  """
  @behaviour Core.SceneBehaviour

  @tick_ms 1000.0 / 60.0
  @tick_sec 1.0 / 60.0

  # フィールドサイズ
  @field_half 10.0

  # プレイヤー設定
  @player_speed 6.0
  @player_radius 0.5
  @player_initial_hp 3
  @invincible_duration_ms 1500

  # 敵設定
  @enemy_radius 0.5
  @enemy_spawn_interval_ms 1000

  # 弾設定
  @bullet_radius 0.15
  @bullet_speed 7.0

  # 難易度テーブル: {経過秒, 敵数上限, 発射間隔ms}
  @difficulty_table [
    {90, 30, 500},
    {60, 20, 750},
    {30, 12, 1000},
    {0, 6, 2000}
  ]

  @impl Core.SceneBehaviour
  def init(_init_arg) do
    {:ok,
     %{
       player: {0.0, 0.0, 0.0},
       enemies: [],
       bullets: [],
       hp: @player_initial_hp,
       elapsed_sec: 0.0,
       move_input: {0.0, 0.0},
       invincible_ms: 0,
       next_enemy_id: 0,
       next_bullet_id: 0,
       spawn_timer_ms: 0,
       shoot_timer_ms: 1500
     }}
  end

  @impl Core.SceneBehaviour
  def render_type, do: :playing

  @impl Core.SceneBehaviour
  def update(_context, state) do
    if state.hp <= 0 do
      {:transition,
       {:replace, Content.BulletHell3D.Scenes.GameOver, %{elapsed_sec: state.elapsed_sec}}, state}
    else
      new_state = tick(state)
      {:continue, new_state}
    end
  end

  # ── メインティック ────────────────────────────────────────────────

  defp tick(state) do
    {dx, dz} = state.move_input
    elapsed_sec = state.elapsed_sec + @tick_sec
    {max_enemies, shoot_interval_ms} = difficulty(elapsed_sec)

    # プレイヤー移動
    player = move_player(state.player, dx, dz)

    # 弾移動・フィールド外削除
    bullets = move_bullets(state.bullets)

    # 敵移動
    enemies = move_enemies(state.enemies, player)

    # スポーンタイマー更新
    {enemies, next_enemy_id, spawn_timer_ms} =
      update_spawn_timer(enemies, state.spawn_timer_ms, state.next_enemy_id, max_enemies)

    # 発射タイマー更新
    {bullets, next_bullet_id, shoot_timer_ms} =
      update_shoot_timer(
        bullets,
        state.shoot_timer_ms,
        state.next_bullet_id,
        enemies,
        player,
        shoot_interval_ms
      )

    # 衝突判定（無敵時間中はスキップ）
    {hp, invincible_ms} =
      if state.invincible_ms > 0 do
        {state.hp, state.invincible_ms - trunc(@tick_ms)}
      else
        check_damage(state.hp, player, enemies, bullets)
      end

    %{
      state
      | player: player,
        enemies: enemies,
        bullets: bullets,
        hp: max(0, hp),
        elapsed_sec: elapsed_sec,
        invincible_ms: max(0, invincible_ms),
        next_enemy_id: next_enemy_id,
        next_bullet_id: next_bullet_id,
        spawn_timer_ms: spawn_timer_ms,
        shoot_timer_ms: shoot_timer_ms
    }
  end

  # ── 難易度計算 ────────────────────────────────────────────────────

  defp difficulty(elapsed_sec) do
    {_threshold, max_enemies, shoot_interval_ms} =
      Enum.find(@difficulty_table, fn {threshold, _max, _interval} ->
        elapsed_sec >= threshold
      end)

    {max_enemies, shoot_interval_ms}
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

  defp move_bullets(bullets) do
    bullets
    |> Enum.map(fn b ->
      {bx, by, bz} = b.pos
      {vx, _vy, vz} = b.vel
      %{b | pos: {bx + vx * @tick_sec, by, bz + vz * @tick_sec}}
    end)
    |> Enum.filter(fn b ->
      {bx, _by, bz} = b.pos
      abs(bx) <= @field_half + 2.0 and abs(bz) <= @field_half + 2.0
    end)
  end

  # 敵同士の分離に使う直径（半径 × 2）
  @enemy_diameter @enemy_radius * 2

  # ── 敵移動 ────────────────────────────────────────────────────────

  defp move_enemies(enemies, {px, _py, pz}) do
    speed = 2.5 * @tick_sec

    enemies
    |> Enum.map(fn e ->
      {ex, ey, ez} = e.pos
      ddx = px - ex
      ddz = pz - ez
      len = :math.sqrt(ddx * ddx + ddz * ddz)

      new_pos =
        if len > 0.001 do
          {ex + ddx / len * speed, ey, ez + ddz / len * speed}
        else
          {ex, ey, ez}
        end

      %{e | pos: new_pos}
    end)
    |> separate_enemies()
  end

  # 敵同士が重なっている場合に互いを押し出す分離パス。
  # O(N²) だが敵数は高々 30 体なので問題ない。
  # 1 パスで完全解消はしないが、毎フレーム繰り返すことで自然に分離される。
  defp separate_enemies([]), do: []
  defp separate_enemies([_] = enemies), do: enemies

  defp separate_enemies(enemies) do
    # 各敵に加算する押し出しベクトルを id → {dx, dz} のマップで蓄積する
    deltas = collect_separation_deltas(enemies, %{})

    Enum.map(enemies, fn e ->
      case Map.get(deltas, e.id) do
        nil ->
          e

        {ddx, ddz} ->
          {ex, ey, ez} = e.pos
          %{e | pos: {ex + ddx, ey, ez + ddz}}
      end
    end)
  end

  defp collect_separation_deltas([], acc), do: acc

  defp collect_separation_deltas([head | tail], acc) do
    acc = Enum.reduce(tail, acc, fn other, a -> push_apart(head, other, a) end)
    collect_separation_deltas(tail, acc)
  end

  defp push_apart(ei, ej, acc) do
    {ix, _iy, iz} = ei.pos
    {jx, _jy, jz} = ej.pos
    dx = ix - jx
    dz = iz - jz
    d2 = dx * dx + dz * dz

    if d2 < @enemy_diameter * @enemy_diameter and d2 > 0.0001 do
      d = :math.sqrt(d2)
      overlap = (@enemy_diameter - d) * 0.5
      nx = dx / d * overlap
      nz = dz / d * overlap

      acc
      |> Map.update(ei.id, {nx, nz}, fn {ax, az} -> {ax + nx, az + nz} end)
      |> Map.update(ej.id, {-nx, -nz}, fn {ax, az} -> {ax - nx, az - nz} end)
    else
      acc
    end
  end

  # ── スポーンタイマー ──────────────────────────────────────────────

  defp update_spawn_timer(enemies, timer_ms, next_id, max_enemies) do
    new_timer = timer_ms - trunc(@tick_ms)

    if new_timer <= 0 and length(enemies) < max_enemies do
      {new_enemy, new_id} = spawn_enemy(next_id)
      {enemies ++ [new_enemy], new_id, @enemy_spawn_interval_ms}
    else
      {enemies, next_id, max(0, new_timer)}
    end
  end

  defp spawn_enemy(id) do
    angle = :rand.uniform() * 2.0 * :math.pi()
    dist = @field_half + 1.5
    x = :math.cos(angle) * dist
    z = :math.sin(angle) * dist

    enemy = %{
      id: id,
      pos: {x, 0.0, z}
    }

    {enemy, id + 1}
  end

  # ── 発射タイマー ──────────────────────────────────────────────────

  defp update_shoot_timer(bullets, timer_ms, next_id, enemies, player, shoot_interval_ms) do
    new_timer = timer_ms - trunc(@tick_ms)

    if new_timer <= 0 and enemies != [] do
      {new_bullets, new_id} = fire_bullets(enemies, player, next_id)
      {bullets ++ new_bullets, new_id, shoot_interval_ms}
    else
      {bullets, next_id, max(0, new_timer)}
    end
  end

  defp fire_bullets(enemies, {px, _py, pz}, next_id) do
    Enum.reduce(enemies, {[], next_id}, fn e, {acc, id} ->
      {ex, _ey, ez} = e.pos
      ddx = px - ex
      ddz = pz - ez
      len = :math.sqrt(ddx * ddx + ddz * ddz)

      if len > 0.001 do
        vx = ddx / len * @bullet_speed
        vz = ddz / len * @bullet_speed
        bullet = %{id: id, pos: e.pos, vel: {vx, 0.0, vz}}
        {acc ++ [bullet], id + 1}
      else
        {acc, id}
      end
    end)
  end

  # ── 衝突判定 ──────────────────────────────────────────────────────

  defp check_damage(hp, {px, _py, pz}, enemies, bullets) do
    enemy_hit =
      Enum.any?(enemies, fn e ->
        {ex, _ey, ez} = e.pos

        dist2(px, pz, ex, ez) <
          (@player_radius + @enemy_radius) * (@player_radius + @enemy_radius)
      end)

    bullet_hit =
      Enum.any?(bullets, fn b ->
        {bx, _by, bz} = b.pos

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
