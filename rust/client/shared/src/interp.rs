//! 線形補間 (Lerp) ロジック
//!
//! サーバーの低頻度更新（10〜20Hz）を描画タイミング（~60Hz）に合わせて補間。
//! `SnapshotInterpolator` が複数スナップショットをキュー保持し、描画遅延バッファ
//! （観測間隔の約 2 倍）上の表示時刻を挟む 2 枚で座標を線形補間する。

use std::collections::VecDeque;
use std::time::{Duration, Instant};

use crate::render_frame::{CameraParams, DrawCommand, RenderFrame};
use crate::types::Vec2;

/// 描画遅延バッファの既定値。実運用では観測したスナップショット間隔の約 2 倍に追従する。
pub const INTERP_DELAY: Duration = Duration::from_millis(100);

/// 適応遅延の下限 / 上限（10Hz 欠落時でも補間区間に収まるよう上限を広めに取る）。
const INTERP_DELAY_MIN: Duration = Duration::from_millis(80);
const INTERP_DELAY_MAX: Duration = Duration::from_millis(250);

/// 描画遅延の EMA 係数。ジッターで `render_time` が跳ねないよう緩やかに追従する。
const DELAY_EMA_ALPHA: f64 = 0.1;

/// 保持するスナップショット上限。
/// 遅延 ≈ 2×interval のため、直近 2 枚だけでは `render_time` が履歴より過去になり補間できない。
/// バースト到着時の押し出しにも余裕を持たせる。
const MAX_SNAPSHOTS: usize = 16;

/// これ未満の受信間隔はバーストとみなし、間隔 EMA を更新しない。
const BURST_RECV_GAP: Duration = Duration::from_millis(5);

/// 観測 tick 間隔の下限 / 上限（10〜60Hz 相当）。
const INTERVAL_MIN: Duration = Duration::from_millis(16);
const INTERVAL_MAX: Duration = Duration::from_millis(120);

/// 同一バリアント内で「同じエンティティ」とみなす最大移動距離。
/// bullet_hell の弾速 7.0 × 欠落込み ~0.3s ≈ 2.1 に余裕を持たせた値。
/// これを超えるペアはスポーン／デスポーンによる別個体とみなし、補間せず curr を採用する。
pub const MAX_MATCH_DISTANCE: f32 = 3.0;

/// a と b を t (0.0..=1.0) で線形補間
#[inline]
pub fn lerp_vec2(a: Vec2, b: Vec2, t: f32) -> Vec2 {
    Vec2 {
        x: a.x + (b.x - a.x) * t,
        y: a.y + (b.y - a.y) * t,
    }
}

/// f32 の線形補間
#[inline]
pub fn lerp(a: f32, b: f32, t: f32) -> f32 {
    a + (b - a) * t
}

#[inline]
fn lerp3(a: [f32; 3], b: [f32; 3], t: f32) -> [f32; 3] {
    [lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t)]
}

