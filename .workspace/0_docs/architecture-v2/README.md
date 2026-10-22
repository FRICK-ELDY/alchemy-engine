# architecture-v2 — AI / 人間向け読む順

> **目的**: v1（現行実装記述）と v2（目標）を同時に読んでも矛盾しないよう、**読む順と優先順位**を固定する。  
> **作成**: 2026-10-23（Phase 0: AI 正本の矛盾解消）

---

## 読む順（固定）

1. **目標の全体像** — [overview.md](overview.md)  
   分散連合型 VRSNS を見据えた目標構成図。未実装を含む。
2. **一致・衝突・決定** — [diff-from-v1.md](diff-from-v1.md)  
   - §1 一致（M1–M16）: 移行時も壊さない  
   - §2.1 方針決定済: **現行記述より優先**（C1/C12・C6・C9・C10 および後続決定）  
   - §2 未決: 実装前に決めるゲート  
3. **現行実装の詳細** — [../architecture/](../architecture/)  
   コードと一致する記述。各主要ファイル先頭のステータスバナーを読む。

---

## 優先順位（矛盾時）

| 優先 | 文書 | 使い方 |
|:---|:---|:---|
| 1 | `diff-from-v1.md` §2.1（方針決定済） | 決定内容は v1 本文より優先 |
| 2 | `architecture-v2/overview.md` | 目標の全体像・境界 |
| 3 | `architecture/`（v1） | 現行実装の詳細。バナー付き |

**Cursor alwaysApply ルール**（[`.cursor/rules/implementation.mdc`](../../../.cursor/rules/implementation.mdc)）は §2.1 の **時間軸別 4 SSoT** に合わせてある。v1 の「Elixir = 単一ドメイン SSoT」表現と食い違う場合はルールと §2.1 を正とする。

---

## ステータスバナー（v1 先頭の統一文言）

```text
> **ステータス**: 現行実装の記述  
> **目標**: [architecture-v2/](../architecture-v2/)  
> **決定済みの上書き**: [diff-from-v1.md](../architecture-v2/diff-from-v1.md) §2.1（C1/C12・C6・C9・C10 等）を優先
```

---

## 関連索引

| 文書 | 内容 |
|:---|:---|
| [auth-server.md](auth-server.md) | auth 索引（契約正本は jwt-jwks） |
| [host-server.md](host-server.md) | host-server 責務・契約（コード: `client/host-server`） |
| [shared-sim.md](shared-sim.md) | shared-sim 責務・契約（コード: `client/shared-sim`） |
| [builtin-world-manifests.md](builtin-world-manifests.md) | 検証用 3 本の WorldManifest 移植・DoD |
| [../jwt-jwks-engine-contract.md](../jwt-jwks-engine-contract.md) | auth ↔ engine JWT/JWKS 契約 |
| [../vision-goal.md](../vision-goal.md) | Phase ロードマップ |

## Phase 進捗（文書ゲート）

| Phase | 内容 | 状態 |
|:---|:---|:---|
| 0 | 読む順・バナー・Cursor ルール（4 SSoT） | 完了 2026-10-23 |
| 1 | 決定済み（C1/C6/C9/C10）本文化・auth 索引 | 完了 |
| 2 | C2/C3/C4/C5/C7/C8/C11 方針決定 | 完了（全衝突 ID 決定済） |
| 3 | shared-sim / host-server スキャフォールド | S0 完了（Manifest・Frame publish は後続） |
