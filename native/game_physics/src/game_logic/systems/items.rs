use crate::item::ItemKind;
use crate::world::{FrameEvent, GameWorldInner};

/// 1.2.4: アイテム更新（磁石エフェクト + 自動収集）
pub(crate) fn update_items(w: &mut GameWorldInner, dt: f32, px: f32, py: f32) {
    if w.magnet_timer > 0.0 {
        w.magnet_timer = (w.magnet_timer - dt).max(0.0);
    }

    if w.magnet_timer > 0.0 {
        let item_len = w.items.len();
        for i in 0..item_len {
            if !w.items.alive[i] {
                continue;
            }
            if w.items.kinds[i] != ItemKind::Gem {
                continue;
            }
            let dx = px - w.items.positions_x[i];
            let dy = py - w.items.positions_y[i];
            let dist = (dx * dx + dy * dy).sqrt().max(1.0);
            w.items.positions_x[i] += (dx / dist) * 300.0 * dt;
            w.items.positions_y[i] += (dy / dist) * 300.0 * dt;
        }
    }

    let collect_r = if w.magnet_timer > 0.0 {
        9999.0_f32
    } else {
        60.0_f32
    };
    let collect_r_sq = collect_r * collect_r;
    let item_len = w.items.len();
    for i in 0..item_len {
        if !w.items.alive[i] {
            continue;
        }
        let dx = px - w.items.positions_x[i];
        let dy = py - w.items.positions_y[i];
        if dx * dx + dy * dy <= collect_r_sq {
            let item_k = w.items.kinds[i];
            match item_k {
                ItemKind::Gem => {
                    // EXP は撃破時に加算済みのため、収集イベント発行のみ
                }
                ItemKind::Potion => {
                    w.player.hp = (w.player.hp + w.items.value[i] as f32).min(w.player_max_hp);
                    w.particles.emit(px, py, 6, [0.2, 1.0, 0.4, 1.0]);
                }
                ItemKind::Magnet => {
                    w.magnet_timer = 10.0;
                    w.particles.emit(px, py, 8, [1.0, 0.9, 0.2, 1.0]);
                }
            }
            w.frame_events.push(FrameEvent::ItemPickup {
                item_kind: item_k as u8,
            });
            w.items.kill(i);
        }
    }
}
