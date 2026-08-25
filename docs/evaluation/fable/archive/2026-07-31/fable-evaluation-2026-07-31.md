# Fable 総合評価レポート — 2026-07-31

評価者: Fable 5
評価方法: **ソースコードのみ**に基づく評価（Markdown ドキュメント非参照）。前回評価（2026-07-07）の全指摘（プラス・マイナスとも）を現ソースで再検証し、前回以降の変更（engine PR #320〜#322、auth は変更なし）を反映。
対象: `auth/`（Phoenix + Ash 認証サービス、lib 37 ファイル）+ `engine/`（umbrella 4 アプリ + Rust client 10 クレート + Rust NIF）
前回レポート: `docs/evaluation/fable/archive/2026-07-07/fable-evaluation-2026-07-07.md`

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

| 大分類 | プラス | マイナス | 小計 | 前回小計（訂正後） | 差分 |
|:---|:---:|:---:|:---:|:---:|:---:|
| プロジェクト全体（アーキテクチャ） | — | -9 | **-9** | -9 | — |
| auth（認証サービス） | +56 | -8 | **+48** | +48 | — |
| engine — apps/core | +21 | -10 | **+11** | +9 | **+2** |
| engine — apps/contents | +20 | -14 | **+6** | +3 | **+3** |
| engine — apps/network | +20 | -16 | **+4** | +4 | — |
| engine — apps/server | +4 | -2 | **+2** | +2 | — |
| engine — rust/nif（Formula VM） | +11 | -9 | **+2** | +2 | — |
| engine — rust/client | +32 | -22 | **+10** | +8 | **+2** |
| 横断評価層 | +21 | -6 | **+15** | +14 | **+1** |
| **総合** | **+185** | **-96** | **+89** | **+81** | **+8** |

> **前回スコアの訂正**: 前回レポートは総合 +77 と記載していたが、auth プラス小計に集計誤りがあった（記載 +52、個別項目の実合計 +56）。訂正後の前回総合は **+81**。本表の「前回小計」「差分」は訂正後の値を基準とする。

> 詳細な個別項目は以下を参照:
> - プラス点: `docs/evaluation/fable/archive/2026-07-31/fable-specific-strengths.md`（68 項目）
> - マイナス点: `docs/evaluation/fable/archive/2026-07-31/fable-specific-weaknesses.md`（48 項目）
> - 提案(0点): `docs/evaluation/fable/archive/2026-07-31/fable-specific-proposals.md`（15 件）
> - 改善計画: `workspace/0_reference/fable-improvement-plan.md`
> - 前回版: `docs/evaluation/fable/archive/2026-07-07/`

---

## 再評価の背景

前回評価（2026-07-07）以降のコード変更は engine 側に集中している。

- **権威 tick Hz の設定化**（PR #321）— `Core.Config` に tick_hz（許容 10/20/30/60、フォールバック 20）を導入し、`TICK_HZ` env・`tick_ms`/`dt` のコンテキスト注入・バックプレッシャー/診断間隔の追従・専用テストまで一貫して実装。コンテンツの移動・タイマーは dt ベースに全面移行。
- **physics_ms の実測化**（同上）— 従来は固定値を emit していた死にメトリクスが、ゲームプレイ更新の実測時間になった。
- **CI の再有効化**（PR #322）— `ci.yml.ignore` → `ci.yml` のリネームで GitHub Actions が復活。proto-verify は protoc-gen-elixir 0.16.0 のピン留め付き。
- **auth は変更なし**（HEAD `4df420e`、作業ツリークリーン）。前回の全項目をスポット再確認し、存続を確認した。

なお前回「変更なしと仮定」で踏襲した engine 部分についても、今回はマイナス 45 項目・プラス主要項目を現ソースで実地検証した。その結果、前回指摘のうち 1 件（GPU デバイスロス回復なし）は実装が確認できたため撤回し、1 件（Core.Stats の graze 統計）は記述を事実に合わせて修正した。

---

## 総評

**「土台の丁寧さは引き続き高水準。だが価値命題（連合・マルチルーム・VR・滑らかさ）の配線と、engine の防御線は 3 週間前からほぼ動いていない」**

### 今回の改善（+8）

今回の tick 設定化は、単なる定数変更ではなく「権威 tick を第一級の設定にする」正攻法の実装だった。

1. **tick_hz 設定化 + dt ベース化（core +2, contents +2）** — 許容値検証・フォールバック・env 上書き・テストが揃い、ゲームロジックは tick_hz 非依存になった。前回指摘の「tick 定数の不整合（-1）」も根本解消。
2. **physics_ms 実測化** — 死にメトリクス指摘（-2）が -1 に緩和。OVER BUDGET 判定が初めて意味を持つようになった。
3. **SurfaceError::Lost/Outdated 回復の確認（client +1、-1 撤回）** — reconfigure による回復経路が存在する。
4. **CI 再有効化 + protobuf 0.16.0 ピン留め（横断 +1）** — 生成物ドリフト検出が再現性の根拠付きで復活。

一方で新規の軽微な問題も 1 件計上した: `config.exs` のコメントは「デフォルト 20（推奨）」と言いながら出荷値は `tick_hz: 10` で、選定理由の説明がない（-1）。

### 依然として残る構造的問題

スコアの重心は 3 週間前から変わっていない。以下は前回指摘のまま全て現存する。

