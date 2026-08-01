//! 線形補間 (Lerp) ロジック
//!
//! サーバーの低頻度更新（10〜20Hz）を描画タイミング（~60Hz）に合わせて補間。
//! `SnapshotInterpolator` が直近 2 スナップショットを保持し、描画遅延バッファ
//! （既定 100ms）上の表示時刻で座標を線形補間する。

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
        (
            DrawCommand::Particle {
                x: ax,
                y: ay,
                r: ar,
                g: ag,
                b: ab,
                alpha: aa,
                size: asz,
            },
            DrawCommand::Particle {
                x: bx,
                y: by,
                r: br,
                g: bg,
                b: bb,
                alpha: ba,
                size: bsz,
            },
        ) => DrawCommand::Particle {
            x: lerp(*ax, *bx, t),
            y: lerp(*ay, *by, t),
            r: lerp(*ar, *br, t),
            g: lerp(*ag, *bg, t),
            b: lerp(*ab, *bb, t),
            alpha: lerp(*aa, *ba, t),
            size: lerp(*asz, *bsz, t),
        },
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

/// 同一バリアント・未使用のうち、距離が閾値以内で最も近い prev コマンドを探す。
fn find_nearest_prev(
    prev_commands: &[DrawCommand],
    curr_cmd: &DrawCommand,
    used: &[bool],
    max_dist: f32,
) -> Option<usize> {
    let curr_pos = command_position(curr_cmd)?;
    let max_dist_sq = max_dist * max_dist;
    let curr_kind = std::mem::discriminant(curr_cmd);

    let mut best: Option<(usize, f32)> = None;
    for (i, prev_cmd) in prev_commands.iter().enumerate() {
        if used[i] || std::mem::discriminant(prev_cmd) != curr_kind {
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
/// 弾・敵のスポーン／デスポーンでコマンド列がずれても、別個体同士を補間して
/// 瞬間移動に見せないため。マッチ不能（新規スポーン・Particle 等）は `curr` をそのまま採用。
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
    let commands = curr
        .commands
        .iter()
        .map(|curr_cmd| {
            if command_position(curr_cmd).is_none() {
                return curr_cmd.clone();
            }
            match find_nearest_prev(&prev.commands, curr_cmd, &used, MAX_MATCH_DISTANCE) {
                Some(i) => {
                    used[i] = true;
                    lerp_draw_command(&prev.commands[i], curr_cmd, t)
                }
                None => curr_cmd.clone(),
            }
        })
        .collect();

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

/// 受信時刻付きスナップショットの直近 2 枚を保持し、表示時刻で補間する。
pub struct SnapshotInterpolator {
    prev: Option<(Instant, RenderFrame)>,
    curr: Option<(Instant, RenderFrame)>,
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
        Self {
            prev: None,
            curr: None,
            pending_audio: Vec::new(),
            delay,
        }
    }

    /// 現在の描画遅延（テスト・診断用）。
    pub fn delay(&self) -> Duration {
        self.delay
    }

    /// 新しい権威スナップショットを取り込む。`audio_cues` は pending に移し、再再生を防ぐ。
    /// 受信間隔×2 を目標遅延とし、EMA で緩やかに追従する（ジッターによる render_time 跳ねを抑制）。
    ///
    /// `received_at` はフレーム権威順で単調非減少であること。最新より古い時刻の
    /// push は破棄する（補間の時間逆行・SE 重複を防ぐ）。到着時刻だけのスタンプでは
    /// ペイロードのアウトオブオーダーは検知できない点に注意。
    pub fn push(&mut self, mut frame: RenderFrame, received_at: Instant) {
        if let Some((curr_at, _)) = &self.curr {
            if received_at < *curr_at {
                // 順序逆転した古いフレームは無視する
                return;
            }
            let interval = received_at.saturating_duration_since(*curr_at);
            if !interval.is_zero() {
                let target = interval
                    .saturating_mul(2)
                    .clamp(INTERP_DELAY_MIN, INTERP_DELAY_MAX);
                let current_ms = self.delay.as_secs_f64() * 1000.0;
                let target_ms = target.as_secs_f64() * 1000.0;
                let next_ms =
                    current_ms * (1.0 - DELAY_EMA_ALPHA) + target_ms * DELAY_EMA_ALPHA;
                self.delay = Duration::from_secs_f64((next_ms / 1000.0).max(0.0))
                    .clamp(INTERP_DELAY_MIN, INTERP_DELAY_MAX);
            }
        }
        let cues = std::mem::take(&mut frame.audio_cues);
        if !cues.is_empty() {
            self.pending_audio.extend(cues);
        }
        self.prev = self.curr.take();
        self.curr = Some((received_at, frame));
    }

    /// 新規受信フレーム由来の SE キューを取り出す（描画サンプルとは独立）。
    pub fn take_pending_audio(&mut self) -> Vec<String> {
        std::mem::take(&mut self.pending_audio)
    }

    /// `now` 時点の表示用フレームを返す。スナップショットが無い場合は `None`。
    pub fn sample(&self, now: Instant) -> Option<RenderFrame> {
        let render_time = now.checked_sub(self.delay).unwrap_or(now);

        match (&self.prev, &self.curr) {
            (None, None) => None,
            (None, Some((_, curr))) => Some(curr.clone()),
            (Some((_, prev)), None) => Some(prev.clone()),
            (Some((prev_at, prev)), Some((curr_at, curr))) => {
                let span = curr_at.saturating_duration_since(*prev_at);
                if span.is_zero() {
                    return Some(curr.clone());
                }

                let since_prev = render_time.saturating_duration_since(*prev_at);
                let t = (since_prev.as_secs_f64() / span.as_secs_f64()) as f32;

                if t <= 0.0 {
                    Some(prev.clone())
                } else if t >= 1.0 {
                    Some(curr.clone())
                } else {
                    Some(interpolate_render_frame(prev, curr, t))
                }
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

        // render_time = now - 100ms = t0 + 25ms → t = 25/50 = 0.5
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
        // A→B' を補間して瞬間移動になる。近傍マッチなら B→B' になる。
        let prev = RenderFrame {
            commands: vec![sphere_at(0.0, 0.0), sphere_at(10.0, 0.0)],
            ..Default::default()
        };
        let curr = RenderFrame {
            commands: vec![sphere_at(10.5, 0.0)],
            ..Default::default()
        };
        let mid = interpolate_render_frame(&prev, &curr, 0.5);
        assert_eq!(mid.commands.len(), 1);
        match &mid.commands[0] {
            DrawCommand::Sphere3D { x, z, .. } => {
                assert!((*x - 10.25).abs() < 1e-4, "x={x} (should track B, not A)");
                assert!(z.abs() < 1e-4);
            }
            other => panic!("unexpected: {other:?}"),
        }
    }

    #[test]
    fn interpolate_snaps_new_spawn_without_far_match() {
        let prev = RenderFrame {
            commands: vec![sphere_at(0.0, 0.0)],
            ..Default::default()
        };
        // 距離 10 > MAX_MATCH_DISTANCE → 新規スポーン扱い、補間せず curr
        let curr = RenderFrame {
            commands: vec![sphere_at(10.0, 0.0)],
            ..Default::default()
        };
        let mid = interpolate_render_frame(&prev, &curr, 0.5);
        match &mid.commands[0] {
            DrawCommand::Sphere3D { x, .. } => {
                assert!((*x - 10.0).abs() < 1e-5, "x={x}");
            }
            other => panic!("unexpected: {other:?}"),
        }
    }

    #[test]
    fn snapshot_delay_tracks_observed_interval_with_ema() {
        let mut interp = SnapshotInterpolator::with_delay(Duration::from_millis(100));
        let t0 = Instant::now();
        interp.push(player_at(0.0, 0.0), t0);
        // 10Hz 相当: 目標 200ms。1 ステップでは EMA により中間値へ（100*0.9 + 200*0.1 = 110）
        interp.push(player_at(1.0, 0.0), t0 + Duration::from_millis(100));
        let ms = interp.delay().as_secs_f64() * 1000.0;
        assert!((ms - 110.0).abs() < 1.0, "delay_ms={ms}");

        // 同間隔を続けても急変せず、目標へ近づく
        let mut t = t0 + Duration::from_millis(100);
        for _ in 0..30 {
            t += Duration::from_millis(100);
            interp.push(player_at(1.0, 0.0), t);
        }
        let settled = interp.delay().as_secs_f64() * 1000.0;
        assert!(settled > 180.0, "settled_ms={settled}");
        assert!(settled <= 250.0, "settled_ms={settled}");
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
