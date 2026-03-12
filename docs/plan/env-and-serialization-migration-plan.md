# 環境変数リネーム・Erlang term 直列化 対応計画書

> 作成日: 2026-03-08  
> 目的: 環境変数のリネーム（GAME_ プレフィックス削除）と、MessagePack から Erlang term 形式への移行を体系的に進める。

---

## 要約

| 項目 | 内容 | 工数目安 |
|:---|:---|:---|
| 1. 環境変数リネーム | `GAME_ASSETS_PATH` → `ASSETS_PATH`, `GAME_ASSETS_ID` → `ASSETS_ID` | 0.5〜1 日 |
| 2. Erlang term 直列化 | MessagePack から Erlang term（`:erlang.term_to_binary`）へ移行 | 1〜2 週間 |
| 3. set_cursor_grabbed 抽象化 | RenderBridge または CursorGrabHandler トレイトでカーソルグラブ実行を抽象化 | 0.5〜1 日 |

---

## 1. 環境変数リネーム

### 1.1 背景

プロジェクトがゲームに限定されなくなったため、`GAME_` プレフィックスを削除する。

### 1.2 変更一覧

| 旧名称 | 新名称 | 説明 |
|:---|:---|:---|
| `GAME_ASSETS_PATH` | `ASSETS_PATH` | アセットルートディレクトリ |
| `GAME_ASSETS_ID` | `ASSETS_ID` | コンテンツ別サブディレクトリ名（例: `vampire_survivor`） |

### 1.3 影響ファイル

| ファイル | 変更内容 |
|:---|:---|
| `native/client_desktop/src/main.rs` | コメント・`set_var("GAME_ASSETS_PATH", ...)` → `set_var("ASSETS_PATH", ...)` |
| `native/audio/src/asset/mod.rs` | コメント・`env::var("GAME_ASSETS_PATH")` → `env::var("ASSETS_PATH")`<br/>`env::var("GAME_ASSETS_ID")` → `env::var("ASSETS_ID")` |
| `apps/server/lib/server/application.ex` | `put_env("GAME_ASSETS_ID", ...)` → `put_env("ASSETS_ID", ...)` |
| `docs/architecture/rust/client_desktop.md` | 環境変数一覧の更新 |
| `docs/architecture/shader-path-traversal-design.md` | `GAME_ASSETS_PATH` 表記の更新 |
| `docs/plan/asset-cdn-design.md` | `GAME_ASSETS_PATH`, `GAME_ASSETS_ID` 表記の更新 |
| `docs/plan/asset-storage-classification.md` | `GAME_ASSETS_ID` 表記の更新 |
| `assets/README.md` | `GAME_ASSETS_ID` 表記の更新 |

### 1.4 後方互換（任意）

移行期間中、旧変数が設定されていれば新変数へフォールバックする処理を追加するか、一括リネームのみで進めるかを選ぶ。

```rust
// 例: フォールバック
let path = std::env::var("ASSETS_PATH")
    .or_else(|_| std::env::var("GAME_ASSETS_PATH"))
    .unwrap_or_else(|_| ".".into());
```

---

## 2. MessagePack → Erlang term 直列化移行

### 2.1 背景

- ポリシー: [zenoh-frame-serialization.md](../policy-as-code/why_adopted/zenoh-frame-serialization.md) で Erlang term 形式を採用
- `term_to_binary` は C BIF で高速。Msgpax（純 Elixir）より負荷が低い
- 型の保持・NIF 親和性が高い

### 2.2 対象範囲

| 用途 | 現状 | 移行先 |
|:---|:---|:---|
| **フレーム配信**（Zenoh） | `Content.MessagePackEncoder.encode_frame` + Msgpax | `term_to_binary` |
| **フレーム受信**（client_desktop） | `msgpack_decode::decode_render_frame` (rmp_serde) | bert または BinaryTerm デコード |
| **movement / action**（Zenoh） | `rmp_serde::to_vec` (client) / Msgpax.unpack (server) | Erlang term 形式 |
| **set_frame_injection**（NIF） | `apply_injection_from_msgpack` (rmp_serde) | bert デコード |

### 2.3 フェーズ構成

#### フェーズ A: フレーム配信・受信の Erlang term 化（中核）

| ステップ | 内容 | 影響ファイル |
|:---|:---|:---|
| A1 | Elixir: `MessagePackEncoder` を `FrameEncoder` にリネームし、`term_to_binary` 実装に置き換え | `apps/contents/lib/contents/message_pack_encoder.ex` → 新規 `frame_encoder.ex` |
| A2 | Elixir: 各 RenderComponent の `MessagePackEncoder.encode_frame` を `FrameEncoder.encode_frame` に変更 | `vampire_survivor`, `rolling_ball`, `canvas_test` 等 |
| A3 | Rust: client_desktop に `bert` クレートを追加 | `native/client_desktop/Cargo.toml` |
| A4 | Rust: `msgpack_decode` を `bert_decode`（または `erlang_term_decode`）に置き換え | `native/client_desktop/src/msgpack_decode.rs` → `bert_decode.rs` |
| A5 | Rust: `network_render_bridge.rs` のデコード呼び出しを更新 | `network_render_bridge.rs` |
| A6 | スキーマドキュメント: `erlang-term-schema.md` を新規作成 | `docs/architecture/erlang-term-schema.md` |

