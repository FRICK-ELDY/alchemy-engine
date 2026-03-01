# Credo 対応手順書

> 2026-03-01 の `mix credo --strict` 実行結果（63 ファイル・81 件）に基づく対応手順。
> 優先度の高い順に並べている。完了した項目には ✅ を付けること。

---

## サマリー

| カテゴリ | 件数 | 優先度 |
|:---|:---:|:---:|
| [C] Consistency（改行コード CRLF） | 52 | 🔴 最優先 |
| [R] Code Readability | 13 | 🟡 高 |
| [F] Refactoring opportunities | 10 | 🟡 高 |
| [W] Warning | 1 | 🟡 高 |
| [D] Software Design | 5 | 🟢 中 |

---

## CR-01: CRLF 改行コードの一括修正（52 件）

**対象**: `game_engine`・`game_content`・`game_network`・`game_server` の多数のファイル

**原因**: Windows 環境でファイルを作成したため CRLF になっている。
プロジェクトの他のファイルは LF であるため、Credo が不整合を検出している。

**対応方針**: `.gitattributes` で `text=auto eol=lf` を設定し、既存ファイルを LF に変換する。

**手順**:

1. プロジェクトルートに `.gitattributes` を作成（または確認）する

   ```
   * text=auto eol=lf
   *.bat text eol=crlf
   ```

   `.bat` ファイルは Windows で実行するため CRLF のまま維持する。

