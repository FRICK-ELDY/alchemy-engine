# LocalUserComponent 実装手順

> 設計: [local-user-component-design.md](../plan/local-user-component-design.md)

---

## 前提

- vampire_survivor を最初の対象コンテンツとする
- 後方互換を維持し、他コンテンツ（asteroid_arena, canvas_test 等）は従来の InputHandler を継続使用
- 段階的に実装し、各ステップで動作確認可能にする

---

## 実装ステップ一覧

| 手順 | 内容 | 依存 |
|:-----|:-----|:-----|
| 1 | ContentBehaviour に `local_user_input_module/0` 追加 | - |
| 2 | LocalUserComponent スケルトン作成 | 1 |
| 3 | GameEvents: raw_key / focus_lost をコンポーネントに dispatch | 2 |
| 4 | GameEvents: `maybe_set_input_and_broadcast` で local_user_input_module を参照 | 2 |
| 5 | LocalUserComponent のロジック実装（キーマップ、ETS、on_nif_sync） | 2 |
| 6 | vampire_survivor に LocalUserComponent を組み込み | 5 |
| 7 | InputHandler の raw_key / focus_lost 呼び出しを conditional に変更 | 3, 4 |
| 8 | テスト・動作確認 | 6 |

---

## 手順 1: ContentBehaviour に `local_user_input_module/0` 追加

### 1.1 変更対象

`apps/core/lib/core/content_behaviour.ex`

### 1.2 追加内容

```elixir
@doc """
ローカルユーザー入力を提供するモジュールを返す。

- `nil`（デフォルト）: Core.InputHandler を従来通り使用
- `module`: 指定モジュールの `get_move_vector/1` を呼んで player_input を取得。
            raw_key / raw_mouse_motion / focus_lost はコンポーネントに dispatch され、
            当該モジュールが on_event で処理する。
"""
@callback local_user_input_module() :: module() | nil
```

- `@optional_callbacks` に `local_user_input_module: 0` を追加
- デフォルト実装は提供しない（`nil` を返す想定のため、未実装時は `function_exported?` で分岐）

---

## 手順 2: LocalUserComponent スケルトン作成

### 2.1 新規ファイル

`apps/contents/lib/contents/vampire_survivor/local_user_component.ex`

### 2.2 スケルトン構成

```elixir
defmodule Content.VampireSurvivor.LocalUserComponent do
  @moduledoc """
  ローカルユーザーのキーボード・マウス入力を管理するコンポーネント。

  raw_key, raw_mouse_motion, focus_lost を受け取り、
  コンテンツ内で move_input, sprint, key_pressed として利用する。
  """
  @behaviour Core.Component

  @table :local_user_input

  # 1. init: ETS テーブル作成（存在しない場合）
  # 2. on_event({:raw_key, key, state}, context)
  # 3. on_event({:mouse_delta, dx, dy}, context)
  # 4. on_event({:focus_lost}, context)
  # 5. on_nif_sync(context): frame_injection に player_input をマージ
  # 6. get_move_vector(room_id): 公開 API（GameEvents から呼ばれる）

  def init(_world_ref), do: :ok

  def on_event(_event, _context), do: :ok
  def on_nif_sync(_context), do: :ok

  def get_move_vector(room_id) do
    case :ets.lookup(@table, {room_id, :move}) do
      [{{^room_id, :move}, vec}] -> vec
      [] -> {0, 0}
    end
  end
end
```

---

## 手順 3: GameEvents: raw_key / focus_lost をコンポーネントに dispatch

### 3.1 変更対象

`apps/contents/lib/contents/game_events.ex`

### 3.2 変更内容

**handle_info({:raw_key, ...})** の修正:

