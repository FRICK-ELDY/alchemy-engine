# 方針: 連合層アーキテクチャ

> 作成日: 2026-07-13  
> ステータス: 採用（設計方針。連合 API の実装は Phase 4。Phase 1–3 は本書の制約に従う）  
> 背景: 分散連合型 VRSNS へ向け、スケールアウト層と連合層を分離して明文化する。

---

## 関連ドキュメント

| 文書 | 内容 |
|:---|:---|
| [vision-goal.md](../vision-goal.md) | 最終ゴール・Phase ロードマップ・コンテンツポリシー |
| [overview.md](./overview.md) | 現行サーバー／クライアント構成 |
| [authoritative-state-sync-policy.md](./authoritative-state-sync-policy.md) | 権威ある状態・入力・同期レート |
| [policy-as-code/federation-constraints.md](../policy-as-code/federation-constraints.md) | Phase 1–3 で守る実装制約 |
| [policy-as-code/gaps/scale-and-gaps.md](../policy-as-code/gaps/scale-and-gaps.md) | スケール上の未整備事項 |

---

## 1. 二層モデル

AlchemyEngine の「分散」には **性質の異なる二層** がある。混同しない。

```
┌─────────────────────────────────────────────────────────────┐
│  連合層（運営者間）              Phase 4 で本格実装・現状未実装    │
│  - インスタンス設定（ドメイン・S2S 公開鍵）                        │
│  - 署名付き HTTP（S2S API）                                   │
│  - WebFinger / リモート Actor 解決（方針未決）                   │
│  - identity federation（ホーム JWKS を訪問先が検証）              │
│  - コンテンツメタデータ同期 + ステータスによるフィルタ              │
│  - クロスインスタンス入室（リアルタイム経路は別プロトコル）           │
└─────────────────────────────────────────────────────────────┘
                            ↕
┌─────────────────────────────────────────────────────────────┐
│  スケールアウト層（単一運営者内）     現状ここまで実装あり           │
│  - libcluster + `:rpc`                                       │
│  - `Network.Distributed`（ルームのノード配置・RPC ブロードキャスト） │
│  - Zenoh / UDP / Phoenix（同一デプロイ／クラスタ内のリアルタイム）   │
└─────────────────────────────────────────────────────────────┘
```

| 層 | 誰のサーバか | 典型技術 | 現状 |
|:---|:---|:---|:---|
| **スケールアウト層** | 同一運営者の BEAM クラスタ | libcluster, `Network.Distributed`, Zenoh | 基盤あり（デフォルトは単一ノード） |
| **連合層** | 別運営者のインスタンス同士 | S2S HTTP, JWKS, （将来）ActivityPub ハイブリッド | **未実装** |

---

## 2. 用語

| 用語 | 意味 |
|:---|:---|
| **サーバインスタンス** | `alchemy.{domain}` で運用される配備単位（Mastodon のインスタンスと同義） |
| **実行単位**（`{instance_id}`） | 1 コンテンツ上のルーム／セッション／マッチ等。URL パス上の ID。**サーバインスタンスとは別** |
| **ホームインスタンス** | ユーザーアカウントが属するインスタンス（`@user@alchemy.home.com`） |
| **ホストインスタンス** | クロスインスタンス入室時に、リアルタイムセッションを権威的にホストする側 |

---

## 3. Phase 4 実装ロードマップ（段階的）

Phase 4 では一括でフル ActivityPub を目指さず、**相互参照が成立する最小単位**から積み上げる。

### 4-1. インスタンス自己記述

各デプロイが持つ設定（リソース化）:

- カノニカル URL: `https://alchemy.{domain}.{TLD}`
- S2S 用インスタンス公開鍵（署名・検証）
- 受け入れるコンテンツステータス上限（`General` … `Explicit`）
- （任意）フェデレーション許可リスト / ブロックリスト

### 4-2. read-only S2S（第一マイルストーン）

署名付き HTTP で他インスタンスのメタデータを取得する。

例（案）:

```
GET https://alchemy.some-studio.com/api/s2s/worlds
Authorization: Signature ...（呼び出し元インスタンスの署名）
```

- ワールド／コンテンツ一覧、タイトル、ステータス、サムネ URL 等
- **リアルタイム入室はまだしない**が、Hub に「連合先のコンテンツ」が載り始める

### 4-3. identity federation（訪問トークン）

1. ユーザーは **ホーム** の auth（`auth/` サービス）でログイン
2. リモート参加時、ホーム発行の JWT（または短命訪問トークン）を提示
3. **訪問先** engine が、ホームの `/.well-known/jwks.json` で検証
4. 訪問先の `POST /api/room_token` は検証済み `@user@home` にスコープした room token を発行

