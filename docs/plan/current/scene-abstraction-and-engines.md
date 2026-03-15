# シーン抽象化と他エンジンとの比較

> 作成日: 2026-03-15  
> 目的: 「Contents.Scenes.Playing を Content.VampireSurvivor で使う」ような抽象化を検討するため、Unity / Unreal / Godot のシーン・モードの扱いを整理し、AlchemyEngine での設計案を示す。

---

## 1. 他エンジンの扱い方

### 1.1 Unity

- **シーン = アセット**: シーンは `.unity` ファイル（SceneAsset）であり、「Playing」という型が1つあるわけではない。ゲームごとに別シーン（VampireSurvivorGameplay.unity, FormulaTestPlay.unity）を持つ。
- **役割の分け方**: 「プレイ中」という**役割**は、シーンにアタッチされた**スクリプト**（MonoBehaviour）で表現する。共通の「GameplaySceneController」のような基底スクリプトを複数シーンで使い回すことはよくある。
- **抽象化の形**: 「Playing という型」はクラス（スクリプト）として共有し、**シーンアセットはコンテンツごと**。つまり「振る舞いの型は共通、中身（オブジェクト構成・設定）はコンテンツごと」。

### 1.2 Unreal Engine

- **レベルと GameMode**: レベル（.umap）は「場」のデータ。**GameMode** が「いま何をしているか」（ルール・フェーズ・スポーン規則）を定義する。GameMode はレベルごと／プロジェクト設定で「このレベルではこの GameMode」と紐づく。
- **抽象化の形**: 「Playing」に相当するのは **GameMode クラス**（例: `AGameModeBase` を継承した `AMyGameMode`）。複数レベルが**同じ GameMode** を使い、レベル側はマップの違いだけ持つ。必要なら GameMode をサブクラス化してゲーム固有のルールを足す。
- **まとめ**: 「Playing」＝1つのクラス（GameMode）。コンテンツ（レベル）は「その GameMode を使う」か「GameMode のサブクラスを指定する」。

### 1.3 Godot

- **シーン = ノードツリー**: シーンは `.tscn`（PackedScene）で、ノードツリーのテンプレート。**継承**（親シーンを拡張した子シーン）と**コンポジション**（シーンをインスタンス化して組み合わせ）の両方がある。
- **抽象化の形**:
  - **継承**: 「BasePlaying.tscn」を継承して「VampireSurvivorPlaying.tscn」を作る。共通の「Playing」の土台を1つにまとめ、ゲームごとにオーバーライド・追加。
  - **スクリプトの共通化**: ルートノードに張るスクリプト（例: `Playing.gd`）を共通にし、複数の .tscn が同じスクリプトを参照する。中身（ノード構成）は .tscn ごとに違う。
- **まとめ**: 「Playing」＝基底シーンまたは共通スクリプト。コンテンツは「そのシーンを継承した .tscn」か「同じスクリプトを使う別 .tscn」で「Playing を使う」。

---

## 2. 共通パターンの整理

| エンジン | 「Playing」の正体 | コンテンツが使う方法 |
|---------|-------------------|------------------------|
| **Unity** | 共通スクリプト（振る舞いの型） | 各ゲームのシーンアセットにそのスクリプトをアタッチ |
| **Unreal** | GameMode クラス | レベルがその GameMode（またはサブクラス）を指定 |
| **Godot** | 基底シーン or 共通スクリプト | 継承 .tscn または同じスクリプトを使う別 .tscn |

いずれも「**Playing という役割は1つにまとめ、コンテンツはその型／クラス／シーンを「使う」または「拡張する」**」という形になっている。

---

## 3. AlchemyEngine での抽象化の方向性

要望は「**Contents.Scenes.Playing という1つのシーンを、Content.VampireSurvivor などでそのまま使えるようにする**」ことと理解した。以下、3案を挙げる。

### 案A: 汎用シーンモジュール + コンテンツコールバック（UE の GameMode に近い）

