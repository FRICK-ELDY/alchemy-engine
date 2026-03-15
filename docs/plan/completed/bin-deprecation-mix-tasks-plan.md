# bin 廃止・Mix タスク移行実施プラン

> 作成日: 2026-03 頃
> 完了日: 2026-03-15
> 対象: [bin/](../../../bin/) 配下のバッチスクリプト（廃止済み）
> 成果物: `apps/core/lib/mix/tasks/` 配下の Mix カスタムタスク
>
> **実施結果**: フェーズ 0〜3 を完了。bin/ ディレクトリを削除し、すべての機能を `mix alchemy.*` タスクに移行済み。

---

## 1. 実施前の bin スクリプト一覧（参考）


| スクリプト                                               | 役割                                                                                    |
| --------------------------------------------------- | ------------------------------------------------------------------------------------- |
| bin/build.bat                                       | `cargo build -p client_*`（desktop/web/android/ios × debug/release）                    |
| bin/ci.bat                                          | Rust fmt/clippy/test + Elixir compile/format/credo/test。filter: rust / elixir / check |
| bin/credo.bat                                       | `mix credo`（strict / suggest / explain）                                               |
| bin/format.bat                                      | `cargo fmt` + `mix format`。filter: rust / elixir / check                              |
| bin/test.bat                                        | `cargo test -p physics` + `mix test`。filter: rust / elixir / cover                    |
| bin/windows_client.bat                              | クライアント exe 起動（connect, room 指定可）                                                      |


---

## 2. client_desktop 廃止・app への統一（実施済み）

**現行構成**: [native/app/Cargo.toml](../../../native/app/Cargo.toml) は `[[bin]] name = "app"` のみ。`client_desktop` は旧クレート名で、[native-restructure-migration-plan.md](../backlog/native-restructure-migration-plan.md) により `app/` に統合済み。

### 実施内容

- bin/ 配下のスクリプトはすべて削除
- [development.md](../../../development.md)、[README.md](../../../README.md)、[docs/cross-compile.md](../../cross-compile.md) を `mix alchemy.*` と `-p app` に統一済み
- [docs/architecture/rust/desktop_client.md](../../architecture/rust/desktop_client.md) は（※ docs からの相対パス）「app」に更新済み

---

## 3. 実装済み Mix タスク

### 3.1 一覧


| タスク                    | 概要                                      |
| ---------------------- | --------------------------------------- |
| `mix alchemy.clean`    | `_build`、`deps`、`native/target` を削除     |
| `mix alchemy.setup`    | `mix deps.get` + `mix compile`          |
| `mix alchemy.launcher` | `cargo run -p launcher`                 |
| `mix alchemy.build`    | `-p app` で desktop ビルド（debug/release）   |
| `mix alchemy.ci`       | CI 相当（filter: rust / elixir / check）    |
| `mix alchemy.format`   | Elixir + Rust 同時フォーマット                  |
| `mix alchemy.credo`    | `mix credo`（strict / suggest / explain） |
| `mix alchemy.test`     | Elixir + Rust 同時テスト                     |
| `mix alchemy.router`   | `zenohd` 起動                             |
| `mix alchemy.server`   | `mix run --no-halt`                     |
| `mix alchemy.client`   | クライアント起動（`cargo run -p app --`）         |

### 3.2 配置

`apps/core/lib/mix/tasks/` 配下に実装。

### 3.3 CI について

- `mix alchemy.ci` の Rust テストは `-p nif` を採用（CI に合わせて実施済み）

---

## 4. 実施フェーズ（完了）

- **フェーズ 0**: client_desktop 整理 ✅
- **フェーズ 1**: 基盤タスク（clean, setup, format, test, build, ci）✅
- **フェーズ 2**: 起動系タスク（launcher, router, server, client）✅
- **フェーズ 3**: credo 追加、bin/ 削除、ドキュメント更新 ✅

---

## 5. 将来対応（未実施）

以下の項目は将来対応として [bin-deprecation-mix-tasks-future.md](../reference/bin-deprecation-mix-tasks-future.md) に記載。

- `mix alchemy.build` の `--web` / `--android` / `--ios` オプション
