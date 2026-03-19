# 既存コンテンツ移行プラン

> 作成日: 2026-03-12  
> 参照: [docs/architecture/fix_contents.md](../../architecture/fix_contents.md), [fix-contents-implementation-procedure.md](../completed/fix-contents-implementation-procedure.md)  
> 目的: `lib/contents/` 配下の既存コンテンツを、新アーキテクチャ（structs / nodes / components / objects）へ順次移行する。
>
> **方針**: 移行後も `Core.ContentBehaviour` の契約を維持し、既存エンジン（GameEvents, SceneStack）から透過的に動作する。内部実装のみを新アーキテクチャに置き換える。

---

## 1. 概要

### 1.1 移行の定義


| 項目       | 内容                                                    |
| -------- | ----------------------------------------------------- |
| **移行対象** | `apps/contents/lib/contents/` 配下の各コンテンツ               |
| **移行先**  | 同一パス（in-place）。モジュール名・ContentBehaviour 契約は維持          |
| **変更範囲** | 内部実装を structs / nodes / components / objects に置き換え    |
| **非変更**  | エンジンとのインターフェース（Core.ContentBehaviour, Core.Component） |


### 1.2 移行順序と根拠


| 順位  | コンテンツ               | 根拠                                                   |
| --- | ------------------- | ---------------------------------------------------- |
| 1   | **FormulaTest**     | ノードグラフと親和性が高い。FormulaGraph → Contents.Nodes の置き換えが自然 |
| 2   | **CanvasTest**      | UI 系。Contents.Components.Category.UI との対応を検証         |
| 3   | **SimpleBox3D**     | 物理・ゲームロジック。Object 階層の適用パターンを確立                       |
| 4   | **BulletHell3D**    | コンポーネント数増加。弾・ダメージのノード化                               |
| 5   | **AsteroidArena**   | NIF（SpawnSystem）との境界を Object 層で整理                    |
| 6   | **RollingBall**     | 複数シーン・独自物理。シーン遷移の Object 化                           |
| 7   | **VampireSurvivor** | 最も複雑。武器・ボス・レベルアップの全層移行                               |


**除外**: `builtin` は `.gitkeep` のみのため対象外。**Telemetry** は CanvasTest と役割が重複するため、**VRTest** は現状未動作のため、移行対象から外している。

### 1.3 前提条件

- **骨格の完成**: structs, nodes, components, objects の骨格が fix-contents-implementation-procedure に従い実装済みであること
- **Executor**: ノードグラフ実行用の Executor が未実装の場合、Phase 1（FormulaTest）で簡易 Executor または手動呼び出しを実装する

---

## 2. 移行の共通パターン

### 2.1 各コンテンツで行うこと

1. **Scene の origin と着地点参照**: Scene の state に **origin**（空間の原点）を持ち、必要に応じて着地点となる Object への参照（例: `landing_object`）を持つ。root_object 必須は廃止。既存コンテンツは移行対象外のため root_object を残したままでも許容。参照: [scene-and-object.md](../../architecture/scene-and-object.md), [scene-origin-and-landing-reference-plan.md](./scene-origin-and-landing-reference-plan.md)
2. **Object 階層の導入**: シーン state に「空間の実体」を `Contents.Objects.Core.Struct` で表現
3. **Component の二重化解消**: `Core.Component`（エンジン用）と `Contents.Behaviour.Components`（新アーキテクチャ）の役割を整理
  - 当面: 既存 `Core.Component` を維持しつつ、内部で新 Object/Node を参照
  - 将来: 新 Component がノードを束ね、エンジン用の薄いアダプタが Core.Component を実装
4. **Node の活用**: 計算・論理部分を `Contents.Nodes` に移行（該当する場合）
5. **Structs の利用**: データ型を `Structs.Category.`* に統一（該当する場合）

### 2.2 移行時の制約

