defmodule Content.FrameEncoder do
  require Logger

  @moduledoc """
  Zenoh フレーム配信用 protobuf エンコーダ。

  DrawCommand・CameraParams・UiCanvas・MeshDef を `Network.Proto.RenderFrame` に変換して encode する。
  スキーマ: proto/render_frame.proto
  """

  @doc """
  1フレーム分を protobuf（`Network.Proto.RenderFrame`）にエンコードする。

  - cursor_grab: `:grab` | `:release` | `:no_change`（省略可）。Zenoh 配信時にクライアントへ渡す。
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
      %Network.Proto.RenderFrame{
        commands: Enum.map(commands, &command_to_pb/1),
        camera: camera_to_pb(camera),
        ui: ui_to_pb(ui),
        mesh_definitions: Enum.map(mesh_definitions, &mesh_def_to_pb/1)
      }
      |> maybe_put_cursor_grab_pb(cursor_grab)

    Network.Proto.RenderFrame.encode(frame)
  end

  defp maybe_put_cursor_grab_pb(f, :grab), do: struct!(f, cursor_grab: 1)
  defp maybe_put_cursor_grab_pb(f, :release), do: struct!(f, cursor_grab: 2)
  defp maybe_put_cursor_grab_pb(f, _), do: f

  defp pb_float(n), do: n * 1.0

  defp color_tuple_to_pb_list({r, g, b, a}) do
    [pb_float(r), pb_float(g), pb_float(b), pb_float(a)]
  end

  defp vec2_to_pb_list({a, b}), do: [pb_float(a), pb_float(b)]

  defp vec3_to_pb_list({a, b, c}), do: [pb_float(a), pb_float(b), pb_float(c)]

  defp command_to_pb({:player_sprite, x, y, frame}) do
    %Network.Proto.DrawCommand{
      kind: {:player_sprite, %Network.Proto.PlayerSprite{x: pb_float(x), y: pb_float(y), frame: frame}}
    }
  end

  defp command_to_pb({:sprite_raw, x, y, width, height, {{uv_ox, uv_oy}, {uv_sx, uv_sy}, {r, g, b, a}}}) do
    %Network.Proto.DrawCommand{
      kind:
        {:sprite_raw,
         %Network.Proto.SpriteRaw{
           x: pb_float(x),
           y: pb_float(y),
           width: pb_float(width),
           height: pb_float(height),
           uv_offset: vec2_to_pb_list({uv_ox, uv_oy}),
           uv_size: vec2_to_pb_list({uv_sx, uv_sy}),
           color_tint: color_tuple_to_pb_list({r, g, b, a})
         }}
    }
  end

  defp command_to_pb({:particle, x, y, r, g, b, {alpha, size}}) do
    %Network.Proto.DrawCommand{
      kind:
        {:particle,
         %Network.Proto.ParticleCmd{
           x: pb_float(x),
           y: pb_float(y),
           r: pb_float(r),
           g: pb_float(g),
           b: pb_float(b),
           alpha: pb_float(alpha),
           size: pb_float(size)
         }}
    }
  end

  defp command_to_pb({:item, x, y, kind}) do
    %Network.Proto.DrawCommand{
      kind: {:item, %Network.Proto.ItemCmd{x: pb_float(x), y: pb_float(y), kind: kind}}
    }
  end

  defp command_to_pb({:obstacle, x, y, radius, kind}) do
    %Network.Proto.DrawCommand{
      kind:
        {:obstacle,
         %Network.Proto.ObstacleCmd{x: pb_float(x), y: pb_float(y), radius: pb_float(radius), kind: kind}}
    }
  end

  defp command_to_pb({:box_3d, x, y, z, half_w, half_h, {half_d, r, g, b, a}}) do
    %Network.Proto.DrawCommand{
      kind:
        {:box_3d,
         %Network.Proto.Box3dCmd{
           x: pb_float(x),
           y: pb_float(y),
           z: pb_float(z),
           half_w: pb_float(half_w),
           half_h: pb_float(half_h),
           half_d: pb_float(half_d),
           color: color_tuple_to_pb_list({r, g, b, a})
         }}
    }
  end

  defp command_to_pb({:grid_plane, size, divisions, {r, g, b, a}}) do
    %Network.Proto.DrawCommand{
      kind:
        {:grid_plane,
         %Network.Proto.GridPlaneCmd{
           size: pb_float(size),
           divisions: divisions,
           color: color_tuple_to_pb_list({r, g, b, a})
         }}
    }
  end

  defp command_to_pb({:grid_plane_verts, vertices}) do
    verts =
      Enum.map(vertices, fn {{px, py, pz}, {cr, cg, cb, ca}} ->
        %Network.Proto.MeshVertexMsg{
          position: vec3_to_pb_list({px, py, pz}),
          color: color_tuple_to_pb_list({cr, cg, cb, ca})
        }
      end)

    %Network.Proto.DrawCommand{
      kind: {:grid_plane_verts, %Network.Proto.GridPlaneVertsCmd{vertices: verts}}
    }
  end

  defp command_to_pb({:skybox, {tr, tg, tb, ta}, {br, bg, bb, ba}}) do
    %Network.Proto.DrawCommand{
      kind:
        {:skybox,
         %Network.Proto.SkyboxCmd{
           top_color: color_tuple_to_pb_list({tr, tg, tb, ta}),
           bottom_color: color_tuple_to_pb_list({br, bg, bb, ba})
         }}
    }
  end

  defp command_to_pb(command) do
    raise ArgumentError,
          "unknown DrawCommand #{inspect(command)}. Add a clause or update proto/render_frame.proto"
  end

  defp camera_to_pb({:camera_2d, offset_x, offset_y}) do
    %Network.Proto.CameraParams{
      kind:
        {:camera_2d,
         %Network.Proto.Camera2d{offset_x: pb_float(offset_x), offset_y: pb_float(offset_y)}}
    }
  end

  defp camera_to_pb({:camera_3d, {ex, ey, ez}, {tx, ty, tz}, {ux, uy, uz}, {fov_deg, near, far}}) do
    %Network.Proto.CameraParams{
      kind:
        {:camera_3d,
         %Network.Proto.Camera3d{
           eye: vec3_to_pb_list({ex, ey, ez}),
           target: vec3_to_pb_list({tx, ty, tz}),
           up: vec3_to_pb_list({ux, uy, uz}),
           fov_deg: pb_float(fov_deg),
           near: pb_float(near),
           far: pb_float(far)
         }}
    }
  end

  defp ui_to_pb({:canvas, nodes}) do
    %Network.Proto.UiCanvas{nodes: Enum.map(nodes, &ui_node_to_pb/1)}
  end

  defp ui_node_to_pb({:node, rect, component, children}) do
    %Network.Proto.UiNode{
      rect: ui_rect_to_pb(rect),
      component: ui_component_to_pb(component),
      children: Enum.map(children, &ui_node_to_pb/1)
    }
  end

  defp ui_rect_to_pb({anchor, {ox, oy}, size}) do
    anchor_str = Atom.to_string(anchor)

    size_pb =
      case size do
        :wrap -> {:wrap, %Network.Proto.UiSizeWrap{}}
        {:fixed, w, h} -> {:fixed, %Network.Proto.UiSizeFixed{w: pb_float(w), h: pb_float(h)}}
      end

    %Network.Proto.UiRect{
      anchor: anchor_str,
      offset: vec2_to_pb_list({ox, oy}),
      size: size_pb
    }
  end

  defp ui_component_to_pb(:separator) do
    %Network.Proto.UiComponent{kind: {:separator, %Network.Proto.UiSeparator{}}}
  end

  defp ui_component_to_pb({:vertical_layout, spacing, {pl, pt, pr, pb}}) do
    %Network.Proto.UiComponent{
      kind:
        {:vertical_layout,
         %Network.Proto.UiVerticalLayout{
           spacing: pb_float(spacing),
           padding: color_tuple_to_pb_list({pl, pt, pr, pb})
         }}
    }
  end

  defp ui_component_to_pb({:horizontal_layout, spacing, {pl, pt, pr, pb}}) do
    %Network.Proto.UiComponent{
      kind:
        {:horizontal_layout,
         %Network.Proto.UiHorizontalLayout{
           spacing: pb_float(spacing),
           padding: color_tuple_to_pb_list({pl, pt, pr, pb})
         }}
    }
  end

  defp ui_component_to_pb({:rect, {r, g, b, a}, corner_radius, border}) do
    border_pb =
      case border do
        :none ->
          nil

        {{br, bg, bb, ba}, w} ->
          %Network.Proto.UiBorder{
            color: color_tuple_to_pb_list({br, bg, bb, ba}),
            width: pb_float(w)
          }
      end

    %Network.Proto.UiComponent{
      kind:
        {:rect,
         %Network.Proto.UiRectStyle{
           color: color_tuple_to_pb_list({r, g, b, a}),
           corner_radius: pb_float(corner_radius),
           border: border_pb
         }}
    }
  end

  defp ui_component_to_pb({:text, text, {r, g, b, a}, size, bold}) do
    %Network.Proto.UiComponent{
      kind:
        {:text,
         %Network.Proto.UiText{
           text: text,
           color: color_tuple_to_pb_list({r, g, b, a}),
           size: pb_float(size),
           bold: bold
         }}
    }
  end

  defp ui_component_to_pb({:button, label, action, {r, g, b, a}, min_width, min_height}) do
    %Network.Proto.UiComponent{
      kind:
        {:button,
         %Network.Proto.UiButton{
           label: label,
           action: action,
           color: color_tuple_to_pb_list({r, g, b, a}),
           min_width: pb_float(min_width),
           min_height: pb_float(min_height)
         }}
    }
  end

  defp ui_component_to_pb(
         {:progress_bar, value, max, width, height,
          {{fhr, fhg, fhb, fha}, {fmr, fmg, fmb, fma}, {flr, flg, flb, fla}, {bgr, bgg, bgb, bga},
           corner_radius}}
       ) do
    %Network.Proto.UiComponent{
      kind:
        {:progress_bar,
         %Network.Proto.UiProgressBar{
           value: pb_float(value),
           max: pb_float(max),
           width: pb_float(width),
           height: pb_float(height),
           fg_color_high: color_tuple_to_pb_list({fhr, fhg, fhb, fha}),
           fg_color_mid: color_tuple_to_pb_list({fmr, fmg, fmb, fma}),
           fg_color_low: color_tuple_to_pb_list({flr, flg, flb, fla}),
           bg_color: color_tuple_to_pb_list({bgr, bgg, bgb, bga}),
           corner_radius: pb_float(corner_radius)
         }}
    }
  end

  defp ui_component_to_pb({:spacing, amount}) do
    %Network.Proto.UiComponent{kind: {:spacing, %Network.Proto.UiSpacing{amount: pb_float(amount)}}}
  end

  defp ui_component_to_pb(
         {:world_text, world_x, world_y, world_z, text, {r, g, b, a}, {lifetime, max_lifetime}}
       ) do
    %Network.Proto.UiComponent{
      kind:
        {:world_text,
         %Network.Proto.UiWorldText{
           world_x: pb_float(world_x),
           world_y: pb_float(world_y),
           world_z: pb_float(world_z),
           text: text,
           color: color_tuple_to_pb_list({r, g, b, a}),
           lifetime: pb_float(lifetime),
           max_lifetime: pb_float(max_lifetime)
         }}
    }
  end

  defp ui_component_to_pb({:screen_flash, {r, g, b, a}}) do
    %Network.Proto.UiComponent{
      kind: {:screen_flash, %Network.Proto.UiScreenFlash{color: color_tuple_to_pb_list({r, g, b, a})}}
    }
  end

  defp mesh_def_to_pb(%{name: name, vertices: vertices, indices: indices}) do
    name_str = name |> to_string()

    verts =
      Enum.map(vertices, fn {{px, py, pz}, {cr, cg, cb, ca}} ->
        %Network.Proto.MeshVertexMsg{
          position: vec3_to_pb_list({px, py, pz}),
          color: color_tuple_to_pb_list({cr, cg, cb, ca})
        }
      end)

    %Network.Proto.MeshDefMsg{name: name_str, vertices: verts, indices: indices}
  end

  # ── set_frame_injection（injection_map）protobuf エンコーダ ─────────────────

  @doc """
  injection_map を `Network.Proto.FrameInjection` にエンコードする。

  set_frame_injection_binary NIF 用。map のキーは atom でも string でも可。
  スキーマ: proto/frame_injection.proto。未対応キーはログして無視する。
  """
  @spec encode_injection_map(map()) :: {:ok, binary()} | {:error, term()}
  def encode_injection_map(injection) when is_map(injection) do
    frame =
      Enum.reduce(injection, %Network.Proto.FrameInjection{}, fn {key, value}, acc ->
        key_str = to_string(key)

        case put_injection_pb_field(key_str, value, acc) do
          {:ok, next} ->
            next

          :skip ->
            Logger.warning(
              "[FrameEncoder] encode_injection_map: unsupported key or value type #{inspect(key_str)}, skipping"
            )

            acc
        end
      end)

    {:ok, Network.Proto.FrameInjection.encode(frame)}
  rescue
    e -> {:error, e}
  end

  defp put_injection_pb_field("player_input", {dx, dy}, acc) do
    {:ok,
     struct!(acc,
       player_input: %Network.Proto.Vec2f{x: pb_float(dx), y: pb_float(dy)}
     )}
  end

  defp put_injection_pb_field("player_snapshot", {hp, inv}, acc) do
    {:ok,
     struct!(acc,
       player_snapshot: %Network.Proto.Vec2f{x: pb_float(hp), y: pb_float(inv)}
     )}
  end

  defp put_injection_pb_field("elapsed_seconds", v, acc) when is_number(v) do
    {:ok, struct!(acc, elapsed_seconds: pb_float(v))}
  end

  defp put_injection_pb_field("weapon_slots", slots, acc) when is_list(slots) do
    pb_slots =
      Enum.map(slots, fn {k, l, c, cs, pd} ->
        %Network.Proto.WeaponSlot{
          kind_id: k,
          level: l,
          cooldown: pb_float(c),
          cooldown_sec: pb_float(cs),
          precomputed_damage: pd
        }
      end)

    {:ok, struct!(acc, weapon_slots: %Network.Proto.WeaponSlotsList{slots: pb_slots})}
  end

  defp put_injection_pb_field("enemy_damage_this_frame", list, acc) when is_list(list) do
    pairs =
      Enum.map(list, fn {k, d} ->
        %Network.Proto.EnemyDamagePair{kind_id: k, damage: pb_float(d)}
      end)

    {:ok,
     struct!(acc,
       enemy_damage_this_frame: %Network.Proto.EnemyDamageList{pairs: pairs}
     )}
  end

  defp put_injection_pb_field("special_entity_snapshot", :none, acc) do
    {:ok,
     struct!(acc,
       special_entity_snapshot: %Network.Proto.SpecialEntitySnapshot{
         state: {:none, %Network.Proto.SpecialNone{}}
       }
     )}
  end

  defp put_injection_pb_field("special_entity_snapshot", {:alive, x, y, radius, damage, inv}, acc) do
    {:ok,
     struct!(acc,
       special_entity_snapshot: %Network.Proto.SpecialEntitySnapshot{
         state:
           {:alive,
            %Network.Proto.SpecialAlive{
              x: pb_float(x),
              y: pb_float(y),
              radius: pb_float(radius),
              damage: pb_float(damage),
              invincible: inv
            }}
       }
     )}
  end

  defp put_injection_pb_field(_key, _value, _acc), do: :skip
end
