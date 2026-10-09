# 提案 統合一覧 — 2026-10-09

評価日: 2026-10-09
統合元:
- 第1評価者（Claude Opus 5.5）: `opus/opus-specific-proposals-2026-10-09.md`（18 項目）
- 第2評価者（GPT-5.6 Sol）: `gpt/gpt-specific-proposals-2026-10-09.md`（20 項目）

提案は採点しない。マイナス点と根が同じものは、改善計画側に寄せ、ここでは「あると次の価値になるもの」だけを残す。ルームごとのシーンスタック、`__quit__` の許可リスト、RoomToken の配線、gas メータリング、保証文書の追従は提案ではなく欠陥の修正である。

## 採点基準

| 点数 | 基準 |
|:---:|:---|
| 0 | 現時点では存在しないが、実装すればプロジェクトの価値を高める提案 |

---

## 権威と空間

### 座標と物理の器

- **binary64 を浮動原点として実装する** `0` — **両者**
  > 文言を f32 に直すのは欠陥の解消である。その先に、原点をルームまたは観測者に置き、遠方でも精度を落とさない契約を protocol に足すと、ビジョンの一行が実装になる。Bevy の `Transform` や大規模ワールドの origin rebasing が参照になる。
  > 対象ファイル: `protocol`, `client/shared`, `.workspace/0_docs/vision.md`

- **物理の器を純 Elixir の core に置く** `0` — **Opus**
  > Rust にゲームルールを戻さない。衝突と空間分割のインターフェースだけを contents の外に定義し、中身は後から差し替える。撤去した SoA 実装の復活とは別物である。
  > 対象ファイル: `world-server/apps/core`

- **決定論的 tick journal と replay** `0` — **GPT**
  > 権威 tick が既にある。入力列を残せば、不具合の再生とチート検証の土台になる。
  > 対象ファイル: `world-server/apps/contents`

### アイデンティティと入室

- **room admission controller** `0` — **GPT**
  > 定員、バージョン、コンテンツ互換を入室の前に判定する。トークン配線（欠陥）の次の段である。
  > 対象ファイル: `world-server/apps/network`

- **配置テーブルと訪問トークンによる連合スライス** `0` — **GPT**
  > いまの S2S はカタログである。どのノードがどの空間を持つかをテーブルにし、訪問トークンでスライスを開くと連合が読み取り以上になる。
  > 対象ファイル: `world-server/apps/network`

- **WebAuthn / passkey** `0` — **GPT**
  > パスワードの Argon2 は既に強い。パスキーはアカウントライフサイクルの次の認証器である。
  > 対象ファイル: `auth-server/lib/auth`

- **OIDC discovery 互換の metadata** `0` — **GPT**
  > JWKS は既にある。`/.well-known/openid-configuration` があると、外部クライアントがこの認証サービスを発見できる。
  > 対象ファイル: `auth-server/lib/auth_web`

---

## クライアント体験

### 描画・入力・音

- **DrawCommand に安定した `entity_id` を足す** `0` — **Opus**
  > 最近傍補間（欠陥）を消すための契約拡張である。提案として残すのは、ID の上に補間・音声・デバッグを載せるところまでである。
  > 対象ファイル: `protocol`, `client/shared`

- **自機の予測と reconciliation** `0` — **Opus**
  > 予測関数はいま恒等である。自機だけを予測し、権威スナップショットで戻すと、補間遅延と操作感を分離できる。
  > 対象ファイル: `client/shared`

- **RenderGraph と GPU timestamp の予算** `0` — **GPT**
  > いまの wgpu パスは一枚岩でも描けている。パスをグラフにし、GPU 時間を予算化すると、コンテンツ WGSL を足してもフレームの説明が残る。
  > 対象ファイル: `client/render`

- **headless 描画の golden image** `0` — **Opus**
  > オフスクリーンレンダラは既にある。画像差分を CI に載せると、シェーダ変更の回帰が見える。
  > 対象ファイル: `client/render`

- **入力アクションをアセットとして外に出す** `0` — **GPT**
  > キーとアクションの対応がコードにある。差し替え可能なマップにすると、コンテンツごとの操作を Elixir 定義へ寄せられる。
  > 対象ファイル: `client/window`, `world-server/apps/contents`

