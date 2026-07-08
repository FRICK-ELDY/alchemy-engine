# Fable 総合評価レポート — 2026-07-07

評価者: Fable 5
評価方法: **ソースコードのみ**に基づく評価（Markdown ドキュメント非参照）。前回評価（2026-07-04）以降、**auth 強化**（`auth/.workspace/3_done` の 5 計画）を中心に再調査。engine 部分は前回評価を踏襲（変更なしと仮定）。
対象: `auth/`（Phoenix + Ash 認証サービス、lib 37 ファイル）+ `engine/`（umbrella 4 アプリ + Rust client 10 クレート + Rust NIF）
前回レポート: `docs/evaluation/archive/2026-07-04/fable-evaluation-2026-07-04.md`

## 採点基準

| 点数 | 基準 |
|:---:|:---|
| +5 / -5 | 卓越した実装 / アーキテクチャレベルの根本的欠陥 |
| +4 / -4 | プロダクション水準 / 価値命題を損なう重大な欠如 |
| +3 / -3 | 平均を明確に上回る / バグ・クラッシュを引き起こしうる欠陥 |
| +2 / -2 | ベストプラクティス準拠 / 設計原則違反・テスト欠如 |
| +1 / -1 | 正しい実装 / 軽微な問題 |

満点・上限なし。加点・減点の積み上げで総合スコアを算出。

---

## 総合スコア

| 大分類 | プラス | マイナス | 小計 | 前回小計 | 差分 |
|:---|:---:|:---:|:---:|:---:|:---:|
| プロジェクト全体（アーキテクチャ） | — | -9 | **-9** | -9 | — |
| auth（認証サービス） | +52 | -8 | **+44** | +4 | **+40** |
| engine — apps/core | +19 | -10 | **+9** | +9 | — |
| engine — apps/contents | +18 | -15 | **+3** | +3 | — |
| engine — apps/network | +20 | -16 | **+4** | +4 | — |
| engine — apps/server | +4 | -2 | **+2** | +2 | — |
| engine — rust/nif（Formula VM） | +11 | -9 | **+2** | +2 | — |
| engine — rust/client | +31 | -23 | **+8** | +8 | — |
| 横断評価層 | +20 | -6 | **+14** | +14 | — |
| **総合** | **+175** | **-98** | **+77** | **+37** | **+40** |

> 詳細な個別項目は以下を参照:
> - プラス点: `docs/evaluation/fable-specific-strengths.md`（68 項目）
> - マイナス点: `docs/evaluation/fable-specific-weaknesses.md`（49 項目）
> - 提案(0点): `docs/evaluation/fable-specific-proposals.md`（15 件）
> - 改善計画: `workspace/0_reference/fable-improvement-plan.md`
> - 前回版: `docs/evaluation/archive/2026-07-04/`

---

## 再評価の背景

`auth/.workspace/3_done` に記録された 5 計画（レート制限、Authenticate 硬化、セッション/トークン強化、JWT/JWKS 契約、品質/本番対応）に基づき auth を徹底再調査した。lib ファイル数は 26 → 37、テストファイルは 6 → 21 に増加している。

---

## 総評

**「認証サービスは運用可能な水準に到達。エンジン側の配線課題は依然として残る」** — 前回の一言要約を更新する。

### 前回からの最大の変化（auth +40 点）

auth は前回「暗号設計は丁寧だが防御線に穴だらけ」（ネット +4）だったが、今回 **ネット +44** まで改善した。特に以下 3 点が評価を大きく押し上げている。

1. **多軸レート制限** — 前回最大の -4 が解消。IP / identifier / email / token family の endpoint 別制限、429 + `Retry-After`、telemetry まで実装。
2. **refresh ローテーション + family 再利用検知** — OAuth 2.0 Security BCP 準拠。grace 期間内外の挙動をテストで検証済み。
3. **アカウントライフサイクル一式** — verify-email / forgot-password / change-password / deactivate を API 化。列挙安全な応答設計も統一。

加えて、JWT TTL 15 分化、マルチ鍵 JWKS、TokenCleanup GC、CI 品質ゲート（format/credo/warnings-as-errors）、本番 release Dockerfile が揃い、**「登録だけの認証」から「運用できる認証サービス」へ昇格**した。

### 依然として残る構造的問題（engine 中心）

engine 部分のスコアは前回と同一（変更なし仮定）。以下は総合スコアを押し下げ続けている。

