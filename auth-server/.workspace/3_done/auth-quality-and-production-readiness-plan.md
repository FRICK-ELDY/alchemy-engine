# 実施計画: auth 品質ゲートと本番運用基盤の整備

> 作成日: 2026-07-04
> ステータス: 完了
> 出典: [fable-specific-weaknesses.md](../../../engine/.workspace/0_docs/evaluation/fable/archive/2026-07-31/fable-specific-weaknesses.md)

---

## 1. 目的

- `auth` の CI を `test` のみから脱し、フォーマット・警告・静的品質を gate に含める。
- あわせて release、health check、DB SSL を整え、本番デプロイの最低条件を満たす。

---

## 2. 対象

- `auth/.github/workflows/ci.yml`
- `auth/mix.exs`
- `auth/Dockerfile`
- `auth/config/runtime.exs`
- `auth/lib/auth_web/router.ex`
- `auth/README.md`

---

## 3. 実装スコープ

1. CI 品質ゲート追加
2. `mix release` ベースの本番起動整備
3. `/health` などの最小監視 API
4. DB SSL 設定の明文化と有効化

---

## 4. タスク

- [x] CI に `mix format --check-formatted` を追加する
- [x] CI に `mix compile --warnings-as-errors` を追加する
- [x] CI に `mix credo` を追加する
- [x] release ビルド手順と本番 Docker 起動方針を決める
- [x] `/health` の返却内容を定義する
- [x] DB SSL 設定を TODO のままにせず環境変数で制御可能にする
- [x] README または deploy 文書に本番起動手順を追記する

---

## 5. 受け入れ条件

- [x] CI で format / compile / test / credo が走る
- [x] warning 混入で CI が失敗する
- [x] 本番向け起動経路が 1 つ定義されている
- [x] ヘルスチェックと DB SSL 設定の運用方法が文書化されている
