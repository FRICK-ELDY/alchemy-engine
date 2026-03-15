# FormulaTest Phase 1 アーキテクチャ

> 作成日: 2026-03-12  
> 更新日: 2026-03-15（Scene の位置づけを明示）  
> 対象: Phase 1 移行後の FormulaTest が通る全アーキテクチャを記載する。  
> 参照: [fix_contents.md](./fix_contents.md), [scene-and-object.md](./scene-and-object.md)

---

## 1. 概要

FormulaTest は、新アーキテクチャ（structs / nodes / components / objects / **scenes**）の動作を検証するコンテンツである。Phase 1 移行後、以下を用いて 5 パターンの式計算を行い、結果を HUD に表示する。

- **Structs**: データ型（Transform 等）
- **Nodes**: Value, Add, Sub, Equals（handle_sample による Logic フロー）
- **Objects**: Struct, CreateEmptyChild（空間階層）
- **Scenes**: Scenes.Playing（時間軸。Object ツリーのルート参照、遷移管理）
- **Contents**: Content モジュール、Core.Component（エンジン統合）

---

## 2. Six Pillars と使用モジュール（Scene 追加）

```mermaid
flowchart TB
    subgraph contents["Contents（体験）"]
        C1["Content.FormulaTest"]
    end

    subgraph scenes["Scenes（時間軸）"]
        C2["Scenes.Playing"]
    end

    subgraph objects["Objects（空間軸）"]
        O1["Contents.Objects.Core.Struct"]
        O2["CreateEmptyChild"]
    end

    subgraph components["Components（状態のピア・エンジン統合）"]
        CP1["InputComponent"]
        CP2["RenderComponent"]
        CP3["LocalUserComponent（注入）"]
        CP4["TelemetryComponent（注入）"]
    end

    subgraph nodes["Nodes（論理のピア）"]
        N1["Value"]
        N2["Add"]
        N3["Sub"]
        N4["Equals"]
    end

    subgraph structs["Structs（データの形）"]
        S1["Transform"]
        S2["Value.Float"]
    end

    contents --> scenes
    scenes --> objects
    objects --> components
    components --> nodes
    nodes --> structs
```

---

## 3. モジュール一覧

### 3.1 Contents 層

| モジュール | 役割 | パス |
|------------|------|------|
| `Content.FormulaTest` | コンテンツ定義。Core.ContentBehaviour を実装 | `contents/formula_test.ex` |

### 3.2 Scenes 層（時間軸）

| モジュール | 役割 | パス |
|------------|------|------|
| `Content.FormulaTest.Scenes.Playing` | メインシーン。Nodes を実行し Object を構築。root_object（着地点）を state に保持 | `contents/formula_test/scenes/playing.ex` |

### 3.3 Objects 層

| モジュール | 役割 | パス |
|------------|------|------|
| `Contents.Objects.Core.Struct` | オブジェクト構造体（name, parent, tag, active, persistent, transform） | `objects/core/struct.ex` |
| `Contents.Objects.Core.CreateEmptyChild` | 空の子オブジェクト作成 | `objects/core/create_empty_child.ex` |

### 3.4 Components 層（Core.Component = エンジン用）

| モジュール | 役割 | パス |
|------------|------|------|
| `Content.FormulaTest.InputComponent` | ESC で HUD トグル、__quit__ で終了 | `contents/formula_test/input_component.ex` |
| `Content.FormulaTest.RenderComponent` | HUD に検証結果を描画、NIF へ frame 送信 | `contents/formula_test/render_component.ex` |
| `Contents.LocalUserComponent` | キー・マウス入力（ComponentList により注入） | `contents/local_user_component.ex` |
| `Contents.TelemetryComponent` | 入力状態参照用（ComponentList により注入） | `contents/telemetry_component.ex` |

### 3.5 Nodes 層

| モジュール | 役割 | 使用するコールバック | パス |
|------------|------|----------------------|------|
| `Contents.Nodes.Category.Core.Input.Value` | 定数値入力。context[:value] を返す | handle_sample | `nodes/category/core/input/value.ex` |
| `Contents.Nodes.Category.Operators.Add` | 加算。%{a:, b:} → a + b | handle_sample | `nodes/category/operators/add.ex` |
| `Contents.Nodes.Category.Operators.Sub` | 減算。%{a:, b:} → a - b | handle_sample | `nodes/category/operators/sub.ex` |
| `Contents.Nodes.Category.Operators.Equals` | 比較。%{a:, b:, op:} → eq/lt/gt 等 | handle_sample | `nodes/category/operators/equals.ex` |

