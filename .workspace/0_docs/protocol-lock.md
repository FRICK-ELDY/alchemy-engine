# プロトコル（`.proto`）ロック

[alchemy-protocol](https://github.com/FRICK-ELDY/alchemy-protocol) の **推奨リビジョン**です。スーパープロジェクトでは submodule **`protocol/`** にピンします（ビルド必須ではない。再生成・閲覧用）。

実行コード（`world-server` 等）は **生成物をコミット**してビルドする方針です。日常ビルドは親の `protocol/` や旧 `3rdparty/` に依存しません。詳細は [実施計画](../2_todo/alchemy-engine-superproject-and-world-server-plan.md)。

| 項目 | 値 |
|:---|:---|
| **親内パス** | `protocol/`（リモート [alchemy-protocol](https://github.com/FRICK-ELDY/alchemy-protocol)） |
| **Git タグ** | `v0.1.2` |
| **コミット SHA** | `84278a8a6f51fe559263b36a1d5dae9c9a731504` |
| **タグ付きツリー** | [github.com/FRICK-ELDY/alchemy-protocol @ `v0.1.2`](https://github.com/FRICK-ELDY/alchemy-protocol/tree/v0.1.2) |
| **world-server の `3rdparty` との関係** | `proto/` 内容は上記タグと **一致**（2026-09-23 確認）。段階 B で `3rdparty` は廃止予定 |

## 親でピンを上げるとき

1. `protocol/` で目的のタグまたはコミットを checkout する。  
2. 親で `git add protocol` してコミットする。  
3. **本ファイル**の表を更新する。  
4. 生成物追従は **world-server（将来 client）側の PR**で行う（`PROTO_ROOT` に本ツリーの `proto/` を明示して `mix alchemy.gen.proto` 等）。親パスを子のソースに焼き込まない。

## 再生成時の PROTO_ROOT 例

```bat
rem 親一式を clone している場合（人が明示する。コードの既定値にはしない）
set PROTO_ROOT=%CD%\protocol\proto
cd world-server
mix alchemy.gen.proto
```
