# メッシュ定義一覧（P3-1）

> 作成日: 2026-03-07  
> 出典: [contents-defines-rust-executes.md](../plan/contents-defines-rust-executes.md) P3-1  
> 目的: 現行の 3D メッシュ（Box3D / GridPlane / Skybox）の頂点・インデックス定義を列挙する

---

## 1. 共通頂点型

`MeshVertex`（`native/render/src/renderer/pipeline_3d.rs`）:

| 属性 | 型 | 説明 |
|:---|:---|:---|
| position | [f32; 3] | ワールド座標 (x, y, z) |
| color | [f32; 4] | RGBA (0.0〜1.0) |

---

## 2. Box3D（軸平行ボックス）

### 2.1 ジオメトリ

- **頂点数**: 8
- **インデックス数**: 36（12 三角形 × 3 頂点）
- **生成**: `box_mesh(cx, cy, cz, hw, hh, hd, color)` で中心 `(cx,cy,cz)`、半幅 `(hw,hh,hd)`、単色 `color` を適用

### 2.2 頂点（単位ボックス中心原点、-0.5〜0.5 を DrawCommand の半サイズでスケール・移動）

| idx | position (x0,x1,y0,y1,z0,z1) | 備考 |
|:---:|:---|:---|
| 0 | (x0, y0, z0) | 前面左下 |
| 1 | (x1, y0, z0) | 前面右下 |
| 2 | (x1, y1, z0) | 前面右上 |
| 3 | (x0, y1, z0) | 前面左上 |
| 4 | (x0, y0, z1) | 背面左下 |
| 5 | (x1, y0, z1) | 背面右下 |
| 6 | (x1, y1, z1) | 背面右上 |
| 7 | (x0, y1, z1) | 背面左上 |

※ `x0 = cx - hw`, `x1 = cx + hw` 等

### 2.3 インデックス（各面 2 三角形）

```
0,1,2, 0,2,3   # -Z 面（前面）
5,4,7, 5,7,6   # +Z 面（背面）
4,0,3, 4,3,7   # -X 面（左）
1,5,6, 1,6,2   # +X 面（右）
3,2,6, 3,6,7   # +Y 面（上）
4,5,1, 4,1,0   # -Y 面（下）
```

### 2.4 単位ボックス（中心原点、辺長 1）の頂点座標

```
v0: (-0.5, -0.5, -0.5)
v1: ( 0.5, -0.5, -0.5)
v2: ( 0.5,  0.5, -0.5)
v3: (-0.5,  0.5, -0.5)
v4: (-0.5, -0.5,  0.5)
v5: ( 0.5, -0.5,  0.5)
v6: ( 0.5,  0.5,  0.5)
v7: (-0.5,  0.5,  0.5)
```

---

## 3. GridPlane（XZ 平面グリッド）

### 3.1 ジオメトリ

- **頂点数**: 可変 `(divisions + 1) × 4`（最大 404、divisions=100 時）
- **インデックス**: なし（LineList トポロジ）
- **生成**: `grid_lines(size, divisions, color)` で `[-half, half]` の XZ 平面上に等間隔線を生成

### 3.2 頂点生成アルゴリズム

```text
half = size / 2
step = size / divisions
n = divisions + 1

for i in 0..n:
  t = -half + i * step
  # Z 方向線（X を -half から half へ）
  push position: [-half, 0, t], color
  push position: [ half, 0, t], color
  # X 方向線（Z を -half から half へ）
  push position: [t, 0, -half], color
  push position: [t, 0,  half], color
```

### 3.3 パラメータ（DrawCommand から）

| パラメータ | 型 | 説明 |
|:---|:---|:---|
| size | f32 | 一辺のサイズ |
| divisions | u32 | 分割数 |
| color | [f32; 4] | RGBA |

---

## 4. Skybox（クリップ空間フルスクリーン矩形）

### 4.1 ジオメトリ

- **頂点数**: 4
- **インデックス数**: 6（2 三角形）
- **座標系**: クリップ空間（MVP 変換なし、`vs_sky` エントリポイント使用）
- **深度**: z = 0.999（深度テストなしパスで最背面）

### 4.2 頂点

| idx | position (x, y, z) | color |
|:---:|:---|:---|
| 0 | (-1.0, 1.0, 0.999) | top_color |
| 1 | (1.0, 1.0, 0.999) | top_color |
| 2 | (1.0, -1.0, 0.999) | bottom_color |
| 3 | (-1.0, -1.0, 0.999) | bottom_color |

### 4.3 インデックス

```
0, 1, 2, 0, 2, 3
```

### 4.4 パラメータ（DrawCommand から）

| パラメータ | 型 | 説明 |
|:---|:---|:---|
| top_color | [f32; 4] | 上空色 RGBA |
| bottom_color | [f32; 4] | 地平色 RGBA |

---

## 5. 関連ファイル

| ファイル | 役割 |
|:---|:---|
| `native/render/src/lib.rs` | MeshVertex / MeshDef 定義 |
| `native/render/src/renderer/pipeline_3d.rs` | メッシュ生成・描画（P3 以降 Elixir 定義を優先、未登録時フォールバック） |
| `docs/architecture/draw-command-spec.md` | DrawCommand タグ・フィールド仕様 |
| `docs/plan/contents-defines-rust-executes.md` | P3 メッシュ Elixir 移行計画 |