- 既存の `Contents.Behaviour.Content` コールバックは変更しない
- `Core.Component` の `on_nif_sync`, `on_event` 等はエンジンが呼ぶため、シグネチャを維持
- 移行中は既存テスト・手動動作確認でリグレッションを防ぐ

---

## 3. Phase 別実施内容

---

### Phase 0: 事前準備（推奨）


| タスク          | 内容                                                |
| ------------ | ------------------------------------------------- |
| Executor の検討 | ノードグラフを Link に従って実行する Executor を、簡易版でもよいので実装するか決定 |
| 移行用ブランチ      | 各 Phase をブランチで実施し、マージ前に動作確認                       |


---

### Phase 1: FormulaTest ✅ 完了（2026-03-12）

**目的**: FormulaGraph を Contents.Nodes に置き換え、ノードアーキテクチャの移行パターンを確立する。

#### 1.1 現状

- `Content.FormulaTest.Scenes.Playing` が `Core.FormulaGraph` で 5 パターンの式を実行
- 結果を `formula_results` として state に格納し、RenderComponent で HUD 表示

#### 1.2 移行内容


| 対象               | 変更内容                                                                                                      |
| ---------------- | --------------------------------------------------------------------------------------------------------- |
| `Scenes.Playing` | `FormulaGraph.run` を、`Contents.Nodes`（Value, Add, Sub, Equals 等）を手動または Executor で実行する処理に置き換え              |
| テストパターン          | test_add_inputs, test_constants, test_comparison, test_store, test_multiple_outputs を Contents.Nodes で再実装 |
| Object 階層        | Root Object を `Objects.Core.Struct.new` で作成し、state に保持（検証用）                                               |


#### 1.3 不足ノードの対応

- `test_comparison` の `lt`: `Contents.Nodes.Category.Operators.Equals` に less-than 相当があれば利用。なければ `operators/less.ex` を追加
- `test_store` の read_store / write_store: 新アーキテクチャに Store ノードがなければ、Phase 1 では簡略化（store テストをスキップするか、別モジュールで暫定実装）

#### 1.4 検証

- `config :server, :current, Content.FormulaTest` で起動
- HUD に 5 パターン（または store を除く 4 パターン）の結果が表示されること
- 既存の FormulaGraph は `Core.FormulaStore` 等で使用中のため、削除しない

---

### Phase 2: CanvasTest ✅ 完了（2026-03-17）

**目的**: UI 系コンポーネントと新アーキテクチャの対応を検証する。

#### 2.1 現状

- InputComponent, RenderComponent
- ワールド空間の Canvas パネル、HUD Canvas

#### 2.2 移行内容


| 対象                                  | 変更内容                                                                                      |
| ----------------------------------- | ----------------------------------------------------------------------------------------- |
| ワールドパネル                             | 各パネルを Object として表現。`Objects.Core.Struct` に transform で 3D 位置を保持                           |
| `Contents.Components.Category.UI.`* | Canvas, RectTransform, Text 等が既にあれば、RenderComponent 内で参照。なければ、Object 階層のみ導入し、描画は既存ロジックを維持 |


#### 2.3 検証

- HUD の表示/非表示、ワールドパネル、Quit ボタンが従来通り動作すること

#### 2.4 実施内容（2026-03-17）

- **Scenes.Playing**: `origin`（Transform）、`children`（ワールドパネル用 Object 4 件）を state に追加。各パネルは `Contents.Objects.Core.Struct` で `transform.position` に 3D 座標を保持（(5,1.5,-5), (-5,1.5,-5), (0,1.5,-10), (8,1.5,0)）。
- **RenderComponent**: ワールドノードを `state.children` から組み立てる `build_world_nodes_from_objects/2` を追加。各 Object の `transform.position` を参照し、テキストは従来どおり（静的な 3 件＋4 番目は FPS/Pos で動的）。`Contents.Components.Category.UI.*` は既存の骨格のみのため、Object 階層のみ導入し描画ロジックは維持。

---

### Phase 3: SimpleBox3D ✅ 完了（2026-03-19）

