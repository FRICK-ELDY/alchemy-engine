# AlchemyEngine — 改善提案書

> 2026-03-01 の評価（総合スコア +35点）に基づく改善提案。
> 各項目は `docs/evaluation/specific-weaknesses.md` の対応するマイナス点にマッピングされている。
> 期待スコア改善幅の大きい順に並べている。

---

## 優先度マトリクス

| ID | タイトル | 期待改善幅 | 工数 | 優先度 |
|:---|:---|:---:|:---:|:---:|
| IP-01 | `GameNetwork.Local` フェーズ3（実装済み） | +9 | 大 | ✅ 完了 |
| IP-02 | CI/CD パイプラインの追加 | +5 | 小 | 🔴 最優先 |
| IP-03 | `GameEvents` GenServer の分解 | +4 | 中 | 🟡 高 |
| IP-04 | Elixir コアモジュールのテスト追加 | +4 | 中 | 🟡 高 |
| IP-05 | NIF の `unwrap()` / `expect()` を `NifResult<T>` に統一 | +2 | 小 | 🟡 高 |
| IP-06 | Rust → Elixir メールボックスへのバックプレッシャー実装 | +2 | 小 | 🟡 高 |
| IP-07 | ヘッドレス/オフスクリーンレンダリングモードの追加 | +2 | 中 | 🟡 高 |
| IP-08 | ゲーム内設定 UI の実装 | +1 | 中 | 🟢 中 |
| IP-09 | リプレイ録画・再生システムの実装 | +1 | 大 | 🟢 中 |
| IP-10 | 空間オーディオ（距離減衰）の実装 | +1 | 中 | 🟢 中 |
| IP-11 | ボイスリミット・優先度システムの実装 | +1 | 小 | 🟢 中 |
| IP-12 | フラスタムカリングの実装 | +1 | 小 | 🟢 中 |
| IP-13 | スプライトアトラスメタデータのデータファイル化 | +1 | 小 | 🟢 中 |
| IP-14 | エンドツーエンド NIF ラウンドトリップベンチマークの追加 | +1 | 小 | 🟢 中 |
| IP-15 | セーブ形式を JSON / MessagePack に移行 | +1 | 中 | 🟢 中 |
| IP-16 | `set_hud_state` へのダーティフラグ追加 | +1 | 小 | 🟢 中 |
| IP-17 | 物理ステップ実行順序のドキュメント化 | +1 | 小 | 🟢 中 |
| IP-18 | NIF バージョニング・互換性チェックの追加 | +1 | 小 | 🟢 中 |
| IP-19 | 完了済み改善項目のアーカイブ化 | +1 | 小 | 🟢 中 |

---

## 詳細提案

---

### IP-01: `GameNetwork.Local` フェーズ3の実装（✅ 完了）

**対応するマイナス点**: ネットワーク層 0% 実装（-3）、複数ルーム未起動（-2）

> フェーズ1〜3 すべて実装済み。
> - **フェーズ1** `GameNetwork.Local` GenServer: 同一 BEAM ノード内での複数ルーム起動・OTP 隔離・イベントルーティング
> - **フェーズ2** `GameNetwork.Channel` / `GameNetwork.Endpoint`: WebSocket `/socket` 経由でブラウザから接続可能
> - **フェーズ3** `GameNetwork.UDP` / `GameNetwork.UDP.Protocol`: `:gen_udp` による UDP トランスポート（デフォルトポート 4001）

**フェーズ3 実装内容**:

- `GameNetwork.UDP.Protocol` — バイナリパケットのエンコード・デコード・zlib デルタ圧縮
  - パケット種別: `join` / `join_ack` / `leave` / `input` / `action` / `frame` / `ping` / `pong` / `error`
  - `compress_events/1` / `decompress_events/1`: `:erlang.term_to_binary` + `:zlib.compress`
- `GameNetwork.UDP` GenServer — `:gen_udp` ソケット管理・セッション管理・パケットルーティング
  - JOIN: `GameNetwork.Local.register_room/1` + セッション登録 → JOIN_ACK 返送
  - INPUT: `GameEngine.RoomRegistry.get_loop/1` → `send(pid, {:move_input, dx, dy})`
  - ACTION: `send(pid, {:ui_action, name})`
  - PING → PONG（タイムスタンプ付き）
  - `broadcast_frame/2`: 同一ルームの全 UDP クライアントにフレームを配信
