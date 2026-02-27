//! Path: native/game_nif/src/nif/util.rs
//! Summary: NIF 共通ユーティリティ（lock_poisoned_err）

#[inline]
pub(crate) fn lock_poisoned_err() -> rustler::Error {
    rustler::Error::RaiseAtom("lock_poisoned")
}
