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
| `""` | 共通 LocalAssets を参照（VRTest, SimpleBox3D, BulletHell3D, CanvasTest, RollingBall など） |
| `"vampire_survivor"` | 当該ゲーム固有の LocalAssets サブディレクトリを参照 |
| `"asteroid_arena"` | 同上 |

`GAME_ASSETS_ID` 環境変数へ渡す値として、Application 起動時に Elixir から注入する。
