# architecture v1 ↔ v2 — 追加・削除・衝突の洗い出し

> **作成日**: 2026-10-22  
> **更新**: 2026-10-23 — Phase 0–2: AI 正本整備、決定済み本文化、**C2/C3/C4/C5/C7/C8/C11 を方針決定**（全衝突 ID が方針決定済）。同日より前: C9・D6 / C6 / C1・C12 / C10・D3 / host-server 配置  
> **対象**: [overview.md](overview.md)（v2 目標図）と [../architecture/](../architecture/)（v1 現行実装記述）  
> **方針**: 洗い出し＋方針決定を記録。v1 一括アーカイブはしない（C8）。決定の本文化は進行中。  
> **補足**: 「v1 に無い」は **`.workspace/0_docs/architecture/` 内に正本が無い** という意味。  
> 兄弟サービス（例: `.workspace/`）に既にある文書は §8 で別扱いする。

凡例:

| 区分 | 意味 |
|:---|:---|
| **一致 (aligned)** | v1 と v2 で方針・数値が揃っている（担い手や細部が衝突する場合は「切り分け」列で明示） |
| **追加 (v2 only)** | `architecture/`（v1）に相当する正本記述がない新コンポーネント・概念（兄弟サービス文書の有無は問わない） |
| **削除 / 廃止方向 (v1→v2)** | v1 が正としているが、v2 図では消える／前面から下がるもの |
| **衝突 (要方針決定)** | 同じ概念で結論が食い違う。移行時にどちらを正にするか要決定 |
| **方針決定済** | §2.1 に結論を記録済み。v1 正本への反映は未実施 |
| **保留** | 意図的に後回し（詰めは別タスク） |
| **既存・分散 (sibling)** | モノレポ内の別 `.workspace` に正本があり、engine の `architecture/` からは薄い参照のみ |

---

## 1. 一致（v1 と v2 で方針が揃っている部分）

「誰が実行するか」は衝突でも、「何を・どのレートで・どの契約で」は揃っているもの。移行時はここを壊さない。

| ID | 一致している内容 | v1 / v2 での表現 | 衝突との切り分け | 主な参照 |
|:---|:---|:---|:---|:---|
| M1 | **権威更新レートは推奨 20Hz** | v1: Elixir tick 推奨 20Hz（10/30/非推奨60）。v2: host-server 権威 Tick 20Hz | **誰が tick するか**は C1 | [authoritative-state-sync-policy.md](../architecture/authoritative-state-sync-policy.md), [overview.md](overview.md) |
| M2 | **表示時間と主時間の分離** | クライアント描画は ~60fps（v2 は ~60–120）で予測・補間。表示は権威スナップショットを埋めない | 権威の主体は C1。補間方針自体は一致 | 同上, [policy/render-interpolation.md](../policy/render-interpolation.md) |
| M3 | **ワイヤ契約 SSoT = alchemy-protocol `proto/`** | RenderFrame / 入力等は Protobuf。PROTOCOL_PIN 方向 | ドメイン権威の置き場は C1 / C12。**ペイロード形は一致** | [overview.md](../architecture/overview.md)#設計思想, [protobuf-migration.md](../architecture/protobuf-migration.md) |
| M4 | **リアルタイム中核は Zenoh** | フレーム・入力を Zenoh で運ぶ。zenohd / zenoh-router を別プロセス想定 | **クライアント⇔サーバー間の転送は C9 で Zenoh 一本化**。トラッカー等のローカル OSC は Device Input Edge（C9）として別層 | [network-protocol-current.md](../architecture/network-protocol-current.md), [zenoh-protocol-spec.md](../architecture/zenoh-protocol-spec.md) |
| M5 | **クライアントは Pure Rust（wgpu / OpenXR）** | VRAlchemy = winit/wgpu、任意で OpenXR。**クライアントは nif 非依存** | サーバ側 NIF の有無は C2 | [rust/desktop_client.md](../architecture/rust/desktop_client.md), [overview.md](../architecture/overview.md) |
| M6 | **最終ゴールは分散連合型 VRSNS** | vision-goal / federation。運営者間連携を目指す | 連合の具体手段は **§2.1 / C6 で決定**（S2S HTTPS 必須・運営者間フルメッシュ禁止） | [vision-goal.md](../vision-goal.md), [federation.md](../architecture/federation.md) |
| M7 | **スケールアウトと連合は別層** | 単一運営者内スケール ≠ 運営者間連合 | §2.1: Zenoh Mesh は主にスケールアウト層（＋ Trusted+ACL）。連合の正面は S2S | [federation.md](../architecture/federation.md) |
| M8 | **認証は RS256 JWT + JWKS** | federation / auth 契約。`/.well-known/jwks.json`、`sub` = user UUID | ToS / Friendship 等の拡張は §8・A1。**署名検証モデルは一致** | [federation.md](../architecture/federation.md), [jwt-jwks-engine-contract.md](../jwt-jwks-engine-contract.md) |
| M9 | **Room Token で入室をゲート** | v1: `Network.RoomToken`（Phoenix.Token）。v2: world-server が Room Token 発行、入力に付与 | 発行主体・JWT 必須化の進みは実装差。**概念は一致** | [elixir/network.md](../architecture/elixir/network.md), [overview.md](overview.md) |
| M10 | **Formula を空間ギミック／数式実行に使う** | バイトコード VM の存在と「定義と実行の分離」思想 | **実行場所**（NIF vs shared-sim）は C2 / C11。命令仕様は部分維持可 | [formula-vm-bytecode.md](../architecture/formula-vm-bytecode.md) |
| M11 | **旧ゲーム用 60Hz NIF / GameWorld は復活させない** | v1: physics NIF・Rust 60Hz ループ撤去済み。v2: world-server NIF 完全廃止 | Rapier を Pure Rust host に置くのは **別経路**（C4）。NIF 物理の復活ではない | [rust/nif.md](../architecture/rust/nif.md), [legacy_contents-to-physics-bottlenecks.md](../architecture/legacy_contents-to-physics-bottlenecks.md) |
| M12 | **描画はサーバ NIF 経由ではない** | DrawCommand / RenderFrame は Zenoh → クライアント decode → wgpu | **誰が encode/publish するか**は C3 | [draw-command-spec.md](../architecture/draw-command-spec.md) |
| M13 | **入力キャプチャはクライアント、信頼しない** | デバイス取得は Rust。公式採否はサーバ側 | 「サーバ」が Elixir か host-server かは C1 | [authoritative-state-sync-policy.md](../architecture/authoritative-state-sync-policy.md) |
| M14 | **Elixir Umbrella が運営側の案内・制御を持つ** | apps: core / network / contents（v2 は world-server 名称＋verifier） | 権威 tick・Frame 発行をどこまで持つかは C1 / C3 | [elixir/contents.md](../architecture/elixir/contents.md), [overview.md](overview.md) |
| M15 | **launcher が複数プロセス起動を担う** | zenohd・サーバ・client の起動（alchemy-launcher / rust/launcher） | ローカル host-server 分離・画面クローズ後維持は C5 | [rust/launcher.md](../architecture/rust/launcher.md) |
| M16 | **クライアント音声はクライアント側クレート** | v1: `audio` は app 利用・nif 非紐付け。v2: client の audio / Zenoh Audio | 空間オーディオ指揮・Opus over QUIC は A11（拡張）。**nif に音声を戻さない**点は一致 | [rust/nif/audio.md](../architecture/rust/nif/audio.md) |

