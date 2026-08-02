# alchemy-assets サービス＋engine 永続化 実施計画書

> 作成日: 2026-08-02  
> 目的: `auth/` に並ぶ `Assets/`（alchemy-assets）を新設し、ユーザー所有ストレージ上のセーブデータを本線とする engine 永続化（fable 改善 3-6）を段階実装する。  
> 方針決定: セーブの**所在**は User の LocalAssets。**権威**は engine。まず Assets サービス骨格から着手する。

---

## 1. 概要

### 1.1 達成したいこと

| 項目 | 内容 |
|:---|:---|
| **Assets サービス新設** | リポジトリルートに `auth/` と同列の `Assets/`（alchemy-assets）を作成 |
| **ユーザー所有セーブ** | `users/{user_id}/private/Save/{content_id}/save.NNN` にセーブ実体を置く |
| **`__save__` / `__load__` 配線** | engine が権威スナップショットを生成し、Assets API 経由で読み書きする |
| **3-6 の段階解消** | 永続化層の不在（`-2`）を、セーブ経路から解消し、後続でルーム揮発性も扱う |

### 1.2 背景（なぜこの順か）

評価の「永続化層の不在」は次を含む。

1. `__save__` / `__load__` が意図的 no-op（`network TBD`）
2. ルーム再起動で状態初期化、FormulaStore synced が ETS のみ
3. VRSNS としてワールド・アバター等の永続データの置き場がない

本計画は **(1) をユーザー所有ストレージで本線化**することから始める。  
(2)(3) は Assets 骨格の後続フェーズとする（§5）。

`auth/README.md` は既に「alchemy-assets（予定）」を関連リポジトリとして記載しており、本計画はその実装着手書である。

### 1.3 スコープ外（本計画ではやらない）

| 項目 | 理由 |
|:---|:---|
| スプライト・音声の CDN 本番配信 | [asset-cdn-design.md](asset-cdn-design.md) の別フェーズ。MVP はローカル／単一バケットで可 |
| GroupAssets / ShareLink 一式 | [asset-storage-classification.md](asset-storage-classification.md) Phase 4 相当。Save は LocalAssets のみ |
| ワールド・アバター・フレンドグラフのフルモデル | fable 提案の Ash 活用は後続（§5.3） |
| クライアントからの任意バイナリ直書きセーブ | 改ざんリスク。書き込みは engine 権威のみ |
| デモ当日の必須化 | 2026-08-27 お披露目は auth オフ本線。Assets 連携は切替可能にする |

---

## 2. 責務境界

```
┌─────────────────┐     JWT (Bearer)      ┌─────────────────┐
│  alchemy-engine │ ◄──────────────────── │  alchemy-auth   │
│  (権威スナップ)  │     JWKS 公開鍵参照    │  (Identity SSoT) │
└────────┬────────┘                       └────────┬────────┘
         │ HTTPS（サービス間 or ユーザー代理）        │
         ▼                                         │
┌─────────────────┐     JWT sub = owner            │
│ alchemy-assets  │ ◄──────────────────────────────┘
│ (メタ + BLOB)   │
└─────────────────┘
```

| サービス | 責務 | 担わないもの |
|:---|:---|:---|
| **auth** | ユーザー ID（JWT `sub`）、ログイン | セーブ実体・ゲーム状態 |
| **Assets** | アセットメタデータ、BLOB 格納、所有権チェック | ゲームロジック・ルーム進行 |
| **engine** | セーブ対象の決定、スナップショット生成／適用、検証 | ユーザーパスワード・永続 BLOB の主保管 |

### 2.1 所在と権威

| 層 | 役割 |
|:---|:---|
| **所在（Assets）** | 実体をユーザー領域に置く |
| **権威（engine）** | 誰のセーブか・いつ・どの版か・改ざん可否を決める |
| **配線** | `__save__` → スナップショット → Assets 書込 ／ `__load__` → 検証 → ルーム適用 |

---

## 3. データ・パス規約

### 3.1 論理パス（ユーザー向けイメージ）

```
Assets / {user} / Save / {content_id} / save.001
```

### 3.2 ストレージプレフィックス（実装正）

[asset-storage-classification.md](asset-storage-classification.md) の LocalAssets に合わせる。

```
users/{user_id}/private/Save/{content_id}/save.{slot}
```

| 要素 | 例 | 説明 |
|:---|:---|:---|
| `user_id` | JWT `sub`（UUID） | auth のユーザー ID |
| `content_id` | `bullet_hell_3d` 等 | コンテンツ識別子（`assets_path/0` 相当と整合） |
| `slot` | `001`〜`NNN` | セーブスロット。初期は固定桁 |

