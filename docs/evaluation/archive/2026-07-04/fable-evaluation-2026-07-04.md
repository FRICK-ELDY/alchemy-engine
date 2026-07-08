# Fable 総合評価レポート — 2026-07-04

評価者: Fable 5
評価方法: **ソースコードのみ**に基づく評価（Markdown ドキュメント非参照）。4 系統の並列詳細調査（auth / engine Elixir apps / rust/client / rust/nif + 横断品質）に加え、重要指摘は評価者がコードを直接読んで検証。`mix alchemy.ci` を main ブランチで実行し **ALL PASSED** を確認済み。
対象: `auth/`（Phoenix + Ash 認証サービス、lib 26 ファイル）+ `engine/`（umbrella 4 アプリ 約 172 ファイル + Rust client 10 クレート + Rust NIF）

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

| 大分類 | プラス | マイナス | 小計 |
|:---|:---:|:---:|:---:|
| プロジェクト全体（アーキテクチャ） | — | -9 | **-9** |
| auth（認証サービス） | +30 | -26 | **+4** |
| engine — apps/core | +19 | -10 | **+9** |
| engine — apps/contents | +18 | -15 | **+3** |
| engine — apps/network | +20 | -16 | **+4** |
| engine — apps/server | +4 | -2 | **+2** |
| engine — rust/nif（Formula VM） | +11 | -9 | **+2** |
| engine — rust/client | +31 | -23 | **+8** |
| 横断評価層（テスト・可観測性・DX・セキュリティ） | +20 | -6 | **+14** |
| **総合** | **+153** | **-116** | **+37** |

> 詳細な個別項目は以下を参照:
> - プラス点: `docs/evaluation/fable-specific-strengths.md`（56 項目）
> - マイナス点: `docs/evaluation/fable-specific-weaknesses.md`（55 項目）
> - 提案(0点): `docs/evaluation/fable-specific-proposals.md`（15 件）
> - 改善計画: `workspace/0_reference/fable-improvement-plan.md`

---

## 総評

**「エンジンとしての骨格は本物。VRSNS としての看板はまだ実装が追いついていない」** — これが本評価の一言要約である。

### このプロジェクトの本質的な強さ

1. **境界設計の一貫した規律。** Elixir がコンパイル・オーケストレーション、Rust が実行・描画という責務分離が、Formula（Elixir コンパイラ → バイトコード契約 → Rust VM）、描画（Elixir FrameEncoder → protobuf golden 契約テスト → Rust デコーダ）、認証（RS256 秘密鍵は auth のみ、公開鍵は JWKS 配布、クライアント資格情報は OS keyring のみ）の 3 箇所すべてで貫かれている。言語間契約を golden バイナリテストと CI の proto-verify ジョブで二重に守る構えは、個人プロジェクトとして例外的に優れる。

2. **失敗を想定した実装。** NIF は不正バイトコードで panic せずエラータプルを返し、UDP/Zenoh は不正パケットで落ちず、ルームは kill されても他ルームが生き残ることをテストが実証し、ゲームループはメールボックス深度でフレームドロップしつつスコア整合性だけは守る。「落ちない・落ちても局所化する」という BEAM の思想を正しく体現している。

3. **誠実なコードベース。** FIXME/HACK ゼロ、TODO 5 件。moduledoc は歴史的経緯や制約（当たり判定の近似、キャッシュの欠如）まで正直に記述し、実装と乖離した美化がない。`mix alchemy.ci` 一発でローカルと CI の品質ゲートが一致する DX も高水準。

### 総合スコアを押し下げている構造的問題

1. **「連合」が未着手（-4）。** ActivityPub / WebFinger / S2S / インスタンス間 identity のいずれもソースに存在しない。現状は「単一運営者の BEAM クラスタ + 中央 auth」であり、libcluster すらデフォルト `topologies: []` で単一ノード。「分散」の基盤はあるが「連合」はゼロである。