1. **「連合」未着手（-4）** — ActivityPub / S2S / インスタンス間 identity は依然ゼロ。
2. **看板機能の未配線** — VR スタブ、非 `:main` ルーム未駆動、補間未使用（各 -4）。
3. **auth ↔ engine 未接続（-3）** — auth の強化は完了したが、engine の `POST /api/room_token` は依然無認証。auth の JWT がゲーム入場に使われていない。
4. **engine セキュリティの非対称** — UDP 無認証 JOIN、SECRET_KEY_BASE fail-fast なし、zlib 無制限展開（各 -3）。
5. **Formula VM 除算バグ** — `5.0 / 2.0` → `I32(2)` の実バグが未修正。

### 評価の位置づけ

総合 **+37 → +77**（+40）。改善の全量が auth に集中しており、**次の費用対効果の高い一手は auth ↔ engine 接続**である。auth 単体の残課題（メール検証必須化、health DB チェック等）は -8 と小さく、ポリシー判断と運用仕上げの領域に移った。

---

## auth 再評価 — 解消・残存の対照

### 解消されたマイナス点（前回 auth -26 のうち -18 解消）

| 前回指摘 | 点数 | 対応 |
|:---|:---:|:---|
| レート制限欠如 | -4 | `Auth.RateLimit` + `AuthWeb.Plugs.RateLimit` |
| Authenticate 500 経路 | -3 | `classify_failure/1` + rescue + キャッチオール |
| refresh ローテーションなし | -2 | family_id + rotate + reuse detection |
| JWT TTL 24h | -2 | 900 秒（15 分） |
| 鍵ローテーション未対応 | -2 | `jwt_verification_key_paths` + multi-key JWKS |
| token GC なし | -2 | `Auth.TokenCleanup` |
| アカウント運用機能なし | -2 | lifecycle API 一式 |
| auth CI 品質ゲートなし | -2 | format / credo / warnings-as-errors |
| 本番デプロイ構成なし | -2 | mix release + Dockerfile + force_ssl + MailConfig |
| register 列挙 | -1 | 汎用 `:register_failed` |
| DB SSL コメントアウト | -1 | `DATABASE_SSL` env |

### auth 残存マイナス点（-8）

| 指摘 | 点数 |
|:---|:---:|
| ログインにメール検証を要求しない | -2 |
| 最低年齢チェックなし | -1 |
| `/health` に DB 疎通なし | -1 |
| `account_tokens` GC なし | -1 |
| レート制限が単一ノード ETS | -1 |
| CORS 未設定 | -1 |
| Dialyzer / hex.audit なし | -1 |

---

## 特筆事項（抜粋）

### 最高評価項目（+4 以上、auth 新規/強化分）

- RS256 JWT + マルチ鍵 JWKS + kid ルーティング（`auth/lib/auth/token/keys.ex`）
- 多軸レート制限 + telemetry + Retry-After（`auth/lib/auth/rate_limit.ex`）
- refresh ローテーション + family 再利用検知（`auth/lib/auth/accounts.ex`）
- アカウントライフサイクル API（verify / reset / change / deactivate）
- Authenticate プラグ防御深度（`auth/lib/auth_web/plugs/authenticate.ex`）

### 最重要指摘（-4、engine 側・変更なし）

- 連合（ActivityPub 型 federation）の実装ゼロ
- `:main` 以外のルームでゲームループ未駆動
- 補間・予測の未配線（実質 20Hz 表示）
- OpenXR 完全スタブ（VR が動作しない）

### 次の優先改善（費用対効果順）

1. **auth ↔ engine 接続** — JWKS 検証 + room token の Bearer 必須化（横断 -3 解消）
2. **Formula VM 除算バグ修正** — Rust 単体テスト追加と同時（nif -3 解消）
3. **engine SECRET_KEY_BASE fail-fast** — 数行で -3 解消
4. **auth ログイン時のメール検証必須化** — auth 残 -2 解消

---

## 検証記録

- auth ソース再調査: `auth/.workspace/3_done` の 5 計画に対応する実装を `lib/`（37 ファイル）・`test/`（21 ファイル）・`ci.yml`・`Dockerfile` で確認
- engine 部分: 前回（2026-07-04）評価を踏襲。engine コードの変更は本再評価の対象外
- auth ローカルテスト: `remote_ip` 依存未取得のため `mix test` 未実行。CI（ubuntu + Postgres 16 + format/credo/warnings-as-errors/test）は `ci.yml` で構成確認済み

---

## アーカイブ

前回評価（2026-07-04）のドキュメント 5 点は `docs/evaluation/archive/2026-07-04/` に移動済み:

- `fable-specific-strengths.md`
- `fable-specific-weaknesses.md`
- `fable-specific-proposals.md`
- `fable-evaluation-2026-07-04.md`
- `fable-improvement-plan.md`
