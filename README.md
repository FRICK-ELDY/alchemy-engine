# AlchemyEngine

> A platform for worlds. You bring the rules.

**AlchemyEngine** は、**IEEE 754 binary64 の 3D 座標系**と、そこに存在するユーザーを保証するプラットフォームです。  
空間の上に何を置くか（コンテンツ）はクリエイターが決めます。

本リポジトリは実行コードの単一ソースではなく、**ドキュメント／計画の正本**と、実行リポジトリを束ねる **Git スーパープロジェクト**です。

| 読者 | まず見る場所 |
|:---|:---|
| 動かしたい | [Quick Start](#quick-start) |
| 設計・ビジョンを知りたい | [ビジョン](.workspace/0_docs/vision.md) |
| コードだけ欲しい | [alchemy-world-server](https://github.com/FRICK-ELDY/alchemy-world-server) / [alchemy-client](https://github.com/FRICK-ELDY/alchemy-client) |

**Status:** 開発中（実験的）。API・レイアウト・起動手順は変わり得ます。

## Highlights

- **IEEE 754 binary64 の 3D 空間** — 単一原点の直交座標
- **Elixir = ドメインの SSoT** — 権威ある状態・ルール・コンテンツ定義は Elixir（`contents`）が持つ
- **Rust = 実行・体感** — サーバー NIF・クライアント描画／入力／予測。コンテンツのルールはハードコードしない
- **Zenoh 同期** — 複数ユーザーが同じ空間を共有するネットワーク基盤
- **コンテンツはコンポーネント** — エンジンは「敵・武器・スコア」を知らない。クリエイターが持ち込む

詳細な保証範囲は [ビジョン](.workspace/0_docs/vision.md) を参照してください。

## リポジトリ構成

| 置き場 | 内容 |
|:---|:---|
| [`.workspace/`](.workspace/) | ビジョン・アーキテクチャ・評価・実施計画（ドキュメント正本） |
| [`world-server/`](https://github.com/FRICK-ELDY/alchemy-world-server) | 世界サーバー（Elixir / Rust NIF）— submodule → `alchemy-world-server` |
| [`client/`](https://github.com/FRICK-ELDY/alchemy-client) | デスクトップ／XR クライアント（Rust）— submodule → `alchemy-client` |
| [`auth-server/`](https://github.com/FRICK-ELDY/alchemy-auth-server) | ユーザー認証 API — submodule → `alchemy-auth-server` |
| [`protocol/`](https://github.com/FRICK-ELDY/alchemy-protocol) | ワイヤ契約 `.proto`（再生成・閲覧用）— submodule → `alchemy-protocol` |

実行コードのビルド・テスト・CI の正本は各子リポジトリです。  
ワイヤ契約の SSoT は [alchemy-protocol](https://github.com/FRICK-ELDY/alchemy-protocol)（推奨ピンは [protocol-lock.md](.workspace/0_docs/protocol-lock.md)）。  
子は **生成物／`PROTOCOL_PIN`** でビルドし、親レイアウトは参照しません。

## Quick Start

### Clone

```bash
git clone --recurse-submodules git@github.com:FRICK-ELDY/alchemy-engine.git
cd alchemy-engine
```

すでに clone 済みの場合:

```bash
git submodule update --init --recursive
```

### 前提条件

| 項目 | 目安 |
|:---|:---|
| OS | Windows（`bin/*.bat` 推奨。他 OS は手動手順） |
| Elixir / Mix | `world-server` の README に従う |
| Rust / Cargo | `client` の README に従う |
| zenohd | `cargo install eclipse-zenoh` など、PATH に通す |

### Windows: `bin/*.bat`（推奨・暫定）

親からそのまま実行できます（内部で submodule に移動します）。`alchemy-launcher` 導入までの暫定入口です。

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

### 手動（他 OS・デバッグ用）

```bash
# サーバー
cd world-server
mix deps.get
mix alchemy.setup
# 別ターミナルで:
mix alchemy.router
mix alchemy.server

# クライアント（別ターミナル）
cd client
cargo run -p app -- --connect tcp/127.0.0.1:7447 --room main
```

手順の詳細は各 submodule 内の README / `development.md` を参照してください。

## ドキュメント

| 文書 | 内容 |
|:---|:---|
| [ビジョン](.workspace/0_docs/vision.md) | 何を保証し、何を保証しないか |
| [protocol-lock.md](.workspace/0_docs/protocol-lock.md) | `.proto` の推奨ピン |
| [実施計画](.workspace/2_todo/alchemy-engine-superproject-and-world-server-plan.md) | スーパープロジェクトと world-server の計画 |
| [`.workspace/`](.workspace/) | backlog / todo / done・参照メモ |
| [bin/README.md](bin/README.md) | 親からの起動ラッパ |

## License

Eclipse Public License 2.0 (EPL-2.0) — 各子リポジトリも同様です。  
全文は [LICENSE](LICENSE) を参照してください。