```elixir
# Before
def handle_info({:raw_key, key, key_state}, state)
    when is_atom(key) and key_state in [:pressed, :released] do
  Core.InputHandler.raw_key(key, key_state)
  {:noreply, state}
end

# After
def handle_info({:raw_key, key, key_state}, state)
    when is_atom(key) and key_state in [:pressed, :released] do
  content = current_content()
  local_mod = if function_exported?(content, :local_user_input_module, 0) do
    content.local_user_input_module()
  else
    nil
  end

  if is_nil(local_mod) do
    Core.InputHandler.raw_key(key, key_state)
  else
    now = now_ms()
    context = build_context(state, now, now - state.start_ms, flow_runner(state))
    dispatch_event_to_components({:raw_key, key, key_state}, context)
  end
  {:noreply, state}
end
```

**handle_info(:focus_lost)** の修正:

```elixir
# Before
def handle_info(:focus_lost, state) do
  Core.InputHandler.focus_lost()
  {:noreply, state}
end

# After
def handle_info(:focus_lost, state) do
  content = current_content()
  local_mod = if function_exported?(content, :local_user_input_module, 0) do
    content.local_user_input_module()
  else
    nil
  end

  if is_nil(local_mod) do
    Core.InputHandler.focus_lost()
  else
    now = now_ms()
    context = build_context(state, now, now - state.start_ms, flow_runner(state))
    dispatch_event_to_components(:focus_lost, context)
  end
  {:noreply, state}
end
```

---

## 手順 4: GameEvents: maybe_set_input_and_broadcast で local_user_input_module を参照

### 4.1 変更対象

`apps/contents/lib/contents/game_events.ex` の `maybe_set_input_and_broadcast/5`

### 4.2 変更内容

```elixir
defp maybe_set_input_and_broadcast(state, mod, physics_scenes, events, context) do
  if mod in physics_scenes do
    content = current_content()
    local_mod = if function_exported?(content, :local_user_input_module, 0) do
      content.local_user_input_module()
    else
      nil
    end

    {dx, dy} = if is_nil(local_mod) do
      Core.InputHandler.get_move_vector()
    else
      local_mod.get_move_vector(state.room_id)
    end

    inj = Process.get(:frame_injection, %{})
    Process.put(:frame_injection, Map.put(inj, :player_input, {dx * 1.0, dy * 1.0}))

    run_component_physics_callbacks(context)

    unless events == [], do: Core.EventBus.broadcast(events)
  end

  :ok
end
```

---

## 手順 5: LocalUserComponent のロジック実装

### 5.1 ETS テーブル

- テーブル名: `:local_user_input`
- `init` で作成。複数ルーム存在時は同一テーブルを共有するため、既存ならスキップ:

```elixir
def init(_world_ref) do
  if :ets.whereis(@table) == :undefined do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
  end
  :ok
end
```

### 5.2 キーマッピング（InputHandler から移植）

```elixir
# move_vector_from_keys/1
# - :w, :arrow_up → dy -= 1
# - :s, :arrow_down → dy += 1
# - :a, :arrow_left → dx -= 1
# - :d, :arrow_right → dx += 1

# sprint_from_keys/1
# - :shift_left, :shift_right → sprint
```

### 5.3 on_event 実装

- `{:raw_key, key, state}`: keys_held を更新、move_vector 計算、ETS に保存。必要なら `send(event_handler, {:move_input, dx, dy})` 等で他コンポーネントへ配信
- `{:mouse_delta, dx, dy}`: 現行 vampire_survivor はマウスで移動しないため、必要に応じて状態保持のみ（将来拡張用）
- `:focus_lost`: keys_held を空に、move_vector を {0,0} に、sprint を false にリセット

### 5.4 意味論的イベントの配信

- `{:move_input, dx, dy}`, `{:sprint, pressed}`, `{:key_pressed, :escape}` を GameEvents に送信する必要がある場合:
  - `context` に `event_handler` が含まれていない場合は、`Content.VampireSurvivor` の `event_handler(room_id)` を使用
  - 設計上、LevelUp 等のシーンでは `key_pressed` が必要。LocalUserComponent から `send(handler, {:key_pressed, :escape})` を送る

### 5.5 on_nif_sync

