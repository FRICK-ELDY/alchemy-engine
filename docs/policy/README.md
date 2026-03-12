# docs/policy — プロジェクト方針

プロジェクト全体で採用する技術・運用方針を記載する。

| ドキュメント | 内容 |
|:---|:---|
| [policy-as-code](../policy-as-code/index.md) | Elixir x Rust で絶対にやってはいけない事（演算・NIF・責務） |
| [zenoh-frame-serialization](../policy-as-code/why_adopted/zenoh-frame-serialization.md) | Zenoh フレーム直列化形式（Erlang term 採用） |
| [nif-desktop-separation](./nif-desktop-separation.md) | NIF と desktop の分離、Zenoh 専用 |
| [render-interpolation](./render-interpolation.md) | プレイヤー補間（2D 廃止、3D はクライアント側 render_interpolation） |
| [audio-responsibility](./audio-responsibility.md) | 音声の責務（再生=クライアント、同期=サーバー） |
| [architecture-docs-structure](./architecture-docs-structure.md) | アーキテクチャドキュメントの構成（サーバー/クライアント分割） |
| [bottleneck-prevention](./bottleneck-prevention.md) | ボトルネックの事前対策 |
