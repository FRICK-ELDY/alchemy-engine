//! Path: native/nif/src/nif/decode/camera.rs
//! Summary: CameraParams の Elixir タプル → Rust 変換

use render::CameraParams;
use rustler::{Atom, Error as NifError, NifResult, Term};

use super::tag_of;

pub fn decode_camera(term: Term) -> NifResult<CameraParams> {
    let tag_str = tag_of(term)?;

    match tag_str.as_str() {
        // {:camera_2d, offset_x, offset_y}
        "camera_2d" => {
            let (_, offset_x, offset_y): (Atom, f64, f64) = term.decode().map_err(|_| {
                NifError::Term(Box::new(
                    "CameraParams: expected {:camera_2d, offset_x, offset_y}",
                ))
            })?;
            Ok(CameraParams::Camera2D {
                offset_x: offset_x as f32,
                offset_y: offset_y as f32,
            })
        }
        // {:camera_3d, {eye_x, eye_y, eye_z}, {target_x, target_y, target_z}, {up_x, up_y, up_z}, {fov_deg, near, far}}
        "camera_3d" => {
            #[allow(clippy::type_complexity)]
            let (_, eye, target, up, (fov_deg, near, far)): (
                Atom,
                (f64, f64, f64),
                (f64, f64, f64),
                (f64, f64, f64),
                (f64, f64, f64),
            ) = term.decode().map_err(|_| {
                NifError::Term(Box::new(
                    "CameraParams: expected {:camera_3d, {ex,ey,ez}, {tx,ty,tz}, {ux,uy,uz}, {fov,near,far}}",
                ))
            })?;
            Ok(CameraParams::Camera3D {
                eye: [eye.0 as f32, eye.1 as f32, eye.2 as f32],
                target: [target.0 as f32, target.1 as f32, target.2 as f32],
                up: [up.0 as f32, up.1 as f32, up.2 as f32],
                fov_deg: fov_deg as f32,
                near: near as f32,
                far: far as f32,
            })
        }
        other => Err(NifError::Term(Box::new(format!(
            "CameraParams: unknown tag '{other}'"
        )))),
    }
}
