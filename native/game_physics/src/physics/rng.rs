//! Path: native/game_core/src/physics/rng.rs
//! Summary: 決定論的 LCG 乱数ジェネレータ（no-std 互換）

pub struct SimpleRng(u64);

impl SimpleRng {
    pub fn new(seed: u64) -> Self {
        Self(seed)
    }

    pub fn next_u32(&mut self) -> u32 {
        self.0 = self
            .0
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        (self.0 >> 33) as u32
    }

    pub fn next_f32(&mut self) -> f32 {
        self.next_u32() as f32 / u32::MAX as f32
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn deterministic_reproducibility() {
        let mut rng = SimpleRng::new(12345);
        let a: Vec<u32> = (0..10).map(|_| rng.next_u32()).collect();
        let mut rng2 = SimpleRng::new(12345);
        let b: Vec<u32> = (0..10).map(|_| rng2.next_u32()).collect();
        assert_eq!(a, b);
    }

    #[test]
    fn next_f32_in_range() {
        let mut rng = SimpleRng::new(999);
        for _ in 0..100 {
            let f = rng.next_f32();
            assert!(f >= 0.0 && f <= 1.0);
        }
    }
}
