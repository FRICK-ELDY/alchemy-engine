# AlchemyEngine — ビジョンと設計思想

## このドキュメントの目的

AlchemyEngine が「何を保証するか」「何を保証しないか」を明文化する。
これはコードの設計判断の拠り所であり、機能追加・リファクタリング・新しいコンテンツを作るときに立ち返るべき原則を定義する。

---

## 一言で言うと

> **AlchemyEngine は「無限の空間」と「そこに存在するユーザー」だけを保証する。**
> **世界を作るのはクリエイター。ルールを作るのもクリエイター。ゲームはその組み合わせだ。**

---

## 3つの概念の定義

### Engine（エンジン）— AlchemyEngine が保証するもの

エンジンが提供するのは、あらゆる世界の「器」となる基盤だけだ。

| 保証するもの | 説明 |
|---|---|
| **無限の3D空間** | f64 精度の座標系。原点から無限に広がる空間 |
| **ユーザーの存在** | 空間に存在し、位置・向きを持つプレイヤー |
| **物理の基盤** | 衝突判定・空間分割・移動の仕組み（ルールではなく器） |
| **ネットワーク基盤** | 複数のユーザーが同じ空間を共有できる同期の仕組み |
| **描画の基盤** | 空間に存在するものを画面に映す仕組み |
| **オーディオの基盤** | 空間に存在するものが音を鳴らせる仕組み（3D空間オーディオ・DSP） |
| **時間の流れ** | 60Hz で刻まれる物理時間 |

エンジンは「敵」「武器」「EXP」「スコア」「ボス」「レベル」を知らない。
これらはすべてルールであり、クリエイターが定義するものだ。

### World（ワールド）— クリエイターが持ち込むもの（その1）

ワールドは「どんな空間か」を定義する。エンジンが提供する空間に「意味」を与えるものだ。

| クリエイターが定義するもの | 例 |
|---|---|
| **地形・障害物** | 草原、洞窟、宇宙空間 |
| **エンティティの種類** | この世界に何が存在するか（敵、NPC、オブジェクト） |
| **アセット** | スプライト、3Dモデル、サウンド |
| **空間の性質** | 重力の有無、昼夜サイクル、天候 |

ワールドはルールを持たない。ただそこに「存在する」だけだ。
同じワールドに異なるルールを適用することで、異なるゲームが生まれる。

### Rule（ルール）— クリエイターが持ち込むもの（その2）

ルールは「その世界でどう振る舞うか」を定義する。ゲームの「意味」を与えるものだ。

| クリエイターが定義するもの | 例 |
|---|---|
| **勝敗条件** | 生き残る、ゴールに到達する、スコアを競う |
| **イベントの解釈** | 「エンティティが消えた」→「倒した」と解釈するかどうか |
| **状態の管理** | HP、EXP、スコア、レベル（ルールが必要なら持つ） |
| **ゲームフロー** | 開始・終了・シーン遷移 |
| **パラメータ** | エンティティの強さ、報酬の量 |

ルールはワールドを知らなくてもよい。
「エンティティが消えたらポイントを加算する」というルールは、
どんなワールドにも適用できる。

### Game（ゲーム）— World + Rule の組み合わせ

```
Game = World + Rule
```

VampireSurvivor は「草原のワールド」に「ウェーブサバイバーのルール」を組み合わせたゲームだ。
同じ「草原のワールド」に「探索RPGのルール」を組み合わせれば別のゲームになる。

---

## Hub — 世界を公開する場所

クリエイターが作った Game（World + Rule）は **Hub** にパブリッシュされる。
ユーザーは Hub から好きな世界を選んで遊ぶ。

```
クリエイターA: 草原ワールド + サバイバールール → ゲームA → Hub
クリエイターB: 宇宙ワールド + レースルール    → ゲームB → Hub
クリエイターC: 草原ワールド + 探索RPGルール   → ゲームC → Hub
                ↑ 同じワールドを再利用
```

Hub 自体もエンジンが動かす一つの「世界」だ。
ロビー、アバター選択、ゲーム選択画面も、エンジンの空間上に存在する。

---

## 現在地と目指す場所

### 現在（VampireSurvivor フェーズ）

```
Engine ← 物理・描画・NIF基盤（Rust）+ ゲームループ制御（Elixir）
World  ← VampireSurvivorWorld（草原 + 5種の敵・エンティティパラメータ注入）
Rule   ← VampireSurvivorRule（ウェーブ・EXP・武器・ボスAI）
```

`WorldBehaviour` と `RuleBehaviour` の分割は完了済み。
`config :game_server, current_world: VampireSurvivorWorld, current_rule: VampireSurvivorRule` で組み合わせる。