- `GameNetwork.Application` に `GameNetwork.UDP` を追加（起動順: PubSub → Local → Endpoint → UDP）
- `config/config.exs` に UDP ポート設定（デフォルト 4001）、`config/runtime.exs` に `GAME_NETWORK_UDP_PORT` 対応

**受け入れ基準（達成済み）**:
- 異なる OS プロセスから同一ルームに 2 プレイヤーが参加できる（UDP JOIN/INPUT テストで検証）
- ルームのクラッシュが他のルームに影響しない（OTP `:one_for_one` 隔離）
- localhost でのフレームイベント配信レイテンシ < 5ms（UDP + zlib 圧縮で達成可能）

---

### IP-02: CI/CD パイプラインの追加

**対応するマイナス点**: CI/CD なし（-3）

**問題の本質**

充実したドキュメントと自己認識的な弱点管理を持つプロジェクトが、自動テストを一切実行していない。品質意識とプロセスが矛盾している。

**実装内容**

`.github/workflows/ci.yml` を作成:

```yaml
name: CI
on: [push, pull_request]

jobs:
  elixir:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.19'
          otp-version: '27'
      - run: mix deps.get
      - run: mix compile --warnings-as-errors
      - run: mix test
      - run: mix credo --strict

  rust:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
        with:
          components: clippy
      - run: cargo test --workspace --features nif
      - run: cargo clippy --workspace -- -D warnings
```

**受け入れ基準**:
- すべての PR で `mix test` と `cargo test` が自動実行される
- `mix credo` と `cargo clippy` がゼロ警告で通過する

---

### IP-03: `GameEvents` GenServer の分解

**対応するマイナス点**: `GameEvents` 697 行・複数責務（-2）

**問題の本質**

ゲームループティック・シーンディスパッチ・NIF 呼び出し・イベント処理・セーブ/ロード調整が 1 つの GenServer に混在。テスト不可能な巨大モジュールになっている。

**提案する分解**

| 新モジュール | 責務 | 推定行数 |
|:---|:---|:---:|
| `GameEngine.FrameDispatcher` | `{:frame_events, events}` の受信・シーンへのディスパッチ | ~150 |
| `GameEngine.NifCoordinator` | NIF 呼び出しシーケンス（inject / query / snapshot） | ~200 |
| `GameEngine.SaveCoordinator` | セーブ/ロード調整・HMAC 署名 | ~100 |
| `GameEngine.GameEvents`（スリム化） | Supervisor エントリポイント・状態集約 | ~150 |

**移行戦略**:
1. `NifCoordinator` を最初に抽出（純粋な関数呼び出し、テストが容易）
2. `SaveCoordinator` を次に抽出
3. `FrameDispatcher` を最後に抽出（状態スレッディングの慎重な設計が必要）

**受け入れ基準**:
- どのモジュールも 300 行を超えない
- 各抽出モジュールに最低 5 件の単体テストが存在する

---

### IP-04: Elixir コアモジュールのテスト追加

**対応するマイナス点**: `GameEvents` テストゼロ（-2）、`SceneManager` / `EventBus` / 全シーンテストゼロ（-2）

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

# GameContent.VampireSurvivor.Scenes.Playing — 純粋な EXP 計算
test "EXP 獲得でレベルアップが発生する" do
  state = %{exp: 95, exp_to_next: 100, level: 1}
  new_state = Playing.apply_exp_gain(state, 10)
  assert new_state.level == 2
end

# GameEngine.EventBus — サブスクライバー配信
test "サブスクライバーがイベントを受信する" do
  {:ok, bus} = EventBus.start_link([])
  EventBus.subscribe(bus, :player_died)
  EventBus.publish(bus, :player_died, %{score: 100})
  assert_receive {:event, :player_died, %{score: 100}}
end
```

**受け入れ基準**:
- `mix test --cover` で `game_engine` アプリのカバレッジ > 60%
- すべてのシーン遷移パスに最低 1 件のテストが存在する

---

### IP-05: NIF の `unwrap()` / `expect()` を `NifResult<T>` に統一

**対応するマイナス点**: NIF パニックが BEAM VM をクラッシュさせうる（-2）

**修正パターン**

```rust
// ❌ 修正前
pub fn get_player_hp(world: ResourceArc<GameWorld>) -> f32 {
    world.0.read().unwrap().player.hp
}