- **audio mixer graph** `0` — **GPT**
  > 専用スレッドとデバイス不在フォールバックの次に、バス、優先度、空間化をグラフで持つ。同時発音の上限（欠陥）の先にある。
  > 対象ファイル: `client/audio`

- **接続状態機械の型化** `0` — **GPT**
  > 再接続、認証、ルーム参加が別モジュールに散らばっている。状態を型にすると、認証付き入室の欠落がコンパイル時に残らない。
  > 対象ファイル: `client/app`, `client/network`

---

## 検証と運用

### テストと観測

- **Formula の differential oracle** `0` — **GPT**
  > Elixir 側の評価と Rust VM の結果をランダム式で突き合わせる。除算に偏ったテストの次の段である。
  > 対象ファイル: `world-server/rust/nif`, `world-server/apps/core`

- **プロパティベーステストと fuzz** `0` — **Opus**
  > プロトコルと VM の入力に向く。導入自体は欠陥の解消に近いが、どの性質を性質として固定するかは提案である。
  > 対象ファイル: `world-server`, `client`

- **ネットワーク障害のシナリオハーネス** `0` — **GPT**
  > zenohd の再起動、遅延、順不同を台本にして、クライアント再接続とサーバ非再接続の非対称をテストで固定する。
  > 対象ファイル: `client/network`, `world-server/apps/network`

- **保証ごとのテスト行列** `0` — **GPT**
  > ビジョンの各保証行に、緑であるテストを 1 つ割り当てる。保証文書の追従（欠陥）のあとに効く。
  > 対象ファイル: `.workspace/0_docs/vision.md`

- **room trace とクライアントのデバッグ HUD** `0` — **GPT**
  > tick、補間遅延、ドロップを同じ ID で見る。ConsoleReporter の次である。
  > 対象ファイル: `world-server/apps/core`, `client`

- **architecture boundary test** `0` — **GPT**
  > contents が network を直接参照しない、core がコンテンツ語彙を持たない、をコンパイルまたはテストで拒否する。
  > 対象ファイル: `world-server`

### 配布と開発入口

- **スーパープロジェクトの integration CI** `0` — **Opus**
  > ピンの一致、golden の再生成、認証付き smoke。欠如はマイナス側でも計上している。ここでの提案は、そのジョブが「製品の縦切り」を 1 本だけ見ることである。
  > 対象ファイル: スーパープロジェクト

- **superproject doctor コマンド** `0` — **GPT**
  > ピン、サブモジュール、ツールバージョン、保証文書の参照先を 1 コマンドで点検する。`mix alchemy.ci` が world-server に閉じていることの補完になる。
  > 対象ファイル: スーパープロジェクト

- **再現可能な release と provenance** `0` — **GPT**
  > auth-server の release を、world-server と client に広げるときに SBOM とビルド入力のハッシュを付ける。
  > 対象ファイル: `world-server`, `client`, `auth-server`

- **クロスプラットフォームの起動スクリプト** `0` — **Opus**
  > `.bat` 以外から同じ手順で届くようにする。
  > 対象ファイル: リポジトリ直下

- **QUIC / WebTransport の検討** `0` — **Opus**
  > UDP の信頼性を自前で足す前に、トランスポートを替える選択肢を比較する。今すぐの置換ではない。
  > 対象ファイル: `world-server/apps/network`

- **Content manifest と hot reload のトランザクション** `0` — **GPT**
  > コンテンツ差し替えは再起動前提に見える。定義の世代を manifest にし、失敗したら戻せるロードにすると、編集経路の土台になる。
  > 対象ファイル: `world-server/apps/contents`

- **最小の縦切りを製品指標にする** `0` — **GPT**
  > 「登録 → 認証 → ルーム参加 → ルーム独立の状態 → 再接続 → 保存」の 1 本が緑かで、次の評価の合否を先に決める。機能数ではなくこの列を見る。
  > 対象ファイル: `.workspace/0_docs/vision.md`

---

**小計: 0 点**（26 項目）