/// 同一バリアントの位置成分を `t` で補間する。不一致・非位置コマンドは `curr` を返す。
pub fn lerp_draw_command(prev: &DrawCommand, curr: &DrawCommand, t: f32) -> DrawCommand {
    match (prev, curr) {
        (
            DrawCommand::PlayerSprite { x: ax, y: ay, .. },
            DrawCommand::PlayerSprite { x: bx, y: by, frame },
        ) => {
            let p = lerp_vec2(Vec2::new(*ax, *ay), Vec2::new(*bx, *by), t);
            DrawCommand::PlayerSprite {
                x: p.x,
                y: p.y,
                frame: *frame,
            }
        }
        // Particle は近傍マッチ対象外のためここには来ない（curr をそのまま採用）
        (
            DrawCommand::Item { x: ax, y: ay, .. },
            DrawCommand::Item { x: bx, y: by, kind },
        ) => {
            let p = lerp_vec2(Vec2::new(*ax, *ay), Vec2::new(*bx, *by), t);
            DrawCommand::Item {
                x: p.x,
                y: p.y,
                kind: *kind,
            }
        }
        (
            DrawCommand::Obstacle {
                x: ax,
                y: ay,
                radius: ar,
                ..
            },
            DrawCommand::Obstacle {
                x: bx,
                y: by,
                radius: br,
                kind,
            },
        ) => DrawCommand::Obstacle {
            x: lerp(*ax, *bx, t),
            y: lerp(*ay, *by, t),
            radius: lerp(*ar, *br, t),
            kind: *kind,
        },
        (
            DrawCommand::SpriteRaw {
                x: ax,
                y: ay,
                width: aw,
                height: ah,
                ..
            },
            DrawCommand::SpriteRaw {
                x: bx,
                y: by,
                width: bw,
                height: bh,
                uv_offset,
                uv_size,
                color_tint,
            },
        ) => DrawCommand::SpriteRaw {
            x: lerp(*ax, *bx, t),
            y: lerp(*ay, *by, t),
            width: lerp(*aw, *bw, t),
            height: lerp(*ah, *bh, t),
            uv_offset: *uv_offset,
            uv_size: *uv_size,
            color_tint: *color_tint,
        },
        (
            DrawCommand::Box3D {
                x: ax,
                y: ay,
                z: az,
                ..
            },
            DrawCommand::Box3D {
                x: bx,
                y: by,
                z: bz,
                half_w,
                half_h,
                half_d,
                color,
            },
        ) => DrawCommand::Box3D {
            x: lerp(*ax, *bx, t),
            y: lerp(*ay, *by, t),
            z: lerp(*az, *bz, t),
            half_w: *half_w,
            half_h: *half_h,
            half_d: *half_d,
            color: *color,
        },
        (
            DrawCommand::Sphere3D {
                x: ax,
                y: ay,
                z: az,
                radius: ar,
                ..
            },
            DrawCommand::Sphere3D {
                x: bx,
                y: by,
                z: bz,
                radius: br,
                color,
            },
        ) => DrawCommand::Sphere3D {
            x: lerp(*ax, *bx, t),
            y: lerp(*ay, *by, t),
            z: lerp(*az, *bz, t),
            radius: lerp(*ar, *br, t),
            color: *color,
        },
        (
            DrawCommand::Cone3D {
                x: ax,
                y: ay,
                z: az,
                ..
            },
            DrawCommand::Cone3D {
                x: bx,
                y: by,
                z: bz,
                half_w,
                half_h,
                half_d,
                color,
            },
        ) => DrawCommand::Cone3D {
            x: lerp(*ax, *bx, t),
            y: lerp(*ay, *by, t),
            z: lerp(*az, *bz, t),
            half_w: *half_w,
            half_h: *half_h,
            half_d: *half_d,
            color: *color,
        },
        _ => curr.clone(),
    }
}

fn lerp_camera(prev: &CameraParams, curr: &CameraParams, t: f32) -> CameraParams {
    match (prev, curr) {
        (
            CameraParams::Camera2D {
                offset_x: ax,
                offset_y: ay,
            },
            CameraParams::Camera2D {
                offset_x: bx,
                offset_y: by,
            },
        ) => CameraParams::Camera2D {
            offset_x: lerp(*ax, *bx, t),
            offset_y: lerp(*ay, *by, t),
        },
        (
            CameraParams::Camera3D {
                eye: ae,
                target: at,
                ..
            },
            CameraParams::Camera3D {
                eye: be,
                target: bt,
                up,
                fov_deg,
                near,
                far,
            },
        ) => CameraParams::Camera3D {
            eye: lerp3(*ae, *be, t),
            target: lerp3(*at, *bt, t),
            up: *up,
            fov_deg: *fov_deg,
            near: *near,
            far: *far,
        },
        _ => curr.clone(),
    }
}

/// 近傍マッチ対象のワールド座標。
///
/// `Particle` は大量生成され得て O(N×M) 探索のコストが大きい一方、
/// 個別の厳密補間の重要性が低いため対象外（`None` → curr をそのまま採用）。
fn command_position(cmd: &DrawCommand) -> Option<[f32; 3]> {
    match *cmd {
        DrawCommand::PlayerSprite { x, y, .. }
        | DrawCommand::Item { x, y, .. }
        | DrawCommand::Obstacle { x, y, .. }
        | DrawCommand::SpriteRaw { x, y, .. } => Some([x, y, 0.0]),
        DrawCommand::Box3D { x, y, z, .. }
        | DrawCommand::Sphere3D { x, y, z, .. }
        | DrawCommand::Cone3D { x, y, z, .. } => Some([x, y, z]),
        DrawCommand::Particle { .. }
        | DrawCommand::GridPlane { .. }
        | DrawCommand::GridPlaneVerts { .. }
        | DrawCommand::Skybox { .. } => None,
    }
}