---

## 2. 衝突（最重要・移行前に方針決定が必要）

| ID | 状態 | 論点 | v1（現行正本） | v2（目標図） | 主な v1 参照 |
|:---|:---|:---|:---|:---|:---|
| C1 | **方針決定済**（§2.1） | **主時間 / 状態 SSOT** | Elixir 権威 tick が主時間。状態の SSOT は Elixir サーバー | Rust `host-server` が権威 Tick 20Hz。Elixir（world-server）は案内所・門番・verifier | [authoritative-state-sync-policy.md](../architecture/authoritative-state-sync-policy.md), [overview.md](../architecture/overview.md) |
| C2 | **方針決定済**（§2.1） | **NIF** | Formula VM のみ Rustler NIF として残存（`run_formula_bytecode`） | world-server は **NIF 完全廃止**。Formula VM は `shared-sim`（Pure Rust）内 | [rust/nif.md](../architecture/rust/nif.md), [elixir/core.md](../architecture/elixir/core.md) |
| C3 | **方針決定済**（§2.1） | **RenderFrame 発行元** | Elixir `Contents.FrameEncoder` → `FrameBroadcaster` → Zenoh publish | `host-server` が 20Hz RenderFrame を 1 回 Publish → Zenoh Fan-out。verifier が抜き打ち監査 | [network-protocol-current.md](../architecture/network-protocol-current.md), [draw-command-spec.md](../architecture/draw-command-spec.md), [rust/desktop/render.md](../architecture/rust/desktop/render.md) |
| C4 | **方針決定済**（§2.1） | **物理の置き場** | ゲーム用物理 NIF は **撤去済み**（再導入しない前提の現行記述） | Rapier3d を `host-server` / `shared-sim` に配置（旧 NIF 物理とは別経路） | [rust/nif/legacy_physics.md](../architecture/rust/nif/legacy_physics.md), [legacy_contents-to-physics-bottlenecks.md](../architecture/legacy_contents-to-physics-bottlenecks.md) |
| C5 | **方針決定済**（§2.1） | **launcher 責務** | zenohd + mix run（Phoenix）+ VRAlchemy の起動・トレイ管理 | client とローカル host-server のプロセス分離・死活・`alchemy://` 起動。画面クローズでもホスト維持 | [rust/launcher.md](../architecture/rust/launcher.md), [overview.md](../architecture/overview.md)（外部 alchemy-launcher） |
| C6 | **方針決定済**（§2.1） | **連合の形** | スケールアウト層（libcluster）と連合層（S2S HTTP / JWKS / identity federation）の二層。Phase 4 正本 | World 連合リスト交換・Zenoh Federation Mesh・マーケット Trusted/Blocked が前面。S2S ActivityPub 系は図上で明示されない | [federation.md](../architecture/federation.md), [vision-goal.md](../vision-goal.md) |
| C7 | **方針決定済**（§2.1） | **シェーダー定義経路** | Elixir コンテンツのアセットパスから WGSL を起動時ロード（サーバ定義寄り） | Dual Representation（ノードグラフ ⇄ WGSL）をクライアント Dual Editor + Naga 中心。規格は共通層 | [shader-elixir-interface.md](../architecture/shader-elixir-interface.md) |
| C8 | **方針決定済**（§2.1） | **ドキュメント分割軸** | サーバー / クライアント、Elixir / Rust クレート単位 | Operator / Shared / Client Host / Guest+Platform | [policy/architecture-docs-structure.md](../policy/architecture-docs-structure.md) |
| C9 | **方針決定済**（§2.1） | **Network Transport vs Device Input Edge** | Zenoh + 独自 UDP（`Network.UDP.Protocol`）+ 空間同期用 Phoenix Channel を並列で記述 | **転送は Zenoh 一本化**。独自 UDP / 空間同期用 Phoenix Channel は廃止。OSC over UDP はクライアント局所の入力エッジとして存続 | [elixir/network.md](../architecture/elixir/network.md), [network-protocol-current.md](../architecture/network-protocol-current.md) |
| C10 | **方針決定済**（§2.1） | **コンテンツモデル** | 第一級コンテンツ 3 本（CanvasTest / BulletHell3D / FormulaTest）+ Scene/Component | WorldManifest / AlchemyPrefab / Spatial VCS / 空間ギミック Formula。検証用 3 コンテンツの位置づけが未定義だった | [elixir/contents.md](../architecture/elixir/contents.md), [scene-and-object.md](../architecture/scene-and-object.md) |
| C11 | **方針決定済**（§2.1・C2 と一体） | **Formula 実行場所** | Elixir `Core.Formula` → NIF VM（サーバプロセス内） | host-server / shared-sim 内の Pure Rust Formula VM（クライアント・クラウドホスト共通） | [formula-vm-bytecode.md](../architecture/formula-vm-bytecode.md), [elixir/core.md](../architecture/elixir/core.md) |
| C12 | **方針決定済**（§2.1・C1 と一体） | **SSoT の層表現** | ドメイン = Elixir、ワイヤ = alchemy-protocol proto | ドメイン権威が host-server 側へ寄る一方、protocol / assets / auth が複数 SSoT として並立（→ **時間軸別 4 SSoT で解消**） | [overview.md](../architecture/overview.md)#設計思想 |

