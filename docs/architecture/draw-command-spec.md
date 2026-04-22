# DrawCommand タグ・フィールド仕様（SSoT）

> 作成日: 2026-03-07  
> 出典: [contents-defines-rust-executes.md](../plan/backlog/contents-defines-rust-executes.md) P2-1  
> 目的: DrawCommand のタグ・フィールド（Elixir タプル形）を文書化する。**ワイヤ契約の SSoT** は [alchemy-protocol の `render_frame.proto`（タグ `v0.1.1`）](https://github.com/FRICK-ELDY/alchemy-protocol/blob/v0.1.1/proto/render_frame.proto)（本リポでは submodule **`3rdparty/alchemy-protocol/proto/`** 配下。ドメインの SSoT は Elixir。二層の整理は [overview.md](./overview.md#設計思想)）。本ドキュメントは人間可読な対応表と `Content.FrameEncoder` の入力形式を示す。
>
> **プロトコル仕様**: ワイヤ上のバイト列は **protobuf**（上記 `render_frame.proto` と `render_frame/*.proto`）。本ドキュメントは同じ意味論の **Elixir タプル入力**を述べる。Zenoh 経由のフレーム配信でも同じ契約を用いる（歴史的出典: [client-server-separation-procedure.md](../plan/completed/client-server-separation-procedure.md) フェーズ 1）。

---

## 1. 概要

**DrawCommand** は Elixir 側（contents の Render コンポーネント等）が **タプル**として組み立てる描画命令リストの要素である。**サーバーからクライアントへは NIF を経由しない。** `Content.FrameEncoder.encode_frame/5` が **`Alchemy.Render.RenderFrame` の protobuf** に変換し、Zenoh 等で配信する。クライアント（Rust）は `render_frame_proto::decode_pb_render_frame` でデコードし、`render` が描画する。

- **ワイヤ契約（SSoT）**: [alchemy-protocol `render_frame.proto`（`v0.1.1`）](https://github.com/FRICK-ELDY/alchemy-protocol/blob/v0.1.1/proto/render_frame.proto)（protobuf）。Elixir 側の対応実装は `Content.FrameEncoder`（`command_to_pb/1` 等）。
- **実行**: クライアント Rust（`rust/client/render_frame_proto` → `rust/client/shared` の `DrawCommand`、`rust/client/render`）。`Core.NifBridge` は **`run_formula_bytecode/3` のみ**であり、DrawCommand 型や描画 NIF は持たない。

---

## 2. タグ一覧

| タグ | 用途 | 2D/3D |
|:---|:---|:---:|
| `:player_sprite` | プレイヤースプライト（補間対象） | 2D |
| `:sprite_raw` | 汎用スプライト（UV・サイズ直接指定） | 2D |
| `:particle` | パーティクル | 2D |
| `:item` | アイテム | 2D |
| `:obstacle` | 障害物 | 2D |
| `:box_3d` | 3D ボックス | 3D |
| `:grid_plane` | XZ 平面グリッド（地面等、パラメータで Rust が生成） | 3D |
| `:grid_plane_verts` | XZ 平面グリッド（P3: Elixir が頂点を生成） | 3D |
| `:skybox` | 空色グラデーション背景 | 3D |

**注**: `:sprite` は decode には未対応。`:sprite_raw` を推奨。`:player_sprite` / `:item` はレガシーで SpriteRaw で代用可能。

---

## 3. フィールド仕様（Elixir タプル形式）

### 3.1 player_sprite

```elixir
{:player_sprite, x, y, frame}
```

| フィールド | 型 | 説明 |
|:---|:---|:---|
| x | float | ワールド X 座標 |
| y | float | ワールド Y 座標 |
| frame | non_neg_integer | アニメーションフレーム（u8 に変換） |

---

### 3.2 sprite_raw

```elixir
{:sprite_raw, x, y, width, height, {{uv_ox, uv_oy}, {uv_sx, uv_sy}, {r, g, b, a}}}
```

| フィールド | 型 | 説明 |
|:---|:---|:---|
| x, y | float | ワールド座標 |
| width, height | float | 表示サイズ（px） |
| uv_ox, uv_oy | float | UV オフセット（0.0〜1.0） |
| uv_sx, uv_sy | float | UV サイズ（0.0〜1.0） |
| r, g, b, a | float | 乗算カラー（0.0〜1.0） |

---

### 3.3 particle

```elixir
{:particle, x, y, r, g, b, {alpha, size}}
```

| フィールド | 型 | 説明 |
|:---|:---|:---|
| x, y | float | ワールド座標 |
| r, g, b | float | 色（0.0〜1.0） |
| alpha | float | 透明度 |
| size | float | パーティクルサイズ |

---

### 3.4 item

```elixir
{:item, x, y, kind}
```

| フィールド | 型 | 説明 |
|:---|:---|:---|
| x, y | float | ワールド座標 |
| kind | non_neg_integer | アイテム種別 ID（u8 に変換） |

---

### 3.5 obstacle

```elixir
{:obstacle, x, y, radius, kind}
```

| フィールド | 型 | 説明 |
|:---|:---|:---|
| x, y | float | 中心座標 |
| radius | float | 半径 |
| kind | non_neg_integer | 障害物種別 ID（u8 に変換） |

---

### 3.6 box_3d

```elixir
{:box_3d, x, y, z, half_w, half_h, {half_d, r, g, b, a}}
```

| フィールド | 型 | 説明 |
|:---|:---|:---|
| x, y, z | float | 中心座標 |
| half_w, half_h, half_d | float | 半幅・半高さ・半奥行き |
| r, g, b, a | float | 色（0.0〜1.0） |

---

### 3.7 grid_plane

```elixir
{:grid_plane, size, divisions, {r, g, b, a}}
```

| フィールド | 型 | 説明 |
|:---|:---|:---|
| size | float | 一辺のサイズ |
| divisions | non_neg_integer | 分割数 |
| r, g, b, a | float | グリッド線の色 |

### 3.7.1 grid_plane_verts（P3）

```elixir
{:grid_plane_verts, [{{x, y, z}, {r, g, b, a}}, ...]}
```

| フィールド | 型 | 説明 |
|:---|:---|:---|
| vertices | list | Elixir 定義の頂点リスト。`Contents.Components.Category.Procedural.Meshes.Grid.grid_plane/1` から取得可 |

---

### 3.8 skybox

```elixir
{:skybox, {top_r, top_g, top_b, top_a}, {bot_r, bot_g, bot_b, bot_a}}
```

| フィールド | 型 | 説明 |
|:---|:---|:---|
| top_* | float | 上空色（RGBA） |
| bot_* | float | 地平色（RGBA） |

---

## 4. Rust 側の受け手（クライアント）

ワイヤ上は **protobuf のみ**。`rust/client/render_frame_proto` の `decode_pb_render_frame/1` が `prost` で `Alchemy.Render.RenderFrame` をデコードし、`shared::render_frame::DrawCommand` に変換する。タグ・フィールドの追加・変更は **alchemy-protocol の `render_frame.proto` / `render_frame/*.proto`（`v0.1.1` 例: [render_frame.proto](https://github.com/FRICK-ELDY/alchemy-protocol/blob/v0.1.1/proto/render_frame.proto)）と `Content.FrameEncoder` を先に更新**し、続いて Rust のデコードを追随する。

---

## 5. 関連ドキュメント

- [contents-defines-rust-executes.md](../plan/backlog/contents-defines-rust-executes.md) — 方針・リファクタリング計画
- [Rust: render](rust/desktop/render.md) — 描画パイプライン（render クレート）
- [Rust: nif](rust/nif.md) — Formula NIF（`run_formula_bytecode`）のみ
- [`rust/client/render_frame_proto`](../../rust/client/render_frame_proto) — protobuf → `RenderFrame` デコード
