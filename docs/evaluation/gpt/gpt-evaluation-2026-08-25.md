# AlchemyEngine GPT 総合評価レポート — 2026-08-25

評価者: GPT-5.6 Sol（第2評価者）  
対象: `engine/`、`auth/`、`assets/`  
検証commit: `8f35a57`（PR #347後、CI項目を再検証）  
前回: Fable 5（+185 / -96 / 総合 +89）

## 採点基準

### 加点・減点

| 点数 | プラス | マイナス |
|:---:|:---|:---|
| 1 | 正しく実装 | 軽微な改善余地 |
| 2 | ベストプラクティス | 重要機能・設計の欠如 |
| 3 | 同種平均を明確に上回る | バグ・性能劣化を起こしうる欠陥 |
| 4 | production OSS水準 | 価値命題を損なう欠如 |
| 5 | 個人開発として卓越 | 根幹を揺るがす欠陥 |

## 総合スコア

### カテゴリ別

| 大分類 | プラス | マイナス | 小計 |
|:---|---:|---:|---:|
| プロジェクト全体 | +0 | -11 | **-11** |
| auth | +47 | -8 | **+39** |
| assets | +16 | -10 | **+6** |
| apps/core | +23 | -8 | **+15** |
| apps/contents | +21 | -15 | **+6** |
| apps/network | +26 | -17 | **+9** |
| apps/server | +4 | -3 | **+1** |
| rust/nif | +12 | -7 | **+5** |
| rust/client | +37 | -19 | **+18** |
| 横断評価層 | +17 | -11 | **+6** |
| ゲームプレイ完成度 | +12 | -10 | **+2** |
| **総合** | **+215** | **-119** | **+96** |

### 前回との差分

| 評価 | プラス | マイナス | 総合 |
|:---|---:|---:|---:|
| Fable 2026-07-31 | +185 | -96 | +89 |
| GPT 2026-08-25 | +215 | -119 | +96 |
| **差分** | **+30** | **-23** | **+7** |

> 差分は独立再採点を含む。PR #326〜#345と新assets serviceの加点は大きい。一方、room共有state、Elixir Zenoh再接続、OpenXR未配線、NIF error非対称、ゲームプレイ完成度を新規計上した。

## 総評

### 結論

**「防御機能・client表示品質・所有BLOBサービスは大きく前進し、CIもgreenへ復帰した。しかし“実装本体がある”ことと“出荷経路で成立する”ことを混同しており、マルチルーム・OpenXR・Zenoh運用・save/load統合は未完成である。」**

改善は、prod secret fail-fast、JWT/JWKS、UDP/Zenoh RoomToken、inflate limit、session timeout、Formula除算、snapshot補間、Rust Zenoh再接続に集中している。

新規 `assets/` は単一commitながら、Phoenix + Ash + local BLOB、auth JWKS、subject ownership、active CIまで備えた筋の良いMVPである。しかしengine `__save__` / `__load__` は未配線（`../assets/README.md:155-160`）で、BLOBとmetadataにもtransaction境界がない（`../assets/lib/assets/objects.ex:22-26,47-53`）。

ゲームプレイ面ではBulletHell3DとTetrisが完結loopを持つ。Tetrisはtitle/play/game over/retryと3D盤面/UIまである（`apps/contents/lib/contents/tetris/frame.ex:28-155`）。一方、残る3 contentは技術demoで、assetはaudio 6件 + atlas 1件、game別2 directoryは空である。エンジンdemoとしては有益だが、完成作品としてはprototype段階である。

## 主要加点

### 前進した領域

- **auth暗号・lifecycle** `+5`
  > multi-key RS256、refresh family reuse、credential変更時失効まで備える。
  > 対象ファイル: `../auth/lib/auth/token/keys.ex`
- **assets所有境界** `+4`
  > JWT subと `users/{sub}/private` prefixを強制する。
  > 対象ファイル: `../assets/lib/assets/path_policy.ex`
- **認証・UDP防御vertical slice** `+4`
  > JWT→RoomToken→transport検証、inflate limit、timeoutまで一貫する。
  > 対象ファイル: `apps/network/lib/network/room_auth.ex`
- **snapshot interpolation** `+5`
  > adaptive delay、burst除外、playback clampを表示経路へ配線した。
  > 対象ファイル: `rust/client/shared/src/interp.rs`
- **BulletHell3D/Tetrisの完結loop** `+4`
  > 入力、進行、終了、再開、描画UIまで成立する。
  > 対象ファイル: `apps/contents/lib/contents/tetris/frame.ex`