#### フェーズ B: movement / action の Erlang term 化

| ステップ | 内容 | 影響ファイル |
|:---|:---|:---|
| B1 | Rust: `MovementPayload`, `ActionPayload` のエンコードを `term_to_binary` 相当の形式に変更<br/>※ クライアント側は Rust → Elixir 向けに binary を組み立てる必要あり。`bert` の encode を利用 | `native/client_desktop/src/network_render_bridge.rs` |
| B2 | Elixir: ZenohBridge の `Msgpax.unpack` を `:erlang.binary_to_term` に変更 | `apps/network/lib/network/zenoh_bridge.ex` |

#### フェーズ C: set_frame_injection の Erlang term 化（NIF）

| ステップ | 内容 | 影響ファイル |
|:---|:---|:---|
| C1 | Elixir: `MessagePackEncoder.encode_injection_map` を Erlang term 形式に変更 | `apps/contents/lib/contents/message_pack_encoder.ex` |
| C2 | Elixir: `game_events.ex` の injection バイナリ生成を term 形式に変更 | `apps/contents/lib/contents/game_events.ex` |
| C3 | Rust: `msgpack_injection.rs` を `bert_injection.rs` に置き換え | `native/nif/src/nif/decode/msgpack_injection.rs` → `bert_injection.rs` |
| C4 | Rust: `world_nif.rs` の `apply_injection_from_msgpack` を `apply_injection_from_bert` に変更 | `native/nif/src/nif/world_nif.rs` |

### 2.4 技術的検討事項

#### Rust での Erlang term デコード

- **bert クレート**: `bert` または `bert-rs` で `binary_to_term` 互換のデコードが可能
- **型マッピング**: Erlang のタプル `{:sprite_raw, x, y, ...}` を Rust の enum や構造体に変換するロジックを実装
- **schema 設計**: [messagepack-schema.md](../architecture/messagepack-schema.md) の構造を Erlang term 用に変換（キーをアトムに、値はタプル/マップ）

#### クライアント → サーバー（movement / action）のエンコード

- 現状: Rust が `rmp_serde::to_vec` で MessagePack を生成
- 移行: Rust が `bert` の encode で Erlang term バイナリを生成し、Elixir が `binary_to_term` で受け取る
- フォーマット例: `{:movement, %{dx: 0.0, dy: 1.0}}` または `%{type: :movement, dx: 0.0, dy: 1.0}`

### 2.5 ドキュメント更新

| ドキュメント | 更新内容 |
|:---|:---|
| `docs/architecture/messagepack-schema.md` | 非推奨注記を追加。`erlang-term-schema.md` へ誘導 |
| `docs/architecture/erlang-term-schema.md` | 新規。Erlang term 形式のスキーマ定義 |
| `docs/architecture/zenoh-protocol-spec.md` | MessagePack 参照を Erlang term に変更 |
| `docs/architecture/rust/client_desktop.md` | エンコード・デコードの記述を Erlang term に更新 |
| `docs/architecture/overview.md` | MessagePackEncoder → FrameEncoder に更新 |
| `docs/architecture/elixir/contents.md` | 同上 |

### 2.6 依存関係の整理

| クレート / ライブラリ | 移行後の扱い |
|:---|:---|
| `native/client_desktop`: rmp-serde | bert に置き換え後、削除 |
| `native/nif`: rmp-serde | bert に置き換え後、削除 |
| `mix.exs`: msgpax | フレーム・injection から使用しなくなった場合、他用途がなければ削除検討 |

---

## 3. desktop_input: set_cursor_grabbed の抽象化

### 3.1 背景

現状、`desktop_input` 内の `DesktopApp::set_cursor_grabbed` は winit の `window.set_cursor_visible` / `set_cursor_grab` を直接呼ぶ private メソッドであり、トレイトやブリッジ経由で抽象化されていない。ESC によるカーソルグラブ切替の意味づけは contents 層（InputComponent）で行われ、`frame.cursor_grab` としてクライアントへ渡される。プラットフォーム差（例: 別 UI フレームワーク利用）やテスタビリティを考慮し、カーソルグラブの実行を抽象化する。

### 3.2 方針

- **RenderBridge** または新規トレイト（例: `CursorGrabHandler`）に `set_cursor_grabbed(&self, grabbed: bool)` を追加
- `DesktopApp` はそのメソッドを呼び出し、実装は `DefaultCursorGrabHandler`（winit 直接呼び出し）に委譲
- テスト時やヘッドレス時はモック実装に差し替え可能にする

### 3.3 工数目安

0.5〜1 日（既存フローへの組み込み・既存テストの確認含む）

---

## 4. 実施順序の推奨

1. **環境変数リネーム**（先行・独立）
   - 影響が小さく、他の作業と並行しにくいため先行実施

