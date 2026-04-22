# プロトコル（`.proto`）ロック

[alchemy-protocol](https://github.com/FRICK-ELDY/alchemy-protocol) を **意図しない追従から固定**するための記録です。サブモジュールの実体は **`3rdparty/alchemy-protocol`** です。

| 項目 | 値 |
|:---|:---|
| **Git タグ（レビュー用の人間可読名）** | `v0.1.1` |
| **コミット SHA（真のロック）** | `3abd65e1341c88b55fbc74bf3ec1cf9f42bad215` |
| **タグ付きツリー（GitHub）** | [github.com/FRICK-ELDY/alchemy-protocol @ `v0.1.1`](https://github.com/FRICK-ELDY/alchemy-protocol/tree/v0.1.1) |

## 追従するとき

1. `3rdparty/alchemy-protocol` で目的のタグまたはコミットをチェックアウトする。  
2. 親リポジトリで `git add 3rdparty/alchemy-protocol` してコミットする。  
3. **本ファイル**の表を、新しいタグ名・SHA・リンクに更新する。  
4. `mix alchemy.gen.proto` と Rust の `network` / `render_frame_proto` ビルド、関連 `mix test` で整合を確認する。

`PROTO_ROOT` で別パスを使うローカル開発では、上記ロックと異なるツリーになる場合があります。CI および共有ブランチではサブモジュール指し先を本ファイルと一致させる運用を推奨します。
