# AlchemyEngine — ビジョンと設計思想

## このドキュメントの目的

AlchemyEngine が「何を保証するか」「何を保証しないか」を明文化する。
これはコードの設計判断の拠り所であり、機能追加・リファクタリング・新しいコンテンツを作るときに立ち返るべき原則を定義する。

---

## 一言で言うと

> **AlchemyEngine は「無限の空間」と「そこに存在するユーザー」だけを保証する。**
> **空間の上に何を作るかはクリエイターが決める。それがコンテンツだ。**

---

## 2つの概念の定義

### Engine（エンジン）— AlchemyEngine が保証するもの

エンジンが提供するのは、あらゆるコンテンツの「器」となる基盤だけだ。

| 保証するもの | 説明 |
|---|---|
| **無限の3D空間** | f64 精度の座標系。原点から無限に広がる空間 |
| **ユーザーの存在** | 空間に存在し、位置・向きを持つプレイヤー |
| **物理の基盤** | 衝突判定・空間分割・移動の仕組み（コンテンツではなく器） |
| **ネットワーク基盤** | 複数のユーザーが同じ空間を共有できる同期の仕組み |
| **描画の基盤** | 空間に存在するものを画面に映す仕組み |
| **オーディオの基盤** | 空間に存在するものが音を鳴らせる仕組み（3D空間オーディオ・DSP） |
| **時間の流れ** | 60Hz で刻まれる物理時間 |
| **コンポーネントのライフサイクル** | `on_ready` / `on_process` / `on_physics_process` / `on_event` の呼び出しタイミング |

エンジンは「敵」「武器」「EXP」「スコア」「ボス」「レベル」「地形」「スカイボックス」を知らない。
これらはすべてコンテンツであり、クリエイターがコンポーネントとして定義するものだ。

### Content（コンテンツ）— クリエイターが持ち込むもの

コンテンツは**コンポーネントの集合**だ。

エンジンの上に乗るものはすべてコンテンツであり、コンテンツはコンポーネントで構成される。
「ワールド（空間の見た目・地形）」も「ルール（ゲームロジック）」も、どちらもコンポーネントの一種に過ぎない。

```
Content = [ComponentA, ComponentB, ComponentC, ...]
```

各コンポーネントはエンジンのライフサイクルに応答する：

```elixir
defmodule GameEngine.Component do
  @optional_callbacks [on_ready: 1, on_process: 1, on_physics_process: 1, on_event: 2]

  @callback on_ready(world_ref)          :: :ok  # 初期化時（1回）
  @callback on_process(context)          :: :ok  # 毎フレーム（Elixir側）
  @callback on_physics_process(context)  :: :ok  # 物理フレーム（60Hz）
  @callback on_event(event, context)     :: :ok  # イベント発生時
end
```

これは Unity の `MonoBehaviour`、Unreal の `ActorComponent`、Godot の `Node` と同じ思想だ。
エンジンはコンポーネントの「中身」を知らない。ライフサイクルのタイミングだけを提供する。

---

## Hub — コンテンツを公開する場所

クリエイターが作ったコンテンツは **Hub** にパブリッシュされる。
ユーザーは Hub から好きなコンテンツを選び、ダウンロードして遊ぶ。

```
クリエイターA: VampireSurvivor コンテンツ → Hub
クリエイターB: SpaceRace コンテンツ       → Hub
クリエイターC: DungeonRPG コンテンツ      → Hub
```

Hub 自体もエンジンが動かす一つのコンテンツだ。
ロビー、アバター選択、コンテンツ選択画面も、エンジンの空間上に存在する。

---

## 現在地と目指す場所

### 現在（VampireSurvivor フェーズ）

```
Engine ← 物理・描画・NIF基盤（Rust）+ ゲームループ制御（Elixir）
Content ← GameContent.VampireSurvivor（コンポーネント群）
```

`config :game_server, :current, GameContent.VampireSurvivor` でコンテンツを指定する。

