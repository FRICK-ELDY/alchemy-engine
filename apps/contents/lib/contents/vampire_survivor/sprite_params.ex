defmodule Content.VampireSurvivor.SpriteParams do
  @moduledoc """
  R-R1 案 B: スプライトの UV・サイズの SSoT。
  DrawCommand SpriteRaw 用に (pos_x, pos_y, width, height, uv_offset, uv_size, color_tint) を返す。
  Rust renderer の enemy_anim_uv, enemy_sprite_size 等と同値。
  """
  @atlas_w 1664.0
  @frame_w 64.0
  @elite_offset 20
  @elite_size_mult 1.2

  # アトラス X オフセット（px）
  @offsets %{
    slime: 256,
    bat: 512,
    golem: 640,
    bullet: 768,
    fireball: 1088,
    lightning: 1152,
    whip: 1216,
    slime_king: 1280,
    bat_lord: 1344,
    stone_golem: 1408,
    rock_bullet: 1472,
    skeleton: 1536,
    ghost: 1600
  }

  @doc """
  render_kind と frame から sprite_raw 用パラメータを返す。
  戻り値: {:ok, {pos_x, pos_y, width, height, {uv_ox, uv_oy}, {uv_sx, uv_sy}, {r, g, b, a}}}
  または :error

  entity_x, entity_y は NIF から取得した座標（敵は top-left、弾は center、ボスは push 側で center→top-left 変換済み）
  """
  def sprite_raw_params(entity_x, entity_y, render_kind, frame) do
    case params_for_kind(render_kind, frame) do
      {:ok, {offset_x, offset_y, w, h, uv_off, uv_sz, color}} ->
        pos_x = entity_x + offset_x
        pos_y = entity_y + offset_y
        # NIF は f64 を期待するため、明示的に float で渡す
        {:ok, {pos_x * 1.0, pos_y * 1.0, w * 1.0, h * 1.0, uv_off, uv_sz, color}}

      :error ->
        :error
    end
  end

  defp params_for_kind(kind, frame) when kind in 1..3 do
    {w, h} = enemy_size(kind)
    {uv_off, uv_sz} = enemy_uv(kind, frame)
    {:ok, {0, 0, w, h, uv_off, uv_sz, {1.0, 1.0, 1.0, 1.0}}}
  end

  defp params_for_kind(kind, frame) when kind in 21..23 do
    base = kind - @elite_offset
    {bw, _} = enemy_size(base)
    sz = bw * @elite_size_mult
    {uv_off, uv_sz} = enemy_uv(base, frame)
    offset = -sz * 0.1
    {:ok, {offset, offset, sz, sz, uv_off, uv_sz, {1.0, 0.4, 0.4, 1.0}}}
  end

  # Ghost (enemy render_kind 4) - Rust では BULLET_KIND_NORMAL(4) が先にマッチするため bullet 扱い。
  # 呼び出し側で :enemy を指定した場合は ghost_uv を使用可能にする拡張余地あり。
  defp params_for_kind(4, _frame) do
    {uv_off, uv_sz} = uv_from_offset(@offsets.bullet)
    {:ok, {-8, -8, 16, 16, uv_off, uv_sz, {1.0, 1.0, 1.0, 1.0}}}
  end

  defp params_for_kind(5, frame) do
    {w, h} = enemy_size(5)
    {uv_off, uv_sz} = skeleton_uv(frame)
    {:ok, {0, 0, w, h, uv_off, uv_sz, {1.0, 1.0, 1.0, 1.0}}}
  end

  # BULLET_KIND_NORMAL = 4
  # BULLET_KIND_FIREBALL = 8
  defp params_for_kind(8, _frame) do
    {uv_off, uv_sz} = uv_from_offset(@offsets.fireball)
    {:ok, {-11, -11, 22, 22, uv_off, uv_sz, {1.0, 1.0, 1.0, 1.0}}}
  end

  # BULLET_KIND_LIGHTNING = 9
  defp params_for_kind(9, _frame) do
    {uv_off, uv_sz} = uv_from_offset(@offsets.lightning)
    {:ok, {-9, -9, 18, 18, uv_off, uv_sz, {1.0, 1.0, 1.0, 1.0}}}
  end

  # BULLET_KIND_WHIP = 10
  defp params_for_kind(10, _frame) do
    {uv_off, uv_sz} = uv_from_offset(@offsets.whip)
    {:ok, {-20, -10, 40, 20, uv_off, uv_sz, {1.0, 1.0, 1.0, 1.0}}}
  end

  # BULLET_KIND_ROCK = 14
  defp params_for_kind(14, _frame) do
    {uv_off, uv_sz} = uv_from_offset(@offsets.rock_bullet)
    {:ok, {-14, -14, 28, 28, uv_off, uv_sz, {1.0, 1.0, 1.0, 1.0}}}
  end

  # Boss 11-13
  defp params_for_kind(kind, _frame) when kind in 11..13 do
    {w, h} = enemy_size(kind)
    {uv_off, uv_sz} = boss_uv(kind)
    {:ok, {0, 0, w, h, uv_off, uv_sz, {1.0, 1.0, 1.0, 1.0}}}
  end

  defp params_for_kind(_, _), do: :error

  defp enemy_size(1), do: {40, 40}
  defp enemy_size(2), do: {24, 24}
  defp enemy_size(3), do: {64, 64}
  defp enemy_size(4), do: {32, 32}
  defp enemy_size(5), do: {40, 40}
  defp enemy_size(11), do: {96, 96}
  defp enemy_size(12), do: {96, 96}
  defp enemy_size(13), do: {128, 128}

  defp enemy_uv(1, frame), do: slime_uv(frame)
  defp enemy_uv(2, frame), do: bat_uv(frame)
  defp enemy_uv(3, frame), do: golem_uv(frame)
  defp enemy_uv(5, frame), do: skeleton_uv(frame)
  defp enemy_uv(11, _), do: uv_from_offset(@offsets.slime_king)
  defp enemy_uv(12, _), do: uv_from_offset(@offsets.bat_lord)
  defp enemy_uv(13, _), do: uv_from_offset(@offsets.stone_golem)
  defp enemy_uv(_, frame), do: slime_uv(frame)

  defp boss_uv(11), do: uv_from_offset(@offsets.slime_king)
  defp boss_uv(12), do: uv_from_offset(@offsets.bat_lord)
  defp boss_uv(13), do: uv_from_offset(@offsets.stone_golem)
  defp boss_uv(_), do: uv_from_offset(@offsets.slime)

  defp slime_uv(frame) do
    x = @offsets.slime + rem(frame, 4) * @frame_w
    uv_from_px(x)
  end

  defp bat_uv(frame) do
    x = @offsets.bat + rem(frame, 2) * @frame_w
    uv_from_px(x)
  end

  defp golem_uv(frame) do
    x = @offsets.golem + rem(frame, 2) * @frame_w
    uv_from_px(x)
  end

  defp skeleton_uv(frame) do
    x = @offsets.skeleton + rem(frame, 2) * @frame_w
    uv_from_px(x)
  end

  defp uv_from_offset(px) do
    {{px / @atlas_w, 0.0}, {@frame_w / @atlas_w, 1.0}}
  end

  defp uv_from_px(px) do
    {{px / @atlas_w, 0.0}, {@frame_w / @atlas_w, 1.0}}
  end
end
