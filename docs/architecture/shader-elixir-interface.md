# シェーダー Elixir インターフェース（P4-2, P4-3）

> 作成日: 2026-03-07  
> 出典: [contents-defines-rust-executes.md](../plan/backlog/contents-defines-rust-executes.md) P4-2, P4-3  
> 目的: Elixir から WGSL を渡すインターフェースとコンテンツアセット構成を定義する

---

## 1. 概要

シェーダー（sprite.wgsl, mesh.wgsl）を Elixir 定義から取得する方式は **起動時ロード** とする。

- **アセットパス方式**: コンテンツの `assets_path/0` から導出したディレクトリ配下の `shaders/*.wgsl` を Rust がファイルから読み込む
- **フォールバック**: ファイルが存在しない場合は `include_str!` の埋め込み WGSL を使用（P4-5）
- **Elixir API 変更なし**: 既存の `start_render_thread(world, render_buf, pid, title, atlas_path)` のまま。atlas_path からシェーダーディレクトリを導出する

---

## 2. アセットディレクトリ構成（P4-3）

### 2.1 パス解決

atlas_path は `resolve_atlas_path(content)` で以下のように解決される:

```
assets/{game_assets_id}/sprites/atlas.png
```

シェーダーディレクトリは **atlas_path の 2 階層上 + "shaders"** で導出:

```
assets/{game_assets_id}/shaders/
```

例:
- atlas_path: `assets/vampire_survivor/sprites/atlas.png`
- shader_dir: `assets/vampire_survivor/shaders/`

### 2.2 期待するファイル名

| ファイル | 用途 | 契約 |
|:---|:---|:---|
| sprite.wgsl | 2D スプライトパス | [desktop/render.md](rust/desktop/render.md) の sprite.wgsl 仕様に準拠 |
| mesh.wgsl | 3D メッシュ・グリッド・スカイボックス | [desktop/render.md](rust/desktop/render.md) の mesh.wgsl 仕様に準拠 |

### 2.3 フォールバック順序

1. `{shader_dir}/sprite.wgsl` が存在 → 使用
2. 存在しない → 共有フォールバック `assets/shaders/sprite.wgsl` を試行
3. それも存在しない → `include_str!` 埋め込み

※ mesh.wgsl も同様

### 2.4 ログ仕様

ファイル未存在時は `log::debug!` でデバッグログを出力する。`load_atlas_png` と異なり `log::warn!` は出さない（フォールバックが正常系のため）。

---

## 3. Rust 側の実装（P4-4）

### 3.1 RendererInit の拡張

```rust
pub struct RendererInit {
    pub atlas_png: Vec<u8>,
    /// P4: コンテンツ定義の WGSL。None の場合は include_str! フォールバック
    pub sprite_wgsl: Option<String>,
    pub mesh_wgsl: Option<String>,
}
```

### 3.2 ロード処理（render_bridge）

1. atlas_path から shader_dir を導出
2. `load_wgsl(shader_dir, "sprite.wgsl")` → Option<String>
3. `load_wgsl(shader_dir, "mesh.wgsl")` → Option<String>
4. ファイル未存在時は None（Rust 側で include_str! を使用）

### 3.3 Renderer / Pipeline3D

- `Renderer::new(window, init: &RendererInit)` に変更
- sprite_wgsl を init から取得。None なら `include_str!("shaders/sprite.wgsl")`
- `Pipeline3D::new(..., mesh_wgsl: Option<&str>)` を渡す。None なら include_str!

---

## 4. コンテンツ側の利用方法

### 4.1 カスタムシェーダーを使用する場合

コンテンツの `assets_path/0` が `"my_game"` を返す場合:

```
assets/
  my_game/
    sprites/
      atlas.png
    shaders/           # 追加
      sprite.wgsl      # 契約に準拠した WGSL
      mesh.wgsl        # 同上
```

ファイルを配置するだけで、起動時に自動的にロードされる。

### 4.2 デフォルトシェーダーを使用する場合

`shaders/` ディレクトリを用意しない、またはファイルを配置しない。Rust の埋め込み WGSL が使用される。

---

## 5. include_str! フォールバック（P4-5）

**採用方針**: フォールバックとして残す。

- ファイルが存在しない環境（CI、最小構成）でも動作保証
- headless モードは従来通り `include_str!` のまま（render_bridge を経由しないため）
- 将来的に動的シェーダー注入（push_render_frame 経由）を追加する場合は、その時点で拡張

---

## 6. 関連ドキュメント

- [contents-defines-rust-executes.md](../plan/backlog/contents-defines-rust-executes.md) — P4 計画
- [desktop/render.md](rust/desktop/render.md) — シェーダー契約（uniform・バインド・頂点レイアウト）
- [asset-storage-classification.md](../plan/backlog/asset-storage-classification.md) — アセット配置の分類
