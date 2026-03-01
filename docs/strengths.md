# AlchemyEngine — 実装済みの強み

> このドキュメントは「ElixirとRustの真価を発揮するために、すでに実現できていること」を記録する。
> 課題や改善点は `improvement-plan.md` / `pending-issues.md` に委ねる。
> ここは**モチベーションの源泉**として、誇れる設計と実装を集めた場所だ。

---

## Rust の強み

### 1. SoA（Structure of Arrays）設計 — キャッシュ効率の最大化

最大 10,000 体の敵を処理するために、ECS の教科書的な SoA レイアウトを採用している。

```rust
struct EnemyWorld {
    positions_x: Vec<f32>,   // 全敵の X 座標が連続メモリに並ぶ
    positions_y: Vec<f32>,
    velocities_x: Vec<f32>,
    velocities_y: Vec<f32>,
    hp:          Vec<f32>,
    alive:       Vec<bool>,
    free_list:   Vec<usize>, // O(1) スポーン / キル
}
```

AoS（Array of Structs）と比較して、Chase AI のような「全敵の座標だけを読む」処理でキャッシュラインの無駄が消える。
`free_list` による O(1) スポーン/キルも、毎フレーム大量のエンティティが生死する Vampire Survivor 系ゲームに最適な設計だ。

---

### 2. SSE2 SIMD intrinsics — 4体並列の Chase AI

x86_64 環境では、Rust の `std::arch::x86_64` を直接使った SSE2 SIMD で敵 AI を 4 体同時に処理している。

```rust
#[cfg(target_arch = "x86_64")]
pub fn update_chase_ai_simd(enemies: &mut EnemyWorld, player_x: f32, player_y: f32, dt: f32) {
    let px4 = _mm_set1_ps(player_x);
    let py4 = _mm_set1_ps(player_y);

    // 4体分の距離を一括計算
    let dist_sq_val = _mm_add_ps(_mm_mul_ps(dx, dx), _mm_mul_ps(dy, dy));
    // 高速逆平方根（sqrt の代わりに rsqrt）
    let inv_dist = _mm_rsqrt_ps(dist_sq_safe);
    // 4体分の速度・位置を一括更新
    let new_ex = _mm_add_ps(ex, _mm_mul_ps(vx, dt4));
}
```

`_mm_rsqrt_ps` による高速逆平方根は、通常の `sqrt` + 除算より大幅に高速だ。
SoA レイアウトがあるからこそ、`_mm_loadu_ps` で 4 体分の座標を連続メモリから一括ロードできる。
**SoA と SIMD は切り離せない一体の設計**になっている。

---

### 3. rayon による非 x86_64 環境の並列化

SIMD が使えない環境（ARM 等）では、rayon の `par_iter_mut` で自動的にマルチコア並列処理にフォールバックする。

```rust
#[cfg(not(target_arch = "x86_64"))]
pub fn update_chase_ai(enemies: &mut EnemyWorld, ...) {
    (positions_x, positions_y, velocities_x, velocities_y, speeds, alive)
        .into_par_iter()
        .for_each(|(px, py, vx, vy, speed, is_alive)| { ... });
}
```

`#[cfg(target_arch)]` による条件コンパイルで、プラットフォームごとに最適なコードパスを選択している。
これは「ゼロコスト抽象化」の実践だ。

---

### 4. FxHashMap ベースの空間ハッシュ — O(1) 近傍クエリ

衝突判定に `rustc-hash` の `FxHashMap` を使った空間ハッシュを実装している。

```rust
pub fn query_nearby_into(&self, x: f32, y: f32, radius: f32, buf: &mut Vec<usize>) {
    buf.clear();  // 呼び出し元のバッファを再利用（アロケーションなし）
    let r = (radius / self.cell_size).ceil() as i32;
    for ix in (cx - r)..=(cx + r) {
        for iy in (cy - r)..=(cy + r) {
            if let Some(ids) = self.cells.get(&(ix, iy)) {
                buf.extend_from_slice(ids);
            }
        }
    }
}
```