### 2.1 方針決定（2026-10-22〜23）

#### C6 — 連合の形：S2S HTTPS 必須／Zenoh フルメッシュ禁止

**結論**: 運営者間の zenoh-router を **無制限フルメッシュ（Zenoh Peering）で結ばない**。悪意ある運営者のルーターからトピック汚染・大量購読による帯域 DDoS が成立するため。運営者間の **S2S HTTPS は必須**。

| 経路 | 手段 | 保証すること | 保証しないこと |
|:---|:---|:---|:---|
| **案内・認証・マーケットの連合** | **S2S HTTPS REST** | ワールド一覧交換、`/.well-known/jwks.json`・`alchemy-node-info.json`（A14）取得、連合マーケットのカタログ検索。Blocked はドメイン／IP 単位で確実に遮断できる | リアルタイム空間状態の運営者間中継 |
| **空間への入室（Cross-Origin Client Connection）** | ゲスト **client が相手運営者へ直接接続** | 運営者 B のユーザーが運営者 A のワールドへ行くとき: B の auth-server で得た JWT を提示 → A の world-server から Room Token → **A の zenoh-router に直接接続** | 運営者 B の zenoh-router 経由での A 空間中継 |
| **Zenoh Mesh** | 用途を限定 | (1) **同一運営者内**のマルチリージョン分散（M7: スケールアウト層）。(2) **Trusted 提携**かつトピック ACL で対象ルームのみ許可したブリッジ | 未信頼運営者間の無制限 Peering |

v2 overview 図の「Federation Mesh」エッジは、上記の限定用途に読み替える。連合の正面玄関は S2S HTTPS（v1 [federation.md](../architecture/federation.md) の連合層を維持・強化）。本文化先: `federation.md` 改訂 / `architecture-v2/zenoh-mesh.md`。

#### C1 / C12 — SSoT を「3つの時間軸＋ワイヤ」で並立定義する

**問題**: 「ドメイン権威が host-server に移った」と書くと、ローカル host-server はユーザー PC 上の **Untrusted 計算係（A7）** であるのに、v1 の「Elixir が世界の秩序を守る」と矛盾して見える。C12 の「複数 SSoT 並立」も、時間軸を分けないと衝突に見える。

**結論**: 単一の「ドメイン SSoT」を host に移すのではなく、**時間軸別の権威**を並立させる。C1 と C12 の衝突はこれで解消する。

| 時間軸 | SSoT | 担い手 | 保証すること |
|:---|:---|:---|:---|
| **永続**（アカウント・資産） | 永続 SSoT | **auth-server**（ユーザー・フレンド）＆ **assets-server**（WorldManifest / Prefab / Git 履歴） | アカウント・権利・アセット履歴の正 |
| **セッション・台帳**（秒〜分） | セッション・台帳 SSoT | **world-server**（Elixir: core + verifier） | 「今この部屋に誰がいて、どのアセットをスポーン・着用する権利があるか（Scene Manifest）」。**v2 でも Elixir が秩序の権威を握る** |
| **空間ティック**（~50ms / 推奨 20Hz） | 空間ティック SSoT | **host-server**（Pure Rust / shared-sim） | Elixir が署名した台帳の範囲内で、座標・物理・Formula の数値状態を回す **実行権威**（Untrusted・verifier 監査対象） |
| **ワイヤ契約** | ワイヤ契約 SSoT | **alchemy-protocol**（`.proto`） | 通信の形（M3 と一致） |