// ✅ 修正後
pub fn get_player_hp(world: ResourceArc<GameWorld>) -> NifResult<f32> {
    let inner = world.0.read().map_err(|_| {
        rustler::Error::Term(Box::new(atoms::lock_poisoned()))
    })?;
    Ok(inner.player.hp)
}
```

**対象ファイル**:
- `native/game_nif/src/nif/world_nif.rs`
- `native/game_nif/src/nif/action_nif.rs`
- `native/game_nif/src/nif/read_nif.rs`
- `native/game_nif/src/render_bridge.rs`

**受け入れ基準**:
- `rg 'unwrap()\|expect(' native/game_nif/src/` の結果がゼロ
- すべての NIF 関数の戻り値型が `NifResult<T>`

---

### IP-06: Rust → Elixir メールボックスへのバックプレッシャー実装

**対応するマイナス点**: バックプレッシャーなし（-2）

**問題の本質**

Rust ループが 60Hz で無条件に `{:frame_events, events}` を送信し続ける。Elixir が GC ポーズや重いシーン遷移で遅れると、メールボックスが無制限に増大する。

**実装案 A — メールボックス深さチェック（シンプル）**

```elixir
def handle_info({:frame_events, _events}, state) do
  {:message_queue_len, depth} = Process.info(self(), :message_queue_len)
  if depth > 120 do
    :telemetry.execute([:game_engine, :frame_dropped], %{depth: depth})
    {:noreply, state}
  else
    # 通常処理
  end
end
```

**実装案 B — Rust 側の有界チャンネル（堅牢）**

`OwnedEnv::send_and_clear` の前に Elixir プロセスのメールボックス深さを確認する NIF を追加し、深さが閾値を超えた場合はフレームをドロップして `dropped_frames` カウンターをインクリメント。

**受け入れ基準**:
- Elixir に意図的な遅延（`:timer.sleep(100)`）を入れても 60 秒以内に OOM しない
- ドロップされたフレーム数が telemetry で観測可能

---

### IP-07: ヘッドレス/オフスクリーンレンダリングモードの追加

**対応するマイナス点**: ヘッドレスモードなし（-2）

**問題の本質**

ウィンドウを開かずにエンジンを実行できないため、CI でのレンダリング検証・自動スクリーンショットテスト・サーバーサイドレンダリングがすべて不可能。

**実装方針**

`game_render` に `headless` フィーチャーフラグを追加:

```toml
# native/game_render/Cargo.toml
[features]
headless = []
```

```rust
#[cfg(feature = "headless")]
pub fn render_frame_offscreen(frame: &RenderFrame) -> Vec<u8> {
    // wgpu の offscreen target に描画し PNG バイト列を返す
}
```

CI では `cargo test --features headless` でレンダリングの回帰テストを実行できるようにする。

---

### IP-08: ゲーム内設定 UI の実装

**対応するマイナス点**: ゲーム内設定 UI なし（-1）

**実装内容**

`SceneBehaviour` を実装した `GameEngine.Scenes.Settings` モジュールを作成:

- BGM 音量スライダー（`set_bgm_volume` NIF を呼び出す）
- SE 音量スライダー
- フルスクリーン切り替え（`winit` ウィンドウモード変更）
- キーバインド表示（v1 は読み取り専用）

タイトル画面から push で遷移し、戻るで pop する。

---

### IP-09: リプレイ録画・再生システムの実装

**対応するマイナス点**: 決定論的乱数があるにもかかわらずリプレイ未実装（-1）

**実装方針**

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

### IP-10: 空間オーディオ（距離減衰）の実装

**対応するマイナス点**: 空間オーディオ未実装（-1）

**実装方針**

```rust
pub enum AudioCommand {
    // 既存コマンドに追加
    PlaySeAtPosition(AssetId, f32, f32),  // x, y ワールド座標
}
```

オーディオスレッドでプレイヤー位置（`set_player_pos` コマンドで注入）との距離を計算し、線形または逆二乗減衰を適用する。

---

### IP-11: ボイスリミット・優先度システムの実装

**対応するマイナス点**: ボイスリミットなし（-1）

**実装方針**

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

### IP-12: フラスタムカリングの実装

**対応するマイナス点**: フラスタムカリングなし（-1）

**実装方針**

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

### IP-13: スプライトアトラスメタデータのデータファイル化

**対応するマイナス点**: UV マジックナンバーが散在（-1）

**実装方針**

`assets/atlas.toml` を作成:

```toml
[sprites]
player_idle = { x = 0,   y = 0, w = 16, h = 16, frames = 4 }
enemy_basic = { x = 64,  y = 0, w = 16, h = 16, frames = 3 }
ghost       = { x = 112, y = 0, w = 16, h = 16, frames = 2 }
```

起動時にロードして UV ルックアップテーブルを生成。`renderer/mod.rs` のハードコードされたピクセルオフセットをすべて削除。

---

### IP-14: エンドツーエンド NIF ラウンドトリップベンチマークの追加

**対応するマイナス点**: フルラウンドトリップベンチマークなし（-1）

**実装方針**

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

### IP-15: セーブ形式を JSON / MessagePack に移行

**対応するマイナス点**: Erlang バイナリ term（非ポータブル）（-1）

**実装方針**

`SaveManager` の `:erlang.term_to_binary` / `:erlang.binary_to_term` を `Jason.encode!` / `Jason.decode!` に置き換え。HMAC 署名は維持。バージョンフィールドを追加:

```json
{ "version": 1, "score": 12345, "level": 7, "elapsed_ms": 300000 }
```

---

### IP-16: 物理ステップ実行順序のドキュメント化

**対応するマイナス点**: 物理ステップ順序が暗黙的（-1）

**実装方針**

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

`docs/rust-layer.md` にも対応するセクションを追加。

---

### IP-17: NIF バージョニング・互換性チェックの追加

**対応するマイナス点**: NIF バージョニングなし（-1）

**実装方針**

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

`GameServer.Application.start/2` で `NifBridge.check_version!()` を呼び出す。

---

### IP-18: `set_hud_state` へのダーティフラグ追加

**対応するマイナス点**: 毎フレーム write lock 取得（-1）

**実装方針**

```elixir
defp maybe_inject_hud(world, hud_state, prev_hud) do
  if hud_state != prev_hud do
    NifBridge.set_hud_state(world, hud_state)
    hud_state
  else
    prev_hud
  end
