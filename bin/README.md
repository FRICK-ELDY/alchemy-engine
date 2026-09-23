# bin/（スーパープロジェクト用ラッパ）

親リポジトリに `mix.exs` はないため、ここにある `.bat` は各 submodule に移動してからコマンドを実行する薄い入口です。

| スクリプト | cwd | 実体 |
|:---|:---|:---|
| `deps.get.bat` | `world-server/` | `mix deps.get` |
| `setup.bat` | `world-server/` | `mix alchemy.setup` |
| `router.bat` | `world-server/` | `mix alchemy.router`（zenohd） |
| `server.bat` | `world-server/` | `mix alchemy.server` |
| `client.bat` | `client/` | `cargo run -p app -- …` |

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

前提: `git submodule update --init --recursive` 済み、Elixir / Rust / `zenohd`（`cargo install zenohd`）が PATH にあること。
