//! One bounded async executor for Android transports; no per-frame isolate or
//! per-request OS thread. Source actors retain their existing business rules.
use std::sync::OnceLock;

pub fn runtime() -> &'static tokio::runtime::Runtime {
    static RUNTIME: OnceLock<tokio::runtime::Runtime> = OnceLock::new();
    RUNTIME.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .max_blocking_threads(4)
            .thread_name("rq-android-net")
            .enable_all()
            .build()
            .expect("Android network executor")
    })
}

pub fn host_port(host: &str, port: u32) -> String {
    if host.contains(':') {
        format!("[{host}]:{port}")
    } else {
        format!("{host}:{port}")
    }
}
