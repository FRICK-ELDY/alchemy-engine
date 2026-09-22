# AlchemyEngine（スーパープロジェクト）

> A platform for worlds. You bring the rules.

本リポジトリは **ドキュメント／計画の正本**と、実行リポジトリを束ねる **Git スーパープロジェクト**です。

| 置き場 | 内容 |
|:---|:---|
| [`.workspace/`](.workspace/) | ビジョン・アーキテクチャ・評価・実施計画 |
| [`world-server/`](https://github.com/FRICK-ELDY/alchemy-world-server) | 世界サーバー（Elixir / Rust）の実行コード（submodule → リポ名は `alchemy-world-server`） |
| [`protocol/`](https://github.com/FRICK-ELDY/alchemy-protocol) | ワイヤ契約 `.proto`（submodule → リポ名は `alchemy-protocol`）。**再生成・閲覧用**。日常ビルドの必須入力ではない |

実行コードのビルド・テスト・CI の正本は **[alchemy-world-server](https://github.com/FRICK-ELDY/alchemy-world-server)** です。ワイヤ契約の SSoT は [alchemy-protocol](https://github.com/FRICK-ELDY/alchemy-protocol)（推奨ピンは [protocol-lock.md](.workspace/0_docs/protocol-lock.md)）。子は **生成物をコミット**してビルドし、親レイアウトは参照しません。

詳細な設計思想は [ビジョン](.workspace/0_docs/vision.md) と [実施計画](.workspace/2_todo/alchemy-engine-superproject-and-world-server-plan.md) を参照してください。

## Clone

```bash
git clone --recurse-submodules git@github.com:FRICK-ELDY/alchemy-engine.git
cd alchemy-engine
```

すでに clone 済みの場合:

```bash
git submodule update --init --recursive
```

## 開発（コード）

### Windows: `bin/*.bat`（推奨・暫定）

親からそのまま実行できます（内部で `world-server/` に移動します）。`alchemy-launcher` 導入までの暫定入口です。

```bat
rem 初回
bin\deps.get.bat
bin\setup.bat

rem 起動（ターミナルを 3 つ）
bin\router.bat
bin\server.bat
bin\client.bat
```

詳細は [bin/README.md](bin/README.md) を参照。

### 手動（cwd = world-server）

```bash
cd world-server
mix deps.get
mix alchemy.setup
# 別ターミナルで:
mix alchemy.router
mix alchemy.server
mix alchemy.client
```

手順の詳細は submodule 内の `development.md` を参照してください。コードだけ欲しい場合は [alchemy-world-server](https://github.com/FRICK-ELDY/alchemy-world-server) を直接 clone しても構いません。

## License

Eclipse Public License 2.0 (EPL-2.0) — 各子リポジトリも同様です。
