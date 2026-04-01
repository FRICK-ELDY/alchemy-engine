# Rust: audio — オーディオ管理

> **2026-04**: `native/nif` は **`audio` に依存しない**（Formula NIF のみ）。本クレートは主に **クライアント `app`** 等から利用。

## 概要

`audio` クレートは **rodio** によるオーディオ再生とアセット読み込みを担当します。SuperCollider 風のコマンド駆動オーディオスレッドで、BGM / SE の再生・一時停止・再開・音量制御を行います。

- **パス**: `native/audio/`
- **依存**: rodio

---

## `audio.rs`

```mermaid
graph LR
    AC[AudioCommand enum<br/>PlayBgm / PauseBgm / ResumeBgm<br/>SetBgmVolume / PlaySe / Shutdown]
    ACS[AudioCommandSender]
    AT[オーディオスレッド<br/>コマンドループ]
    AM[AudioManager<br/>bgm_sink + OutputStream]

    ACS -->|send| AT
    AT --> AM
    AC -->|経由| ACS
```

---

## `asset/mod.rs` — アセット管理

```mermaid
flowchart LR
    REQ[アセット要求]
    P1["1. ゲーム別パス\nassets/{game_name}/..."]
    P2["2. ベースパス\nassets/..."]
    P3["3. カレントディレクトリ"]
    P4["4. コンパイル時埋め込み\ninclude_bytes!"]
    RES[アセット返却]

    REQ --> P1
    P1 -->|見つからない| P2
    P2 -->|見つからない| P3
    P3 -->|見つからない| P4
    P1 & P2 & P3 & P4 -->|見つかった| RES
```

---

## AudioCommand 一覧

| コマンド | 説明 |
|:---|:---|
| `PlayBgm` | BGM 再生 |
| `PauseBgm` | BGM 一時停止 |
| `ResumeBgm` | BGM 再開 |
| `SetBgmVolume(f32)` | BGM 音量 |
| `PlaySe(AssetId)` | SE 再生 |
| `PlaySeWithVolume(AssetId, f32)` | 音量指定で SE 再生 |
| `Shutdown` | オーディオスレッド終了 |

---

## 関連ドキュメント

- [アーキテクチャ概要](../../overview.md)
- [nif](../nif.md)
