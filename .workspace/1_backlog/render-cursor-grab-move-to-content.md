# Render から cursor_grab シーン分岐を外し、コンテンツ側に寄せる

> 作成日: 2026-04-01  
> 関連コード: `apps/contents/lib/components/category/rendering/render.ex`  
> きっかけ: `Content.Tetris` のタイトルで START ボタンをクリック可能にするため、`scene_needs_cursor_release?/1` を Render から呼ぶ暫定対応が入った。

---

## 1. 現状（問題になっている点）

`Contents.Components.Category.Rendering.Render` の `resolve_cursor_grab/3` が次を行っている。

1. **`playing_state` の `cursor_grab_request`**（既存）
2. **`current_scene == content.game_over_scene()`** のとき **`:release`**（既存）
3. **`content.scene_needs_cursor_release?(current_scene)`**（Tetris 向けに追加）

**3 は汎用レンダリングコンポーネントがコンテンツ固有のオプションコールバックに依存している**ため、層の責務として不適切である。

- Render は「`build_frame` の結果をエンコードして送る」実行層に留めるべきで、**「どのシーンでカーソルを離すか」はコンテンツのポリシー**である。
- `game_over_scene()` との特別扱いも同様に、**エンジン汎用部とコンテンツ境界が混ざっている**（歴史的経緯はあるが、理想形ではない）。

---

## 2. 望ましい方向性（コンテンツ内で実装すべきもの）

**カーソルグラブの意図（`:release` / `:grab` / `:no_change`）は、各コンテンツが決め、Render はそれを解釈せずにフレームへ載せるだけにする。**

想定できる実装パターン（いずれかまたは併用。要設計確定）:

| 方針 | 概要 |
| ---- | ---- |
| A. `build_frame` の戻り値拡張 | `{commands, camera, ui}` に加え、`cursor_grab` をコンテンツが明示的に返す（Behaviour 拡張）。Render は `content` のオプション関数を増やさず、**戻り値だけ**を使う。 |
| B. シーン state 経由 | タイトル／ゲームオーバーなど UI 操作が必要なシーンの state に `cursor_grab_request: :release` を載せ、**`get_scene_state` がそのシーンを返す経路**で Render が読む（現状は `playing_scene` の state しか見ていないため、**取得元の見直しが必要**）。 |
| C. `Content` Behaviour の第一級コールバック | `cursor_grab_for_scene(scene_type, ...)` のように契約化する場合は **behaviour と全コンテンツ更新**が必要。オプションの `function_exported?` 分岐は避け、必須またはデフォルト実装で統一する。 |

**避けたいこと**: `Rendering.Render` 内で `function_exported?(content, :scene_needs_cursor_release?, 1)` のような **コンテンツごとの特別分岐の追加が続くこと**。

---

## 3. 受け入れ条件（完了の目安）

- [ ] `render.ex` から **`scene_needs_cursor_release?/1` 呼び出しを削除**している。
- [ ] タイトル／ゲームオーバー等で **マウス操作が必要なコンテンツ**（少なくとも `Content.Tetris`）が、**コンテンツ側の実装だけ**で `cursor_grab: :release` がフレームに載る。
- [ ] 可能なら **`current_scene == game_over_scene()` のハードコードも**同じ仕組みに寄せ、Render の `cond` を単純化する（別タスクに切り出してもよい）。
- [ ] `Contents.Behaviour.Content` または `build_frame` 契約に、意図が読める形で **ドキュメント化**されている。

---

## 4. 暫定で触れたファイル（リファクタ時の参照）

- `apps/contents/lib/components/category/rendering/render.ex` — `resolve_cursor_grab/3`
- `apps/contents/lib/contents/tetris.ex` — `scene_needs_cursor_release?/1`（削除対象になりうる）
- 既存: `CanvasTest` 等の `cursor_grab_request` を `playing_scene` state に載せるパターン（`render.ex` 後半の `update_by_scene_type`）

---

## 5. 次のアクション

設計方針（上記 A/B/C）を `2_todo` で具体タスク化し、Behaviour・Render・代表コンテンツ（Tetris / BulletHell3D）の順で差し替えを行う。
