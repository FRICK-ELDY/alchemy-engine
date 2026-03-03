# VR デバッグログの見方

`mix phx.server` 起動後、ターミナルに出るログで VR の状態を確認できます。

## 起動直後に出るログ（上から順に）


| ログ                                              | 意味                                              |
| ----------------------------------------------- | ----------------------------------------------- |
| `[VR] XR 入力スレッドを起動しました`                         | XR スレッドが spawn した                               |
| `[VR] OpenXR セッション準備完了（フレーム待ちループに入りました）`        | SteamVR 等と接続し、`frame_waiter.wait()` でフレーム待ちに入った |
| `[VR] head_pose を受信しました（VR ヘッドセットからの入力が届いています）` | head_pose が Elixir に届いた                         |
| `[VR] カメラ: VR ヘッドセットを使用中`                       | カメラが VR の向きで描画されている（ヘッドセットを回すと画面が追従する）          |
| `[VR] カメラ: マウスにフォールバック（head_pose 未受信 or 未反映）`   | head_pose が来ていないためマウスでカメラを制御している                |
| `[VR] Ignoring malformed head_pose`             | head_pose の形式が不正（まれ）                            |
| `[VR] OpenXR 初期化失敗: ...`                   | OpenXR の初期化・セッション作成で失敗（原因が表示される）           |


## 判断の目安

1. `**XR 入力スレッドを起動しました` が出ない**
  → `spawn_xr_input_thread` が呼ばれていない。config の `features: ["xr"]` を確認。
2. `**XR 入力スレッドを起動しました` は出るが `OpenXR セッション準備完了` が出ない**
  → OpenXR の初期化・セッション作成で失敗している（ローダー、拡張、SteamVR 未起動など）。
3. `**OpenXR セッション準備完了` は出るが `head_pose を受信しました` が出ない**
  → `frame_waiter.wait()` が戻っていない。SteamVR のヘッドレスでフレームが進まない可能性が高い。
4. `**head_pose を受信しました` が出る**
  → OpenXR は動いている。カメラに反映されないなら InputComponent / RenderComponent の経路を疑う。
5. `**カメラ: VR ヘッドセットを使用中` が出る**
  → 正常動作。ヘッドセットを回すと視点が変わるはず。
6. `**カメラ: マウスにフォールバック` が出る**
  → head_pose が届いていないか、届いても scene state に反映されていない。

---

## OpenXR loader failed: LoadLibraryExW failed

Steam が標準パス外にある場合に発生する既知の課題。→ [vr-openxr-loader-path-issue.md](./vr-openxr-loader-path-issue.md)

