# CI/CD ガイド

## CI パイプライン（GitHub Actions）

`.github/workflows/ci.yml` に定義。すべての push / main への PR で自動実行。

| ジョブ | 内容 | 実行条件 |
|:---|:---|:---|
| `Rust — fmt & clippy` | `cargo fmt --check` + `cargo clippy -D warnings` | 全 push / PR |
| `Rust — unit tests` | `cargo test -p physics` | 全 push / PR |
| `Elixir — compile & credo` | `mix compile --warnings-as-errors` + `mix format --check-formatted` + `mix credo --strict` | 全 push / PR |
| `Elixir — mix test (with NIF)` | `mix test`（NIF ビルド込み） | 全 push / PR |
| `Rust — bench regression` | `cargo bench -p physics`（前回比 +10% 超でブロック） | `main` push のみ |

---

## ローカルでの確認手順

コミット前に以下のコマンドで CI と同等のチェックを実行できます。

```bash
mix alchemy.format          # フォーマット自動修正（Rust + Elixir）
mix alchemy.ci check        # 静的解析のみ（高速、テストなし）
mix alchemy.credo           # Elixir 静的解析のみ
mix alchemy.ci              # 全チェック（テスト含む）
```

| コマンド | 用途 |
|:---|:---|
| `mix alchemy.format` | Rust + Elixir のフォーマット自動修正 |
| `mix alchemy.format --check` | フォーマット差分チェックのみ（変更なし） |
| `mix alchemy.ci check` | fmt + clippy + compile + format + credo（テストなし） |
| `mix alchemy.ci rust` | Rust のみ（fmt + clippy + test） |
| `mix alchemy.ci elixir` | Elixir のみ（compile + format + credo + test） |
| `mix alchemy.ci` | 全ジョブ実行 |
| `mix alchemy.credo` | `mix credo --strict` 単体実行 |

---

## Credo 除外ルール（`.credo.exs`）

### 閾値を緩和しているルール

| ルール | デフォルト | 本プロジェクト | 理由 |
|:---|:---:|:---:|:---|
| `CyclomaticComplexity` | 9 | **15** | `Contents.Events.Game` / `SaveManager`（削除済み）は複数の分岐を持つ状態機械だった。IP-03 の分解完了まで暫定緩和 |
| `Nesting` | 2 | **4** | SoA パターンの物理演算ループや NIF ブリッジで深いネストが構造上必要 |
| `AliasUsage` | 1回以上 | **3回以上** | 短命な参照に alias を強制するとかえって可読性が下がるため |

### 無効化しているルール

| ルール | 理由 |
|:---|:---|
| `UnlessWithElse` | ゲームロジックの早期リターンパターンで `unless ... else` を許容 |
| `WithClauses` | NIF 呼び出しシーケンスで可読性のために使用。IP-03 の `NifCoordinator` 分離後に再評価 |

### Credo デフォルト無効（opt-in）のルール

Credo 本体がデフォルト無効としている実験的・論争的なルールは本プロジェクトでも無効のままにしています。

- `DuplicatedCode` — 誤検知が多い
- `Specs` — `@spec` は現時点で必須としない
- `StrictModuleLayout` — モジュール内の定義順序を強制しない
- `SinglePipe` — 単一パイプの `|>` を禁止しない
- `VariableRebinding` — 変数の再束縛を禁止しない
