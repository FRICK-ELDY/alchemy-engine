# 提案（0点）統合一覧 — 2026-08-25

評価日: 2026-08-25
検証対象コミット: engine `8f35a57`（PR #347 マージ後）
統合元: `opus/opus-specific-proposals-2026-08-25.md`（16 件） / `gpt/gpt-specific-proposals-2026-08-25.md`（19 件）

現時点では存在しないため加点も減点もしないが、実装すればプロジェクトの価値を高める提案。既にマイナス点として計上した「欠陥の修正」は `workspace/0_reference/improvement-plan.md` 側に記載し、ここには **新規の発展方向** のみを挙げる。

各項目には出典を付す。

| 出典 | 意味 |
|:---|:---|
| **両者** | 両評価者が独立に同じ提案に到達したもの（優先度が高い信号として扱う） |
| **Opus** / **GPT** | 一方の評価者のみが挙げたもの |
| **統合時追加** | どちらの提案文書にもないが、両者のマイナス点・プラス点から統合時に導出したもの |

## 採点基準

| 点数 | 基準 |
|:---:|:---|
| 0 | 現時点では存在しないが、実装すればプロジェクトの価値を高める提案 |

---

## 連合（Federation）

### 次のフェーズ

- **訪問トークン（インスタンス間ゲスト入場）** `0` — **GPT**
  > read-only S2S でメタデータ交換の入口ができた今、連合の次の一歩は「他インスタンスのユーザーが自分のワールドに入れる」ことである。`Network.S2S.Instance` は既に短命 JWT の署名と peer の JWKS 取得・検証の両方向を持ち、`Network.AuthVerifier` は kid ミス時の JWKS 再取得まで実装済み。必要なのは「訪問者の home instance が発行した JWT を、訪問先が home の JWKS で検証して RoomToken を発行する」1 経路だけで、部品はすべて揃っている。Mastodon 型の identity federation モデルをそのまま適用できる。GPT は署名付き visit grant と guest identity という形でこれを提案した。Opus は同じ領域について「まず見えるところまで」（下記ディレクトリ機能）を 1 段前に置いており、**2 人の提案は連合ロードマップの連続する 2 ステップとして読める**。
  > 関連ファイル: `engine/apps/network/lib/network/s2s/instance.ex`, `engine/apps/network/lib/network/auth_verifier.ex`, `engine/apps/network/lib/network/room_token.ex`

- **`.well-known` からの相互発見とインスタンスディレクトリ** `0` — **Opus**
  > S2S は自己記述（`GET /.well-known/alchemy-s2s.json`）と署名付き worlds カタログまで到達した（`apps/network/lib/network/s2s/instance.ex:1-16`）。次の段として、既知インスタンスのリストを設定で持ち、定期的に `Client.fetch_worlds` して結果をキャッシュする「ディレクトリ」機能を置くと、ユーザーから見て初めて連合が体験になる（他インスタンスのワールドが一覧に並ぶ）。訪問トークンによる実際の入室はその次で、まず「見える」ところまでを 1 段として切ると、連合の価値を早く検証できる。認証設計を伴わないため、上記の訪問トークンより実装コストが小さい。
  > 関連ファイル: `engine/apps/network/lib/network/s2s/client.ex`, `engine/apps/network/lib/network/s2s/catalog.ex`

- **auth の OIDC プロバイダ化（discovery + PKCE）** `0` — **GPT**
  > RS256 + JWKS + refresh ローテーションという土台は既に OpenID Connect の要件に近い。`/.well-known/openid-configuration` と authorization code flow + PKCE を追加すれば、auth が連合内の他インスタンスや外部ツール（launcher / web）に対する標準 IdP になる。訪問トークンを独自形式で作る前に OIDC に寄せておくと、後から外部の VRSNS / SNS と繋ぐときの変換コストがゼロになる。engine と assets という自前の検証者が 2 つ動いた今、標準に寄せる判断の見返りが読みやすくなった。
  > 関連ファイル: `auth/lib/auth/token/keys.ex`, `auth/lib/auth_web/router.ex`

