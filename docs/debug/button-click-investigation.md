# ボタンクリック不能の調査結果

## 想定される原因（2つ）

### 1. カーソルグラブが解除されない（最有力）

- **現象**: ゲームオーバーで RETRY ボタンがクリックできない
- **原因**: プレイ中はマウスクリックで `cursor_grabbed = true` になり、カーソルが非表示・固定される。ゲームオーバーに遷移しても `cursor_grab_request` が送られず、クライアント側でカーソルが解放されない
- **証拠**: 
  - `Rendering.Render` は `playing_state` から `cursor_grab_request` を取得
  - ゲームオーバー時は `:playing` がスタックから外れるため `playing_state = %{}`
  - `encode_frame` に `cursor_grab` を渡しておらず、Zenoh フレームに含まれない
  - クライアントは常に `cursor_grab: None` を受け取り、カーソル状態を変更しない

### 2. action ペイロードの形式不一致（movement と同様の可能性）

- **現象**: クリックは検出されるがサーバーに届かない
- **原因**: Rust の rmp_serde が ActionPayload を map ではなく配列等でシリアライズしている可能性
- **対処**: ZenohBridge の handle_action で配列形式にも対応する（movement と同様）

## 修正方針

1. **cursor_grab**: フレームに cursor_grab を含め、ゲームオーバー時は `"release"` を送る
2. **handle_action**: 配列形式 `[name]` に対応する
