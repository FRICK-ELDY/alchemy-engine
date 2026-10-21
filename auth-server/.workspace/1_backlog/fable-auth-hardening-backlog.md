# バックログ: auth 実装項目（分割後の残件）

> 更新日: 2026-07-04
> 目的: `engine/.workspace/0_docs/evaluation/fable/archive/2026-07-31/fable-specific-weaknesses.md` 起点の `auth` 課題について、着手可能なものを `2_todo` へ分割した後の残件を管理する。

---

## `2_todo` へ分割した項目

- [auth-api-rate-limiting-plan.md](../2_todo/auth-api-rate-limiting-plan.md)
- [authenticate-plug-error-hardening-plan.md](../2_todo/authenticate-plug-error-hardening-plan.md)
- [auth-jwt-jwks-engine-contract-plan.md](../2_todo/auth-jwt-jwks-engine-contract-plan.md)
- [auth-session-token-hardening-plan.md](../2_todo/auth-session-token-hardening-plan.md)
- [auth-account-lifecycle-hardening-plan.md](../2_todo/auth-account-lifecycle-hardening-plan.md)
- [auth-quality-and-production-readiness-plan.md](../2_todo/auth-quality-and-production-readiness-plan.md)

---

## `1_backlog` に残す項目

### 最低年齢チェック追加

**残留理由**

- `birthday` を何のポリシーに使うかが未確定
- 地域差、タイムゾーン、年齢制限対象コンテンツの扱いが未整理
- 仕様確定前に実装へ進めると手戻りが大きい

**次に決めること**

- [ ] 最低年齢ポリシーの有無
- [ ] 判定基準日とタイムゾーン
- [ ] 年齢不足時の挙動（登録拒否 / 一部機能制限）

---

## メモ

- 元ソース: [fable-specific-weaknesses.md](../../../engine/.workspace/0_docs/evaluation/fable/archive/2026-07-31/fable-specific-weaknesses.md)
- `2_todo` の各計画が完了したら、対応する項目は `3_Inprogress` 以降へ移動して管理する