- **ActivityPub によるソーシャルグラフの連合** `0` — **統合時追加**
  > 訪問トークンが「入場」の連合なら、ActivityPub は「関係」の連合である。フレンド・フォロー・ワールド公開通知を `Follow` / `Create` / `Announce` アクティビティとして表現すれば、既存の Fediverse クライアントから AlchemyEngine インスタンスのワールド更新を購読できる。`.well-known` の自己記述と RSA 署名の基盤は S2S で作ったものを再利用できるため、追加コストは actor エンドポイントと inbox/outbox に絞られる。両評価者の提案文書にはないが、S2S の実装済み範囲（自己記述 + RS256 署名）から素直に伸ばせる方向として挙げる。
  > 関連ファイル: `engine/apps/network/lib/network/s2s/instance.ex`, `engine/apps/network/lib/network/router.ex`

---

## 永続化・データモデル

### assets を実際に使う

- **engine ↔ assets の往復を 1 経路通す（`__save__` / `__load__`）** `0` — **GPT**
  > マイナス点として計上した「配線の不在」の裏返しだが、提案として書くべき発展がある。`assets` は所有権・パスポリシー・サイズ上限まで揃った状態で待っており、保存パス（`users/{sub}/private/Save/{content_id}/save.{slot}`）と JSON スキーマも定義済み。ここに Tetris または BulletHell3D のハイスコア 1 スロットだけを `schema_version` 付き JSON で往復させると、(1) engine → assets の HTTP クライアント、(2) ユーザー JWT の代理送出（README のパターン A）、(3) セーブ／ロードの UI アクションという 3 つの型が同時に決まる。以降のワールド定義・アバターは同じ型の反復になるため、最初の 1 経路の価値が最も高い。
  > 関連ファイル: `engine/apps/contents/lib/events/game.ex`, `assets/lib/assets_web/controllers/object_controller.ex`

- **BLOB / メタデータの saga + 整合リコンサイラ** `0` — **GPT**
  > `Assets.Objects` はファイル操作と Ash アクションをまたいでロールバックできない（マイナス点として計上）。提案としての形は、temp ファイルへ書く → メタデータをコミット → atomic rename、という順序に整え、加えて孤児 BLOB とメタデータ不整合を照合する reconciler を定期実行することである。BLOB ストアと RDB を併用するサービスでは避けられない設計課題で、早い段階で型を決めておくほど安い。
  > 関連ファイル: `assets/lib/assets/objects.ex`

- **アバター・ワールドの永続リソース設計（所有モデル）** `0` — **GPT**
  > BLOB は `assets` に置く道筋が立ったので、次はメタデータ側のリレーションである。auth で実証済みの Ash リソースパターンを使い、`users ↔ worlds ↔ visits` の最小データモデルを設計する。GPT はここに owner instance / revision / content hash / moderation status を持たせるべきと指摘しており、連合を前提にするならこの 4 つは後付けが難しいため最初から入れる価値がある。「誰がどのワールドをいつ訪れたか」が記録されるだけで、VRSNS の「ソーシャル」に必要な導線（フレンドのいるワールドへ飛ぶ、訪問履歴から戻る）が成立する。
  > 関連ファイル: `auth/lib/auth/accounts/user.ex`（パターン参照元）, `engine/apps/network/lib/network/s2s/catalog.ex`

- **assets の署名付き URL とキャッシュ配信** `0` — **Opus**
  > 現在 BLOB は `GET /api/v1/objects/*path` が毎回 Bearer 検証を通して本体を返す形で（`assets/lib/assets_web/controllers/object_controller.ex:34-115`）、アバターやワールドのメッシュのように「サイズが大きく変更頻度が低い」データには不向きである。短命な署名付き URL を発行して本体配信は CDN / 静的サーバに任せる形にすると、認証の負荷とレイテンシを同時に下げられ、`ETag` / `Cache-Control` による差分取得も効く。`AssetMetadata` に `byte_size` / `content_type` / `uri` が既にあるので（`assets/lib/assets/inventory/asset_metadata.ex:16-66`）、必要なのは署名の発行と検証だけである。
  > 関連ファイル: `assets/lib/assets_web/controllers/object_controller.ex`

---

## Formula エンジン

### 安全性

