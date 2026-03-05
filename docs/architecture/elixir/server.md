# Elixir: server — 起動プロセス

## 概要

`server` は OTP Application のエントリポイントです。Supervisor ツリーを構築し、全 GenServer を起動します。

---

## アプリケーション構成（Elixir Umbrella）

```mermaid
graph LR
    GS[server<br/>OTP Application 起動]
    GE[core<br/>SSoT コアエンジン]
    GC[contents<br/>VampireSurvivor / AsteroidArena]
    GN[network<br/>Phoenix Channels / UDP]

    GS -->|依存| GE
    GS -->|依存| GC
    GC -->|依存| GE
```

---

## `application.ex`

```mermaid
graph TD
    APP[Server.Application]
    REG[Registry<br/>Core.RoomRegistry]
    SS[Contents.SceneStack]
    IH[Core.InputHandler]
    EB[Core.EventBus]
    RS[Core.RoomSupervisor]
    GEV[Contents.GameEvents<br/>:main ルーム]
    MON[Core.StressMonitor]
    STATS[Core.Stats]
    TEL[Core.Telemetry]

    APP --> REG
    APP --> SS
    APP --> IH
    APP --> EB
    APP --> RS
    RS -->|start_room :main| GEV
    APP --> MON
    APP --> STATS
    APP --> TEL
```

起動後に `Core.RoomSupervisor.start_room(:main)` を呼び出してメインルームを開始します。

---

## 設定（`config/config.exs`）

```elixir
# 使用するコンテンツモジュールを指定する
# 例: Content.VampireSurvivor / Content.AsteroidArena / Content.SimpleBox3D /
# Content.BulletHell3D / Content.RollingBall / Content.VRTest / Content.CanvasTest
config :server, :current, Content.SimpleBox3D
config :server, :map, :plain
config :server, :game_events_module, Contents.GameEvents
```

---

## 関連ドキュメント

- [アーキテクチャ概要](../overview.md)
- [core](./core.md) / [contents](./contents.md) / [network](./network.md)
- [contents](./contents.md)