### 3.3 セーブオブジェクト契約（MVP 案）

| 項目 | 方針 |
|:---|:---|
| 形式 | JSON または MessagePack（初期は JSON 可） |
| 必須フィールド | `schema_version`, `content_id`, `user_id`, `created_at`, `payload` |
| 改ざん対策 | engine が HMAC または署名付きダイジェストを付与し、load 時に検証 |
| サイズ上限 | 要決定（例: 1 MiB）。Assets API で拒否 |
| スロット数 | MVP: コンテンツあたり 1〜3 |

`payload` の中身（どのゲーム状態を含めるか）はコンテンツ／共通レイヤの ADR で確定する（§6）。

---

## 4. 実施フェーズ

### Phase 0: ADR・契約の固定（半日〜1日）

- [ ] オンライン永続化 ADR を起草（所在＝Assets LocalAssets、権威＝engine）
- [ ] engine ↔ Assets の API 契約（パス・認証・エラーコード）を 1 枚にまとめる
- [ ] `content_id` / スロット / スキーマ版の命名を確定

**完了条件**: ADR 草案がレビュー可能。実装フェーズに未決事項が残らない。

---

### Phase 1: `Assets/` サービス骨格（3〜5日）

auth と同型の Elixir/Phoenix + Ash（または同等）サービスを `Assets/` に新設する。

- [ ] リポジトリ／ディレクトリ作成（`mix phx.new` 系、auth を雛形に）
- [ ] PostgreSQL + Ash: `AssetMetadata`（最小）
  - `id`, `owner_user_id`, `storage_category`（`local_private`）, `logical_path`, `uri`, `byte_size`, `content_type`, timestamps
- [ ] ストレージアダプタ（MVP: ローカルディスク。将来 R2 に差し替え可能な behaviour）
- [ ] JWT 検証（auth JWKS）。`sub` と `owner_user_id` の一致を強制
- [ ] MVP API

| Method | Path | 認証 | 説明 |
|:---|:---|:---|:---|
| `PUT` | `/api/v1/objects/*path` | Bearer | 本人の LocalAssets へ書込 |
| `GET` | `/api/v1/objects/*path` | Bearer | 本人のみ読取 |
| `DELETE` | `/api/v1/objects/*path` | Bearer | 本人のみ削除 |
| `GET` | `/api/v1/objects?prefix=` | Bearer | プレフィックス一覧（Save スロット列挙用） |
| `GET` | `/health` | なし | 疎通 |

- [ ] パス検証: `..` 拒否、`users/{sub}/private/` プレフィックス強制
- [ ] Docker Compose（dev）と README（責務・非責務を auth と同粒度で）
- [ ] 単体／統合テスト（所有権不一致は 403、パストラバーサル拒否）

**完了条件**: JWT 付きで Save パスへ put/get できる。他ユーザー領域は拒否される。

---

### Phase 2: engine → Assets クライアント（2〜3日）

- [ ] engine に Assets HTTP クライアント（設定: `ASSETS_BASE_URL`、既定オフまたは dev ローカル）
- [ ] 環境変数切替（例: `ASSETS_PERSISTENCE=off|on`）。オフ時は現行どおりログのみ
- [ ] サービス間呼び出し方針の確定（下記どちらかを ADR で選ぶ）
  - **A（推奨 MVP）**: engine がユーザー JWT（または短命委譲トークン）を受け取り、Assets に代理 PUT/GET
  - **B**: engine サービス資格情報 + `X-On-Behalf-Of: user_id`（要追加認可）

**完了条件**: engine からテスト用バイト列を Assets のユーザー Save パスへ往復できる。

---

### Phase 3: `__save__` / `__load__` 本線化（3〜5日）

対象: `engine/apps/contents/lib/events/game.ex` ほか

- [ ] `__save__`: ルーム／コンテンツ状態から権威スナップショットを組み立て → Assets PUT
- [ ] `__load__` / `__load_confirm__`: Assets GET → 検証 → 状態適用（確認 UI フローは既存アクション名を維持）
- [ ] プレイヤー ID（JWT `sub`）とセーブ `user_id` の一致チェック
- [ ] スキーマ版不一致時の明示エラー（黙って壊さない）
- [ ] テスト: save → load で状態が復元される／改ざんペイロードは拒否

**完了条件**: `ASSETS_PERSISTENCE=on` 時、UI アクション経由でセーブ／ロードが機能する。オフ時は従来動作。

