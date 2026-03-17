# CanvasTest Playing およびコンポーネント再配置 実施計画書

> 作成日: 2026-03-17  
> 更新: 2026-03-17（Device 細分化・Renderer 役割分割・終了委譲の設計を追記）  
> 目的: CanvasTest の Playing を直下に移し、入力を device（mouse / keyboard）に、描画を renderer + procedural/shader に分割する。終了処理はコンテンツまたは上位層に委譲する。

---

## 1. 概要

### 1.1 変更内容

| 種別 | 変更前 | 変更後 |
|:---|:---|:---|
| Playing シーン | `contents/canvas_test/scenes/playing.ex`<br>モジュール: `Content.CanvasTest.Scenes.Playing` | `contents/canvas_test/playing.ex`<br>モジュール: `Content.CanvasTest.Playing` |
| 入力 | `contents/canvas_test/input_component.ex`<br>1 モジュールでマウス・キー・UI を処理 | **device を細分化**<br>`components/category/device/mouse.ex` — マウス入力<br>`components/category/device/keyboard.ex` — キーボード入力<br>マウスとキーボードの入力をそれぞれ取得できるようにする |
| 描画 | `contents/canvas_test/render_component.ex`<br>値の定義と描画が一体 | **役割分割**<br>・**値の定義**: `contents/canvas_test/playing.ex` で定義<br>・**renderer/render.ex**: どのメッシュをどのシェーダーで描画するかだけを担当。メッシュ・シェーダーを参照し、クライアントへ投げる「器」のみ<br>・**メッシュ**: `procedural/meshes/box.ex`, `procedural/meshes/quad.ex`<br>・**シェーダー**: `shader/skybox.ex`, `shader/pbs_metallic.ex`（クライアントに投げる器としての骨格） |
| 終了処理 | コンポーネント内で `System.stop(0)` を直接呼ぶ | **終了はコンテンツまたは上位層に委譲**。コンポーネントは終了要求をイベント等で通知し、実際の終了は Content や上位が行う設計とする |

### 1.2 方針

- **Playing**: シーンが 1 つのため `scenes/` を廃止し、`Content.CanvasTest.Playing` として直下に置く。**描画に必要な値（カメラ・メッシュ割当・UI 定義など）の定義も Playing（または Content）で行う**。
- **Device**: 入力を **Mouse** と **Keyboard** に分け、マウス入力・キーボード入力をそれぞれ取得できるようにする。
- **Renderer.Render**: 「どのメッシュをどのシェーダーで描画するか」に専念し、メッシュ・シェーダーは参照するだけ。具体的な頂点データやシェーダーコードは procedural/meshes と shader に分離する。
- **終了**: `{:ui_action, "__quit__"}` 等は Device が受け取り、**終了の実行は行わない**。Content または上位層がイベントを購読し、終了するかどうかと `System.stop/1` 等の呼び出しを担当する。

---

## 2. 実施手順

### Phase 1: Playing の移動

#### Step 1-1: ファイル移動とモジュール名変更

1. **移動**
   - 移動元: `apps/contents/lib/contents/canvas_test/scenes/playing.ex`
   - 移動先: `apps/contents/lib/contents/canvas_test/playing.ex`

2. **モジュール名の変更**
   - 変更前: `Content.CanvasTest.Scenes.Playing`
   - 変更後: `Content.CanvasTest.Playing`

3. **値の定義**
   - 描画に必要な値（カメラ FOV・色・グリッドサイズ・ワールドパネル用テキスト・HUD レイアウトなど）は、本計画に従い **Playing 側で定義する** 方針とする。Render はそれらを参照するだけにする場合は、Playing が state または公開関数で提供する形を想定する。

#### Step 1-2: 参照の更新

**ファイル:** `apps/contents/lib/contents/canvas_test.ex`

| 箇所 | 変更前 | 変更後 |
|:---|:---|:---|
| `scene_init(:playing, init_arg)` | `Content.CanvasTest.Scenes.Playing.init(init_arg)` | `Content.CanvasTest.Playing.init(init_arg)` |
| `scene_init(:game_over, init_arg)` | `Content.CanvasTest.Scenes.Playing.init(init_arg)` | `Content.CanvasTest.Playing.init(init_arg)` |
| `scene_update(:playing, context, state)` | `Content.CanvasTest.Scenes.Playing.update(...)` | `Content.CanvasTest.Playing.update(...)` |
| `scene_update(:game_over, context, state)` | 同様 | 同様 |

