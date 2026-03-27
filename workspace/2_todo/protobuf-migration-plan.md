# Erlang term 廃止・protobuf 移行 実施計画書

> 作成日: 2026-03-27  
> 目的: Zenoh 通信で使用中の Erlang term（ETF）を段階的に廃止し、protobuf に統一する。  
> 対象: フレーム配信、入力（movement/action）、frame injection、client_info

---

## 1. 背景

- 現状は `Content.FrameEncoder` と `native/network` の `bert_decode` を中心に ETF を利用している
- ETF は Elixir 内では高速だが、長期的なスキーマ進化と言語間契約管理を protobuf に統一したい
- 既存の MessagePack レガシーが一部残存しているため、移行時に併せて整理する

---

## 2. ゴール / 非ゴール

### 2.1 ゴール

1. Zenoh 経由の主要ペイロードを protobuf 化する
   - server -> client: render frame
   - client -> server: movement / action
   - contents -> nif: frame injection
   - client_info
2. ETF デコード/エンコード経路（`bert_*`）を廃止する
3. スキーマの単一ソース（`.proto`）を確立する
4. ドキュメントを protobuf 前提に更新する

### 2.2 非ゴール

- 直列化方式以外のレンダリング仕様変更
- Zenoh トポロジやルータ構成の最適化
- UI/ゲーム仕様の変更

---

## 3. 対象範囲

## 3.1 変更対象（主要）

- `apps/contents/lib/contents/frame_encoder.ex`
- `apps/contents/lib/events/game.ex`
- `native/network/src/bert_decode.rs`
- `native/network/src/bert_encode.rs`
- `native/network/src/network_render_bridge.rs`
- `native/nif/src/nif/decode/bert_injection.rs`
- `native/nif/src/nif/world_nif.rs`
- `docs/architecture/erlang-term-schema.md`
- `docs/policy-as-code/why_adopted/zenoh-frame-serialization.md`
- `workspace/1_backlog/env-and-serialization-migration-plan.md`

### 3.2 新規追加想定

- `proto/render_frame.proto`
- `proto/input_events.proto`
- `proto/frame_injection.proto`
- `proto/client_info.proto`
- 言語別生成コード（Elixir / Rust）を配置するディレクトリ

---

## 4. 移行方針

- **段階移行（デュアルデコード期間あり）**を採用する
- 送信側を protobuf 化する前に、受信側で protobuf を受け取れる状態を作る
- フェーズごとに ETF フォールバックを残し、最終フェーズで除去する
- 本番切替は「片方向ずつ」行い、障害時は即時ロールバック可能にする

---

## 5. 実施フェーズ

## フェーズ P0: スキーマ設計とコード生成基盤

### 作業

- `.proto` の初版を定義
  - RenderFrame（commands/camera/ui/mesh_definitions/cursor_grab）
  - Movement / Action
  - FrameInjection
  - ClientInfo
- フィールド番号ポリシー（予約、削除時の扱い）を決める
- Elixir / Rust のコード生成手順を確立する（ビルド再現可能化）

### 完了条件

- `.proto` だけで主要メッセージの契約を説明できる
- 両言語で同一サンプルを encode/decode できる

---

## フェーズ P1: クライアント受信（server -> client）protobuf 対応

### 作業

- Rust 側に protobuf `decode_render_frame` を追加（ETF と並存）
- `network_render_bridge` を「protobuf 優先、ETF フォールバック」に変更
- Elixir 側で protobuf frame 生成パスを実装（旧 ETF も維持）

### 完了条件

- protobuf frame で描画が成立
- ETF / protobuf どちらのフレームもクライアントで受信可能

---

## フェーズ P2: 入力系（client -> server）protobuf 化

### 作業

- Rust 側 movement/action 送信を protobuf に変更
- Elixir 側受信デコードを protobuf 対応（ETF フォールバック維持）
- キー、トピック、イベント処理の整合性確認

### 完了条件

- movement/action が protobuf のみで往復成立
- ETF 入力経路を使わなくてもゲーム進行に問題なし

