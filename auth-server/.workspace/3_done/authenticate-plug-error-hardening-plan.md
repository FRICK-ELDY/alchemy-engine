# 実施計画: Authenticate プラグ例外安全化

> 作成日: 2026-07-04
> ステータス: 着手前
> 出典: [fable-specific-weaknesses.md](../../../engine/.workspace/0_docs/evaluation/fable/archive/2026-07-31/fable-specific-weaknesses.md)

---

## 1. 目的

- 壊れた JWT や細工トークンを受けても `Authenticate` プラグが 500 を返さず、安定して 401 系で処理を終えるようにする。
- 外部レスポンスは単純化しつつ、内部では原因を追跡可能にする。

---

## 2. 対象

- `auth/lib/auth_web/plugs/authenticate.ex`
- 必要に応じて `auth/lib/auth/token.ex`
- `auth/test/`

---

## 3. 実装方針

1. `Token.verify/1` の戻り値を atom 固定だと仮定しない。
2. 未知エラーを握り潰すのではなく、内部では構造化ログに残す。
3. 認証失敗レスポンスは 401 または 403 に正規化する。
4. 壊れた token、期限切れ token、署名不正 token のケースをテストで固定する。

---

## 4. タスク

- [ ] `with` / `case` の分岐を見直し、未知エラーでも落ちないようにする
- [ ] 失敗レスポンスの JSON と status code を統一する
- [ ] 内部ログまたは telemetry で失敗種別を観測できるようにする
- [ ] 回帰テストを追加する

---

## 5. 受け入れ条件

- [ ] 細工トークンで `WithClauseError` などの 500 が発生しない
- [ ] 既知エラーと未知エラーの両方にテストがある
- [ ] 外部レスポンスは情報を出し過ぎず、内部では原因を追える
