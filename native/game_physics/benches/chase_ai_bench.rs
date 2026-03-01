//! Path: native/game_physics/benches/chase_ai_bench.rs
//! Summary: Chase AI 縺ｮ rayon 荳ｦ蛻礼沿縺ｨ SIMD 迚医・繝吶Φ繝√・繝ｼ繧ｯ・域雰謨ｰ 100縲・0000 菴難ｼ・

use criterion::{criterion_group, criterion_main, BenchmarkId, Criterion};
use game_simulation::{
    entity_params::EnemyParams,
    game_logic::{update_chase_ai, update_chase_ai_simd},
    world::EnemyWorld,
};

fn make_params() -> EnemyParams {
    EnemyParams {
        max_hp:           100.0,
        speed:            80.0,
        radius:           20.0,
        damage_per_sec:   10.0,
        render_kind:      1,
        particle_color:   [1.0, 0.0, 0.0, 1.0],
        passes_obstacles: false,
    }
}

fn make_world(n: usize) -> EnemyWorld {
    let mut world = EnemyWorld::new();
    let ep = make_params();
    let positions: Vec<(f32, f32)> = (0..n)
        .map(|i| (i as f32 * 5.0, (i % 100) as f32 * 5.0))
        .collect();
    world.spawn(&positions, 0, &ep);
    world
}

fn bench_rayon(c: &mut Criterion) {
    let mut group = c.benchmark_group("chase_ai_rayon");
    for &n in &[100usize, 500, 1000, 5000, 10000] {
        group.bench_with_input(BenchmarkId::from_parameter(n), &n, |b, &n| {
            let mut world = make_world(n);
            b.iter(|| {
                update_chase_ai(&mut world, 400.0, 300.0, 0.016);
            });
        });
    }
    group.finish();
}

#[cfg(target_arch = "x86_64")]
fn bench_simd(c: &mut Criterion) {
    let mut group = c.benchmark_group("chase_ai_simd");
    for &n in &[100usize, 500, 1000, 5000, 10000] {
        group.bench_with_input(BenchmarkId::from_parameter(n), &n, |b, &n| {
            let mut world = make_world(n);
            b.iter(|| {
                update_chase_ai_simd(&mut world, 400.0, 300.0, 0.016);
            });
        });
    }
    group.finish();
}

#[cfg(not(target_arch = "x86_64"))]
fn bench_simd(_c: &mut Criterion) {}

criterion_group!(benches, bench_rayon, bench_simd);
criterion_main!(benches);
