//! Android WebSocket transport with the same ABI as the Windows transport.
//! Queue limits, raw messages, HTTP rejection codes and explicit disposal are
//! preserved; feed authentication/retry policies remain in the source actor.
use futures_util::{SinkExt, StreamExt};
use std::{
    collections::{HashMap, VecDeque},
    ffi::{c_void, CStr},
    ptr,
    sync::{
        atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering},
        Arc, Condvar, Mutex, OnceLock,
    },
    time::Duration,
};
use tokio::task::AbortHandle;
use tokio_tungstenite::{
    tungstenite::{
        self,
        client::IntoClientRequest,
        protocol::{CloseFrame, WebSocketConfig},
        Message,
    },
    Connector,
};
const LIMIT: usize = 64 * 1024 * 1024;
#[repr(C)]
pub(crate) struct DartObject {
    kind: i32,
    value: [i64; 5],
}
type Post = unsafe extern "C" fn(i64, *mut DartObject) -> bool;
struct Event {
    kind: u32,
    code: u32,
    bytes: Vec<u8>,
}
#[derive(Default)]
struct Events {
    queue: VecDeque<Event>,
    bytes: usize,
    delivered: Vec<u8>,
}
enum Command {
    Send(Vec<u8>, bool),
    Close(u16, Vec<u8>),
}
struct Session {
    sender: tokio::sync::mpsc::UnboundedSender<Command>,
    events: Mutex<Events>,
    stopped: AtomicBool,
    outgoing: AtomicUsize,
    finished: (Mutex<bool>, Condvar),
    task: Mutex<Option<AbortHandle>>,
    port: i64,
    post: Post,
}
impl Session {
    fn event(&self, kind: u32, code: u32, bytes: Vec<u8>) -> bool {
        if self.stopped.load(Ordering::Acquire) {
            return false;
        }
        let mut q = self.events.lock().unwrap();
        if q.bytes + bytes.len() > LIMIT {
            return false;
        }
        let notify = q.queue.is_empty();
        q.bytes += bytes.len();
        q.queue.push_back(Event { kind, code, bytes });
        drop(q);
        if notify {
            let mut o = DartObject {
                kind: 3,
                value: [1, 0, 0, 0, 0],
            };
            return unsafe { (self.post)(self.port, &mut o) };
        }
        true
    }
}
static SESSIONS: OnceLock<Mutex<HashMap<u64, Arc<Session>>>> = OnceLock::new();
static NEXT: AtomicU64 = AtomicU64::new(1);
static WORKERS: AtomicUsize = AtomicUsize::new(0);
fn registry() -> &'static Mutex<HashMap<u64, Arc<Session>>> {
    SESSIONS.get_or_init(Default::default)
}
fn session(id: u64) -> Option<Arc<Session>> {
    registry().lock().unwrap().get(&id).cloned()
}
struct Completion(Arc<Session>);
impl Drop for Completion {
    fn drop(&mut self) {
        self.0.event(6, 0, vec![]);
        self.0.stopped.store(true, Ordering::Release);
        WORKERS.fetch_sub(1, Ordering::Relaxed);
        *self.0.finished.0.lock().unwrap() = true;
        self.0.finished.1.notify_all();
    }
}
// Used only when the caller explicitly requests the existing certificate
// exception; ordinary authenticated sources always use verified rustls TLS.
#[derive(Debug)]
struct AcceptRequestedCertificate;
impl rustls::client::danger::ServerCertVerifier for AcceptRequestedCertificate {
    fn verify_server_cert(
        &self,
        _: &rustls::pki_types::CertificateDer<'_>,
        _: &[rustls::pki_types::CertificateDer<'_>],
        _: &rustls::pki_types::ServerName<'_>,
        _: &[u8],
        _: rustls::pki_types::UnixTime,
    ) -> Result<rustls::client::danger::ServerCertVerified, rustls::Error> {
        Ok(rustls::client::danger::ServerCertVerified::assertion())
    }
    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &rustls::pki_types::CertificateDer<'_>,
        dss: &rustls::DigitallySignedStruct,
    ) -> Result<rustls::client::danger::HandshakeSignatureValid, rustls::Error> {
        rustls::crypto::verify_tls12_signature(
            message,
            cert,
            dss,
            &rustls::crypto::ring::default_provider().signature_verification_algorithms,
        )
    }
    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &rustls::pki_types::CertificateDer<'_>,
        dss: &rustls::DigitallySignedStruct,
    ) -> Result<rustls::client::danger::HandshakeSignatureValid, rustls::Error> {
        rustls::crypto::verify_tls13_signature(
            message,
            cert,
            dss,
            &rustls::crypto::ring::default_provider().signature_verification_algorithms,
        )
    }
    fn supported_verify_schemes(&self) -> Vec<rustls::SignatureScheme> {
        rustls::crypto::ring::default_provider()
            .signature_verification_algorithms
            .supported_schemes()
    }
}
fn error_code(error: &tungstenite::Error) -> u32 {
    match error {
        tungstenite::Error::Http(response) => 0x10000 | response.status().as_u16() as u32,
        tungstenite::Error::Capacity(_) => 1009,
        tungstenite::Error::Utf8(_) => 1007,
        _ => 12029,
    }
}
#[no_mangle]
pub extern "C" fn rq_ws_abi_version() -> u32 {
    1
}
#[no_mangle]
pub unsafe extern "C" fn rq_ws_open(
    host: *const u8,
    path: *const u8,
    headers: *const u8,
    port: u32,
    flags: u32,
    timeout: u32,
    keepalive: u32,
    dart_port: i64,
    post: Post,
) -> u64 {
    if host.is_null() || path.is_null() || headers.is_null() || port == 0 || port > 65535 {
        return 0;
    }
    let read = |p: *const u8| {
        unsafe { CStr::from_ptr(p.cast()) }
            .to_str()
            .map(str::to_owned)
    };
    let (Ok(host), Ok(path), Ok(headers)) = (read(host), read(path), read(headers)) else {
        return 0;
    };
    let url = format!(
        "{}://{}{}",
        if flags & 1 != 0 { "wss" } else { "ws" },
        crate::android_network::host_port(&host, port),
        path
    );
    let Ok(mut request) = url.into_client_request() else {
        return 0;
    };
    for line in headers.split("\r\n").filter(|s| !s.is_empty()) {
        let Some((name, value)) = line.split_once(':') else {
            return 0;
        };
        let (Ok(name), Ok(value)) = (
            tungstenite::http::HeaderName::from_bytes(name.trim().as_bytes()),
            tungstenite::http::HeaderValue::from_str(value.trim()),
        ) else {
            return 0;
        };
        request.headers_mut().insert(name, value);
    }
    let connector = (flags & 2 != 0).then(|| {
        Connector::Rustls(Arc::new(
            rustls::ClientConfig::builder()
                .dangerous()
                .with_custom_certificate_verifier(Arc::new(AcceptRequestedCertificate))
                .with_no_client_auth(),
        ))
    });
    let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel();
    let id = NEXT.fetch_add(1, Ordering::Relaxed);
    let s = Arc::new(Session {
        sender: tx,
        events: Mutex::new(Events::default()),
        stopped: AtomicBool::new(false),
        outgoing: AtomicUsize::new(0),
        finished: (Mutex::new(false), Condvar::new()),
        task: Mutex::new(None),
        port: dart_port,
        post,
    });
    registry().lock().unwrap().insert(id, s.clone());
    WORKERS.fetch_add(1, Ordering::Relaxed);
    let completion = Completion(s.clone());
    let owner = s.clone();
    let job = crate::android_network::runtime().spawn(async move {
        let _completion = completion;
        let config = WebSocketConfig::default().max_message_size(Some(LIMIT)).max_frame_size(Some(LIMIT));
        let connect = tokio_tungstenite::connect_async_tls_with_config(request, Some(config), true, connector);
        let connect = tokio::time::timeout(Duration::from_millis(timeout.clamp(1, 120000) as u64), connect);
        tokio::pin!(connect);
        let mut pending = VecDeque::new();
        let mut socket = loop {
            tokio::select! {
                result = &mut connect => match result {
                    Ok(Ok((socket, _))) => break socket,
                    Ok(Err(error)) => { owner.event(4, error_code(&error), vec![]); return; }
                    Err(_) => { owner.event(4, 12002, vec![]); return; }
                },
                command = rx.recv() => match command {
                    Some(Command::Close(code, bytes)) => {
                        owner.event(5, code as u32, bytes);
                        return; // Drop the in-flight DNS/TLS/HTTP handshake.
                    }
                    Some(command) => pending.push_back(command),
                    None => return,
                }
            }
        };
        if !owner.event(1, 0, vec![]) { return; }
        let mut tick = tokio::time::interval(Duration::from_millis(keepalive.max(15000) as u64));
        tick.tick().await;
        let mut closing = None;
        loop {
            tokio::select! {
                command = async { match pending.pop_front() {
                    Some(command) => Some(command),
                    None => rx.recv().await,
                } } => match command {
                    Some(Command::Send(bytes, text)) => {
                        let len = bytes.len();
                        let message = if text {
                            match String::from_utf8(bytes) {
                                Ok(s) => Message::Text(s.into()),
                                Err(_) => { owner.event(4, 1007, vec![]); break; }
                            }
                        } else { Message::Binary(bytes.into()) };
                        let result = socket.send(message).await;
                        owner.outgoing.fetch_sub(len, Ordering::Relaxed);
                        if let Err(error) = result { owner.event(4, error_code(&error), vec![]); break; }
                    }
                    Some(Command::Close(code, reason)) => {
                        let frame = CloseFrame { code: code.into(), reason: String::from_utf8_lossy(&reason).into_owned().into() };
                        if socket.close(Some(frame)).await.is_err() { break; }
                        closing = Some(tokio::time::Instant::now() + Duration::from_secs(5));
                    }
                    None => break,
                },
                message = socket.next() => match message {
                    Some(Ok(Message::Text(text))) => {
                        if !owner.event(2, 0, text.as_bytes().to_vec()) { owner.event(4, 1009, vec![]); break; }
                    }
                    Some(Ok(Message::Binary(bytes))) => {
                        if !owner.event(3, 0, bytes.to_vec()) { owner.event(4, 1009, vec![]); break; }
                    }
                    Some(Ok(Message::Close(frame))) => {
                        let (code, bytes) = frame.map(|f| (u16::from(f.code) as u32, f.reason.as_bytes().to_vec())).unwrap_or((1005, vec![]));
                        owner.event(5, code, bytes);
                        let _ = socket.flush().await;
                        break;
                    }
                    Some(Ok(_)) => { if socket.flush().await.is_err() { break; } }
                    Some(Err(error)) => { owner.event(4, error_code(&error), vec![]); break; }
                    None => break,
                },
                _ = tick.tick(), if keepalive != 0 => {
                    // Match WinHTTP's unsolicited-pong keepalive, not the
                    // ping/deadline contract used by the separate EMSC path.
                    if socket.send(Message::Pong(vec![].into())).await.is_err() { break; }
                },
                _ = async { if let Some(t) = closing { tokio::time::sleep_until(t).await; }
                    else { std::future::pending::<()>().await; } } => break,
            }
        }
    });
    *s.task.lock().unwrap() = Some(job.abort_handle());
    id
}
#[no_mangle]
pub unsafe extern "C" fn rq_ws_send(id: u64, input: *const u8, length: usize, text: u32) -> u32 {
    let Some(s) = session(id) else {
        return 1;
    };
    if s.stopped.load(Ordering::Acquire) || length > LIMIT || (length != 0 && input.is_null()) {
        return 1;
    }
    if s.outgoing.fetch_add(length, Ordering::Relaxed) + length > LIMIT {
        s.outgoing.fetch_sub(length, Ordering::Relaxed);
        return 2;
    }
    let bytes = if length == 0 {
        vec![]
    } else {
        unsafe { std::slice::from_raw_parts(input, length) }.to_vec()
    };
    if s.sender.send(Command::Send(bytes, text != 0)).is_err() {
        s.outgoing.fetch_sub(length, Ordering::Relaxed);
        return 1;
    }
    0
}
#[no_mangle]
pub unsafe extern "C" fn rq_ws_take(
    id: u64,
    length: *mut usize,
    kind: *mut u32,
    code: *mut u32,
) -> *const u8 {
    if length.is_null() || kind.is_null() || code.is_null() {
        return ptr::null();
    }
    let Some(s) = session(id) else {
        return ptr::null();
    };
    let mut events = s.events.lock().unwrap();
    let Some(event) = events.queue.pop_front() else {
        return ptr::null();
    };
    events.bytes -= event.bytes.len();
    events.delivered = event.bytes;
    unsafe {
        *length = events.delivered.len();
        *kind = event.kind;
        *code = event.code;
    }
    events.delivered.as_ptr()
}
#[no_mangle]
pub unsafe extern "C" fn rq_ws_close(id: u64, code: u32, reason: *const u8, length: usize) {
    if length > 123 || (length != 0 && reason.is_null()) {
        return;
    }
    if let Some(s) = session(id) {
        let bytes = if length == 0 {
            vec![]
        } else {
            unsafe { std::slice::from_raw_parts(reason, length) }.to_vec()
        };
        let _ = s.sender.send(Command::Close(code as u16, bytes));
    }
}
fn release(id: u64) -> Option<Arc<Session>> {
    let s = registry().lock().unwrap().remove(&id)?;
    s.stopped.store(true, Ordering::Release);
    if let Some(task) = s.task.lock().unwrap().take() {
        task.abort();
    }
    Some(s)
}
#[no_mangle]
pub extern "C" fn rq_ws_release(id: u64) {
    release(id);
}
pub(crate) fn release_and_wait(id: u64) -> bool {
    let Some(s) = release(id) else {
        return true;
    };
    let finished = s.finished.0.lock().unwrap();
    let done = *s
        .finished
        .1
        .wait_timeout_while(finished, Duration::from_secs(6), |v| !*v)
        .unwrap()
        .0;
    done
}
#[no_mangle]
pub extern "C" fn rq_ws_release_finalizer(id: *mut c_void) {
    rq_ws_release(id as usize as u64);
}
#[no_mangle]
pub extern "C" fn rq_ws_workers() -> usize {
    WORKERS.load(Ordering::Relaxed)
}