---

### Phase 4: 運用最低限＋評価点の確認（1〜2日）

- [ ] サイズ上限・レート制限の初期値
- [ ] ログ／メトリクス（save/load 成功・失敗理由）
- [ ] fable 改善計画 3-6 の記述を「セーブ経路実装済み／ルーム揮発は残」と更新可能な状態にする
- [ ] 関連ドキュメントへのリンク（overview 永続化節、auth README の alchemy-assets）

**完了条件**: ローカルで再現手順が README または docs に書かれている。

---

## 5. 後続フェーズ（本計画の直後〜別計画）

### 5.1 ルーム／FormulaStore の短寿命スナップショット

セーブとは別系統。ルームクラッシュ復元用。

- 初期: DETS / SQLite で engine ローカルでも可
- Assets に置く場合も「ユーザー Save」ではなくインスタンス／ルーム用プレフィックスを分ける

### 5.2 メディア Assets（音・画像）

- [asset-cdn-design.md](asset-cdn-design.md) / [asset-storage-classification.md](asset-storage-classification.md) に合流
- Save で固めたメタ＋ストレージ＋JWT 所有権を再利用

### 5.3 VRSNS 構造化データ

- ワールド定義・アバター・訪問履歴を Ash リソース化（engine 内 or Assets 隣接）
- 最小モデル: `users ↔ worlds ↔ visits`

---

## 6. 未決事項（Phase 0 で決める）

| 項目 | 候補 | メモ |
|:---|:---|:---|
| スナップショットに含める状態 | シーン／プレイヤー進捗／Formula store／スコア | コンテンツ共通ヘッダ＋コンテンツ固有 payload |
| engine→Assets 認可 | ユーザー JWT 代理 / サービス資格情報 | MVP は代理が単純 |
| ストレージ実体 | ローカル FS → R2 | behaviour で隠蔽 |
| 競合（同時 save） | last-write-wins + `updated_at` / 楽観ロック | オンライン前提で必須 |
| オフラインセーブ | 当面なし | クライアント直書きは禁止を維持 |
| リポジトリ形態 | monorepo 内 `Assets/` / 独立 git | auth と同じ並びを優先 |

---

## 7. 受け入れ条件（全体）

1. `Assets/` が起動し、auth JWT で本人の `Save/{content_id}/` のみ読み書きできる  
2. engine の `__save__` / `__load__` が切替オン時に Assets 経由で状態を永続・復元できる  
3. 他ユーザーのパス・パストラバーサル・改ざんペイロードは拒否される  
4. 切替オフ時は現行（ログのみ）を壊さない  
5. CDN／Group／Share なしでも Save MVP が完結する  

---

## 8. 実施順序サマリ

```
Phase 0  : ADR・API 契約 ──────────────────────── 半日〜1日
Phase 1  : Assets/ 骨格（メタ + ローカル BLOB + JWT）── 3〜5日
Phase 2  : engine Assets クライアント + 切替 ─────── 2〜3日
Phase 3  : __save__ / __load__ 本線化 ───────────── 3〜5日
Phase 4  : 運用最低限・ドキュメント ─────────────── 1〜2日
────────────────────────────────────────────────
後続     : ルーム揮発対策 / メディア CDN / VRSNS モデル
```

---

## 9. 関連ドキュメント

| 文書 | 関係 |
|:---|:---|
| [fable-improvement-plan.md](../0_reference/fable-improvement-plan.md) §3-6 | 評価上の親タスク（`-2`） |
| [fable-specific-weaknesses.md](../../docs/evaluation/fable-specific-weaknesses.md) | 永続化層不在の根拠 |
| [fable-specific-proposals.md](../../docs/evaluation/fable-specific-proposals.md) | アバター・ワールド永続（後続） |
| [improvement-plan.md](../0_reference/improvement-plan.md) D-2 | オンライン永続化 ADR |
| [asset-storage-classification.md](asset-storage-classification.md) | LocalAssets 区分・プレフィックス |
| [asset-cdn-design.md](asset-cdn-design.md) | URI／CDN（メディア後続） |
| [architecture/overview.md](../../docs/architecture/overview.md) | 永続化節（現状未実装） |
| `auth/README.md` | alchemy-assets 予定の記載元 |

---

## 10. 次の遷移

- 課題の目的・スコープ・受け入れ条件は本計画で定義済み  
- 着手時は `2_todo` へ移動し、Phase 0（ADR）から開始する  
- 実装開始時は Agent モードで `Assets/` スケルトン作成に進む
