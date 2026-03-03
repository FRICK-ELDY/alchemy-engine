# VR Test 実施手順書 — ヘッドセットで3D空間を見渡す

> 作成日: 2026-03-03  
> 目的: `apps/game_content/lib/game_content/vr_test.ex` と関連コンテンツを作成し、  
> `native/game_input_openxr` を使って VR ヘッドセットで3D空間を見渡せるようにする。

---

## 1. 現状サマリ

### 1.1 既存実装の状態

| コンポーネント | 状態 | 備考 |
|:---|:---|:---|
| `native/game_input_openxr` | ✅ 実装済み | XR_MND_headless でヘッドレスセッション、head pose 取得 |
| `native/game_nif` xr_bridge | 完了 | XrInputEvent → Elixir タプル変換・送信は実装済み |
| `apps/game_engine/game_events.ex` | 完了 | `{:head_pose}`, `{:controller_pose}` 等の `handle_info` は実装済み |
| `native/game_render` | デスクトップのみ | winit + wgpu でウィンドウ描画。VR ステレオレンダリング・OpenXR コンポジションは未対応 |
| `config :game_engine, GameEngine.NifBridge, features` | デフォルト `[]` | VR 有効化には `features: ["xr"]` が必要 |

### 1.2 データフロー（設計済み）

```
OpenXR runtime → game_input_openxr → xr_bridge → GameEvents
                                                      ↓
                                              dispatch_event_to_components
                                                      ↓
                                              VRTest の RenderComponent
                                                      ↓
                                              head_pose でカメラ制御
                                                      ↓
                                              push_render_frame (Camera3D)
                                                      ↓
                                              game_render (デスクトップウィンドウ)
```

---

## 2. 課題一覧

### 2.1 最優先課題（VR 体験の前提）

| 課題 | 重要度 | 内容 |
|:---|:---|:---|
| **OpenXR ループ未実装** | 高 | `game_input_openxr::run_openxr_loop` が TODO のまま。ヘッドポーズを取得できない |
| **描画先がデスクトップのみ** | 高 | 現状の game_render はウィンドウ出力のみ。ヘッドセット内に直接描画するには OpenXR コンポジション層との統合が必要 |

### 2.2 次点の課題

| 課題 | 重要度 | 内容 |
|:---|:---|:---|
| **OpenXR ローダーが LoadLibraryExW で失敗** | 高 | Steam が標準パス外の場合、`openxr_loader.dll` が見つからない。ユーザー設定不要の解決策が未確立。→ [vr-openxr-loader-path-issue.md](./vr-openxr-loader-path-issue.md) |
| **XR 入力スレッド未起動** | 中 | `spawn_xr_input_thread` が GameEvents の init から呼ばれていない |
| **VR 専用コンテンツの設定** | 低 | `config :game_server, :current` を VRTest に切り替える必要 |
| **head_pose の座標系** | 中 | OpenXR の reference space と game_render のカメラ座標系の対応を確認する必要がある |

### 2.3 段階的アプローチの整理

VR で「ヘッドセットで周りを見渡す」には、**入力（head pose）** と **出力（描画先）** の両方が必要。

| フェーズ | 入力 | 出力 | 体験 |
|:---|:---|:---|:---|
| **Phase A** | マウスでカメラ回転（モック） | デスクトップ | 3D空間をデスクトップで見る（VR なし） |
| **Phase B** | OpenXR head_pose（実装後） | デスクトップ | ヘッドセットの向きでカメラが動く（ミラーリング相当） |
| **Phase C** | OpenXR head_pose | ヘッドセット内 | 完全な VR 体験（OpenXR レンダリング統合が必要） |

本手順書では **Phase A → Phase B** を対象とする。Phase C は別タスクとして切り出す。

---

## 3. 実施手順

### Phase A: VRTest コンテンツの骨格とデスクトップ3D表示

目的: VR 入力がなくても動作するコンテンツを作り、3D空間を見られるようにする。

#### Step A-1: VRTest コンテンツの作成

1. `apps/game_content/lib/game_content/vr_test.ex` を作成
2. 既存の `SimpleBox3D` を参考に、最小限のコンポーネント構成にする
   - `SpawnComponent`: SimpleBox3D 同様に `set_world_size` のみ（物理は使わない想定でもインターフェース合わせ）
   - `InputComponent`: マウスドラッグでカメラ回転（Phase A の代替入力）
   - `RenderComponent`: Skybox / GridPlane / Box3D を描画、Camera3D を head_pose またはマウスで制御
3. `Scenes.Playing` を定義
   - シーン state: `%{camera_yaw: 0.0, camera_pitch: 0.0, player: {0,0,0}, enemies: [...]}` 等
   - `{:mouse_delta, dx, dy}` で `camera_yaw`, `camera_pitch` を更新

#### Step A-2: 設定の切り替え

1. `config/config.exs` の `config :game_server, :current` を一時的に `GameContent.VRTest` に変更
2. `mix compile` と起動で、デスクトップ上で3D空間が表示され、マウスで見回せることを確認

---

### Phase B: OpenXR 入力の有効化と head_pose によるカメラ制御

