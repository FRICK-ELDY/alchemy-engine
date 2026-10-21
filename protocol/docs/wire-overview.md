# ワイヤ概要（Wire overview）

本リポジトリの **`proto/*.proto`** は、サーバーとクライアント等が共有する **Protobuf ペイロード**の契約です（UDP 外枠や Phoenix の JSON など **別形式**は別の SSoT になります）。

## 現行の主経路（要約）

- **Zenoh**: フレームは `alchemy.render.RenderFrame`（`render_frame.proto`）、入力は `alchemy.input`（`input_events.proto`）など。キー表式・トピックの詳細はエンジン側の **[zenoh-protocol-spec.md](https://github.com/FRICK-ELDY/alchemy-engine/blob/main/docs/architecture/zenoh-protocol-spec.md)** を参照してください。
- **歴史と経路の整理**: **[network-protocol-current.md](https://github.com/FRICK-ELDY/alchemy-engine/blob/main/docs/architecture/network-protocol-current.md)**

## 本ドキュメントの位置づけ

詳細な契約記述の一部は、移行完了まで **alchemy-engine の `docs/architecture/`** に残る場合があります。本ファイルは **このリポジトリをクローンした人向けの入口**として、上記へのリンクを維持します。
