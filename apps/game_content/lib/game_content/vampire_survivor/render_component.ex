defmodule GameContent.VampireSurvivor.RenderComponent do
  @moduledoc """
  毎フレーム DrawCommand リストを組み立てて push_render_frame NIF に送るコンポーネント。

  Phase R-2: render_snapshot.rs の責務を Elixir 側（game_content）に移した。
  GameWorldInner への直接依存を排除し、get_render_entities NIF 経由で
  描画用データを取得する。

  ## on_nif_sync
  1. `get_render_entities/1` で物理ワールドのスナップショットを取得する
  2. Playing シーン state から UiCanvas ツリーを組み立てる
  3. `push_render_frame/4` で RenderFrameBuffer に書き込む
  """
  @behaviour Core.Component

  # Rust 側の constants.rs と同値
  @screen_width 1280.0
  @screen_height 720.0
  @player_size 64.0

  # 武器レジストリ（atom → kind_id）をコンパイル時定数として保持する。
  @weapon_registry GameContent.VampireSurvivor.SpawnComponent.entity_registry().weapons

  @weapon_display_names %{
    "magic_wand" => "Magic Wand",
    "axe" => "Axe",
    "cross" => "Cross",
    "whip" => "Whip",
    "fireball" => "Fireball",
    "lightning" => "Lightning"
  }

  @impl Core.Component
  def on_nif_sync(context) do
    content = Core.Config.current()
    playing_state = Core.SceneManager.get_scene_state(content.playing_scene()) || %{}

    current_scene =
      case Core.SceneManager.current() do
        {:ok, %{module: mod}} -> mod
        _ -> content.playing_scene()
      end

    {{player_x, player_y, frame_id, enemy_count, bullet_count}, {magnet_timer, invincible_timer},
     {enemies, bullets, particles}, {items, obstacles, boss, score_popups}} =
      Core.NifBridge.get_render_entities(context.world_ref)

    anim_frame = rem(div(frame_id, 4), 4)

    entities = {enemies, bullets, particles, items, obstacles, boss}
    commands = build_commands(player_x, player_y, anim_frame, entities)

    camera = build_camera(player_x, player_y)

    ui =
      build_ui(
        context,
        playing_state,
        current_scene,
        content,
        enemy_count,
        bullet_count,
        boss,
        score_popups,
        magnet_timer,
        invincible_timer
      )

    Core.NifBridge.push_render_frame(
      context.render_buf_ref,
      commands,
      camera,
      ui,
      :no_change
    )

    :ok
  end

  # ── DrawCommand 組み立て ──────────────────────────────────────────

  defp build_commands(player_x, player_y, anim_frame, entities) do
    {enemies, bullets, particles, items, obstacles, boss} = entities

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

  # ── UiCanvas 組み立て ─────────────────────────────────────────────

  defp build_ui(
         context,
         playing_state,
         current_scene,
         content,
         enemy_count,
         bullet_count,
         boss,
         score_popups,
         magnet_timer,
         invincible_timer
       ) do
    nodes =
      cond do
        current_scene == content.game_over_scene() ->
          [build_game_over_panel(playing_state)]

        true ->
          build_playing_nodes(
            context,
            playing_state,
            enemy_count,
            bullet_count,
            boss,
            score_popups,
            magnet_timer,
            invincible_timer
          )
      end

    {:canvas, nodes}
  end

  # ── GameOver パネル ───────────────────────────────────────────────

  defp build_game_over_panel(playing_state) do
    elapsed_s = trunc(Map.get(playing_state, :elapsed_ms, 0) / 1000)
    m = div(elapsed_s, 60)
    s = rem(elapsed_s, 60)
    score = Map.get(playing_state, :score, 0)
    kill_count = Map.get(playing_state, :kill_count, 0)
    level = Map.get(playing_state, :level, 1)

    info_nodes = [
      text_node(
        "Survived:  #{String.pad_leading(to_string(m), 2, "0")}:#{String.pad_leading(to_string(s), 2, "0")}",
        {0.86, 0.86, 1.0, 1.0},
        18.0
      ),
      text_node("Score:     #{score}", {1.0, 0.86, 0.31, 1.0}, 18.0),
      text_node("Kills:     #{kill_count}", {0.78, 0.90, 0.78, 1.0}, 18.0),
      text_node("Level:     #{level}", {0.71, 0.78, 1.0, 1.0}, 18.0)
    ]

    retry_btn = button_node("  RETRY  ", "__retry__", {0.63, 0.16, 0.16, 1.0}, 160.0, 44.0)

    inner_children =
      [
        text_node("GAME OVER", {1.0, 0.31, 0.31, 1.0}, 40.0, bold: true),
        spacing_node(16.0)
      ] ++
        info_nodes ++
        [
          spacing_node(20.0),
          retry_btn
        ]

    vertical_panel(
      inner_children,
      bg: {0.08, 0.02, 0.02, 0.92},
      border: {{0.78, 0.24, 0.24, 1.0}, 2.0},
      padding: {50, 35, 50, 35},
      anchor: :center
    )
  end

  # ── Playing 中ノード群 ────────────────────────────────────────────

  defp build_playing_nodes(
         context,
         playing_state,
         enemy_count,
         bullet_count,
         boss,
         score_popups,
         magnet_timer,
         invincible_timer
       ) do
    nodes = []

    # 画面フラッシュ（無敵時間中）
    nodes =
      if invincible_timer > 0.0 do
        alpha = min(invincible_timer, 1.0) * 0.35
        [screen_flash_node({0.78, 0.12, 0.12, alpha}) | nodes]
      else
        nodes
      end

    # スコアポップアップ（ワールド座標テキスト）
    nodes =
      Enum.reduce(score_popups, nodes, fn {wx, wy, value, lifetime}, acc ->
        [world_text_node(wx, wy, "+#{value}", {1.0, 0.90, 0.20, 1.0}, lifetime, 0.8) | acc]
      end)

    # 上部 HUD バー
    nodes = [build_top_hud_bar(context, playing_state, magnet_timer) | nodes]

    # デバッグ情報（右上）
    nodes = [build_debug_panel(enemy_count, bullet_count, playing_state, magnet_timer) | nodes]

    # ボス HP バー
    nodes =
      case build_boss_hp_bar(boss, playing_state) do
        nil -> nodes
        bar_node -> [bar_node | nodes]
      end

    # レベルアップ選択モーダル
    nodes =
      if Map.get(playing_state, :level_up_pending, false) do
        [build_level_up_modal(context, playing_state) | nodes]
      else
        nodes
      end

    Enum.reverse(nodes)
  end

  # ── 上部 HUD バー ─────────────────────────────────────────────────

  defp build_top_hud_bar(context, playing_state, magnet_timer) do
    hp = Map.get(playing_state, :player_hp, 100.0)
    max_hp = Map.get(playing_state, :player_max_hp, 100.0)
    score = Map.get(playing_state, :score, 0)
    elapsed_ms = Map.get(playing_state, :elapsed_ms) || context.elapsed
    elapsed_s = trunc(elapsed_ms / 1000)
    m = div(elapsed_s, 60)
    s = rem(elapsed_s, 60)
    level = Map.get(playing_state, :level, 1)
    exp = Map.get(playing_state, :exp, 0)
    exp_to_next = Map.get(playing_state, :exp_to_next, 10)
    weapon_levels = Map.get(playing_state, :weapon_levels, %{})

    hp_children = [
      text_node("HP", {1.0, 0.39, 0.39, 1.0}, 14.0, bold: true),
      progress_bar_node(hp, max_hp, 160.0, 18.0,
        fg_high: {0.31, 0.86, 0.31, 1.0},
        fg_mid: {0.86, 0.71, 0.0, 1.0},
        fg_low: {0.86, 0.24, 0.24, 1.0},
        bg: {0.24, 0.08, 0.08, 1.0}
      ),
      text_node("#{trunc(hp)}/#{trunc(max_hp)}", {1.0, 1.0, 1.0, 1.0}, 13.0)
    ]

    exp_total = exp + exp_to_next

    exp_children = [
      text_node("Lv.#{level}", {1.0, 0.86, 0.20, 1.0}, 14.0, bold: true),
      progress_bar_node(exp, exp_total, 100.0, 18.0,
        fg_high: {0.31, 0.47, 1.0, 1.0},
        fg_mid: {0.31, 0.47, 1.0, 1.0},
        fg_low: {0.31, 0.47, 1.0, 1.0},
        bg: {0.08, 0.08, 0.24, 1.0}
      ),
      text_node("EXP #{exp}", {0.71, 0.78, 1.0, 1.0}, 13.0)
    ]

    score_children = [
      text_node("Score: #{score}", {1.0, 0.86, 0.39, 1.0}, 14.0, bold: true),
      text_node(
        "#{String.pad_leading(to_string(m), 2, "0")}:#{String.pad_leading(to_string(s), 2, "0")}",
        {1.0, 1.0, 1.0, 1.0},
        14.0
      )
    ]

    weapon_children =
      Enum.map(weapon_levels, fn {weapon_name, lv} ->
        display = Map.get(@weapon_display_names, to_string(weapon_name), to_string(weapon_name))
        text_node("[#{display}] Lv.#{lv}", {0.71, 0.90, 1.0, 1.0}, 13.0, bold: true)
      end)

    save_load_children = [
      button_node("Save", "__save__", {0.39, 0.86, 0.39, 1.0}, 50.0, 22.0),
      button_node("Load", "__load__", {0.39, 0.71, 1.0, 1.0}, 50.0, 22.0)
    ]

    magnet_children =
      if magnet_timer > 0.0 do
        [
          separator_node(),
          text_node(
            "MAGNET #{:erlang.float_to_binary(magnet_timer, decimals: 1)}s",
            {1.0, 0.90, 0.20, 1.0},
            13.0,
            bold: true
          )
        ]
      else
        []
      end

    all_children =
      hp_children ++
        [separator_node()] ++
        exp_children ++
        [separator_node()] ++
        score_children ++
        if(weapon_children != [], do: [separator_node()] ++ weapon_children, else: []) ++
        [separator_node()] ++
        save_load_children ++
        magnet_children

    {:node, {:top_left, {8.0, 8.0}, :wrap}, {:rect, {0.0, 0.0, 0.0, 0.71}, 6.0, :none},
     [
       {:node, {:top_left, {0.0, 0.0}, :wrap}, {:horizontal_layout, 6.0, {12.0, 8.0, 12.0, 8.0}},
        all_children}
     ]}
  end

  # ── デバッグパネル（右上）────────────────────────────────────────

  defp build_debug_panel(enemy_count, bullet_count, playing_state, _magnet_timer) do
    item_count = Map.get(playing_state, :item_count, 0)

    children = [
      text_node("Enemies: #{enemy_count}", {1.0, 0.59, 0.39, 1.0}, 13.0),
      text_node("Bullets: #{bullet_count}", {0.78, 0.78, 1.0, 1.0}, 13.0),
      text_node("Items: #{item_count}", {0.59, 0.90, 0.59, 1.0}, 13.0)
    ]

    {:node, {:top_right, {-8.0, 8.0}, :wrap}, {:rect, {0.0, 0.0, 0.0, 0.55}, 6.0, :none},
     [
       {:node, {:top_left, {0.0, 0.0}, :wrap}, {:vertical_layout, 2.0, {8.0, 6.0, 8.0, 6.0}},
        children}
     ]}
  end

  # ── ボス HP バー ──────────────────────────────────────────────────

  defp build_boss_hp_bar({:alive, _, _, _, _}, playing_state) do
    boss_hp = Map.get(playing_state, :boss_hp)
    boss_max_hp = Map.get(playing_state, :boss_max_hp)

    if boss_hp == nil or boss_max_hp == nil do
      nil
    else
      children = [
        text_node("👹 Boss", {1.0, 0.31, 0.31, 1.0}, 18.0, bold: true),
        spacing_node(4.0),
        progress_bar_node(boss_hp, boss_max_hp, 360.0, 22.0,
          fg_high: {0.71, 0.0, 0.86, 1.0},
          fg_mid: {0.86, 0.24, 0.24, 1.0},
          fg_low: {1.0, 0.12, 0.12, 1.0},
          bg: {0.16, 0.04, 0.04, 1.0},
          corner_radius: 6.0
        ),
        text_node("#{trunc(boss_hp)} / #{trunc(boss_max_hp)}", {1.0, 0.78, 1.0, 1.0}, 12.0)
      ]

      {:node, {:top_center, {0.0, 8.0}, :wrap},
       {:rect, {0.08, 0.0, 0.12, 0.86}, 8.0, {{0.78, 0.0, 1.0, 1.0}, 2.0}},
       [
         {:node, {:top_left, {0.0, 0.0}, :wrap},
          {:vertical_layout, 4.0, {16.0, 10.0, 16.0, 10.0}}, children}
       ]}
    end
  end

  defp build_boss_hp_bar({:none, _, _, _, _}, _), do: nil

  # ── レベルアップモーダル ──────────────────────────────────────────

  defp build_level_up_modal(context, playing_state) do
    level = Map.get(playing_state, :level, 1)
    weapon_choices = Map.get(playing_state, :weapon_choices, []) |> Enum.map(&to_string/1)
    weapon_levels = Map.get(playing_state, :weapon_levels, %{})

    weapon_upgrade_descs =
      if weapon_choices != [] do
        slots = weapon_slots_for_nif(playing_state)

        Core.NifBridge.get_weapon_upgrade_descs(
          context.world_ref,
          weapon_choices,
          slots
        )
      else
        []
      end

    title_node =
      text_node("*** LEVEL UP!  Lv.#{level} ***", {1.0, 0.86, 0.20, 1.0}, 28.0, bold: true)

    body_nodes =
      if weapon_choices == [] do
        [
          text_node("All weapons are at MAX level!", {1.0, 0.71, 0.20, 1.0}, 16.0, bold: true),
          spacing_node(16.0),
          button_node("Continue  [Esc]", "__skip__", {0.31, 0.31, 0.31, 1.0}, 160.0, 36.0)
        ]
      else
        cards =
          weapon_choices
          |> Enum.with_index()
          |> Enum.map(fn {choice, idx} ->
            current_lv = Map.get(weapon_levels, String.to_existing_atom(choice), 0)
            display = Map.get(@weapon_display_names, choice, choice)
            descs = Enum.at(weapon_upgrade_descs, idx, [])
            build_weapon_card(choice, display, current_lv, descs)
          end)

        skip_btn = button_node("Skip  [Esc]", "__skip__", {0.24, 0.24, 0.24, 0.78}, 90.0, 24.0)

        [
          text_node("Choose a weapon", {1.0, 1.0, 1.0, 1.0}, 16.0),
          spacing_node(16.0),
          {:node, {:top_left, {0.0, 0.0}, :wrap},
           {:horizontal_layout, 12.0, {0.0, 0.0, 0.0, 0.0}}, cards},
          spacing_node(12.0),
          skip_btn
        ]
      end

    inner_children = [title_node, spacing_node(8.0)] ++ body_nodes

    vertical_panel(
      inner_children,
      bg: {0.04, 0.04, 0.16, 0.94},
      border: {{1.0, 0.86, 0.20, 1.0}, 2.0},
      padding: {40, 30, 40, 30},
      anchor: :center
    )
  end

  defp build_weapon_card(action, display_name, current_lv, upgrade_descs) do
    is_upgrade = current_lv > 0
    next_lv = current_lv + 1

    {border_color, bg_color} =
      if is_upgrade do
        {{1.0, 0.71, 0.20, 1.0}, {0.20, 0.14, 0.04, 1.0}}
      else
        {{0.39, 0.71, 1.0, 1.0}, {0.06, 0.12, 0.24, 1.0}}
      end

    lv_text = if is_upgrade, do: "Lv.#{current_lv} -> Lv.#{next_lv}", else: "NEW!"

    lv_color =
      if is_upgrade, do: {1.0, 0.78, 0.31, 1.0}, else: {0.39, 1.0, 0.59, 1.0}

    desc_nodes = Enum.map(upgrade_descs, &text_node(&1, {0.71, 0.78, 0.71, 1.0}, 11.0))

    card_children =
      [
        text_node(display_name, {0.86, 0.90, 1.0, 1.0}, 16.0, bold: true),
        spacing_node(4.0),
        text_node(lv_text, lv_color, 13.0, bold: true),
        spacing_node(6.0)
      ] ++
        desc_nodes ++
        [
          spacing_node(8.0),
          button_node("Select  [1/2/3]", action, border_color, 110.0, 28.0)
        ]

    {:node, {:top_left, {0.0, 0.0}, :wrap}, {:rect, bg_color, 10.0, {border_color, 2.0}},
     [
       {:node, {:top_left, {0.0, 0.0}, :wrap}, {:vertical_layout, 2.0, {16.0, 14.0, 16.0, 14.0}},
        card_children}
     ]}
  end

  # ── 武器スロット変換 ──────────────────────────────────────────────

  defp weapon_slots_for_nif(playing_state) do
    weapon_levels = Map.get(playing_state, :weapon_levels, %{})

    Enum.flat_map(weapon_levels, fn {weapon_name, level} ->
      case Map.get(@weapon_registry, weapon_name) do
        nil -> []
        kind_id -> [{kind_id, level}]
      end
    end)
  end

  # ── UiNode ヘルパー ───────────────────────────────────────────────

  defp text_node(text, {r, g, b, a}, size, opts \\ []) do
    bold = Keyword.get(opts, :bold, false)
    {:node, {:top_left, {0.0, 0.0}, :wrap}, {:text, text, {r, g, b, a}, size, bold}, []}
  end

  defp button_node(label, action, {r, g, b, a}, min_w, min_h) do
    {:node, {:top_left, {0.0, 0.0}, :wrap}, {:button, label, action, {r, g, b, a}, min_w, min_h},
     []}
  end

  defp progress_bar_node(value, max, width, height, opts) do
    fg_high = Keyword.get(opts, :fg_high, {0.31, 0.86, 0.31, 1.0})
    fg_mid = Keyword.get(opts, :fg_mid, {0.86, 0.71, 0.0, 1.0})
    fg_low = Keyword.get(opts, :fg_low, {0.86, 0.24, 0.24, 1.0})
    bg = Keyword.get(opts, :bg, {0.16, 0.16, 0.16, 1.0})
    corner_radius = Keyword.get(opts, :corner_radius, 4.0)

    {fhr, fhg, fhb, fha} = fg_high
    {fmr, fmg, fmb, fma} = fg_mid
    {flr, flg, flb, fla} = fg_low
    {bgr, bgg, bgb, bga} = bg

    {:node, {:top_left, {0.0, 0.0}, :wrap},
     {:progress_bar, value * 1.0, max * 1.0, width, height,
      {{fhr, fhg, fhb, fha}, {fmr, fmg, fmb, fma}, {flr, flg, flb, fla}, {bgr, bgg, bgb, bga},
       corner_radius}}, []}
  end

  defp separator_node do
    {:node, {:top_left, {0.0, 0.0}, :wrap}, :separator, []}
  end

  defp spacing_node(amount) do
    # amount * 1.0 は整数リテラルを float に強制変換するため（NIF は f32 を期待する）
    {:node, {:top_left, {0.0, 0.0}, :wrap}, {:spacing, amount * 1.0}, []}
  end

  defp screen_flash_node({r, g, b, a}) do
    {:node, {:top_left, {0.0, 0.0}, :wrap}, {:screen_flash, {r, g, b, a}}, []}
  end

  defp world_text_node(wx, wy, text, {r, g, b, a}, lifetime, max_lifetime) do
    {:node, {:top_left, {0.0, 0.0}, :wrap},
     {:world_text, wx, wy, 0.0, text, {r, g, b, a}, {lifetime, max_lifetime}}, []}
  end

  defp vertical_panel(children, opts) do
    {bgr, bgg, bgb, bga} = Keyword.get(opts, :bg, {0.0, 0.0, 0.0, 0.8})
    border = Keyword.get(opts, :border, :none)
    {pl, pt, pr, pb} = Keyword.get(opts, :padding, {40, 30, 40, 30})
    anchor = Keyword.get(opts, :anchor, :center)

    border_term =
      case border do
        :none -> :none
        {{r, g, b, a}, w} -> {{r, g, b, a}, w}
      end

    {:node, {anchor, {0.0, 0.0}, :wrap}, {:rect, {bgr, bgg, bgb, bga}, 16.0, border_term},
     [
       {:node, {:top_left, {0.0, 0.0}, :wrap},
        {:vertical_layout, 0.0, {pl * 1.0, pt * 1.0, pr * 1.0, pb * 1.0}}, children}
     ]}
  end
end
