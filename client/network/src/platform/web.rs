//! Zenoh over WebSocket (WASM) - 将来実装

/// WASM 用クライアントセッション（スケルトン）
pub struct ClientSession;

impl ClientSession {
    pub fn open(_connect_config: &str) -> Result<Self, String> {
        Err("Zenoh WebSocket (WASM) は未実装".to_string())
    }

    pub fn put(&self, _key: &str, _payload: &[u8]) -> Result<(), String> {
        Err("Zenoh WebSocket (WASM) は未実装".to_string())
    }

    pub fn put_drop(&self, _key: &str, _payload: &[u8]) -> Result<(), String> {
        Err("Zenoh WebSocket (WASM) は未実装".to_string())
    }

    pub fn spawn_subscriber<F>(
        &self,
        _key: &str,
        _shutdown: std::sync::Arc<std::sync::atomic::AtomicBool>,
        _on_payload: F,
    ) -> std::thread::JoinHandle<()>
    where
        F: Fn(Vec<u8>) + Send + 'static,
    {
        std::thread::spawn(|| {})
    }
}
