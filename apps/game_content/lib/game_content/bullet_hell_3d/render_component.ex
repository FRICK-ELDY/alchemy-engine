defmodule GameContent.BulletHell3D.RenderComponent do
  @moduledoc """
  毎フレーム3D DrawCommand リストを組み立てて push_render_frame NIF に送るコンポーネント。

  BulletHell3D コンテンツの描画担当。
  Elixir 側のシーン state（プレイヤー・敵・弾の3D座標）から DrawCommand を組み立て、
  Camera3D と共に RenderFrameBuffer に書き込む。

  ## 描画内容
  - `DrawCommand::Skybox`    — 空色グラデーション背景
  - `DrawCommand::GridPlane` — XZ 平面グリッド地面
  - `DrawCommand::Box3D`     — プレイヤー（青）・敵（赤）・弾（黄）
  - HUD                      — 残り HP・生存時間（egui）
  """
  @behaviour GameEngine.Component

  # カメラ設定（斜め上から俯瞰）
  @camera_eye {0.0, 18.0, 14.0}
  @camera_target {0.0, 0.0, 0.0}
  @camera_up {0.0, 1.0, 0.0}
  @camera_fov 45.0
  @camera_near 0.1
  @camera_far 100.0

  # 色定義
  @color_player {0.2, 0.4, 0.9, 1.0}
  @color_enemy {0.9, 0.2, 0.2, 1.0}
  @color_bullet {0.95, 0.85, 0.1, 1.0}
  @color_grid {0.3, 0.3, 0.3, 1.0}
  @color_sky_top {0.4, 0.6, 0.9, 1.0}
  @color_sky_bottom {0.7, 0.85, 1.0, 1.0}

  # ボックスサイズ
  @player_half 0.5
  @enemy_half 0.5
  @bullet_half 0.15

  # グリッドパラメータ
  @grid_size 20.0
  @grid_divisions 20

  # HP 表示用の最大 HP
  @max_hp 3

  @impl GameEngine.Component
  def on_nif_sync(context) do
    content = GameEngine.Config.current()

    current_scene =
      case GameEngine.SceneManager.current() do
        {:ok, %{module: mod}} -> mod
        _ -> content.playing_scene()
      end

    playing_state = GameEngine.SceneManager.get_scene_state(content.playing_scene()) || %{}
    game_over_state = GameEngine.SceneManager.get_scene_state(content.game_over_scene()) || %{}

    commands = build_commands(playing_state)
    camera = build_camera()
    ui = build_ui(current_scene, content, playing_state, game_over_state)

    GameEngine.NifBridge.push_render_frame(
      context.render_buf_ref,
      commands,
      camera,
      ui,
      :no_change
    )

    :ok
  end

  # ── DrawCommand 組み立て ──────────────────────────────────────────

  defp build_commands(scene_state) do
    player = Map.get(scene_state, :player, {0.0, 0.0, 0.0})
    enemies = Map.get(scene_state, :enemies, [])
    bullets = Map.get(scene_state, :bullets, [])
    invincible_ms = Map.get(scene_state, :invincible_ms, 0)

    {sky_top_r, sky_top_g, sky_top_b, sky_top_a} = @color_sky_top
    {sky_bot_r, sky_bot_g, sky_bot_b, sky_bot_a} = @color_sky_bottom
    {grid_r, grid_g, grid_b, grid_a} = @color_grid
    {er, eg, eb, ea} = @color_enemy
    {br, bg, bb, ba} = @color_bullet

    skybox_cmd =
      {:skybox, {sky_top_r, sky_top_g, sky_top_b, sky_top_a},
       {sky_bot_r, sky_bot_g, sky_bot_b, sky_bot_a}}

    grid_cmd = {:grid_plane, @grid_size, @grid_divisions, {grid_r, grid_g, grid_b, grid_a}}

    player_cmd = build_player_cmd(player, invincible_ms)

    enemy_cmds =
      Enum.map(enemies, fn e ->
        {ex, ey, ez} = e.pos

        {:box_3d, ex, ey + @enemy_half, ez, @enemy_half, @enemy_half,
         {@enemy_half, er, eg, eb, ea}}
      end)

    bullet_cmds =
      Enum.map(bullets, fn b ->
        {bx, by, bz} = b.pos

        {:box_3d, bx, by + @bullet_half, bz, @bullet_half, @bullet_half,
         {@bullet_half, br, bg, bb, ba}}
      end)

    [skybox_cmd, grid_cmd, player_cmd] ++ enemy_cmds ++ bullet_cmds
  end

  defp build_player_cmd({px, py, pz}, invincible_ms) do
    {pr, pg, pb, _pa} = @color_player

    alpha =
      if invincible_ms > 0 do
        frame = div(invincible_ms, 100)
        if rem(frame, 2) == 0, do: 0.3, else: 1.0
      else
        1.0
      end

    {:box_3d, px, py + @player_half, pz, @player_half, @player_half,
     {@player_half, pr, pg, pb, alpha}}
  end

  # ── カメラ組み立て ─────────────────────────────────────────────────

  defp build_camera do
    {ex, ey, ez} = @camera_eye
    {tx, ty, tz} = @camera_target
    {ux, uy, uz} = @camera_up

    {:camera_3d, {ex, ey, ez}, {tx, ty, tz}, {ux, uy, uz},
     {@camera_fov, @camera_near, @camera_far}}
  end

  # ── UiCanvas 組み立て ─────────────────────────────────────────────

  defp build_ui(current_scene, content, playing_state, game_over_state) do
    is_game_over = current_scene == content.game_over_scene()

    hp = Map.get(playing_state, :hp, @max_hp)
    elapsed_sec = Map.get(playing_state, :elapsed_sec, 0.0)
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
end