#### Step 1-3: 空ディレクトリの削除

- `apps/contents/lib/contents/canvas_test/scenes/` を削除する（中身が playing.ex のみの場合）。

---

### Phase 2: 入力の細分化（device/mouse.ex と device/keyboard.ex）

#### 2.1 設計

- **Mouse** (`device/mouse.ex`): マウス由来の入力のみを扱う。
  - 例: `{:move_input, dx, dz}`（WASD に紐づく論理ベクトルはクライアント由来ならマウスとは別でもよいが、同一クライアント入力として扱う場合は Mouse に含めてもよい）、`{:mouse_delta, dx, dy}`、カーソルグラブ関連の状態更新。
  - マウス入力を取得できるようにする（取得 API は必要に応じて定義）。

- **Keyboard** (`device/keyboard.ex`): キーボード由来の入力のみを扱う。
  - 例: `{:sprint, bool}`, `{:key_pressed, :escape}`, `{:ui_action, "__quit__"}` 等。
  - キーボード入力を取得できるようにする。
  - **終了について**: `{:ui_action, "__quit__"}` を受け取っても **`System.stop(0)` は呼ばない**。イベントとして伝え、終了するかどうかは **Content または上位層** が決める。例: Content が `on_event` を購読するか、GameEvents 等で `:quit_requested` を発行し、上位が `System.stop(1)` 等を実行する。

#### Step 2-2: 既存 InputComponent の分割と配置

1. ディレクトリ: `apps/contents/lib/components/category/device/`

2. **新規作成: `device/mouse.ex`**（モジュール: `Contents.Components.Category.Device.Mouse`）
   - 現在の `input_component.ex` のうち、マウスに関係する処理を移す。
   - 例: `{:move_input, dx, dz}`, `{:mouse_delta, dx, dy}` の `on_event` と、必要ならカーソルグラブ用の state 更新。
   - 既知の不具合修正: `Contents.SceneStack` → `Contents.Scenes.Stack`。

3. **新規作成: `device/keyboard.ex`**（モジュール: `Contents.Components.Category.Device.Keyboard`）
   - 現在の `input_component.ex` のうち、キーボード・UI アクションを移す。
   - 例: `{:sprint, value}`, `{:key_pressed, :escape}`, `{:ui_action, "__quit__"}`。
   - **`{:ui_action, "__quit__"}` の扱い**: ここではシーン state の更新（例: 終了要求フラグのセット）や、上位へイベント送信のみ行う。**終了の実行（`System.stop(0)` 等）は Content または上位層に委譲する**。委譲方法は別設計（例: GameEvents に `:quit_requested` を送る、Content がコールバックを登録する等）とする。

4. **Content の components 更新**
   - `Content.CanvasTest.components/0` で、`Device.Mouse` と `Device.Keyboard` の両方を列挙する。

5. 旧ファイル `apps/contents/lib/contents/canvas_test/input_component.ex` を削除する。

---

### Phase 3: 描画の役割分割（renderer/render.ex + 値は Playing、メッシュ・シェーダーは器）

#### 3.1 設計

- **値の定義**: 描画に使う具体的な値（カメラパラメータ、色、グリッドサイズ、ワールドパネル文言、HUD レイアウトなど）は **`apps/contents/lib/contents/canvas_test/playing.ex`**（または Content.CanvasTest）で定義する。
- **Rendering.Render** (`rendering/render.ex`): 役割は「**どのメッシュをどのシェーダーで描画するか**」に限定する。メッシュとシェーダーを**参照するだけ**で、クライアントへ送る「器」（描画コマンドの組み立て・送信の枠）だけを提供する。具体的な頂点データやシェーダー実装は持たない。
- **メッシュ（器）**: 以下をクライアントに投げるためのモジュールとして用意する。中身は「メッシュ種別とパラメータを返す／エンコードする」程度の骨格でよい。
  - `apps/contents/lib/components/category/procedural/meshes/box.ex`
  - `apps/contents/lib/components/category/procedural/meshes/quad.ex`
- **シェーダー（器）**: 以下をクライアントに投げるためのモジュールとして用意する。中身は「シェーダー種別とパラメータを返す／エンコードする」程度の骨格でよい。
  - `apps/contents/lib/components/category/shader/skybox.ex`
  - `apps/contents/lib/components/category/shader/pbs_metallic.ex`