### 3.6 Structs 層

| モジュール | 役割 | パス |
|------------|------|------|
| `Structs.Category.Space.Transform` | 位置・回転・スケール | `structs/category/space/transform.ex` |
| `Structs.Category.Value.Float` | float, t3, quaternion 等の型定義 | `structs/category/value/float.ex` |

### 3.7 エンジン・インフラ

| モジュール | 役割 |
|------------|------|
| `Core.ContentBehaviour` | コンテンツの契約（components, flow_runner, initial_scenes 等） |
| `Core.Component` | エンジンが呼ぶコールバック（on_event, on_nif_sync 等） |
| `Contents.SceneBehaviour` | シーンの契約（init, update, render_type） |
| `Contents.Scenes.Stack` | シーンスタック管理 |
| `Contents.Events.Game` | フレームイベント受信・コンポーネント dispatch |
| `Contents.ComponentList` | コンポーネントリスト解決（LocalUser, Telemetry 注入） |
| `Core.Config` | 現在のコンテンツ取得（config :server, :current） |
| `Core.RoomRegistry` | ルーム・イベントハンドラ登録 |
| `Content.MessagePackEncoder` | frame の MessagePack エンコード |
| `Contents.FrameBroadcaster` | frame をクライアントへ配信 |
| `Content.MeshDef` | グリッド平面の頂点生成 |

---

## 4. 依存関係（依存方向）

```mermaid
flowchart LR
    subgraph structs["Structs"]
        S1["Transform"]
        S2["Float"]
    end

    subgraph objects["Objects"]
        O1["Struct"]
        O2["CreateEmptyChild"]
    end

    subgraph scenes["Scenes（時間軸）"]
        P["Scenes.Playing"]
    end

    subgraph nodes["Nodes"]
        N1["Value"]
        N2["Add"]
        N3["Sub"]
        N4["Equals"]
    end

    subgraph components["Core.Component"]
        C1["InputComponent"]
        C2["RenderComponent"]
    end

    S1 --> O1
    O1 --> P
    O2 --> P
    N1 --> P
    N2 --> P
    N3 --> P
    N4 --> P
    C1 --> P
    C2 --> P
    P --> C2
```

※ Scenes.Playing は Object ツリーのルート（root_object：着地点）を保持。Objects は Scenes に依存しない。

---

## 5. 実行フロー

### 5.1 起動〜init

```mermaid
sequenceDiagram
    participant Config as Core.Config
    participant Content as Content.FormulaTest
    participant CL as ComponentList
    participant GE as GameEvents
    participant SS as SceneStack
    participant Playing as Scenes.Playing
    participant Nodes as Value/Add/Sub/Equals
    participant Objects as Struct/CreateEmptyChild

    Config->>Content: current()
    CL->>Content: components()
    GE->>Content: initial_scenes()
    Content->>SS: push(Playing, %{})
    SS->>Playing: init(%{})
    Playing->>Nodes: handle_sample (5パターン)
    Nodes-->>Playing: formula_results
    Playing->>Objects: new, create
    Objects-->>Playing: root_object, child_object
    Playing-->>SS: {:ok, state}
```

### 5.2 ノード実行（Scenes.Playing 内）

各テストは `handle_sample(inputs, context)` を直接呼び出す。

```mermaid
flowchart LR
    subgraph add_inputs["test_add_inputs"]
        V1a["Value(1)"] --> A1["Add"]
        V1b["Value(2)"] --> A1
        A1 --> R1["3.0"]
    end

    subgraph constants["test_constants"]
        V2a["Value(10)"] --> A2["Add"]
        V2b["Value(3)"] --> A2
        A2 --> R2["13"]
    end

    subgraph comparison["test_comparison"]
        V3a["Value(1.0)"] --> E1["Equals :lt"]
        V3b["Value(2.0)"] --> E1
        E1 --> R3["true"]
    end

    subgraph store["test_store"]
        V4a["Value(0)"] --> A3["Add"]
        V4b["Value(1)"] --> A3
        A3 --> R4["1"]
    end

    subgraph multiple["test_multiple_outputs"]
        V5a["Value(2)"] --> A4["Add"]
        V5b["Value(3)"] --> A4
        V5a --> S1["Sub"]
        V5b --> S1
        A4 --> R5a["5.0"]
        S1 --> R5b["-1.0"]
    end
```

