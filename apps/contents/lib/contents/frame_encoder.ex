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

  defp command_to_pb({:player_sprite, x, y, frame}) do
    %Network.Proto.DrawCommand{
      kind: {:player_sprite, %Network.Proto.PlayerSprite{x: x * 1.0, y: y * 1.0, frame: frame}}
    }
  end

  defp command_to_pb({:sprite_raw, x, y, width, height, {{uv_ox, uv_oy}, {uv_sx, uv_sy}, {r, g, b, a}}}) do
    %Network.Proto.DrawCommand{
      kind:
        {:sprite_raw,
         %Network.Proto.SpriteRaw{
           x: x * 1.0,
           y: y * 1.0,
           width: width * 1.0,
           height: height * 1.0,
           uv_offset: [uv_ox * 1.0, uv_oy * 1.0],
           uv_size: [uv_sx * 1.0, uv_sy * 1.0],
           color_tint: [r * 1.0, g * 1.0, b * 1.0, a * 1.0]
         }}
    }
  end

  defp command_to_pb({:particle, x, y, r, g, b, {alpha, size}}) do
    %Network.Proto.DrawCommand{
      kind:
        {:particle,
         %Network.Proto.ParticleCmd{
           x: x * 1.0,
           y: y * 1.0,
           r: r * 1.0,
           g: g * 1.0,
           b: b * 1.0,
           alpha: alpha * 1.0,
           size: size * 1.0
         }}
    }
  end

  defp command_to_pb({:item, x, y, kind}) do
    %Network.Proto.DrawCommand{
      kind: {:item, %Network.Proto.ItemCmd{x: x * 1.0, y: y * 1.0, kind: kind}}
    }
  end

  defp command_to_pb({:obstacle, x, y, radius, kind}) do
    %Network.Proto.DrawCommand{
      kind:
        {:obstacle,
         %Network.Proto.ObstacleCmd{x: x * 1.0, y: y * 1.0, radius: radius * 1.0, kind: kind}}
    }
  end

  defp command_to_pb({:box_3d, x, y, z, half_w, half_h, {half_d, r, g, b, a}}) do
    %Network.Proto.DrawCommand{
      kind:
        {:box_3d,
         %Network.Proto.Box3dCmd{
           x: x * 1.0,
           y: y * 1.0,
           z: z * 1.0,
           half_w: half_w * 1.0,
           half_h: half_h * 1.0,
           half_d: half_d * 1.0,
           color: [r * 1.0, g * 1.0, b * 1.0, a * 1.0]
         }}
    }
  end

  defp command_to_pb({:grid_plane, size, divisions, {r, g, b, a}}) do
    %Network.Proto.DrawCommand{
      kind:
        {:grid_plane,
         %Network.Proto.GridPlaneCmd{
           size: size * 1.0,
           divisions: divisions,
           color: [r * 1.0, g * 1.0, b * 1.0, a * 1.0]
         }}
    }
  end

  defp command_to_pb({:grid_plane_verts, vertices}) do
    verts =
      Enum.map(vertices, fn {{px, py, pz}, {cr, cg, cb, ca}} ->
        %Network.Proto.MeshVertexMsg{
          position: [px * 1.0, py * 1.0, pz * 1.0],
          color: [cr * 1.0, cg * 1.0, cb * 1.0, ca * 1.0]
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
           top_color: [tr * 1.0, tg * 1.0, tb * 1.0, ta * 1.0],
           bottom_color: [br * 1.0, bg * 1.0, bb * 1.0, ba * 1.0]
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
         %Network.Proto.Camera2d{offset_x: offset_x * 1.0, offset_y: offset_y * 1.0}}
    }
  end

  defp camera_to_pb({:camera_3d, {ex, ey, ez}, {tx, ty, tz}, {ux, uy, uz}, {fov_deg, near, far}}) do
    %Network.Proto.CameraParams{
      kind:
        {:camera_3d,
         %Network.Proto.Camera3d{
           eye: [ex * 1.0, ey * 1.0, ez * 1.0],
           target: [tx * 1.0, ty * 1.0, tz * 1.0],
           up: [ux * 1.0, uy * 1.0, uz * 1.0],
           fov_deg: fov_deg * 1.0,
           near: near * 1.0,
           far: far * 1.0
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
        {:fixed, w, h} -> {:fixed, %Network.Proto.UiSizeFixed{w: w * 1.0, h: h * 1.0}}
      end

    %Network.Proto.UiRect{
      anchor: anchor_str,
      offset: [ox * 1.0, oy * 1.0],
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
           spacing: spacing * 1.0,
           padding: [pl * 1.0, pt * 1.0, pr * 1.0, pb * 1.0]
         }}
    }
  end

  defp ui_component_to_pb({:horizontal_layout, spacing, {pl, pt, pr, pb}}) do
    %Network.Proto.UiComponent{
      kind:
        {:horizontal_layout,
         %Network.Proto.UiHorizontalLayout{
           spacing: spacing * 1.0,
           padding: [pl * 1.0, pt * 1.0, pr * 1.0, pb * 1.0]
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
            color: [br * 1.0, bg * 1.0, bb * 1.0, ba * 1.0],
            width: w * 1.0
          }
      end

    %Network.Proto.UiComponent{
      kind:
        {:rect,
         %Network.Proto.UiRectStyle{
           color: [r * 1.0, g * 1.0, b * 1.0, a * 1.0],
           corner_radius: corner_radius * 1.0,
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
           color: [r * 1.0, g * 1.0, b * 1.0, a * 1.0],
           size: size * 1.0,
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
           color: [r * 1.0, g * 1.0, b * 1.0, a * 1.0],
           min_width: min_width * 1.0,
           min_height: min_height * 1.0
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
           value: value * 1.0,
           max: max * 1.0,
           width: width * 1.0,
           height: height * 1.0,
           fg_color_high: [fhr * 1.0, fhg * 1.0, fhb * 1.0, fha * 1.0],
           fg_color_mid: [fmr * 1.0, fmg * 1.0, fmb * 1.0, fma * 1.0],
           fg_color_low: [flr * 1.0, flg * 1.0, flb * 1.0, fla * 1.0],
           bg_color: [bgr * 1.0, bgg * 1.0, bgb * 1.0, bga * 1.0],
           corner_radius: corner_radius * 1.0
         }}
    }
  end

  defp ui_component_to_pb({:spacing, amount}) do
    %Network.Proto.UiComponent{kind: {:spacing, %Network.Proto.UiSpacing{amount: amount * 1.0}}}
  end

  defp ui_component_to_pb(
         {:world_text, world_x, world_y, world_z, text, {r, g, b, a}, {lifetime, max_lifetime}}
       ) do
    %Network.Proto.UiComponent{
      kind:
        {:world_text,
         %Network.Proto.UiWorldText{
           world_x: world_x * 1.0,
           world_y: world_y * 1.0,
           world_z: world_z * 1.0,
           text: text,
           color: [r * 1.0, g * 1.0, b * 1.0, a * 1.0],
           lifetime: lifetime * 1.0,
           max_lifetime: max_lifetime * 1.0
         }}
    }
  end

  defp ui_component_to_pb({:screen_flash, {r, g, b, a}}) do
    %Network.Proto.UiComponent{
      kind: {:screen_flash, %Network.Proto.UiScreenFlash{color: [r * 1.0, g * 1.0, b * 1.0, a * 1.0]}}
    }
  end

  defp mesh_def_to_pb(%{name: name, vertices: vertices, indices: indices}) do
    name_str = name |> to_string()

    verts =
      Enum.map(vertices, fn {{px, py, pz}, {cr, cg, cb, ca}} ->
        %Network.Proto.MeshVertexMsg{
          position: [px * 1.0, py * 1.0, pz * 1.0],
          color: [cr * 1.0, cg * 1.0, cb * 1.0, ca * 1.0]
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
       player_input: %Network.Proto.Vec2f{x: dx * 1.0, y: dy * 1.0}
     )}
  end

  defp put_injection_pb_field("player_snapshot", {hp, inv}, acc) do
    {:ok,
     struct!(acc,
       player_snapshot: %Network.Proto.Vec2f{x: hp * 1.0, y: inv * 1.0}
     )}
  end

  defp put_injection_pb_field("elapsed_seconds", v, acc) when is_number(v) do
    {:ok, struct!(acc, elapsed_seconds: v * 1.0)}
  end

  defp put_injection_pb_field("weapon_slots", slots, acc) when is_list(slots) do
    pb_slots =
      Enum.map(slots, fn {k, l, c, cs, pd} ->
        %Network.Proto.WeaponSlot{
          kind_id: k,
          level: l,
          cooldown: c * 1.0,
          cooldown_sec: cs * 1.0,
          precomputed_damage: pd
        }
      end)

    {:ok, struct!(acc, weapon_slots: %Network.Proto.WeaponSlotsList{slots: pb_slots})}
  end

  defp put_injection_pb_field("enemy_damage_this_frame", list, acc) when is_list(list) do
    pairs =
      Enum.map(list, fn {k, d} ->
        %Network.Proto.EnemyDamagePair{kind_id: k, damage: d * 1.0}
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
              x: x * 1.0,
              y: y * 1.0,
              radius: radius * 1.0,
              damage: damage * 1.0,
              invincible: inv
            }}
       }
     )}
  end

  defp put_injection_pb_field(_key, _value, _acc), do: :skip
end
