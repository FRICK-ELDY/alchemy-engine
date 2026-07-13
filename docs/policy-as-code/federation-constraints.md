# Policy as Code — 連合を意識した Phase 1–3 制約

> Phase 4 で連合層を本格実装するまで、**連合 API は書かない**が、以下の制約に反する変更を engine / network / contents に入れない。  
> 技術背景: [architecture/federation.md](../architecture/federation.md)  
> 戦略: [vision-goal.md](../vision-goal.md)

---

## 適用範囲

- **対象**: Phase 1–3 のすべての PR（engine umbrella、関連する auth 接続）
- **除外**: Phase 4 用の feature ブランチで明示的にマークされた連合モジュール

---

## 制約一覧

### アイデンティティ

| 制約 | 理由 |
|:---|:---|
| 永続的なユーザー識別子を **ローカル整数のみ** に固定しない | 将来 `@user@alchemy.home.com` 形式が必要 |
| ルーム参加・セーブ等に **グローバルに意味のない** 一時 ID だけを焼き込まない | クロスインスタンスで同一人物を追跡できなくなる |
| auth の subject / user id を engine が解釈できる境界を **`network` 層に集約**する | 各コンテンツが独自に auth を解釈すると連合時に破綻する |

### トークン・認証

| 制約 | 理由 |
|:---|:---|
| `POST /api/room_token` の発行ロジックを **差し替え可能**（プラグ／behaviour）に保つ | Phase 3 で JWT 必須化、Phase 4 で訪問先 JWKS 検証へ拡張 |
| room token のペイロードに **room スコープ以外** を載せる場合は拡張可能な map 構造にする | 訪問者の `@user@host` クレーム追加に備える |
| UDP / Zenoh の入力経路を **永久に無認証** と設計しない | Phase 2–3 で RoomToken 適用予定（[fable-improvement-plan.md](../../workspace/0_reference/fable-improvement-plan.md)） |

### コンテンツ・メタデータ

| 制約 | 理由 |
|:---|:---|
| コンテンツ公開用メタデータ（タイトル、作者、サムネ等）を **ゲーム状態と分離**して扱えるようにする | S2S 同期はリアルタイム状態ではなくメタデータから始める |
| コンテンツステータス（`General` … `Explicit`）を載せられる **フィールドまたは behaviour** を将来追加しやすい形にする | Phase 4 のポリシーフィルタ |
| Hub 一覧用 ID を **インスタンス内ローカル ID だけ** に依存しない設計を検討する | リモートコンテンツは `https://host/...` 形式の URI で指す |

### ネットワーク・スケール

| 制約 | 理由 |
|:---|:---|
| `Network.Distributed` / libcluster を **「連合の完成形」** と誤認するコメント・設計を書かない | 単一運営者内スケールアウトと連合は別層 |
| インスタンス固有のドメイン・ポリシーを **engine core** にハードコードしない | 設定リソース化（Phase 4-1）の前提 |
| リアルタイムプロトコル（Zenoh 等）を **インスタンス間 S2S の代替** とみなさない | メタデータ S2S とリアルタイムはハイブリッド |

### エンジン境界（vision.md との整合）

| 制約 | 理由 |
|:---|:---|
| 連合・インスタンス・フェデレーションの概念を **コンテンツ（`Content.*`）や engine core** に漏らさない | 連合は network / 将来の federation アプリの責務 |
| エンジンが保証するのは「空間・ユーザー・同期の器」まで | インスタンスポリシーは連合層 |

---

## レビュー時のチェック

PR で以下を確認する:

1. 新しい ID 型は将来の `@user@host` を阻害しないか
2. 認証・トークンが単一デプロイ前提だけに閉じていないか
3. libcluster / Distributed の変更を「連合対応」と説明していないか
4. コンテンツメタデータとゲーム状態が S2S 向けに分離可能か

---

## 関連

- [architecture/federation.md](../architecture/federation.md) — 二層モデル・Phase 4 ロードマップ
- [vision-goal.md](../vision-goal.md) — Phase 定義
- [gaps/scale-and-gaps.md](./gaps/scale-and-gaps.md) — スケール未整備
