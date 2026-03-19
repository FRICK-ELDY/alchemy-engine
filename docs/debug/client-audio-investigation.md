# クライアント側で音が鳴らない — 調査報告

> 作成日: 2026-03-20  
> 状態: 調査完了

---

## 1. 結論

**音声はサーバー・クライアントいずれでも現在鳴っていない。** 音声再生用のコードは存在するが、全体の経路が未接続の状態である。

---

## 2. 現状の構成

### 2.1 サーバー側（mix run + NIF）

| 要素 | 状態 |
|------|------|
| `native/audio` クレート | ✅ `start_audio_thread`, `AudioCommandSender`, `AudioCommand`, rodio 再生は実装済み |
| NIF からの audio 利用 | ❌ `start_audio_thread` を呼ぶ箇所が存在しない |
| Elixir → 音声 | ❌ `Core.NifBridge` に音声用 NIF（play_se, play_bgm 等）がない |
| フレームイベント → 音声 | ❌ `on_frame_event`（enemy_killed, player_damaged 等）から音声を鳴らすコンポーネントがない |

### 2.2 クライアント側（VRAlchemy / app）

| 要素 | 状態 |
|------|------|
| `native/app` main.rs | ❌ `start_audio_thread` を呼んでいない |
| `NetworkRenderBridge` | フレーム（`game/room/{id}/frame`）のみ subscribe。音声トピックは未使用 |
| Zenoh 音声トピック | ❌ `game/room/{id}/audio` 等の定義・配信が存在しない |
| フレームペイロード | commands, camera, ui, mesh_definitions, cursor_grab のみ。音声コマンドは含まれない |

---

## 3. 原因の整理

1. **サーバー側で音声スレッドが起動していない**  
   NIF の `load` やゲームループ起動時に `start_audio_thread` が呼ばれていない。

2. **Elixir から音声をトリガーする手段がない**  
   `Core.NifBridge` に `play_se` / `play_bgm` 等の NIF が無く、フレームイベントを音声に紐づけるコードもない。

3. **Zenoh に音声用トピックがない**  
   `zenoh-protocol-spec.md` では `frame`, `input/movement`, `input/action` のみ定義。音声の配信仕様・実装がない。

4. **クライアントは音声を受け取る設計になっていない**  
   `NetworkRenderBridge` はフレームのみ受信し、オーディオスレッドを起動していない。

---

## 4. 関連ドキュメント

- `docs/policy/audio-responsibility.md`  
  - 「音を鳴らすのはクライアント」「将来的には Zenoh 経由でクライアントに委譲する可能性あり」と記載
- `docs/architecture/zenoh-protocol-spec.md`  
  - 現行の Zenoh トピック定義（音声なし）
- `native/audio/README.md`  
  - サーバーは nif 経由、クライアントは将来のローカル再生を想定と記載

---

## 5. 推奨対応方針

クライアントで音を鳴らすには、次のいずれか（または組み合わせ）が必要。

### 案 A: Zenoh 経由でクライアントに音声を配信（ポリシー準拠）

1. **Zenoh に audio トピックを追加**  
   例: `game/room/{room_id}/audio`
2. **サーバー側**  
   - フレームイベント（enemy_killed, player_damaged, item_pickup 等）から音声種別を決定  
   - 該当する `AudioCommand` を MessagePack 等で encode して上記トピックへ publish
3. **クライアント側**  
   - 上記トピックを subscribe  
   - `start_audio_thread` でオーディオスレッドを起動  
   - 受信したコマンドを `AudioCommandSender` 経由で再生

### 案 B: フレームペイロードに audio_commands を追加

- フレームの MessagePack に `audio_commands: [...]` を追加し、同一フレームで音声も配信する方法。
- 実装がシンプルだが、60Hz フレームと音声タイミングの関係（同時再生・遅延）の設計が必要。

### 案 C: サーバー側のみで音声再生（一時対応）

- サーバー側で `start_audio_thread` を起動し、Elixir に `play_se` / `play_bgm` の NIF を追加する。
- クライアント PC のスピーカーでは鳴らないが、サーバー実行環境のスピーカーでは鳴る。

---

## 6. 次のステップ候補

1. **調査結果の共有**  
   - 本ドキュメントをチームで共有し、A/B/C のどれを採用するか決定する。

2. **案 A を採用する場合**  
   - `zenoh-protocol-spec.md` に audio トピックの仕様を追記  
   - Elixir コンポーネントでフレームイベント → 音声種別のマッピング  
   - ZenohBridge に audio publish を追加  
   - クライアントで audio subscribe + `start_audio_thread` を実装

3. **案 B を採用する場合**  
   - `messagepack-schema.md` に `audio_commands` のスキーマを追加  
   - `encode_frame` で audio_commands を埋め込み  
   - クライアントの `msgpack_decode` で audio_commands を処理し、`AudioCommandSender` に渡す
