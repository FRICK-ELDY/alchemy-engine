//! ワーカースレッドで API 呼び出しを実行し、UI が毎フレームポーリングする仕組み。

use crate::error::AuthError;
use std::sync::mpsc;
use std::thread;

/// バックグラウンドで実行中の auth API 呼び出し。
///
/// egui は immediate mode なので、フォームは毎フレーム [`AuthTask::try_take`] を
/// 呼んで完了を検出する。結果は一度だけ取り出せる。
pub struct AuthTask<T> {
    receiver: mpsc::Receiver<Result<T, AuthError>>,
}

impl<T: Send + 'static> AuthTask<T> {
    /// ワーカースレッドを起動して `job` を実行する。
    ///
    /// login/register は低頻度操作なのでリクエストごとのスレッド生成で十分。
    pub(crate) fn spawn(job: impl FnOnce() -> Result<T, AuthError> + Send + 'static) -> Self {
        let (sender, receiver) = mpsc::channel();
        thread::spawn(move || {
            // 受信側が先に破棄されていても（フォームが閉じられた等）問題ない
            let _ = sender.send(job());
        });
        Self { receiver }
    }

    /// 完了していれば結果を取り出す。未完了なら `None`。
    ///
    /// ワーカースレッドが panic した場合はネットワークエラーとして返す。
    pub fn try_take(&self) -> Option<Result<T, AuthError>> {
        match self.receiver.try_recv() {
            Ok(result) => Some(result),
            Err(mpsc::TryRecvError::Empty) => None,
            Err(mpsc::TryRecvError::Disconnected) => Some(Err(AuthError::Network(
                "auth request worker terminated unexpectedly".to_string(),
            ))),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{Duration, Instant};

    #[test]
    fn try_take_returns_result_once_finished() {
        let task = AuthTask::spawn(|| Ok::<_, AuthError>(42));

        let deadline = Instant::now() + Duration::from_secs(5);
        loop {
            if let Some(result) = task.try_take() {
                assert_eq!(result, Ok(42));
                break;
            }
            assert!(Instant::now() < deadline, "task did not finish in time");
            thread::sleep(Duration::from_millis(5));
        }
    }

    #[test]
    fn try_take_propagates_errors() {
        let task: AuthTask<i32> =
            AuthTask::spawn(|| Err(AuthError::Network("offline".to_string())));

        let deadline = Instant::now() + Duration::from_secs(5);
        loop {
            if let Some(result) = task.try_take() {
                assert_eq!(result, Err(AuthError::Network("offline".to_string())));
                break;
            }
            assert!(Instant::now() < deadline, "task did not finish in time");
            thread::sleep(Duration::from_millis(5));
        }
    }
}