2. **看板機能が配線されていない。** VR は xr クレートが完全スタブ（-4）、マルチルームは `:main` 以外でゲームループが駆動せず（-4）、補間ユーティリティ `interp.rs` は存在するが未使用で 20Hz 表示のまま（-4）。auth と engine も未接続で、room token は無認証発行（-3）。個々の部品は丁寧に作られているのに、部品同士をつなぐ「最後の配線」が系統的に欠けている。

3. **セキュリティの非対称。** auth はタイミング攻撃対策まで実装する一方でレート制限が皆無（-4）。WebSocket は RoomToken 必須なのに UDP JOIN は無認証（-3）。engine の SECRET_KEY_BASE は公開リポジトリの固定値のまま prod 起動しうる（-3）。zlib 展開は無制限（-3）。「作り込んだ箇所」と「素通しの箇所」の落差が攻撃者に最短経路を提供してしまう。

4. **テストの量が質に追いつかない。** テストの設計品質（隔離実証・golden 契約・不正入力耐性）は高いのに、contents は lib 119 に対しテスト 4、nif は Rust テスト 0（`cargo test -p nif` は 0 件で PASS）、約 29 件あるクライアント Rust テストは CI で一度も実行されない。**Formula VM の float 除算が整数除算に化ける実バグ（`5.0 / 2.0` → `2`）が現存する**のは、この検証空白の直接的帰結である。

### 評価の位置づけ

プラス +153 に対しマイナス -116 という比率は、「書かれたコードの質は高いが、書かれていないもの・つながっていないものが多い」ことを示す。マイナスの大半（-4 級 5 件、-3 級 9 件)は設計のやり直しではなく **配線・防御・検証の追加** で解消可能であり、アーキテクチャレベルの手戻り（-5）は 1 件もない。改善の費用対効果は極めて高い状態にある。

---

## 特筆事項（抜粋）

### 最高評価項目（+4、9 件）

- RS256 JWT + JWKS 公開（`auth/lib/auth/token/keys.ex`）
- Argon2id + 体系的タイミング攻撃対策（`auth/lib/auth/password.ex`）
- リフレッシュトークン設計（ハッシュ保存・スライディング失効・越境保護）
- FormulaGraph コンパイラ / バイトコード契約の Elixir–Rust 同期
- ゲームループのバックプレッシャー設計（整合性維持とドロップの区別）
- 3 トランスポート統一メッセージ収束
- panic しない NIF エラー境界
- golden E2E protobuf 契約テスト / クレート分離とセキュリティ境界
- mix alchemy.ci 単一エントリ CI

### 最重要指摘（-4、5 件）

- 連合（ActivityPub 型 federation）の実装ゼロ
- auth のレート制限完全欠如
- `:main` 以外のルームでゲームループ未駆動
- 補間・予測の未配線（実質 20Hz 表示）
- OpenXR 完全スタブ（VR が動作しない）

### 発見した実バグ（-3 級）

- **Formula VM `binary_div`**: `as_i32()` が F32 でも Some を返すため float 除算パスが到達不能。`5.0 / 2.0` が `I32(2)` を返す（`engine/rust/nif/src/formula/vm.rs`）
- **Authenticate プラグ**: Joken 構造体エラーで WithClauseError → 500（`auth/lib/auth_web/plugs/authenticate.ex`）
- **i32::MIN / -1**: VM の整数除算がオーバーフローパニック（エラータプル契約の破れ）

---

## 検証記録

- `mix alchemy.ci`（engine, main ブランチ）: **ALL PASSED**（cargo fmt / clippy -D warnings / cargo test -p nif / mix format / credo --strict / mix test）
- auth ローカルテスト: Windows 環境の C コンパイラ（nmake）不在により argon2_elixir がビルド不可。GitHub Actions（ubuntu + Postgres 16 service）ではテスト実行が構成されていることを ci.yml で確認
- 主要指摘（除算バグ、非 :main ルーム、flow_runner(:main)、plug エラー経路、SECRET_KEY_BASE、interp 未使用、publisher 毎 put 宣言、topologies: []、auth CI 構成）は評価者が該当ソースを直接読んで確認済み