1. **「連合」未着手（-4）** — 方針ドキュメントは追加されたが、ソース上の実装はゼロのまま。
2. **看板機能の未配線** — 非 `:main` ルーム未駆動（-4）、補間未使用（-4）、OpenXR 実質スタブ（-4）。特に補間は、権威 tick の 10〜20Hz 化により**前回より体感影響が拡大**している（60fps 描画に対し 10〜20Hz スナップショット表示）。
3. **auth ↔ engine 未接続（-3）** — `POST /api/room_token` は依然無認証。auth の RS256/JWKS がゲーム入場に使われていない。
4. **engine セキュリティの非対称** — UDP 無認証 JOIN、SECRET_KEY_BASE fail-fast なし、zlib 無制限展開（各 -3）。
5. **Formula VM 除算バグ（-3）** — `5.0 / 2.0` → `I32(2)` の実バグが未修正。Rust 単体テストもゼロのまま（-3）。

### 評価の位置づけ

総合 **+81 → +89**（+8）。今回の改善は「品質の地固め」であり方向は正しいが、上記の -3〜-4 帯が 10 件残っている限りスコアの伸びは頭打ちになる。**次の費用対効果の最高点は前回から不変で、(1) auth ↔ engine 接続、(2) Formula 除算バグ + Rust テスト、(3) SECRET_KEY_BASE fail-fast の 3 点**である。

---

## 前回指摘の解消・変化の対照

| 前回指摘 | 前回点数 | 今回 | 内容 |
|:---|:---:|:---:|:---|
| tick 定数の不整合（contents） | -1 | **解消** | `Core.Config.tick_ms/0` + dt ベース化 |
| 死にコード・死に設定（core） | -2 | **-1 に緩和** | physics_ms 実測化。InputHandler / features:[] は残存 |
| GPU デバイスロス回復なし（client） | -1 | **撤回** | `SurfaceError::Lost / Outdated` → reconfigure を確認 |
| RoomSupervisor のコンテンツ直接参照（core -3 の一部） | — | **部分改善** | RoomSupervisor は解消。ただし漏洩は `Core.Config` / StressMonitor に残存し -3 は維持 |
| Core.Stats の graze 統計（core -1 の記述） | — | **記述修正** | graze は現存せず。kills 系は残存し -1 は維持 |
| 出荷 tick_hz とコメントの矛盾（core） | — | **新規 -1** | コメント「デフォルト 20（推奨）」直下で `tick_hz: 10` |

上記以外の前回マイナス指摘（40 件超）は全て現ソースで CONFIRMED。

---

## 特筆事項（抜粋）

### 最高評価項目（+4 以上）

- RS256 JWT + マルチ鍵 JWKS + kid ルーティング（auth、+5）
- refresh ローテーション + family 再利用検知（auth、+5）
- 多軸レート制限 + Retry-After / アカウントライフサイクル API / テスト拡充（auth、各 +4）
- FormulaGraph コンパイラ / バイトコード契約（core、各 +4）
- バックプレッシャー設計（contents、+4）
- 3 トランスポート統一収束（network、+4）
- panic しない NIF エラー境界（nif、+4）
- クレート分離 / golden E2E 契約テスト / auth_client 資格情報管理（client、各 +4）
- mix alchemy.ci（横断、+4）

### 最重要指摘（-4）

- 連合（ActivityPub 型 federation）の実装ゼロ
- `:main` 以外のルームでゲームループ未駆動
- 補間・予測の未配線（実質 10〜20Hz 表示）
- OpenXR 実質スタブ（VR が動作しない）

### 次の優先改善（費用対効果順）

1. **auth ↔ engine 接続** — JWKS 検証 + room token の Bearer 必須化（-3 解消）
2. **Formula VM 除算バグ修正 + Rust 単体テスト** — 型分岐修正と checked_div、テスト同時追加（-6 解消）
3. **engine SECRET_KEY_BASE fail-fast** — 数行で -3 解消
4. **CI の `cargo test --workspace` 化** — 1 行変更で既存 29 テストが回帰検出に乗る（-3 解消）
5. **補間の配線** — interp.rs は実装済み。ブリッジへの接続のみ（-4 解消、tick 低 Hz 化で優先度上昇）

---

## 検証記録

- 検証方法: 前回評価の全マイナス項目（49 件）+ プラス主要項目を、3 系統の並行調査（engine Elixir / engine Rust / auth）で現ソースと照合。CONFIRMED / REFUTED / CHANGED を判定し、本レポートに反映
- engine 差分調査: `git diff d0705b4..HEAD`（前回評価コミット以降）で変更 13 ファイルを精読
- auth: 前回評価以降コミットなし（`git log` / `git status` で確認）。残存指摘 7 件・強み 14 件をスポット再確認
- テスト実行: 本再評価は静的検証のみ（`mix alchemy.ci` の実行は前回 2026-07-07 に main で ALL PASSED を確認済み。CI は PR #322 で再有効化され GitHub Actions 上で稼働）

---

## アーカイブ

前回評価（2026-07-07）のドキュメント 4 点は `docs/evaluation/fable/archive/2026-07-07/` に移動済み:

- `fable-evaluation-2026-07-07.md`
- `fable-specific-strengths.md`
- `fable-specific-weaknesses.md`
- `fable-specific-proposals.md`