- **Formula VM の gas 方式実行上限 + capability サンドボックス（制御フロー命令の前提）** `0` — **両者**
  > 現在の VM は直線実行のみ（分岐・ループなし、OpCode は算術・比較・入出力・Store の 14 種）で、命令数・入力量・store 量の上限がない。条件ジャンプを追加すれば ProtoFlux 級の表現力に近づくが、順序が重要で、**命令数上限・実行ステップ上限（gas 方式）・`DirtyCpu` 指定・store キーの権限分離を先に入れてから**制御フローを足すこと。ループのない今は「巨大バイトコードでスケジューラを占有できる」程度の問題だが、ループが入った瞬間に「1 命令で無限ループ」が可能になり、ユーザー作成コンテンツを実行する VM としては致命的になる。参考: EVM の gas、Lua の instruction hook、wasmtime の fuel。
  > 関連ファイル: `engine/rust/nif/src/formula/vm.rs`, `engine/rust/nif/src/formula/opcode.rs`, `engine/rust/nif/src/nif/formula_nif.rs`

### 検証

- **純 Elixir 参照 VM による differential / プロパティテスト** `0` — **両者**
  > `Core.NifBridge.Behaviour` が既にあるので、同じ契約を満たす純 Elixir 実装を用意すれば (1) NIF ビルド不要の高速 CI、(2) Rust 実装との差分検証、(3) NIF ロード失敗時のフォールバックが一挙に手に入る。さらに StreamData / proptest で「任意の有効な `FormulaGraph` を生成 → コンパイル → Rust VM 実行 → Elixir 参照実装と照合」を回せば、今回の除算バグ（型昇格の見落ち）と同型の欠陥を恒久的に検出できる。修正と 6 テストで当該バグは固定されたが、同型の見落ちが他の opcode に潜んでいないことは保証されていない。Behaviour が死んだ抽象になっている問題（マイナス -2）の最も価値のある解消方法でもある。参考: WebAssembly の spec interpreter、SQLite の SQL Logic Test。
  > 関連ファイル: `engine/apps/core/lib/core/nif_bridge_behaviour.ex`, `engine/apps/core/lib/core/formula_graph.ex`, `engine/rust/nif/src/formula/vm.rs`

### 編集手段

- **ノードグラフのビジュアルエディタ** `0` — **Opus**
  > `Core.FormulaGraph` がグラフ → バイトコードのコンパイラを持ち（`apps/core/lib/core/formula_graph.ex:139,198-200`）、`nodes/` に 20 種のノード実装がある。一方でグラフを組む手段はコードのみで、ビジュアル編集はない。クライアントには egui ベースの `system_ui` クレート（1237 行、16 テスト）があるので、ノードエディタを載せる土台はすでに手元にある。実装イメージ: `egui_snarl` などのノードエディタ crate でグラフを編集し、JSON として `assets` サービスに保存、engine 側が `FormulaGraph` に流す。「A platform for worlds. You bring the rules.」という看板に対して、ルールを持ち込む手段が GUI で存在することの意味は大きい。
  > 関連ファイル: `engine/apps/core/lib/core/formula_graph.ex`, `engine/rust/client/system_ui/`

---

## コンテンツ・ゲームプレイ

### prototype から作品へ

- **BulletHell3D を「15 分遊べる 1 作品」まで磨く** `0` — **GPT**
  > wave 構成・ボス・アイテム・ビルド（成長選択）・メタ進行、専用アセット、セーブを追加する。マイナス点として計上したゲームプレイ完成度への最短の応答であり、設計上の障害はなく物量の問題である。エンジンのパラメータ外部化（`FormulaStore` / コンポーネント注入）が既にあるため、追加する要素の大半はデータで表現できる。
  > 関連ファイル: `engine/apps/contents/lib/contents/bullet_hell_3d/playing.ex`

- **コンテンツパッケージ manifest** `0` — **GPT**
  > engine バージョン・proto バージョン・アセットハッシュ・要求パーミッションをロード前に検証する manifest。`ContentLoader` が現状スタブである以上、descriptor 実行系を実装するときに同時に決めておくべき契約である。連合で他インスタンスのコンテンツを読み込む将来像では必須装備になる。
  > 関連ファイル: `engine/apps/contents/lib/behaviour/content.ex`, `engine/apps/contents/lib/contents/content_loader.ex`

