# 実施計画: RenderFrame / FrameEncoder / 3D パイプラインの分割（可読性優先）

> 作成日: 2026-04-08  
> ステータス: **フェーズ 3 完了**（計画した分割はすべて実施済み）  
> 方針: **実行時コストは変えず**、ソースの**見通しと変更点の局所化**を優先する。ワイヤ形式・protobuf の意味は変更しない。

---

## 1. 目的

- `apps/contents/lib/contents/frame_encoder.ex` がコマンド種類の増加で長大化するのを避け、**DrawCommand タプル → protobuf** の変換を**サブモジュールへ委譲**する。
- `proto/render_frame.proto` を必要に応じて **`import` で分割**し、**メッセージ定義の論理単位**をファイル単位で整理する（後述の制約あり）。
- Rust 側で `protobuf_render_frame.rs`・`pipeline_3d.rs`・`shared/render_frame.rs` の**実装の塊**をサブモジュールへ逃がし、中央ファイルは**短いディスパッチ**に留める。
- **非目的（本計画のスコープ外）**: `Contents.Events.Game` の `apply/3` コンポーネントディスパッチ見直し（別タスク。インシデント扱いで後追い）。

---

## 2. 制約と期待値（事前合意）

### 2.1 protobuf

- **独立した `message`（例: `Sphere3dCmd`）**は別 `.proto` に切り出し、`import` で参照できる。
- **`DrawCommand` の `oneof kind { ... }`**は言語仕様上 **1 つの `message` 定義内**にまとまる。**新コマンド追加時は、その `message` にフィールドを 1 行足す**必要が残る。「proto ファイルを増やすだけで oneof が自動拡張」は**標準 proto3 では不可**。
- ワイヤ上のバイト列は、分割の有無で**変わらない**（同一スキーマなら）。

### 2.2 Rust `DrawCommand` enum

- `shared::render_frame::DrawCommand` は **enum のためバリアント宣言は 1 箇所に集約**される。分割しても**新バリアント 1 行**は中央に残る。
- デコード・描画の**本体ロジック**は別ファイルへ移し、中央は **`Variant => submodule::from_pb(...)` 程度の 1 行**を目指す。

### 2.3 Elixir `FrameEncoder`

- `defp command_to_pb/1` の**関数句はモジュールをまたげない**。中央モジュールに **`case elem(cmd, 0)` またはマクロ生成**のいずれかが必要。
- 推奨: **タグ（アトム）で `case` し、各枝で `Encoder.DrawCommands.Box.to_pb/1` 等を呼ぶ**（枝はコマンド数に比例して増えるが、各行は短い）。

### 2.4 `render_frame.pb.ex`

- 現状は `apps/network/lib/network/proto/generated/render_frame.pb.ex` を**手メンテ**している運用があり得る。proto 分割後も **prost / protoc_gen_elixir の出力と手元の差分管理方針**をタスク内で明示する（「再生成手順を README に書く」「CI で drift 検知」等）。

---

## 3. スコープ一覧

| 領域 | やること | やらないこと |
|------|----------|--------------|
| Elixir FrameEncoder | ルータ + `Content.FrameEncoder.DrawCommands.*`（または `...Encoder.Frame.*`）への委譲 | タプル契約の変更、新 DrawCommand の追加（本計画は**構造整理のみ**でも可） |
| proto | `messages/*.proto` 等への分割 + `render_frame.proto` から `import` | oneof の完全自動拡張 |
| Rust shared | enum は 1 ファイル維持、doc の整理 | enum の廃止・Any 化 |
| Rust render_frame_proto | `draw_cmd_pb` をコマンド別ファイルへ分割委譲 | デコード方針（緩いデコード）の変更 |
| Rust pipeline_3d | `Sphere3D` / `Box3D` 等を `draw_commands/` サブモジュールへ | 描画アルゴリズムの変更 |
| Rust render mod | `sprite_instance_from_command` 等の列挙は現状維持、必要ならコメントのみ | 大規模リファクタ |
| テスト | 既存 golden / `mix compile` / `cargo test` 相当で回帰確認 | 新 golden の大量追加（不要ならしない） |
| Game の `apply/3` | **触らない** | 本書では追記のみ |

---

## 4. 提案ディレクトリ構成（案）

### 4.1 Elixir

