# AlchemyEngine（スーパープロジェクト）

> A platform for worlds. You bring the rules.

本リポジトリは **ドキュメント／計画の正本**と、実行リポジトリを束ねる **Git スーパープロジェクト**です。

| 置き場 | 内容 |
|:---|:---|
| [`.workspace/`](.workspace/) | ビジョン・アーキテクチャ・評価・実施計画 |
| [`alchemy-world-server/`](https://github.com/FRICK-ELDY/alchemy-world-server) | 世界サーバー（Elixir / Rust）の実行コード（submodule） |

実行コードのビルド・テスト・CI の正本は **[alchemy-world-server](https://github.com/FRICK-ELDY/alchemy-world-server)** です。ワイヤ契約は各子が [alchemy-protocol](https://github.com/FRICK-ELDY/alchemy-protocol) を `3rdparty` / `deps` の git タグで固定します（親レイアウトは参照しません）。

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

```bash
cd alchemy-world-server
mix deps.get
mix alchemy.setup
mix alchemy.server
```

手順の詳細は submodule 内の `development.md` を参照してください。コードだけ欲しい場合は [alchemy-world-server](https://github.com/FRICK-ELDY/alchemy-world-server) を直接 clone しても構いません。

## License

Eclipse Public License 2.0 (EPL-2.0) — 各子リポジトリも同様です。