#### Step 3-2: ファイル作成と参照関係

1. **メッシュ（器）の新規作成**
   - `apps/contents/lib/components/category/procedural/meshes/box.ex` — Box メッシュをクライアントに渡すための定義・参照用。
   - `apps/contents/lib/components/category/procedural/meshes/quad.ex` — Quad メッシュをクライアントに渡すための定義・参照用。

2. **シェーダー（器）の新規作成**
   - `apps/contents/lib/components/category/shader/skybox.ex` — Skybox シェーダーをクライアントに渡すための定義・参照用。
   - `apps/contents/lib/components/category/shader/pbs_metallic.ex` — PBS Metallic シェーダーをクライアントに渡すための定義・参照用。

3. **Rendering.Render の作成**
   - **新規作成:** `apps/contents/lib/components/category/rendering/render.ex`（モジュール: `Contents.Components.Category.Rendering.Render`）
   - 役割: メッシュとシェーダーを**参照**し、「どのメッシュをどのシェーダーで描画するか」を組み立て、クライアントへ投げる器だけを提供する。具体的な値（カメラ・色・グリッド等）は **Playing** から渡されるか、state から取得する想定。
   - 移動元の `render_component.ex` のうち、フレーム送信の枠と、メッシュ/シェーダー参照に相当する部分をここに置く。値の定義は Playing に移す。

4. **Playing での値定義**
   - カメラ FOV・near/far、色、グリッドサイズ、ワールドパネル用テキスト一覧、HUD の rect/vertical_layout などの**値**は、`Content.CanvasTest.Playing`（または Content）で定義する。Render はそれらを引数や state から受け取り、メッシュ・シェーダーと組み合わせてクライアントへ送る。

5. 旧ファイル `apps/contents/lib/contents/canvas_test/render_component.ex` を削除する。

6. **Content の components 更新**
   - `Content.CanvasTest.components/0` に `Contents.Components.Category.Rendering.Render` を登録する。

---

## 3. 移行後の構成

```
apps/contents/lib/
  contents/
    canvas_test.ex
    canvas_test/
      playing.ex                    # Content.CanvasTest.Playing（値の定義もここ）
  components/
    category/
      device/
        mouse.ex                    # Contents.Components.Category.Device.Mouse
        keyboard.ex                 # Contents.Components.Category.Device.Keyboard
      rendering/
        render.ex                   # Contents.Components.Category.Rendering.Render（メッシュ・シェーダー参照、クライアントへ投げる器）
      procedural/
        meshes/
          box.ex                    # Box メッシュの器
          quad.ex                   # Quad メッシュの器
      shader/
        skybox.ex                   # Skybox シェーダーの器
        pbs_metallic.ex             # PBS Metallic シェーダーの器
      ui/
        ...                         # 既存のまま
```

---

## 4. 終了処理の委譲（設計）

- **現状**: コンポーネント内で `{:ui_action, "__quit__"}` を受け取ると `System.stop(0)` を直接呼んでいる。
- **方針**: **終了はコンテンツまたは上位層に委譲する**。
  - Device.Keyboard（または UI アクションを扱う層）では、`__quit__` を受け取ったら「終了要求」を state に書くか、イベントとして送るだけにする。
  - 実際に `System.stop(1)` 等を呼ぶのは、Content モジュールのコールバック、または GameEvents / ルームループ等の上位層とする。
- 実施時: Keyboard から `System.stop(0)` を削除し、終了要求の通知方法（例: `send(pid, :quit_requested)`、GameEvents の新イベント、Content の `on_ui_action/2` など）を決め、Content または上位で終了処理を実行するようにする。

---

## 5. 検証

- `mix compile` が通ること。
- `config :server, :current, Content.CanvasTest` で起動し、従来どおり動作すること。
  - マウス: 移動入力・マウスデルタ・カーソルグラブ。
  - キーボード: Sprint、ESC（HUD トグル）、Quit（終了は委譲先で実行されることを確認）。
  - 描画: HUD 表示/非表示、ワールドパネル、メッシュ・シェーダー経由の描画。

---

## 6. 参照

- [contents-components-reorganization-procedure.md](./contents-components-reorganization-procedure.md) — 共有コンポーネント再配置の手順・方針
- [contents-migration-plan.md](./contents-migration-plan.md) — 既存コンテンツ移行プラン（Phase 2 CanvasTest 完了済み）
