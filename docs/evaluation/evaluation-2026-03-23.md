# AlchemyEngine — 総合評価レポート（2026-03-23）

> 評価日: 2026年3月23日  
> 評価対象: HEAD（main ブランチ相当）  
> 評価者: Cursor AI Agent  
> 評価ルール: `evaluation.mdc` に基づく

---

## エグゼクティブサマリー

AlchemyEngine は「Elixir（OTP）でゲームロジックを制御し、Rust（SoA/SIMD/wgpu）で演算・描画を処理する」というアーキテクチャを採用した個人製ゲームエンジンである。

**総合スコア: +161 / -82 = +79点**

前回評価（2026-03-10）からコードベースに大きな変更は見られない。`mix alchemy.ci` のエラーゼロ通過を**本評価日時点で再検証済み**（Windows / PowerShell 環境で全ジョブ PASS を確認）。

---

## 検証実施状況

| 項目 | 結果 |
|:---|:---|
| `mix alchemy.ci` 全体 | **ALL PASSED**（exit 0） |
| 実行環境 | Windows 10, PowerShell |
| 確認コマンド | `mix alchemy.ci`（cargo fmt / clippy / test, mix compile / format / credo / test） |

### 直接検証した内容

- **CI 実行**: `mix alchemy.ci` を実行し、ジョブ [A]〜[D] がすべて PASS することを確認
- **テスト存在確認**: `EventBus`・`SaveManager` のテストが `apps/core/test/` に存在することを確認
- **SceneStack・GameEvents テスト**: `apps/core/test/` 内に SceneStack・GameEvents のテストは**依然として存在しない**ことを確認
- **CI トリガー**: `.github/workflows/ci.yml` は `push` のみで、`pull_request` トリガーは**未設定**のまま

---

## スコアサマリ（前回評価を踏襲）

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
| **横断（テスト・DX・可観測性・セキュリティ）** | +39 | -34 | +5 |
| **合計** | **+161** | **-82** | **+79** |

詳細なプラス点・マイナス点・提案は以下を参照：

- [specific-strengths.md](./specific-strengths.md)
- [specific-weaknesses.md](./specific-weaknesses.md)
- [specific-proposals.md](./specific-proposals.md)

---

## 前回評価（2026-03-10）からの変化

| 観点 | 状態 |
|:---|:---|
| mix alchemy.ci | 継続してパス（本日再検証済み） |
| bin/ci.bat | 存在しない。プロジェクトは `mix alchemy.ci` をローカル CI として採用しており、同等の役割を果たしている |
| SceneStack・GameEvents テスト | 未整備のまま |
| pull_request トリガー | 未設定のまま |
| その他 | 顕著な変更なし |

---

## 総括

総合スコア **+79**。ローカル CI は安定して通過しており、品質保証の基盤は整っている。

引き続き、[improvement-plan.md](../task/improvement-plan.md) に従い、**pull_request トリガー追加**・**SceneStack・GameEvents テスト整備**・**EntityParams SSoT 化**を優先して進めることを推奨する。
