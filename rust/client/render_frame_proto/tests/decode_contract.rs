//! **役割（薄いスモーク）**: `render_frame_proto` が golden をクラッシュなくデコードできること、
//! および代表バリアント（先頭 `DrawCommand`）が壊れていないことを確認する。
//!
//! **フィールド網羅・数値の詳細比較・golden 再生成手順の SSoT**は
//! `native/network/tests/render_frame_e2e_contract.rs` に集約する。golden を更新したときは
//! まずそちらを更新し、ここは「デコード成功＋先頭コマンドのみ」に留める（二重メンテを避ける）。

use render_frame_proto::decode_pb_render_frame;
use shared::render_frame::DrawCommand;

// network の E2E と同一バイト列（再生成手順は network テスト先頭コメント参照）。
const GOLDEN_FRAME: &[u8] =
    include_bytes!("../../network/tests/fixtures/render_frame_elixir_golden.bin");

#[test]
fn golden_decodes_and_first_draw_command_matches_smoke() {
    let frame = decode_pb_render_frame(GOLDEN_FRAME).expect("golden frame must decode");

    assert_eq!(frame.commands.len(), 3, "smoke: command list shape");

    match &frame.commands[0] {
        DrawCommand::PlayerSprite { x, y, frame } => {
            assert!((*x - 10.0).abs() < 1.0e-6);
            assert!((*y - 20.0).abs() < 1.0e-6);
            assert_eq!(*frame, 3);
        }
        _ => panic!("expected PlayerSprite as first command"),
    }
}

#[test]
fn reject_truncated_or_garbage_payload() {
    assert!(decode_pb_render_frame(&[0, 1, 2, 3]).is_err());
}
