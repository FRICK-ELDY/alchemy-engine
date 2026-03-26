# mix compile 警告とマップ層の今後の方針

> 作成日: 2026-03-15  
> 関連: [scene-type-as-atom-implementation-procedure.md](./scene-type-as-atom-implementation-procedure.md)  
> 目的: `mix compile` で出ている「never used」警告の内容を記録し、`map_transition_module_to_scene_type` / `scene_module_to_type` をどう扱うかの検討事項をドキュメント化する。

---

## 1. 現在の mix compile 警告

### 1.1 警告の種類

すべて **「this clause of defp map_transition_module_to_scene_type/1 is never used」** である。

各 Content モジュール（SimpleBox3D, BulletHell3D, AsteroidArena, VampireSurvivor, RollingBall）の `map_transition_module_to_scene_type/1` のうち、*現状の Scenes. の update 戻り値では使われていない節** に対して出ている。

### 1.2 対象ファイルと「未使用」になっている節のパターン


| コンテンツ           | ファイル                                             | 未使用とされる節（パターン）                                                                                                                                                                     |
| --------------- | ------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| SimpleBox3D     | `apps/contents/lib/contents/simple_box_3d.ex`    | `{:continue, state, opts}` / `{:transition, :pop, state}` および opts 付き / `{:transition, {:push, mod, arg}, state}` および opts 付き / `{:transition, {:replace, mod, arg}, state, opts}` |
| BulletHell3D    | `apps/contents/lib/contents/bullet_hell_3d.ex`   | 同上                                                                                                                                                                                 |
| AsteroidArena   | `apps/contents/lib/contents/asteroid_arena.ex`   | 同上                                                                                                                                                                                 |
| VampireSurvivor | `apps/contents/lib/contents/vampire_survivor.ex` | 同上                                                                                                                                                                                 |
| RollingBall     | `apps/contents/lib/contents/rolling_ball.ex`     | 同上                                                                                                                                                                                 |


- **実際に使われている節**: 各コンテンツの Scenes.* が返している形のみ（主に `{:continue, state}` と `{:transition, {:replace, mod, arg}, state}` の 3 要素タプル）。
- **未使用の節**: 上記以外。具体的には
  - 4 要素タプル（opts 付き）: `{:continue, state, opts}`, `{:transition, action, state, opts}`
  - `:pop` 遷移: `{:transition, :pop, state}` および opts 付き
  - `:push` 遷移: `{:transition, {:push, mod, arg}, state}` および opts 付き
  - `{:replace, mod, arg}` の opts 付き

### 1.3 なぜこれらの節を用意しているか

- **ContentBehaviour の契約**: `scene_update/3` の戻り値として、opts 付きの 4 要素タプルや `:pop` / `{:push, scene_type, init_arg}` / `{:replace, scene_type, init_arg}` が許容されている。
- **移行期の実装**: 現状は Content の `scene_update` が既存の `Content.XXX.Scenes.*` に委譲し、その戻り値（モジュールを返す 3 要素タプル中心）を `map_transition_module_to_scene_type` で scene_type に変換している。
- **将来の安全のため**: Scenes.* が将来 opts を返す、または `:pop` / `:push` を返すように変更した場合に FunctionClauseError にしないよう、契約で許容されている形を一通り受け取れるようにしている。その結果、現時点では「使われていない節」が残り、コンパイラに「never used」と警告されている。

---

## 2. 現状の設計（委譲＋マップ層）

- **Content** の `scene_init` / `scene_update` / `scene_render_type` は、必要な scene_type についてのみ実装し、多くは **既存の `Content.XXX.Scenes.*` に委譲**している。
- **scene_update** の戻り値は、Scenes.* がまだ **モジュール**（例: `Content.VampireSurvivor.Scenes.GameOver`）を返すため、Content 側で `**map_transition_module_to_scene_type`** により `module` → **scene_type**（例: `:game_over`）に変換している。
- 変換テーブルとして `**scene_module_to_type/1`**（各 Content 内の private 関数）で、自コンテンツの Scenes モジュール → scene_type を定義している。未知モジュール用の catch-all で `raise("unknown scene module: ...")` を入れているコンテンツもある。

この「委譲＋戻り値の module → scene_type 変換」が**二重対応**になっており、警告の温床ともなっている。

---

## 3. 警告の扱いと今後の方針（検討事項）

### 3.1 警告への対処オプション


