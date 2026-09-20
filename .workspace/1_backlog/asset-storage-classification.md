# アセット格納先の区分設計

> 作成日: 2026-03-04  
> 目的: 画像データなど著作物を含むアセットの格納先を、所有権・共有範囲で分類する方針を定義する。キャッシュ・暗号化の設計において参照する。

---

## 区分の定義

| 区分 | 説明 | アクセス範囲 |
|:---|:---|:---|
| **LocalAssets** | ユーザー個人の資産。誰からも干渉されない。 | 当該ユーザーのみ |
| **LocalShareAssets** | ユーザー個人が管理する共有資産。URL を発行して参照できる。 | URL 保有者 |
| **GroupAssets** | グループの資産。グループ以外から干渉されない。 | グループメンバーのみ |
| **GroupShareAssets** | グループが管理する共有資産。URL を発行して参照できる。 | URL 保有者 |

---

## 設計方針

- **著作物への配慮**: 画像データなど著作物が含まれるため、キャッシュ・暗号化周りは慎重に設計する。
- **契約の明確化**: 各コンテンツの `assets_path/0` は常に文字列を返す。`nil` は使用しない。
- **区別の意味**:
  - `""` — 共通 LocalAssets（ゲーム固有サブディレクトリなし）
  - `"vampire_survivor"` など — ゲーム固有の LocalAssets サブディレクトリ

---

## assets_path/0 の契約

| 戻り値 | 意味 |
|:---|:---|
| `""` | 共通 LocalAssets を参照（SimpleBox3D, BulletHell3D, CanvasTest, RollingBall など） |
| `"vampire_survivor"` | 当該ゲーム固有の LocalAssets サブディレクトリを参照 |
| `"asteroid_arena"` | 同上 |

`ASSETS_ID` 環境変数へ渡す値として、Application 起動時に Elixir から注入する。

---

## 実現に必要なレイヤー（Google Drive 風）

Google Drive 風に「保存・共有・グループ管理」を実現するには、以下の 5 層を順に構築する。

| 層 | 責務 | 主な構成要素 |
|:---|:---|:---|
| **クライアント層** | アップロード・共有設定・閲覧 | Upload, Share, Browse UI |
| **API 層** | 認証・グループ・アセットメタデータ・共有リンクの API | AuthAPI, GroupAPI, AssetMetaAPI, ShareAPI |
| **データモデル層** | エンティティとリレーション | User, Group, Membership, AssetMetadata, ShareLink |
| **ストレージ層** | 実体の永続化 | R2 バケット / プレフィックス |
| **ロード層** | アセット取得 | AssetLoader（Rust） |

アクセス可否は Elixir の API 層で判定する。Rust の AssetLoader は「渡された URI を取得する」だけに徹する（層間インターフェース原則）。

---

## データモデル

### エンティティ定義

| エンティティ | 説明 | 主な属性 |
|:---|:---|:---|
| **User** | ユーザー（@user@instance） | id, instance_id |
| **Group** | 会社・チーム等の組織 | id, name, owner_user_id |
| **Membership** | グループへの所属 | group_id, user_id, role (admin/member/viewer) |
| **AssetMetadata** | アセットのメタデータ（実体は R2） | id, owner_type (user/group), owner_id, uri, storage_category, created_at |
| **ShareLink** | 共有リンク | id, asset_id, token, expires_at, scope (view/download) |

### 区分とモデルの対応

| 区分 | owner_type | owner_id | ShareLink の有無 |
|:---|:---|:---|:---|
| LocalAssets | user | user_id | なし |
| LocalShareAssets | user | user_id | あり |
| GroupAssets | group | group_id | なし |
| GroupShareAssets | group | group_id | あり |

---

## アクセス制御ルール

| アクション | LocalAssets | LocalShareAssets | GroupAssets | GroupShareAssets |
|:---|:---|:---|:---|:---|
| アップロード | 本人のみ | 本人のみ | メンバー（admin/member） | メンバー |
| 閲覧・参照 | 本人のみ | 本人 or 有効な ShareLink トークン保有者 | グループメンバーのみ | メンバー or トークン保有者 |
| 共有リンク発行 | 不可 | 本人 | 不可 | 管理者 |
| 削除 | 本人のみ | 本人のみ | 管理者 | 管理者 |

---

## ストレージ配置（R2 / ローカル）

[asset-cdn-design.md](asset-cdn-design.md) の URI スキームを拡張する形で、区分ごとにプレフィックスを割り当てる。

| 区分 | URI パターン（例） | R2 プレフィックス |
|:---|:---|:---|
| LocalAssets | `local://user/{user_id}/...` または CDN | `users/{user_id}/private/` |
| LocalShareAssets | 同上（ShareLink でトークン付き URL を発行） | `users/{user_id}/shared/` |
| GroupAssets | `local://group/{group_id}/...` | `groups/{group_id}/private/` |
| GroupShareAssets | 同上（ShareLink でトークン付き） | `groups/{group_id}/shared/` |

アクセス可否は Elixir の AssetMetadata + ShareLink で判定し、許可された場合のみ URI（必要に応じて Signed URL）をクライアントに渡す。

---

## 共有リンク

### URL 形式

```
https://assets.yourgame.com/s/{token}
```

- `token`: 予測困難なランダム文字列（UUID v4 や 256bit 乱数の Base64url）
- DB で `ShareLink (token, asset_id, expires_at, scope)` を管理

### アクセスフロー

1. クライアントが `GET /s/{token}` をリクエスト
2. API が token で ShareLink を検索
3. 有効なトークン → AssetMetadata 取得 → R2 の Signed URL 発行 → 302 Redirect
4. 無効 or 期限切れ → 404

---

## 実装フェーズ

| フェーズ | 内容 | 前提 |
|:---|:---|:---|
| **Phase 1** | ユーザー認証基盤（JWT / セッション） | vision Phase 3 |
| **Phase 2** | User, Group, Membership の CRUD API | Phase 1 |
| **Phase 3** | AssetMetadata の CRUD、R2 アップロード API | Phase 1, asset-cdn-design の Phase A-2 完了 |
| **Phase 4** | ShareLink の発行・検証 API、Signed URL 発行 | Phase 3 |
| **Phase 5** | クライアント UI（アップロード・共有設定・ブラウズ） | Phase 4 |

---

## 残すべき検討事項

- **インスタンス跨ぎ**: グループは単一インスタンス内か、フェデレーション時に跨げるか
- **グループの階層**: 親子グループ（例: 事業部 > チーム）をサポートするか
- **ShareLink の詳細**: 閲覧のみ / ダウンロード可 / 編集可 などの scope をどこまで細かくするか
- **ストレージコスト**: ユーザー数増加に伴う R2 コスト見積もり