**目的**: ゲームロジック（プレイヤー・敵・衝突）を Object / Component で表現する。

#### 3.1 現状

- SpawnComponent, InputComponent, RenderComponent
- physics_scenes 使用（move_input を Rust から取得）
- シーン: Playing, GameOver

#### 3.2 移行内容


| 対象             | 変更内容                                                                    |
| -------------- | ----------------------------------------------------------------------- |
| プレイヤー・敵        | 各々を `Objects.Core.Struct` で表現。transform.position で座標を保持                 |
| 衝突判定           | ノード化は任意。Object の position を比較する関数を Component 内に配置                       |
| physics_scenes | 既存のまま。move_input は GameEvents 経由で届くため、InputComponent が state を更新する現状を維持 |


#### 3.3 検証

- プレイヤー移動、敵の追跡、衝突でゲームオーバー、リトライが従来通り動作すること

#### 3.4 実施内容（2026-03-19）

- **Scenes.Playing**: `origin`（Transform）、`landing_object`（プレイヤー Object への参照）、`player_object`（`Objects.Core.Struct`）、`enemy_objects`（敵 Object リスト）を state に追加。各 Object の `transform.position` に 3D 座標を保持。tick 処理で `extract_positions` / `put_position` / `put_positions` により Object の position を更新。`collides_any?` は Object の position を比較する既存ロジックを維持。
- **RenderComponent**: `build_commands` で `player_object`・`enemy_objects` から `position_from_object` で座標を取得し DrawCommand を組み立て。`player_object` が nil の場合は `{0,0,0}` をフォールバック。
- **InputComponent**: `Contents.SceneStack` → `Contents.Scenes.Stack` に修正（既知の不具合対応）。

---

### Phase 4: BulletHell3D ✅ 完了（2026-03-19）

**目的**: 弾・ダメージのコンポーネントを Object / Node で整理する。

#### 4.1 現状

- SpawnComponent, InputComponent, BulletComponent, DamageComponent, RenderComponent

#### 4.2 移行内容


| 対象     | 変更内容                                                      |
| ------ | --------------------------------------------------------- |
| 弾・敵    | Object として表現。BulletComponent が Object リストを管理              |
| ダメージ計算 | 可能であれば Nodes（Equals, 減算等）で表現。複雑なら既存ロジックを維持し、Object 参照のみ追加 |


#### 4.3 検証

- 弾幕、HP 減少、ゲームオーバーが従来通り動作すること

#### 4.4 実施内容（2026-03-19）

- **構成変更**: `scenes/` を廃止し、`game_over.ex` と `playing.ex` を `bullet_hell_3d/` 直下に配置。モジュール名を `Content.BulletHell3D.Playing` / `Content.BulletHell3D.GameOver` に変更。
- **共有コンポーネントへ移行**: SpawnComponent, InputComponent, BulletComponent, DamageComponent, RenderComponent を削除。`Contents.Components.Category.Spawner`, `Device.Mouse`, `Device.Keyboard`, `Rendering.Render` を使用。`build_frame/2` を Content に追加し Playing.build_frame に委譲。
- **Playing**: `origin`、`landing_object`、`player_object`（`Objects.Core.Struct`）、`enemy_objects`（`[%{id, object}]`）、`bullet_objects`（`[%{id, object, vel}]`）を state に追加。各 Object の `transform.position` で座標を保持。tick 処理で `extract_positions` / `put_position` / `put_positions` により Object の position を更新。弾は Object + vel のペアで管理。衝突判定は Object の position を比較する既存ロジックを維持。
- **build_frame**: `player_object`・`enemy_objects`・`bullet_objects` から `position_from_object` で座標を取得し DrawCommand を組み立て。HUD は従来どおり。

---

### Phase 5: AsteroidArena

**目的**: NIF（SpawnSystem, world_ref）との境界を Object 層で整理する。

#### 5.1 現状

- SpawnComponent, SplitComponent
- SpawnSystem が NIF 経由でエンティティをスポーン

