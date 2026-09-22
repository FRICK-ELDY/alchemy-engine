# プロトコル（`.proto`）ロック

[alchemy-protocol](https://github.com/FRICK-ELDY/alchemy-protocol) の **推奨リビジョン**です。

| 層 | 役割 |
|:---|:---|
| **親 `protocol/`** | 閲覧・再生成用 submodule（ビルド必須ではない） |
| **`world-server/PROTOCOL_PIN`** | 実行リポの **真のビルド／再生成ピン**（R2: 未設定時は git fetch） |
| **生成物** | Elixir `*.pb.ex` は world-server にコミット。Rust はビルド時に pin から取得して prost 生成 |

| 項目 | 値 |
|:---|:---|
| **親内パス** | `protocol/` |
| **Git タグ** | `v0.1.2` |
| **コミット SHA** | `84278a8a6f51fe559263b36a1d5dae9c9a731504` |
| **タグ付きツリー** | [github.com/FRICK-ELDY/alchemy-protocol @ `v0.1.2`](https://github.com/FRICK-ELDY/alchemy-protocol/tree/v0.1.2) |
| **world-server ピンファイル** | `world-server/PROTOCOL_PIN`（上記と一致させる） |

## 親で `protocol/` を上げるとき

1. `protocol/` で目的のタグを checkout → 親で `git add protocol`  
2. **同時に** world-server 側で `PROTOCOL_PIN` を更新し、必要なら `mix alchemy.gen.proto` で Elixir 生成物を同一系統の変更で追従  
3. 本ファイルの表を更新  

## 再生成例

```bat
rem 明示（推奨・親一式）
set PROTO_ROOT=%CD%\protocol\proto
cd world-server
mix alchemy.gen.proto

rem または PROTO_ROOT 未設定で PROTOCOL_PIN に従い .proto-cache へ fetch
cd world-server
mix alchemy.gen.proto
```