- `buf` を引数で受け取ることでヒープアロケーションをゼロにしている
- `FxHashMap` は標準の `HashMap` より 2〜3 倍高速（暗号学的安全性が不要なゲーム用途に最適）
- 毎フレームの衝突判定が O(n²) から O(n) に近づく

---

### 5. Spatial Hash の段階的拡大検索 — Lightning チェーン武器

最近接敵の探索では、空間ハッシュで候補が見つからない場合に半径を 2 倍ずつ最大 4 回拡大し、それでも見つからない場合のみ O(n) 全探索にフォールバックする。

```rust
for _ in 0..4 {
    collision.dynamic.query_nearby_into(px, py, radius, buf);
    if result.is_some() { return result; }
    radius *= 2.0;  // 半径を 2 倍に拡大して再試行
}
// 極稀なケースのみ O(n) 全探索
find_nearest_enemy_excluding_set(enemies, px, py, exclude)
```

Lightning チェーン武器の「次のターゲット探索」にも除外セット付きの同アルゴリズムを使っており、チェーン数が増えても効率が落ちない。

---

### 6. 決定論的物理演算 — LCG 乱数

`SimpleRng`（線形合同法）によるシード固定の決定論的乱数を使っている。

```rust
pub struct SimpleRng { state: u64 }
impl SimpleRng {
    pub fn new(seed: u64) -> Self { Self { state: seed } }
    pub fn next_f32(&mut self) -> f32 { ... }  // LCG
}
```

同じシードで同じゲームプレイが再現できる。将来のリプレイ機能・デバッグ・ネットワーク同期（ロールバック等）の基盤になる。

---

### 7. RwLock の競合最小化 — レンダースレッドの read lock 設計

レンダースレッドは `read lock` でデータを最小コピーし、**ロック外**で補間計算（`lerp`）を行う。

```
ゲームループスレッド（write lock、60Hz）
レンダースレッド（read lock → コピー → ロック解放 → lerp 計算）
```

- `read lock` は複数のスレッドが同時取得できるため、レンダースレッド同士は競合しない
- ゲームループの `write lock` とは競合するが、ロック保持時間を最小化することで待機時間を抑えている
- ロック外で lerp 計算を行うことで、write lock との競合ウィンドウをデータコピーの瞬間だけに絞っている

---

### 8. コマンドパターンによるオーディオの非同期制御

オーディオスレッドへの命令を `AudioCommand` enum のチャネル送信で行い、ゲームループをブロックしない。

```rust
enum AudioCommand { Play(SoundId), Stop(SoundId), SetVolume(f32) }
// ゲームループ側: ノンブロッキング送信
audio_sender.send(AudioCommand::Play(explosion));
// オーディオスレッド側: コマンドループで処理
```

ゲームループが音声処理の完了を待たない設計で、60Hz の安定性を保っている。

---

### 9. `game_physics` の依存最小化

`game_physics` クレートの依存は `rustc-hash = "2"` のみ（rayon は `game_nif` 経由）。
物理演算コアを外部依存から切り離すことで、将来の WebAssembly 対応・組み込み環境への移植が容易になる。

---

## Elixir の強み

### 10. OTP Supervisor ツリーによる構造的な耐障害性の土台

Supervisor ツリーが正しく設計されており、将来の NIF 安全化（I-C）が完了すれば即座に耐障害性が機能する。

```
GameServer.Supervisor（:one_for_one）
├── Registry（RoomRegistry）
├── SceneManager（GenServer）
├── EventBus（GenServer）
├── RoomSupervisor（DynamicSupervisor）
│   └── GameEvents（GenServer, :main）
├── StressMonitor（GenServer）
├── Stats（GenServer）
└── Telemetry（Supervisor）
```

`:one_for_one` 戦略により、`GameEvents` がクラッシュしても他のプロセスに影響しない。
`DynamicSupervisor` + `Registry` による複数ルーム設計は、マルチプレイヤー対応の準備が整っている。

---

### 11. イミュータブルなシーン状態管理

シーン状態を純粋関数で変換し、遷移をタプルで返す設計はElixirのイミュータブル性を最大限に活かしている。

