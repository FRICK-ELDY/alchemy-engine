# AlchemyEngine — 総合評価レポート（2026-03-08）

## 評価の概要

プロジェクト全体を技術評価層（apps/・native/）と横断評価層で評価した。コードを直接読み、`bin/ci.bat check` の実行でローカル CI 通過を確認済み。

---

## スコアサマリ

| カテゴリ | プラス | マイナス | 小計 |
|:---|:---:|:---:|:---:|
| **apps/core** | +7 | -1 | +6 |
| **apps/contents** | +6 | -4 | +2 |
| **apps/network** | +2 | 0 | +2 |
| **native/physics** | +9 | 0 | +9 |
| **native/nif** | +5 | -2 | +3 |
| **native/desktop_render** | +4 | 0 | +4 |
| **横断（DX・設計・CI・可観測性）** | +14 | -11 | +3 |
| **合計** | **+47** | **-18** | **+29** |

---

## 主なプラス点

1. **Elixir = SSoT / Rust = 実行層** の設計思想が vision.md と実装で一貫している
2. **ContentBehaviour / Component** によるコンテンツ抽象化とオプショナルコールバック設計
3. **SoA + SIMD** による物理演算の効率化とテストによる検証
4. **bin/ci.bat** によるローカル CI の整備とエラーゼロ前提
5. **EntityParams の外部注入** によるゲームバランス値の SSoT 化

---

## 主なマイナス点

1. **Contents.Scenes.Stack・Contents.Events.Game のテスト不足** — 中核ロジックの検証が不十分
2. **Diagnostics のコンテンツ固有知識** — `:enemies` / `:bullets` の直接参照
3. **create_world の NifResult 未対応** — NIF 設計の一貫性の欠如
4. **NIF パニック時の回復ロジック・分散フェイルオーバー未実装** — Elixir の耐障害性・分散の証明不足
5. **セーブ対象データの収集責務未定義** — Elixir 側状態がセーブに含まれない
6. **bin/ci.bat と CI yml の clippy スコープの差** — launcher の扱いの不整合

---

## 提案（0点）

- コンポーネントの `on_save` / `on_load` コールバック
- ContentBehaviour の `diagnostics/0` コールバック
- Contents.Scenes.Stack の ExUnit テスト、プロパティベーステスト、E2E テスト
- HudData の汎用化、render_interpolation のクライアント移行
- mix audit / cargo audit の CI 追加

詳細は [specific-proposals.md](./specific-proposals.md) を参照。

---

## 検証実施状況

| 項目 | 結果 |
|:---|:---|
| `bin/ci.bat check`（format + lint） | PASS（exit 0） |
| `bin/ci.bat` 全体 | PASS（exit 0） |
| コード直接確認 | apps/core, contents, network, native/physics, nif, desktop_render の主要ファイルを読み検証 |

---

## 総括

総合スコア **+29**。Rust 側の物理演算・NIF 設計・Elixir 側のビヘイビア設計は高水準。一方で、Elixir を選んだ理由である OTP 耐障害性・分散の証明が不足しているほか、テスト戦略とセーブ設計に改善余地が大きい。`docs/plan/reference/improvement-plan.md` に課題と改善方針が整理されているため、それを基に優先順位をつけて進めることを推奨する。