---

## フェーズ P3: frame injection（contents -> nif）protobuf 化

### 作業

- `encode_injection_map` を protobuf 実装へ差し替え（または新規関数追加）
- NIF 側に protobuf injection デコーダを追加
- `world_nif` で protobuf 優先経路へ切替（ETF フォールバック維持）

### 完了条件

- injection が protobuf 経路で適用される
- 既存の注入テスト観点を維持

---

## フェーズ P4: client_info protobuf 化 + レガシー整理

### 作業

- `client_info` の MessagePack 経路を protobuf に置換
- MessagePack レガシー記述を整理し、移行完了状態へ更新
- 依存クレート（msgpax/rmp-serde/eetf）の利用箇所を棚卸し

### 完了条件

- client_info が protobuf で送受信される
- レガシー直列化経路の残存が明示化される

---

## フェーズ P5: ETF 経路削除・ドキュメント更新

### 作業

- `bert_decode` / `bert_encode` / `bert_injection` を削除または非公開化
- ETF 前提のポリシー文書を protobuf 前提に置換
- 実施計画・完了記録を更新

### 完了条件

- 主要通信で ETF が使われていない
- ドキュメントが現実装と一致している

---

## 6. テスト計画

### 6.1 契約テスト

- 同一 fixture を Elixir encode -> Rust decode、Rust encode -> Elixir decode で検証
- optional / repeated / oneof 相当の後方互換ケースを追加

### 6.2 統合テスト

- ローカル起動で frame 受信描画、input 送信、injection 適用を確認
- ETF フォールバック期間は「protobuf優先で成功、ETFでも成功」を両方確認

### 6.3 性能確認（最低限）

- encode/decode の p50/p95/p99 を ETF 比較で取得
- payload サイズ比較（平均/最大）
- フレーム欠損率・入力反映遅延の比較

---

## 7. リスクと対策

| リスク | 内容 | 対策 |
|:---|:---|:---|
| スキーマ不整合 | Elixir/Rust で型差異が出る | fixture 契約テストを CI 化 |
| 可変長データ不備 | commands/ui で decode 失敗 | 段階導入 + フォールバック維持 |
| 互換破壊 | フィールド変更で古いクライアントが壊れる | field 番号予約ポリシーを固定 |
| 移行長期化 | ETF/Protobuf 二重保守が増える | フェーズ期限と削除条件を明確化 |

---

## 8. ロールバック方針

- 各フェーズで ETF 受信経路は残し、問題発生時は publish 側のみ旧方式へ戻す
- 切替フラグ（環境変数または設定）で protobuf/ETF の優先順位を変更できるようにする
- ロールバック時はスキーマ変更を凍結し、原因分析後に再リリースする

---

## 9. 実施順序（推奨）

1. P0: `.proto` と生成基盤を固定
2. P1: server -> client（最も影響が大きい経路）を先行
3. P2: client -> server 入力系
4. P3: frame injection
5. P4: client_info / レガシー整理
6. P5: ETF 削除と文書確定

---

## 10. 完了判定

- [x] render frame / movement / action / frame injection / client_info が protobuf で稼働（主要経路）
- [ ] ETF 依存コードが主要経路から削除済み（デュアルデコード期間中はフォールバックとして維持）
- [ ] 契約テストと統合テストが通過（ネットワーク protobuf の単体テストは `apps/network/test/network/proto/render_frame_oneof_test.exs`）
- [x] ドキュメントと実装が一致（`docs/architecture/erlang-term-schema.md` を protobuf 前提に更新済み）

---

## 11. 実施状況メモ（2026-03）

- Elixir `Network.Proto` は手書き（`protobuf` 0.16）。oneof は `oneof :name, N` と各 `field ..., oneof: N` が必須。
- Rust / `proto/*.proto` / Elixir の三箇所をスキーマ変更時に同期すること。
- `config/config.exs` の `:server, :current` は protobuf 移行と無関係。コンテンツ切替は別 PR で扱う。

