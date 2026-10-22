//! alchemy-host-server — ローカル / ヘッドレス空間ティック権威（スキャフォールド）。
//!
//! 責務正本: `.workspace/0_docs/architecture-v2/host-server.md`
//!
//! 現状: 20Hz で `shared_sim::SimWorld` を進めるのみ。
//! 次: WorldManifest ロード、入力（Room Token）、Zenoh RenderFrame publish（C3）。

use std::env;
use std::thread;
use std::time::{Duration, Instant};

use shared_sim::{SimWorld, AUTHORITATIVE_TICK_HZ, TICK_DT_SECS};

fn main() {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();

    let manifest_id = env::args()
        .nth(1)
        .unwrap_or_else(|| "builtin.formula_test".to_string());

    let mut world = SimWorld::new(&manifest_id);
    let tick_period = Duration::from_secs_f64(1.0 / f64::from(AUTHORITATIVE_TICK_HZ));

    log::info!(
        "alchemy-host-server starting (manifest={}, tick_hz={})",
        world.manifest_id,
        AUTHORITATIVE_TICK_HZ
    );

    let mut next = Instant::now() + tick_period;
    loop {
        world.step(TICK_DT_SECS);

        if world.tick % AUTHORITATIVE_TICK_HZ as u64 == 0 {
            log::info!("tick={} manifest={}", world.tick, world.manifest_id);
        }

        let now = Instant::now();
        if now < next {
            thread::sleep(next - now);
        }
        next += tick_period;
        // 遅延が溜まったら次の目標を「今＋1 period」にリセットし、追いつき連打を避ける。
        if Instant::now() > next + tick_period {
            next = Instant::now() + tick_period;
        }
    }
}
