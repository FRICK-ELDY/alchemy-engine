# Rust: audio — オーディオ管理

## 概要

`audio` クレートは rodio によるオーディオ再生とアセット読み込みを担当します。コマンド送信で BGM / SE の再生・停止・音量制御を行います。

---

## `audio.rs`

```mermaid
graph LR
    AC[AudioCommand enum<br/>PlayBgm / PlaySfx<br/>StopBgm / SetVolume]
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

## 関連ドキュメント

- [アーキテクチャ概要](../overview.md)
- [nif](./nif.md)