2. 対象ファイルを LF に一括変換する

   ```powershell
   # PowerShell で対象ファイルを LF に変換
   Get-ChildItem -Path apps -Recurse -Include "*.ex","*.exs" | ForEach-Object {
     $content = [System.IO.File]::ReadAllText($_.FullName)
     $converted = $content -replace "`r`n", "`n"
     [System.IO.File]::WriteAllText($_.FullName, $converted, [System.Text.UTF8Encoding]::new($false))
   }
   ```

3. `mix credo --strict` を再実行して [C] 件数がゼロになることを確認する

**対象ファイル一覧**（52 件）:

- `apps/game_engine/lib/game_engine.ex`
- `apps/game_engine/lib/game_engine/game_events.ex`
- `apps/game_engine/lib/game_engine/nif_bridge.ex`
- `apps/game_engine/lib/game_engine/nif_bridge_behaviour.ex`
- `apps/game_engine/lib/game_engine/scene_manager.ex`
- `apps/game_engine/lib/game_engine/scene_behaviour.ex`
- `apps/game_engine/lib/game_engine/content_behaviour.ex`
- `apps/game_engine/lib/game_engine/component.ex`
- `apps/game_engine/lib/game_engine/config.ex`
- `apps/game_engine/lib/game_engine/event_bus.ex`
- `apps/game_engine/lib/game_engine/frame_cache.ex`
- `apps/game_engine/lib/game_engine/input_handler.ex`
- `apps/game_engine/lib/game_engine/map_loader.ex`
- `apps/game_engine/lib/game_engine/room_registry.ex`
- `apps/game_engine/lib/game_engine/room_supervisor.ex`
- `apps/game_engine/lib/game_engine/save_manager.ex`
- `apps/game_engine/lib/game_engine/stats.ex`
- `apps/game_engine/lib/game_engine/stress_monitor.ex`
- `apps/game_engine/lib/game_engine/telemetry.ex`
- `apps/game_content/lib/game_content.ex`
- `apps/game_content/lib/game_content/entity_params.ex`
- `apps/game_content/lib/game_content/asteroid_arena.ex`
- `apps/game_content/lib/game_content/asteroid_arena/scenes/playing.ex`
- `apps/game_content/lib/game_content/asteroid_arena/scenes/game_over.ex`
- `apps/game_content/lib/game_content/asteroid_arena/spawn_system.ex`
- `apps/game_content/lib/game_content/asteroid_arena/spawn_component.ex`
- `apps/game_content/lib/game_content/asteroid_arena/split_component.ex`
- `apps/game_content/lib/game_content/vampire_survivor.ex`
- `apps/game_content/lib/game_content/vampire_survivor/boss_component.ex`
- `apps/game_content/lib/game_content/vampire_survivor/boss_system.ex`
- `apps/game_content/lib/game_content/vampire_survivor/level_component.ex`
- `apps/game_content/lib/game_content/vampire_survivor/level_system.ex`
- `apps/game_content/lib/game_content/vampire_survivor/spawn_component.ex`
- `apps/game_content/lib/game_content/vampire_survivor/spawn_system.ex`
- `apps/game_content/lib/game_content/vampire_survivor/scenes/playing.ex`
- `apps/game_content/lib/game_content/vampire_survivor/scenes/boss_alert.ex`
- `apps/game_content/lib/game_content/vampire_survivor/scenes/game_over.ex`
- `apps/game_content/lib/game_content/vampire_survivor/scenes/level_up.ex`
- `apps/game_network/lib/game_network.ex`
- `apps/game_network/lib/game_network/application.ex`
- `apps/game_network/lib/game_network/channel.ex`
- `apps/game_network/lib/game_network/endpoint.ex`
- `apps/game_network/lib/game_network/local.ex`
- `apps/game_network/lib/game_network/router.ex`
- `apps/game_network/lib/game_network/udp/protocol.ex`
- `apps/game_network/lib/game_network/udp/server.ex`
- `apps/game_network/lib/game_network/user_socket.ex`
- `apps/game_network/test/game_network_channel_test.exs`
- `apps/game_network/test/game_network_local_test.exs`
- `apps/game_network/test/game_network_udp_test.exs`
- `apps/game_network/test/support/local_test_helpers.ex`
- `apps/game_network/test/support/room_stubs.ex`
- `apps/game_server/lib/game_server.ex`

---

## CR-02: 述語関数の命名規則修正（2 件）

**カテゴリ**: [R] Code Readability

**ルール**: Elixir の慣習として述語関数は `is_` プレフィックスを使わず、`?` サフィックスを使う。

**対象**:

| ファイル | 現在 | 修正後 |
|:---|:---|:---|
| `apps/game_engine/lib/game_engine/nif_bridge.ex:65` | `is_player_dead` | `player_dead?` |
| `apps/game_engine/lib/game_engine.ex:26` | `is_player_dead?` | `player_dead?` |

**手順**:

1. `game_engine/nif_bridge.ex` の `is_player_dead` を `player_dead?` に改名する
2. `game_engine.ex` の `is_player_dead?` を `player_dead?` に改名する
3. 両ファイルの呼び出し元をすべて検索して更新する

   ```powershell
   rg "is_player_dead" apps/
   ```

---

## CR-03: `with` を `case` に変更（1 件）

**カテゴリ**: [R] Code Readability

**対象**: `apps/game_engine/lib/game_engine/game_events.ex:308`
（`handle_frame_events_main` 内）

**ルール**: `<-` 節が 1 つだけで `else` ブランチがある `with` は `case` で書く。

**修正パターン**:

```elixir
# ❌ 修正前
with {:ok, result} <- some_call() do
  process(result)
else
  {:error, reason} -> handle_error(reason)
end

# ✅ 修正後
case some_call() do
  {:ok, result} -> process(result)
  {:error, reason} -> handle_error(reason)
