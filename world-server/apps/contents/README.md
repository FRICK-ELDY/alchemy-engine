# contents

ゲームコンテンツ層。ContentBehaviour 実装・Component 群・シーン管理を提供。

## 責務

- **GameEvents** — メインゲームループ GenServer（contents 層）
- **SceneStack** — シーンスタック管理、SceneBehaviour コールバック
- **FrameBroadcaster** — Zenoh フレーム配信（Process.put → ZenohBridge）
- **FrameEncoder** — RenderFrame の protobuf エンコード
- Component 群: LocalUserComponent, TelemetryComponent, MenuComponent 等

## コンテンツ一覧（第一級・維持）

- `CanvasTest` — Canvas / ワールド空間 UI デバッグ
- `BulletHell3D` — 3D 弾幕避け（`config/config.exs` の既定）
- `FormulaTest` — Formula / Nodes 検証（`config/formula_test.exs` で切替）

## データフロー

RenderComponent が DrawCommand・CameraParams・UiCanvas を組み立て、FrameBroadcaster で Zenoh へ publish。クライアント（app）が subscribe して描画。
