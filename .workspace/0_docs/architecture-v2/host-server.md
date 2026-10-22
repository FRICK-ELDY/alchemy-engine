# host-server — 責務・契約

> **ステータス**: 目標責務の正本（コードはスキャフォールド段階）  
> **コード**: [`client/host-server/`](../../../client/host-server/)（client Cargo Workspace のバイナリ）  
> **決定**: [diff-from-v1.md](diff-from-v1.md) §2.1（C1/C3/C5・配置方針）

---

## 保証すること

| 項目 | 内容 |
|:---|:---|
| 空間ティック権威 | 推奨 **20Hz** で shared-sim を進行 |
| RenderFrame 発行（C3） | 組み立てた Frame を Zenoh へ **1 回** Publish |
| 入力ゲート | Room Token 検証後に入力を適用 |
| Untrusted | world-server verifier の Spot-Check / 死活監視の対象 |

## 保証しないこと

- セッション台帳・着用権の SSoT（world-server）
- クライアント描画・ウィンドウ
- 別リポジトリでのバージョン管理（禁止）

## 配置

- PC: launcher が **別プロセス**として起動（C5）。画面クローズでも維持
- Web / Quest: client 内 Worker（同一 shared-sim）
- クラウド貸し出し: 運営側 headless プール（同一バイナリ想定）

## 現行との関係

現行は Elixir `FrameEncoder` → Zenoh。移行 DoD は [builtin-world-manifests.md](builtin-world-manifests.md)。