目的: ヘッドセットをかぶった状態で head_pose に応じてカメラが動くようにする（出力はデスクトップでも可）。

#### Step B-1: game_input_openxr の run_openxr_loop 実装

1. `native/game_input_openxr` に OpenXR クレートの依存を確認（`openxr` 0.21）
2. `run_openxr_loop` 内で以下を実装:
   - `xr::Instance` の作成
   - `System` の取得（`XR_TYPE_VIEW_CONFIGURATION_TYPE_PRIMARY_STEREO`）
   - ヘッドレスセッションの作成（描画なし、入力のみ）
   - `ReferenceSpace::Local` と `Space::create_reference_space` でヘッド用スペース作成
   - `Session::locate_space` で head pose を取得
   - ポーリングループで `HeadPose { position, orientation, timestamp_us }` を `on_event` に渡す
3. 参考: [openxr-rs](https://github.com/khronosgroup/OpenXR-Hpp) のサンプルや `openxr` crate の examples

**技術的注意点:**

- OpenXR はランタイム（SteamVR / Oculus / Windows Mixed Reality 等）が必須
- セッション作成時に `GraphicsBinding` が要求される場合、描画バインディングなしのヘッドレスは拡張依存（`XR_EXT_headless` 等）の可能性あり。必要に応じてシミュレーターやドライラン（`XR_KHR_loader_init`）で動作確認

#### Step B-2: XR 入力スレッドの起動

1. `config/config.exs` で `config :game_engine, GameEngine.NifBridge, features: ["xr"]` を設定
2. `apps/game_engine/lib/game_engine/game_events.ex` の `init/1` 内で、`render_started` が true のときに `GameEngine.NifBridge.spawn_xr_input_thread(self())` を呼ぶ
3. `mix compile` で `--features xr` が渡ることを確認
4. OpenXR ランタイム未導入時は `run_xr_input_loop` が即終了するが、エラーでクラッシュしないことを確認

#### Step B-3: VRTest で head_pose をカメラに反映

1. `VRTest.RenderComponent` で `context` から head_pose を取得する方法を検討
   - `GameEngine.EventBus` 経由で head_pose をサブスクライブ
   - または `SceneManager` / `FrameCache` に head_pose を保持し、RenderComponent が参照
2. 設計方針: head_pose は `GameEvents` が `dispatch_event_to_components` で配信するため、VRTest のシーンまたはコンポーネントが `on_event` で `{:head_pose, data}` を受け取り、state に保持
3. `build_camera/1` で head_pose の `position` と `orientation` から eye / target / up を計算
   - `orientation` はクォータニオン `{qx, qy, qz, qw}`。前方ベクトルは `q * {0,0,-1} * q^{-1}` で算出
4. head_pose が届いていないときはマウス入力（Phase A）にフォールバック

#### Step B-4: 座標系の一致

- OpenXR: 右手系、Y-up が一般的。`xrLocateSpace` の `pose` は position + orientation
- game_render の Camera3D: `eye`, `target`, `up` で指定
- 必要に応じて Y-up / Z-up や左右の変換を適用

---

### Phase C（将来）: ヘッドセット内への直接描画

Phase B まででデスクトップミラーリング＋head_pose カメラは実現できる。  
ヘッドセット内に直接描画するには、以下が必要（本手順書のスコープ外）:

1. `game_render` に OpenXR の Swapchain / コンポジション層との統合を追加
2. 左右眼用のビュー行列・射影行列を OpenXR の `View` から取得
3. 毎フレーム `xrWaitFrame` → `xrBeginFrame` → 左右眼描画 → `xrEndFrame` のループを game_render 側で実装

---

## 4. 成果物一覧

| 成果物 | パス |
|:---|:---|
| VR Test コンテンツ | `apps/game_content/lib/game_content/vr_test.ex` |
| シーン | `apps/game_content/lib/game_content/vr_test/scenes/playing.ex` |
| SpawnComponent | `apps/game_content/lib/game_content/vr_test/spawn_component.ex` |
| InputComponent | `apps/game_content/lib/game_content/vr_test/input_component.ex` |
| RenderComponent | `apps/game_content/lib/game_content/vr_test/render_component.ex` |

---

## 5. 事前準備チェックリスト

- [ ] OpenXR ランタイムがインストールされている（SteamVR / Oculus / WMR 等）
- [ ] VR ヘッドセットが接続されている
- [ ] `config :game_engine, GameEngine.NifBridge, features: ["xr"]` を設定済み
- [ ] `mix compile` が `--features xr` で成功する
- [ ] `native/game_input_openxr` の `openxr` フィーチャーが有効になっている（game_nif の xr フィーチャー経由）

---

## 6. 参考ドキュメント

- [input-device-abstraction-design.md](./input-device-abstraction-design.md) — VR イベント形式・フロー
- [vision-correction-pass-tech-spec.md](../paper/vision-correction-pass-tech-spec.md) — OpenXR / wgpu 連携の将来的な検討
- [implementation.mdc](../../.cursor/rules/implementation.mdc) — レイヤー責務・アーキテクチャ原則