本文化先: [authoritative-state-sync-policy.md](../architecture/authoritative-state-sync-policy.md) の改訂版に上記 4 行を書く。v1 の「Elixir = 状態 SSOT・主時間」は **セッション・台帳** に縮約し、**空間ティック** のみ host へ移譲する（D4 もこの読み替え）。

#### C9 / D6 — Network Transport と Device Input Edge を分離する

**問題**: 「独自 UDP 廃止」と書くと、フルボディ／フェイシャルトラッカー連携のための **OSC over UDP** まで消えると読まれうる。実際に廃止したいのは **クライアント⇔サーバー／ホスト間のネットワーク転送** 側であり、機器入力エッジとは層が違う。

**結論**: 層を分けて決める。

| 層 | 範囲 | 方針 | 保証すること | 保証しないこと |
|:---|:---|:---|:---|:---|
| **Network Transport** | クライアント ⇔ サーバー／ホスト間のネットワーク転送 | **Zenoh に完全一本化** | 空間状態・入力・RenderFrame 等のワイヤ上のリアルタイム経路は Zenoh（M4 と一致） | world-server 側の独自 UDP（`Network.UDP.Protocol`）および **空間同期用** Phoenix Channel による転送 |
| **Device Input Edge** | トラッカー ⇔ クライアント間のローカル機器入力 | alchemy-client の局所入力エッジとして **標準 OSC over UDP（127.0.0.1 / LAN）** をサポート | フルボディ／フェイシャル等の OSC をクライアントが受信し、**検証・Protobuf 化**したうえで **Zenoh トピックとして送信**する | OSC をそのまま WAN／運営者間メッシュへ流すこと。world-server が OSC/UDP を直接受けて空間同期すること |

**廃止（D6）**: `Network.UDP.Protocol`、空間同期を担う Phoenix Channel を前面に出す記述・経路。  
**存続（入力エッジ）**: クライアント上の OSC over UDP 受信。ネットワーク上の正は常に Zenoh + Protobuf（alchemy-protocol）。

本文化先: [network-protocol-current.md](../architecture/network-protocol-current.md) / [elixir/network.md](../architecture/elixir/network.md) の改訂、および [rust/desktop/input.md](../architecture/rust/desktop/input.md)（または `architecture-v2/osc-input-edge.md`）への OSC エッジ追記。

#### C10 / D3 — 第一級コンテンツ 3 本：捨てず「v2 初期検証用 WorldManifest」へ昇格

**結論**: CanvasTest / BulletHell3D / FormulaTest は廃止しない。Elixir 内ハードコードモジュールから、**v2 の host-server（shared-sim）が最初に読み込む公式ビルトイン WorldManifest / Prefab テストスイート**へ **データとして移植**する。

| コンテンツ | 検証する能力 |
|:---|:---|
| CanvasTest | UI 描画 |
| BulletHell3D | 大量エンティティの同期負荷 |
| FormulaTest | 数式 VM の動作 |

**移行完了基準（DoD）案**: `host-server` 上で BulletHell3D と FormulaTest が 20Hz で動くこと。

#### host-server / shared-sim のリポジトリ配置

**結論**: `host-server` を別リポジトリに切り出さない。`shared-sim`（Rapier3d + Formula VM）は PC では別プロセス host-server、Web/Quest では client 内 Worker、さらに client の 60–120fps 予測補間でも同一クレートを使う（A7）。別リポにすると **shared-sim のバージョン同期地獄**になる。

**配置**: **alchemy-client（または統合 Rust ワークスペース）の Cargo Workspace 内**に `shared-sim` クレートと `host-server` バイナリクレートを同居させる。1 回のビルドで `vralchemy-client` と `alchemy-host-server` の両方の実行ファイルが出る構成とする。

文書上の `architecture-v2/host-server.md` / `shared-sim.md` は **責務・契約の正本**とし、コードの置き場はこの Workspace 方針に従う（§6 参照）。

#### C3 — RenderFrame 発行元：host-server

**結論（2026-10-23）**: 20Hz RenderFrame の **組み立て・1 回 Publish** は **host-server** が行う。Zenoh Fan-out。world-server（verifier）は抜き打ち監査のみで、定常経路の FrameEncoder 発行主体にはならない。

| 保証すること | 保証しないこと |
|:---|:---|
| host が台帳範囲内の状態から binary64 RenderFrame を生成し Zenoh へ 1 回 publish | Elixir が毎 tick Frame を組み立て続ける現行経路の永続化 |
| verifier が Spot-Check で改ざん検知できること | verifier が全フレームを再エンコードすること |

移行中は Elixir `FrameEncoder` 経路が現行。DoD: host が BulletHell3D 相当で 20Hz publish し、クライアントが受信描画できること。本文化先: [draw-command-spec.md](../architecture/draw-command-spec.md) / [host-server.md](host-server.md)。

#### C2 / C11 — NIF 廃止と Formula 実行場所：shared-sim

**結論（2026-10-23）**: world-server から **Rustler NIF を完全廃止**する。Formula VM は **shared-sim（Pure Rust）** 内に置き、host-server（権威 tick）と client（予測補間）と Worker で同一クレートを共有する。バイトコード契約（[formula-vm-bytecode.md](../architecture/formula-vm-bytecode.md)）は維持しうる。

| 段階 | 内容 |
|:---|:---|
| 現行 | `Core.Formula` → `run_formula_bytecode` NIF（新規 NIF 追加禁止） |
| 目標 | NIF 削除。Formula は shared-sim のみ。Elixir はバイトコード／定義を台帳経由で渡す側 |

