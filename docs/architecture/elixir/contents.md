# Elixir: contents — ゲームコンテンツ層

## 概要

`contents` はゲームコンテンツ（VampireSurvivor / AsteroidArena / SimpleBox3D / BulletHell3D / RollingBall / CanvasTest / FormulaTest）の実装と、シーン管理・メインゲームループのディスパッチを担当します。エンジン本体（[core](./core.md)）はゲームロジックを知らず、ContentBehaviour で定義されたインターフェースに従ってコンポーネントへ委譲します。描画は Zenoh 専用。RenderComponent が DrawCommand・Camera・UiCanvas を組み立て、`Contents.MessagePackEncoder` で MessagePack にエンコードし、`FrameBroadcaster.put(room_id, frame_binary)` で Zenoh へ publish する。

使用するコンテンツは `config/config.exs` の `config :server, :current, ...` で指定します（既定値は `Content.VampireSurvivor`）。

---

## コンテンツ設計パターン

各コンテンツは `ContentBehaviour` を実装するエントリポイントモジュールと、`Component` ビヘイビアを実装するコンポーネント群で構成されます。

```mermaid
graph LR
    CB["ContentBehaviour\n（エントリポイント）"]
    SC["SpawnComponent\non_ready: ワールド初期化"]
    LC["LevelComponent\non_frame_event: EXP・HP\non_nif_sync: NIF 注入"]
    BC["BossComponent\non_physics_process: ボス AI\non_nif_sync: ボス HP 注入"]
    RC["RenderComponent\non_nif_sync: FrameBroadcaster.put"]

    CB -->|components/0 で列挙| SC
    CB -->|components/0 で列挙| LC
    CB -->|components/0 で列挙| BC
    CB -->|components/0 で列挙| RC
```

> VampireSurvivor は Spawn / Level / Boss / Render の 4 コンポーネント。AsteroidArena は Spawn / Split の 2 コンポーネント。

---

## `Contents.SceneBehaviour` — シーンコールバック定義

各シーンが実装すべきコールバック。`apps/contents/lib/contents/scene_behaviour.ex` に定義。

```elixir
@callback init(init_arg)        :: {:ok, state}
@callback update(context, state) :: {:continue, new_state}
                                  | {:transition, transition, new_state}
@callback render_type()         :: atom()
```

**トランジション種別:**

| 種別 | 動作 |
|:---|:---|
| `:pop` | 現在のシーンをスタックから取り出す |
| `{:push, module, init_arg}` | 新しいシーンをスタックに積む |
| `{:replace, module, init_arg}` | 現在のシーンを置き換える |

---

## `Contents.Scenes.Stack` — シーンスタック管理 GenServer

シーンスタックを管理する GenServer。`apps/contents/lib/scenes/stack.ex` に定義。起動時に `content_module.initial_scenes()` からスタックを初期化します。`Server.Application` で `{Contents.Scenes.Stack, [content_module: content]}` として起動。

| 関数 | 説明 |
|:---|:---|
| `push_scene/2` | シーンをスタックに積む |
| `pop_scene/0` | 最上位シーンを取り出す |
| `replace_scene/2` | 最上位シーンを置き換える |
| `update_current/1` | 現在シーンの状態を更新 |
| `update_by_scene_type/3` | スタック内の特定シーン種別の状態を更新 |
| `get_scene_state/2` | スタック内の特定シーン種別の状態を取得 |

---

## `Contents.Events.Game` — メインゲームループ GenServer

Rust の 60Hz ゲームループから `{:frame_events, events}` を受信し、コンポーネントへ委譲する。contents 層に配置され、エンジン自体はゲームロジックを知らず、ディスパッチのみを担う。**イベント配送先**はこのモジュール（旧名 GameEvents）。Core.EventBus の `{:game_events, events}` や Zenoh の入力配送先もここを指す。他ドキュメント・コメントで「GameEvents」とある場合は本モジュールの旧名である。

**GenServer state:**

```elixir
%{
  room_id: atom(),
  world_ref: reference(),
  control_ref: reference(),
  last_tick: integer(),
  frame_count: integer(),
  start_ms: integer()
}
```

**フレーム処理フロー（毎フレーム）:**

```mermaid
flowchart TD
    R["Rust\n{:frame_events, events}"]
    BP{バックプレッシャー\n> 120 メッセージ?}
    FE[on_frame_event/2\n全コンポーネントへ配信]
    SC[flow_runner 経由で Scene.update/2\nシーン遷移判断]
    PHY[on_physics_process/1\nボス AI 等]
    NIF[on_nif_sync/1\nElixir state → Rust 注入]
    LOG[ログ・FrameCache\n60フレームごと]

    R --> BP
    BP -->|No: 通常処理| FE --> SC --> PHY --> NIF --> LOG
    BP -->|Yes: 軽量処理| FE --> SC
```

**シーン遷移パターン:**

```mermaid
stateDiagram-v2
    Playing --> LevelUp   : SpecialEntitySpawned / EXP 閾値超過
    LevelUp --> Playing   : 選択 / 3秒タイムアウト（auto_select）

    Playing --> BossAlert : ボス出現スケジュール到達
    BossAlert --> Playing : 3秒後にボスをスポーン

    Playing --> GameOver  : 死亡（HP <= 0）
    GameOver --> Playing  : リトライ
```

---

## コンテンツ実装

| コンテンツ | 説明 | 仕様 |
|:---|:---|:---|
| `Content.VampireSurvivor` | Spawn / Level / Boss / Render コンポーネント、レベルアップ・ボスアラート・ゲームオーバーシーン | [vampire_survivor.md](./contents/vampire_survivor.md) |
| `Content.AsteroidArena` | Spawn / Split コンポーネント、playing / game_over シーンのみ | [asteroid_arena.md](./contents/asteroid_arena.md) |
| `Content.SimpleBox3D` | Phase R-6 動作検証用 3D ゲーム | - |
| `Content.BulletHell3D` | 3D 弾幕避けゲーム | - |
| `Content.RollingBall` | 玉転がしゲーム | - |
| `Content.CanvasTest` | 描画テスト用（DrawCommand・UiCanvas・CanvasUI 動作検証） | [docs/task/canvas-test-design.md](../../task/canvas-test-design.md) |
| `Content.FormulaTest` | Formula エンジン検証（Elixir→Rust NIF VM→Elixir フロー、Input / Render コンポーネント） | - |

**補助モジュール**

| モジュール | 説明 |
|:---|:---|
| `Contents.ComponentList` | コンポーネント解決。LocalUserComponent・TelemetryComponent を自動注入 |
| `Contents.FrameBroadcaster` | Zenoh フレーム配信。`put(room_id, frame_binary)` で Process.put → GameEvents が ZenohBridge に配送 |
| `Contents.MessagePackEncoder` | RenderFrame の MessagePack エンコード |

---

## 関連ドキュメント

- [アーキテクチャ概要](../overview.md)
- [server](./server.md) / [core](./core.md) / [network](./network.md)
