# Rust: desktop_input — デスクトップ入力・ウィンドウ・イベントループ

## 概要

`desktop_input` は **winit** によるウィンドウ生成とイベントループを担当します。`desktop_render` の `Renderer` を用いて描画しますが、イベントループの所有権はここにあります。

- **パス**: `native/desktop_input/`
- **依存**: `desktop_render`, `winit`, `pollster`

---

## クレート構成

```mermaid
graph LR
    DINPUT[desktop_input]
    DRENDER[desktop_render]

    DINPUT -->|依存| DRENDER
```

---

## run_desktop_loop

### シグネチャ

```rust
pub fn run_desktop_loop<B: RenderBridge>(bridge: B, config: WindowConfig) -> Result<(), String>
```

`RenderBridge` トレイトを実装した任意のブリッジを受け取り、winit の `EventLoop` を構築して `ApplicationHandler` として実行します。

### 利用側

| 呼び出し元 | ブリッジ | 用途 |
|:---|:---|:---|
| `nif`（`run_render_thread`） | `NativeRenderBridge` | ローカル NIF モード |
| `client_desktop` | `NetworkRenderBridge` | Zenoh リモートモード |

---

## desktop_loop.rs — イベントハンドリング

### DesktopApp 構造体

- `bridge: B` — RenderBridge 実装
- `config: WindowConfig` — ウィンドウ設定
- `window: Option<Arc<Window>>`
- `renderer: Option<Renderer>`
- `ui_state: GameUiState`
- `cursor_grabbed: bool`
- `suppress_grab_frames: u8` — グラブ解除直後の誤検知防止

### イベントフロー

```mermaid
flowchart TD
    RESUMED[resumed]
    DEVICE[device_event]
    WINDOW[window_event]

    RESUMED -->|初回| CREATE[ウィンドウ生成]
    CREATE --> RENDERER[Renderer::new]
    RENDERER --> REDRAW[request_redraw]

    DEVICE -->|cursor_grabbed| MOUSE[on_raw_mouse_motion]
    WINDOW -->|CloseRequested| EXIT[event_loop.exit]
    WINDOW -->|Focused false| FOCUS[on_focus_lost]
    WINDOW -->|MouseInput| GRAB[カーソルグラブ切替]
    WINDOW -->|KeyboardInput| KEY[on_raw_key]
    WINDOW -->|Resized| RESIZE[renderer.resize]
    WINDOW -->|RedrawRequested| NEXT[next_frame + render + on_ui_action]
```

### イベント別処理

| イベント | 処理 |
|:---|:---|
| `resumed` | ウィンドウ未生成なら `create_window` → `Renderer::new`（pollster::block_on）→ `request_redraw` |
| `DeviceEvent::MouseMotion` | `cursor_grabbed` 時のみ `bridge.on_raw_mouse_motion(dx, dy)` |
| `WindowEvent::CloseRequested` | `event_loop.exit()` |
| `WindowEvent::Focused(false)` | グラブ解除、`bridge.on_focus_lost()` |
| `WindowEvent::MouseInput` | マウスクリックでカーソルグラブ切替（`suppress_grab_frames` で誤検知抑制） |
| `WindowEvent::KeyboardInput` | `repeat` を無視し、`bridge.on_raw_key(code, state)` |
| `WindowEvent::Resized` | `renderer.resize(width, height)` |
| `WindowEvent::RedrawRequested` | `bridge.next_frame()` → `frame.cursor_grab` でグラブ同期 → `renderer.update_instances` → `renderer.render` → `on_ui_action` → `request_redraw` |

### カーソルグラブ

- マウスクリックで `cursor_grabbed` をトグル
- `frame.cursor_grab` が `Some(grab)` ならその値に同期
- `suppress_grab_frames` でグラブ解除直後の余計な再グラブを防止

---

## ソースコードレベルの流れ

### モジュール構成とエントリポイント

```mermaid
flowchart TB
    subgraph lib_rs [lib.rs]
        MOD[mod desktop_loop]
        EXPORT[pub use desktop_loop::run_desktop_loop]
        MOD --> EXPORT
    end

    subgraph callers [呼び出し元]
        DC[client_desktop::main]
        DC --> |NetworkRenderBridge, WindowConfig| RUN
    end

    subgraph desktop_loop_rs [desktop_loop.rs]
        RUN[run_desktop_loop&lt;B: RenderBridge&gt;]
    end

    EXPORT -.-> RUN
```

### run_desktop_loop の起動シーケンス

```mermaid
flowchart TD
    subgraph run_desktop_loop ["run_desktop_loop (desktop_loop.rs:20-31)"]
        A[EventLoop::builder]
        B[cfg windows: builder.with_any_thread]
        C[event_loop.build]
        D[DesktopApp::new]
        E[event_loop.run_app]
        A --> B
        B --> C
        C --> D
        D --> E
    end

    subgraph DesktopApp_new ["DesktopApp::new (desktop_loop.rs:44-55)"]
        N1[bridge, config を保持]
        N2[window: None, renderer: None]
        N3[ui_state, cursor_grabbed, suppress_grab_frames 初期化]
    end
```

