# Vision Correction Pass — 技術仕様書（Tech Spec）

> 作成日: 2026-03-03  
> 目的: 物理的な補正レンズを使用せず、ソフトウェアで視度（近視・遠視・乱視）を補正する「Vision Correction Pass」の設計・実装指針を定義する。  
> 参考: Xu et al., "Software Based Visual Aberration Correction for HMDs" (IEEE VR 2018)

---

## 1. 概要

### 1.1 背景

HMD（ヘッドマウントディスプレイ）において、ユーザーの屈折異常（近視・遠視・乱視）をソフトウェアのみで補正するため、**逆畳み込み（Deconvolution）による Pre-filtering** を適用する。

表示される画像を事前に「逆ボケ」フィルタで処理しておくことで、ユーザーの光学系（眼の屈折）を通過した結果、シャープな像が網膜に結像する。

### 1.2 開発環境

| 項目 | 技術スタック |
|:---|:---|
| 言語 | Rust / Elixir |
| グラフィックス / VR | OpenXR, Vulkan（または wgpu が使用するバックエンド API） |
| 目標フレームレート | 90 FPS 以上のリアルタイムポストプロセス |
| エンジン統合 | native/render（wgpu）、native/input_openxr |

---

## 2. Mathematical Model

### 2.1 光学モデル

観察される像 \( b \) は、理想的な画像 \( f \) と点広がり関数（PSF）\( h \) の畳み込みで近似される：

$$
b = f * h + n
$$

- \( b \): 網膜に結像する像（ぼけた像）
- \( f \): ディスプレイ上の理想画像
- \( h \): PSF（光学系のインパルス応答）
- \( n \): ノイズ
- \( * \): 畳み込み

**目標**: 事前に \( \tilde{f} = f * g \) を表示し、眼を通過した結果 \( \tilde{f} * h \approx f \) となるような **逆フィルタ \( g \)** を求める。

---

### 2.2 処方箋から PSF への変換

#### 2.2.1 処方パラメータ

| 記号 | 意味 | 単位 |
|:---|:---|:---|
| \( S \) | Sphere（球面度数） | D（ジオプトリ） |
| \( C \) | Cylinder（円柱度数） | D |
| \( \alpha \) | Axis（乱視軸） | 度（°） |

- **近視**: \( S < 0 \)
- **遠視**: \( S > 0 \)
- **乱視**: \( C \neq 0 \)、軸 \( \alpha \) で方向が決まる

#### 2.2.2 Power Vector 表現

Thibos らに従い、処方箋をパワーベクトル \((M, J_0, J_{45})\) に変換する：

$$
\begin{aligned}
M &= S + \frac{C}{2} \\
J_0 &= -\frac{C}{2} \cos(2\alpha) \\
J_{45} &= -\frac{C}{2} \sin(2\alpha)
\end{aligned}
$$

ここで \( \alpha \) は度数法（°）であり、ラジアンへの変換 \( \alpha_{\mathrm{rad}} = \alpha \cdot \pi / 180 \) を用いる。

#### 2.2.3 波面誤差と PSF

波面 aberrations は Zernike または Seidel  aberrations でモデル化し、幾何光学的 PSF を得る。簡易モデルとして、**ガウシアン PSF** を採用する：

近視・遠視のみ（\( C = 0 \)）の場合：

$$
h(x, y) = \frac{1}{2\pi\sigma^2} \exp\left(-\frac{x^2 + y^2}{2\sigma^2}\right), \quad \sigma \propto |S|
$$

乱視を含む場合、主経線に沿った異なる \( \sigma_x, \sigma_y \) を用いた楕円ガウシアン：

$$
h(x, y) = \frac{1}{2\pi\sigma_x\sigma_y} \exp\left(-\frac{x'^2}{2\sigma_x^2} - \frac{y'^2}{2\sigma_y^2}\right)
$$

\( (x', y') \) は \( \alpha \) で回転した座標系。

**スケール係数**  
ピクセル単位の \( \sigma \) は、ディスプレイの解像度・視野角・瞳孔径・眼球モデルから決める。実装時は経験的なキャリブレーション係数 \( k \) を導入し、

$$
\sigma_{\mathrm{px}} = k \cdot |S| \quad \text{（球面成分）}
$$

とする。

---

### 2.3 逆フィルタの導出

#### 2.3.1 周波数領域での畳み込み

フーリエ変換を用いると、

$$
\mathcal{F}\{b\} = \mathcal{F}\{f\} \cdot H + \mathcal{F}\{n\}
$$

\( H = \mathcal{F}\{h\} \) は OTF（Optical Transfer Function）である。

#### 2.3.2 Naive Inverse Filter

逆フィルタ \( G = 1/H \) とすると、

$$
\hat{F} = \frac{B}{H} = F + \frac{\mathcal{F}\{n\}}{H}
$$

\( |H| \) が小さい高周波でノイズが増幅され、**リンギング（Ringing）** が発生する。

#### 2.3.3 Wiener Filter（推奨）

ノイズを考慮した正則化フィルタ：