#### 5.2 移行内容


| 対象       | 変更内容                                                  |
| -------- | ----------------------------------------------------- |
| エンティティ表現 | NIF 側のエンティティと Object を 1:1 または N:1 で対応させる設計を検討        |
| 境界       | Object は「Elixir 側の論理的な実体」、NIF は「Rust 側の物理・描画」として責務を分離 |


#### 5.3 検証

- 小惑星・UFO のスポーン、分裂、プレイヤー死亡が従来通り動作すること

---

### Phase 6: RollingBall

**目的**: 複数シーン・独自物理を Object 階層で構造化する。

#### 6.1 現状

- 5 シーン: Title, Playing, StageClear, GameOver, Ending
- PhysicsComponent（Elixir 側で重力・摩擦・衝突を計算）
- StageData

#### 6.2 移行内容


| 対象               | 変更内容                                         |
| ---------------- | -------------------------------------------- |
| ボール・フロア・障害物      | Object として表現。Transform で位置・回転を保持             |
| PhysicsComponent | 計算ロジックを維持しつつ、Object の transform を更新する形に変更    |
| シーン遷移            | 既存の SceneStack を維持。各シーン state に Object 階層を追加 |


#### 6.3 検証

- 全シーン遷移、ボールの転がり、ゴール・穴落下が従来通り動作すること

---

### Phase 7: VampireSurvivor

**目的**: 最も複雑なコンテンツの全層移行。武器・ボス・レベルアップを Object / Node で表現する。

#### 7.1 現状

- 5 コンポーネント、4 シーン
- LevelSystem, BossSystem, WeaponFormulas, EntityParams

#### 7.2 移行内容


| 対象            | 変更内容                                                    |
| ------------- | ------------------------------------------------------- |
| 武器フォーミュラ      | `Core.FormulaGraph` または既存式を、Contents.Nodes で再実装（可能な範囲で） |
| 敵・ボス          | Object として表現                                            |
| レベルアップ・ボスアラート | シーン state に Object 階層を追加                                |


#### 7.3 検証

- ゲームプレイ、レベルアップ、ボス出現、セーブ/ロードが従来通り動作すること

---

## 4. 移行チェックリスト（全 Phase 共通）

各 Phase 完了時に確認する項目:

- `mix compile --warnings-as-errors` が通る
- `config :server, :current, Content.XXX` で起動し、従来の挙動が維持されている
- 既存テストが通る（該当する場合）
- 依存方向が守られている（structs → nodes → components → objects）
- 移行内容をドキュメント化（本プランの該当 Phase に追記）

---

## 5. リスクと対策


| リスク                                       | 対策                                                                                  |
| ----------------------------------------- | ----------------------------------------------------------------------------------- |
| Executor 未実装で FormulaTest 移行が進まない         | 手動でノードを呼び出す簡易実装で Phase 1 を完了。Executor は後続で追加                                        |
| NIF との境界が曖昧                               | Phase 5（AsteroidArena）で Object と NIF の責務を文書化。必要に応じてアダプタ層を導入                         |
| 移行中に既存コンテンツが壊れる                           | 各 Phase を小さく区切り、マージ前に動作確認。必要に応じて feature flag で新旧を切り替え                              |
| Core.Component と Contents.Components の二重化 | 当面は Core.Component を維持。新 Component は「ノード束」として内部で使用し、エンジンには Core.Component の薄いラッパを渡す |


---

## 6. 参照

- [fix_contents.md](../../architecture/fix_contents.md) — アーキテクチャ概要
- [scene-and-object.md](../../architecture/scene-and-object.md) — Scene と Object の責務、Scene state の規約（origin・着地点参照）
- [scene-concept-addition-plan.md](../completed/scene-concept-addition-plan.md) — Scene 概念の追加プラン（完了）
- [fix-contents-implementation-procedure.md](../completed/fix-contents-implementation-procedure.md) — 骨格実装手順

