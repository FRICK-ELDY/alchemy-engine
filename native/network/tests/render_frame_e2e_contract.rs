use network::protobuf_render_frame::decode_pb_render_frame;
use render::{CameraParams, DrawCommand, UiComponent};

// Golden fixture: same bytes as `Content.FrameEncoder.encode_frame/5` (same `proto/render_frame.proto`).
// Regenerate: `mix run` a one-off script that calls `Content.FrameEncoder.encode_frame/5` with the
// same tuples as the assertions below, `File.write!` to this path, then rerun `cargo test -p network`.
const GOLDEN_FRAME: &[u8] = include_bytes!("fixtures/render_frame_elixir_golden.bin");

#[test]
fn decode_elixir_generated_render_frame_golden() {
    let frame = decode_pb_render_frame(GOLDEN_FRAME).expect("golden frame must decode");

    assert_eq!(frame.commands.len(), 3);
    assert_eq!(frame.mesh_definitions.len(), 1);
    assert_eq!(frame.ui.nodes.len(), 1);
    assert_eq!(frame.cursor_grab, Some(true));

    match &frame.camera {
        CameraParams::Camera2D { offset_x, offset_y } => {
            assert!((*offset_x - 7.5).abs() < 1.0e-6);
            assert!((*offset_y + 4.25).abs() < 1.0e-6);
        }
        _ => panic!("expected Camera2D"),
    }

    match &frame.commands[0] {
        DrawCommand::PlayerSprite { x, y, frame } => {
            assert!((*x - 10.0).abs() < 1.0e-6);
            assert!((*y - 20.0).abs() < 1.0e-6);
            assert_eq!(*frame, 3);
        }
        _ => panic!("expected PlayerSprite as first command"),
    }

    match &frame.commands[1] {
        DrawCommand::Particle {
            x,
            y,
            r,
            g,
            b,
            alpha,
            size,
        } => {
            assert!((*x - 1.0).abs() < 1.0e-6);
            assert!((*y - 2.0).abs() < 1.0e-6);
            assert!((*r - 0.1).abs() < 1.0e-6);
            assert!((*g - 0.2).abs() < 1.0e-6);
            assert!((*b - 0.3).abs() < 1.0e-6);
            assert!((*alpha - 0.8).abs() < 1.0e-6);
            assert!((*size - 5.0).abs() < 1.0e-6);
        }
        _ => panic!("expected Particle as second command"),
    }

    match &frame.commands[2] {
        DrawCommand::Box3D {
            x,
            y,
            z,
            half_w,
            half_h,
            half_d,
            color,
        } => {
            assert!((*x - 1.0).abs() < 1.0e-6);
            assert!((*y - 2.0).abs() < 1.0e-6);
            assert!((*z - 3.0).abs() < 1.0e-6);
            assert!((*half_w - 0.5).abs() < 1.0e-6);
            assert!((*half_h - 0.6).abs() < 1.0e-6);
            assert!((*half_d - 0.7).abs() < 1.0e-6);
            assert!((color[0] - 0.1).abs() < 1.0e-6);
            assert!((color[1] - 0.2).abs() < 1.0e-6);
            assert!((color[2] - 0.3).abs() < 1.0e-6);
            assert!((color[3] - 1.0).abs() < 1.0e-6);
        }
        _ => panic!("expected Box3D as third command"),
    }

    let first_node = &frame.ui.nodes[0];
    match &first_node.component {
        UiComponent::Text { text, bold, .. } => {
            assert_eq!(text, "golden");
            assert!(*bold);
        }
        _ => panic!("expected first ui node to be text"),
    }

    let mesh = &frame.mesh_definitions[0];
    assert_eq!(mesh.name, "tri");
    assert_eq!(mesh.vertices.len(), 3);
    assert_eq!(mesh.indices, vec![0, 1, 2]);
}
