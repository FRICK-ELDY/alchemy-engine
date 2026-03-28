# 環境変数リネーム・Erlang term 直列化 実施完了記録

> 元計画: [env-and-serialization-migration-plan.md](../1_backlog/env-and-serialization-migration-plan.md)  
> 実施完了: 2026-03 頃  
> 本ドキュメント: 実施済みの §1, §2（フェーズ A/B/C）を記録。
>
> **追記（2026-03-28）**: 以降の開発では Zenoh フレーム・入力・injection のワイヤ形式は **protobuf** に統一済み（[protobuf-migration.md](../../docs/architecture/protobuf-migration.md)）。以下 §2 は当時の作業ログであり、現行実装の唯一の真実ではない。

---

## 1. 環境変数リネーム ✅

### 1.1 背景

プロジェクトがゲームに限定されなくなったため、`GAME_` プレフィックスを削除する。

### 1.2 変更一覧

| 旧名称 | 新名称 | 説明 |
|:---|:---|:---|
| `GAME_ASSETS_PATH` | `ASSETS_PATH` | アセットルートディレクトリ |
| `GAME_ASSETS_ID` | `ASSETS_ID` | コンテンツ別サブディレクトリ名（例: `vampire_survivor`） |

### 1.3 実施内容

- `native/audio/src/asset/mod.rs`: `ASSETS_PATH`, `ASSETS_ID` を優先し、後方互換で `GAME_ASSETS_PATH`, `GAME_ASSETS_ID` へフォールバック
- `apps/server/lib/server/application.ex`: `put_env("ASSETS_ID", ...)`
- `native/app/src/main.rs`: `set_var("ASSETS_PATH", ...)`
- 関連ドキュメントの更新

---

## 2. MessagePack → Erlang term 直列化移行 ✅（歴史的。現行ワイヤは protobuf）

### 2.1 フェーズ A: フレーム配信・受信の Erlang term 化

| ステップ | 実施内容 |
|:---|:---|
| A1 | `Content.FrameEncoder` を新規作成。`term_to_binary` でフレームをエンコード |
| A2 | 各 RenderComponent が `FrameEncoder.encode_frame` を使用 |
| A3 | `native/network` に bert（eetf）を導入 |
| A4 | `bert_decode` モジュールで `decode_render_frame` を実装 |
| A5 | `network_render_bridge.rs` が `bert_decode::decode_render_frame` を呼び出し |
| A6 | `docs/architecture/erlang-term-schema.md` を新規作成 |

### 2.2 フェーズ B: movement / action の Erlang term 化

| ステップ | 実施内容 |
|:---|:---|
| B1 | Rust クライアントが `bert` エンコードで movement / action を送信 |
| B2 | ZenohBridge が `:erlang.binary_to_term` で movement / action を受信 |

### 2.3 フェーズ C: set_frame_injection の Erlang term 化（NIF）

| ステップ | 実施内容 |
|:---|:---|
| C1 | `Content.FrameEncoder.encode_injection_map/1` で Erlang term 形式の injection を生成 |
| C2 | `game_events.ex` が `FrameEncoder.encode_injection_map` で injection バイナリを生成 |
| C3 | `native/nif/src/nif/decode/bert_injection.rs` を新規作成 |
| C4 | `world_nif.rs` が `apply_injection_from_bert` を呼び出し |

### 2.4 残作業・将来検討

- **2.6 ETF ヘルパーの共通化**: `bert_injection` と `bert_decode` のヘルパー重複。Phase D（native/client 作成）で整理を検討
- **2.7 依存関係の整理**: `msgpax` は client_info デコード等で一部まだ使用中。`rmp-serde` は NIF の msgpack_injection（レガシー）で残存

---

## 3. 関連ドキュメント

- [zenoh-frame-serialization.md](../../policy-as-code/why_adopted/zenoh-frame-serialization.md)
- [erlang-term-schema.md](../../docs/architecture/erlang-term-schema.md)
- [protobuf-migration.md](../../docs/architecture/protobuf-migration.md)
