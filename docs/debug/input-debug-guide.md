# 入力デバッグガイド

クライアント（VRAlchemy）からのマウス・キーボード入力が効かない場合の診断手順。

## 追加したデバッグログの場所

すべてのログは `[input:` で始まるため、以下で絞り込めます:

```bash
# サーバー側（PowerShell）
mix run --no-halt 2>&1 | Select-String "\[input:"

# または Linux/macOS
mix run --no-halt 2>&1 | grep "\[input:"
```

## Zenoh: フレームは届くが movement だけサーバーにログが無いとき

- **原因の典型**: Elixir 側は `mode: client` で zenohd に接続しているが、Rust クライアントが **`connect/endpoints` だけ**で peer 扱いになり、クライアントの PUT がルータ上の購読者に届かない。
- **対処**: `native/network` の `ClientSession::open` で **`mode: "client"` を明示**（サーバーと同じ方針）。修復後はサーバーに `[input:ZenohBridge] Sample recv … movement` が出る。

## 期待されるログの流れ（WASD 押下時）

### 1. クライアント側（VRAlchemy exe のコンソール）

- `[input:client] on_raw_key key=KeyW state=Pressed` … キーが検出されている
- `[input:client] next_frame keys→(dx=0, dy=-1)` … 移動ベクトルが計算され送信されている

**ここが出ない場合**: ウィンドウにフォーカスがない、または winit のキーイベントが届いていない。

### 2. サーバー側（ZenohBridge）

- `[input:ZenohBridge] Sample recv key=game/room/main/input/movement` … Zenoh で movement を受信
- `[input:ZenohBridge] handle_movement unpack ok` … MessagePack のデコード成功
- `[input:ZenohBridge] forward_move_input room=main` … GameEvents へ転送

**ここが出ない場合**:
- zenohd が起動していない
- ZenohBridge が movement を subscribe していない
- `[input:ZenohBridge] handle_info UNMATCHED` が出る → Sample の構造が想定と異なる

### 3. GameEvents

- `[input:GameEvents] handle_info {:move_input, 0.0, -1.0}` … メッセージ受信

**ここが出ない場合**: ZenohBridge の forward 先（RoomRegistry）が正しくない。

### 4. LocalUserComponent

- `[input:LocalUserComponent] on_event {:move_input, ...}` … ETS への保存

**ここが出ない場合**: `dispatch_event_to_components` が呼ばれていない、またはコンポーネントが登録されていない。

### 5. maybe_set_input_and_broadcast

- `[input:GameEvents] maybe_set_input_and_broadcast frame=... get_move_vector=({0.0, -1.0})` … 約5秒ごと

**ここで get_move_vector が常に (0, 0) の場合**: LocalUserComponent の ETS への保存に失敗している。

## 起動手順（デバッグ用）

1. ターミナル1: `zenohd` または `mix alchemy.router`
2. ターミナル2: `mix run --no-halt`（ログを確認）
3. ターミナル3: VRAlchemy exe を起動
4. ゲームウィンドウをアクティブにし、W キーを押す

## デバッグログの削除

原因が特定できたら、`[input:` または `[DEBUG]` を検索して該当ログを削除してください。