- **Contents.Scenes.Playing** を1モジュールにし、`init/1` の `init_arg` で **どのコンテンツか** を渡す（例: `%{content: Content.VampireSurvivor}`）。
- コンテンツは **Playing 用のコールバック** を実装する（例: `ContentBehaviour` に `playing_init/1`, `playing_update/2` を追加するか、別の Behaviour で定義）。
- `Contents.Scenes.Playing` は内部で `content.playing_init(arg)` / `content.playing_update(ctx, state)` を呼ぶ。状態の形もコンテンツ任せにするか、共通のキー（`root_object` 等）だけ必須にする。

**長所**: 「Playing」が1モジュールで、コンテンツは「そのシーンを使う」だけ。  
**短所**: ContentBehaviour（または別契約）が Playing 用に肥大化する可能性。シーン種別（Title, GameOver 等）を増やすたびにコールバックが増える。

---

### 案B: シーン種別は atom、実装はコンテンツ（シーン型 = ラベル）

- シーンを「モジュール」ではなく **種別（atom）** で扱う。例: `:playing`, `:title`, `:game_over`。
- **ContentBehaviour** に `scene_init(type, init_arg)` / `scene_update(type, context, state)` / `scene_render_type(type)` を追加。SceneStack は「現在のコンテンツ」と「現在のシーン種別」を持ち、`content.scene_init(:playing, arg)` のように呼ぶ。
- 「Contents.Scenes.Playing」は **概念**（`:playing` というラベル）としてのみ存在し、**実装は常にコンテンツ側**。コンテンツが「:playing のときはこう振る舞う」を実装する。

**長所**: シーン型が一覧化しやすく、`Content.VampireSurvivor` が「:playing をこう実装する」と明確。  
**短所**: 今の「1シーン = 1モジュール」からは設計が変わる。既存の `Content.XXX.Scenes.Playing` や `Contents.Scenes.FormulaTest.Playing` は「:playing の実装をそのモジュールに委譲する」ようなラッパにする必要がある。

---

### 案C: 汎用 Playing + オプション／設定（Unity の共通スクリプトに近い）

- **Contents.Scenes.Playing** は「プレイ中シーン」の共通ロジックだけを持つ（例: 経過時間の更新、共通の遷移判定の枠だけ）。
- コンテンツは `initial_scenes` で `%{module: Contents.Scenes.Playing, init_arg: %{content: Content.VampireSurvivor, ...}}` のように**同じモジュール**を指定する。
- `init_arg` で渡した `content` やオプションに応じて、Contents.Scenes.Playing が「root_object の作り方」「update で何を読むか」を切り替える。必要なら content が提供する小さなコールバック（例: `content.playing_custom_init/1`）だけ呼ぶ。

**長所**: 既存の「シーン = モジュール」を維持しつつ、Playing を1つにまとめられる。  
**短所**: `Contents.Scenes.Playing` が `content` に強く依存し、分岐が増える可能性。

---

## 4. 推奨の考え方

- **短期**: 今の「コンテンツごとのシーンモジュール」（例: `Contents.Scenes.FormulaTest.Playing`, `Contents.Scenes.VampireSurvivor.Playing`）を維持しつつ、`apps/contents/lib/scenes` に集約する方針で問題ない。
- **中期**: 「Playing を1つにしたい」なら **案B（シーン種別 = atom、実装 = コンテンツ）** が他エンジンとも比べやすく、拡張しやすい。SceneStack が「(content, scene_type)」をキーに持ち、ContentBehaviour に `scene_*` コールバックを足す形。
- **案A・案C** は、既存の「シーン = モジュール」を活かしつつ、Playing だけ共通化したい場合の現実的な妥協案になる。

---

## 5. 参照

- [scene-and-object.md](../../architecture/scene-and-object.md) — Scene の責務
- [contents-migration-plan.md](./contents-migration-plan.md) — Phase 1 とシーン配置
- [formula-test-scene-migration-procedure.md](./formula-test-scene-migration-procedure.md) — FormulaTest のシーン移行手順（現方式）
- [scene-type-as-atom-implementation-procedure.md](./scene-type-as-atom-implementation-procedure.md) — 案B 実施手順書