#[inline]
fn dist_sq(a: [f32; 3], b: [f32; 3]) -> f32 {
    let dx = a[0] - b[0];
    let dy = a[1] - b[1];
    let dz = a[2] - b[2];
    dx * dx + dy * dy + dz * dz
}

/// 補間ペアとして互換か（バリアント + kind / UV 等の識別子）。
fn is_compatible_command(a: &DrawCommand, b: &DrawCommand) -> bool {
    match (a, b) {
        (DrawCommand::Item { kind: ak, .. }, DrawCommand::Item { kind: bk, .. }) => ak == bk,
        (DrawCommand::Obstacle { kind: ak, .. }, DrawCommand::Obstacle { kind: bk, .. }) => {
            ak == bk
        }
        (
            DrawCommand::SpriteRaw {
                uv_offset: ao,
                uv_size: asz,
                ..
            },
            DrawCommand::SpriteRaw {
                uv_offset: bo,
                uv_size: bsz,
                ..
            },
        ) => ao == bo && asz == bsz,
        _ => std::mem::discriminant(a) == std::mem::discriminant(b),
    }
}

/// 互換・未使用のうち、距離が閾値以内で最も近い prev コマンドを探す。
///
/// 現状は線形走査 O(N×M)。オブジェクト数が数百〜数千規模になったら
/// 種別ごとのバケットや空間分割での絞り込みを検討する。
fn find_nearest_prev(
    prev_commands: &[DrawCommand],
    curr_cmd: &DrawCommand,
    used: &[bool],
    max_dist: f32,
) -> Option<usize> {
    let curr_pos = command_position(curr_cmd)?;
    let max_dist_sq = max_dist * max_dist;

    let mut best: Option<(usize, f32)> = None;
    for (i, prev_cmd) in prev_commands.iter().enumerate() {
        if used[i] || !is_compatible_command(prev_cmd, curr_cmd) {
            continue;
        }
        let Some(prev_pos) = command_position(prev_cmd) else {
            continue;
        };
        let d2 = dist_sq(prev_pos, curr_pos);
        if d2 > max_dist_sq {
            continue;
        }
        let is_better = match best {
            None => true,
            Some((_, best_d2)) => d2 < best_d2,
        };
        if is_better {
            best = Some((i, d2));
        }
    }
    best.map(|(i, _)| i)
}

/// `prev` → `curr` を `t` (0.0..=1.0) で補間した描画フレームを返す。
///
/// 位置コマンドは **インデックスではなく近傍マッチ**で突き合わせる。
/// - 新規スポーン（curr のみ）: `t < 1.0` の間は非表示（フライング出現防止）
/// - デスポーン（prev のみ）: `t < 1.0` の間は prev 座標で維持（早期消滅防止）
/// 非位置コマンド（Skybox 等）と Particle は `curr` を採用。
/// UI / mesh / cursor / audio は最新（`curr`）を採用する。
pub fn interpolate_render_frame(prev: &RenderFrame, curr: &RenderFrame, t: f32) -> RenderFrame {
    let t = t.clamp(0.0, 1.0);
    if t <= 0.0 {
        return prev.clone();
    }
    if t >= 1.0 {
        return curr.clone();
    }

    let mut used = vec![false; prev.commands.len()];
    let mut commands: Vec<DrawCommand> = curr
        .commands
        .iter()
        .filter_map(|curr_cmd| {
            if command_position(curr_cmd).is_none() {
                return Some(curr_cmd.clone());
            }
            match find_nearest_prev(&prev.commands, curr_cmd, &used, MAX_MATCH_DISTANCE) {
                Some(i) => {
                    used[i] = true;
                    Some(lerp_draw_command(&prev.commands[i], curr_cmd, t))
                }
                // t < 1.0 の間は新規スポーンを出さず、curr 到達まで待つ
                None => None,
            }
        })
        .collect();

    // デスポーン体: 論理的な消滅（t = 1.0）まで prev 座標で残す
    for (i, was_used) in used.iter().enumerate() {
        if *was_used {
            continue;
        }
        let prev_cmd = &prev.commands[i];
        if command_position(prev_cmd).is_some() {
            commands.push(prev_cmd.clone());
        }
    }

    RenderFrame {
        commands,
        camera: lerp_camera(&prev.camera, &curr.camera, t),
        ui: curr.ui.clone(),
        cursor_grab: curr.cursor_grab,
        mesh_definitions: curr.mesh_definitions.clone(),
        // 補間サンプルでは SE を再送しない（新規受信時に別途 drain する）
        audio_cues: Vec::new(),
    }
}

