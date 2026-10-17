# CI/CD ガイド

スーパープロジェクト（このリポジトリ）に GitHub Actions のワークフローは無い。
検証は子リポジトリ 4 本がそれぞれ持つ。`mix alchemy.ci` は world-server だけを見る。

---

## 子リポジトリのワークフロー

### world-server（`.github/workflows/ci.yml`）

すべての push と pull request で実行する。

| ジョブ | 内容 |
|:---|:---|
| `Rust — fmt & clippy` | `cargo fmt --all -- --check` と `cargo clippy --workspace -- -D warnings`（`rust/Cargo.toml`） |
| `Rust — unit tests` | `cargo test -p nif` |
| `Protobuf — codegen up to date` | `mix alchemy.gen.proto` のあと生成物を `mix format` し、`git diff --exit-code` |
| `Elixir — compile & credo` | `mix compile --warnings-as-errors`、`mix format --check-formatted`、`mix credo --strict` |
| `Elixir — mix test (with NIF)` | `mix test` |

`cargo test -p physics` と `cargo bench` は無い。physics クレートは撤去済みである。

### client（`.github/workflows/ci.yml`）

すべての push と pull request で実行する。

| ジョブ | 内容 |
|:---|:---|
| `Rust — fmt & clippy` | `cargo fmt --all -- --check` と `cargo clippy --workspace -- -D warnings` |
| `Rust — build app` | `cargo build -p app` |

`cargo test` はまだこのワークフローに無い。

### auth-server（`.github/workflows/ci.yml`）

`main` への push と pull request で実行する。Postgres 16 をサービスコンテナに使う。

| ジョブ | 内容 |
|:---|:---|
| `test` | `mix format --check-formatted`、`mix compile --warnings-as-errors`、`mix credo --strict`、`mix ecto.create`、`mix ecto.migrate`、`mix test` |

### protocol（`.github/workflows/proto-verify.yml`）

`main` への push と、`main` 向けの pull request で実行する。

| ジョブ | 内容 |
|:---|:---|
| `proto-verify` | `protoc` で `proto/*.proto` を descriptor にコンパイルし、出力が空でないことを確認する |

---

## ローカルでの確認手順（world-server）

world-server のルートで、次のコマンドが GitHub Actions の Rust / Elixir ジョブに対応する。
protobuf 生成物の diff と、client / auth-server / protocol のワークフローは含まない。

```bash
mix alchemy.format          # フォーマット自動修正（Rust + Elixir）
mix alchemy.ci check        # 静的解析のみ（テストなし）
mix alchemy.credo           # Elixir 静的解析のみ
mix alchemy.ci              # world-server の全チェック（テスト含む）
```

| コマンド | 用途 |
|:---|:---|
| `mix alchemy.format` | Rust + Elixir のフォーマット自動修正 |
| `mix alchemy.format --check` | フォーマット差分チェックのみ（変更なし） |
| `mix alchemy.ci check` | fmt + clippy + deps.get + format + credo（テストなし） |
| `mix alchemy.ci rust` | Rust のみ（fmt + clippy + `cargo test -p nif`） |
| `mix alchemy.ci elixir` | Elixir のみ（deps.get + format + credo + `mix test --warnings-as-errors`） |
| `mix alchemy.ci` | 上記の Rust と Elixir |
| `mix alchemy.credo` | `mix credo --strict` 単体実行 |

`mix alchemy.ci` の Elixir テストは `MIX_ENV=test` で `mix test --warnings-as-errors` を実行する。コンパイルの警告は、このテスト起動に含める。

---

## Credo（world-server の `.credo.exs`）

`strict: true`。`checks` に書かれているのは次だけである。

| ルール | 設定 |
|:---|:---|
| `Nesting` | `max_nesting: 4` |
| `CyclomaticComplexity` | `max_complexity: 10` |
| `AliasUsage` | 無効（`false`） |
| `TagTODO` | 無効（`false`） |
