# AlchemyEngine — 改善計画

> このドキュメントは現在の弱点を整理し、各課題に対する具体的な改善方針を定義する。  
> 最新の評価: [evaluation-2026-04-01.md](../../docs/evaluation/evaluation-2026-04-01.md)  
> 2026-03 系の日付付き評価レポート: [docs/evaluation/archive/](../../docs/evaluation/archive/)  
> プラス点: [specific-strengths.md](../../docs/evaluation/specific-strengths.md) / マイナス点: [specific-weaknesses.md](../../docs/evaluation/specific-weaknesses.md) / 提案: [specific-proposals.md](../../docs/evaluation/specific-proposals.md)

---

## スコアカード（2026-04-01 評価）

| カテゴリ | 本評価での傾向 |
|:---|:---|
| Elixir OTP・ルーム／ストア | 高 — `RoomSupervisor`・`FormulaStore`・`EventBus` が整理されている |
| Network（Channel / UDP / Local） | 高 — トークン付き join とテストが厚い |
| Rust NIF | Formula VM に特化。旧 physics / ECS 実証はツリー外（意図的削除） |
| Rust クライアント | 高 — Protobuf レンダリング契約と clippy 厳格化 |
| テスト・静的解析 | 高 — `mix test` 102 件、credo strict、clippy `-D warnings` |
| ドキュメント整合 | 改善 — `UserSocket` moduledoc は 2026-04-01 に Channel 実装と整合 |
| 永続化（セーブ／ロード） | **未実装（意図的）** — オンライン向け設計はこれから ADR で取り決め |
| **採点式合計（当該レポート）** | **+33 点**（[evaluation-2026-04-01.md](../../docs/evaluation/evaluation-2026-04-01.md)。`UserSocket` 修正・`mix alchemy.ci` 反映後の再集計） |
| ローカル CI | **`mix alchemy.ci`** — [docs/warranty/ci.md](../../docs/warranty/ci.md) |

---

## 解消・変化した以前の論点（参考）

以下は **2026-03 以前の改善計画にあったが、現行コードでは前提が変わった** 項目である。

| 旧 ID / 論点 | 変化 |
|:---|:---|
| SaveManager / HMAC ローカルセーブ | コードベースから削除。`Contents.Events.Game` が `__save__` 等をログのみで無視（network TBD） |
| `create_world` NIF / `world_nif.rs` | Formula NIF のみに縮小。物理ワールド NIF は無し |
| I-P 補間と nif/physics | physics クレート不在。補間・姿勢の議論は protobuf フレーム／クライアント側に再定義が必要 |

---

## 課題一覧（優先度順）

### D-1: `Network.UserSocket` の moduledoc 修正 — **対応済み（2026-04-01）**

`connect/3` と Channel join のトークン必須を分離して記述し、`Network.Channel` moduledoc へ誘導するよう更新した。

**対象**: `apps/network/lib/network/user_socket.ex`

---

### D-2: オンライン永続化 ADR

**優先度**: 高（プロダクト方針）

**問題**: UI からセーブ／ロード操作は届くがサーバーは無視するのみ。ネットワークゲームでは権威データ・競合・プレイヤー紐付けを決めないと実装できない。

**方針**: ADR で「サーバー権威スナップショット」「バージョン」「オフライン可否」「改ざん対策のレイヤ」を定義したうえで behaviour 実装へ落とす。

**対象**: `docs/`（新規 ADR、ユーザー合意後）, `apps/contents/lib/events/game.ex`（将来マッピング）

---

### D-3: 単一 CI エントリ — **既存: `mix alchemy.ci`**

**優先度**: 低（ドキュメント整合のみ）

**現状**: `Mix.Tasks.Alchemy.Ci`（`mix alchemy.ci`）が Rust / Elixir のローカル CI を単一コマンドで実行する。`mix alchemy.ci check` はテストなしの高速チェック。

**残タスク**: `.cursor/rules/evaluation.mdc` の CI 手順は `mix alchemy.ci` に更新済み。技術層の `native/` 等、パス記述の残り整合は任意。

**参照**: [docs/warranty/ci.md](../../docs/warranty/ci.md), [development.md](../../development.md)

---

### D-4: `Server.Application` の smoke テスト

**優先度**: 中

**問題**: `apps/server` に ExUnit が無い。

**方針**: 最小限の監督ツリー起動テスト（子の生存確認のみ）。

---

### D-5: Diagnostics のコンテンツ非依存化

**優先度**: 低〜中

**問題**: ログ用に playing 状態のキー構造に依存しうる。

**方針**: `ContentBehaviour` に診断用コールバックを追加するか、フレームキャッシュ更新をコンテンツ側に寄せる。

**対象**: `apps/contents/lib/events/game/diagnostics.ex`

---

### D-6: ランチャー（`rust/launcher`）

**優先度**: 低（運用・配布フェーズ）

**問題**: Windows での zenohd 起動方式、ポート検知、プロセス寿命管理など、過去計画に列挙された課題は **クライアント配布時に再浮上**しうる。

**方針**: 「動くこと」を小さな単位で検証しながら直す。詳細は必要時に `rust/launcher` 直下の設計メモを再作成する。

---

### D-7: `Core.InputHandler` の残骸

**優先度**: 低

**問題**: LocalUser 系移行後も `apps/core/lib/core/input_handler.ex` が残っている可能性。デッドコードなら削除。

**方針**: 参照 grep → 未使用なら削除、使用中なら責務をドキュメント化。

---

## 関連リンク

- [architecture/overview.md](../../docs/architecture/overview.md)
- [cross-compile.md](../../docs/cross-compile.md)
