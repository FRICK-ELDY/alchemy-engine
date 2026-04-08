# 実施計画: RenderFrame / FrameEncoder / 3D パイプラインの分割（可読性優先）

> 作成日: 2026-04-08  
> ステータス: 着手前  
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

### 4.2 proto（任意・フェーズ 2）

```
proto/
  render_frame.proto            # RenderFrame, DrawCommand oneof, Camera, Ui 等の「束ね」
  render_frame/
    draw_sphere_3d.proto        # message Sphere3dCmd のみ、package 同一 alchemy.render
    draw_box_3d.proto           # message Box3dCmd のみ
    ...
```

- `package alchemy.render` を全ファイルで統一すること。
- `prost-build` の `compile_protos` に**複数ファイル**を渡すか、`render_frame.proto` のみをエントリにし中で `import`（既存 `build.rs` の方針に合わせる）。

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

### フェーズ 0: 準備

- [ ] 本書をレビューし、「FrameEncoder だけ先」「proto 分割は後」など**切り出し順**を決める。
- [ ] `Content.FrameEncoder.encode_frame/5` の公開 API・呼び出し元（`Rendering.Render` 等）を固定し、**振る舞い不変**を完了条件に書く。

### フェーズ 1: Elixir FrameEncoder 分割（最優先・リスク低）

- [ ] `frame_encoder.ex` から `command_to_pb/1` の各句を `frame_encoder/draw_commands/*.ex` へ移動。
- [ ] 中央に `command_to_pb(cmd)` → `case elem(cmd, 0)` でディスパッチ（または既存のマッチを 1 関数に集約）。
- [ ] `camera_to_pb` / `ui_to_pb` / `mesh_def_to_pb` は**第 2 段**で同様に分割可能（任意）。
- [ ] `mix compile`、既存テストがあれば実行。

### フェーズ 2: Rust デコード・3D パイプラインの委譲

- [ ] `render_frame_proto`: `draw_cmd_pb` の `match` 各枝を `draw_commands/*.rs` の関数へ（`Sphere3d(s) => sphere_3d::map(s)`）。
- [ ] `pipeline_3d`: `DrawCommand::Box3D` / `Sphere3D` の処理を既に `push_mesh_from_def` に寄せている部分を **`mod` ファイル**に移し、`render()` 内の `match` は短く保つ。
- [ ] `cargo test -p render_frame_proto -p network -p shared`（既存 CI 相当）で確認。

### フェーズ 3: proto ファイル分割（任意・コンフリクト時に効く）

- [ ] `Box3dCmd` / `Sphere3dCmd` 等を `proto/render_frame/*.proto` に移し、`render_frame.proto` で `import`。
- [ ] `rust/client/render_frame_proto/build.rs` の入力ファイル一覧を更新。
- [ ] Elixir `render_frame.pb.ex` を **protoc 再生成 or 手差し**で整合。
- [ ] **ワイヤ互換**: 既存 `render_frame_elixir_golden.bin` 等が通ることを確認。

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
