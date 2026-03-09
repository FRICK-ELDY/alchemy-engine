# bin 廃止・Mix タスク移行実施プラン

> 対象: [bin/](../bin/) 配下のバッチスクリプト
> 成果物: `lib/mix/tasks/` 配下の Mix カスタムタスク

---

## 1. 現行 bin スクリプト一覧


| スクリプト                                               | 役割                                                                                    |
| --------------------------------------------------- | ------------------------------------------------------------------------------------- |
| [bin/build.bat](../bin/build.bat)                   | `cargo build -p client_*`（desktop/web/android/ios × debug/release）                    |
| [bin/ci.bat](../bin/ci.bat)                         | Rust fmt/clippy/test + Elixir compile/format/credo/test。filter: rust / elixir / check |
| [bin/credo.bat](../bin/credo.bat)                   | `mix credo`（strict / suggest / explain）                                               |
| [bin/format.bat](../bin/format.bat)                 | `cargo fmt` + `mix format`。filter: rust / elixir / check                              |
| [bin/test.bat](../bin/test.bat)                     | `cargo test -p physics` + `mix test`。filter: rust / elixir / cover                    |
| [bin/windows_client.bat](../bin/windows_client.bat) | クライアント exe 起動（connect, room 指定可）                                                      |


---

## 2. client_desktop 廃止・app への統一（前提作業）

**現行構成**: [native/app/Cargo.toml](../../native/app/Cargo.toml) は `[[bin]] name = "app"` のみ。`client_desktop` は旧クレート名で、[native-restructure-migration-plan.md](native-restructure-migration-plan.md) により `app/` に統合済み。ワークスペースに `client_desktop` パッケージは存在しない。

### 2.1 修正対象（コード・設定）


| ファイル                                                         | 現状                                     | 修正内容                                                      |
| ------------------------------------------------------------ | -------------------------------------- | --------------------------------------------------------- |
| [native/.cargo/config.toml](../../native/.cargo/config.toml) | `--bin client_desktop` のエイリアス          | `--bin app` に統一。コメントも修正                                   |
| [bin/windows_client.bat](../bin/windows_client.bat)          | `-p app --bin client_desktop`          | `-p app` に変更（bin は app のみなので省略可、または `--bin app`）          |
| [bin/build.bat](../bin/build.bat)                            | `-p client_%CLIENT%`（client_desktop 等） | `-p app` に統一。`--desktop` のみ現状対応。web/android/ios は将来対応時に追加 |


### 2.2 ドキュメント・コメントの整理

以下は概念説明（「デスクトップクライアント exe」の別名として）として `client_desktop` を使っている場合がある。`app` または「デスクトップクライアント」に統一するか、文脈に応じて判断。


| カテゴリ      | ファイル例                                                                                       | 方針                                 |
| --------- | ------------------------------------------------------------------------------------------- | ---------------------------------- |
| コマンド・パス   | [development.md](../../development.md), [docs/cross-compile.md](../cross-compile.md)        | `cargo run -p app` / `app.exe` に統一 |
| アーキテクチャ説明 | [docs/architecture/overview.md](../architecture/overview.md), [docs/architecture/rust/](..) | 「app（デスクトップクライアント exe）」等に統一可能      |
| 計画・手順     | [docs/plan/improvement-plan.md](improvement-plan.md) 等                                      | 実コマンド・パスは `app` に統一                |


**ランチャー**: [native/tools/launcher/src/main.rs](../../native/tools/launcher/src/main.rs) は既に `exe_name("app")` と `-p app` を使用しており修正不要。

### 2.3 削除不要（概念・過去参照）

- [docs/plan/env-and-serialization-migration-plan.md](env-and-serialization-migration-plan.md) 等の過去プラン内の `client_desktop` 表記は履歴として残す
- [docs/architecture/rust/desktop_client.md](../architecture/rust/desktop_client.md) は「client_desktop」をクライアントの概念名として使っている場合、ファイル名・内容を「app / デスクトップクライアント」に合わせて更新を検討

---

## 3. 新規 Mix タスク仕様

### 3.1 一覧


| タスク                    | 対応 bin             | 概要                                      |
| ---------------------- | ------------------ | --------------------------------------- |
| `mix alchemy.clean`    | （新規）               | `_build`、`deps`、`native/target` を削除     |
| `mix alchemy.setup`    | （新規）               | `mix deps.get` + `mix compile`          |
| `mix alchemy.launcher` | （新規）               | `cargo run -p launcher`                 |
| `mix alchemy.build`    | build.bat          | `-p app` で desktop ビルド（debug/release）   |
| `mix alchemy.ci`       | ci.bat             | CI 相当（filter: rust / elixir / check）    |
| `mix alchemy.format`   | format.bat         | Elixir + Rust 同時フォーマット                  |
| `mix alchemy.credo`    | credo.bat          | `mix credo`（strict / suggest / explain） |
| `mix alchemy.test`     | test.bat           | Elixir + Rust 同時テスト                     |
| `mix alchemy.router`   | （新規）               | `zenohd` 起動                             |
| `mix alchemy.server`   | （新規）               | `mix run --no-halt`                     |
| `mix alchemy.client`   | windows_client.bat | クライアント起動（`cargo run -p app --`）         |


### 3.2 各タスクの挙動

**mix alchemy.build**

- 現行構成に合わせて `-p app` でビルド
- `--desktop`（default）/ `--debug`（default）/ `--release`
- `--web` / `--android` / `--ios` は将来対応時に追加

**mix alchemy.client**

- `cargo run --manifest-path native/Cargo.toml -p app -- --connect ... --room ...`
- オプション: `--connect`, `--room`（デフォルト: tcp/127.0.0.1:7447, main）

その他は前版プランと同様。

---

## 4. 実施フェーズ

### フェーズ 0: client_desktop 整理（先に実施）

1. `native/.cargo/config.toml` を `app` に統一
2. `bin/build.bat` を `-p app` に修正
3. `bin/windows_client.bat` を `-p app` に修正
4. [development.md](../../development.md)、[docs/cross-compile.md](../cross-compile.md) のコマンド・パスを `app` に統一

### フェーズ 1: 基盤タスク

1. `lib/mix/tasks/` を用意（適切な app またはルート）
2. `mix alchemy.clean`, `setup`, `format`, `test`, `build`, `ci`

### フェーズ 2: 起動系タスク

1. `mix alchemy.launcher`, `router`, `server`, `client`

### フェーズ 3: 統合・廃止

1. `mix alchemy.credo`
2. `bin/` ディレクトリの削除、ドキュメント更新

---

## 5. bin の削除

- `bin/` ディレクトリは削除する（ラッパーは残さない）
- [development.md](../../development.md)、[README.md](../../README.md)、[docs/cross-compile.md](../cross-compile.md) を `mix alchemy.`* ベースに更新
- `mix alchemy.up` は不要（launcher で router / server / client の起動を管理するため）

---

## 6. 確認事項

- **app に統一**: ビルド成果物・コマンドはすべて `-p app` / `app` に統一
- **ci.bat vs test.bat**: ci.bat は `-p nif`、test.bat は `-p physics`。CI に合わせて `-p nif` を採用

