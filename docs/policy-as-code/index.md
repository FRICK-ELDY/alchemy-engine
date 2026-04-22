# Policy as Code — Elixir x Rust の 責務と禁止事項

> このドキュメントは AI および開発者が守るべき方針を明文化する。  
> 設計判断・コードレビュー・リファクタリング時に参照し、以下の原則に反する実装を絶対に許容しない。

---

## ドキュメント構成

| ファイル | 対象 | 内容 |
|:---|:---|:---|
| [why_adopted/zenoh-frame-serialization.md](./why_adopted/zenoh-frame-serialization.md) | 採用理由 | Zenoh フレーム直列化（Erlang term） |
| [elixir.md](./elixir.md) | Elixir | 責務・禁止事項（**ドメイン**定義の SSoT、ワイヤは `.proto`、処理レート 10/20/30Hz） |
| [elixir_zenoh.md](./elixir_zenoh.md) | Elixir × Zenoh | ネットワーク・フレーム配信 |
| [nif.md](./nif.md) | NIF | ブロック・シリアライズ・呼び出し頻度 |
| [nif_rust_thread.md](./nif_rust_thread.md) | NIF × Rust スレッド | 責務分担・Dirty NIF・委譲 |
| [rust_client.md](./rust_client.md) | Rust クライアント | 描画・入力・DSP・予測補間・Zenoh 通信 |
| [contents/object.md](./contents/object.md) | Contents | 層の責務（Structs / Node / Component / Object） |
| [gaps/scale-and-gaps.md](./gaps/scale-and-gaps.md) | gaps | 大規模分散 VRSNS へのスケール・未整備事項 |

---

## まとめ（クイックリファレンス）

| 禁止事項 | 理由の要約 | 詳細 |
|:---|:---|:---|
| Elixir で演算 | BEAM はヒープ・型解決・GC で演算が遅い | [elixir.md](./elixir.md) |
| 責務の逆転 | SSoT と実行層の分離が崩れる | [elixir.md](./elixir.md) |
| Elixir で 60Hz を保証 | BEAM のオーバーヘッドでキュー詰まりのリスク | [elixir.md](./elixir.md) |
| Zenoh ハンドラで重い処理 | ライブネス・スケールの低下 | [elixir_zenoh.md](./elixir_zenoh.md) |
| NIF で長時間ブロック | スケジューラを止め、ライブネスを損なう | [nif.md](./nif.md) |
| 大きなバイナリを NIF で渡す | シリアライズコストが設計を破綻させる | [nif.md](./nif.md) |
| ループ内の高頻度 NIF 呼び出し | 境界越えコストが積み重なる | [nif.md](./nif.md) |
| NIF から描画・入力へ依存 | サーバー・クライアント分離の崩壊 | [rust_client.md](./rust_client.md) |

---

*このポリシーは [vision.md](../vision.md) およびアーキテクチャ設計と整合する。違反を検出した場合は修正を優先する。*
