# NetworkRenderBridge の RenderFrame 共有最適化 検討

> 作成日: 2026-03-21  
> 目的: フレーム欠損時のフリッカー防止で導入した `last_frame` 保持において、`RenderFrame` の `.clone()` によるパフォーマンス負荷を `Arc<RenderFrame>` 等で軽減する検討を記録する。

---

## 背景

`native/network/src/network_render_bridge.rs` で、受信フレーム欠損時に前回の描画を保持してフリッカーを防ぐため、`last_frame` フィールドを導入した。

この実装では次が発生している：

- **新フレーム受信時**: 取得した `RenderFrame` を `.clone()` して `last_frame` に格納し、元を返却
- **フレーム欠損時**: `last_frame` の参照を `.clone()` して返却

`RenderFrame` は `commands`（`Vec<DrawCommand>`）・`ui`（`UiCanvas`）・`mesh_definitions`（`Vec<MeshDef>`）などを含む大きな構造体であり、ディープコピーは負荷が高い。

---

## 現状の問題

| 状況 | クローン発生 |
|:---|:---|
| 新フレーム受信時 | 1 回（`last_frame` への格納用） |
| フレーム欠損時 | 1 回（`next_frame` の返却用） |
| 60fps 描画ループ | 毎フレーム 1〜2 回のディープコピーが発生し得る |

ネットワーク遅延時には同一フレームのクローンが連続する可能性があり、パフォーマンス負荷になる懸念がある。

---

## 検討方針: Arc による共有

### 案: `Arc<RenderFrame>` で共有

- `frame_buffer` と `last_frame` の型を `Option<Arc<RenderFrame>>` に変更
- 新フレーム受信時: デコード後に `Arc::new(frame)` でラップし、`frame_buffer` と `last_frame` の両方で同一の `Arc` を参照
- フレーム欠損時: `last_frame` の `Arc` をそのまま返す（または `Arc::clone` のみ、参照カウント増加のみでコピー負荷なし）
- `next_frame` の戻り値: `Arc<RenderFrame>` を返す

### トレイト定義への影響

`RenderBridge` トレイトは現在 `fn next_frame(&self) -> RenderFrame` を要求している。

| 選択肢 | 内容 |
|:---|:---|
| A. トレイト変更 | `fn next_frame(&self) -> Arc<RenderFrame>` に変更。全実装（ローカル・ネットワーク）を更新 |
| B. トレイトは据え置き | `next_frame` 内で `Arc` から参照を取り、必要に応じて `.clone()`。ただしフレーム欠損時のみ `Arc::clone` を返すメリットは薄い |
| C. 新トレイト追加 | `fn next_frame_arc(&self) -> Option<Arc<RenderFrame>>` 等のオーバーロード。複雑化の可能性 |

トレイト定義の変更が必要となる場合は、`RenderBridge` を実装する全クレート（`app`・`native/window` 経由のローカル描画など）への影響を洗い出す必要がある。

---

## 検討すべき事項

1. **他実装の確認**  
   `RenderBridge` を実装している全箇所で `Arc<RenderFrame>` を扱えるか、または `RenderFrame` を要求する呼び出し元がクローンを許容するか

2. **デコード後のラップ**  
   `msgpack_decode::decode_render_frame` の戻り値 `RenderFrame` をデコード直後に `Arc::new()` でラップする位置（subscriber コールバック内か、`next_frame` 内か）

3. **計測**  
   現状の `.clone()` による負荷が実際にボトルネックとなっているか、プロファイリングまたはフレーム時間計測で確認する

4. **段階的導入**  
   トレイト変更の影響が大きい場合、`NetworkRenderBridge` 内で `Arc` を利用しつつ、`next_frame` の戻り値は従来どおり `RenderFrame`（`Arc` からの `.as_ref().clone()`）とし、呼び出し側の変更を最小限に抑える折衷案

---

## 関連ファイル

| ファイル | 役割 |
|:---|:---|
| `native/network/src/network_render_bridge.rs` | `last_frame` 保持・`next_frame` 実装 |
| `native/render/src/window.rs` | `RenderBridge` トレイト定義 |
| `native/render/src/lib.rs` | `RenderFrame` 型定義 |
| `native/app/` | `RenderBridge` の呼び出し元（desktop クライアント） |

---

## ステータス

- [ ] プロファイリングで clone 負荷の実測
- [ ] `RenderBridge` 実装・呼び出し箇所の網羅的洗い出し
- [ ] `Arc<RenderFrame>` 導入の設計決定
- [ ] 実装