```
apps/contents/lib/contents/
  frame_encoder.ex              # encode_frame/5 とルーティングのみ（公開 API 不変）
  frame_encoder/
    draw_commands/
      box_3d.ex                 # {:box_3d, ...} -> %Alchemy.Render.DrawCommand{}
      sphere_3d.ex
      grid_plane.ex
      ...                       # 既存 command_to_pb 句を順次移動
    # 任意: camera.ex, ui.ex, mesh_def.ex（段階的に）
```

- 各サブモジュールは **`@doc false`** または短い moduledoc で「FrameEncoder 専用」と明記。
- **命名**: `Content.FrameEncoder.DrawCommands.Sphere3d` のように protobuf 名と揃えると追いやすい。

### 4.2 proto（フェーズ 3 で実施済み）

```
proto/
  render_frame.proto            # RenderFrameEnvelope, RenderFrame + import のみ
  render_frame/
    cursor_grab.proto           # CursorGrabKind
    mesh.proto                  # MeshVertex, MeshDef
    camera.proto                # CameraParams, Camera2d, Camera3d
    ui.proto                    # UiCanvas … UiScreenFlash
    draw_commands.proto         # DrawCommand oneof + 各 Draw 用 message（import mesh）
```

- 全ファイル `package alchemy.render`。
- `prost-build`: エントリは `render_frame.proto` のみ、`import` で断片を解決。

### 4.3 Rust（render クレート例）

```
rust/client/render/src/renderer/
  pipeline_3d.rs                # render() の骨格 + ループ、細部は mod に委譲
  pipeline_3d/
    mesh_from_def.rs            # push_mesh_from_def 等（既存の抽出先）
    draw_box_3d.rs
    draw_sphere_3d.rs
```

```
rust/client/render_frame_proto/src/
  protobuf_render_frame.rs      # pb_into_render_frame, draw_cmd_pb の骨格
  draw_commands/
    sphere_3d.rs                # Sphere3d(s) => DrawCommand::Sphere3D { ... }
```

（実際のファイル名はチームの命名規則に合わせて調整可。）

---

## 5. 実施フェーズ

### フェーズ 0: 準備（完了）

- [x] 本書をレビューし、「FrameEncoder だけ先」「proto 分割は後」など**切り出し順**を決める。
- [x] `Content.FrameEncoder.encode_frame/5` の公開 API・呼び出し元（`Rendering.Render` 等）を固定し、**振る舞い不変**を完了条件に書く。

#### フェーズ 0 で確定したこと

**切り出し順（この順で実施する）**

1. **フェーズ 1** — Elixir `Content.FrameEncoder`（`command_to_pb` のサブモジュール化）を**最優先**。
2. **フェーズ 2** — Rust `render_frame_proto` / `pipeline_3d` の委譲。
3. **フェーズ 3** — `proto` の `import` 分割は**任意・最後**（コンフリクトやレビュー負荷が効くときに実施）。

**`encode_frame/5` の公開契約（リファクタ中も変更しない）**

| 項目 | 内容 |
|------|------|
| 定義 | `Content.FrameEncoder.encode_frame(commands, camera, ui, mesh_definitions, cursor_grab \\ nil)` |
| 戻り値 | `binary()` — `Alchemy.Render.RenderFrame` の protobuf エンコード結果 |
| `cursor_grab` | `:grab` \| `:release` \| `:no_change` \| `nil`（省略時はフィールド未設定扱い） |
| タプル形式 | `commands` / `camera` / `ui` の各要素は [draw-command-spec.md](../../docs/architecture/draw-command-spec.md) および本モジュールの `command_to_pb` 句と一致させる |

**実行時の呼び出し元（調査日: 2026-04-08）**

- **唯一の本番経路**: `Contents.Components.Category.Rendering.Render.on_nif_sync/1` が `Content.FrameEncoder.encode_frame(commands, camera, ui, mesh_definitions, cursor_grab)` を呼ぶ。
- **その他**: `Contents.Behaviour.Content` の moduledoc が `encode_frame/4` 形式の戻り値について言及するのみ（コード呼び出しなし）。
- **別 API**: `Content.FrameEncoder.encode_injection_map/1` は `Contents.Events.Game` から使用。**フェーズ 1 の分割対象は主に `encode_frame` 経路**とし、`encode_injection_map` は同ファイルに残すか、必要になったら別計画で切り出す。

**振る舞い不変の検証**

- 同一の `{commands, camera, ui, mesh_definitions, cursor_grab}` に対する出力バイナリは、分割前後で**一致すること**（`rust/client/network/tests/fixtures/render_frame_elixir_golden.bin` 等の既存契約テストで担保）。

