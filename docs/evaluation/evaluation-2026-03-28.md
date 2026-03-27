# AlchemyEngine — 総合評価レポート（2026-03-28）

> 評価日: 2026年3月28日  
> 評価対象: リポジトリ作業ツリー（main 追従）  
> 評価者: Cursor AI Agent  
> 評価ルール: `.cursor/rules/evaluation.mdc` に基づく

---

## エグゼクティブサマリー

AlchemyEngine は、Elixir（OTP・コンテンツ SSoT）と Rust（NIF 物理・wgpu・Zenoh クライアント）を組み合わせた「ワールド基盤 + コンテンツ」型のゲームエンジンである。`Contents.Behaviour.Content` と `Core.Component` によるライフサイクル分離、`Contents.Events.Game` と NIF の協調、Phoenix / UDP / Local の多層ネットワークが、個人／小規模チーム規模のプロジェクトとしては高い完成度を示している。

**総合スコア: +163 / -81 = +82点**

前回（2026-03-23）からの主な変化は、**GitHub Actions に `pull_request` と `proto-verify` が組み込まれていることの反映**（プラス点の追加・該当マイナス点の解消）、および **ローカル CI と GHA の差分（proto のローカル未統合）を新たにマイナス点化**したことである。

---

## 検証実施状況

| 項目 | 結果 |
|:---|:---|
| `mix compile --warnings-as-errors` | **PASS** |
| `mix format --check-formatted` | **PASS** |
| `mix credo --strict` | **PASS**（206 ファイル、問題なし） |
| `mix test` | **PASS**（core 45 + network 59 + contents 75 = 179、server はテストなし） |
| `cargo fmt` / `cargo clippy -D warnings` / `cargo test -p nif` | **PASS**（nif ユニット 36 件） |
| `mix alchemy.ci` | **ALL PASSED** |
| 実行環境 | Windows 10, PowerShell |

### 直接検証した内容

- `.github/workflows/ci.yml` に `pull_request:` および `proto-verify` ジョブが存在することを確認した。
- `Contents.Behaviour.Content` は `apps/contents/lib/behaviour/content.ex` に定義され、旧ドキュメントの `content_behaviour.ex` パスは現状と不一致であるため、評価ドキュメントを更新した。
- `docs/evaluation/specific-weaknesses.md` にあった「pull_request 未設定」は**解消済み**（ワークフローを確認）。
- `Contents.Scenes.Stack` の **専用ユニットテストは依然として存在しない**（`apps/**/*_test.exs` を grep で確認）。

---

## スコアサマリ

| カテゴリ | プラス | マイナス | 小計 |
|:---|:---:|:---:|:---:|
| **apps/core** | +18 | -8 | +10 |
| **apps/contents** | +18 | -11 | +7 |
| **apps/network** | +12 | -3 | +9 |
| **apps/server** | +3 | 0 | +3 |
| **native/shared** | +2 | -2 | 0 |
| **native/network** | +8 | -6 | +2 |
| **native/nif** | +35 | -2 | +33 |
| **native/render** | +11 | -10 | +1 |
| **native/audio** | +7 | 0 | +7 |
| **native/window** | +3 | -1 | +2 |
| **native/xr** | +1 | -3 | -2 |
| **native/app** | +4 | -2 | +2 |
| **横断（テスト・DX・可観測性・セキュリティ・CI）** | +41 | -34 | +7 |
| **合計** | **+163** | **-81** | **+82** |

詳細は以下を参照する。

- [specific-strengths.md](./specific-strengths.md)
- [specific-weaknesses.md](./specific-weaknesses.md)
- [specific-proposals.md](./specific-proposals.md)

---

## 前回評価（2026-03-23）からの変化

| 観点 | 状態 |
|:---|:---|
| `pull_request` トリガー | **設定済み**（前回評価時の記述は旧実態に基づく誤り） |
| `proto-verify` ジョブ | GHA に存在。プラス点として記録 |
| `mix alchemy.ci` | 本日 Windows で **ALL PASSED** を再確認 |
| `Contents.Scenes.Stack` / `Events.Game` の直接テスト | 依然として不足（マイナス点継続） |
| EntityParams の二重管理・network→render 依存 等 | 構造課題は継続（[specific-weaknesses.md](./specific-weaknesses.md) 参照） |

---

## 総括

総合 **+82**。CI は PR 時・protobuf 生成物の検証まで含め、リポジトリの品質ゲートとして強化されている。一方、`mix alchemy.ci` は GHA の `proto-verify` と同等の検証を含まない、ローカルとリモートのわずかな差分が残る。

引き続き **[improvement-plan.md](../../workspace/0_reference/improvement-plan.md)** に沿い、**SceneStack / Events.Game のユニットテスト**、**EntityParams の SSoT 化**、**ネットワーク層と描画層の依存整理**を優先すると、ビジョン（`docs/vision.md`）との整合と保守性がさらに上がる。