- `player_input` は `maybe_set_input_and_broadcast` で既に frame_injection に投入されている
- LocalUserComponent は `get_move_vector` で提供するため、`on_nif_sync` でのマージは不要
- ただし、コンテンツによっては LocalUserComponent が直接 frame_injection を書く設計も可能。現状は GameEvents が get_move_vector を呼ぶ方式で統一

---

## 手順 6: vampire_survivor に LocalUserComponent を組み込み

### 6.1 Content.VampireSurvivor の修正

`apps/contents/lib/contents/vampire_survivor.ex`:

```elixir
# components/0 に LocalUserComponent を先頭に追加
def components do
  [
    Content.VampireSurvivor.LocalUserComponent,
    Content.VampireSurvivor.SpawnComponent,
    Content.VampireSurvivor.LevelComponent,
    Content.VampireSurvivor.BossComponent,
    Content.VampireSurvivor.RenderComponent
  ]
end

# local_user_input_module/0 を追加
def local_user_input_module, do: Content.VampireSurvivor.LocalUserComponent
```

### 6.2 ContentBehaviour の optional_callbacks

`local_user_input_module: 0` を `@optional_callbacks` に追加済みであることを確認。

---

## 手順 7: InputHandler の raw_key / focus_lost 呼び出しを conditional に変更

手順 3 で既に `local_mod` が `nil` のときのみ InputHandler を呼ぶ形にしているため、追加の変更は不要。

---

## 手順 8: テスト・動作確認

### 8.1 単体テスト

- `LocalUserComponent.get_move_vector/1` のテスト
- `on_event` で raw_key を渡したときの ETS 更新のテスト

### 8.2 結合テスト

1. vampire_survivor で起動
2. WASD でプレイヤーが移動することを確認
3. Shift でスプリント（vampire_survivor でスプリント機能がある場合）
4. Escape でメニュー等が反応することを確認
5. ウィンドウのフォーカスを外したとき、入力がリセットされることを確認

### 8.3 後方互換確認

1. `config :server, :current, Content.AsteroidArena` 等に切り替え
2. 従来通り InputHandler 経由で動作することを確認

---

## チェックリスト

- [ ] ContentBehaviour に `local_user_input_module/0` 追加
- [ ] LocalUserComponent スケルトン作成
- [ ] GameEvents: raw_key を conditional dispatch
- [ ] GameEvents: focus_lost を conditional dispatch
- [ ] GameEvents: maybe_set_input_and_broadcast で local_user_input_module 参照
- [ ] LocalUserComponent: キーマッピング・ETS・on_event 実装
- [ ] LocalUserComponent: get_move_vector/1 実装
- [ ] vampire_survivor: components に LocalUserComponent 追加
- [ ] vampire_survivor: local_user_input_module/0 実装
- [ ] 動作確認（vampire_survivor）
- [ ] 後方互換確認（asteroid_arena 等）
- [ ] `mix format` 実行

---

## 備考

- **raw_mouse_motion**: 現状は GameEvents が `{:mouse_delta, dx, dy}` としてコンポーネントに dispatch している。LocalUserComponent 導入後も、mouse_delta はコンポーネントに dispatch されるため、LocalUserComponent の `on_event({:mouse_delta, dx, dy})` で受信可能。
- **move_input の二重送信**: InputHandler は `send(handler, {:move_input, dx, dy})` を送っていた。LocalUserComponent が同様のイベントを送る場合、canvas_test 等の InputComponent が `{:move_input}` で state を更新しているコンテンツは、GameEvents の `handle_info({:move_input, ...})` が dispatch するため、LocalUserComponent からも send する必要がある。vampire_survivor は move_input をシーン state で持たず、frame_injection の player_input のみ使用しているため、LocalUserComponent から move_input を send する必要はない（LevelUp 等で使う場合は要検討）。
- **key_pressed**: LevelUp や BossAlert で Escape を押したときの挙動。現在は InputHandler が `send(handler, {:key_pressed, :escape})` を送っている。LocalUserComponent でも同様に送る必要がある。