本文化先: [shared-sim.md](shared-sim.md)、[rust/nif.md](../architecture/rust/nif.md) をレガシー／アーカイブ候補へ。

#### C4 — 物理：Rapier3d を shared-sim に（旧 NIF 物理とは別経路）

**結論（2026-10-23）**: Rapier3d は **shared-sim** に置く。旧ゲーム用物理 NIF（撤去済み）の復活ではない（M11 / D7）。パラメータ・スポーン定義は台帳／WorldManifest 側。物理ルールのハードコードを shared-sim に埋め込まない。

#### C5 — launcher：client とローカル host-server のプロセス分離

**結論（2026-10-23）**: launcher（alchemy-launcher）は **client（画面）とローカル host-server（裏プロセス）を分離起動・監視**する。画面クローズでも host は維持。`alchemy://` ディープリンク起動を担う。zenohd / world-server（mix）の起動も継続しうるが、**ローカル空間ティックの主体は host-server**。

| 保証すること | 保証しないこと |
|:---|:---|
| client 終了 ≠ ルーム host 終了（Private / ローカル host 時） | 電源 OFF 時の無停止（その場合はゲスト昇格または貸し出し host） |

本文化先: [rust/launcher.md](../architecture/rust/launcher.md)。

#### C7 — シェーダー：Dual Representation（クライアント Dual Editor + Naga）

**結論（2026-10-23）**: シェーダー／ギミックの正は **Dual Representation**（ノードグラフ ⇄ テキスト、共通 AST → Naga / Formula VM）。編集 UX の中心は **クライアント Dual Editor**。Elixir アセットパスからの WGSL 起動時ロードは移行期の互換に留め、正本は `architecture-v2/dual-representation.md`（新設予定）へ。現行 [shader-elixir-interface.md](../architecture/shader-elixir-interface.md) は要改訂／移譲。

#### C8 — ドキュメント分割軸：architecture-v2 を Operator / Shared / Client 軸に、v1 は現行実装記述として併存

**結論（2026-10-23）**:

