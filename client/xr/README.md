# xr

OpenXR セッションと VR 入力管理。**クライアント側**で使用。

## 責務

- OpenXR セッション初期化、フレームループ管理
- アクションマッピング（トリガー、スティック等の正規化）
- platform/ でランタイム固有の初期化（SteamVR, Oculus, Monado 等）

## データフロー

1. VR 入力（手の位置、ボタン）を取得
2. `shared::types` の形式に変換
3. `network` 経由で Zenoh により Elixir サーバーへ送信

## 依存

依存なし（基底クレート）。`nif` には依存しない。
