# AlchemyEngine — 改善提案書

> 2026-03-01 の評価（第2回、総合スコア +116点）に基づく改善提案。
> 各項目は `docs/evaluation/specific-weaknesses.md` の対応するマイナス点にマッピングされている。
> 期待スコア改善幅の大きい順に並べている。

---

## 優先度マトリクス

| ID | タイトル | 期待改善幅 | 工数 | 優先度 |
|:---|:---|:---:|:---:|:---:|
| IP-01 | Elixir コアモジュールのテスト追加 | +8 | 中 | 🔴 最高 |
| IP-02 | `LevelComponent` アイテムドロップ重複バグ修正 | +4 | 小 | 🔴 最高 |
| IP-03 | 複数ルームの実動作実証 | +3 | 小 | 🟡 高 |
| IP-04 | 描画層の技術的負債解消（アロケーション・UV） | +4 | 中 | 🟡 高 |
| IP-05 | NIF バージョニング・`create_world()` エラーハンドリング | +3 | 小 | 🟡 高 |
| IP-06 | ゲーム内設定 UI の実装 | +2 | 中 | 🟢 中 |
| IP-07 | リプレイ録画・再生システムの実装 | +1 | 大 | 🟢 中 |
| IP-08 | 空間オーディオ（距離減衰）の実装 | +1 | 中 | 🟢 中 |
| IP-09 | ボイスリミット・優先度システムの実装 | +2 | 小 | 🟢 中 |
| IP-10 | フラスタムカリングの実装 | +2 | 小 | 🟢 中 |
| IP-11 | エンドツーエンド NIF ラウンドトリップベンチマークの追加 | +2 | 小 | 🟢 中 |
| IP-12 | セーブ形式を JSON / MessagePack に移行 | +2 | 中 | 🟢 中 |
| IP-13 | WebSocket 認証の実装 | +2 | 中 | 🟢 中 |
| IP-14 | 物理ステップ実行順序のドキュメント化 | +1 | 小 | 🟢 中 |
| IP-15 | プロセス辞書ダーティフラグの State 管理への移行 | +1 | 小 | 🟢 中 |

---

## 詳細提案

---

### IP-01: Elixir コアモジュールのテスト追加

**対応するマイナス点**: `GameEvents` テストゼロ（-3）、`SceneManager` / `EventBus` / 全シーンテストゼロ（-2）

**テスト対象と方針**

```elixir
# GameEngine.SceneManager — シーン遷移ロジック
test "push でシーンがスタックに追加される" do
  {:ok, sm} = SceneManager.start_link([])
  SceneManager.push(sm, MyScene, %{})
  assert SceneManager.current(sm) == MyScene
end

test "pop で前のシーンに戻る" do
  {:ok, sm} = SceneManager.start_link([])
  SceneManager.push(sm, SceneA, %{})
  SceneManager.push(sm, SceneB, %{})
  SceneManager.pop(sm)
  assert SceneManager.current(sm) == SceneA
end

# GameEngine.EventBus — サブスクライバー配信
test "サブスクライバーがイベントを受信する" do
  {:ok, bus} = EventBus.start_link([])
  EventBus.subscribe(bus, self())
  EventBus.broadcast(bus, {:item_pickup, %{exp: 10}})
  assert_receive {:item_pickup, %{exp: 10}}
end

test "死亡したサブスクライバーが自動的に購読解除される" do
  {:ok, bus} = EventBus.start_link([])
  pid = spawn(fn -> receive do _ -> :ok end end)
  EventBus.subscribe(bus, pid)
  Process.exit(pid, :kill)
  Process.sleep(10)
  # ブロードキャストがクラッシュしないことを確認
  EventBus.broadcast(bus, :test_event)
end

# GameEngine.GameEvents — バックプレッシャー機構
test "メールボックス深度が閾値を超えた場合にフレームをドロップする" do
  # Mox を使用して NIF をモック
  # メールボックスを人工的に埋めてバックプレッシャーが発動することを確認
end
```

