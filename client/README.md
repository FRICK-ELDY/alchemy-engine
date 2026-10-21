# Alchemy Client

> VRAlchemy — desktop / XR client for [alchemy-world-server](https://github.com/FRICK-ELDY/alchemy-world-server)

Rust クライアント（wgpu / Zenoh）。ワイヤ契約は [alchemy-protocol](https://github.com/FRICK-ELDY/alchemy-protocol)（本リポは `PROTOCOL_PIN` + R2 git fetch）。

スーパープロジェクト [alchemy-engine](https://github.com/FRICK-ELDY/alchemy-engine) では submodule パス **`client/`** として取り込みます。

## Setup

```bash
git clone git@github.com:FRICK-ELDY/alchemy-client.git
cd alchemy-client
cargo build -p app
```

初回ビルド時、`PROTOCOL_PIN` に従い alchemy-protocol を `.proto-cache/` へ取得します（`PROTO_ROOT` で上書き可）。

## Run

前提: zenohd（`mix alchemy.router`）と world-server（`mix alchemy.server`）が起動済み。

```bash
cargo run -p app -- --connect tcp/127.0.0.1:7447 --room main
# アセット（リポ内 assets/ または --assets）
cargo run -p app -- --assets ./assets
```

親スーパープロジェクトからは `bin\client.bat` でも起動できます。

## License

Eclipse Public License 2.0 (EPL-2.0)