| ツリー | 役割 | 分割軸 |
|:---|:---|:---|
| **architecture-v2/** | 目標・決定・索引 | Operator / Shared / Client Host / Guest+Platform（overview 図に合わせる） |
| **architecture/**（v1） | 現行実装の詳細 | 当面 Server/Client・クレート単位を維持。先頭バナーで v2 決定を優先 |

v1 を一括アーカイブはしない。決定のたびに v1 要改訂ファイルへ段落反映し、詳細正本が v2 に移ったものから v1 をレガシー／アーカイブ候補にする。ポリシー [architecture-docs-structure.md](../policy/architecture-docs-structure.md) は「v1 現行向け」と注釈し、v2 軸を追記する。

---

## 3. 追加（v2 only）

v1 の `architecture/` に **同等のコンポーネント正本がない**（一部は vision / federation に断片のみ）。  
**auth-server はここに載せつつ、実装契約ドキュメントは既に兄弟ツリーにある**（§8）。「ドキュメントが無い新規」ではない。

| ID | 要素 | 概要 | 既存文書の所在 |
|:---|:---|:---|:---|
| A1 | **auth-server** | JWT (RS256)・ToS 同意・Friendship・JWKS。Stage 1 SQLite / Stage 2+ PostgreSQL | **既存・分散 (sibling)** — 索引 [auth-server.md](auth-server.md)、契約 [jwt-jwks-engine-contract.md](../jwt-jwks-engine-contract.md)（§8 案 B）。署名検証は **M8 で一致** |
| A2 | **assets-server** | Spatial VCS（Commit/Branch/Tag）・Quota・アップロード検疫・Origin Cert・R2 CAS | なし（v2 図のみ） |
| A3 | **BillingProvider** | MoR/Stripe・プリペイドコイン・Quota 即時拡張（Optional Profile） | なし |
| A4 | **market-server** | BOOTH 風ストア・License Token・エスクロー・連合 Trusted/Blocked | なし |
| A5 | **apps/verifier** | Scene Manifest 署名・20Hz Spot-Check・ホスト死活・昇格指令 | なし |
| A6 | **クラウド host-server プール** | 貸し出し・常設・ヘッドレス冗長 A/B/C | なし |
| A7 | **ローカル host-server 分離** | PC 裏プロセス / Web・Quest は Worker。Untrusted 計算係 | なし |
| A8 | **見る権利と着る権利の分離** | 表示は即時、着用・配置のみ License Token | なし |
| A9 | **クライアント側 LOD ビルド** | PC 高画質 + Quest/Web KTX2 を自 PC でビルド。サーバ CPU 0 | なし |
| A10 | **セキュア P2P キャッシュ** | BLAKE3 事前照合・ChaCha20 難読化・Zenoh 経由チャンク融通 | なし |
| A11 | **Zenoh Audio Streaming** | Opus over QUIC Datagram。空間オーディオの指揮は world-server | なし |
| A12 | **Dual Editor / Dual Representation** | シェーダー・ギミックのノード⇄テキスト共通 AST | なし |
| A13 | **マルチプラットフォーム Step 1–5** | Win → Linux/macOS → Web → Mobile → Quest | なし |
| A14 | **alchemy:// / alchemy-node-info.json** | ディープリンク直ワープ・機能ディスカバリ | なし |
| A15 | **client_info（性能・Host可否）** | ホスト引き受け ON/OFF とスペック余裕度の定期通知 | なし |
| A16 | **公開範囲 5 段階** | Private / LAN / Friends / Friends+ / Public | なし |
| A17 | **binary64 描画境界** | 空間状態 f32 → RenderFrame 境界 f64 | なし |
| A18 | **運営伸縮 Stage** | 1人 SQLite All-in-One 〜 PostgreSQL + 連合 | なし |

---

## 4. 削除 / 廃止方向（v1→v2）

| ID | 要素 | v1 での位置づけ | v2 での扱い |
|:---|:---|:---|:---|
| D1 | **サーバ内 Formula NIF（Rustler）** | 現行唯一のサーバ NIF | 廃止方向（C2 / C11）。実行は shared-sim |
| D2 | **Elixir 中心の RenderFrame 組み立て・publish** | FrameEncoder → Zenoh が正経路 | host-server 発行へ移譲（C3）。Elixir は監査側 |
| D3 | **第一級コンテンツ 3 本を中心とした contents 記述** | CanvasTest 等が現行第一級 | **廃止ではなく昇格**（§2.1 / C10）。Elixir ハードコード → 公式ビルトイン WorldManifest / Prefab テストスイートへ移植。記述の中心は WorldManifest / Prefab / VCS |
| D4 | **「Elixir が状態 SSOT・主時間」の前提（単一軸）** | authoritative-state-sync-policy の核 | **時間軸分割で縮約**（§2.1 / C1・C12）。セッション・台帳は Elixir 維持。空間ティックのみ host へ。単一「Elixir=全状態 SSOT」表現は廃止 |
| D5 | **リポジトリ内 launcher の mix run 中心モデル** | zenohd + Phoenix + Client | プロセス分離ホストモデルへ（C5）。旧メニュー構成は縮小 |
| D6 | **独自 UDP / 空間同期用 Phoenix を前面に出す記述** | network の三本柱（Zenoh + UDP + Phoenix） | **Network Transport としては廃止**（§2.1 / C9）。OSC over UDP は Device Input Edge としてクライアント局所に残す |
| D7 | **サーバ NIF 経由の描画・物理・入力** | 既に廃止済みの歴史記述 | v2 でも復活させない（物理は Pure Rust host として別経路で再登場＝C4） |

※ D7 は「v1 がすでに削除したものを v2 が NIF として戻す」のではなく、「Pure Rust host として再配置する」点で C4 とセットで読む。

---

## 5. v1 ファイル単位の対応表

| v1 ファイル | 判定 | メモ |
|:---|:---|:---|
| [overview.md](../architecture/overview.md) | **要改訂**（移行時） | 全体図・責務表が C1–C5 と全面衝突。当面は現行正本のまま併存 |
| [authoritative-state-sync-policy.md](../architecture/authoritative-state-sync-policy.md) | **要改訂** | C1 / C12 正本。§2.1 の **時間軸別 4 SSoT** を本文に書く（host = 空間ティック実行権威、Elixir = セッション・台帳） |
| [federation.md](../architecture/federation.md) | **要改訂** | C6 決定済。S2S HTTPS 必須・運営者間フルメッシュ禁止・Zenoh Mesh 用途限定を統合 |
| [network-protocol-current.md](../architecture/network-protocol-current.md) | **要改訂** | C3 / C9 決定済。発行元変更＋ **Zenoh 一本化**（独自 UDP / 空間同期用 Phoenix を前面から外す） |
| [draw-command-spec.md](../architecture/draw-command-spec.md) | **要改訂** | C3。組み立て主体が Elixir → host-server へ |
| [elixir/core.md](../architecture/elixir/core.md) | **要改訂** | C2 / C11。NIF Bridge 廃止方向 |
| [elixir/contents.md](../architecture/elixir/contents.md) | **要改訂** | C1 / C10 決定済。tick は時間軸分割。3 本はビルトイン WorldManifest テストスイートへ |
| [elixir/network.md](../architecture/elixir/network.md) | **要改訂** | C3 / C9 決定済。案内・Room Token・verifier 連携へ寄せる。`Network.UDP.Protocol` / 空間同期用 Phoenix は廃止方向 |
| [elixir/server.md](../architecture/elixir/server.md) | **要改訂** | world-server への名称・責務再編候補 |
| [rust/nif.md](../architecture/rust/nif.md) | **要改訂 → アーカイブ候補** | C2。NIF 廃止後は legacy 扱いへ |
| [rust/launcher.md](../architecture/rust/launcher.md) | **要改訂** | C5。ホスト分離・alchemy:// 前提へ |
| [rust/desktop_client.md](../architecture/rust/desktop_client.md) | **要改訂** | ローカル IPC・LOD ビルド・Dual Editor 追加 |
| [rust/desktop/render.md](../architecture/rust/desktop/render.md) | **要改訂** | 受信元は維持しつつ発行側記述を host 側へ |
| [rust/desktop/input.md](../architecture/rust/desktop/input.md) | **要改訂** | 入力キャプチャはクライアント。送信は Zenoh（C1 / C9）。**OSC over UDP 受信 → 検証・Protobuf → Zenoh** の Device Input Edge を追記 |
| [rust/desktop/input_openxr.md](../architecture/rust/desktop/input_openxr.md) | **部分維持** | VR 入力経路。権威適用先の記述のみ要更新。OSC エッジ（C9）と並立 |
| [rust/nif/audio.md](../architecture/rust/nif/audio.md) | **要改訂** | A11。Zenoh Audio Streaming / 空間 DSP へ拡張 |
| [shader-elixir-interface.md](../architecture/shader-elixir-interface.md) | **要改訂 / v2 移譲** | C7。Dual Representation 正本へ置き換え候補 |
| [formula-vm-bytecode.md](../architecture/formula-vm-bytecode.md) | **部分維持** | バイトコード契約は維持しうる。実行場所は C11 |
| [protobuf-migration.md](../architecture/protobuf-migration.md) | **部分維持** | ワイヤ契約方向は継続。PROTOCOL_PIN / client_info 拡張 |
| [zenoh-protocol-spec.md](../architecture/zenoh-protocol-spec.md) | **部分維持 → 拡張** | Fan-out・Audio・P2P キャッシュ経路の追加が必要 |
| [scene-and-object.md](../architecture/scene-and-object.md) | **要改訂** | C10 決定済。WorldManifest / Prefab / Scene Manifest 署名＋ビルトイン 3 本の移植 |
| [mesh-definitions.md](../architecture/mesh-definitions.md) | **部分維持** | メッシュ定義の多くは assets / LOD ビルド側へ寄る可能性 |
| [erlang-term-schema.md](../architecture/erlang-term-schema.md) | **縮小 / アーカイブ候補** | Elixir↔NIF term 前提が薄れる（C2） |
| [legacy_contents-to-physics-bottlenecks.md](../architecture/legacy_contents-to-physics-bottlenecks.md) | **レガシー継続** | 歴史記録。C4 議論の反面教師 |
| [rust/nif/legacy_physics.md](../architecture/rust/nif/legacy_physics.md) | **レガシー継続** | 旧 NIF 物理。v2 Rapier host とは別物として明示 |
| [elixir/contents/vampire_survivor.md](../architecture/elixir/contents/vampire_survivor.md) | **レガシー継続** | 削除済みコンテンツの記録 |
| [elixir/contents/asteroid_arena.md](../architecture/elixir/contents/asteroid_arena.md) | **レガシー継続** | 同上 |
| [fix_contents.md](../architecture/fix_contents.md) | **アーカイブ候補** | 修正ログ系。v2 本文化対象外 |
| [fix_rust_architecture.md](../architecture/fix_rust_architecture.md) | **アーカイブ候補** | 同上 |

---

## 6. v2 新設ドキュメント候補（今回は本文化しない）

| 候補パス（案） | カバーする追加 ID | 統合メモ |
|:---|:---|:---|
| `architecture-v2/auth-server.md` | A1 | **新規起草より統合を優先**（§8）。薄い索引＋契約へのリンク、または契約の移設 |
| `architecture-v2/assets-server.md` | A2, A9, A10 | 現状は v2 図のみ |
| `architecture-v2/billing.md` | A3 | 同上 |
| `architecture-v2/market-server.md` | A4, A8 | 同上 |
| `architecture-v2/world-server.md` | WorldDir, Room Token, alchemy:// | world-server 配下に `.workspace/0_docs` があれば同様に突合 |
| `architecture-v2/verifier.md` | A5, A15 | 同上 |
| `architecture-v2/host-server.md` | A6, A7, C1, C4 | **文書**あり。**コード**スキャフォールド: `client/host-server`（`alchemy-host-server`） |
| `architecture-v2/shared-sim.md` | C11, Rapier, Formula VM | **文書**あり。**コード**スキャフォールド: `client/shared-sim` |
| `architecture-v2/builtin-world-manifests.md` | C10 / D3 | 移植仕様・DoD あり |
| `architecture-v2/dual-representation.md` | A12, C7 | 同上 |
| `architecture-v2/multi-platform.md` | A13 | 同上 |
| `architecture-v2/zenoh-mesh.md` | A10, A11, C6, C9 | C6 決定: 同一運営者スケールアウト ＋ Trusted+ACL のみ。運営者間フルメッシュは書かない。C9: **Network Transport = Zenoh のみ** |
| `architecture-v2/osc-input-edge.md`（案） | C9 / D6 | トラッカー等の OSC over UDP（127.0.0.1 / LAN）→ 検証・Protobuf → Zenoh。Network Transport とは分離 |
| `architecture-v2/builtin-world-manifests.md`（案） | C10 / D3 | CanvasTest / BulletHell3D / FormulaTest のビルトイン移植仕様・DoD |

### 6.1 コード配置（方針決定済）

| 成果物 | 置き場 | 備考 |
|:---|:---|:---|
| `shared-sim` クレート | alchemy-client（または統合 Rust）Cargo Workspace | Rapier3d + Formula VM。host / client 予測補間 / Web・Quest Worker で同一 |
| `host-server` バイナリ | 同上 Workspace | 別リポジトリ禁止（バージョン同期地獄回避） |
| client バイナリ（VRAlchemy 等） | 同上 | 1 ビルドで client + host-server の両方を出力 |

---

## 7. 推奨する次ステップ（文書作業）

> **2026-10-23 Phase 0 完了**: AI 正本の矛盾解消 — [README.md](README.md)（読む順）、v1 主要ファイル先頭バナー、[`.cursor/rules/implementation.mdc`](../../../.cursor/rules/implementation.mdc) / evaluation を時間軸別 4 SSoT に更新。

1. **auth-server 文書の統合方針を決める**（§8）。A1 を「無いから書く」ではなく「どこを正本にするか」の問題として扱う。→ **案 B 採用**（索引＋契約は既存パス）。
2. **決定済みの本文化**: §2.1 を [authoritative-state-sync-policy.md](../architecture/authoritative-state-sync-policy.md)（C1/C12）、[federation.md](../architecture/federation.md)（C6）、[network-protocol-current.md](../architecture/network-protocol-current.md) / [elixir/network.md](../architecture/elixir/network.md) / input 系（C9/D6）へ反映。overview v2 図の Federation Mesh 注釈と「転送＝Zenoh／OSC＝クライアント局所」を更新。
3. **未決の衝突**: ~~C2 / C3 / C4 / C5 / C7 / C8 / C11~~ → **2026-10-23 方針決定済**（§2.1）。§1 の一致（M1–M16）は維持。
4. **C9 実装準備**: OSC 契約を `osc-input-edge.md` または input 系へ。world-server の UDP / 空間同期用 Phoenix 廃止手順を起票。
5. **C10 実装準備**: [builtin-world-manifests.md](builtin-world-manifests.md) と host 上 20Hz DoD。
6. **C8 運用**: v1 改訂と v2 詳細の併存。一括アーカイブしない。コード背骨は client Workspace の `shared-sim` / `host-server`（Phase 3）。

---

## 8. 兄弟サービス文書（auth-server）と統合案

### 8.1 現状：差分が「薄い」理由

`architecture/`（v1）から見ると auth は断片のみ（[federation.md](../architecture/federation.md) の `auth/`・JWKS、overview の identity federation 箱）。  
一方、**実装契約の正本は既に** [`.workspace/0_docs/jwt-jwks-engine-contract.md`](../jwt-jwks-engine-contract.md) にある。

| 層 | 置き場 | 内容の粒度 |
|:---|:---|:---|
| engine 全体図（v2） | `architecture-v2/overview.md` | auth-server 箱・JWT/JWKS/ToS/Friendship のビジョン |
| engine 連合方針（v1） | `architecture/federation.md` | Phase 4 identity federation・`auth/` をホーム IdP とする |
| **auth ↔ engine 契約** | `.workspace/0_docs/` | RS256・iss/aud・JWKS・失効モデル・engine 検証チェックリスト（**実装済み寄り**） |
| auth 内部 hardening | `.workspace/3_done/` 等 | セッション・レート制限・アカウントライフサイクル（サービス固有） |

洗い出しで A1 を「追加」としたのは **engine の `architecture/` ツリーに正本が無い** からであり、**auth 側に文書が無いからではない**。

### 8.2 v2 図と既存契約のギャップ（統合時に埋める）

| 項目 | v2 overview 図 | jwt-jwks-engine-contract | 統合時の扱い |
|:---|:---|:---|:---|
| RS256 / JWKS / `sub` UUID | あり | **正本あり** | 契約を正とする |
| Remember Me / Refresh（7日） | あり | 契約本文は access TTL・refresh 詳細は別 plan 参照寄り | auth 実装 docs を突合して追記 or リンク |
| ToS（tos_version） | あり | 未記載 | v2 ビジョン → 契約 or auth ドメイン docs へ昇格 |
| Friendship / グループ | あり | 未記載 | 同上 |
| Stage SQLite→PostgreSQL | あり | 未記載（Ash DataLayer は実装側） | auth 運用 docs へ |
| engine の room_token + Bearer | 図は Room Token 発行を world-server 側に記載 | engine チェックリストあり（AUTH_REQUIRED） | world-server / federation と相互リンク |

### 8.3 統合オプション — **案 B 採用（2026-10-23）**

**結論**: **B（索引＋契約は既存パスに残す）**。サービス固有の hardening は auth に置き、プラットフォーム横断の「見え方」だけ engine の architecture-v2 に寄せる。正本: [auth-server.md](auth-server.md)。

| 案 | 内容 | 長所 | 短所 |
|:---|:---|:---|:---|
| **A. 移設** | 契約を architecture-v2 へ移動 | engine で一覧しやすい | auth 単体の導線が弱る |
| **B. 索引（採用）** | 薄い索引＋契約は `.workspace/0_docs/` のまま | 保証の単位＝フォルダを維持 | 詳細がワンホップ先 |
| **C. 複製** | 両方に全文 | 単体閲覧は楽 | すぐ乖離。非推奨 |

### 8.4 統合後にやる最小セット（案 B 前提）

1. `architecture-v2/auth-server.md` を新設し、overview の Auth 箱・federation の identity federation・jwt-jwks 契約を相互リンク。
2. v1 `federation.md` / v2 overview から上記へリンク（パス表記を `auth/` → `auth-server` に揃える）。
3. §8.2 のギャップ（ToS / Friendship / Refresh）を「契約に昇格」か「v2 ビジョンのまま」か決める。
4. A1 の分類を「追加」から **既存・分散 (sibling) → 索引で architecture-v2 に接続** へ更新する。

---

## 関連

- [v2 overview（目標図）](overview.md)
- [v1 overview（現行正本）](../architecture/overview.md)
- [vision-goal.md](../vision-goal.md)
- [auth: JWT/JWKS engine 契約](../jwt-jwks-engine-contract.md)
- [v1 federation（auth 断片）](../architecture/federation.md)
- [authoritative-state-sync-policy.md](../architecture/authoritative-state-sync-policy.md)（C1/C12 本文化先）
