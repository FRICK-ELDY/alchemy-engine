defmodule GameContent.SimpleBox3D.RenderComponent do
  @moduledoc """
  毎フレーム3D DrawCommand リストを組み立てて push_render_frame NIF に送るコンポーネント。

  Phase R-6: SimpleBox3D コンテンツの描画担当。
  Elixir 側のシーン state（プレイヤー・敵の3D座標）から DrawCommand を組み立て、
  Camera3D と共に RenderFrameBuffer に書き込む。

  ## 描画内容
  - `DrawCommand::Skybox` — 空色グラデーション背景
  - `DrawCommand::GridPlane` — XZ 平面グリッド地面
  - `DrawCommand::Box3D` — プレイヤー（青）と敵（赤）
  """
  @behaviour GameEngine.Component

  # ボックスの半サイズ
  @half_size 0.5

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
  @color_grid {0.3, 0.3, 0.3, 1.0}
  @color_sky_top {0.4, 0.6, 0.9, 1.0}
  @color_sky_bottom {0.7, 0.85, 1.0, 1.0}

  # グリッドパラメータ
  @grid_size 20.0
  @grid_divisions 20

  @impl GameEngine.Component
  def on_nif_sync(context) do
    # Config.current() は Application.get_env（ETS ルックアップ）なので毎フレーム呼んでも軽量。
    # ただし同一フレーム内で複数回参照しないよう、ここで一度だけ取得する。
    content = GameEngine.Config.current()

    # Playing → GameOver に replace 遷移した後、playing_scene() の state は %{} になるため
    # SceneManager.current() で現在シーンを判定して phase を正しく設定する。
    current_scene =
      case GameEngine.SceneManager.current() do
        {:ok, %{module: mod}} -> mod
        _ -> content.playing_scene()
      end

    playing_state = GameEngine.SceneManager.get_scene_state(content.playing_scene()) || %{}

    commands = build_commands(playing_state)
    camera = build_camera()
    hud = build_hud(current_scene, content)

    GameEngine.NifBridge.push_render_frame(
      context.render_buf_ref,
      commands,
      camera,
      hud
    )

    :ok
  end

  # ── DrawCommand 組み立て ──────────────────────────────────────────

  defp build_commands(scene_state) do
    player = Map.get(scene_state, :player, {0.0, 0.0, 0.0})
    enemies = Map.get(scene_state, :enemies, [])

    {sky_top_r, sky_top_g, sky_top_b, sky_top_a} = @color_sky_top
    {sky_bot_r, sky_bot_g, sky_bot_b, sky_bot_a} = @color_sky_bottom
    {grid_r, grid_g, grid_b, grid_a} = @color_grid
    {pr, pg, pb, pa} = @color_player
    {er, eg, eb, ea} = @color_enemy

    skybox_cmd =
      {:skybox, {sky_top_r, sky_top_g, sky_top_b, sky_top_a},
       {sky_bot_r, sky_bot_g, sky_bot_b, sky_bot_a}}

    grid_cmd = {:grid_plane, @grid_size, @grid_divisions, {grid_r, grid_g, grid_b, grid_a}}

    {px, py, pz} = player

    # NIF 側は Rustler の最大 7 要素制約のため、末尾 5 要素 {half_d, r, g, b, a} を
    # 内部タプルにまとめている。half_d は色ではなく奥行き方向の半サイズ。
    player_cmd =
      {:box_3d, px, py + @half_size, pz, @half_size, @half_size, {@half_size, pr, pg, pb, pa}}

    enemy_cmds =
      Enum.map(enemies, fn {ex, ey, ez} ->
        {:box_3d, ex, ey + @half_size, ez, @half_size, @half_size, {@half_size, er, eg, eb, ea}}
      end)

    [skybox_cmd, grid_cmd, player_cmd | enemy_cmds]
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
  #
  # SimpleBox3D は HUD 表示を最小限にする。
  # push_render_frame の hud 引数は NifBridge のコメントに記載された固定フォーマット:
  #   { {hp, max_hp, score, elapsed_sec, level, exp, exp_to_next},
  #     {enemy_count, bullet_count, fps, level_up_pending},
  #     {weapon_choices, weapon_upgrade_descs, weapon_levels},
  #     {magnet_timer, item_count, boss_info, phase, flash_alpha, score_popups, kill_count} }
  # SimpleBox3D で使わないフィールドはゼロ・空リスト・:none で埋める。

  @hud_dummy_hp 100.0
  @hud_dummy_max_hp 100.0
  @hud_dummy_score 0
  @hud_dummy_elapsed 0.0
  @hud_dummy_level 1
  @hud_dummy_exp 0
  @hud_dummy_exp_to_next 10

  defp build_hud(current_scene, content) do
    phase = if current_scene == content.game_over_scene(), do: :game_over, else: :playing

    {
      {@hud_dummy_hp, @hud_dummy_max_hp, @hud_dummy_score, @hud_dummy_elapsed, @hud_dummy_level,
       @hud_dummy_exp, @hud_dummy_exp_to_next},
      {0, 0, 0.0, false},
      {[], [], []},
      {0.0, 0, :none, phase, 0.0, [], 0}
    }
  end
end
