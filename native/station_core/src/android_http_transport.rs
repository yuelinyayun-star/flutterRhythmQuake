//! Android implementation of the existing HTTP ABI. Native source actors use
//! the same event stream and own all parsing, timers and source state.
use futures_util::StreamExt;
use std::{
    collections::{HashMap, VecDeque},
    ffi::{c_void, CStr},
    ptr,
    sync::{
        atomic::{AtomicU64, AtomicUsize, Ordering},
        Arc, Mutex, OnceLock,
    },
};
use tokio::{sync::Notify, task::AbortHandle};

#[repr(C)]
pub struct DartObject {
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
struct Queue {
    events: VecDeque<Event>,
    bytes: usize,
}
struct Session {
    client: u64,
    queue: Mutex<Queue>,
    port: i64,
    post: Post,
    drained: Notify,
    task: Mutex<Option<AbortHandle>>,
}
impl Session {
    fn event(&self, kind: u32, code: u32, bytes: Vec<u8>) {
        let mut q = self.queue.lock().unwrap();
        let notify = q.events.is_empty();
        q.bytes += bytes.len();
        PEAK.fetch_max(q.bytes, Ordering::Relaxed);
        q.events.push_back(Event { kind, code, bytes });
        drop(q);
        if notify {
            let mut o = DartObject {
                kind: 3,
                value: [1, 0, 0, 0, 0],
            };
            unsafe {
                (self.post)(self.port, &mut o);
            }
        }
    }
    async fn capacity(&self) {
        loop {
            let notified = self.drained.notified();
            if self.queue.lock().unwrap().bytes < 64 * 1024 {
                return;
            }
            notified.await;
        }
    }
}
#[derive(Clone)]
struct Client {
    regular: reqwest::Client,
    palert: reqwest::Client,
}
static CLIENTS: OnceLock<Mutex<HashMap<u64, Client>>> = OnceLock::new();
static SESSIONS: OnceLock<Mutex<HashMap<u64, Arc<Session>>>> = OnceLock::new();
static NEXT: AtomicU64 = AtomicU64::new(1);
static ACTIVE: AtomicUsize = AtomicUsize::new(0);
static PEAK: AtomicUsize = AtomicUsize::new(0);
fn clients() -> &'static Mutex<HashMap<u64, Client>> {
    CLIENTS.get_or_init(Default::default)
}
fn sessions() -> &'static Mutex<HashMap<u64, Arc<Session>>> {
    SESSIONS.get_or_init(Default::default)
}
struct Active;
impl Drop for Active {
    fn drop(&mut self) {
        ACTIVE.fetch_sub(1, Ordering::Relaxed);
    }
}

