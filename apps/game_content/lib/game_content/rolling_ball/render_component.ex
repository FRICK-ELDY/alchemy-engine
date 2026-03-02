defmodule GameContent.RollingBall.RenderComponent do
  @moduledoc """
  毎フレーム3D DrawCommand リストを組み立てて push_render_frame NIF に送るコンポーネント。

  ## 描画内容
  - `DrawCommand::Skybox` — 昼空グラデーション背景
  - `DrawCommand::Box3D` — フロアタイル（グレー）、ボール（白・大）、障害物（赤）、ゴール（緑・高い柱）
  """
  @behaviour GameEngine.Component

  # カメラ設定（斜め上から俯瞰）
  # フロアが最大 10×2=20 ユニット幅になるため、少し引いて全体が見えるようにする
  @camera_eye {0.0, 28.0, 22.0}
  @camera_target {0.0, 0.0, 0.0}
  @camera_up {0.0, 1.0, 0.0}
  @camera_fov 45.0
  @camera_near 0.1
  @camera_far 150.0

  # 色定義
  # 夕焼け：上が深い赤紫、下が明るいオレンジ
  @color_sky_top {0.55, 0.15, 0.10, 1.0}
  @color_sky_bottom {1.0, 0.55, 0.15, 1.0}
  # フロア：明るいグレー（穴との対比を出す）
  @color_floor {0.55, 0.55, 0.60, 1.0}
  # ボール：明るい白
  @color_ball {1.0, 1.0, 1.0, 1.0}
  # ゴール：鮮やかな黄緑
  @color_goal {0.1, 0.95, 0.3, 1.0}
  # 静的障害物：赤
  @color_obstacle {0.95, 0.15, 0.15, 1.0}
  # 動く障害物：オレンジ
  @color_moving_obstacle {1.0, 0.55, 0.05, 1.0}

  # タイルの半サイズ（tile_size=2.0 に合わせる）
  # XZ は 0.98 にして隙間を作り、穴の場所が暗く見えるようにする
  @tile_half_xz 0.98
  @tile_half_y 0.08

  # ボール：大きく・フロアより上に浮かせる
  @ball_half 0.55
  # ゴール：目立つ柱状（高さ 1.0）
  @goal_half_xz 0.7
  @goal_half_y 1.0
  # 障害物：ボールより少し大きい立方体
  @obstacle_half 0.65

  @impl GameEngine.Component
  def on_nif_sync(context) do
    content = GameEngine.Config.current()

    current_scene =
      case GameEngine.SceneManager.current() do
        {:ok, %{module: mod}} -> mod
        _ -> content.playing_scene()
      end

    playing_state = GameEngine.SceneManager.get_scene_state(content.playing_scene()) || %{}

    commands = build_commands(playing_state, current_scene)
    camera = build_camera()
    hud = build_hud(playing_state, current_scene, content)

    GameEngine.NifBridge.push_render_frame(
      context.render_buf_ref,
      commands,
      camera,
      hud
    )

    :ok
  end

  # ── DrawCommand 組み立て ──────────────────────────────────────────

  defp build_commands(scene_state, current_scene) do
    {sky_top_r, sky_top_g, sky_top_b, sky_top_a} = @color_sky_top
    {sky_bot_r, sky_bot_g, sky_bot_b, sky_bot_a} = @color_sky_bottom

    skybox_cmd =
      {:skybox, {sky_top_r, sky_top_g, sky_top_b, sky_top_a},
       {sky_bot_r, sky_bot_g, sky_bot_b, sky_bot_a}}

    # Title シーンはスカイボックスのみ（Playing シーンがスタックにないため）。
    # StageClear / GameOver / Ending は Playing シーンの state を使って描画を継続する。
    title_scenes = [
      GameContent.RollingBall.Scenes.Title,
      GameContent.RollingBall.Scenes.Ending
    ]

    if current_scene in title_scenes do
      [skybox_cmd]
    else
      floor_cmds = build_floor_cmds(scene_state)
      goal_cmds = build_goal_cmds(scene_state)
      obstacle_cmds = build_obstacle_cmds(scene_state)
      moving_obstacle_cmds = build_moving_obstacle_cmds(scene_state)
      ball_cmd = build_ball_cmd(scene_state)

      # 描画順：スカイボックス → フロア → ゴール → 障害物 → ボール（手前に来るように最後）
      [skybox_cmd | floor_cmds] ++
        goal_cmds ++ obstacle_cmds ++ moving_obstacle_cmds ++ [ball_cmd]
    end
  end

  defp build_floor_cmds(scene_state) do
    floor_tiles = Map.get(scene_state, :floor_tiles, [])
    {fr, fg, fb, fa} = @color_floor

    Enum.map(floor_tiles, fn {x, z} ->
      {:box_3d, x, @tile_half_y, z, @tile_half_xz, @tile_half_y, {@tile_half_xz, fr, fg, fb, fa}}
    end)
  end

  defp build_goal_cmds(scene_state) do
    case Map.get(scene_state, :goal_pos) do
      nil ->
        []

      {gx, gz} ->
        {gr, gg, gb, ga} = @color_goal

        [
          {:box_3d, gx, @goal_half_y, gz, @goal_half_xz, @goal_half_y,
           {@goal_half_xz, gr, gg, gb, ga}}
        ]
    end
  end

  defp build_obstacle_cmds(scene_state) do
    obstacles = Map.get(scene_state, :obstacles, [])
    {r, g, b, a} = @color_obstacle

    Enum.map(obstacles, fn {x, z} ->
      {:box_3d, x, @obstacle_half, z, @obstacle_half, @obstacle_half,
       {@obstacle_half, r, g, b, a}}
    end)
  end

  defp build_moving_obstacle_cmds(scene_state) do
    moving = Map.get(scene_state, :moving_obstacles, [])
    {r, g, b, a} = @color_moving_obstacle

    Enum.map(moving, fn %{x: x, z: z} ->
      {:box_3d, x, @obstacle_half, z, @obstacle_half, @obstacle_half,
       {@obstacle_half, r, g, b, a}}
    end)
  end

  defp build_ball_cmd(scene_state) do
    # ボールの Y 座標はフロア上面（tile_half_y * 2）+ ボール半径
    default_y = @tile_half_y * 2 + @ball_half
    {bx, by, bz} = Map.get(scene_state, :ball, {0.0, default_y, 0.0})
    {r, g, b, a} = @color_ball
    {:box_3d, bx, by, bz, @ball_half, @ball_half, {@ball_half, r, g, b, a}}
  end

  # ── カメラ組み立て ─────────────────────────────────────────────────

  defp build_camera do
    {ex, ey, ez} = @camera_eye
    {tx, ty, tz} = @camera_target
    {ux, uy, uz} = @camera_up

    {:camera_3d, {ex, ey, ez}, {tx, ty, tz}, {ux, uy, uz},
     {@camera_fov, @camera_near, @camera_far}}
  end

  # ── HUD 組み立て ───────────────────────────────────────────────────

  defp build_hud(playing_state, current_scene, content) do
    stage = Map.get(playing_state, :stage, 1)
    retries_left = Map.get(playing_state, :retries_left, 3)

    phase =
      cond do
        current_scene == GameContent.RollingBall.Scenes.Title -> :title
        current_scene == GameContent.RollingBall.Scenes.StageClear -> :stage_clear
        current_scene == GameContent.RollingBall.Scenes.Ending -> :ending
        current_scene == content.game_over_scene() -> :game_over
        true -> :playing
      end

    # score フィールドにステージ番号を流用（StageClear UI の "Stage N Complete" 表示に使う）
    {
      {100.0, 100.0, stage, 0.0, retries_left, 0, 10},
      {0, 0, 0.0, false},
      {[], [], []},
      {0.0, 0, :none, phase, 0.0, [], 0}
    }
  end
end