### フェーズ 1: Elixir FrameEncoder 分割（完了）

- [x] `frame_encoder.ex` から `command_to_pb/1` の各句を `frame_encoder/draw_commands/*.ex` へ移動。
- [x] 中央は **タプル先頭タグ＋アリティに合わせた `defp command_to_pb/1` 1 行委譲**（`case elem(cmd, 0)` より未知コマンドの `ArgumentError` 挙動を保ちやすい）。
- [x] 共有数値ヘルパーは `Content.FrameEncoder.Proto` に集約（`camera_to_pb` / `ui_to_pb` / `mesh_def_to_pb` / injection から利用）。
- [ ] `camera_to_pb` / `ui_to_pb` / `mesh_def_to_pb` のファイル分割は**第 2 段**（任意）。
- [x] `mix compile` 確認済み。

### フェーズ 2: Rust デコード・3D パイプラインの委譲（完了）

- [x] `render_frame_proto`: `protobuf_render_frame.rs` を `protobuf_render_frame/` に分割。`draw_command.rs` に `DrawCommand` oneof の `match`、`float_helpers.rs` に `f2`/`f3`/`f4`/`pad4`、`mesh_helpers.rs` に `MeshVertex`/`MeshDef` 変換。
- [x] `pipeline_3d`: `pipeline_3d.rs` を `pipeline_3d/mod.rs` に移し、`mesh_template.rs`（`box_mesh` / `push_mesh_from_def` / `grid_lines` / `skybox_verts`）、`mesh_accumulate.rs`（グリッド・Box3D・Sphere3D のスクラッチ蓄積）へ分離。`include_str!` は `../shaders/mesh.wgsl` に変更。
- [x] `shared::render_frame::DrawCommand` enum は**未変更**（計画どおり中央集約）。
- [x] `cargo test -p render_frame_proto -p network -p shared -p render` で確認済み。

### フェーズ 3: proto ファイル分割（完了）

- [x] `proto/render_frame.proto` をエントリにし、`proto/render_frame/` 配下へ分割:
  - `cursor_grab.proto`, `mesh.proto`, `camera.proto`, `ui.proto`, `draw_commands.proto`（`DrawCommand` oneof 含む。`mesh.proto` を import）。
- [x] `rust/client/render_frame_proto/build.rs` — エントリは `render_frame.proto` のみ、`cargo:rerun-if-changed` に各断片を列挙。
- [x] Elixir `render_frame.pb.ex` — **ワイヤ・型名は不変のため変更なし**（手メンテ運用のまま）。
- [x] **ワイヤ互換**: `cargo test -p render_frame_proto -p network`（golden `render_frame_elixir_golden.bin`）通過済み。

### フェーズ 4（別タスク・本書では記録のみ）

- [ ] `Contents.Events.Game` の `dispatch_to_components/2` における **`apply/3` の見直し**（静的ディスパッチ、コールバック登録の最適化、計測）。本計画の完了条件に**含めない**。

---

## 6. 完了条件（Definition of Done）

- [ ] `Content.FrameEncoder.encode_frame/5` のシグネチャと意味が変わらない。
- [ ] 既存の protobuf デコードテスト・golden（該当するもの）が通る。
- [ ] 新規 DrawCommand を追加する手順が、本書または `docs/architecture/draw-command-spec.md` から**たどれる**（「中央に 1 行 + 新ファイル 1 つ」程度のチェックリスト）。

---

## 7. 参照

- `docs/architecture/draw-command-spec.md`
- `proto/render_frame.proto`
- `apps/contents/lib/contents/frame_encoder.ex`
- `rust/client/render_frame_proto/build.rs`
- `rust/client/render/src/renderer/pipeline_3d.rs`

---

## 8. 変更履歴

| 日付 | 内容 |
|------|------|
| 2026-04-08 | 初版作成 |
| 2026-04-08 | フェーズ 0 完了: 切り出し順の確定、`encode_frame/5` 契約・呼び出し元の記録 |
| 2026-04-08 | フェーズ 1 完了: `frame_encoder/draw_commands/*.ex` + `frame_encoder/proto.ex`、本体内は `command_to_pb` 委譲のみ |
| 2026-04-08 | フェーズ 2 完了: `render_frame_proto` の `protobuf_render_frame/` 分割、`render` の `pipeline_3d/` 分割 |
| 2026-04-08 | フェーズ 3 完了: `proto/render_frame/*.proto` に分割、`build.rs` の rerun 依存を更新 |