```elixir
def update(context, state) do
  # 状態を変更せず、新しい状態を返す
  {:transition, {:push, LevelUp, %{choices: weapon_choices}}, state}
  # または
  {:continue, %{state | exp: state.exp + gain}}
end
```

状態の変更履歴が追いやすく、バグの再現が容易だ。シーンスタック（push/pop）の設計も、ゲームの UI 階層を自然に表現している。

---

### 12. ETS によるフレームキャッシュ — ノンブロッキングな状態共有

`FrameCache` が ETS（Erlang Term Storage）に最新フレームのスナップショットを保持している。

```elixir
defmodule GameEngine.FrameCache do
  # ETS への書き込み（GameEvents プロセス）
  def update(snapshot), do: :ets.insert(@table, {:frame, snapshot})
  # ETS からの読み取り（任意のプロセスからノンブロッキング）
  def get(), do: :ets.lookup(@table, :frame)
end
```

ETS はプロセス間でロックなしに読み取れるため、将来の複数クライアント対応でも性能が落ちない。

---

### 13. Telemetry による計測基盤

`:telemetry.execute/3` がゲームの重要イベントに埋め込まれている。

```elixir
:telemetry.execute([:game, :boss_spawn], %{count: 1}, %{boss: boss_name})
:telemetry.execute([:game, :level_up], %{level: level, count: 1}, %{})
```

`GameEngine.Telemetry` Supervisor が `telemetry_metrics` と連携しており、将来の監視ダッシュボード（Phoenix LiveDashboard 等）にすぐ接続できる。

---

### 14. セーブデータの Behaviour による差し替え可能設計

`SaveStorage` behaviour でストレージ実装を抽象化しており、ローカル保存とクラウド保存を `config.exs` の 1 行で切り替えられる。

```elixir
# フェーズ1（実装済み）
config :game_engine, :save_storage, GameEngine.SaveStorage.Local

# フェーズ2（将来）
config :game_engine, :save_storage, GameNetwork.SaveStorage.Cloud
```

Elixir の `@behaviour` による依存性逆転の原則が正しく適用されている。

---

### 15. コンポーネントライフサイクルの設計

`GameEngine.Component` behaviour が Unity の `MonoBehaviour` / Godot の `Node` に相当するライフサイクルを定義している。

```elixir
defmodule GameEngine.Component do
  @optional_callbacks [on_ready: 1, on_process: 1, on_physics_process: 1, on_event: 2]

  @callback on_ready(world_ref)         :: :ok  # 初期化時（1回）
  @callback on_process(context)         :: :ok  # 毎フレーム（Elixir 側）
  @callback on_physics_process(context) :: :ok  # 物理フレーム（60Hz）
  @callback on_event(event, context)    :: :ok  # イベント発生時
end
```

`@optional_callbacks` により、コンポーネントは必要なコールバックだけを実装すればよい。
エンジンはコンポーネントの中身を知らず、ライフサイクルのタイミングだけを提供する。

---

## Elixir × Rust の組み合わせの強み

### 16. Elixir as SSoT — 責務の明確な分離

ゲーム状態の権威（Single Source of Truth）を Elixir 側が持ち、Rust は毎フレーム NIF 注入を受けて描画・物理演算のみを担当する。

```
Elixir（SSoT・ゲームロジック）    Rust（物理・描画）
  score, kill_count     →  set_hud_state NIF
  player_hp             →  set_player_hp NIF
  weapon_levels         →  set_weapon_slots NIF
  boss_hp               →  set_boss_hp NIF
  elapsed_ms            →  set_elapsed_seconds NIF
```

この設計により：
- ゲームロジックのバグを Rust を再コンパイルせずに Elixir 側だけで修正できる
- セーブ/ロードは Elixir 側の状態を保存するだけでよい（Rust 側に永続化が不要）
- 将来のネットワーク同期も Elixir 側の状態を同期すれば実現できる

> **トレードオフ**: 現状の実装では、この注入が毎フレーム複数の `write lock` を伴っており、
> Rust ゲームループとのロック競合が発生している（`improvement-plan.md` 課題 I-A 参照）。
> SSoT パターン自体はアーキテクチャ上の正しい選択だが、注入の実装をダブルバッファリングや
> 差分更新に改善することで、この設計の利点をコストなく享受できるようになる。

