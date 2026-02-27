//! Path: native/game_native/src/lock_metrics.rs
//! Summary: RwLock 待機時間メトリクス（警告 + 周期レポート）

use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

// 閾値（ADR の guardrail）
pub const READ_WAIT_WARN_US: u64 = 300;
pub const WRITE_WAIT_WARN_US: u64 = 500;
pub const REPORT_INTERVAL_MS: u64 = 5_000;

static READ_WAIT_TOTAL_NS: AtomicU64 = AtomicU64::new(0);
static READ_WAIT_SAMPLES: AtomicU64 = AtomicU64::new(0);
static WRITE_WAIT_TOTAL_NS: AtomicU64 = AtomicU64::new(0);
static WRITE_WAIT_SAMPLES: AtomicU64 = AtomicU64::new(0);
static LAST_REPORT_MS: AtomicU64 = AtomicU64::new(0);

#[inline]
fn now_ms() -> u64 {
    let Ok(dur) = SystemTime::now().duration_since(UNIX_EPOCH) else {
        return 0;
    };
    dur.as_millis().min(u64::MAX as u128) as u64
}

#[inline]
fn as_nanos_u64(dur: Duration) -> u64 {
    dur.as_nanos().min(u64::MAX as u128) as u64
}

pub fn record_read_wait(context: &str, wait: Duration) {
    let wait_us = wait.as_micros().min(u64::MAX as u128) as u64;
    READ_WAIT_TOTAL_NS.fetch_add(as_nanos_u64(wait), Ordering::Relaxed);
    READ_WAIT_SAMPLES.fetch_add(1, Ordering::Relaxed);
    if wait_us >= READ_WAIT_WARN_US {
        log::warn!(
            "RwLock read wait high: {}us (threshold={}us, context={})",
            wait_us,
            READ_WAIT_WARN_US,
            context
        );
    }
    maybe_report();
}

pub fn record_write_wait(context: &str, wait: Duration) {
    let wait_us = wait.as_micros().min(u64::MAX as u128) as u64;
    WRITE_WAIT_TOTAL_NS.fetch_add(as_nanos_u64(wait), Ordering::Relaxed);
    WRITE_WAIT_SAMPLES.fetch_add(1, Ordering::Relaxed);
    if wait_us >= WRITE_WAIT_WARN_US {
        log::warn!(
            "RwLock write wait high: {}us (threshold={}us, context={})",
            wait_us,
            WRITE_WAIT_WARN_US,
            context
        );
    }
    maybe_report();
}

fn maybe_report() {
    let now = now_ms();
    let last = LAST_REPORT_MS.load(Ordering::Relaxed);
    if now.saturating_sub(last) < REPORT_INTERVAL_MS {
        return;
    }
    if LAST_REPORT_MS
        .compare_exchange(last, now, Ordering::AcqRel, Ordering::Relaxed)
        .is_err()
    {
        return;
    }

    let read_samples = READ_WAIT_SAMPLES.swap(0, Ordering::AcqRel);
    let read_total_ns = READ_WAIT_TOTAL_NS.swap(0, Ordering::AcqRel);
    let write_samples = WRITE_WAIT_SAMPLES.swap(0, Ordering::AcqRel);
    let write_total_ns = WRITE_WAIT_TOTAL_NS.swap(0, Ordering::AcqRel);

    let read_avg_us = if read_samples > 0 {
        (read_total_ns / read_samples) / 1_000
    } else {
        0
    };
    let write_avg_us = if write_samples > 0 {
        (write_total_ns / write_samples) / 1_000
    } else {
        0
    };

    log::info!(
        "[LOCK] avg_wait_us(read={}, write={}) samples(read={}, write={}) window={}ms",
        read_avg_us,
        write_avg_us,
        read_samples,
        write_samples,
        REPORT_INTERVAL_MS
    );
}