2. **フェーズ A: フレーム配信・受信**
   - 中核機能。まず A1〜A6 を完了し、動作確認

3. **フェーズ B: movement / action**
   - フレームが動いた後に実施

4. **フェーズ C: set_frame_injection**
   - NIF 側はフレーム配信と独立。並行可能だが、スキーマ整合性に注意

5. **set_cursor_grabbed の抽象化**（任意・独立）
   - desktop_input のリファクタ。直列化移行とは独立して実施可能

---

## 5. native/client 作成・client_info ・client_* 依存整理 実行計画

### 5.1 背景

- クライアント共通ロジック（Zenoh 接続、エンコード/デコード、クライアント情報取得等）を `native/client` に集約する
- `platform_info` はクライアント属性全般を扱うため、`client_info` とする
- `client_desktop`, `client_web`, `client_android`, `client_ios` は `native/client` に依存し、プラットフォーム固有部分のみを実装する

### 5.2 対象クレート

| クレート | 役割 |
|:---|:---|
| `native/client` | 共有ライブラリ。Zenoh 接続、Erlang term エンコード/デコード、`client_info`（OS/arch 等）の提供 |
| `native/client_desktop` | Windows/Linux/macOS 向け。`client` + `desktop_render` + `desktop_input` に依存 |
| `native/client_web` | Web 向け（将来）。`client` に依存 |
| `native/client_android` | Android 向け（将来）。`client` に依存 |
| `native/client_ios` | iOS 向け（将来）。`client` に依存 |

### 5.3 実行手順

#### フェーズ D1: native/client クレート作成

| ステップ | 内容 | 影響ファイル |
|:---|:---|:---|
| D1-1 | `native/client` ディレクトリ・`Cargo.toml` 作成 | `native/client/Cargo.toml` |
| D1-2 | `client_info` モジュール作成（OS, arch, family 取得。`std::env::consts` 使用、winit 非依存） | `native/client/src/client_info.rs` |
| D1-3 | Zenoh 関連型・エンコード/デコードを `client` へ移動（`network_render_bridge` の共通部分、`msgpack_decode` → `bert_decode` 等） | `native/client/src/` |
| D1-4 | ワークスペース `native/Cargo.toml` に `client` を追加 | `native/Cargo.toml` |

#### フェーズ D2: client_info の提供

| ステップ | 内容 | 備考 |
|:---|:---|:---|
| D2-1 | `ClientInfo` 構造体（`os`, `arch`, `family`）を定義 | `platform_info` ではなく `client_info` とする |
| D2-2 | `ClientInfo::current()` で `std::env::consts` から取得 | Windows, Linux, macOS, Android, iOS 対応 |
| D2-3 | Erlang term 形式でシリアライズ可能にする | Zenoh 経由で Elixir へ送信するため |

#### フェーズ D3: client_* の client 依存化

| ステップ | 内容 | 影響ファイル |
|:---|:---|:---|
| D3-1 | `client_desktop` の `Cargo.toml` に `client = { path = "../client" }` を追加 | `native/client_desktop/Cargo.toml` |
| D3-2 | `client_desktop` から `client` へ移したモジュールを削除し、`client::` を参照 | `native/client_desktop/src/*.rs` |
| D3-3 | `client_web`, `client_android`, `client_ios` の `Cargo.toml` に `client` 依存を追加 | 各 `Cargo.toml` |
| D3-4 | 将来的な実装時に `client` の共通 API を利用するようにする | スタブのままでも依存だけ追加 |

### 5.4 依存関係図（移行後）

```
native/client          ← 共有: client_info, Zenoh 接続, エンコード/デコード
    ↑
    ├── client_desktop ← desktop_render, desktop_input
    ├── client_web     ← 将来: wasm-bindgen 等
    ├── client_android ← 将来: ndk 等
    └── client_ios     ← 将来: objc 等
```

### 5.5 実施順序

- **D1, D2** を先行。`client` に `client_info` と共通ロジックを実装
- **D3** で各 `client_*` を `client` に依存させる。`client_desktop` から共通部分を `client` へ移行
- 環境変数リネーム・Erlang term 移行と並行可能。`client` 作成時に `bert` を導入すれば、移行先の型を `client` に集約できる

### 5.6 関連ドキュメント

- [platform-info-crate-and-local-user-execution-plan.md](./platform-info-crate-and-local-user-execution-plan.md) — `platform_info` → `client_info` に読み替え。`client` 配下に配置する想定で更新すること

---

## 6. 関連ドキュメント

- [zenoh-frame-serialization.md](../policy-as-code/why_adopted/zenoh-frame-serialization.md) — Erlang term 採用ポリシー
- [messagepack-schema.md](../architecture/messagepack-schema.md)（現行スキーマ・構造参照）
- [bottleneck-prevention.md](../policy/bottleneck-prevention.md)（ボトルネック対策方針）
- [desktop/input.md](../architecture/rust/desktop/input.md)（set_cursor_grabbed の現状・ESC と contents 層の責務）