$$
G_{\mathrm{Wiener}}(u, v) = \frac{H^*(u,v)}{|H(u,v)|^2 + \gamma}
$$

- \( H^* \): \( H \) の複素共役
- \( \gamma \): 正則化パラメータ（ノイズ／信号パワー比の推定）

または、より単純な **Pseudo-inverse** 形式：

$$
G(u, v) = \frac{H^*(u,v)}{\max(|H(u,v)|^2, \epsilon)}
$$

\( \epsilon \) はゼロ除算と高周波の過増幅を防ぐしきい値（例: \( 10^{-3} \sim 10^{-6} \)）。

#### 2.3.4 アルゴリズムフロー（PSF → 逆フィルタ）

```
Input: 処方箋 (S, C, α), 解像度 (W, H), 正則化 ε
Output: 逆フィルタ G (周波数領域, 複素数)

1. Power Vector 算出
   (M, J0, J45) ← prescription_to_power_vector(S, C, α)

2. PSF 生成（空間領域）
   h ← gaussian_psf_2d(M, J0, J45, W, H)
   h を正規化（Σh = 1）

3. FFT で OTF 取得
   H ← FFT(h)

4. Wiener 型逆フィルタ
   for each (u,v):
     G(u,v) ← H*(u,v) / max(|H(u,v)|², ε)

5. return G
```

---

## 3. Rendering Pipeline

### 3.1 パイプライン構成

```
[Main Render Pass]  →  [Composition / Final Framebuffer]
         ↓
[Vision Correction Pass]
  - 入力: 最終フレームバッファ（左眼 / 右眼それぞれ）
  - 処理: FFT → 周波数領域で G と乗算 → IFFT
  - 出力: 補正済み画像 → コンポジット / ディスプレイ
```

### 3.2 GPU 上の処理フロー

| ステップ | 処理 | シェーダー / Compute |
|:---|:---|:---|
| 1 | フレームバッファ読み込み（RGBA → Y のみ、または YUV 変換） | Fullscreen quad / Compute |
| 2 | 2D FFT（行・列方向） | Compute Shader |
| 3 | 逆フィルタ \( G \) との乗算（複素数） | Compute Shader |
| 4 | 2D IFFT | Compute Shader |
| 5 | Y を元のフレームに書き戻し（YUV の場合は Y のみ補正） | Fullscreen quad / Compute |

### 3.3 2D FFT の実装方針

- **オプション A**: 自前で Vulkan/wgpu Compute Shader に Radix-2 FFT を実装
- **オプション B**: FFT ライブラリ（例: rustfft + GPU 転送）で CPU 側 FFT を実行し、結果を GPU に転送
- **オプション C**: エンジンが利用する API に対応した FFT ライブラリ（例: cuFFT, FFTW + OpenCL）

**90 FPS 目標**を満たすには、GPU 上での FFT（オプション A または C）が望ましい。1080×1200 程度の眼ごとの解像度であれば、最適化された 2D FFT で 1–2 ms 以内を目標とする。

### 3.4 YUV 色空間での輝度のみ処理

色ずれ（カラーフリンギング）を避けるため、**輝度（Y）チャンネルのみ**に逆畳み込みを適用する：

1. RGB → YUV（BT.601 または BT.709）変換
2. Y に対して FFT → \( G \) 乗算 → IFFT
3. U, V はそのまま（または軽いスムージングのみ）
4. YUV → RGB 変換で戻す

これにより、コントラストの低下やリンギングを輝度に限定し、色飽和の悪化を抑制する。

### 3.5 On/Off 切り替え

Vision Correction Pass は **実行時オプション** とし、ユーザーが無効化できるようにする。

- 設定例: `vision_correction_enabled: bool`（Elixir 設定または NIF 経由）
- デフォルト: `false`（補正なしで従来のパイプラインを通す）
- `false` の場合: Vision Correction Pass をスキップし、最終フレームバッファをそのまま出力

---

## 4. Trade-offs & Mitigation

### 4.1 問題と対策一覧

| 問題 | 原因 | 対策 |
|:---|:---|:---|
| **リンギング** | 逆フィルタの高周波増幅 | Wiener 正則化（\( \gamma \), \( \epsilon \)）、Hanning 等の窓関数 |
| **コントラスト低下** | 高周波成分の減衰 | HDR ディスプレイ、マルチレイヤ表示（将来検討） |
| **色ずれ** | 全チャンネルに逆畳み込み | **Y チャンネルのみ**処理（YUV） |
| **ノイズ増幅** | \( 1/H \) の特異性 | L2 正則化、\( \epsilon \) によるクリッピング |
| **遅延** | FFT 計算コスト | GPU Compute、解像度ダウンサンプリング（必要に応じて） |

### 4.2 L2 正則化

Wiener フィルタの \( \gamma \) は実質的に Tikhonov 正則化に対応：

$$
\min_{\hat{f}} \| h * \hat{f} - b \|^2 + \gamma \| \hat{f} \|^2
$$

解は \( G = H^* / (|H|^2 + \gamma) \) となり、高周波で \( G \) が過大にならない。

### 4.3 窓関数