pub(crate) fn open_system_client(agent: &str) -> u64 {
    let builder = || {
        reqwest::Client::builder()
            .user_agent(agent)
            .redirect(reqwest::redirect::Policy::none())
            .connect_timeout(std::time::Duration::from_secs(20))
            .read_timeout(std::time::Duration::from_secs(30))
    };
    // Preserve the existing P-Alert-only certificate exception. It is never
    // used for other hosts, redirects, authenticated feeds or ordinary APIs.
    let (Ok(regular), Ok(palert)) = (
        builder().build(),
        builder().danger_accept_invalid_certs(true).build(),
    ) else {
        return 0;
    };
    let id = NEXT.fetch_add(1, Ordering::Relaxed);
    clients()
        .lock()
        .unwrap()
        .insert(id, Client { regular, palert });
    id
}
#[no_mangle]
pub unsafe extern "C" fn rq_http_client_open(agent: *const u8) -> u64 {
    if agent.is_null() {
        return 0;
    }
    let Ok(agent) = unsafe { CStr::from_ptr(agent.cast()) }.to_str() else {
        return 0;
    };
    open_system_client(agent)
}
#[no_mangle]
pub extern "C" fn rq_http_client_close(id: u64) {
    clients().lock().unwrap().remove(&id);
    let ids: Vec<_> = sessions()
        .lock()
        .unwrap()
        .iter()
        .filter_map(|(&key, s)| (s.client == id).then_some(key))
        .collect();
    for id in ids {
        rq_http_release(id);
    }
}
#[no_mangle]
pub extern "C" fn rq_http_client_finalizer(id: *mut c_void) {
    rq_http_client_close(id as usize as u64);
}
#[no_mangle]
pub unsafe extern "C" fn rq_http_open(
    client: u64,
    host: *const u8,
    path: *const u8,
    method: *const u8,
    headers: *const u8,
    body: *const u8,
    body_len: usize,
    port: u32,
    flags: u32,
    dart_port: i64,
    post: Post,
) -> u64 {
    if host.is_null()
        || path.is_null()
        || method.is_null()
        || headers.is_null()
        || port == 0
        || port > 65535
        || body_len > 64 * 1024 * 1024
        || (body_len != 0 && body.is_null())
    {
        return 0;
    }
    let text = |p: *const u8| {
        unsafe { CStr::from_ptr(p.cast()) }
            .to_str()
            .map(str::to_owned)
    };
    let (Ok(host), Ok(path), Ok(method), Ok(headers)) =
        (text(host), text(path), text(method), text(headers))
    else {
        return 0;
    };
    let Some(c) = clients().lock().unwrap().get(&client).cloned() else {
        return 0;
    };
    let c = if flags & 8 != 0 && host == "palert.earth.sinica.edu.tw" {
        c.palert
    } else {
        c.regular
    };
    let Ok(method) = reqwest::Method::from_bytes(method.as_bytes()) else {
        return 0;
    };
    let url = format!(
        "{}://{}{}",
        if flags & 1 != 0 { "https" } else { "http" },
        crate::android_network::host_port(&host, port),
        path
    );
    let mut request = c.request(method, url);
    for line in headers.split("\r\n").filter(|s| !s.is_empty()) {
        let Some((key, value)) = line.split_once(':') else {
            return 0;
        };
        request = request.header(key.trim(), value.trim());
    }
    if flags & 2 != 0 {
        request = request.header("Connection", "close");
    }
    if body_len != 0 {
        request = request.body(unsafe { std::slice::from_raw_parts(body, body_len) }.to_vec());
    }
    let id = NEXT.fetch_add(1, Ordering::Relaxed);
    let s = Arc::new(Session {
        client,
        queue: Mutex::new(Queue::default()),
        port: dart_port,
        post,
        drained: Notify::new(),
        task: Mutex::new(None),
    });
    sessions().lock().unwrap().insert(id, s.clone());
    ACTIVE.fetch_add(1, Ordering::Relaxed);
    let active = Active;
    let owner = s.clone();
    let job = crate::android_network::runtime().spawn(async move {
        let _active = active;
        let result = async {
            let response = request.send().await?;
            let mut headers = format!(
                "HTTP/1.1 {} {}\r\n",
                response.status().as_u16(),
                response.status().canonical_reason().unwrap_or("")
            );
            for (key, value) in response.headers() {
                headers.push_str(key.as_str());
                headers.push_str(": ");
                headers.push_str(value.to_str().unwrap_or(""));
                headers.push_str("\r\n");
            }
            headers.push_str("\r\n");
            let buffered = flags & 4 != 0;
            let headers = headers.into_bytes();
            if !buffered {
                owner.event(1, 0, headers.clone());
            }
            let mut body = Vec::new();
            let mut stream = response.bytes_stream();
            loop {
                if !buffered {
                    owner.capacity().await;
                }
                let Some(chunk) = stream.next().await else {
                    break;
                };
                let chunk = chunk?;
                if buffered {
                    if body.len().saturating_add(chunk.len()) > 64 * 1024 * 1024 {
                        owner.event(4, 1009, vec![]);
                        return Ok::<_, reqwest::Error>(());
                    }
                    body.extend_from_slice(&chunk);
                    continue;
                }
                for part in chunk.chunks(32 * 1024) {
                    owner.capacity().await;
                    owner.event(2, 0, part.to_vec());
                }
            }
            if buffered {
                // The existing Dart zero-copy buffered ABI expects exactly
                // one owned body, while SSE and streaming use bounded chunks.
                owner.event(1, 0, headers);
                owner.event(2, 0, body);
            }
            owner.event(3, 0, vec![]);
            Ok::<_, reqwest::Error>(())
        }
        .await;
        if let Err(error) = result {
            owner.event(4, if error.is_timeout() { 12002 } else { 12029 }, vec![]);
        }
    });
    *s.task.lock().unwrap() = Some(job.abort_handle());
    id
}
#[no_mangle]
pub unsafe extern "C" fn rq_http_take(
    id: u64,
    size: *mut usize,
    kind: *mut u32,
    code: *mut u32,
    owner: *mut *mut c_void,
) -> *const u8 {
    if size.is_null() || kind.is_null() || code.is_null() || owner.is_null() {
        return ptr::null();
    }
    let Some(s) = sessions().lock().unwrap().get(&id).cloned() else {
        return ptr::null();
    };
    let mut q = s.queue.lock().unwrap();
    let Some(event) = q.events.pop_front() else {
        return ptr::null();
    };
    q.bytes -= event.bytes.len();
    drop(q);
    s.drained.notify_one();
    let bytes = Box::new(event.bytes);
    let data = bytes.as_ptr();
    unsafe {
        *size = bytes.len();
        *kind = event.kind;
        *code = event.code;
        *owner = Box::into_raw(bytes).cast();
    }
    data
}
#[no_mangle]
pub unsafe extern "C" fn rq_http_chunk_release(owner: *mut c_void) {
    if !owner.is_null() {
        drop(unsafe { Box::from_raw(owner as *mut Vec<u8>) });
    }
}
#[no_mangle]
pub extern "C" fn rq_http_release(id: u64) {
    if let Some(s) = sessions().lock().unwrap().remove(&id) {
        if let Some(task) = s.task.lock().unwrap().take() {
            task.abort();
        }
    }
}
#[no_mangle]
pub extern "C" fn rq_http_release_finalizer(id: *mut c_void) {
    rq_http_release(id as usize as u64);
}
#[no_mangle]
pub extern "C" fn rq_http_clients() -> usize {
    clients().lock().unwrap().len()
}
#[no_mangle]
pub extern "C" fn rq_http_requests() -> usize {
    ACTIVE.load(Ordering::Relaxed)
}
#[no_mangle]
pub extern "C" fn rq_http_queue_peak() -> usize {
    PEAK.load(Ordering::Relaxed)
}
