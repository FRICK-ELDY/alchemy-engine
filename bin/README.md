# bin/（スーパープロジェクト用ラッパ）

親リポジトリに `mix.exs` はないため、ここにある `.bat` は **`world-server/` に移動してから** `mix` を実行する薄い入口です。

旧モノレポ時代の `bin/`（ビルド／CI ロジック本体）とは別物です。ロジックの正本は引き続き `world-server` 内の `mix alchemy.*` です。将来の `alchemy-launcher` が揃うまでの暫定手段です。

| スクリプト | 実体 |
|:---|:---|
| `deps.get.bat` | `mix deps.get` |
| `setup.bat` | `mix alchemy.setup`（deps.get + compile） |
| `router.bat` | `mix alchemy.router`（zenohd） |
| `server.bat` | `mix alchemy.server` |
| `client.bat` | `mix alchemy.client`（引数はそのまま転送） |

## 使い方

初回（1 ターミナル）:

```bat
bin\deps.get.bat
bin\setup.bat
```

起動（別ターミナルを 3 つ）:

```bat
bin\router.bat
bin\server.bat
bin\client.bat
```

前提: `git submodule update --init --recursive` 済み、Elixir / Rust / `zenohd`（`cargo install eclipse-zenoh`）が PATH にあること。
