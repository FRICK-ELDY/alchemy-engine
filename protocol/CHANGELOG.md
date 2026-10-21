# Changelog

本ファイルに、スキーマの**破壊的変更**と**リリース単位のまとめ**を記載します。

## [1.0.0] - 2026-10-10

### Changed

- `RenderFrame` の空間量を proto3 `float`（binary32）から `double`（IEEE 754 binary64）に変更した。対象は描画コマンドの位置とワールド寸法、カメラの offset / eye / target / up / near / far、メッシュ頂点の `position`、UI の `world_x` / `world_y` / `world_z`。フィールド番号は維持する。
- 色、UV、アルファ、`fov_deg`、UI のピクセル量は `float` のまま。

旧 `v0.1.x` のクライアントとはワイヤ非互換である。

## [0.1.1] - 2026-04-22

### Changed

- `README.md`: Git submodule の配置例を **`vendor/` から `3rdparty/`** に更新（alchemy-engine 側の既定レイアウトと一致）。

## [0.1.0] - 2026-04-22

### Added

- 初回: `proto/` ツリー全体を [alchemy-engine](https://github.com/FRICK-ELDY/alchemy-engine) のワーキングツリーからインポート（移設元 git 短縮ハッシュ: **`a8464e7`**）。
- `README.md` / `CONTRIBUTING.md` / `docs/wire-overview.md` / CI（`protoc` によるコンパイル検証）。