**受け入れ基準**:
- `mix test --cover` で `game_engine` アプリのカバレッジ > 60%
- すべてのシーン遷移パス（push / pop / replace）に最低 1 件のテストが存在する
- バックプレッシャー機構の動作テストが存在する

---

### IP-02: `LevelComponent` アイテムドロップ重複バグ修正

**対応するマイナス点**: アイテムドロップ重複ロジック（-3）

**問題の詳細**

`on_event({:entity_removed, ...})` と `on_frame_event({:enemy_killed, ...})` の両方でアイテムドロップが発生する可能性がある。1回の敵撃破でアイテムが2個ドロップするバグが潜在している。

**修正方針**

`on_event({:entity_removed, ...})` のアイテムドロップロジックを削除し、`on_frame_event({:enemy_killed, ...})` のみでドロップを処理する。または逆に、`on_frame_event` 側を削除して `on_event` 側に統一する。どちらのイベントが先に発火するかを確認した上で統一する。

```elixir
# 修正前: 2箇所にドロップロジックが存在
def on_event({:entity_removed, world_ref, kind_id, x, y}, _context) do
  # ← この重複ドロップを削除
  roll = :rand.uniform(100)
  cond do
    roll <= @drop_magnet_threshold -> ...
  end
end

# 修正後: on_frame_event のみでドロップを処理
def on_event({:entity_removed, _world_ref, _kind_id, _x, _y}, _context) do
  :ok  # ドロップは on_frame_event({:enemy_killed, ...}) で処理
end
```

**受け入れ基準**:
- 敵を 100 体撃破してアイテムドロップ数が 100 個以下であることを確認
- `entity_removed` と `enemy_killed` の両方が発火するケースのテストを追加

---

### IP-03: 複数ルームの実動作実証

**対応するマイナス点**: 複数ルームの同時起動が実証されていない（-2）

**実装方針**

`GameServer.Application.start/2` で `:main` ルームに加えて `:sub` ルームを起動し、両ルームが独立して 60Hz で動作することを確認する。

```elixir
# apps/game_server/lib/game_server/application.ex
children = [
  ...
  GameEngine.RoomSupervisor,
  ...
]

# start/2 の末尾で
{:ok, _} = GameEngine.RoomSupervisor.start_room(:main)
{:ok, _} = GameEngine.RoomSupervisor.start_room(:sub)  # ← 追加
GameNetwork.Local.connect_rooms(:main, :sub)             # ← 接続
```

**受け入れ基準**:
- 2 ルームが同時起動し、一方がクラッシュしても他方が継続することを確認
- `GameNetwork.Local.list_rooms/0` が 2 ルームを返すことを確認

---

### IP-04: 描画層の技術的負債解消

**対応するマイナス点**: 毎フレーム `Vec` アロケーション（-2）、UV マジックナンバー（-2）

**4-a: 毎フレームアロケーションの解消**

```rust
// 修正前: 毎フレーム Vec を生成
fn update_instances(&self, frame: &RenderFrame) -> Vec<SpriteInstance> {
    let mut instances = Vec::with_capacity(MAX_INSTANCES);
    // ...
    instances
}

// 修正後: Renderer フィールドに Vec を保持して再利用
pub struct Renderer {
    // ...
    instances: Vec<SpriteInstance>,  // ← 追加
}

fn update_instances(&mut self, frame: &RenderFrame) {
    self.instances.clear();
    // self.instances.push(...) で再利用
}
```

**4-b: UV マジックナンバーのデータファイル化**

`assets/atlas.toml` を作成:

```toml
[sprites]
player_idle = { x = 0,   y = 0, w = 16, h = 16, frames = 4 }
enemy_basic = { x = 64,  y = 0, w = 16, h = 16, frames = 3 }
ghost       = { x = 112, y = 0, w = 16, h = 16, frames = 2 }
```

起動時にロードして UV ルックアップテーブルを生成。`renderer/mod.rs` のハードコードされたピクセルオフセットをすべて削除。

---

### IP-05: NIF バージョニング・`create_world()` エラーハンドリング

**対応するマイナス点**: NIF バージョニングなし（-2）、`create_world()` NifResult 未対応（-2）