PSF を有限サイズで切り出す際、矩形窓は周波数リークを招く。**Hanning** または **Kaiser** 窓を PSF に掛けてから FFT し、リンギングを軽減する。

---

## 5. Rust Implementation Idea

### 5.1 モジュール構成（案）

```
native/
├── render/                # 既存
│   └── src/
│       └── vision_correction/   # 新規
│           ├── mod.rs
│           ├── psf.rs           # 処方箋 → PSF
│           ├── inverse_filter.rs # PSF → Wiener 逆フィルタ
│           └── pass.rs          # wgpu パス・シェーダー
│
├── input_openxr/          # 既存（拡張）
│   └── src/
│       └── vision_params.rs     # 左右眼の処方パラメータ取得（将来）
```

### 5.2 input_openxr との連携

- **現状**: `input_openxr` は HeadPose, ControllerPose, ControllerButton 等のイベントを `nif` 経由で Elixir に送信
- **拡張案**: ユーザー設定（処方箋）を **Elixir 側で保持**し、NIF 経由で Rust に渡す
  - `{:set_vision_prescription, %{left: %{s: -2.0, c: -0.5, axis: 90}, right: %{s: -1.5, c: 0, axis: 0}}}`
- **Rust 側**: `render` が毎フレームまたは処方変更時に、左右眼ごとの逆フィルタ `G_left`, `G_right` を再計算（またはキャッシュ）

### 5.3 左右眼の独立パラメータ

```rust
/// 処方箋（1 眼分）
#[derive(Clone, Debug)]
pub struct VisionPrescription {
    pub sphere: f32,    // D
    pub cylinder: f32,  // D
    pub axis: f32,      // degrees
}

/// 両眼分
#[derive(Clone, Debug)]
pub struct BinocularPrescription {
    pub left: VisionPrescription,
    pub right: VisionPrescription,
}

/// Vision Correction Pass の入力
pub struct VisionCorrectionParams {
    pub enabled: bool,             // false の場合はパスをスキップ
    pub left_eye: InverseFilter,   // 事前計算済み G_left
    pub right_eye: InverseFilter,  // 事前計算済み G_right
    pub use_yuv_luma_only: bool,   // true: Y のみ処理
}
```

### 5.4 パイプライン統合フロー

```
1. Elixir: ユーザーが処方箋を入力
2. nif: set_vision_prescription(S, C, α) を Rust に渡す
3. render::vision_correction::psf:
   - prescription_to_psf() → h
   - psf_to_inverse_filter() → G
4. render の描画ループ:
   - if params.enabled:
       - 左眼フレーム → VisionCorrectionPass(G_left) → 左眼出力
       - 右眼フレーム → VisionCorrectionPass(G_right) → 右眼出力
   - else:
       - パスをスキップし、そのまま出力
5. コンポジット / ディスプレイへ
```

---

## 6. コード内の特許に関する注意書き

Vision Correction Pass を実装するモジュールには、以下のモジュールレベル doc コメントを必ず含めること。ビルド・`cargo doc` で可視化され、実装者・利用者に特許リスクを明示する。

```rust
//! Vision Correction Pass — ソフトウェアによる視度補正（逆畳み込み Pre-filtering）
//!
//! 本アルゴリズムは第三者の特許の対象となる可能性があります。
//! 関連特許の例:
//! - US10529059B2 (MIT/UCSD): Vision correcting display
//! - US20160314564A1 (eSight/Gentex): Optical aberration correction
//!
//! 本プロジェクトは特許の実施可能性（Freedom-to-Operate）を保証しません。
//! 利用前に適切な専門家にご相談ください。
//!
//! 参考: Xu et al., "Software Based Visual Aberration Correction for HMDs," IEEE VR 2018.
```

---

## 7. 実装チェックリスト（Phase 1）

- [ ] 処方箋 → Power Vector → 2D ガウシアン PSF の実装
- [ ] PSF → Wiener 逆フィルタ（周波数領域）の実装
- [ ] wgpu Compute Shader: 2D FFT（または既存 FFT の GPU 統合）
- [ ] YUV 変換（RGB ↔ YUV）のシェーダー実装
- [ ] Vision Correction Pass を render パイプラインに挿入
- [ ] Elixir / NIF 経由での処方箋設定 API
- [ ] input_openxr または設定モジュールから左右眼パラメータを取得する構造の設計
- [ ] プロファイリング（90 FPS 達成の可否確認）
- [ ] On/Off 切り替え（`vision_correction_enabled`）の実装
- [ ] モジュール doc コメントへの特許に関する注意書きの追加

---

## 8. 参考文献

1. Xu et al., "Software Based Visual Aberration Correction for HMDs," *IEEE VR*, 2018.
2. Thibos et al., "Calculation of the geometrical point-spread function from wavefront aberrations," *Ophthalmic & Physiological Optics*, 2019.
3. Aberration pre-correction for HMDs (Optica, 2024).

---

*本ドキュメントは、Rust によるシェーダー・コンポジット処理の設計図として利用する。数式とアルゴリズムフローを実装時に参照すること。*