- **コンテンツの外部化とホットリロード** `0` — **Opus**
  > 現在コンテンツは umbrella 内の `apps/contents/lib/contents/` にコンパイル時に同居し、切り替えは `config :server, :current` の再起動を伴う（`config/config.exs:90`）。コンテンツ交換可能性は 5 実装で実証済みなので（プラス点参照）、次は「エンジンをビルドせずにコンテンツを差し込める」段に進める価値がある。Elixir なら別 OTP アプリとして動的ロードする、あるいは `Contents.Behaviour.Content` を満たすモジュールを実行時にコード読み込みする形が取れる。開発中のイテレーション速度が直接上がるほか、「他人が作ったワールドを自分のインスタンスに置く」という連合構想の前提にもなる。上記の manifest と同じタスクの表裏である。
  > 関連ファイル: `engine/apps/contents/lib/behaviour/content.ex`

- **ゲーム別アセットパイプライン** `0` — **GPT**
  > 現状は audio 6 件 + atlas 1 件で、ゲーム別ディレクトリは `.gitkeep` のみ。ソース・ライセンス・atlas manifest を持つ再現可能な生成・パッケージングに置き換える。アセットが増える前に型を決めておくほど安く、`assets` サービスの BLOB 管理とも接続できる。
  > 関連ファイル: `engine/assets/`, `engine/apps/contents/lib/contents/frame_encoder.ex`

- **`Content.*` / `Contents.*` 命名規約の明文化** `0` — **統合時追加**
  > PR #340 でゲームコンテンツ本体を `Content.*`（14 モジュール）、エンジン側インフラ・コンポーネントを `Contents.*`（112 モジュール）とする分離が確立し、前回の「命名の不統一（-1）」は規約として撤回した。ただしこの規約はコード上の慣行としてしか存在せず、どこにも書かれていない。新しいモジュールを足す人間が同じ判断を再現できるよう、`docs/architecture/` または `Contents.Behaviour.Content` の moduledoc に 3 行書いておくとよい。規約は明文化された時点で初めてレビュー可能になる。Opus のマイナス点撤回の副産物として挙げる。
  > 関連ファイル: `engine/apps/contents/lib/behaviour/content.ex`, `engine/docs/architecture/`

---

## クライアント体験

### ネットコード

- **クライアント側予測（予測 → 照合 → ロールバックの段階導入）** `0` — **Opus**
  > 補間が完成した今、次段はこれである。自分の移動入力のみローカル即時反映 + サーバ照合で、体感遅延が大きく改善する。`SnapshotInterpolator` が遅延バッファを 80〜250ms で適応制御している以上、自機の反応にもその分の遅延が乗っているため、補間の完成度が高いほど「滑らかだが重い」というギャップが目立つ。入力に `seq` が既にあるので、第 1 段は「サーバが `seq` を反射し、乖離が閾値を超えたときだけ位置を補正する」だけで成立する。第 2 段の「ロールバック + 再シミュレーション」は決定論的リプレイ基盤（下記）と同じ仕組みを必要とするため、別タスクとして順序づけておく。`predict.rs` のスケルトンを本実装にする形になる。
  > 関連ファイル: `engine/rust/client/shared/src/predict.rs`, `engine/apps/network/lib/network/udp/protocol.ex`

- **安定エンティティ ID による補間対応付け** `0` — **GPT**
  > `SnapshotInterpolator` の現在の対応付けは最近傍探索で、密集した弾幕では誤対応と O(n²) が同時に起きる（マイナス点として計上）。`entity_id` をワイヤに乗せて HashMap join に置き換えれば、両方が同時に解消する。補間の実装品質が高い（プラス +5）だけに、対応付けだけが弱点として残っている状態である。
  > 関連ファイル: `engine/rust/client/shared/src/interp.rs`, `engine/apps/contents/lib/contents/frame_encoder.ex`

- **RenderFrame の差分送信と AOI（Area of Interest）** `0` — **Opus**
  > 現在は毎 tick フル `RenderFrame` を送っている。「1000 人規模のプレイヤーが交差する大規模ネットワーク」（`README.md:46`）を目標に置くなら、送信量は参加者数 × エンティティ数で二乗的に伸びるため、どこかで差分化と関心領域の絞り込みが必要になる。順序としては AOI（各クライアントの視界・距離でエンティティを選別）が先で、これはサーバが DrawCommand を生成している現構造（`apps/contents/lib/contents/frame_encoder.ex:37-48`）ならクライアント改修なしに導入できる。差分化はその後、`seq` を使った ack ベースのベースライン管理として載せる。参考: Overwatch の GDC 講演、Source Engine の snapshot delta。
  > 関連ファイル: `engine/apps/contents/lib/contents/frame_encoder.ex`

