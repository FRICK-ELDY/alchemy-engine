# DrawCommand タグ・フィールド仕様（SSoT）

> 作成日: 2026-03-07  
> 出典: [contents-defines-rust-executes.md](../plan/backlog/contents-defines-rust-executes.md) P2-1  
> 目的: Elixir 側を SSoT（Single Source of Truth）として DrawCommand のタグ・フィールドを文書化する
>
> **プロトコル仕様**: 本ドキュメントは [client-server-separation-procedure.md](../plan/completed/client-server-separation-procedure.md) フェーズ 1 フレームペイロードの SSoT として確定。Zenoh 経由のフレーム配信でも本仕様に従う。

---

## 1. 概要

**DrawCommand** は Elixir 側（contents の RenderComponent）が組み立て、`push_render_frame` NIF 経由で Rust に渡す描画命令リストの要素である。

- **定義**: Elixir（本ドキュメント + `Core.NifBridge.Behaviour` の `@type draw_command`）
- **実行**: Rust（`decode/draw_command.rs` が decode、`render` が描画）

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

## 4. Rust 側の受け手

`native/nif/src/nif/decode/draw_command.rs` が本仕様に従って Elixir タプルを Rust の `DrawCommand` enum に decode する。Rust は **定義の受け手** であり、タグやフィールドの追加・変更は本ドキュメントを SSoT として Elixir 側で決定する。

---

## 5. 関連ドキュメント

- [contents-defines-rust-executes.md](../plan/backlog/contents-defines-rust-executes.md) — 方針・リファクタリング計画
- [Rust: render](rust/desktop/render.md) — 描画パイプライン（render クレート）
- [Rust: nif](rust/nif.md) — NIF インターフェース
