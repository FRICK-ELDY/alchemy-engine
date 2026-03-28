# P5 転送効率化 — Protobuf 採用の実施プラン

> **ステータス**: 完了（`workspace/2_todo` → `workspace/7_done` に移動済み）。  
> 出典: [contents-defines-rust-executes.md](../1_backlog/contents-defines-rust-executes.md)（旧セクション 2・P5）  
> **Protobuf でエンコード（Elixir）・デコード（Rust）** する。`proto/render_frame.proto`、`Content.FrameEncoder`、`render` / `network` の `decode_pb_render_frame`、`set_frame_injection_binary`（`FrameInjection`）と同じスタック。

---

## 0. アーキテクチャ上の前提（採用しないもの）

- **NIF 層は描画を持たない。** 描画は `render` クレート（デスクトップクライアント等）と Zenoh 経路が担当する。
- **ローカル NIF 内の `RenderFrameBuffer` への書き込み・「NIF だけで描画」は復活させない**（過去設計の名残をプランから除外する）。

---

## 1. 目的

- Elixir（contents）から送出する **描画フレームのバイト列**を Protobuf に統一し、Rust 側のデコードコストとペイロードサイズを抑える（実際の描画パスは Zenoh / `render`）。
- **スキーマの単一情報源**を `.proto` に置き、Elixir・Rust で同じバイト列契約を共有する（ネットワーク経路の `Alchemy.Render.RenderFrame` と整合可能にする）。

---

## 2. スコープ（バックログ P5 との対応）

| ID | バックログの内容 | 本プランでの位置づけ |
|----|------------------|----------------------|
| **P5-1** | `set_frame_injection` バッチ API | 実装済み（バックログ記載どおり）。本プランでは触れない。 |
| **P5-2** | DrawCommand・メッシュ定義のバイナリ形式 | **Protobuf**（`render_frame.proto` 拡張・`FrameEncoder`・NIF 側デコード検証）。 |
| **P5-3** | `push_render_frame` の decode オーバーヘッド低減 | ターム逐次デコードから **バイナリ＋prost デコード**への移行、または既存バイナリ経路の最適化・計測。設計書 [p5-transfer-optimization-design.md](../../docs/architecture/p5-transfer-optimization-design.md) では一部「実装済み」とあるため、**現状コードと突合し、残差があれば追記タスク化**する。 |
| **P5-4** | `get_render_entities` の O(n) コピー削減 | `render_snapshot.rs` 等の **ダブルバッファ／事前構築**と突合。未達・回帰があれば継続タスクとする。 |

---

## 3. 現状のたたき台（実装前の確認）

実施前に次をリポジトリで確認し、重複実装を避ける。

1. **Elixir**: `apps/contents/lib/contents/frame_encoder.ex` — 既に `Alchemy.Render.RenderFrame.encode/1`（protobuf）。
2. **Rust（ネットワーク）**: `native/network/src/protobuf_render_frame.rs` — `decode_pb_render_frame`（prost）。
3. **NIF**: `set_frame_injection_binary` — `FrameInjection` の protobuf デコード（`native/nif/src/nif/protobuf_frame_injection.rs`）。
4. **設計ドキュメント**: [draw-command-spec.md](../../docs/architecture/draw-command-spec.md)・[zenoh-protocol-spec.md](../../docs/architecture/zenoh-protocol-spec.md) を参照する。

---

## 4. 実装フェーズ

### フェーズ A — スキーマと型の一本化（P5-2 の核）

1. **`proto/render_frame.proto`（SSoT）**
   - [draw-command-spec.md](../../docs/architecture/draw-command-spec.md) と差分があれば、フィールド番号・意味を揃える。
   - 新しい `DrawCommand` バリアントや `MeshDef` 拡張は **ここを先に**更新する。

2. **Elixir**
   - `protoc` 生成物（`apps/network/lib/network/proto/generated/render_frame.pb.ex` 等）を再生成。
   - `Content.FrameEncoder` のマッピングを `.proto` 変更に追随。ゴールデン／契約テストがあれば更新。

3. **Rust**
   - NIF クレートが `network` の `decode_pb_render_frame` を **直接依存できるか**検討。循環依存が出る場合は、**共通クレートへの抽出**（例: `render` または `shared` にデコード＋`RenderFrame` 変換を置く）を検討。
   - `native/nif` で prost 生成コードを共有する場合は、`build.rs` / `include!` パターンを `protobuf_frame_injection` と揃える。

### フェーズ B — NIF 経路のバイナリ化（P5-2 / P5-3）

1. **API 方針**
   - 既存のタームベース `push_render_frame` を残しつつ、**バイナリ専用 NIF**（例: `push_render_frame_binary`）を追加するか、既存関数に `binary | term` を判別させるかを決める。後方互換は [p5-transfer-optimization-design.md §2.4](../../docs/architecture/p5-transfer-optimization-design.md) の意図に沿う。

2. **デコード**
   - 受け取った `binary` を `decode_pb_render_frame` で `RenderFrame` に変換できることを確認する（契約検証・テスト用）。**NIF 内への描画バッファ書き込みは行わない**（§0）。

3. **計測**
   - フレームあたりのデコード時間・割り当てバイト数を、移行前後で比較（簡易ログまたはベンチ）。

### フェーズ C — `get_render_entities`（P5-4）

1. `native/nif/src/nif/read_nif.rs` の `get_render_entities` と `GameWorldInner` のスナップショット更新箇所を追い、**毎フレームの Vec 再構築・コピー**が残っていないか確認。
2. `render_snapshot.rs` のダブルバッファ設計が十分なら **回帰テスト・負荷確認のみ**。不足なら差分更新・プール等をバックログに切り出す。

---

## 5. テスト観点（Definition of Done）

- **契約**: Elixir で `FrameEncoder.encode_frame/5`（または相当）したバイト列を、Rust の `decode_pb_render_frame`（または NIF 内の同一ロジック）でデコードし、**意味的に同等**の `RenderFrame` になる（既存の `native/network/tests/render_frame_e2e_contract.rs` パターンを NIF でも再利用可能なら拡張）。
- **後方互換**: 移行期間中、ターム経路が残る場合は両方を短い期間テストする。
- **失敗時**: 不正バイナリは NIF で `:error` または明確な例外にし、ログに識別可能なメッセージを残す。

---

## 6. 工数目安（バックログの 5〜12 日の内訳イメージ）

| 項目 | 目安 |
|------|------|
| proto / Elixir / Rust 生成・依存整理 | 1.5〜3 日 |
| NIF バイナリ経路（デコード検証まで） | 2〜4 日 |
| 計測・微調整・P5-4 確認 | 1〜3 日 |
| ドキュメント追随（protobuf への統一） | 0.5〜1 日 |

---

## 7. 関連ドキュメント（作業時に参照）

- [contents-defines-rust-executes.md](../1_backlog/contents-defines-rust-executes.md)
- [p5-transfer-optimization-design.md](../../docs/architecture/p5-transfer-optimization-design.md)
- [draw-command-spec.md](../../docs/architecture/draw-command-spec.md)
- [contents-to-physics-bottlenecks.md](../../docs/architecture/contents-to-physics-bottlenecks.md) セクション 6
- [network-protocol-current.md](../../docs/architecture/network-protocol-current.md)（`push_render_frame` / binary の記述）

---

## 8. ステータス

本プランの実施は完了。フォローアップ（計測・P5-4 の継続確認など）は任意。