- **補間の内部状態を telemetry / デバッグ HUD に出す** `0` — **統合時追加**
  > `SnapshotInterpolator` は適応遅延（80〜250ms）、観測間隔 EMA、キュー枚数、playback-ahead クランプの発動という、体験品質を直接説明する数値を内部に持っている。これを telemetry イベントとデバッグ HUD に出せば、ユーザーが「重い」「飛ぶ」と言ったときに「遅延が 240ms に張り付いている」「キューが 1 枚しかない」と即答できる。ネットコードのチューニングは実測値なしでは進まないため、実装の次に来るべき投資である。両者が独立に高評価した実装（+5）と、両者が独立に指摘した可観測性の乖離を突き合わせて導出した。
  > 関連ファイル: `engine/rust/client/shared/src/interp.rs`, `engine/rust/client/system_ui/src/`

- **QUIC / WebTransport の検討** `0` — **両者**
  > UDP の信頼性層（断片化・再送・輻輳制御）を自作する代わりに QUIC datagram（RFC 9221）を採用すれば、暗号化とパス検証も同時に得られる。今回 UDP に認証・セッション淘汰・zlib 上限を足したが、パケットサイズ上限・レート制限・断片化はまだ残っている。これらを一つずつ自作する前に、QUIC に載せ替えた場合のコストと比較する価値がある。WASM 対応を本気で進める場合は WebTransport が実質必須になるため、`platform/web.rs` のスタブを本実装にする道筋としても効く。実装イメージ: Elixir 側は `quicer`、Rust 側は `quinn`。まず既存 UDP と並列に 1 経路として足し、比較してから寄せる。
  > 関連ファイル: `engine/apps/network/lib/network/udp/`, `engine/rust/client/network/src/platform/web.rs`

### 描画・XR

- **headless レンダラーによる golden image 回帰テスト（マトリクス化）** `0` — **GPT**
  > 既存の headless PNG 出力を CI に組み込み、代表シーン（2D / 3D / UI）のレンダリング結果をピクセル比較（許容誤差付き）する。描画パイプライン変更の回帰を自動検出でき、render クレートのテスト空白（マイナス -2）を実用的に埋められる。最初の 1 本は PNG のハッシュ比較でも十分で、そこから許容誤差付き比較・代表シーンのマトリクスへ育てられる。
  > 関連ファイル: `engine/rust/client/render/src/headless.rs`

- **OpenXR conformance スモークテスト** `0` — **GPT**
  > ダミーランタイムで READY → pose / button 取得 → ネットワークエンコードまでを CI で検証する。OpenXR ループ本体は 296 行の実装がありながら app に未配線（マイナス -4）で、配線するときに「動いていることをどう確認するか」が先に必要になる。`XR_MND_headless` 前提という現在の制約は、そのまま CI 向けの利点として使える。
  > 関連ファイル: `engine/rust/client/xr/src/openxr_loop.rs`

- **サーバ側フラスタムカリングと LOD** `0` — **Opus**
  > DrawCommand をサーバが生成している構造（`apps/contents/lib/contents/frame_encoder.ex:37-48`）は、カリングをサーバ側で行えるという他エンジンにない利点を持つ。クライアント側で捨てる前に送らない判断ができるため、GPU 負荷と帯域の両方が同時に下がる。カメラパラメータはすでに `CameraParams` として送信対象に含まれているので、サーバはクライアントごとの視錐台を知る手段を持っている。距離による LOD（遠方の `Box3D` を簡略メッシュに置換）も同じ判定点に載せられる。上記 AOI と同じ場所に入る改修である。
  > 関連ファイル: `engine/apps/contents/lib/contents/frame_encoder.ex`

- **入力抽象の統合（`XrInputEvent` と `KeyState` / `MouseMotion`）** `0` — **Opus**
  > デスクトップ入力は `window` クレートで `KeyState` などに正規化され（`rust/client/window/src/desktop_loop.rs:193-198`）、XR 入力は `xr` クレートの `XrInputEvent`（HeadPose / ControllerPose / ControllerButton / TrackerPose）として別系統で定義されている（`rust/client/xr/src/lib.rs:1-101`）。この 2 つを 1 つの入力イベント型に束ねてから `RenderBridge` に渡す層を挟むと、XR を app に配線する際にサーバ側プロトコルを触らずに済み、ゲームパッド追加時も同じ場所で済む。実装が両系統とも小さい今のうちに型を統合しておくほど安い。
  > 関連ファイル: `engine/rust/client/xr/src/lib.rs`, `engine/rust/client/window/src/desktop_loop.rs`