end
```

---

## CR-04: `@moduledoc` の追加（2 件）

**カテゴリ**: [R] Code Readability

**対象**:

| ファイル | モジュール |
|:---|:---|
| `apps/game_engine/lib/game_engine/save_manager.ex:1` | `GameEngine.SaveManager` |
| `apps/game_server/lib/game_server/application.ex:1` | `GameServer.Application` |

**手順**: 各モジュールの先頭に最低限の `@moduledoc` を追加する。

```elixir
@moduledoc """
（モジュールの責務を1〜2行で説明）
"""
```

---

## CR-05: 明示的 `try` を暗黙的 `try` に変更（4 件）

**カテゴリ**: [R] Code Readability

**対象**:

| ファイル | 関数 |
|:---|:---|
| `apps/game_engine/lib/game_engine/save_manager.ex:67` | `save_high_score/1` |
| `apps/game_engine/lib/game_engine/save_manager.ex:31` | `save_session/1` |
| `apps/game_engine/lib/game_engine/game_events.ex:704` | `maybe_snapshot_check/1` |
| `apps/game_network/lib/game_network/router.ex:49` | `fetch_rooms/1` |

**修正パターン**:

```elixir
# ❌ 修正前
def save_session(data) do
  try do
    File.write!(path, data)
  rescue
    e -> {:error, e}
  end
end

# ✅ 修正後
def save_session(data) do
  File.write!(path, data)
rescue
  e -> {:error, e}
end
```

---

## CR-06: 引数なし関数の不要な括弧を除去（2 件）

**カテゴリ**: [R] Code Readability

**対象**:

| ファイル | 関数 |
|:---|:---|
| `apps/game_engine/lib/game_engine/nif_bridge.ex:47` | `create_game_loop_control()` |
| `apps/game_engine/lib/game_engine/nif_bridge.ex:14` | `create_world()` |

**修正パターン**:

```elixir
# ❌ 修正前
def create_world() do ... end

# ✅ 修正後
def create_world do ... end
```

---

## CR-07: `alias` のアルファベット順修正（1 件）

**カテゴリ**: [R] Code Readability

**対象**: `apps/game_network/test/game_network_local_test.exs:14`
（`GameNetwork.Test.StubRoom` の alias 順序）

**手順**: `alias` ブロック内の並び順をアルファベット順に揃える。

---

## CR-08: `frame_cache.ex` の明示的 `try` を修正（1 件）

**カテゴリ**: [R] Code Readability

**対象**: `apps/game_engine/lib/game_engine/frame_cache.ex:34`（`get/1`）

CR-05 と同じパターンで修正する。

---

## CR-09: `with` が `<-` で始まっていない（1 件）

**カテゴリ**: [F] Refactoring

**対象**: `apps/game_engine/lib/game_engine/game_events.ex:354`
（`handle_frame_events_main` 内）

**修正パターン**:

```elixir
# ❌ 修正前（with が非パターンマッチ式で始まっている）
with result = compute_something(),
     {:ok, val} <- validate(result) do
  ...
end

# ✅ 修正後（非パターンマッチ式を with の外に出す）
result = compute_something()
with {:ok, val} <- validate(result) do
  ...
end
```

---

## CR-10: `unless` に `else` ブロックがある（1 件）

**カテゴリ**: [F] Refactoring

**対象**: `apps/game_content/lib/game_content/vampire_survivor/scenes/playing.ex:191`
（`maybe_level_up/1`）

**修正パターン**:

```elixir
# ❌ 修正前
unless condition do
  do_something()
else
  do_other()
end

# ✅ 修正後（if に変換）
if condition do
  do_other()
else
  do_something()
