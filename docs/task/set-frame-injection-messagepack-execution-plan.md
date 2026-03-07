# set_frame_injection MessagePack 化 — 実行計画書

> 作成日: 2026-03-07  
> 出典: [p5-transfer-optimization-design.md](../architecture/p5-transfer-optimization-design.md)  
> 参照: [set-frame-injection-messagepack-design.md](../architecture/set-frame-injection-messagepack-design.md)

---

## 概要

`set_frame_injection` の injection_map を MessagePack バイナリ形式で渡す経路を追加し、NIF decode オーバーヘッドを削減する。

| 項目 | 内容 |
|:---|:---|
| 形式 | MessagePack |
| Elixir ライブラリ | msgpax（既存） |
| Rust ライブラリ | rmp-serde（既存） |
| 対象 | set_frame_injection（injection_map） |

---

## 実施タスク

### Phase 1: 基盤整備

| # | タスク | 担当 | 成果物 |
|:---:|:---|:---|:---|
| 1 | injection_map の MessagePack スキーマ文書化 | docs | messagepack-schema.md に injection セクション追加 |
| 2 | 設計ドキュメントのレビュー・確定 | - | [set-frame-injection-messagepack-design.md](../architecture/set-frame-injection-messagepack-design.md) |

### Phase 2: 実装

| # | タスク | 担当 | 成果物 |
|:---:|:---|:---|:---|
| 3 | Elixir: encode_injection_map/1 を MessagePackEncoder に追加 | contents | map → バイナリ変換 |
| 4 | Rust: msgpack_injection デコーダを nif に追加 | nif | decode_injection_from_msgpack |
| 5 | NIF: set_frame_injection_binary/2 を追加 | nif | タプル版は残す |
| 6 | game_events.ex: MessagePack パスを呼び出すよう切り替え | contents | 全コンテンツで一括適用 |

### Phase 3: 検証

| # | タスク | 担当 | 成果物 |
|:---:|:---|:---|:---|
| 7 | 動作確認 | - | 既存コンテンツが正常に動作すること |
| 8 | パフォーマンス計測（任意） | - | Benchee または Telemetry で計測 |

---

## 実施順序

1. **Phase 1**: スキーマ・設計の文書化
2. **Phase 2**: Elixir エンコーダ → Rust デコーダ → NIF 追加 → 呼び出し切り替え
3. **Phase 3**: 動作確認・必要に応じて計測

---

## 完了条件

- [ ] set_frame_injection を MessagePack バイナリで呼び出せる
- [ ] VampireSurvivor・AsteroidArena 等が MessagePack パスで正常に動作する
- [ ] タプル形式パスは残存し、フォールバック可能
- [ ] スキーマが文書化され、変更時の更新手順が明確である

---

## 参照

| ドキュメント | 内容 |
|:---|:---|
| [set-frame-injection-messagepack-design.md](../architecture/set-frame-injection-messagepack-design.md) | 設計 |
| [p5-2-messagepack-execution-plan.md](p5-2-messagepack-execution-plan.md) | push_render_frame の MessagePack 化（参考） |
| [messagepack-schema.md](../architecture/messagepack-schema.md) | スキーマ定義 |