---

## 運用・品質基盤

### 回帰検出

- **E2E スモークテスト（headless client + server）** `0` — **両者**
  > `mix run` でサーバを起動し、headless クライアントが接続 → フレーム受信 → デコード成功までを検証する統合テスト。現在のテストは Elixir 180 件・Rust 58 件がすべてプロセス内で完結しており、実行時構成の破綻（Zenoh キーの不一致、protobuf のフィールド番号ずれ、`ASSETS_ID` の未設定）は単体テストをすべて通り抜ける。`mix alchemy.router` で zenohd を起動でき headless 描画もあるため部品は揃っており、CI ジョブは 5 分以内に収まる。GPT はこれを「seed 付き入力で title → play → game over → retry を通し、score / frame hash / audio を検証する headless gameplay シナリオテスト」まで具体化しており、そこまで行くとゲームプレイ完成度の回帰も同時に守れる。
  > 関連ファイル: `engine/rust/client/render/src/headless.rs`, `engine/apps/core/lib/mix/tasks/alchemy.router.ex`, `engine/apps/contents/test/`

- **決定論リプレイ + 通信劣化下の回帰テスト** `0` — **両者**
  > 権威 tick が Elixir、入力が `{:move_input, ...}` / `{:ui_action, ...}` に正規化済み、ゲームロジックが dt ベースという 3 条件が揃っているため、「入力列 + 初期シードを保存して再生すれば同じ結果になる」土台はすでにある。ここにリプレイを載せると (1) バグ再現がファイル 1 個で済む、(2)「既知のリプレイを流して最終状態のハッシュを比較」という高カバレッジのテストが 1 本で書ける、(3) チート検証やハイライト共有の基盤になる、の 3 つが同時に立つ。GPT の指摘どおり loss / reorder / jitter を注入して state と frame hash を比較すると、補間・予測・UDP を実際の劣化条件下で守れる。「同一 tick_hz なら同一結果」の決定論ポリシーを明文化する契機でもある。参考: Rocket League / Dota 2 のリプレイ、quake3 の demo 形式。
  > 関連ファイル: `engine/apps/contents/lib/events/game.ex`, `assets/lib/assets/objects.ex`

- **`cargo-fuzz` による decode 系のファジング** `0` — **Opus**
  > 外部から任意のバイト列を受ける入口が 3 つある。Formula バイトコードの `decode_bytecode`（`rust/nif/src/formula/decode.rs:53-170`）、UDP パケットの `Protocol.decode`（`apps/network/lib/network/udp/protocol.ex:39-47`）、protobuf の `decode_pb_render_frame`。いずれも現状は example-based テストのみである。Rust 側 2 つは `cargo-fuzz` のターゲットを 20 行書けば回り始め、`DecodeError` を返す以外の結果（panic / 無限ループ / メモリ膨張）が出ないことをコーパスで確認できる。Elixir 側は同じ入力コーパスを流す ExUnit テストで代替できる。バウンドチェックの実装品質は高い（プラス +5）ため、これはその品質を機械的に維持する投資である。
  > 関連ファイル: `engine/rust/nif/src/formula/decode.rs`, `engine/rust/client/render_frame_proto/src/`

- **ベンチマーク基盤と継続的な予算管理** `0` — **GPT**
  > フレームエンコード時間・Formula VM 実行時間・UDP encode/decode・補間の `sample()` に対する継続的ベンチマーク。tick 予算が 20Hz = 50ms と確定した今、各処理の予算消費率（tick/frame budget 比）を数値で追跡でき、`StressMonitor` の警告閾値にも根拠が生まれる。`docs/warranty/ci.md` が「`cargo bench -p physics` で前回比 +10% 超をブロック」という（実在しない）仕組みを既に文書化しているので、その文書を真実にする方向で作るとよい。
  > 関連ファイル: `engine/apps/contents/lib/contents/frame_encoder.ex`, `engine/rust/nif/`, `engine/rust/client/shared/src/interp.rs`

### 可観測性

