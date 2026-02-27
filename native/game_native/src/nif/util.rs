//! Path: native/game_native/src/nif/util.rs
//! Summary: NIF 共通ユーティリティ（lock_poisoned_err）

/// RwLock の PoisonError を NifResult に変換するヘルパー
#[inline]
pub(crate) fn lock_poisoned_err() -> rustler::Error {
    rustler::Error::RaiseAtom("lock_poisoned")
}