| テスト | 呼び出し |
|--------|----------|
| test_add_inputs | Value(1), Value(2) → Add → 3.0 |
| test_constants | Value(10), Value(3) → Add → 13 |
| test_comparison | Value(1.0), Value(2.0) → Equals(:lt) → true |
| test_store | Value(0), Value(1) → Add → 1（Store 未実装のため加算で代用） |
| test_multiple_outputs | Value(2), Value(3) → Add → 5, Sub → -1 |

### 5.3 フレームごとのループ

```mermaid
sequenceDiagram
    participant Rust
    participant GE as GameEvents
    participant SS as SceneStack
    participant Playing as Scenes.Playing
    participant RC as RenderComponent
    participant MP as MessagePackEncoder
    participant FB as FrameBroadcaster

    Rust->>GE: {:frame_events, events}
    GE->>SS: current scene
    SS->>GE: Playing, state
    GE->>Playing: update(context, state)
    Playing-->>GE: {:continue, state}
    GE->>RC: on_nif_sync(context)
    RC->>SS: get_scene_state(Playing)
    SS-->>RC: state
    RC->>MP: encode_frame(commands, camera, ui)
    RC->>FB: put(room_id, frame_binary)
```

### 5.4 入力イベント

```mermaid
sequenceDiagram
    participant LUC as LocalUserComponent
    participant GE as GameEvents
    participant IC as InputComponent
    participant SS as SceneStack
    participant Playing as Scenes.Playing

    LUC->>GE: key_pressed / raw_key
    GE->>IC: on_event({:key_pressed, :escape}, context)
    IC->>SS: update_by_module(Playing, &toggle_hud/1)
    SS->>Playing: state 更新 (hud_visible)
```

---

## 6. ファイルパス一覧（FormulaTest 通過に必要なもの）

```
apps/contents/lib/
├── contents/
│   ├── formula_test.ex
│   ├── formula_test/
│   │   ├── input_component.ex
│   │   ├── render_component.ex
│   │   └── scenes/
│   │       └── playing.ex
│   ├── component_list.ex
│   ├── scene_behaviour.ex
│   ├── scene_stack.ex
│   ├── game_events.ex
│   ├── frame_broadcaster.ex
│   ├── local_user_component.ex
│   ├── telemetry_component.ex
│   ├── message_pack_encoder.ex (Content 名前空間)
│   └── mesh_def.ex (Content 名前空間)
├── objects/
│   └── core/
│       ├── struct.ex
│       └── create_empty_child.ex
├── nodes/
│   ├── core/
│   │   └── behaviour.ex
│   └── category/
│       ├── core/input/value.ex
│       └── operators/
│           ├── add.ex
│           ├── sub.ex
│           └── equals.ex
└── structs/
    └── category/
        ├── space/transform.ex
        └── value/float.ex

apps/core/lib/
├── content_behaviour.ex
├── component.ex
├── config.ex
├── room_registry.ex
└── (NifBridge, MapLoader 等は GameEvents 経由で使用)
```

---

## 7. データフロー概要

```mermaid
flowchart TB
    subgraph rust["Rust"]
        FE["frame_events"]
    end

    subgraph engine["エンジン"]
        CFG["Core.Config\ncurrent=FormulaTest"]
        GE["GameEvents"]
        SS["SceneStack"]
        CL["ComponentList"]
    end

    subgraph scene["Scenes（時間軸）"]
        UP["Playing.update\n{:continue, state}"]
    end

    subgraph comp["Components"]
        RC["RenderComponent\non_nif_sync"]
        IC["InputComponent\non_event"]
    end

    subgraph output["出力"]
        MP["MessagePackEncoder"]
        FB["FrameBroadcaster"]
    end

    CFG --> GE
    FE --> GE
    GE --> SS
    SS --> UP
    GE --> RC
    GE --> IC
    RC --> MP
    MP --> FB
    IC --> SS
```

---

## 8. 備考

- **Executor**: 未使用。Scenes.Playing が Nodes を直接 `handle_sample` で呼び出す。
- **Core.FormulaGraph**: 使用していない（VampireSurvivor 等の他コンテンツで使用中のため削除していない）。
- **physics_scenes**: FormulaTest では空リスト（物理演算なし）。
