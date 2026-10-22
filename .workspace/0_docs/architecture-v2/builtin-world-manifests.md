# ビルトイン WorldManifest テストスイート（C10）

> **ステータス**: 移植仕様・DoD  
> **決定**: [diff-from-v1.md](diff-from-v1.md) §2.1 / C10  
> **作成**: 2026-10-23

---

## 方針

CanvasTest / BulletHell3D / FormulaTest は **廃止しない**。Elixir ハードコードから、host-server（shared-sim）が読む **公式ビルトイン WorldManifest / Prefab** へデータとして移植する。

| ID | 検証する能力 | 現行の所在（概略） |
|:---|:---|:---|
| `builtin.canvas_test` | UI 描画 | `Content.CanvasTest` |
| `builtin.bullet_hell_3d` | 大量エンティティ同期負荷 | `Content.BulletHell3D` |
| `builtin.formula_test` | Formula VM | `Content.FormulaTest` |

---

## 移行完了基準（DoD）

1. `alchemy-host-server` がビルトイン Manifest をロードできる
2. **BulletHell3D** と **FormulaTest** 相当が host 上で **20Hz** で進行する
3. host が RenderFrame を publish し、現行クライアントが受信・描画できる（C3）
4. world-server の NIF に新規依存を増やさない（C2）

---

## 段階

| 段階 | 内容 |
|:---|:---|
| S0（本 PR） | shared-sim / host-server スキャフォールド + 本仕様 |
| S1 | Manifest スキーマ（最小 JSON/Protobuf）と空ワールド tick |
| S2 | FormulaTest を shared-sim VM で実行 |
| S3 | BulletHell3D エンティティ負荷 |
| S4 | CanvasTest / UI 経路 |
| S5 | Elixir 第一級ハードコード記述を「ビルトイン参照」へ縮約 |