- **Formula実バグ修正** `+4`
  > 型昇格/overflow修正と6 regression test。
  > 対象ファイル: `rust/nif/src/formula/vm.rs`

## 主要減点

### 保証と統合

- **CI再無効化を防ぐ強制力なし** `-2`
  > HEADはactive/greenだが、enable/ignore反復履歴がありrequired checks/branch protectionがない。
  > 対象ファイル: `.github/workflows/ci.yml`
- **単一SceneStackのマルチルーム** `-5`
  > roomごとのGameが同じscene stateを更新する。
  > 対象ファイル: `apps/contents/lib/contents/bullet_hell_3d.ex`
- **OpenXR未配線** `-4`
  > loop本体が通常app feature/runtimeへ入らない。
  > 対象ファイル: `rust/client/app/Cargo.toml`
- **Elixir Zenoh復旧なし** `-4`
  > server transportは切断後に自律回復しない。
  > 対象ファイル: `apps/network/lib/network/zenoh_bridge.ex`
- **assetsはengine未接続** `-4`
  > serviceは動いてもsave/load vertical sliceがない。
  > 対象ファイル: `../assets/README.md`
- **作品polish不足** `-3`
  > 実gameは2本、game別asset directoryは空。
  > 対象ファイル: `assets/README.md`

## 前回指摘の再検証

### 解消状況

| 前回指摘 | 判定 | 根拠 |
|:---|:---|:---|
| auth↔engine未接続 | **解消** | `AuthVerifier.verify/1` をrouterへ接続 |
| SECRET_KEY_BASE fail-fastなし | **解消** | `runtime.exs:32-42` |
| UDP/Zenoh無認証 | **条件付き解消** | RoomTokenあり、AUTH既定false |
| zlib無制限 | **解消** | 64KiB streaming上限 |
| UDP session無期限 | **解消** | monotonic timeout sweep |
| 非main room未駆動 | **部分解消** | tickは全room、SceneStack共有 |
| contents→network直依存 | **解消** | publish MFA |
| Formula float除算 | **解消** | typed checked division |
| Rust NIF test 0 | **解消** | division 6 test |
| NIF命令上限なし | **未解消** | size/gasなし |
| 補間未配線 | **解消** | render bridgeでsample |
| Zenoh再接続なし | **client解消/server未解消** | Rustのみbackoff reconnect |
| OpenXR stub | **部分解消** | loop実装、app未配線 |
| client test CI外 | **未解消** | NIF testのみ |
| federation実装ゼロ | **部分解消** | signed read-only S2S |
| engine永続化なし | **service新設/未接続** | assets CRUDあり、wiringなし |

## 次の優先改善

### 費用対効果順

1. CIをrequired checks/branch protectionで固定し、client workspace testを追加する。
2. SceneStack/EventBus/Statsをroom subtreeへ移しstate isolation testを追加。
3. Elixir ZenohBridgeへsubscriber再宣言付きbackoff reconnectを実装。
4. Tetris save slotでengine→assetsをend-to-end配線。
5. OpenXRをapp feature/runtimeとnetwork encodeへ接続。
6. prod AUTHをfail-secure化しRoomTokenへsub/roleを伝播。
7. BulletHell3Dへwave/boss/item/build/save/専用assetを追加。
8. Formula NIFのerror tupleとsize/step上限を統一。

## 検証記録

### 実施内容

- 評価ルールとFable 2026-07-31文書を起点に現行sourceを再確認した。
- `8f35a57` で `elixir -S mix alchemy.ci` を再実行し、全gate PASS / exit 0（21秒）を確認した。
- PR #347差分を確認し、Credo閾値変更ではなく `room_auth.ex` / `s2s/*.ex` 等の関数抽出・分岐整理で修正したと判定した。
- NIF 6 test PASS / umbrella test PASSを再実行結果として確認した。
- `assets/` はpath policy、token verifier、controller、Objects/storage、README、CI、3 test files/12 casesを確認した。
- gameplayは5 contentと `engine/assets/` の実ファイルを確認した。
- Rust構成は `rust/Cargo.toml:3-15` を正とした。

## 詳細文書

### 出力

- `docs/evaluation/gpt/gpt-specific-strengths-2026-08-25.md`
- `docs/evaluation/gpt/gpt-specific-weaknesses-2026-08-25.md`
- `docs/evaluation/gpt/gpt-specific-proposals-2026-08-25.md`
- `docs/evaluation/gpt/gpt-evaluation-2026-08-25.md`