エンティティパラメータ（敵HP・武器クールダウン等）は `set_entity_params` NIF 経由で Rust に注入済み。
ボスAI は Elixir 側コンポーネントで制御する。

### 目指す姿

```
Engine  ← 空間・ユーザー・物理基盤・ネットワーク基盤・コンポーネントライフサイクル
Content ← クリエイターが定義するコンポーネント群
Hub     ← コンテンツの一覧・選択・参加
```

---

## 設計判断の原則

機能追加やリファクタリングの際は、以下の問いに答えること。

**「これはエンジンの責務か？」**
→ 「どんなコンテンツにも必要か？」と問い直す。
→ VampireSurvivor にしか必要でないなら、エンジンに置かない。

**「エンジンはこの概念を知る必要があるか？」**
→ エンジンが知るべきは「エンティティが存在する」という事実だけ。
→ そのエンティティが「敵」か「NPC」かはコンポーネントが決める。

**「これはコンポーネントに分解できるか？」**
→ 単一責務のコンポーネントに分解できるなら、そうする。
→ コンポーネントは `on_ready` / `on_process` / `on_physics_process` / `on_event` のうち必要なものだけ実装する。

---

## 現在の実装との対応

### Elixir 側

| 現在のモジュール | 位置づけ | 移行方針 |
|---|---|---|
| `GameEngine.WorldBehaviour` | World 定義インターフェース | `GameEngine.Component` に統合予定 |
| `GameEngine.RuleBehaviour` | Rule 定義インターフェース | `GameEngine.Component` に統合予定 |
| `GameEngine.Config` | `current_world` / `current_rule` の設定解決 | `:current` キー一本に変更予定 |
| `GameEngine.SceneBehaviour` | シーンインターフェース | 現状維持 |
| `GameEngine.GameEvents` | エンジンコア | コンポーネントライフサイクル呼び出しに対応予定 |
| `GameContent.VampireSurvivorWorld` | WorldBehaviour の実装 | コンポーネントに分解予定 |
| `GameContent.VampireSurvivorRule` | RuleBehaviour の実装 | コンポーネントに分解予定 |
| `GameContent.EntityParams` | エンティティパラメータテーブル | コンポーネントの `on_ready` に移動予定 |

### Rust 側

| 現在のコード | 位置づけ |
|---|---|
| `GameWorldInner`（空間・物理） | Engine に残す |
| `entity_params.rs`（`EntityParamTables`） | `set_entity_params` NIF で外部注入済み（ハードコード廃止） |
| `weapon_slots`, `boss` フィールド | まだ `GameWorldInner` に残存（課題参照） |
| `hud_*` フィールド群 | `set_hud_level_state` NIF で毎フレーム注入（描画専用） |
| 物理演算・空間ハッシュ・衝突判定 | Engine に残す |

---

## 移行の完了状況

1. ✅ **Elixir 側の `context` からコンテンツ固有キーを除去**
   - `weapon_levels`, `level_up_pending`, `weapon_choices` を Playing シーン `state` に移動済み
   - エンジンが「武器」「レベルアップ」を知らない状態を実現

2. ✅ **Rust コアのエンティティパラメータを外部注入化**
   - `entity_params.rs` を `EntityParamTables` 構造体に変更し、`set_entity_params` NIF で注入
   - `set_world_size` NIF でマップサイズも外部注入

3. ✅ **ボスAI を Elixir 側に移行**
   - ボス移動・特殊行動・アイテムドロップを Elixir 側で制御

4. **`WorldBehaviour` / `RuleBehaviour` を `Component` に統合**（未着手）
   - `GameEngine.Component` ビヘイビアを新設
   - `GameContent.VampireSurvivor` をコンポーネント群として再構成
   - `config :game_server, :current` キー一本に変更

5. **残存課題**（`pending-issues.md` 参照）
   - `GameWorldInner` の `weapon_slots`, `boss` フィールドの除去

---

*このドキュメントはプロジェクトの思想の核心を記述するものであり、実装の詳細より優先される。*
*実装がこのビジョンと乖離していると感じたときは、このドキュメントを更新してから実装を変更すること。*