end
```

---

## CR-11: ネストが深すぎる関数の分解（5 件）

**カテゴリ**: [F] Refactoring

**対象**:

| ファイル | 関数 | 現在の深度 |
|:---|:---|:---:|
| `apps/game_engine/lib/game_engine/game_events.ex:666` | `maybe_log_and_cache/1` | 3 |
| `apps/game_content/lib/game_content/vampire_survivor/spawn_system.ex:30` | `maybe_spawn/1` | 3 |
| `apps/game_content/lib/game_content/vampire_survivor/scenes/playing.ex:81` | `update/2` | 5 |
| `apps/game_engine/lib/game_engine/save_manager.ex:134` | `read_json/1` | 4 |
| `apps/game_engine/lib/game_engine/game_events.ex:362` | `handle_frame_events_main/2` | 4 |
| `apps/game_engine/lib/game_engine/game_events.ex:52` | `init/1` | 3 |

**方針**: ネストしているブロックをプライベート関数に抽出して深度を 2 以下にする。

---

## CR-12: 循環的複雑度が高い関数の分解（2 件）

**カテゴリ**: [F] Refactoring

**対象**:

| ファイル | 関数 | 現在の複雑度 |
|:---|:---|:---:|
| `apps/game_engine/lib/game_engine/game_events.ex:251` | `handle_frame_events_main/2` | 12（上限 9） |
| `apps/game_engine/lib/game_engine/save_manager.ex:128` | `read_json/1` | 10（上限 9） |

**方針**: 条件分岐をプライベート関数に切り出して複雑度を 9 以下にする。
`game_events.ex` は IP-03（`GameEvents` GenServer の分解）と合わせて対応することを推奨する。

---

## CR-13: `length/1` の使用を避ける（1 件）

**カテゴリ**: [W] Warning

**対象**: `apps/game_content/test/game_content/level_system_test.exs:14`
（`GameContent.VampireSurvivor.LevelSystemTest`）

**修正パターン**:

```elixir
# ❌ 修正前（O(n) で全件数を数える）
assert length(list) > 0

# ✅ 修正後（先頭要素の存在チェックのみ）
assert list != []
# または
refute Enum.empty?(list)
```

---

## CR-14: ネストモジュールの `alias` 化（5 件）

**カテゴリ**: [D] Software Design

**対象**:

| ファイル | 関数 | ネストモジュール |
|:---|:---|:---|
| `apps/game_content/lib/game_content/vampire_survivor/scenes/playing.ex:120` | `apply_weapon_selected/2` | （要確認） |
| `apps/game_content/lib/game_content/vampire_survivor/scenes/playing.ex:101` | `update/2` | （要確認） |
| `apps/game_content/lib/game_content/vampire_survivor/scenes/playing.ex:83` | `update/2` | （要確認） |
| `apps/game_content/lib/game_content/vampire_survivor/scenes/playing.ex:58` | `update/2` | （要確認） |
| `apps/game_content/lib/game_content/vampire_survivor/scenes/boss_alert.ex:23` | `update/2` | （要確認） |

**修正パターン**:

```elixir
# ❌ 修正前（関数内でフルパスを使用）
def update(state, context) do
  GameContent.VampireSurvivor.LevelSystem.calc_exp(state)
end

# ✅ 修正後（モジュール先頭で alias）
alias GameContent.VampireSurvivor.LevelSystem

def update(state, context) do
  LevelSystem.calc_exp(state)
end
```

---

## 対応ロードマップ

```
フェーズ1 — 自動化・一括修正（30分）
  CR-01  CRLF 改行コードの一括変換

フェーズ2 — 機械的な修正（1〜2時間）
  CR-02  述語関数の命名規則
  CR-04  @moduledoc の追加
  CR-05  明示的 try の修正（save_manager, game_events, router）
  CR-06  引数なし関数の括弧除去
  CR-07  alias のアルファベット順
  CR-08  frame_cache の try 修正
  CR-13  length/1 の修正

フェーズ3 — ロジック変更を伴う修正（2〜4時間）
  CR-03  with → case への変換
  CR-09  with の非パターンマッチ式を外に出す
  CR-10  unless + else → if への変換
  CR-14  ネストモジュールの alias 化

フェーズ4 — リファクタリング（IP-03 と合わせて対応）
  CR-11  ネストが深すぎる関数の分解
  CR-12  循環的複雑度が高い関数の分解
```

---

## 確認コマンド

```powershell
# 全指摘を確認
.\bin\credo.bat

# 特定ファイルのみ確認
mix credo --strict apps/game_engine/lib/game_engine/game_events.ex

# 修正後の差分確認
mix credo --strict --format oneline
```

---

*このドキュメントは `mix credo --strict`（2026-03-01 実行）の結果に基づく。*
*対応完了後は `docs/evaluation/completed-improvements.md` に移動すること。*