/// 再生タイムライン上のスナップショットをキュー保持し、表示時刻で補間する。
///
/// キューの時刻は受信 `Instant` そのものではなく、推定 tick 間隔で進める再生時刻。
/// ジッター／バーストで到着間隔が歪んでも補間速度が暴れにくい。
/// 本命は RenderFrame へのサーバー tick／生成時刻付与（要プロトコル拡張）。
pub struct SnapshotInterpolator {
    /// `(playback_at, frame)` — playback_at は再生タイムライン上の時刻
    snapshots: VecDeque<(Instant, RenderFrame)>,
    last_received_at: Option<Instant>,
    estimated_interval: Duration,
    pending_audio: Vec<String>,
    delay: Duration,
}

impl Default for SnapshotInterpolator {
    fn default() -> Self {
        Self::new()
    }
}

impl SnapshotInterpolator {
    pub fn new() -> Self {
        Self::with_delay(INTERP_DELAY)
    }

    pub fn with_delay(delay: Duration) -> Self {
        let estimated_interval = (delay / 2).clamp(INTERVAL_MIN, INTERVAL_MAX);
        Self {
            snapshots: VecDeque::new(),
            last_received_at: None,
            estimated_interval,
            pending_audio: Vec::new(),
            delay,
        }
    }

    /// 現在の描画遅延（テスト・診断用）。
    pub fn delay(&self) -> Duration {
        self.delay
    }

    fn ema_duration(current: Duration, sample: Duration) -> Duration {
        let current_ms = current.as_secs_f64() * 1000.0;
        let sample_ms = sample.as_secs_f64() * 1000.0;
        let next_ms = current_ms * (1.0 - DELAY_EMA_ALPHA) + sample_ms * DELAY_EMA_ALPHA;
        Duration::from_secs_f64((next_ms / 1000.0).max(0.0))
    }

    /// 新しい権威スナップショットを取り込む。`audio_cues` は pending に移し、再再生を防ぐ。
    ///
    /// 受信間隔から推定 tick を EMA 更新し、キューには `last_playback + estimated_interval`
    /// でスタンプする（バースト時も等間隔に載せる）。描画遅延は推定間隔×2 へ追従。
    ///
    /// 受信が大きく開いて再生タイムラインが実時間から遅れた場合はキューをリセットし、
    /// 以降も補間が効く状態に戻す（瞬断・一時停止対策）。
    ///
    /// `received_at` は受信順で単調非減少であること。最新より古い受信時刻の push は破棄する。
    /// ペイロード内容のアウトオブオーダー検知にはサーバー tick が必要。
    pub fn push(&mut self, mut frame: RenderFrame, received_at: Instant) {
        if let Some(last_recv) = self.last_received_at {
            if received_at < last_recv {
                // 順序逆転した古いフレームは無視する
                return;
            }
        }

        // 再生タイムラインが実時間から delay 超えて遅れたら同期し直す
        if let Some((last_play, _)) = self.snapshots.back() {
            let next_expected = *last_play + self.estimated_interval;
            if received_at > next_expected + self.delay {
                self.snapshots.clear();
                self.last_received_at = None;
            }
        }

        if let Some(last_recv) = self.last_received_at {
            let recv_gap = received_at.saturating_duration_since(last_recv);
            if recv_gap >= BURST_RECV_GAP {
                let sample = recv_gap.clamp(INTERVAL_MIN, INTERVAL_MAX);
                self.estimated_interval = Self::ema_duration(self.estimated_interval, sample)
                    .clamp(INTERVAL_MIN, INTERVAL_MAX);
                let target_delay = self
                    .estimated_interval
                    .saturating_mul(2)
                    .clamp(INTERP_DELAY_MIN, INTERP_DELAY_MAX);
                self.delay = Self::ema_duration(self.delay, target_delay)
                    .clamp(INTERP_DELAY_MIN, INTERP_DELAY_MAX);
            }
        }

        let playback_at = match self.snapshots.back() {
            None => received_at,
            Some((last_play, _)) => *last_play + self.estimated_interval,
        };

        let cues = std::mem::take(&mut frame.audio_cues);
        if !cues.is_empty() {
            self.pending_audio.extend(cues);
        }
        self.last_received_at = Some(received_at);
        self.snapshots.push_back((playback_at, frame));
        while self.snapshots.len() > MAX_SNAPSHOTS {
            self.snapshots.pop_front();
        }
    }

