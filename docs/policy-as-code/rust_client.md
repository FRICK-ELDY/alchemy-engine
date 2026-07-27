# Policy: Rust クライアント — 描画・入力・DSP・予測補間・Zenoh 通信

[← index](./index.md)

> **表示時間**: クライアント描画は既定 ~60fps。**主時間は Elixir の権威 tick**（推奨 20Hz、設定で 10/30/非推奨 60）。Rust は主時間を補う予測・補間層である。正本: [authoritative-state-sync-policy.md](../architecture/authoritative-state-sync-policy.md)。

---

## 1. NIF はクライアント（描画・入力）に依存しない

**やってはいけないこと**: NIF（サーバー側）が `desktop_render` や `desktop_input` に依存すること。NIF 内でウィンドウ・GPU・入力デバイスに直接アクセスすること。

**理由**:

- サーバーとクライアントは責務が異なる。サーバーはヘッドレスで動作し、複数クライアントをサポートする
- 分散型 VRSNS ではクライアント分離が前提
- 二重経路（NIF ローカル / Zenoh リモート）の維持コストを排除するため

**やるべきこと**: サーバー・クライアント間の通信は **Zenoh のみ**。サーバー NIF は Formula VM 等の軽量境界に留め、描画・入力は別プロセスのクライアントが担当する。詳細は [nif-desktop-separation.md](../policy/nif-desktop-separation.md) を参照。

---

## 2. クライアントは Zenoh でフレームを受信する

**やってはいけないこと**: クライアントが NIF 経由で直接フレームデータを取得すること。

**やるべきこと**: フレームは Elixir が権威 tick に合わせて Zenoh 経由で publish し、Rust クライアントは subscribe して受け取る。同一マシン・リモート問わず同じ経路を用いる。配信レートは主時間（推奨 20Hz）に揃える。

---

## 3. 描画・入力・DSP・予測補間はクライアント側の Rust スレッドで行う

**やってはいけないこと**: 描画ループ・入力ポーリング・音声再生・予測補間を Elixir 側やサーバー側で制御すること。受信スナップショットを補間せずに「表示＝権威 Hz」のままにすること（カクつきの固定化）。

**やるべきこと**:

- **描画・入力**: `desktop_render`（wgpu）・`desktop_input`（winit）は Rust のネイティブループで表示レート（既定 ~60fps）に合わせて動作する
- **DSP**: 音を鳴らすのはクライアント（スピーカーがクライアント側にあるため）。サーバーは「いつ何を再生するか」の同期のみ担当（[audio-responsibility.md](../policy/audio-responsibility.md)）
- **予測・補間**: 権威 tick（推奨 20Hz 等）の間を埋め、遅延を隠す。**これが主時間契約のクライアント側の本体**（[render-interpolation.md](../policy/render-interpolation.md)）。公式状態のコミットは行わない
- **権威**: 式・ルール・確定状態はサーバー（Elixir／必要なら Formula NIF）。クライアント予測はサーバ確定で上書き・和解する