**横断インターフェース**（engine ↔ auth）:

| コンポーネント | Phase 3 まで | Phase 4 以降 |
|:---|:---|:---|
| `auth/` | RS256 JWT + JWKS（単体 IdP） | 連合内のホーム IdP として機能 |
| `Network.Router` `POST /api/room_token` | 現状は無認証で発行可能 | Bearer JWT 必須 → 訪問先検証へ拡張 |
| `Network.RoomToken` | 単一デプロイの秘密鍵 | ホーム／訪問先の役割を区別できる設計へ |

### 4-4. コンテンツポリシー・フィルタリング

[vision-goal.md](../vision-goal.md) のタグ／ステータス／インスタンスポリシーを S2S 同期時に適用する。

- **受信側インスタンスのポリシー**でフィルタ（送信側ではなく観測側が決める）
- Hub のリモート一覧・検索結果に反映

### 4-5. クロスインスタンス入室

リアルタイム同期は連合層の HTTP だけでは足りない。方針（未決・[vision-goal.md](../vision-goal.md) 参照）:

| 案 | 概要 |
|:---|:---|
| **A: ホスト権威** | ホストインスタンスで演算し、クライアントは Zenoh 等でストリーミング受信 |
| **B: 決定論的** | 各クライアントが同一入力列でローカル演算（Formula VM 等との整合が必要） |

**プロトコル**: メタデータは ActivityPub 互換または独自 S2S、リアルタイムは Zenoh／独自バイナリの **ハイブリッド** を想定。ワイヤ契約の SSoT は [alchemy-protocol](https://github.com/FRICK-ELDY/alchemy-protocol) の `proto/` に追加する。

---

## 4. Phase 1–3 の設計制約（連合を阻害しない）

Phase 4 以前に連合 API を実装しなくてよいが、以下は守る。詳細は [federation-constraints.md](../policy-as-code/federation-constraints.md)。

| やる | やらない |
|:---|:---|
| ユーザー ID を将来 `@user@host` で表現できる抽象にする | ローカル整数 ID だけを永続的なグローバル ID とみなす |
| auth JWT → room token の検証パイプラインを差し替え可能にする | room token を「単一デプロイ永久秘密」前提だけで設計する |
| コンテンツメタデータにステータス欄を載せられる分離を意識する | 連合フィルタ不能なメタデータ構造に固定する |
| `Network.Distributed` を単一運営者内の層として維持する | libcluster を「連合」の代替とみなして設計を止める |
| engine core にインスタンス固有の暗黙前提を埋め込まない | ドメイン名・ポリシーをコードにハードコードする |

---

## 5. 現状の実装との対応

| 項目 | モジュール／設定 | 連合層との関係 |
|:---|:---|:---|
| クラスタ内ルーム分散 | `Network.Distributed`, `config :libcluster` | スケールアウト層。連合ではない |
| リアルタイム配信 | Zenoh, UDP, Phoenix Channel | 同一インスタンス（または同一クラスタ）内 |
| ルームトークン | `Network.RoomToken`, `Network.Router` | Phase 3 で auth 接続、Phase 4 で訪問検証へ |
| 認証サービス | `auth/`（別リポジトリ） | Phase 4 の identity federation の起点 |
| ActivityPub / WebFinger / S2S | — | **ソース上ゼロ**（Phase 4 着手前） |

---

## 6. 設計決定（確定したもの）

（未解決の問いが決まり次第、 [vision-goal.md](../vision-goal.md) から移設する）

| 決定 | 内容 | 日付 |
|:---|:---|:---|
| 二層分離 | スケールアウト層と連合層を別物として設計・文書化する | 2026-07-13 |
| Phase 4 で連合本格実装 | Phase 1–3 は連合 API なし。制約のみ守る | 2026-07-13 |
| S2S の第一歩 | read-only 署名付き HTTP（ワールド一覧）から開始 | 2026-07-13 |

---

## 7. 未解決（技術）

[vision-goal.md](../vision-goal.md) の「未解決の問い」と同期する。主な技術論点:

- クロスインスタンス入室時の権威ホスト（案 A / B）
- ActivityPub 完全互換 vs 独自プロトコル vs ハイブリッド
- アバター・所持品の連合間持ち込み
- セッション管理（複数インスタンス跨ぎ）

---

*本書は連合の技術正本である。戦略・プロダクト像は [vision-goal.md](../vision-goal.md)、エンジン単体の保証は [vision.md](../vision.md) を参照する。*