### ApplicationHandler イベントディスパッチ（ソース対応）

```mermaid
flowchart TD
    subgraph winit [winit EventLoop]
        LOOP[event_loop.run_app]
    end

    subgraph impl_ApplicationHandler ["impl ApplicationHandler for DesktopApp&lt;B&gt;"]
        DEVICE[device_event]
        RESUMED[resumed]
        WINDOW[window_event]
    end

    LOOP --> DEVICE
    LOOP --> RESUMED
    LOOP --> WINDOW

    subgraph device_event ["device_event (L70-76)"]
        D1{cursor_grabbed?}
        D2[DeviceEvent::MouseMotion]
        D3[bridge.on_raw_mouse_motion]
        D1 -->|Yes| D2
        D2 --> D3
    end

    subgraph resumed ["resumed (L79-102)"]
        R1{window.is_some?}
        R2[event_loop.create_window]
        R3[pollster::block_on Renderer::new]
        R4[window.request_redraw]
        R1 -->|No| R2
        R2 --> R3
        R3 --> R4
    end

    subgraph window_event ["window_event (L104-184)"]
        W1[renderer.handle_window_event]
        W2{event の match}
    end

    DEVICE --> device_event
    RESUMED --> resumed
    WINDOW --> W1
    W1 --> W2
```

### WindowEvent 分岐（ソース関数・処理の対応）

```mermaid
flowchart TD
    subgraph match_event ["match event (desktop_loop.rs:110-183)"]
        E1[CloseRequested]
        E2[Focused]
        E3[MouseInput]
        E4[KeyboardInput]
        E5[Resized]
        E6[RedrawRequested]
        E7[その他]
    end

    E1 --> A1[event_loop.exit]
    E2 --> A2[set_cursor_grabbed false]
    E2 --> A2b[bridge.on_focus_lost]
    E3 --> A3[suppress_grab_frames 確認]
    E3 --> A3b[set_cursor_grabbed true]
    E4 --> A4{event.repeat?}
    A4 -->|No| A4b[bridge.on_raw_key]
    E5 --> A5[renderer.resize]
    E6 --> REDRAW
    E7 --> NOOP["_ => {}"]

    subgraph REDRAW ["RedrawRequested 内 (L148-181)"]
        R1[bridge.next_frame]
        R2[frame.cursor_grab で set_cursor_grabbed 同期]
        R3[renderer.update_instances]
        R4[renderer.render]
        R5[on_ui_action]
        R6[window.request_redraw]
        R1 --> R2 --> R3 --> R4 --> R5 --> R6
    end
```

### RenderBridge トレイトとブリッジ実装

```mermaid
flowchart LR
    subgraph desktop_input ["desktop_input (呼び出し側)"]
        BRIDGE["bridge: B"]
    end

    subgraph RenderBridge_trait ["desktop_render::window::RenderBridge"]
        NF[next_frame]
        OUA[on_ui_action]
        ORK[on_raw_key]
        ORM[on_raw_mouse_motion]
        OFL[on_focus_lost]
    end

    subgraph implementations [実装]
        NRB[NetworkRenderBridge]
    end

    BRIDGE --> RenderBridge_trait
    RenderBridge_trait --> NRB
```

### ファイル・関数参照一覧

| ファイル | 行 | 関数/要素 | 役割 |
|:---|:---|:---|:---|
| `lib.rs` | 7-9 | `mod desktop_loop`, `pub use run_desktop_loop` | エクスポート |
| `desktop_loop.rs` | 20-31 | `run_desktop_loop` | エントリ、EventLoop 構築・起動 |
| `desktop_loop.rs` | 34-42 | `struct DesktopApp<B>` | アプリ状態 |
| `desktop_loop.rs` | 44-55 | `DesktopApp::new` | 初期化 |
| `desktop_loop.rs` | 56-67 | `set_cursor_grabbed` | カーソルグラブ切替 |
| `desktop_loop.rs` | 70-76 | `device_event` | 生マウス移動 |
| `desktop_loop.rs` | 79-102 | `resumed` | ウィンドウ・Renderer 生成 |
| `desktop_loop.rs` | 104-184 | `window_event` | ウィンドウイベント分岐 |
| `desktop_render/window.rs` | 33-39 | `trait RenderBridge` | ブリッジインターフェース |

---

## 関連ドキュメント

- [アーキテクチャ概要](../../overview.md)
- [client_desktop](../client_desktop.md)
- [desktop/render](./render.md)（RenderBridge トレイト定義）
- [desktop/input_openxr](./input_openxr.md)（VR 入力）