| 方針                    | 内容                                                                                         | メリット                                           | デメリット・注意                                                                    |
| --------------------- | ------------------------------------------------------------------------------------------ | ---------------------------------------------- | --------------------------------------------------------------------------- |
| **A. 現状のまま受け入れる**     | 未使用節はそのまま残し、警告は許容する。                                                                       | 将来 Scenes.* が opts / :pop / :push を返してもそのまま動く。 | `mix compile --warnings-as-errors` は通らない。警告数が多い。                            |
| **B. 未使用節を削除する**      | 「never used」と出ている節だけ削除する。                                                                  | 警告が減り、`--warnings-as-errors` を通しやすくなる。         | 将来 Scenes.* がその形を返したときに FunctionClauseError。契約（ContentBehaviour）と実装がずれる可能性。 |
| **C. 完全移行後にマップ層をやめる** | 下記「完全移行後の方針」のいずれかで、`map_transition_module_to_scene_type` / `scene_module_to_type` 自体を廃止する。 | 二重対応がなくなり設計がすっきりする。警告の原因だった「未使用節」もまとめて解消できる。   | 作業量はコンテンツ数・シーン数に比例する。                                                       |


### 3.2 完全移行後の方針（マップ層をどうするか）

以下は**検討事項**として記載する。実施する場合は別途タスク化すること。

- **現状**: Content の `scene_update` が Scenes.* に委譲し、戻り値の `module` を `map_transition_module_to_scene_type` / `scene_module_to_type` で scene_type に変換している。
- *選択肢 1: Scenes. の update が scene_type を返すようにする**  
  - 各 `Content.XXX.Scenes.`* の `update/2` の戻り値を、契約どおり **scene_type を使った形**（例: `{:transition, {:replace, :game_over, %{}}, state}`）に変更する。  
  - Content の `scene_update` は引き続き Scenes.* に委譲するが、**map_transition_module_to_scene_type は不要**になるので削除する。  
  - その結果、未使用だった「opts 付き・:pop・:push」の節も、必要なら Scenes.* 側で返すようにしてから Content 側で受け取るか、あるいは契約と実装を揃えたうえで「本当に使う節だけ」に整理できる。
- *選択肢 2: Scenes. を廃止し、実装を Content に寄せる**  
  - 各コンテンツの `scene_update(type, context, state)` の実装を、Scenes.* への委譲ではなく **Content モジュール内に直接書く**（または Content 配下の別モジュールに切り出しつつ、戻り値は最初から scene_type で返す）。  
  - 既存の `Content.XXX.Scenes.`* は削除するか、別用途に限定する。  
  - **map_transition_module_to_scene_type / scene_module_to_type は不要**になるので削除する。  
  - 二重対応がなくなり、警告の原因だった「未使用節」も一括で解消できる。
- **共通**: どちらにしても「委譲＋変換」の二重対応をやめると設計がすっきりし、`map_transition_module_to_scene_type` の未使用節に起因する警告も解消できる。

### 3.3 ドキュメント・手順との対応

- [scene-type-as-atom-implementation-procedure.md](./scene-type-as-atom-implementation-procedure.md) では、既存の `Content.XXX.Scenes.`* を「削除するか、scene_* から委譲用に残す」と記載しているが、**map_transition_module_to_scene_type や scene_module_to_type をどうするか**は明示していない。
- 本ドキュメントで、その「マップ層の扱い」と「完全移行後の方針」を検討事項として残す。実施する場合は手順書に Step を追加するか、別の実施メモを用意するとよい。

---

## 4. まとめ


| 項目        | 内容                                                                                                           |
| --------- | ------------------------------------------------------------------------------------------------------------ |
| **警告の正体** | 各 Content の `map_transition_module_to_scene_type/1` の、現状未使用の節（opts 付き・:pop・:push 等）に対する「never used」警告。       |
| **理由**    | ContentBehaviour の契約と将来の Scenes.* の変更に備え、受け取れる形を揃えているため。                                                     |
| **今後の検討** | (A) 警告許容 (B) 未使用節削除（リスクあり） (C) 完全移行後に Scenes.* を scene_type 返却に変更するか、Scenes.* を廃止して Content に寄せ、map_* を廃止する。 |
| **参照**    | scene-type-as-atom-implementation-procedure.md（Phase 4 委譲・旧モジュール削除）、本ドキュメント 3.2 節（完全移行後の方針）。                 |


