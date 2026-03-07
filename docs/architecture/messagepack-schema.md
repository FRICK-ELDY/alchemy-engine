# MessagePack スキーマ — push_render_frame バイナリ形式

> 作成日: 2026-03-07  
> 出典: [p5-2-messagepack-execution-plan.md](../task/p5-2-messagepack-execution-plan.md), [draw-command-spec.md](draw-command-spec.md)

---

## 1. 概要

P5-2 で `push_render_frame_binary` NIF が受け取るバイナリの MessagePack スキーマを定義する。
Elixir 側（msgpax）と Rust 側（rmp-serde）で同一の構造を扱う。

## 2. トップレベル構造

1フレーム分のバイナリは次の map 構造を pack したもの:

```elixir
%{
  "commands" => [draw_command, ...],
  "camera" => camera_params_map,
  "ui" => ui_canvas_map,
  "mesh_definitions" => [mesh_def_map, ...]
}
```

- キーは文字列（MessagePack 仕様）
- `cursor_grab` は NIF の別引数として渡す（タプル版と同様）

## 3. DrawCommand ↔ MessagePack 型マッピング

| Elixir タプル | MessagePack map |
|:---|:---|
| `{:player_sprite, x, y, frame}` | `%{"t" => "player_sprite", "x" => x, "y" => y, "frame" => frame}` |
| `{:sprite_raw, x, y, w, h, {{uv_ox, uv_oy}, {uv_sx, uv_sy}, {r,g,b,a}}}` | `%{"t" => "sprite_raw", "x"=>x, "y"=>y, "width"=>w, "height"=>h, "uv_offset"=>[ox,oy], "uv_size"=>[sx,sy], "color_tint"=>[r,g,b,a]}` |
| `{:particle, x, y, r, g, b, {alpha, size}}` | `%{"t" => "particle", "x"=>x, "y"=>y, "r"=>r, "g"=>g, "b"=>b, "alpha"=>alpha, "size"=>size}` |
| `{:item, x, y, kind}` | `%{"t" => "item", "x"=>x, "y"=>y, "kind"=>kind}` |
| `{:obstacle, x, y, radius, kind}` | `%{"t" => "obstacle", "x"=>x, "y"=>y, "radius"=>radius, "kind"=>kind}` |
| `{:box_3d, x, y, z, hw, hh, {hd, r,g,b,a}}` | `%{"t" => "box_3d", "x"=>x, "y"=>y, "z"=>z, "half_w"=>hw, "half_h"=>hh, "half_d"=>hd, "color"=>[r,g,b,a]}` |
| `{:grid_plane, size, div, {r,g,b,a}}` | `%{"t" => "grid_plane", "size"=>size, "divisions"=>div, "color"=>[r,g,b,a]}` |
| `{:grid_plane_verts, [vertices]}` | `%{"t" => "grid_plane_verts", "vertices"=>[...]}` |
| `{:skybox, {tr,tg,tb,ta}, {br,bg,bb,ba}}` | `%{"t" => "skybox", "top_color"=>[tr,tg,tb,ta], "bottom_color"=>[br,bg,bb,ba]}` |

- 数値は f64 として pack（Rust は f32 に変換）
- 頂点: `[[x,y,z],[r,g,b,a]]` の配列

## 4. CameraParams ↔ MessagePack

| Elixir | MessagePack |
|:---|:---|
| `{:camera_2d, offset_x, offset_y}` | `%{"t" => "camera_2d", "offset_x" => x, "offset_y" => y}` |
| `{:camera_3d, {ex,ey,ez}, {tx,ty,tz}, {ux,uy,uz}, {fov,near,far}}` | `%{"t" => "camera_3d", "eye"=>[ex,ey,ez], "target"=>[tx,ty,tz], "up"=>[ux,uy,uz], "fov_deg"=>fov, "near"=>near, "far"=>far}` |

## 5. UiCanvas / UiNode / UiComponent ↔ MessagePack

- **UiCanvas**: `%{"nodes" => [node, ...]}`
- **UiNode**: `%{"rect" => rect_map, "component" => component_map, "children" => [node, ...]}`
- **UiRect**: `%{"anchor" => "top_left"|"center"|..., "offset" => [x,y], "size" => :wrap | [w,h]}`
- **UiSize**: `"wrap"` または `[w, h]` (Fixed)

### UiComponent タグ

| タグ | 追加フィールド |
|:---|:---|
| vertical_layout | spacing, padding: [l,t,r,b] |
| horizontal_layout | spacing, padding |
| text | text, color, size, bold |
| rect | color, corner_radius, border: nil \| [color, width] |
| progress_bar | value, max, width, height, fg_color_high, fg_color_mid, fg_color_low, bg_color, corner_radius |
| button | label, action, color, min_width, min_height |
| separator | (タグのみ) |
| spacing | amount |
| world_text | world_x, world_y, world_z, text, color, lifetime, max_lifetime |
| screen_flash | color |

## 6. MeshDef ↔ MessagePack

```elixir
%{
  "name" => "unit_box",
  "vertices" => [[[x,y,z],[r,g,b,a]], ...],
  "indices" => [0, 1, 2, ...]
}
```

## 7. スキーマ変更時の手順

1. 本ドキュメントの型マッピングを更新
2. Elixir: `Content.MessagePackEncoder` を更新
3. Rust: `nif/decode/msgpack.rs` の Deserialize 構造体を更新
4. 両方のテストを実行して整合性を確認