---

### 17. ResourceArc による安全な Rust リソースの Elixir 管理

`ResourceArc<GameWorld>` により、Rust の `GameWorld` のライフタイムを Elixir のガベージコレクタが管理している。

```rust
// Elixir プロセスが ResourceArc を保持している間、GameWorld は解放されない
pub fn create_world() -> ResourceArc<GameWorld> {
    ResourceArc::new(GameWorld(RwLock::new(GameWorldInner { ... })))
}
```

Elixir プロセスが死ぬと `ResourceArc` の参照カウントが 0 になり、`GameWorld` が自動的に解放される。
メモリリークなしに Rust リソースを Elixir プロセスのライフタイムに紐付けられる。

---

### 18. エンティティパラメータの外部注入化

敵・武器・ボスのパラメータ（HP・速度・ダメージ等）を Rust にハードコードせず、`set_entity_params` NIF で Elixir 側から注入している。

```elixir
# Elixir 側（game_content）でパラメータを定義
def enemy_params do
  [
    %{max_hp: 30.0, speed: 80.0, radius: 20.0, damage_per_sec: 10.0, ...},
    %{max_hp: 60.0, speed: 50.0, radius: 30.0, damage_per_sec: 20.0, ...},
  ]
end
```

Rust を再コンパイルせずにゲームバランスを調整できる。
将来のビジュアルエディタ（`visual-editor-architecture.md` 参照）でパラメータをリアルタイム編集する基盤にもなる。

---

### 19. ボス AI の Elixir 側実装

ボスの移動・特殊行動・アイテムドロップを Elixir 側で制御している。

```elixir
# BossSystem: ボス出現スケジュール（Elixir 側）
def check_spawn(elapsed_sec, spawned_bosses) do
  @boss_schedule
  |> Enum.find(fn {time, kind, _} -> elapsed_sec >= time and kind not in spawned_bosses end)
  |> case do
    nil -> :no_boss
    {_, kind, name} -> {:spawn, kind, name}
  end
end
```

ボス AI のロジックを Rust に埋め込まないことで、コンテンツ側（`game_content`）が自由にボスの行動を定義できる。
Elixir のパターンマッチとイミュータブルなデータ変換が、ステートマシンとして機能している。

---

### 20. config.exs 1 行でコンテンツを切り替える設計

```elixir
config :game_server, :current, GameContent.VampireSurvivor
# または
config :game_server, :current, GameContent.AsteroidArena
```

エンジンのコードを一切変更せずにゲームコンテンツを切り替えられる。
`GameContent.AsteroidArena` が 2 つ目のコンテンツとして実際に動作しており、この設計が机上の空論でないことが証明されている。

---

## まとめ

| カテゴリ | 実現済みの強み |
|:---|:---|
| **Rust パフォーマンス** | SoA + SSE2 SIMD + FxHashMap 空間ハッシュ + アロケーションなしクエリ |
| **Rust 安全性** | ResourceArc によるライフタイム管理・RwLock による並行アクセス制御 |
| **Rust 決定論** | LCG 乱数によるシード固定の再現可能な物理演算 |
| **Elixir OTP** | Supervisor ツリー・DynamicSupervisor・Registry・ETS キャッシュ |
| **Elixir 設計** | イミュータブルなシーン状態・Behaviour による差し替え可能設計・Telemetry |
| **Elixir × Rust** | SSoT パターン・外部注入化・ResourceArc・コンテンツ切り替え |

> **「Rustで速く動かす基盤」と「Elixirで柔軟に制御する構造」は、すでに正しく噛み合っている。**
> あとは Elixir の真価（耐障害性・分散）をネットワーク層に解放するだけだ。

---

*関連ドキュメント*
- [`vision.md`](./vision.md) — 設計思想の核心
- [`improvement-plan.md`](./improvement-plan.md) — 改善すべき課題
- [`architecture-overview.md`](./architecture-overview.md) — 全体構成