- **OpenTelemetry / PromEx によるメトリクス外部化と room SLO** `0` — **両者**
  > telemetry の基盤はあり、この 3.5 週間で「見たい対象」が大幅に増えた（JWKS 検証の成否、S2S peer 取得、UDP セッション数、Zenoh 再接続回数、補間の適応遅延）。ConsoleReporter を PromEx / OTel exporter に差し替えれば、これらをダッシュボード化できる。加えて engine / auth / assets の 3 サービス構成になった今、`traceparent` を Bearer トークンと同じ経路で伝播させれば「ログインが遅い」「入室でこける」を跨サービスで切り分けられる。GPT は tick → encode → Zenoh → decode → render に correlation ID を通して room 単位の SLO を定義することを提案しており、連合として複数運営者にサーバを配る構想があるなら、運営者が自分のインスタンスの健康状態を見る手段は必須装備になる。
  > 関連ファイル: `engine/apps/core/lib/core/telemetry.ex`, `auth/lib/auth_web/telemetry.ex`

- **auth の監査ログ（重要操作の追記専用記録）** `0` — **Opus**
  > `auth` はログイン・パスワード変更・退会・トークン失効といった重要操作を持ち、レート制限の throttle は telemetry に出る（`auth/lib/auth/rate_limit.ex:93-97`）。一方で「いつ・どの IP から・どのアカウントに何をしたか」を後から辿れる追記専用の記録はない。ユーザーへの「不審なログインがありました」通知や、インシデント時の影響範囲特定に直結する。`TokenRevocation` と同様の Ash リソースを 1 つ追加し、`TokenCleanup` と同じ形で保持期間を管理すれば実装は素直である。連合として複数運営者にサービスを配るなら、運営者が説明責任を果たすための道具でもある。
  > 関連ファイル: `auth/lib/auth/accounts.ex`

### 再現性・配布

- **`rust-toolchain.toml` によるツールチェーン固定** `0` — **統合時追加**
  > `engine/rust/` に `rust-toolchain.toml` も `rustfmt.toml` も存在しない。`cargo fmt` と `cargo clippy -D warnings` を品質ゲートに置いている以上、rustfmt / clippy の版が上がった瞬間にローカルと CI で判定が食い違い、「手元では通るのに CI が赤い（またはその逆）」が起きる。CI の無効化と再有効化を往復してきた履歴（マイナス -1）を踏まえると、判定のブレは無効化の動機になりやすいため、先に固定しておく価値が高い。`rust-toolchain.toml` に channel と `components = ["rustfmt", "clippy"]` を書けば、ローカル・CI・将来の貢献者の 3 者で同じ判定になる。Elixir 側は `ELIXIR_VERSION` / `OTP_VERSION` を `ci.yml` の env で既に一元管理しているので、Rust 側にも同じ規律を入れるという整合の話でもある。
  > 関連ファイル: `engine/rust/Cargo.toml`, `engine/.github/workflows/ci.yml`

- **再現可能なリリースチャネル（インストーラ・署名・SBOM・自動更新）** `0` — **GPT**
  > `cargo build -p app` 産物を配布可能にする層（Windows: MSIX / Inno Setup、macOS: notarized dmg）と、protobuf 契約バージョン不一致時の自動更新誘導。GPT の指摘どおり、mix release・署名インストーラ・SBOM・チェックサムを一つの manifest に束ねる形にすると検証可能になる。ランチャーは別リポジトリに分離されたので、そちらとの役割分担を先に決める必要がある。サーバ側は `auth` と `assets` の `mix release` + Dockerfile がそのまま雛形になるため、engine にリリース定義を足すコストは以前より下がっている。連合として他運営者にサーバを立ててもらう構想は、配布形態がないと始まらない。
  > 関連ファイル: `engine/rust/client/app/`, `engine/mix.exs`

### トランスポート防御

- **Zenoh ACL / TLS の有効化** `0` — **統合時追加**
  > Zenoh ルータには ACL・mTLS 機能があるため、アプリ層の認証（RoomToken の Zenoh 経路適用は今回実装された）と併用してトランスポート層でも防御を重ねられる。`AUTH_REQUIRED` を既定オンにする際、アプリ層とトランスポート層の二重防御があると「設定を一つ間違えても即座に穴にならない」状態を作れる。両者が独立に指摘した `AUTH_REQUIRED` 既定オフ問題（マイナス）に対する、修正とは別軸の補強として挙げる。連合公開時の前提装備。
  > 関連ファイル: `engine/apps/network/lib/network/zenoh_bridge.ex`, `engine/rust/client/network/src/platform/desktop.rs`

