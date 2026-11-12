//! JMA image-index source owners. Original HTTP bytes stay in the native worker;
//! Flutter receives only selected frame fields and command acknowledgements.
#![cfg(any(windows, target_os = "android"))]
use crate::http_transport;
use serde_json::{json, Value};
use std::{
    collections::{HashMap, VecDeque},
    ffi::{c_void, CString},
    ptr,
    sync::{
        atomic::{AtomicU64, AtomicUsize, Ordering},
        mpsc, Arc, Mutex, OnceLock, Weak,
    },
    thread,
    time::{Duration, Instant},
};

#[repr(C)]
pub struct DartObject {
    kind: i32,
    value: [i64; 5],
}
type Post = unsafe extern "C" fn(i64, *mut DartObject) -> bool;
struct Shared {
    tx: mpsc::Sender<Command>,
    output: Mutex<VecDeque<Vec<u8>>>,
    port: i64,
    post: Post,
}
enum Command {
    Control(Value),
    Wake,
    Close,
}
struct Owner {
    shared: Arc<Shared>,
    worker: Option<thread::JoinHandle<()>>,
    delivered: Vec<u8>,
}
static NEXT: AtomicU64 = AtomicU64::new(1);
static WORKERS: AtomicUsize = AtomicUsize::new(0);
static SESSIONS: OnceLock<Mutex<HashMap<u64, Weak<Shared>>>> = OnceLock::new();
fn registry() -> &'static Mutex<HashMap<u64, Weak<Shared>>> {
    SESSIONS.get_or_init(Default::default)
}
unsafe extern "C" fn wake(id: i64, _: *mut http_transport::DartObject) -> bool {
    let s = registry()
        .lock()
        .unwrap()
        .get(&(id as u64))
        .and_then(Weak::upgrade);
    s.is_some_and(|s| s.tx.send(Command::Wake).is_ok())
}
fn emit(s: &Shared, v: Value) {
    let mut bytes = vec![b'J'];
    bytes.extend(serde_json::to_vec(&v).unwrap());
    emit_bytes(s, bytes);
}
fn emit_tile(s: &Shared, (id, status, body): (u64, u32, Vec<u8>)) {
    let mut bytes = Vec::with_capacity(13 + body.len());
    bytes.push(b'T');
    bytes.extend_from_slice(&id.to_le_bytes());
    bytes.extend_from_slice(&status.to_le_bytes());
    bytes.extend(body);
    emit_bytes(s, bytes);
}
fn emit_bytes(s: &Shared, bytes: Vec<u8>) {
    let mut out = s.output.lock().unwrap();
    let notify = out.is_empty();
    out.push_back(bytes);
    drop(out);
    if notify {
        let mut object = DartObject {
            kind: 3,
            value: [1, 0, 0, 0, 0],
        };
        unsafe {
            (s.post)(s.port, &mut object);
        }
    }
}
fn days(y: i64, m: i64, d: i64) -> i64 {
    let y = y - i64::from(m <= 2);
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let mp = m + if m > 2 { -3 } else { 9 };
    era * 146097 + yoe * 365 + yoe / 4 - yoe / 100 + (153 * mp + 2) / 5 + d - 1 - 719468
}
fn civil(day: i64) -> (i64, i64, i64) {
    let z = day + 719468;
    let era = z.div_euclid(146097);
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = mp + if mp < 10 { 3 } else { -9 };
    (y + i64::from(m <= 2), m, d)
}
#[repr(C)]
#[derive(Default)]
#[cfg(windows)]
struct SystemTime {
    year: u16,
    month: u16,
    day_of_week: u16,
    day: u16,
    hour: u16,
    minute: u16,
    second: u16,
    millis: u16,
}
#[link(name = "kernel32")]
#[cfg(windows)]
extern "system" {
    fn TzSpecificLocalTimeToSystemTime(
        tz: *const c_void,
        local: *const SystemTime,
        utc: *mut SystemTime,
    ) -> i32;
}
fn stamp(text: &str, satellite: bool) -> Option<i64> {
    let v = if satellite { text } else { text.trim() };
    if (satellite && v.len() != 14)
        || (!satellite && v.len() < 12)
        || !v.bytes().all(|b| b.is_ascii_digit())
    {
        return None;
    }
    let p = |a, b| v.get(a..b)?.parse::<i64>().ok();
    let (mut y, mut m, d, h, mi, se) = (
        p(0, 4)?,
        p(4, 6)?,
        p(6, 8)?,
        p(8, 10)?,
        p(10, 12)?,
        if v.len() >= 14 { p(12, 14)? } else { 0 },
    );
    if satellite {
        let leap = y % 4 == 0 && (y % 100 != 0 || y % 400 == 0);
        let length = match m {
            1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
            4 | 6 | 9 | 11 => 30,
            2 => {
                if leap {
                    29
                } else {
                    28
                }
            }
            _ => return None,
        };
        if d < 1 || d > length || h > 23 || mi > 59 || se > 59 {
            return None;
        }
        return Some((days(y, m, d) * 86400 + h * 3600 + mi * 60 + se) * 1000);
    }
    // Match Dart's existing local DateTime constructor, including overflow
    // normalization. Do not reinterpret radar times as UTC during migration.
    y += (m - 1).div_euclid(12);
    m = (m - 1).rem_euclid(12) + 1;
    let seconds = days(y, m, d) * 86400 + h * 3600 + mi * 60 + se;
    let (year, month, day) = civil(seconds.div_euclid(86400));
    let t = seconds.rem_euclid(86400);
    #[cfg(target_os = "android")]
    return crate::android_platform::local_epoch(year, month, day, t / 3600, t / 60 % 60, t % 60, 0);
    #[cfg(windows)]
    {
    let local = SystemTime {
        year: year as u16,
        month: month as u16,
        day: day as u16,
        hour: (t / 3600) as u16,
        minute: (t / 60 % 60) as u16,
        second: (t % 60) as u16,
        ..Default::default()
    };
    let mut utc = SystemTime::default();
    if unsafe { TzSpecificLocalTimeToSystemTime(ptr::null(), &local, &mut utc) } == 0 {
        return None;
    }
    Some(
        (days(utc.year as i64, utc.month as i64, utc.day as i64) * 86400
            + utc.hour as i64 * 3600
            + utc.minute as i64 * 60
            + utc.second as i64)
            * 1000,
    )
    }
}
#[derive(Clone)]
struct Frame {
    base: String,
    valid: String,
    epoch: i64,
}
fn frame(bytes: &[u8], satellite: bool) -> Option<Frame> {
    let raw: Value =
        serde_json::from_slice(bytes.strip_prefix(&[0xef, 0xbb, 0xbf]).unwrap_or(bytes)).ok()?;
    let mut latest: Option<Frame> = None;
    for row in raw.as_array()? {
        let text = |key| {
            let value = row
                .get(key)
                .filter(|v| !v.is_null())
                .map(|v| {
                    v.as_str()
                        .map(str::to_owned)
                        .unwrap_or_else(|| v.to_string())
                })
                .unwrap_or_default();
            if satellite {
                value
            } else {
                value.trim().to_owned()
            }
        };
        let base = text("basetime");
        let valid = text("validtime");
        if base.is_empty() || valid.is_empty() {
            continue;
        }
        if satellite
            && (!row["basetime"].is_string()
                || !row["validtime"].is_string()
                || stamp(&base, true).is_none())
        {
            continue;
        }
        if !satellite
            && row["elements"]
                .as_array()
                .is_some_and(|v| !v.iter().any(|v| v.as_str() == Some("hrpns")))
        {
            continue;
        }
        let epoch =
            stamp(&valid, satellite).or_else(|| if satellite { None } else { stamp(&base, false) });
        let Some(epoch) = epoch else {
            continue;
        };
        let next = Frame { base, valid, epoch };
        if latest.as_ref().is_none_or(|old| {
            next.epoch > old.epoch
                || (next.epoch == old.epoch
                    && if satellite {
                        next.base > old.base
                    } else {
                        next.valid > old.valid
                    })
        }) {
            latest = Some(next);
        }
    }
    latest
}
struct Request {
    id: u64,
    deadline: Instant,
    status: u32,
    bytes: Vec<u8>,
}
struct Runtime {
    images: crate::jma_tile_images::Images,
    id: u64,
    satellite: bool,
    active: bool,
    generation: u64,
    client: u64,
    interval: Duration,
    next_poll: Option<Instant>,
    retry: Option<Instant>,
    attempts: u64,
    attempt: u64,
    request: Option<Request>,
    queued: bool,
    waiters: Vec<u64>,
    latest: Option<Frame>,
    host: String,
    path: String,
    port: u32,
    secure: bool,
    timeout: Duration,
    requests: u64,
    responses: u64,
    failures: u64,
}
impl Runtime {
    fn new(id: u64, satellite: bool) -> Self {
        Self {
            images: Default::default(),
            id,
            satellite,
            active: false,
            generation: 0,
            client: 0,
            interval: Duration::from_secs(if satellite { 600 } else { 300 }),
            next_poll: None,
            retry: None,
            attempts: 1,
            attempt: 0,
            request: None,
            queued: false,
            waiters: vec![],
            latest: None,
            host: "www.jma.go.jp".into(),
            path: if satellite {
                "/bosai/himawari/data/satimg/targetTimes_fd.json"
            } else {
                "/bosai/jmatile/data/nowc/targetTimes_N1.json"
            }
            .into(),
            port: 443,
            secure: true,
            timeout: Duration::from_secs(20),
            requests: 0,
            responses: 0,
            failures: 0,
        }
    }
    fn publish(&self, s: &Shared) {
        emit(
            s,
            json!({"type":"frame","generation":self.generation,"frame":self.latest.as_ref().map(|f|json!({"basetime":f.base,"validtime":f.valid,"epochMs":f.epoch,"utc":self.satellite}))}),
        );
    }
    fn ack(&self, s: &Shared, id: u64) {
        if id != 0 {
            emit(s, json!({"type":"complete","request":id}));
        }
    }
    fn cancel(&mut self, s: &Shared) {
        for result in self.images.clear() {
            emit_tile(s, result);
        }
        if let Some(r) = self.request.take() {
            http_transport::rq_http_release(r.id);
        }
        self.retry = None;
        self.queued = false;
        for id in std::mem::take(&mut self.waiters) {
            self.ack(s, id);
        }
    }
    fn begin(&mut self) {
        if self.client == 0 {
            self.client = http_transport::open_system_client("flutterrhythmquake/1.0");
        }
        let headers = if self.satellite {
            "Accept-Encoding: gzip\r\n"
        } else {
            "Accept: application/json, text/plain, */*\r\nReferer: https://www.jma.go.jp/bosai/nowc/\r\nUser-Agent: flutterrhythmquake/1.0\r\nAccept-Encoding: gzip\r\n"
        };
        let host = CString::new(self.host.clone()).unwrap();
        let path = CString::new(self.path.clone()).unwrap();
        let headers = CString::new(headers).unwrap();
        let id = unsafe {
            http_transport::rq_http_open(
                self.client,
                host.as_ptr().cast(),
                path.as_ptr().cast(),
                c"GET".as_ptr().cast(),
                headers.as_ptr().cast(),
                ptr::null(),
                0,
                self.port,
                4 | 8 | u32::from(self.secure),
                self.id as i64,
                wake,
            )
        };
        self.requests += 1;
        self.attempt += 1;
        self.retry = None;
        self.request = Some(Request {
            id,
            deadline: Instant::now() + self.timeout,
            status: 0,
            bytes: vec![],
        });
    }
    fn finish(&mut self, s: &Shared, ok: bool) {
        if !ok {
            self.failures += 1;
        }
        if !ok && self.active && self.attempt < self.attempts {
            self.retry = Some(Instant::now() + Duration::from_secs(self.attempt.saturating_mul(2)));
            return;
        }
        if self.queued && self.active {
            self.queued = false;
            self.attempt = 0;
            self.begin();
            return;
        }
        for id in std::mem::take(&mut self.waiters) {
            self.ack(s, id);
        }
    }
    fn drain(&mut self, s: &Shared) {
        let Some(r) = self.request.as_mut() else {
            return;
        };
        let mut done = None;
        loop {
            let (mut len, mut kind, mut code, mut owner) = (0, 0, 0, ptr::null_mut());
            let p = unsafe {
                http_transport::rq_http_take(r.id, &mut len, &mut kind, &mut code, &mut owner)
            };
            if p.is_null() {
                break;
            }
            let bytes = unsafe { std::slice::from_raw_parts(p, len) };
            match kind {
                1 => {
                    r.status = std::str::from_utf8(bytes)
                        .ok()
                        .and_then(|s| s.split_whitespace().nth(1))
                        .and_then(|s| s.parse().ok())
                        .unwrap_or(0)
                }
                2 => {
                    r.bytes.extend_from_slice(bytes);
                    if r.bytes.len() > 8 * 1024 * 1024 {
                        done = Some(false);
                    }
                }
                3 => done = Some(r.status == 200),
                4 => done = Some(false),
                _ => {}
            }
            unsafe {
                http_transport::rq_http_chunk_release(owner);
            }
            if done.is_some() {
                break;
            }
        }
        if done.is_none() && Instant::now() >= r.deadline {
            done = Some(false);
        }
        if let Some(ok) = done {
            let r = self.request.take().unwrap();
            http_transport::rq_http_release(r.id);
            self.responses += 1;
            let next = if ok {
                frame(&r.bytes, self.satellite)
            } else {
                None
            };
            let success = next.is_some();
            if let Some(next) = next {
                let unchanged = self
                    .latest
                    .as_ref()
                    .is_some_and(|p| p.base == next.base && p.valid == next.valid);
                let older =
                    self.satellite && self.latest.as_ref().is_some_and(|p| next.epoch < p.epoch);
                if !older {
                    self.latest = Some(next);
                    if !unchanged {
                        self.publish(s);
                    }
                }
            }
            self.finish(s, success);
        }
    }
    fn control(&mut self, s: &Shared, c: Value) {
        let id = c["request"].as_u64().unwrap_or(0);
        match c["op"].as_str().unwrap_or("") {
            "start" => {
                if self.active {
                    if !self.satellite && self.latest.is_none() {
                        self.fetch(s, id, c["attempts"].as_u64().unwrap_or(3));
                    } else {
                        self.ack(s, id);
                    }
                    return;
                }
                self.generation = c["generation"].as_u64().unwrap_or(self.generation + 1);
                self.active = true;
                self.interval = Duration::from_millis(
                    c["intervalMs"]
                        .as_u64()
                        .unwrap_or(if self.satellite { 600000 } else { 300000 })
                        .max(1),
                );
                // Endpoint overrides are explicit offline-test configuration.
                if let Some(endpoint) = c.get("testEndpoint") {
                    if let (Some(host), Some(path)) =
                        (endpoint["host"].as_str(), endpoint["path"].as_str())
                    {
                        if !host.contains('\0') && !path.contains('\0') {
                            self.host = host.into();
                            self.path = path.into();
                            self.port = endpoint["port"].as_u64().unwrap_or(80) as u32;
                            self.secure = false;
                        }
                    }
                }
                self.timeout =
                    Duration::from_millis(c["testTimeoutMs"].as_u64().unwrap_or(20000).max(1));
                self.next_poll = Some(Instant::now() + self.interval);
                if self.satellite && self.latest.is_some() {
                    self.publish(s);
                }
                self.fetch(
                    s,
                    id,
                    c["attempts"]
                        .as_u64()
                        .unwrap_or(if self.satellite { 1 } else { 3 }),
                );
            }
            "stop" => {
                self.active = false;
                self.generation = c["generation"].as_u64().unwrap_or(self.generation + 1);
                self.next_poll = None;
                self.cancel(s);
                if self.client != 0 {
                    http_transport::rq_http_client_close(self.client);
                    self.client = 0;
                }
                if c["clear"].as_bool() == Some(true) && self.latest.take().is_some() {
                    self.publish(s);
                }
                self.ack(s, id);
            }
            "fetch" => self.fetch(s, id, c["attempts"].as_u64().unwrap_or(1)),
            "tile" => {
                if self.active {
                    if let Some(result) =
                        self.images
                            .add(id, c["path"].as_str().unwrap_or("").into(), self.satellite)
                    {
                        emit_tile(s, result);
                    }
                } else {
                    emit_tile(s, (id, 1, vec![]));
                }
            }
            "cancelTile" => {
                if let Some(result) = self.images.cancel(id) {
                    emit_tile(s, result);
                }
            }
            "diagnostics" => emit(
                s,
                json!({"type":"diagnostics","request":id,"active":self.active,"requests":self.requests,"responses":self.responses,"failures":self.failures,"pending":self.request.is_some(),"retry":self.retry.is_some(),"retainedBodyBytes":self.request.as_ref().map(|r|r.bytes.len()).unwrap_or(0),"hasFrame":self.latest.is_some(),"imageRequests":self.images.requests,"imagesActive":self.images.active_count(),"imagesPending":self.images.count(),"imageBytes":self.images.retained_bytes(),"imagesCancelled":self.images.cancelled,"imagesCompleted":self.images.completed}),
            ),
            _ => self.ack(s, id),
        }
    }
    fn fetch(&mut self, s: &Shared, id: u64, attempts: u64) {
        if !self.active {
            self.ack(s, id);
            return;
        }
        if self.request.is_some() || self.retry.is_some() {
            self.queued = true;
            self.ack(s, id);
            return;
        }
        self.waiters.push(id);
        self.attempts = attempts.max(1);
        self.attempt = 0;
        self.begin();
    }
    fn tick(&mut self, s: &Shared) {
        self.drain(s);
        for result in self.images.drain() {
            emit_tile(s, result);
        }
        if self.active && self.client != 0 {
            self.images.start_ready(
                self.client,
                &self.host,
                self.port,
                self.secure,
                self.id,
                wake,
            );
        }
        let now = Instant::now();
        if self.retry.is_some_and(|at| now >= at) && self.active {
            self.begin();
        }
        if self.next_poll.is_some_and(|at| now >= at) && self.active {
            self.next_poll = Some(now + self.interval);
            self.fetch(s, 0, 1);
        }
    }
    fn deadline(&self) -> Option<Instant> {
        [
            self.next_poll,
            self.retry,
            self.request.as_ref().map(|r| r.deadline),
            self.images.deadline(),
        ]
        .into_iter()
        .flatten()
        .min()
    }
}
fn run(id: u64, satellite: bool, s: Arc<Shared>, rx: mpsc::Receiver<Command>) {
    WORKERS.fetch_add(1, Ordering::Relaxed);
    let mut r = Runtime::new(id, satellite);
    loop {
        r.tick(&s);
        let cmd = match r.deadline() {
            Some(at) => match rx.recv_timeout(at.saturating_duration_since(Instant::now())) {
                Ok(c) => Some(c),
                Err(mpsc::RecvTimeoutError::Timeout) => None,
                Err(_) => break,
            },
            None => match rx.recv() {
                Ok(c) => Some(c),
                Err(_) => break,
            },
        };
        match cmd {
            Some(Command::Control(c)) => r.control(&s, c),
            Some(Command::Close) => break,
            _ => {}
        }
    }
    r.cancel(&s);
    if r.client != 0 {
        http_transport::rq_http_client_close(r.client);
    }
    WORKERS.fetch_sub(1, Ordering::Relaxed);
}
#[no_mangle]
pub unsafe extern "C" fn rq_jma_tile_open(kind: u32, port: i64, post: Post) -> *mut c_void {
    let id = NEXT.fetch_add(1, Ordering::Relaxed);
    let (tx, rx) = mpsc::channel();
    let s = Arc::new(Shared {
        tx,
        output: Mutex::new(VecDeque::new()),
        port,
        post,
    });
    registry().lock().unwrap().insert(id, Arc::downgrade(&s));
    let copy = s.clone();
    let worker = match thread::Builder::new()
        .name(
            if kind == 0 {
                "rq-jma-radar"
            } else {
                "rq-jma-satellite"
            }
            .into(),
        )
        .stack_size(256 * 1024)
        .spawn(move || run(id, kind != 0, copy, rx))
    {
        Ok(worker) => worker,
        Err(_) => {
            registry().lock().unwrap().remove(&id);
            return ptr::null_mut();
        }
    };
    Box::into_raw(Box::new((
        id,
        Owner {
            shared: s,
            worker: Some(worker),
            delivered: vec![],
        },
    )))
    .cast()
}
#[no_mangle]
pub unsafe extern "C" fn rq_jma_tile_send(owner: *mut c_void, bytes: *const u8, len: usize) -> u32 {
    if owner.is_null() || bytes.is_null() || len > 65536 {
        return 0;
    }
    let (_, owner) = unsafe { &*(owner as *const (u64, Owner)) };
    let Ok(value) = serde_json::from_slice(unsafe { std::slice::from_raw_parts(bytes, len) })
    else {
        return 0;
    };
    u32::from(owner.shared.tx.send(Command::Control(value)).is_ok())
}
#[no_mangle]
pub unsafe extern "C" fn rq_jma_tile_take(owner: *mut c_void, len: *mut usize) -> *const u8 {
    if owner.is_null() || len.is_null() {
        return ptr::null();
    }
    let (_, owner) = unsafe { &mut *(owner as *mut (u64, Owner)) };
    let next = owner.shared.output.lock().unwrap().pop_front();
    if let Some(next) = next {
        owner.delivered = next;
        unsafe {
            *len = owner.delivered.len();
        }
        owner.delivered.as_ptr()
    } else {
        owner.delivered = Vec::new();
        ptr::null()
    }
}
#[no_mangle]
pub unsafe extern "C" fn rq_jma_tile_close(owner: *mut c_void) {
    if owner.is_null() {
        return;
    }
    let (id, mut owner) = *unsafe { Box::from_raw(owner as *mut (u64, Owner)) };
    registry().lock().unwrap().remove(&id);
    let _ = owner.shared.tx.send(Command::Close);
    if let Some(worker) = owner.worker.take() {
        let _ = worker.join();
    }
}
#[no_mangle]
pub extern "C" fn rq_jma_tile_workers() -> usize {
    WORKERS.load(Ordering::Relaxed)
}
