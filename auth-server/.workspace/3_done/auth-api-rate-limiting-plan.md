# 実施計画: auth API レート制限導入

> 作成日: 2026-07-04
> ステータス: 完了
> 出典: [fable-specific-weaknesses.md](../../../engine/.workspace/0_docs/evaluation/fable/archive/2026-07-31/fable-specific-weaknesses.md)

---

## 1. 目的

- `POST /api/login`、`POST /api/register`、`POST /api/refresh` にレート制限を導入し、ブルートフォース、登録スパム、過剰 refresh を抑止する。
- 429 応答、観測、環境別設定まで含めて、公開 API として最低限の悪用耐性を持たせる。

---

## 2. 対象

- `auth/lib/auth_web/router.ex`
- 必要に応じて `auth/lib/auth_web/plugs/`
- `auth/mix.exs`
- `auth/config/*.exs`
- `auth/test/`

---

## 3. 実装方針

1. `login` は IP と identifier の両軸で制限する。
2. `register` は IP と email の両軸で制限する。
3. `refresh` は IP と token 系列または user 単位で制限する。
4. 制限超過時は 429 とし、JSON 形式を固定する。
5. throttle 発火回数をログまたは telemetry で観測可能にする。

---

## 4. タスク

- [x] 採用ライブラリまたは自前実装方針を決める
- [x] API ごとの key と window を定義する
- [x] 開発環境で緩和、本番で厳格化できる設定を追加する
- [x] 429 応答のエラーフォーマットを既存 API と整合させる
- [x] 正常系、超過系、境界値のテストを追加する

---

## 5. 非目標

- CAPTCHA や WAF 連携
- 管理画面からの手動解除機能

---

## 6. 受け入れ条件

- [x] `login` / `register` / `refresh` 全てでレート制限が有効
- [x] 制限超過時に 500 ではなく 429 を返す
- [x] テストで超過時の挙動を確認できる
- [x] 本番向けの閾値を設定で変更できる