---

## 規約・ドキュメントの自動整合

- **評価ルール・warranty ドキュメントとコードの整合チェック** `0` — **統合時追加**
  > 今回の評価で、`docs/warranty/ci.md` が削除済みの physics クレートと実在しない credo 設定値を記述していること、`.cursor/rules/evaluation.mdc` の技術評価層が `native/` 配下のクレート構成（`native/render` / `native/audio` / `native/nif/physics` / `native/tools/launcher`）を前提に書かれており現行の `rust/` 構成と対応しなくなっていることが分かった（両評価者が独立にマイナス点として計上）。どちらも「仕組みを説明する文書」の陳腐化であり、コードより気づかれにくい。提案として、(1) `ci.md` の表を `.credo.exs` と `ci.yml` から生成する、(2) 評価ルールに列挙されたパスが実在するかを検証する小さなスクリプトを CI に置く、の 2 点を挙げる。ドキュメント品質がこのプロジェクトの強み（moduledoc の誠実さは +3）である以上、その強みを機械的に守る仕組みには投資価値がある。
  > 関連ファイル: `engine/docs/warranty/ci.md`, `engine/.cursor/rules/evaluation.mdc`, `engine/.credo.exs`

---

## OSC を起点とした相互運用

- **VRChat / Resonite OSC 互換レイヤの拡張** `0` — **統合時追加**
  > 今回の OSC コンポーネント群（両評価者がプラス評価）は、外部エコシステムとの相互運用という新しい方向を開いた。ここを伸ばすなら、VRChat OSC の avatar parameter 規約（`/avatar/parameters/*`）とフェイストラッキング（VRCFaceTracking 系のパラメータ名）への対応が費用対効果が高い。既存の OSC ツール（トラッカー、フェイストラッキングソフト、ハードウェアコントローラ）がそのまま繋がる状態になり、「自作エンジンだから何も繋がらない」という新規エンジン最大のハンデを、コンポーネント 1 つで回避できる。OpenXR の実装が Monado 系に限定されている現状（マイナス）に対する、実用的な迂回路にもなる。
  > 関連ファイル: `engine/apps/contents/lib/components/category/network/osc/`, `engine/apps/contents/lib/contents/sample_osc.ex`

---

## 総計

### 件数

| 出典 | 件数 |
|:---|---:|
| 両評価者が独立に一致 | 6 |
| Opus のみ | 10 |
| GPT のみ | 13 |
| 統合時追加 | 7 |
| **統合後の提案** | **36** |

提案は **36 件、いずれも 0 点**。Opus 16 件 + GPT 19 件のうち 6 組が同一提案として一致したため 29 件に統合され、まとめ作成時に両者のマイナス点・プラス点から導出した 7 件を加えて 36 件となった。

### 採用判断

両評価者が独立に同じ提案へ到達した 6 件は、それだけで優先度の高さを示す信号として扱う。とくに次の 3 件は、実装コストが小さく効果が大きいという点で両者の記述が完全に一致した。

1. **Formula VM の gas 上限** — 制御フロー命令を足す前に入れる必要がある（順序が重要）
2. **E2E スモークテスト** — 部品が揃っており実装が小さいのに、単体テストが構造的に見逃す種類の破綻を捕まえる
3. **決定論リプレイ** — CI が復活した今、器に入れる中身として最も効く。テスト・デバッグ・将来機能（ロールバック予測）の 3 方向に効く

両者の分岐は着眼点の差として読める。**Opus は「エンジン内部の次の段」**（AOI・カリング・ホットリロード・ビジュアルエディタ・入力抽象統合）に、**GPT は「出荷と作品性」**（BulletHell3D の作品化・リリースチャネル・アセットパイプライン・所有モデル）に提案が寄った。どちらか一方だけ見ると偏るため、統合一覧としては両方を残す価値がある。

一方で、一致していない提案のうち **engine ↔ assets の 1 経路配線**（GPT）は、`assets` 側が完成済みで待っているだけの状態であり、コストに対する効果が上記 3 件と同等に大きい。優先度としては「両者一致 3 件 + これ」を第一陣として扱うのが妥当である。

前回（Fable 2026-07-31）の提案 15 件のうち「連合アーキテクチャの二層分離ロードマップ」は read-only S2S として実装され、プラス点へ移行した。
