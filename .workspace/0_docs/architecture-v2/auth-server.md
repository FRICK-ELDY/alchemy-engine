# auth-server — 索引（案 B）

> **ステータス**: 索引のみ。契約本文は移設しない。  
> **作成**: 2026-10-23  
> **統合方針**: [diff-from-v1.md](diff-from-v1.md) §8.3 **案 B**（索引＋契約正本は既存パス）

---

## 図上の位置

[overview.md](overview.md) の **運営側 Core Hub** 内 `auth-server`。

- JWT（RS256）発行・`/.well-known/jwks.json`
- 利用規約同意（tos_version）・Friendship / グループ（ビジョン。契約への昇格は未完）
- Stage 1: SQLite / Stage 2+: PostgreSQL（運用 docs 側）

---

## 正本の置き場（二重管理しない）

| 層 | パス | 内容 |
|:---|:---|:---|
| **auth ↔ engine 契約** | [jwt-jwks-engine-contract.md](../jwt-jwks-engine-contract.md) | RS256・iss/aud・JWKS・失効・engine 検証チェックリスト |
| 連合での役割 | [federation.md](../architecture/federation.md) §1.1 / §4-3 | ホーム IdP・訪問先検証・Room Token |
| 目標箱の説明 | [overview.md](overview.md) | Core Hub の Auth 箱 |
| auth 内部 hardening | `auth-server/.workspace/` 等 | セッション・レート制限・ライフサイクル |

---

## v2 図とのギャップ（意図的に契約未昇格のもの）

| 項目 | 扱い |
|:---|:---|
| Remember Me / Refresh（7日） | auth 実装 docs を正。契約への追記は別タスク |
| ToS（tos_version） | 当面 v2 ビジョン。契約昇格は別タスク |
| Friendship / グループ | 同上 |
| Stage SQLite→PostgreSQL | auth 運用 docs |

---

## A1 の分類

洗い出し上の A1（auth-server）は「architecture/ に正本が無い追加」ではなく、**既存・分散 (sibling) → 本索引で architecture-v2 に接続**。