エンティティパラメータ（敵HP・武器クールダウン等）は `set_entity_params` NIF 経由で Rust に注入済み。
ボスAI は Elixir 側 `RuleBehaviour.update_boss_ai/2` で制御済み。

残存課題：`GameWorldInner` に `weapon_slots`・`boss`・`hud_*` フィールドが残っており、
2つ目のコンテンツを作る際に Rule 側への移動が必要（`pending-issues.md` 参照）。

### 目指す姿

```
Engine ← 空間・ユーザー・物理基盤・ネットワーク基盤
World  ← クリエイターが定義（WorldBehaviour 実装）
Rule   ← クリエイターが定義（RuleBehaviour 実装）
Game   ← World + Rule を config で組み合わせる
Hub    ← Game の一覧・選択・参加
```

---

## 設計判断の原則

機能追加やリファクタリングの際は、以下の問いに答えること。

**「これはエンジンの責務か？」**
→ 「どんなゲームにも必要か？」と問い直す。
→ VampireSurvivor にしか必要でないなら、エンジンに置かない。

**「これはワールドの責務か？ルールの責務か？」**
→ 「ルールが変わっても存在するか？」と問い直す。
→ 地形はルールが変わっても存在する → ワールド。
→ EXP はルールが変わると消える → ルール。

**「エンジンはこの概念を知る必要があるか？」**
→ エンジンが知るべきは「エンティティが存在する」という事実だけ。
→ そのエンティティが「敵」か「NPC」かはルールが決める。

---

## 現在の実装との対応

### Elixir 側

| 現在のモジュール | 位置づけ |
|---|---|
| `GameEngine.WorldBehaviour` | World 定義インターフェース（実装済み） |
| `GameEngine.RuleBehaviour` | Rule 定義インターフェース（実装済み） |
| `GameEngine.Config` | `current_world` / `current_rule` の設定解決（実装済み） |
| `GameEngine.SceneBehaviour` | Rule 側のシーンインターフェース（現状維持） |
| `GameEngine.GameEvents` | エンジンコア（ルール固有キーを除去済み） |
| `GameContent.VampireSurvivorWorld` | WorldBehaviour の実装例 |
| `GameContent.VampireSurvivorRule` | RuleBehaviour の実装例 |
| `GameContent.EntityParams` | VampireSurvivor 専用パラメータテーブル（Elixir 側 SSoT） |

### Rust 側

| 現在のコード | 位置づけ |
|---|---|
| `GameWorldInner`（空間・物理） | Engine に残す |
| `entity_params.rs`（`EntityParamTables`） | `set_entity_params` NIF で外部注入済み（ハードコード廃止） |
| `weapon_slots`, `boss` フィールド | まだ `GameWorldInner` に残存（課題8参照） |
| `hud_*` フィールド群 | `set_hud_level_state` NIF で毎フレーム注入（描画専用） |
| 物理演算・空間ハッシュ・衝突判定 | Engine に残す |

---

## 移行の完了状況

1. ✅ **Elixir 側の `context` からルール固有キーを除去**
   - `weapon_levels`, `level_up_pending`, `weapon_choices` を Playing シーン `state` に移動済み
   - エンジンが「武器」「レベルアップ」を知らない状態を実現

2. ✅ **`GameBehaviour` を `WorldBehaviour` と `RuleBehaviour` に分割**
   - `GameEngine.WorldBehaviour` / `GameEngine.RuleBehaviour` として実装済み
   - `GameEngine.Config` で `current_world` / `current_rule` を解決

3. ✅ **Rust コアのエンティティパラメータを外部注入化（Phase 3-A）**
   - `entity_params.rs` を `EntityParamTables` 構造体に変更し、`set_entity_params` NIF で注入
   - `set_world_size` NIF でマップサイズも外部注入

4. ✅ **ボスAI を Elixir 側に移行（Phase 3-B）**
   - `RuleBehaviour.update_boss_ai/2` でボス移動・特殊行動を Elixir 側で制御
   - `on_entity_removed/4`, `on_boss_defeated/4` でアイテムドロップを Elixir 側で制御

5. **残存課題**（`pending-issues.md` 参照）
   - `GameWorldInner` の `weapon_slots`, `boss` フィールドの除去
   - 2つ目のコンテンツを作り始めるタイミングで実施

---

*このドキュメントはプロジェクトの思想の核心を記述するものであり、実装の詳細より優先される。*
*実装がこのビジョンと乖離していると感じたときは、このドキュメントを更新してから実装を変更すること。*