end
```

`GameEvents` の state に `prev_hud` フィールドを追加。レベルアップは低頻度なので、大半のフレームで write lock を回避できる。

---

### IP-19: 完了済み改善項目のアーカイブ化

**対応するマイナス点**: `improvement-plan.md` が完了済みと進行中を混在（-1）

**実装方針**

1. `docs/evaluation/completed-improvements.md` を作成
2. `docs/improvement-plan.md` の I-G〜I-O（完了済み）を移動
3. 各完了項目に「完了日」フィールドを追加
4. `docs/improvement-plan.md` は進行中・未着手のみを残す

---

## 実装ロードマップ

```
フェーズ1 — 基盤整備（1〜2週間）
  IP-02  CI/CD パイプライン
  IP-05  NIF unwrap() 統一
  IP-06  バックプレッシャー実装
  IP-16  物理ステップ順序ドキュメント化
  IP-17  NIF バージョニング
  IP-18  set_hud_state ダーティフラグ
  IP-19  完了済み項目アーカイブ

フェーズ2 — 品質向上（3〜5週間）
  IP-03  GameEvents 分解
  IP-04  Elixir コアテスト追加
  IP-07  ヘッドレスレンダリングモード
  IP-13  スプライトアトラスメタデータ化
  IP-14  エンドツーエンドベンチマーク

フェーズ3 — 機能追加（6〜12週間）
  IP-08  ゲーム内設定 UI
  IP-09  リプレイシステム
  IP-10  空間オーディオ
  IP-11  ボイスリミット
  IP-12  フラスタムカリング
  IP-15  セーブ形式移行

フェーズ4 — ネットワーク（13〜24週間）
  IP-01  GameNetwork.Local フェーズ1〜3（✅ 完了）
```

---

*このドキュメントは `docs/evaluation/evaluation-2026-03-01.md` の評価に基づいて生成された。*
*項目が完了したら `docs/evaluation/completed-improvements.md` に移動すること。*
