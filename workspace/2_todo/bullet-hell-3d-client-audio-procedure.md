# BulletHell3D 被ダメージ SE（クライアント再生）— 実施手順

## 目的

- サーバー（Elixir / contents）は **音源の識別子としての文字列（v1: リポジトリ相対パス）** のみを `RenderFrame` に載せる。
- クライアント（Rust）は受信したキューを **ローカル `ASSETS_PATH` 等で解決**し、`audio` クレート（rodio）で再生する。

## 非目的（v1）

- `https://` 等のリモート URL からの取得・再生（将来 `AudioCommand` 拡張で対応可能）。
- サーバー側での音声デコード・ストリーミング。

## Definition of Done

- [x] `alchemy-protocol` の `RenderFrame.audio_cues` がワイヤに載る。
- [x] BulletHell3D で被ダメージ時のみキューに 1 要素が入り、送信後 `pending_audio_urls` がクリアされる。
- [x] Rust クライアントが新フレーム受信時のみ SE を鳴らし、**前フレームの再利用描画では再再生しない**。
- [x] 相対パスに `..` を含む等の不正値はクライアントで拒否する。

## 依存・submodule

1. スキーマ変更は **`3rdparty/alchemy-protocol/proto/render_frame.proto`**（上流 PR 後に submodule 更新）。
2. 本リポで生成物を揃える: ルートで `mix alchemy.gen.proto`（`PROTO_ROOT` で別パスも可。詳細は `development.md`）。
3. Rust は `cargo build -p render_frame_proto` 等で `prost` 再生成（Mix タスク内でも `network` ビルドが走る）。

## Elixir 変更の要点

| ファイル | 内容 |
|:---|:---|
| `apps/contents/lib/contents/frame_encoder.ex` | `encode_frame/6`（省略時 `[]`）で `audio_cues` を struct に渡す |
| `apps/contents/lib/components/category/rendering/render.ex` | `pending_audio_urls` を読み encode に渡し、送信後に Stack で `[]` に戻す |
| `apps/contents/lib/contents/bullet_hell_3d/playing.ex` | `init` に `pending_audio_urls`、無敵外で `hp` が減ったティックに URL を追加 |

## Rust 変更の要点

| クレート | 内容 |
|:---|:---|
| `rust/client/shared` | `RenderFrame.audio_cues: Vec<String>` |
| `rust/client/render_frame_proto` | `pb_into_render_frame` でフィールドをマッピング |
| `rust/client/audio` | `AudioCommand::PlaySeFromRelativePath` + `AssetLoader` の検証付き読み込み |
| `rust/client/network` | `NetworkRenderBridge` が `Option<AudioCommandSender>` を保持し、新フレーム時のみ再生；再利用時は返却 clone から `audio_cues` を除去 |
| `rust/client/app` | `start_audio_thread` と `NetworkRenderBridge::new(..., Some(tx))` |

## クライアントパス検証（v1）

- 文字列は **`assets/` で始まる**こと。
- パス成分に **`..` を含まない**こと。
- 上記を満たさない場合はログのうえ **再生しない**。

## 検証手順

1. `zenohd` とサーバー、クライアントを通常どおり起動。
2. `VRAlchemy`（または相当）で BulletHell3D に接続し、敵または弾に接触して HP が減るとき、`assets/audio/player_hurt.wav`（または設定したパス）が鳴ること。
3. `--assets <dir>` を指定した場合も、`<dir>/assets/audio/...` が解決されること。

## テスト観点

- Elixir: `encode_frame` に非空 `audio_cues` を渡したバイナリを `RenderFrame.decode` で読み、フィールドが復元されること。
- Rust: `decode_pb_render_frame` 後の `audio_cues` の内容。
- 手動: 被ダメージ以外のフレームで誤爆しないこと。

## 既知の限界

- フレームと同じ UDP/Zenoh 経路のため、**フレーム欠損時は音も欠ける**可能性がある。
- 同一フレーム内で複数回ヒットするルールに変えた場合は、キュー複数要素またはイベント設計の見直しが必要。
