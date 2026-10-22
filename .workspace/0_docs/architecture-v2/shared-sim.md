# shared-sim — 責務・契約

> **ステータス**: 目標責務の正本（コードはスキャフォールド段階）  
> **コード**: [`client/shared-sim/`](../../../client/shared-sim/)（client Cargo Workspace）  
> **決定**: [diff-from-v1.md](diff-from-v1.md) §2.1（C2/C4/C11・配置方針）

---

## 保証すること

| 項目 | 内容 |
|:---|:---|
| 空間ティック実行 | 台帳（Scene Manifest）範囲内で座標・物理・Formula を回す |
| 単一クレート | host-server / client 予測補間 / Web・Quest Worker で同一ソース |
| Untrusted 前提 | `is_finite` 等のサニタイズ。権利判定は持たない |
| SoA | ホットパスは Structure of Arrays |

## 保証しないこと

- アカウント・ToS・着用権・永続アセット履歴（永続 / セッション台帳 SSoT）
- Network Transport の Fan-out（Zenoh 側）
- ゲームルール・バランスのハードコード

## 含むもの（目標）

- Rapier3d 物理（C4）— 段階導入
- Formula VM（C11）— NIF から移譲
- f32 空間状態 → RenderFrame 境界用の変換ヘルパ（binary64 は host 発行経路と契約）

## 含まないもの

- Zenoh publish（host-server バイナリの責務）
- wgpu 描画
- Elixir / NIF ブリッジ
