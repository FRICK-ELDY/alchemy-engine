use crate::world::GameWorldInner;

pub(crate) fn update_score_popups(w: &mut GameWorldInner, dt: f32) {
    for (_, _, _, lt) in w.score_popups.iter_mut() {
        *lt -= dt;
    }
    w.score_popups.retain(|(_, _, _, lt)| *lt > 0.0);
}

pub(crate) fn update_particles(w: &mut GameWorldInner, dt: f32) {
    let plen = w.particles.len();
    for i in 0..plen {
        if !w.particles.alive[i] {
            continue;
        }
        w.particles.positions_x[i] += w.particles.velocities_x[i] * dt;
        w.particles.positions_y[i] += w.particles.velocities_y[i] * dt;
        w.particles.velocities_y[i] += 200.0 * dt;
        w.particles.lifetime[i] -= dt;
        if w.particles.lifetime[i] <= 0.0 {
            w.particles.kill(i);
        }
    }
}
