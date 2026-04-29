defmodule Content.FrameEncoder do
  require Logger

  alias Content.FrameEncoder.DrawCommands.Box3d, as: DrawBox3d
  alias Content.FrameEncoder.DrawCommands.Cone3d, as: DrawCone3d
  alias Content.FrameEncoder.DrawCommands.GridPlane, as: DrawGridPlane
  alias Content.FrameEncoder.DrawCommands.GridPlaneVerts, as: DrawGridPlaneVerts
  alias Content.FrameEncoder.DrawCommands.Item, as: DrawItem
  alias Content.FrameEncoder.DrawCommands.Obstacle, as: DrawObstacle
  alias Content.FrameEncoder.DrawCommands.Particle, as: DrawParticle
  alias Content.FrameEncoder.DrawCommands.PlayerSprite, as: DrawPlayerSprite
  alias Content.FrameEncoder.DrawCommands.Skybox, as: DrawSkybox
  alias Content.FrameEncoder.DrawCommands.Sphere3d, as: DrawSphere3d
  alias Content.FrameEncoder.DrawCommands.SpriteRaw, as: DrawSpriteRaw
  alias Content.FrameEncoder.Proto

  @moduledoc """
  Zenoh フレーム配信用 protobuf エンコーダ。

  DrawCommand・CameraParams・UiCanvas・MeshDef を `Alchemy.Render.RenderFrame` に変換して encode する。
  スキーマ: [alchemy-protocol の `render_frame.proto`（例: タグ `v0.1.1`）](https://github.com/FRICK-ELDY/alchemy-protocol/blob/v0.1.1/proto/render_frame.proto)（本リポでは submodule `3rdparty/alchemy-protocol/proto/`）。
  """

  @doc """
  1フレーム分を protobuf（`Alchemy.Render.RenderFrame`）にエンコードする。

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
      %Alchemy.Render.RenderFrame{
        commands: Enum.map(commands, &command_to_pb/1),
        camera: camera_to_pb(camera),
        ui: ui_to_pb(ui),
        mesh_definitions: Enum.map(mesh_definitions, &mesh_def_to_pb/1)
      }
      |> maybe_put_cursor_grab_pb(cursor_grab)

    Alchemy.Render.RenderFrame.encode(frame)
  end

  defp maybe_put_cursor_grab_pb(f, :grab), do: struct!(f, cursor_grab: 1)
  defp maybe_put_cursor_grab_pb(f, :release), do: struct!(f, cursor_grab: 2)
  defp maybe_put_cursor_grab_pb(f, _), do: f

  defp command_to_pb({:player_sprite, _, _, _} = t), do: DrawPlayerSprite.to_pb(t)
  defp command_to_pb({:sprite_raw, _, _, _, _, _} = t), do: DrawSpriteRaw.to_pb(t)
  defp command_to_pb({:particle, _, _, _, _, _, _} = t), do: DrawParticle.to_pb(t)
  defp command_to_pb({:item, _, _, _} = t), do: DrawItem.to_pb(t)
  defp command_to_pb({:obstacle, _, _, _, _} = t), do: DrawObstacle.to_pb(t)
  defp command_to_pb({:box_3d, _, _, _, _, _, _} = t), do: DrawBox3d.to_pb(t)
  defp command_to_pb({:cone_3d, _, _, _, _, _, _} = t), do: DrawCone3d.to_pb(t)
  defp command_to_pb({:sphere_3d, _, _, _, _, _} = t), do: DrawSphere3d.to_pb(t)
  defp command_to_pb({:grid_plane, _, _, _} = t), do: DrawGridPlane.to_pb(t)
  defp command_to_pb({:grid_plane_verts, _} = t), do: DrawGridPlaneVerts.to_pb(t)
  defp command_to_pb({:skybox, _, _} = t), do: DrawSkybox.to_pb(t)

  defp command_to_pb(command) do
    raise ArgumentError,
          "unknown DrawCommand #{inspect(command)}. Add a clause or update alchemy-protocol render_frame schema (3rdparty/alchemy-protocol/proto)"
  end

  defp camera_to_pb({:camera_2d, offset_x, offset_y}) do
    %Alchemy.Render.CameraParams{
      kind:
        {:camera_2d,
         %Alchemy.Render.Camera2d{
           offset_x: Proto.pb_float(offset_x),
           offset_y: Proto.pb_float(offset_y)
         }}
    }
  end

  defp camera_to_pb({:camera_3d, {ex, ey, ez}, {tx, ty, tz}, {ux, uy, uz}, {fov_deg, near, far}}) do
    %Alchemy.Render.CameraParams{
      kind:
        {:camera_3d,
         %Alchemy.Render.Camera3d{
           eye: Proto.vec3_to_pb_list({ex, ey, ez}),
           target: Proto.vec3_to_pb_list({tx, ty, tz}),
           up: Proto.vec3_to_pb_list({ux, uy, uz}),
           fov_deg: Proto.pb_float(fov_deg),
           near: Proto.pb_float(near),
           far: Proto.pb_float(far)
         }}
    }
  end

  defp ui_to_pb({:canvas, nodes}) do
    %Alchemy.Render.UiCanvas{nodes: Enum.map(nodes, &ui_node_to_pb/1)}
  end

  defp ui_node_to_pb({:node, rect, component, children}) do
    %Alchemy.Render.UiNode{
      rect: ui_rect_to_pb(rect),
      component: ui_component_to_pb(component),
      children: Enum.map(children, &ui_node_to_pb/1)
    }
  end

  defp ui_rect_to_pb({anchor, {ox, oy}, size}) do
    anchor_str = Atom.to_string(anchor)

    size_pb =
      case size do
        :wrap ->
          {:wrap, %Alchemy.Render.UiSizeWrap{}}

        {:fixed, w, h} ->
          {:fixed, %Alchemy.Render.UiSizeFixed{w: Proto.pb_float(w), h: Proto.pb_float(h)}}
      end

    %Alchemy.Render.UiRect{
      anchor: anchor_str,
      offset: Proto.vec2_to_pb_list({ox, oy}),
      size: size_pb
    }
  end

  defp ui_component_to_pb(:separator) do
    %Alchemy.Render.UiComponent{kind: {:separator, %Alchemy.Render.UiSeparator{}}}
  end

  defp ui_component_to_pb({:vertical_layout, spacing, {pl, pt, pr, pb}}) do
    %Alchemy.Render.UiComponent{
      kind:
        {:vertical_layout,
         %Alchemy.Render.UiVerticalLayout{
           spacing: Proto.pb_float(spacing),
           padding: Proto.color_tuple_to_pb_list({pl, pt, pr, pb})
         }}
    }
  end

  defp ui_component_to_pb({:horizontal_layout, spacing, {pl, pt, pr, pb}}) do
    %Alchemy.Render.UiComponent{
      kind:
        {:horizontal_layout,
         %Alchemy.Render.UiHorizontalLayout{
           spacing: Proto.pb_float(spacing),
           padding: Proto.color_tuple_to_pb_list({pl, pt, pr, pb})
         }}
    }
  end

  defp ui_component_to_pb({:rect, {r, g, b, a}, corner_radius, border}) do
    border_pb =
      case border do
        :none ->
          nil

        {{br, bg, bb, ba}, w} ->
          %Alchemy.Render.UiBorder{
            color: Proto.color_tuple_to_pb_list({br, bg, bb, ba}),
            width: Proto.pb_float(w)
          }
      end

    %Alchemy.Render.UiComponent{
      kind:
        {:rect,
         %Alchemy.Render.UiRectStyle{
           color: Proto.color_tuple_to_pb_list({r, g, b, a}),
           corner_radius: Proto.pb_float(corner_radius),
           border: border_pb
         }}
    }
  end

  defp ui_component_to_pb({:text, text, {r, g, b, a}, size, bold}) do
    %Alchemy.Render.UiComponent{
      kind:
        {:text,
         %Alchemy.Render.UiText{
           text: text,
           color: Proto.color_tuple_to_pb_list({r, g, b, a}),
           size: Proto.pb_float(size),
           bold: bold
         }}
    }
  end

  defp ui_component_to_pb({:button, label, action, {r, g, b, a}, min_width, min_height}) do
    %Alchemy.Render.UiComponent{
      kind:
        {:button,
         %Alchemy.Render.UiButton{
           label: label,
           action: action,
           color: Proto.color_tuple_to_pb_list({r, g, b, a}),
           min_width: Proto.pb_float(min_width),
           min_height: Proto.pb_float(min_height)
         }}
    }
  end

  defp ui_component_to_pb(
         {:progress_bar, value, max, width, height,
          {{fhr, fhg, fhb, fha}, {fmr, fmg, fmb, fma}, {flr, flg, flb, fla}, {bgr, bgg, bgb, bga},
           corner_radius}}
       ) do
    %Alchemy.Render.UiComponent{
      kind:
        {:progress_bar,
         %Alchemy.Render.UiProgressBar{
           value: Proto.pb_float(value),
           max: Proto.pb_float(max),
           width: Proto.pb_float(width),
           height: Proto.pb_float(height),
           fg_color_high: Proto.color_tuple_to_pb_list({fhr, fhg, fhb, fha}),
           fg_color_mid: Proto.color_tuple_to_pb_list({fmr, fmg, fmb, fma}),
           fg_color_low: Proto.color_tuple_to_pb_list({flr, flg, flb, fla}),
           bg_color: Proto.color_tuple_to_pb_list({bgr, bgg, bgb, bga}),
           corner_radius: Proto.pb_float(corner_radius)
         }}
    }
  end

  defp ui_component_to_pb({:spacing, amount}) do
    %Alchemy.Render.UiComponent{
      kind: {:spacing, %Alchemy.Render.UiSpacing{amount: Proto.pb_float(amount)}}
    }
  end

  defp ui_component_to_pb(
         {:world_text, world_x, world_y, world_z, text, {r, g, b, a}, {lifetime, max_lifetime}}
       ) do
    %Alchemy.Render.UiComponent{
      kind:
        {:world_text,
         %Alchemy.Render.UiWorldText{
           world_x: Proto.pb_float(world_x),
           world_y: Proto.pb_float(world_y),
           world_z: Proto.pb_float(world_z),
           text: text,
           color: Proto.color_tuple_to_pb_list({r, g, b, a}),
           lifetime: Proto.pb_float(lifetime),
           max_lifetime: Proto.pb_float(max_lifetime)
         }}
    }
  end

  defp ui_component_to_pb({:screen_flash, {r, g, b, a}}) do
    %Alchemy.Render.UiComponent{
      kind:
        {:screen_flash,
         %Alchemy.Render.UiScreenFlash{color: Proto.color_tuple_to_pb_list({r, g, b, a})}}
    }
  end

  defp mesh_def_to_pb(%{name: name, vertices: vertices, indices: indices}) do
    name_str = name |> to_string()

    verts =
      Enum.map(vertices, fn {{px, py, pz}, {cr, cg, cb, ca}} ->
        %Alchemy.Render.MeshVertex{
          position: Proto.vec3_to_pb_list({px, py, pz}),
          color: Proto.color_tuple_to_pb_list({cr, cg, cb, ca})
        }
      end)

    %Alchemy.Render.MeshDef{name: name_str, vertices: verts, indices: indices}
  end

  # ── FrameInjection（injection_map）protobuf エンコーダ ───────────────────────

  @doc """
  injection_map を `Alchemy.Frame.FrameInjection` にエンコードする。

  バイナリは `Contents.Events.Game` のフレーム注入フローで参照可能。旧 NIF への受け渡しは撤去済み。
  map のキーは atom でも string でも可。スキーマ: [frame_injection.proto（alchemy-protocol `v0.1.1`）](https://github.com/FRICK-ELDY/alchemy-protocol/blob/v0.1.1/proto/frame_injection.proto)（本リポでは `3rdparty/alchemy-protocol/proto/`）。未対応キーはログして無視する。
  """
  @spec encode_injection_map(map()) :: {:ok, binary()} | {:error, term()}
  def encode_injection_map(injection) when is_map(injection) do
    frame =
      Enum.reduce(injection, %Alchemy.Frame.FrameInjection{}, fn {key, value}, acc ->
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

    {:ok, Alchemy.Frame.FrameInjection.encode(frame)}
  rescue
    e -> {:error, e}
  end

  defp put_injection_pb_field("player_input", {dx, dy}, acc) do
    {:ok,
     struct!(acc,
       player_input: %Alchemy.Frame.Vec2f{x: Proto.pb_float(dx), y: Proto.pb_float(dy)}
     )}
  end

  defp put_injection_pb_field("player_snapshot", {hp, inv}, acc) do
    {:ok,
     struct!(acc,
       player_snapshot: %Alchemy.Frame.Vec2f{x: Proto.pb_float(hp), y: Proto.pb_float(inv)}
     )}
  end

  defp put_injection_pb_field("elapsed_seconds", v, acc) when is_number(v) do
    {:ok, struct!(acc, elapsed_seconds: Proto.pb_float(v))}
  end

  defp put_injection_pb_field("weapon_slots", slots, acc) when is_list(slots) do
    pb_slots =
      Enum.map(slots, fn {k, l, c, cs, pd} ->
        %Alchemy.Frame.WeaponSlot{
          kind_id: k,
          level: l,
          cooldown: Proto.pb_float(c),
          cooldown_sec: Proto.pb_float(cs),
          precomputed_damage: pd
        }
      end)

    {:ok, struct!(acc, weapon_slots: %Alchemy.Frame.WeaponSlotsList{slots: pb_slots})}
  end

  defp put_injection_pb_field("enemy_damage_this_frame", list, acc) when is_list(list) do
    pairs =
      Enum.map(list, fn {k, d} ->
        %Alchemy.Frame.EnemyDamagePair{kind_id: k, damage: Proto.pb_float(d)}
      end)

    {:ok,
     struct!(acc,
       enemy_damage_this_frame: %Alchemy.Frame.EnemyDamageList{pairs: pairs}
     )}
  end

  defp put_injection_pb_field("special_entity_snapshot", :none, acc) do
    {:ok,
     struct!(acc,
       special_entity_snapshot: %Alchemy.Frame.SpecialEntitySnapshot{
         state: {:none, %Alchemy.Frame.SpecialNone{}}
       }
     )}
  end

  defp put_injection_pb_field("special_entity_snapshot", {:alive, x, y, radius, damage, inv}, acc) do
    {:ok,
     struct!(acc,
       special_entity_snapshot: %Alchemy.Frame.SpecialEntitySnapshot{
         state:
           {:alive,
            %Alchemy.Frame.SpecialAlive{
              x: Proto.pb_float(x),
              y: Proto.pb_float(y),
              radius: Proto.pb_float(radius),
              damage: Proto.pb_float(damage),
              invincible: inv
            }}
       }
     )}
  end

  defp put_injection_pb_field(_key, _value, _acc), do: :skip
end
