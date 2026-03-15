# contents

ゲームコンテンツ層。ContentBehaviour 実装・Component 群・シーン管理を提供。

## 責務

- **GameEvents** — メインゲームループ GenServer（contents 層）
- **SceneStack** — シーンスタック管理、SceneBehaviour コールバック
- **FrameBroadcaster** — Zenoh フレーム配信（Process.put → ZenohBridge）
- **MessagePackEncoder** — RenderFrame の MessagePack エンコード
- Component 群: LocalUserComponent, TelemetryComponent, MenuComponent 等

## コンテンツ一覧

- `VampireSurvivor` — ヴァンパイアサバイバークローン
- `AsteroidArena` — 小惑星シューター
- `SimpleBox3D`, `BulletHell3D`, `RollingBall` — 動作検証用
- `CanvasTest`, `FormulaTest` — テスト用

## データフロー

RenderComponent が DrawCommand・CameraParams・UiCanvas を組み立て、FrameBroadcaster で Zenoh へ publish。クライアント（app）が subscribe して描画。