**5-a: NIF バージョニング**

```rust
// native/game_nif/src/nif/load.rs
pub const NIF_VERSION: u32 = 1;
```

```elixir
# lib/game_engine/nif_bridge.ex
@expected_nif_version 1

def check_version! do
  case nif_version() do
    @expected_nif_version -> :ok
    v -> raise "NIF バージョン不一致: 期待 #{@expected_nif_version}, 実際 #{v}"
  end
end
```

**5-b: `create_world()` エラーハンドリング**

```rust
// native/game_nif/src/nif/world_nif.rs
#[rustler::nif]
pub fn create_world() -> NifResult<ResourceArc<GameWorld>> {
    // エラー時は Err(rustler::Error::Term(...)) を返す
}
```

```elixir
# apps/game_server/lib/game_server/application.ex
case GameEngine.NifBridge.create_world() do
  {:ok, world_ref} -> world_ref
  {:error, reason} -> {:error, reason}  # raise ではなく error タプルを返す
end
```

---

### IP-06: ゲーム内設定 UI の実装

**対応するマイナス点**: ゲーム内設定 UI なし（-2）

`SceneBehaviour` を実装した `GameEngine.Scenes.Settings` モジュールを作成:

- BGM 音量スライダー（`set_bgm_volume` NIF を呼び出す）
- SE 音量スライダー
- フルスクリーン切り替え（`winit` ウィンドウモード変更）
- キーバインド表示（v1 は読み取り専用）

タイトル画面から push で遷移し、戻るで pop する。

---

### IP-07: リプレイ録画・再生システムの実装

**対応するマイナス点**: 決定論的乱数があるにもかかわらずリプレイ未実装（-1）

初期 RNG シードと全プレイヤー入力イベント（フレームタイムスタンプ付き）を記録。再生時は記録済み入力を `InputHandler` に注入する。決定論的物理が同一ゲームを再現する。

```elixir
defmodule GameEngine.ReplayRecorder do
  def start_recording(seed) :: {:ok, recorder}
  def record_input(recorder, frame_id, input) :: :ok
  def save_replay(recorder, path) :: :ok
  def load_replay(path) :: {:ok, replay_data}
end
```

---

### IP-08: 空間オーディオ（距離減衰）の実装

**対応するマイナス点**: 空間オーディオ未実装（-1）

```rust
pub enum AudioCommand {
    PlaySeAtPosition(AssetId, f32, f32),  // x, y ワールド座標
}
```

オーディオスレッドでプレイヤー位置との距離を計算し、線形または逆二乗減衰を適用する。

---

### IP-09: ボイスリミット・優先度システムの実装

**対応するマイナス点**: ボイスリミットなし（-2）

```rust
struct AudioMixer {
    active_voices: Vec<ActiveVoice>,
    max_voices: usize,  // 例: 32
}

impl AudioMixer {
    fn play(&mut self, cmd: AudioCommand, priority: u8) {
        if self.active_voices.len() >= self.max_voices {
            // 最低優先度のボイスをドロップ
        }
    }
}
```

---

### IP-10: フラスタムカリングの実装

**対応するマイナス点**: フラスタムカリングなし（-2）

`render_snapshot.rs` のスナップショット構築ループ内で、カメラビューポート外のエンティティをフィルタリング:

```rust
let in_view = |x: f32, y: f32| {
    let (cx, cy) = camera_offset;
    x >= cx - HALF_W - MARGIN && x <= cx + HALF_W + MARGIN &&
    y >= cy - HALF_H - MARGIN && y <= cy + HALF_H + MARGIN
};
```

O(n) で既存のスナップショットループと統合可能。

---

### IP-11: エンドツーエンド NIF ラウンドトリップベンチマークの追加

**対応するマイナス点**: フルラウンドトリップベンチマークなし（-2）

```elixir
# apps/game_engine/bench/nif_roundtrip_bench.exs
Benchee.run(%{
  "フルフレームサイクル" => fn ->
    NifBridge.set_hud_state(world, hud_state)
    NifBridge.physics_step(world)
    NifBridge.drain_frame_events(world)
  end
})
```

