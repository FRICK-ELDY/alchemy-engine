# nif

Elixir NIF 用 Rust コード。サーバー側で BEAM VM と Rust を橋渡しする。

## 責務

- Rustler による NIF 関数露出
- **physics** 内包: 60Hz ゲームループ、剛体物理、衝突判定、Chase AI 等
- `audio` でゲーム内 SE/BGM 再生
- `shared` の型を参照

## 主要モジュール

- `lib.rs` — NIF エントリポイント
- `physics/` — 物理演算、GameWorld、ゲームループ
- `audio_sync` — 音同期（オーケストラ等）

## 依存

- `shared`
- `audio`

## 注意

XR には依存しない。VR 入力はクライアント `app` → `xr` → `network` 経由で Elixir へ送信する。
