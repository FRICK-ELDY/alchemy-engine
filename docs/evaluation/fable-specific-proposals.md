# Fable 評価 — 提案（0点）詳細一覧

評価日: 2026-07-04 / 評価者: Fable 5（ソースベース評価、ドキュメント非参照）

現時点では存在しないため加点も減点もしないが、実装すれば将来のプラス評価につながる提案。既にマイナス点として計上した「欠陥の修正」は `fable-improvement-plan.md` 側に記載し、ここには **新規の発展方向** のみを挙げる。

---

## 連合（Federation）

- **連合アーキテクチャの二層分離ロードマップ**
  > 現在の libcluster + `:rpc` は「単一運営者のスケールアウト層」、今後作る ActivityPub/S2S は「運営者間の連合層」と役割が異なる。この二層を明確に分けて設計することを提案する。第一歩として、他インスタンスのワールド一覧を取得する read-only の S2S API（署名付き HTTP）から始めると、既存の `Network.Router` / `Network.Distributed` を壊さずに増築できる。
  > 関連ファイル: `engine/apps/network/lib/network/distributed.ex`, `engine/apps/network/lib/network/router.ex`

- **auth の OIDC プロバイダ化**
  > RS256 + JWKS という土台は既に OpenID Connect の要件に近い。`/.well-known/openid-configuration`・authorization code flow を追加すれば、auth が連合内の他インスタンスや外部ツールに対する IdP になり、インスタンス間 identity federation（訪問先インスタンスが訪問者のホーム JWKS で検証する Mastodon 型モデル）の起点になる。
  > 関連ファイル: `auth/lib/auth/token/keys.ex`, `auth/lib/auth_web/router.ex`

- **アバター・ワールドの永続リソース設計（Ash 活用）**
  > auth で実証済みの Ash リソースパターンを engine 側にも導入し、ワールド定義・アバター・フレンドグラフを永続化する。VRSNS の「ソーシャル」を成立させる最小データモデル（users↔worlds↔visits）から始めるとよい。
  > 関連ファイル: `auth/lib/auth/accounts/user.ex`（パターン参照元）

## Formula エンジン

- **StreamData によるグラフ→VM roundtrip プロパティテスト**
  > 任意の有効な FormulaGraph を生成→コンパイル→Rust VM 実行→Elixir 参照実装と結果照合、というプロパティテストを提案。Elixir/Rust のバイトコード契約を単一のテストで恒久的に守れる。engine 側の除算バグのような「型昇格の見落とし」はこの形のテストが最も効率よく検出する。
  > 関連ファイル: `engine/apps/core/lib/core/formula_graph.ex`, `engine/apps/core/test/`

- **純 Elixir Formula インタプリタ（NIF フォールバック）**
  > `Core.NifBridge.Behaviour` が既にあるので、同じ契約を満たす純 Elixir 実装を用意すれば (1) NIF ビルド不要の高速 CI、(2) Rust 実装との差分検証（differential testing）、(3) NIF ロード失敗時のフォールバックが一挙に手に入る。
  > 関連ファイル: `engine/apps/core/lib/core/nif_bridge_behaviour.ex`

- **Formula VM への制御フロー命令の追加**
  > 現在の VM は直線実行のみ（分岐・ループなし）。条件ジャンプを追加すれば ProtoFlux 級の表現力に近づく。その際は命令数上限・実行ステップ上限（gas 方式）を同時に導入し、ユーザー作成コンテンツの暴走を封じること。
  > 関連ファイル: `engine/rust/nif/src/formula/vm.rs`, `engine/rust/nif/src/formula/opcode.rs`

## クライアント体験

- **headless レンダラーを使った golden image 回帰テスト**
  > 既存の headless PNG 出力を CI に組み込み、代表シーンのレンダリング結果をピクセル比較（許容誤差付き）する。描画パイプライン変更の回帰を自動検出でき、render クレートのテスト空白を実用的に埋められる。
  > 関連ファイル: `engine/rust/client/render/src/headless.rs`

- **E2E スモークテスト（headless client + server）**
  > `mix run` でサーバを起動し、headless クライアントが接続→フレーム受信→デコード成功までを検証する統合テスト。3 トランスポートのうち最低 1 経路の疎通を CI で常時保証できる。
  > 関連ファイル: `engine/apps/network/`, `engine/rust/client/network/`

- **クライアント側予測（client-side prediction）の設計**
  > 補間（既存 `interp.rs` の配線）が済んだ後の次段として、自分の移動入力のみローカル即時反映+サーバ照合の予測を導入すると、体感遅延が大きく改善する。入力に seq が既にあるため、サーバ側の ack 付与だけで実現可能な土台がある。
  > 関連ファイル: `engine/rust/client/shared/src/interp.rs`, `engine/apps/network/lib/network/udp/protocol.ex`

## 運用・品質基盤

- **ベンチマーク基盤（benchee / criterion）**
  > フレームエンコード時間・Formula VM 実行時間・UDP encode/decode に対する継続的ベンチマークを提案。60Hz 予算（16ms）に対する各処理の消費率を数値で追跡でき、StressMonitor の警告閾値にも根拠が生まれる。
  > 関連ファイル: `engine/apps/contents/lib/contents/frame_encoder.ex`, `engine/rust/nif/`

- **PromEx / Grafana によるメトリクス外部化**
  > telemetry イベントの基盤は既にあるので、ConsoleReporter を PromEx に差し替えれば フレームレート・ルーム数・mailbox 深度をダッシュボード化できる。分散運用を目指すなら早期に入れるほど価値が高い。
  > 関連ファイル: `engine/apps/core/lib/core/telemetry.ex`

- **リプレイ・決定論テスト**
  > 入力列を記録して再実行し、同一フレーム列が得られることを検証するリプレイ基盤。デバッグ・チート検証・ネットコード検証の三役を担う。F32 演算の決定論ポリシー（クロスノード同期時）を明文化する契機にもなる。
  > 関連ファイル: `engine/apps/contents/lib/events/game.ex`

- **QUIC / WebTransport の検討**
  > UDP の信頼性層（断片化・再送・輻輳制御）を自作する代わりに QUIC datagram を採用すれば、暗号化と NAT 対応も同時に得られる。WASM 対応を本気で進める場合は WebTransport が実質必須になるため、早期の技術検証に価値がある。
  > 関連ファイル: `engine/apps/network/lib/network/udp/`

- **Zenoh ACL / TLS の有効化**
  > Zenoh ルータには ACL・mTLS 機能があるため、アプリ層の認証（RoomToken の Zenoh 経路適用）と併用してトランスポート層でも防御を重ねられる。連合公開時の前提装備。
  > 関連ファイル: `engine/apps/network/lib/network/zenoh_bridge.ex`, `engine/rust/client/network/src/platform/desktop.rs`

- **インストーラ・ランチャー・自動更新**
  > `cargo build -p app` 産物を配布可能にする層（Windows: MSIX/Inno Setup、macOS: notarized dmg）と、protobuf 契約バージョン不一致時の自動更新誘導。連合として他運営者にサーバを立ててもらう際は、サーバ側の `mix release` + systemd unit / コンテナイメージも同様に必要。
  > 関連ファイル: `engine/rust/client/app/`, `engine/mix.exs`

---

提案は以上 15 件。いずれも既存の設計（Behaviour 契約、telemetry 基盤、headless レンダラー、RS256+JWKS、seq 付き UDP）が「あと一歩」の状態まで用意されているものを優先して選定した。