    /// 新規受信フレーム由来の SE キューを取り出す（描画サンプルとは独立）。
    pub fn take_pending_audio(&mut self) -> Vec<String> {
        std::mem::take(&mut self.pending_audio)
    }

    /// `now` 時点の表示用フレームを返す。スナップショットが無い場合は `None`。
    ///
    /// `render_time = now - delay` を挟む 2 枚を再生タイムライン上から選び補間する。
    pub fn sample(&self, now: Instant) -> Option<RenderFrame> {
        let render_time = now.checked_sub(self.delay).unwrap_or(now);

        match self.snapshots.len() {
            0 => None,
            1 => self.snapshots.front().map(|(_, f)| f.clone()),
            _ => {
                let first_at = self.snapshots.front().unwrap().0;
                if render_time <= first_at {
                    return Some(self.snapshots.front().unwrap().1.clone());
                }
                let last_at = self.snapshots.back().unwrap().0;
                if render_time >= last_at {
                    return Some(self.snapshots.back().unwrap().1.clone());
                }

                for i in 1..self.snapshots.len() {
                    let (curr_at, curr) = &self.snapshots[i];
                    if render_time > *curr_at {
                        continue;
                    }
                    let (prev_at, prev) = &self.snapshots[i - 1];
                    let span = curr_at.saturating_duration_since(*prev_at);
                    if span.is_zero() {
                        return Some(curr.clone());
                    }
                    let since_prev = render_time.saturating_duration_since(*prev_at);
                    let t = (since_prev.as_secs_f64() / span.as_secs_f64()) as f32;
                    return Some(interpolate_render_frame(prev, curr, t));
                }

                // 到達しないはずだが安全側で最新を返す
                Some(self.snapshots.back().unwrap().1.clone())
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::render_frame::CameraParams;

    fn player_at(x: f32, y: f32) -> RenderFrame {
        RenderFrame {
            commands: vec![DrawCommand::PlayerSprite { x, y, frame: 1 }],
            camera: CameraParams::Camera2D {
                offset_x: x,
                offset_y: y,
            },
            ..Default::default()
        }
    }

    #[test]
    fn lerp_vec2_midpoint() {
        let a = Vec2::new(0.0, 0.0);
        let b = Vec2::new(10.0, 20.0);
        let m = lerp_vec2(a, b, 0.5);
        assert!((m.x - 5.0).abs() < 1e-5);
        assert!((m.y - 10.0).abs() < 1e-5);
    }

    #[test]
    fn interpolate_render_frame_midpoint() {
        // 1 tick 相当の移動量（MAX_MATCH_DISTANCE 以内）
        let prev = player_at(0.0, 0.0);
        let curr = player_at(2.0, 1.0);
        let mid = interpolate_render_frame(&prev, &curr, 0.5);
        match &mid.commands[0] {
            DrawCommand::PlayerSprite { x, y, .. } => {
                assert!((*x - 1.0).abs() < 1e-5);
                assert!((*y - 0.5).abs() < 1e-5);
            }
            other => panic!("unexpected command: {other:?}"),
        }
        match mid.camera {
            CameraParams::Camera2D { offset_x, offset_y } => {
                assert!((offset_x - 1.0).abs() < 1e-5);
                assert!((offset_y - 0.5).abs() < 1e-5);
            }
            _ => panic!("expected Camera2D"),
        }
        assert!(mid.audio_cues.is_empty());
    }

    #[test]
    fn snapshot_interpolator_uses_delay_buffer() {
        let mut interp = SnapshotInterpolator::with_delay(Duration::from_millis(100));
        let t0 = Instant::now();
        interp.push(player_at(0.0, 0.0), t0);
        interp.push(player_at(2.0, 0.0), t0 + Duration::from_millis(50));

        // render_time = now - 100ms = t0 + 25ms → 区間 [0,50] で t = 0.5
        let now = t0 + Duration::from_millis(125);
        let frame = interp.sample(now).expect("frame");
        match &frame.commands[0] {
            DrawCommand::PlayerSprite { x, y, .. } => {
                assert!((*x - 1.0).abs() < 1e-4, "x={x}");
                assert!(y.abs() < 1e-4);
            }
            other => panic!("unexpected command: {other:?}"),
        }
    }

    #[test]
    fn snapshot_interpolator_steady_state_with_delay_two_intervals() {
        // 遅延 = 2×interval でも、3 枚以上あれば render_time が履歴内に入り補間できる。
        let mut interp = SnapshotInterpolator::with_delay(Duration::from_millis(100));
        let t0 = Instant::now();
        interp.push(player_at(0.0, 0.0), t0);
        interp.push(player_at(2.0, 0.0), t0 + Duration::from_millis(50));
        interp.push(player_at(4.0, 0.0), t0 + Duration::from_millis(100));

        // now = t0+100 直後相当 → render_time = t0、oldest
        // now = t0+125 → render_time = t0+25 → [0,50] の中点 x=1
        let frame = interp
            .sample(t0 + Duration::from_millis(125))
            .expect("frame");
        match &frame.commands[0] {
            DrawCommand::PlayerSprite { x, .. } => {
                assert!((*x - 1.0).abs() < 1e-3, "x={x} (must interpolate, not stick to prev)");
            }
            other => panic!("unexpected: {other:?}"),
        }
    }

    #[test]
    fn snapshot_interpolator_drains_audio_once() {
        let mut interp = SnapshotInterpolator::new();
        let mut frame = player_at(1.0, 2.0);
        frame.audio_cues = vec!["assets/se/hit.ogg".into()];
        interp.push(frame, Instant::now());
        assert_eq!(interp.take_pending_audio(), vec!["assets/se/hit.ogg"]);
        assert!(interp.take_pending_audio().is_empty());
        let sampled = interp.sample(Instant::now()).unwrap();
        assert!(sampled.audio_cues.is_empty());
    }

    #[test]
    fn lerp_box3d_position() {
        let prev = DrawCommand::Box3D {
            x: 0.0,
            y: 0.0,
            z: 0.0,
            half_w: 1.0,
            half_h: 1.0,
            half_d: 1.0,
            color: [1.0, 0.0, 0.0, 1.0],
        };
        let curr = DrawCommand::Box3D {
            x: 2.0,
            y: 4.0,
            z: 6.0,
            half_w: 1.0,
            half_h: 1.0,
            half_d: 1.0,
            color: [0.0, 1.0, 0.0, 1.0],
        };
        match lerp_draw_command(&prev, &curr, 0.5) {
            DrawCommand::Box3D { x, y, z, color, .. } => {
                assert!((x - 1.0).abs() < 1e-5);
                assert!((y - 2.0).abs() < 1e-5);
                assert!((z - 3.0).abs() < 1e-5);
                // 色は curr を採用（位置のみ補間）
                assert_eq!(color, [0.0, 1.0, 0.0, 1.0]);
            }
            other => panic!("unexpected: {other:?}"),
        }
    }

    fn sphere_at(x: f32, z: f32) -> DrawCommand {
        DrawCommand::Sphere3D {
            x,
            y: 0.15,
            z,
            radius: 0.15,
            color: [1.0, 1.0, 0.0, 1.0],
        }
    }

    #[test]
    fn interpolate_matches_by_nearest_not_index_when_bullet_despawns() {
        // prev: 弾 A(0) と B(10)。curr: A が消え B が 10.5 へ。インデックス 0 だと
        // A→B' を補間して瞬間移動になる。近傍マッチなら B→B'、A はデスポーン維持。
        let prev = RenderFrame {
            commands: vec![sphere_at(0.0, 0.0), sphere_at(10.0, 0.0)],
            ..Default::default()
        };
        let curr = RenderFrame {
            commands: vec![sphere_at(10.5, 0.0)],
            ..Default::default()
        };
        let mid = interpolate_render_frame(&prev, &curr, 0.5);
        assert_eq!(mid.commands.len(), 2);
        let mut xs: Vec<f32> = mid
            .commands
            .iter()
            .map(|c| match c {
                DrawCommand::Sphere3D { x, .. } => *x,
                other => panic!("unexpected: {other:?}"),
            })
            .collect();
        xs.sort_by(|a, b| a.partial_cmp(b).unwrap());
        assert!((xs[0] - 0.0).abs() < 1e-4, "despawned A kept at 0, got {}", xs[0]);
        assert!(
            (xs[1] - 10.25).abs() < 1e-4,
            "B should track to 10.25, got {}",
            xs[1]
        );
    }

    #[test]
    fn interpolate_hides_unmatched_spawn_until_curr() {
        let prev = RenderFrame {
            commands: vec![sphere_at(0.0, 0.0)],
            ..Default::default()
        };
        // 距離 10 > MAX_MATCH_DISTANCE → 別個体。新規は隠し、旧はデスポーン維持
        let curr = RenderFrame {
            commands: vec![sphere_at(10.0, 0.0)],
            ..Default::default()
        };
        let mid = interpolate_render_frame(&prev, &curr, 0.5);
        assert_eq!(mid.commands.len(), 1);
        match &mid.commands[0] {
            DrawCommand::Sphere3D { x, .. } => {
                assert!(x.abs() < 1e-5, "x={x} (keep prev, hide new spawn)");
            }
            other => panic!("unexpected: {other:?}"),
        }
        let at_curr = interpolate_render_frame(&prev, &curr, 1.0);
        assert_eq!(at_curr.commands.len(), 1);
        match &at_curr.commands[0] {
            DrawCommand::Sphere3D { x, .. } => {
                assert!((*x - 10.0).abs() < 1e-5);
            }
            other => panic!("unexpected: {other:?}"),
        }
    }

    #[test]
    fn interpolate_keeps_despawned_entity_until_curr() {
        let prev = RenderFrame {
            commands: vec![sphere_at(5.0, 0.0)],
            ..Default::default()
        };
        let curr = RenderFrame {
            commands: vec![],
            ..Default::default()
        };
        let mid = interpolate_render_frame(&prev, &curr, 0.5);
        assert_eq!(mid.commands.len(), 1);
        match &mid.commands[0] {
            DrawCommand::Sphere3D { x, .. } => {
                assert!((*x - 5.0).abs() < 1e-5);
            }
            other => panic!("unexpected: {other:?}"),
        }
        let at_curr = interpolate_render_frame(&prev, &curr, 1.0);
        assert!(at_curr.commands.is_empty());
    }

    #[test]
    fn interpolate_does_not_match_different_item_kinds() {
        let prev = RenderFrame {
            commands: vec![DrawCommand::Item {
                x: 0.0,
                y: 0.0,
                kind: 1,
            }],
            ..Default::default()
        };
        let curr = RenderFrame {
            commands: vec![DrawCommand::Item {
                x: 0.5,
                y: 0.0,
                kind: 2,
            }],
            ..Default::default()
        };
        let mid = interpolate_render_frame(&prev, &curr, 0.5);
        // kind2 は新規として隠し、kind1 はデスポーン体として残る
        assert_eq!(mid.commands.len(), 1);
        match &mid.commands[0] {
            DrawCommand::Item { x, kind, .. } => {
                assert_eq!(*kind, 1);
                assert!(x.abs() < 1e-5);
            }
            other => panic!("unexpected: {other:?}"),
        }
    }

    #[test]
    fn snapshot_resets_timeline_after_large_receive_gap() {
        let mut interp = SnapshotInterpolator::with_delay(Duration::from_millis(100));
        let t0 = Instant::now();
        interp.push(player_at(0.0, 0.0), t0);
        interp.push(player_at(1.0, 0.0), t0 + Duration::from_millis(50));

        // delay を大きく超えるギャップ → キューリセットして再同期
        let resume = t0 + Duration::from_millis(50) + Duration::from_millis(500);
        interp.push(player_at(10.0, 0.0), resume);
        interp.push(player_at(12.0, 0.0), resume + Duration::from_millis(50));

        // リセット後の timeline: resume, resume+est。delay≈100 のままなら
        // now = resume+125 → render_time = resume+25 → x=11
        let frame = interp
            .sample(resume + Duration::from_millis(125))
            .expect("frame");
        match &frame.commands[0] {
            DrawCommand::PlayerSprite { x, .. } => {
                assert!(
                    (*x - 11.0).abs() < 1e-2,
                    "x={x} (must re-sync and interpolate after gap)"
                );
            }
            other => panic!("unexpected: {other:?}"),
        }
    }

    #[test]
    fn snapshot_delay_tracks_observed_interval_with_ema() {
        let mut interp = SnapshotInterpolator::with_delay(Duration::from_millis(100));
        let t0 = Instant::now();
        interp.push(player_at(0.0, 0.0), t0);
        // est: 50→55, target_delay: 110, delay: 100*0.9+110*0.1 = 101
        interp.push(player_at(1.0, 0.0), t0 + Duration::from_millis(100));
        let ms = interp.delay().as_secs_f64() * 1000.0;
        assert!((ms - 101.0).abs() < 1.0, "delay_ms={ms}");

        // 同間隔を続けても急変せず、目標（≈200ms）へ近づく
        let mut t = t0 + Duration::from_millis(100);
        for _ in 0..40 {
            t += Duration::from_millis(100);
            interp.push(player_at(1.0, 0.0), t);
        }
        let settled = interp.delay().as_secs_f64() * 1000.0;
        assert!(settled > 180.0, "settled_ms={settled}");
        assert!(settled <= 250.0, "settled_ms={settled}");
    }

    #[test]
    fn snapshot_burst_arrival_still_spaces_playback_timeline() {
        let mut interp = SnapshotInterpolator::with_delay(Duration::from_millis(100));
        let t0 = Instant::now();
        // バースト: 受信時刻はほぼ同時でも再生時刻は estimated_interval で等間隔
        interp.push(player_at(0.0, 0.0), t0);
        interp.push(player_at(2.0, 0.0), t0 + Duration::from_millis(1));
        interp.push(player_at(4.0, 0.0), t0 + Duration::from_millis(2));

        // est=50ms のまま → playback t0, t0+50, t0+100
        // now=t0+125, delay=100 → render_time=t0+25 → x=1
        let frame = interp
            .sample(t0 + Duration::from_millis(125))
            .expect("frame");
        match &frame.commands[0] {
            DrawCommand::PlayerSprite { x, .. } => {
                assert!((*x - 1.0).abs() < 1e-3, "x={x}");
            }
            other => panic!("unexpected: {other:?}"),
        }
    }

    #[test]
    fn push_discards_out_of_order_older_timestamp() {
        let mut interp = SnapshotInterpolator::new();
        let t0 = Instant::now();
        let t1 = t0 + Duration::from_millis(50);
        let mut older = player_at(0.0, 0.0);
        older.audio_cues = vec!["assets/se/old.ogg".into()];
        let newer = player_at(2.0, 0.0);

        interp.push(newer, t1);
        interp.push(older, t0); // 古い時刻 → 破棄

        assert!(interp.take_pending_audio().is_empty());
        let frame = interp.sample(t1 + Duration::from_millis(200)).unwrap();
        match &frame.commands[0] {
            DrawCommand::PlayerSprite { x, .. } => {
                assert!((*x - 2.0).abs() < 1e-5, "x={x}");
            }
            other => panic!("unexpected: {other:?}"),
        }
    }

    #[test]
    fn interpolate_skips_nearest_match_for_particles() {
        let prev = RenderFrame {
            commands: vec![DrawCommand::Particle {
                x: 0.0,
                y: 0.0,
                r: 1.0,
                g: 0.0,
                b: 0.0,
                alpha: 1.0,
                size: 1.0,
            }],
            ..Default::default()
        };
        let curr = RenderFrame {
            commands: vec![DrawCommand::Particle {
                x: 2.0,
                y: 0.0,
                r: 1.0,
                g: 0.0,
                b: 0.0,
                alpha: 1.0,
                size: 1.0,
            }],
            ..Default::default()
        };
        let mid = interpolate_render_frame(&prev, &curr, 0.5);
        match &mid.commands[0] {
            DrawCommand::Particle { x, .. } => {
                // 近傍補間せず curr を採用
                assert!((*x - 2.0).abs() < 1e-5, "x={x}");
            }
            other => panic!("unexpected: {other:?}"),
        }
    }
}
