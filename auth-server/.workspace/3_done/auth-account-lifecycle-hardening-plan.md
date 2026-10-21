# 実施計画: アカウント検証・復旧・退会フロー整備

> 作成日: 2026-07-04
> ステータス: 完了
> 出典: [fable-specific-weaknesses.md](../../../engine/.workspace/0_docs/evaluation/fable/archive/2026-07-31/fable-specific-weaknesses.md)

---

## 1. 目的

- メール所有確認なし、パスワードリセットなし、パスワード変更なし、退会なし、register 応答の列挙耐性不足をまとめて解消し、アカウント運用の最小機能を揃える。

---

## 2. 対象

- `auth/lib/auth/accounts/user.ex`
- `auth/lib/auth/accounts.ex`
- `auth/lib/auth_web/router.ex`
- `auth/lib/auth_web/controllers/`
- 必要に応じて migration、メール送信基盤、`auth/test/`

---

## 3. 実装スコープ

1. メール確認フロー
2. パスワードリセット開始 / 完了
3. ログイン中ユーザーのパスワード変更
4. 退会または無効化
5. register 応答の列挙耐性改善

---

## 4. タスク

- [x] `email_verified_at` 相当の状態管理を導入する
- [x] 確認トークンの発行、検証、期限切れ処理を定義する
- [x] パスワードリセット API の入出力とトークン寿命を決める
- [x] 認証済みユーザー向けのパスワード変更 API を追加する
- [x] 退会時の token revoke とデータ保持方針を決める
- [x] register 失敗レスポンスから存在有無を直接推測しにくい形へ整える
- [x] 正常系と期限切れ / 不正 token 系のテストを追加する

---

## 5. 非目標

- メール配信基盤の大規模運用設計
- 本人確認や KYC

---

## 6. 受け入れ条件

- [x] 他人メールで登録しても確認完了前は所有証明済みにならない
- [x] パスワード忘れ、変更、退会の導線が API として揃う
- [x] register 応答の列挙耐性が改善される
- [x] 主要フローにテストがある
