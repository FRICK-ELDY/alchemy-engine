defmodule Content.MessagePackEncoder do
  @moduledoc """
  P5-2: push_render_frame 用の MessagePack バイナリエンコーダ。
  P5: set_frame_injection 用の injection_map エンコーダ。

  DrawCommand・CameraParams・UiCanvas・MeshDef を msgpax でバイナリ化する。
  injection_map を MessagePack バイナリに変換する。
  スキーマ: docs/architecture/messagepack-schema.md
  """

  @doc """
  1フレーム分を MessagePack バイナリにエンコードする。

  - cursor_grab: `:grab` | `:release` | `:no_change`（省略可）。Zenoh 配信時にクライアントへ渡す。
  - NIF（ローカル）経由の場合は cursor_grab を別引数で渡す方式のまま。
  """
  @spec encode_frame(
          commands :: list(),
          camera :: tuple(),
          ui :: tuple(),
          mesh_definitions :: list(),
          cursor_grab :: :grab | :release | :no_change | nil
        ) :: binary()
  def encode_frame(commands, camera, ui, mesh_definitions, cursor_grab \\ nil) do
    frame =
      %{
        "commands" => encode_commands(commands),
        "camera" => encode_camera(camera),
        "ui" => encode_ui(ui),
        "mesh_definitions" => encode_mesh_definitions(mesh_definitions)
      }
      |> maybe_put_cursor_grab(cursor_grab)

    # Msgpax.pack! は NaN/Inf やサポート外の型で Msgpax.PackError を投げる
    Msgpax.pack!(frame, iodata: false)
  end

  defp maybe_put_cursor_grab(frame, :release), do: Map.put(frame, "cursor_grab", "release")
  defp maybe_put_cursor_grab(frame, :grab), do: Map.put(frame, "cursor_grab", "grab")
  defp maybe_put_cursor_grab(frame, _), do: frame

  @doc "DrawCommand リストを MessagePack 用の map リストに変換する。"
  def encode_commands(commands) do
    Enum.map(commands, &encode_command/1)
  end

  defp encode_command({:player_sprite, x, y, frame}) do
    %{"t" => "player_sprite", "x" => x, "y" => y, "frame" => frame}
  end

  defp encode_command(
         {:sprite_raw, x, y, width, height, {{uv_ox, uv_oy}, {uv_sx, uv_sy}, {r, g, b, a}}}
       ) do
    %{
      "t" => "sprite_raw",
      "x" => x,
      "y" => y,
      "width" => width,
      "height" => height,
      "uv_offset" => [uv_ox, uv_oy],
      "uv_size" => [uv_sx, uv_sy],
      "color_tint" => [r, g, b, a]
    }
  end

  defp encode_command({:particle, x, y, r, g, b, {alpha, size}}) do
    %{
      "t" => "particle",
      "x" => x,
      "y" => y,
      "r" => r,
      "g" => g,
      "b" => b,
      "alpha" => alpha,
      "size" => size
    }
  end

  defp encode_command({:item, x, y, kind}) do
    %{"t" => "item", "x" => x, "y" => y, "kind" => kind}
  end

  defp encode_command({:obstacle, x, y, radius, kind}) do
    %{"t" => "obstacle", "x" => x, "y" => y, "radius" => radius, "kind" => kind}
  end

  defp encode_command({:box_3d, x, y, z, half_w, half_h, {half_d, r, g, b, a}}) do
    %{
      "t" => "box_3d",
      "x" => x,
      "y" => y,
      "z" => z,
      "half_w" => half_w,
      "half_h" => half_h,
      "half_d" => half_d,
      "color" => [r, g, b, a]
    }
  end

  defp encode_command({:grid_plane, size, divisions, {r, g, b, a}}) do
    %{"t" => "grid_plane", "size" => size, "divisions" => divisions, "color" => [r, g, b, a]}
  end

  defp encode_command({:grid_plane_verts, vertices}) do
    encoded =
      Enum.map(vertices, fn {{px, py, pz}, {cr, cg, cb, ca}} ->
        [[px, py, pz], [cr, cg, cb, ca]]
      end)

    %{"t" => "grid_plane_verts", "vertices" => encoded}
  end

  defp encode_command({:skybox, {tr, tg, tb, ta}, {br, bg, bb, ba}}) do
    %{
      "t" => "skybox",
      "top_color" => [tr, tg, tb, ta],
      "bottom_color" => [br, bg, bb, ba]
    }
  end

  defp encode_command(command) do
    raise ArgumentError,
          "unknown DrawCommand #{inspect(command)}. Add a clause or update docs/architecture/messagepack-schema.md"
  end

  @doc "CameraParams を MessagePack 用の map に変換する。"
  def encode_camera({:camera_2d, offset_x, offset_y}) do
    %{"t" => "camera_2d", "offset_x" => offset_x, "offset_y" => offset_y}
  end

  def encode_camera({:camera_3d, {ex, ey, ez}, {tx, ty, tz}, {ux, uy, uz}, {fov_deg, near, far}}) do
    %{
      "t" => "camera_3d",
      "eye" => [ex, ey, ez],
      "target" => [tx, ty, tz],
      "up" => [ux, uy, uz],
      "fov_deg" => fov_deg,
      "near" => near,
      "far" => far
    }
  end

  @doc "UiCanvas を MessagePack 用の map に変換する。"
  def encode_ui({:canvas, nodes}) do
    %{"nodes" => Enum.map(nodes, &encode_ui_node/1)}
  end

  defp encode_ui_node({:node, rect, component, children}) do
    %{
      "rect" => encode_ui_rect(rect),
      "component" => encode_ui_component(component),
      "children" => Enum.map(children, &encode_ui_node/1)
    }
  end

  defp encode_ui_rect({anchor, {ox, oy}, size}) do
    anchor_str = Atom.to_string(anchor)

    size_val =
      case size do
        :wrap -> "wrap"
        {:fixed, w, h} -> [w, h]
      end

    %{"anchor" => anchor_str, "offset" => [ox, oy], "size" => size_val}
  end

  defp encode_ui_component(:separator) do
    %{"t" => "separator"}
  end

  defp encode_ui_component({:vertical_layout, spacing, {pl, pt, pr, pb}}) do
    %{"t" => "vertical_layout", "spacing" => spacing, "padding" => [pl, pt, pr, pb]}
  end

  defp encode_ui_component({:horizontal_layout, spacing, {pl, pt, pr, pb}}) do
    %{"t" => "horizontal_layout", "spacing" => spacing, "padding" => [pl, pt, pr, pb]}
  end

  defp encode_ui_component({:rect, {r, g, b, a}, corner_radius, border}) do
    border_val =
      case border do
        :none -> nil
        {{br, bg, bb, ba}, w} -> [[br, bg, bb, ba], w]
      end

    %{
      "t" => "rect",
      "color" => [r, g, b, a],
      "corner_radius" => corner_radius,
      "border" => border_val
    }
  end

  defp encode_ui_component({:text, text, {r, g, b, a}, size, bold}) do
    %{"t" => "text", "text" => text, "color" => [r, g, b, a], "size" => size, "bold" => bold}
  end

  defp encode_ui_component({:button, label, action, {r, g, b, a}, min_width, min_height}) do
    %{
      "t" => "button",
      "label" => label,
      "action" => action,
      "color" => [r, g, b, a],
      "min_width" => min_width,
      "min_height" => min_height
    }
  end

  defp encode_ui_component(
         {:progress_bar, value, max, width, height,
          {{fhr, fhg, fhb, fha}, {fmr, fmg, fmb, fma}, {flr, flg, flb, fla}, {bgr, bgg, bgb, bga},
           corner_radius}}
       ) do
    %{
      "t" => "progress_bar",
      "value" => value,
      "max" => max,
      "width" => width,
      "height" => height,
      "fg_color_high" => [fhr, fhg, fhb, fha],
      "fg_color_mid" => [fmr, fmg, fmb, fma],
      "fg_color_low" => [flr, flg, flb, fla],
      "bg_color" => [bgr, bgg, bgb, bga],
      "corner_radius" => corner_radius
    }
  end

  defp encode_ui_component({:spacing, amount}) do
    %{"t" => "spacing", "amount" => amount}
  end

  defp encode_ui_component(
         {:world_text, world_x, world_y, world_z, text, {r, g, b, a}, {lifetime, max_lifetime}}
       ) do
    %{
      "t" => "world_text",
      "world_x" => world_x,
      "world_y" => world_y,
      "world_z" => world_z,
      "text" => text,
      "color" => [r, g, b, a],
      "lifetime" => lifetime,
      "max_lifetime" => max_lifetime
    }
  end

  defp encode_ui_component({:screen_flash, {r, g, b, a}}) do
    %{"t" => "screen_flash", "color" => [r, g, b, a]}
  end

  # ── set_frame_injection（injection_map）エンコーダ ───────────────────────

  @doc """
  injection_map を MessagePack バイナリにエンコードする。

  P5: set_frame_injection_binary 用。map のキーは atom でも string でも可。
  存在するキーのみ pack する。スキーマ: docs/architecture/messagepack-schema.md §7

  対応しているのは数値・文字列・リスト・マップなど msgpax で pack 可能な型のみ。
  未対応の型（PID・関数参照など）が渡ると pack に失敗し、{:error, reason} を返す。
  """
  @spec encode_injection_map(map()) :: {:ok, binary()} | {:error, term()}
  def encode_injection_map(injection) when is_map(injection) and map_size(injection) == 0 do
    Msgpax.pack(%{}, iodata: false)
  end

  def encode_injection_map(injection) when is_map(injection) do
    frame =
      injection
      |> Enum.reduce(%{}, fn {key, value}, acc ->
        key_str = to_string(key)
        Map.put(acc, key_str, encode_injection_value(key_str, value))
      end)

    Msgpax.pack(frame, iodata: false)
  end

  defp encode_injection_value("player_input", {dx, dy}), do: [dx * 1.0, dy * 1.0]
  defp encode_injection_value("player_snapshot", {hp, inv}), do: [hp * 1.0, inv * 1.0]
  defp encode_injection_value("elapsed_seconds", v) when is_number(v), do: v * 1.0

  defp encode_injection_value("weapon_slots", slots) when is_list(slots) do
    Enum.map(slots, fn {k, l, c, cs, pd} -> [k, l, c * 1.0, cs * 1.0, pd] end)
  end

  defp encode_injection_value("enemy_damage_this_frame", list) when is_list(list) do
    Enum.map(list, fn {k, d} -> [k, d * 1.0] end)
  end

  defp encode_injection_value("special_entity_snapshot", :none), do: %{"t" => "none"}

  defp encode_injection_value("special_entity_snapshot", {:alive, x, y, radius, damage, inv}) do
    %{
      "t" => "alive",
      "x" => x * 1.0,
      "y" => y * 1.0,
      "radius" => radius * 1.0,
      "damage" => damage * 1.0,
      "invincible" => inv
    }
  end

  defp encode_injection_value(_key, value), do: value

  @doc "MeshDef リストを MessagePack 用の map リストに変換する。"
  def encode_mesh_definitions(list) when is_list(list) do
    Enum.map(list, &encode_mesh_def/1)
  end

  defp encode_mesh_def(%{name: name, vertices: vertices, indices: indices}) do
    name_str = name |> to_string()

    verts =
      Enum.map(vertices, fn {{px, py, pz}, {cr, cg, cb, ca}} ->
        [[px, py, pz], [cr, cg, cb, ca]]
      end)

    %{"name" => name_str, "vertices" => verts, "indices" => indices}
  end
end