結果を `docs/benchmarks/nif-roundtrip.md` に記録。

---

### IP-12: セーブ形式を JSON / MessagePack に移行

**対応するマイナス点**: Erlang バイナリ term（非ポータブル）（-2）

`SaveManager` の `:erlang.term_to_binary` / `:erlang.binary_to_term` を `Jason.encode!` / `Jason.decode!` に置き換え。HMAC 署名は維持。バージョンフィールドを追加:

```json
{ "version": 1, "score": 12345, "level": 7, "elapsed_ms": 300000 }
```

---

### IP-13: WebSocket 認証の実装

**対応するマイナス点**: WebSocket 認証が未実装（-2）

```elixir
# apps/game_network/lib/game_network/user_socket.ex
def connect(%{"token" => token}, socket, _connect_info) do
  case verify_token(token) do
    {:ok, user_id} -> {:ok, assign(socket, :user_id, user_id)}
    {:error, _} -> :error
  end
end
```

JWT 検証または Phoenix.Token を使用したトークン検証を実装。

---

### IP-14: 物理ステップ実行順序のドキュメント化

**対応するマイナス点**: 物理ステップ順序が暗黙的（-1）

`physics_step.rs` の先頭にコメントブロックを追加:

```rust
/// 物理ステップ実行順序（60Hz 毎フレーム）:
///
/// 1. プレイヤー移動    — 障害物押し出しの前に確定させる
/// 2. 障害物押し出し    — プレイヤー移動後、AI 前に実行
/// 3. Chase AI          — プレイヤー位置が確定した後に読む
/// 4. 敵分離            — AI 速度更新後に実行
/// 5. 衝突判定          — 最終位置で実行
/// 6. 武器攻撃          — 衝突結果を読む
/// 7. パーティクル      — 独立、順序不問
/// 8. アイテム          — プレイヤー位置を読む
/// 9. 弾丸              — 衝突結果を読む
/// 10. ボス             — プレイヤー位置を読み、ボス状態を書く
```

---

### IP-15: プロセス辞書ダーティフラグの State 管理への移行

**対応するマイナス点**: プロセス辞書によるダーティフラグ管理（-1）

`LevelComponent` と `BossComponent` の `Process.put/get` によるダーティフラグを、コンポーネント state に移動する:

```elixir
# 修正前
defp sync_hud_state(world_ref, playing_state) do
  prev = Process.get({__MODULE__, :last_hud_state})
  # ...
  Process.put({__MODULE__, :last_hud_state}, new_val)
end

# 修正後: on_nif_sync/1 の state に prev_hud を持たせる
def on_nif_sync(%{prev_hud: prev_hud} = state) do
  new_hud = {state.score, state.kill_count}
  if new_hud != prev_hud do
    NifBridge.set_hud_state(state.world_ref, state.score, state.kill_count)
    %{state | prev_hud: new_hud}
  else
    state
  end
end
```

---

## 実装ロードマップ

```
フェーズ1 — バグ修正・品質向上（1〜2週間）
  IP-02  アイテムドロップ重複バグ修正
  IP-05  NIF バージョニング・エラーハンドリング
  IP-14  物理ステップ順序ドキュメント化
  IP-15  プロセス辞書ダーティフラグ移行

フェーズ2 — テスト・実証（3〜5週間）
  IP-01  Elixir コアテスト追加
  IP-03  複数ルームの実動作実証
  IP-11  エンドツーエンドベンチマーク

フェーズ3 — 描画・パフォーマンス（6〜8週間）
  IP-04  描画層技術的負債解消
  IP-10  フラスタムカリング

フェーズ4 — 機能追加（9〜16週間）
  IP-06  ゲーム内設定 UI
  IP-07  リプレイシステム
  IP-08  空間オーディオ
  IP-09  ボイスリミット
  IP-12  セーブ形式移行
  IP-13  WebSocket 認証
```

---

*このドキュメントは `docs/evaluation/evaluation-2026-03-01.md`（第2回）の評価に基づいて生成された。*
*項目が完了したら `docs/evaluation/completed-improvements.md` に移動すること。*
