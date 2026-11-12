//! One asynchronous WinHTTP reactor for ordinary API clients. Only the reactor
//! calls handle APIs; callback contexts/buffers survive HANDLE_CLOSING.
#![cfg(windows)]
use flate2::{Decompress, FlushDecompress, Status};
use std::{
    collections::{HashMap, VecDeque},
    ffi::{c_void, CStr},
    ptr,
    sync::{
        atomic::{AtomicU64, AtomicUsize, Ordering},
        mpsc, Arc, Mutex, OnceLock,
    },
    thread,
};
type Handle = *mut c_void;
type Callback = unsafe extern "system" fn(Handle, usize, u32, *mut c_void, u32);
#[link(name = "winhttp")]
extern "system" {
    fn WinHttpOpen(
        agent: *const u16,
        access: u32,
        proxy: *const u16,
        bypass: *const u16,
        flags: u32,
    ) -> Handle;
    fn WinHttpConnect(session: Handle, host: *const u16, port: u16, reserved: u32) -> Handle;
    fn WinHttpOpenRequest(
        connection: Handle,
        verb: *const u16,
        path: *const u16,
        version: *const u16,
        referer: *const u16,
        accept: *const *const u16,
        flags: u32,
    ) -> Handle;
    fn WinHttpSetOption(handle: Handle, option: u32, buffer: *const c_void, length: u32) -> i32;
    fn WinHttpSetTimeouts(
        handle: Handle,
        resolve: i32,
        connect: i32,
        send: i32,
        receive: i32,
    ) -> i32;
    fn WinHttpSetStatusCallback(
        handle: Handle,
        callback: Option<Callback>,
        flags: u32,
        reserved: usize,
    ) -> usize;
    fn WinHttpSendRequest(
        request: Handle,
        headers: *const u16,
        length: u32,
        optional: *const c_void,
        optional_len: u32,
        total: u32,
        context: usize,
    ) -> i32;
    fn WinHttpReceiveResponse(request: Handle, reserved: *mut c_void) -> i32;
    fn WinHttpQueryHeaders(
        request: Handle,
        level: u32,
        name: *const u16,
        buffer: *mut c_void,
        length: *mut u32,
        index: *mut u32,
    ) -> i32;
    fn WinHttpReadData(request: Handle, buffer: *mut c_void, length: u32, read: *mut u32) -> i32;
    fn WinHttpQueryDataAvailable(request: Handle, available: *mut u32) -> i32;
    fn WinHttpCloseHandle(handle: Handle) -> i32;
}
#[link(name = "kernel32")]
extern "system" {
    fn GetLastError() -> u32;
}
const CLOSING: u32 = 0x800;
const HEADERS: u32 = 0x20000;
const AVAILABLE: u32 = 0x40000;
const READ: u32 = 0x80000;
const ERROR: u32 = 0x200000;
const SENT: u32 = 0x400000;
const HIGH: usize = 64 * 1024;
const BLOCK: usize = 32 * 1024;
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
struct Events {
    queue: VecDeque<Event>,
    bytes: usize,
}
struct Session {
    events: Mutex<Events>,
    port: i64,
    post: Post,
    buffered: bool,
}
impl Session {
    fn complete(&self, headers: Vec<u8>, body: Vec<u8>) {
        let mut events = self.events.lock().unwrap();
        events.bytes = headers.len() + body.len();
        events.queue.extend([
            Event {
                kind: 1,
                code: 0,
                bytes: headers,
            },
            Event {
                kind: 2,
                code: 0,
                bytes: body,
            },
            Event {
                kind: 3,
                code: 0,
                bytes: vec![],
            },
        ]);
        let mut object = DartObject {
            kind: 3,
            value: [1, 0, 0, 0, 0],
        };
        unsafe {
            (self.post)(self.port, &mut object);
        }
    }
    fn event(&self, kind: u32, code: u32, bytes: Vec<u8>) {
        let mut events = self.events.lock().unwrap();
        let notify = events.queue.is_empty();
        events.bytes += bytes.len();
        events.queue.push_back(Event { kind, code, bytes });
        PEAK.fetch_max(events.bytes, Ordering::Relaxed);
        if notify {
            let mut object = DartObject {
                kind: 3,
                value: [1, 0, 0, 0, 0],
            };
            unsafe {
                (self.post)(self.port, &mut object);
            }
        }
    }
}
static REGISTRY: OnceLock<Mutex<HashMap<u64, Arc<Session>>>> = OnceLock::new();
static NEXT: AtomicU64 = AtomicU64::new(1);
static CLIENTS: AtomicUsize = AtomicUsize::new(0);
static REQUESTS: AtomicUsize = AtomicUsize::new(0);
static PEAK: AtomicUsize = AtomicUsize::new(0);
fn registry() -> &'static Mutex<HashMap<u64, Arc<Session>>> {
    REGISTRY.get_or_init(Default::default)
}
struct Config {
    client: u64,
    host: String,
    path: String,
    method: String,
    headers: String,
    body: Vec<u8>,
    port: u16,
    flags: u32,
}
enum Command {
    OpenClient(u64, String, u32),
    CloseClient(u64),
    Start(u64, Config, Arc<Session>),
    Completion(u64, u32, u32, u32),
    Drain(u64),
    Cancel(u64),
}
static REACTOR: OnceLock<mpsc::Sender<Command>> = OnceLock::new();
fn reactor() -> &'static mpsc::Sender<Command> {
    REACTOR.get_or_init(|| {
        let (tx, rx) = mpsc::channel();
        let sender = tx.clone();
        thread::Builder::new()
            .name("rq-http".into())
            .stack_size(256 * 1024)
            .spawn(move || {
                Reactor {
                    sender,
                    clients: HashMap::new(),
                    requests: HashMap::new(),
                }
                .run(rx)
            })
            .expect("HTTP reactor");
        tx
    })
}
struct Context {
    id: u64,
    sender: mpsc::Sender<Command>,
}
#[repr(C)]
struct AsyncError {
    operation: usize,
    error: u32,
}
unsafe extern "system" fn callback(
    _: Handle,
    context: usize,
    status: u32,
    info: *mut c_void,
    length: u32,
) {
    if context == 0 {
        return;
    }
    let context = unsafe { &*(context as *const Context) };
    let length = if status == AVAILABLE && !info.is_null() {
        unsafe { *(info as *const u32) }
    } else {
        length
    };
    let error = if status == ERROR && !info.is_null() {
        unsafe { (*(info as *const AsyncError)).error }
    } else {
        0
    };
    let _ = context
        .sender
        .send(Command::Completion(context.id, status, length, error));
}
fn wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(Some(0)).collect()
}
fn check(ok: i32) -> Result<(), u32> {
    if ok != 0 {
        Ok(())
    } else {
        Err(unsafe { GetLastError() })
    }
}
fn option(handle: Handle, key: u32, value: u32) -> Result<(), u32> {
    check(unsafe { WinHttpSetOption(handle, key, (&value as *const u32).cast(), 4) })
}
struct Client {
    handle: Handle,
    explicit: Handle,
    closing: bool,
}
impl Drop for Client {
    fn drop(&mut self) {
        unsafe {
            WinHttpCloseHandle(self.handle);
            if !self.explicit.is_null() {
                WinHttpCloseHandle(self.explicit);
            }
        }
    }
}
struct Request {
    client: u64,
    session: Arc<Session>,
    context: Box<Context>,
    connection: Handle,
    handle: Handle,
    callback_set: bool,
    closing: bool,
    reading: bool,
    buffer: Vec<u8>,
    body: Vec<u8>,
    decoder: Option<Decompress>,
    decoded_end: bool,
    input_size: usize,
    input_offset: usize,
    eof: bool,
    head: bool,
    buffered: bool,
    collected: Vec<u8>,
    response_headers: Vec<u8>,
}
impl Request {
    fn body_chunk(&mut self, bytes: Vec<u8>) -> Result<(), u32> {
        if crate::network_diagnostic::active() {
            crate::network_diagnostic::record(
                "native_http",
                self.context.id,
                "response_body_decoded",
                serde_json::json!({}),
                &bytes,
            );
        }
        if self.buffered {
            if self.collected.len() + bytes.len() > 64 * 1024 * 1024 {
                return Err(12152);
            }
            if self.collected.is_empty() {
                self.collected = bytes;
            } else {
                self.collected.extend_from_slice(&bytes);
            }
        } else {
            self.session.event(2, 0, bytes);
        }
        Ok(())
    }
    fn start(&mut self, client: Handle, explicit: Handle, config: Config) -> Result<(), u32> {
        if crate::network_diagnostic::active() {
            crate::network_diagnostic::record(
                "native_http",
                self.context.id,
                "request",
                serde_json::json!({"host":config.host,"path":config.path,"method":config.method,"headers":config.headers,"port":config.port,"flags":config.flags}),
                &config.body,
            );
        }
        let route = if config.flags & 8 != 0 {
            palert_proxy_route(&config.host, config.port, config.flags & 1 != 0)?
        } else {
            None
        };
        // WinHTTP automatic sessions reject WINHTTP_OPTION_PROXY (12011).
        // Explicit environment/bypass routes use their own session; requests
        // without an override retain Windows automatic/PAC selection.
        let client = if route.is_some() && !explicit.is_null() {
            explicit
        } else {
            client
        };
        unsafe {
            self.connection = WinHttpConnect(client, wide(&config.host).as_ptr(), config.port, 0);
            if self.connection.is_null() {
                return Err(GetLastError());
            }
            // URLs are already percent-encoded by Uri. Do not double-escape %.
            self.handle = WinHttpOpenRequest(
                self.connection,
                wide(&config.method).as_ptr(),
                wide(&config.path).as_ptr(),
                ptr::null(),
                ptr::null(),
                ptr::null(),
                (if config.flags & 1 != 0 { 0x800000 } else { 0 }) | 0x40 | 0x80,
            );
            if self.handle.is_null() {
                return Err(GetLastError());
            }
            if config.flags & 8 != 0 {
                if let Some(route) = route {
                    palert_apply_proxy(self.handle, &route)?;
                }
                if config.host == "palert.earth.sinica.edu.tw" {
                    // Same host-scoped certificate policy as the existing
                    // P-Alert TLS client; unrelated HTTP clients are unchanged.
                    option(self.handle, 31, 0x3300)?;
                }
            }
            // Match an ordinary Dart client: no cookie jar, automatic Windows
            // credentials, or automatic redirect/header forwarding.
            option(
                self.handle,
                63,
                1 | 2 | 4 | 8 * (u32::from(config.flags & 2 != 0)),
            )?;
            option(self.handle, 88, 0)?;
            let context = &*self.context as *const Context as usize;
            check(WinHttpSetOption(
                self.handle,
                45,
                (&context as *const usize).cast(),
                std::mem::size_of::<usize>() as u32,
            ))?;
            if WinHttpSetStatusCallback(
                self.handle,
                Some(callback),
                CLOSING | HEADERS | AVAILABLE | READ | ERROR | SENT,
                0,
            ) == usize::MAX
            {
                return Err(GetLastError());
            }
            self.callback_set = true;
            self.body = config.body;
            check(WinHttpSendRequest(
                self.handle,
                wide(&config.headers).as_ptr(),
                config.headers.encode_utf16().count() as u32,
                if self.body.is_empty() {
                    ptr::null()
                } else {
                    self.body.as_ptr().cast()
                },
                self.body.len() as u32,
                self.body.len() as u32,
                context,
            ))?;
        }
        Ok(())
    }
    fn read(&mut self) -> Result<(), u32> {
        if self.closing || self.reading || self.session.events.lock().unwrap().bytes >= HIGH {
            return Ok(());
        }
        if self.decoder.is_some() {
            let mut decoded_this_turn = 0;
            loop {
                if self.buffered && decoded_this_turn >= HIGH {
                    let _ = self.context.sender.send(Command::Drain(self.context.id));
                    return Ok(());
                }
                let budget = HIGH
                    .saturating_sub(self.session.events.lock().unwrap().bytes)
                    .min(BLOCK);
                if budget == 0 {
                    return Ok(());
                }
                if self.decoded_end && self.input_offset < self.input_size {
                    self.decoder = Some(Decompress::new_gzip(15));
                    self.decoded_end = false;
                }
                if self.decoded_end {
                    break;
                }
                let decoder = self.decoder.as_mut().unwrap();
                let before_in = decoder.total_in();
                let before_out = decoder.total_out();
                let mut output = vec![0; budget];
                let status = decoder
                    .decompress(
                        &self.buffer[self.input_offset..self.input_size],
                        &mut output,
                        if self.eof {
                            FlushDecompress::Finish
                        } else {
                            FlushDecompress::None
                        },
                    )
                    .map_err(|_| 12152u32)?;
                let consumed = (decoder.total_in() - before_in) as usize;
                let produced = (decoder.total_out() - before_out) as usize;
                self.input_offset += consumed;
                if produced != 0 {
                    decoded_this_turn += produced;
                    output.truncate(produced);
                    self.body_chunk(output)?;
                }
                self.decoded_end = status == Status::StreamEnd;
                if self.decoded_end {
                    continue;
                }
                if consumed == 0 && produced == 0 {
                    if self.eof || self.input_offset != self.input_size {
                        return Err(12152);
                    }
                    break;
                }
            }
        }
        if self.eof {
            if self.decoder.is_some() && !self.decoded_end {
                return Err(12152);
            }
            if self.buffered {
                self.session.complete(
                    std::mem::take(&mut self.response_headers),
                    std::mem::take(&mut self.collected),
                );
            } else {
                self.session.event(3, 0, vec![]);
            }
            self.close();
            return Ok(());
        }
        self.reading = true;
        // Query asynchronously: a slow chunked response must deliver its small
        // available chunk without waiting for an entire 32 KiB read to fill.
        check(unsafe { WinHttpQueryDataAvailable(self.handle, ptr::null_mut()) })
    }
    fn headers(&self) -> Result<Vec<u8>, u32> {
        let mut length = 0;
        unsafe {
            WinHttpQueryHeaders(
                self.handle,
                22,
                ptr::null(),
                ptr::null_mut(),
                &mut length,
                ptr::null_mut(),
            );
        }
        if length == 0 || length as usize > HIGH {
            return Err(12150);
        }
        let mut buffer = vec![0u16; (length as usize).div_ceil(2)];
        check(unsafe {
            WinHttpQueryHeaders(
                self.handle,
                22,
                ptr::null(),
                buffer.as_mut_ptr().cast(),
                &mut length,
                ptr::null_mut(),
            )
        })?;
        let end = buffer.iter().position(|&x| x == 0).unwrap_or(buffer.len());
        String::from_utf16(&buffer[..end])
            .map(String::into_bytes)
            .map_err(|_| 12150)
    }
    fn close(&mut self) {
        if self.closing {
            return;
        }
        if crate::network_diagnostic::active() {
            crate::network_diagnostic::record(
                "native_http",
                self.context.id,
                "request_closed",
                serde_json::json!({"eof":self.eof}),
                &[],
            );
        }
        self.closing = true;
        if !self.handle.is_null() {
            unsafe {
                WinHttpCloseHandle(self.handle);
            }
        }
    }
}
impl Drop for Request {
    fn drop(&mut self) {
        if !self.connection.is_null() {
            unsafe {
                WinHttpCloseHandle(self.connection);
            }
        }
    }
}
struct Reactor {
    sender: mpsc::Sender<Command>,
    clients: HashMap<u64, Client>,
    requests: HashMap<u64, Request>,
}
impl Reactor {
    fn remove(&mut self, id: u64) {
        self.requests.remove(&id);
        REQUESTS.fetch_sub(1, Ordering::Relaxed);
        if self.requests.is_empty() {
            self.requests.shrink_to_fit();
        }
        let dead: Vec<_> = self
            .clients
            .iter()
            .filter(|(id, c)| c.closing && !self.requests.values().any(|r| r.client == **id))
            .map(|(id, _)| *id)
            .collect();
        for id in dead {
            if let Some(c) = self.clients.remove(&id) {
                drop(c);
                CLIENTS.fetch_sub(1, Ordering::Relaxed);
            }
        }
        if self.clients.is_empty() {
            self.clients.shrink_to_fit();
        }
    }
    fn run(&mut self, rx: mpsc::Receiver<Command>) {
        while let Ok(command) = rx.recv() {
            match command {
                Command::OpenClient(id, agent, access) => {
                    let handle = unsafe {
                        WinHttpOpen(
                            wide(&agent).as_ptr(),
                            access,
                            ptr::null(),
                            ptr::null(),
                            0x10000000,
                        )
                    };
                    if !handle.is_null() {
                        // Existing Dart clients have no transport receive deadline.
                        unsafe {
                            WinHttpSetTimeouts(handle, 0, 0, 0, 0);
                        }
                        self.clients.insert(
                            id,
                            Client {
                                handle,
                                explicit: if access == 4 {
                                    unsafe {
                                        let direct = WinHttpOpen(
                                            wide(&agent).as_ptr(),
                                            1,
                                            ptr::null(),
                                            ptr::null(),
                                            0x10000000,
                                        );
                                        if !direct.is_null() {
                                            WinHttpSetTimeouts(direct, 0, 0, 0, 0);
                                        }
                                        direct
                                    }
                                } else {
                                    ptr::null_mut()
                                },
                                closing: false,
                            },
                        );
                        CLIENTS.fetch_add(1, Ordering::Relaxed);
                    }
                }
                Command::CloseClient(id) => {
                    if let Some(c) = self.clients.get_mut(&id) {
                        c.closing = true;
                    }
                    for r in self.requests.values_mut().filter(|r| r.client == id) {
                        r.close();
                    }
                    if !self.requests.values().any(|r| r.client == id) {
                        if let Some(c) = self.clients.remove(&id) {
                            drop(c);
                            CLIENTS.fetch_sub(1, Ordering::Relaxed);
                        }
                    }
                }
                Command::Start(id, config, session) => {
                    let Some(client) = self.clients.get(&config.client).filter(|c| !c.closing)
                    else {
                        session.event(4, 12019, vec![]);
                        continue;
                    };
                    let mut r = Request {
                        client: config.client,
                        session,
                        context: Box::new(Context {
                            id,
                            sender: self.sender.clone(),
                        }),
                        connection: ptr::null_mut(),
                        handle: ptr::null_mut(),
                        callback_set: false,
                        closing: false,
                        reading: false,
                        buffer: vec![0; BLOCK],
                        body: vec![],
                        decoder: None,
                        decoded_end: false,
                        input_size: 0,
                        input_offset: 0,
                        eof: false,
                        head: config.method == "HEAD",
                        buffered: config.flags & 4 != 0,
                        collected: vec![],
                        response_headers: vec![],
                    };
                    let result = r.start(client.handle, client.explicit, config);
                    if let Err(code) = result {
                        if crate::network_diagnostic::active() {
                            crate::network_diagnostic::record(
                                "native_http",
                                id,
                                "error",
                                serde_json::json!({"code":code}),
                                &[],
                            );
                        }
                        r.session.event(4, code, vec![]);
                        r.close();
                    }
                    if r.closing && !r.callback_set {
                        continue;
                    }
                    REQUESTS.fetch_add(1, Ordering::Relaxed);
                    self.requests.insert(id, r);
                }
                Command::Completion(id, status, length, error) => {
                    if status == CLOSING {
                        if self.requests.contains_key(&id) {
                            self.remove(id);
                        }
                        continue;
                    }
                    let Some(r) = self.requests.get_mut(&id).filter(|r| !r.closing) else {
                        continue;
                    };
                    let result = match status {
                        SENT => check(unsafe { WinHttpReceiveResponse(r.handle, ptr::null_mut()) }),
                        HEADERS => r.headers().and_then(|headers| {
                            if crate::network_diagnostic::active() {
                                crate::network_diagnostic::record(
                                    "native_http",
                                    id,
                                    "response_headers",
                                    serde_json::json!({}),
                                    &headers,
                                );
                            }
                            r.body = vec![];
                            if !r.head
                                && std::str::from_utf8(&headers)
                                    .unwrap_or("")
                                    .split("\r\n")
                                    .any(|line| {
                                        line.split_once(':').is_some_and(|(key, value)| {
                                            key.eq_ignore_ascii_case("content-encoding")
                                                && value.trim() == "gzip"
                                        })
                                    })
                            {
                                r.decoder = Some(Decompress::new_gzip(15));
                            }
                            if r.buffered {
                                r.response_headers = headers;
                            } else {
                                r.session.event(1, 0, headers);
                            }
                            r.read()
                        }),
                        AVAILABLE => {
                            if length == 0 {
                                r.reading = false;
                                r.eof = true;
                                r.read()
                            } else {
                                let budget =
                                    HIGH.saturating_sub(r.session.events.lock().unwrap().bytes);
                                check(unsafe {
                                    WinHttpReadData(
                                        r.handle,
                                        r.buffer.as_mut_ptr().cast(),
                                        (length as usize).min(budget).min(BLOCK) as u32,
                                        ptr::null_mut(),
                                    )
                                })
                            }
                        }
                        READ => (|| -> Result<(), u32> {
                            r.reading = false;
                            if length as usize > r.buffer.len() {
                                Err(12150)
                            } else {
                                if r.decoder.is_some() {
                                    r.input_size = length as usize;
                                    r.input_offset = 0;
                                } else if length != 0 {
                                    r.body_chunk(r.buffer[..length as usize].to_vec())?;
                                }
                                if length == 0 {
                                    r.eof = true;
                                }
                                r.read()
                            }
                        })(),
                        ERROR => Err(error),
                        _ => Ok(()),
                    };
                    if let Err(code) = result {
                        if crate::network_diagnostic::active() {
                            crate::network_diagnostic::record(
                                "native_http",
                                id,
                                "error",
                                serde_json::json!({"code":code}),
                                &[],
                            );
                        }
                        r.session.event(4, code, vec![]);
                        r.close();
                    }
                }
                Command::Drain(id) => {
                    if let Some(r) = self.requests.get_mut(&id) {
                        if let Err(code) = r.read() {
                            r.session.event(4, code, vec![]);
                            r.close();
                        }
                    }
                }
                Command::Cancel(id) => {
                    if let Some(r) = self.requests.get_mut(&id) {
                        r.close();
                    }
                }
            }
        }
    }
}
#[no_mangle]
pub unsafe extern "C" fn rq_http_client_open(agent: *const u8) -> u64 {
    if agent.is_null() {
        return 0;
    }
    let Ok(agent) = unsafe { CStr::from_ptr(agent.cast()) }.to_str() else {
        return 0;
    };
    let id = NEXT.fetch_add(1, Ordering::Relaxed);
    let _ = reactor().send(Command::OpenClient(id, agent.into(), 1));
    id
}
pub(crate) fn open_system_client(agent: &str) -> u64 {
    let id = NEXT.fetch_add(1, Ordering::Relaxed);
    let _ = reactor().send(Command::OpenClient(id, agent.into(), 4));
    id
}

#[repr(C)]
struct ProxyInfo {
    access: u32,
    proxy: *const u16,
    bypass: *const u16,
}
fn palert_proxy_route(host: &str, port: u16, secure: bool) -> Result<Option<String>, u32> {
    let env = |key: &str| {
        std::env::var(key)
            .ok()
            .filter(|s| !s.is_empty())
            .or_else(|| {
                std::env::var(key.to_uppercase())
                    .ok()
                    .filter(|s| !s.is_empty())
            })
    };
    let proxy = env(if secure { "https_proxy" } else { "http_proxy" }).or_else(|| env("all_proxy"));
    let host_lower = host.to_lowercase();
    let bypass = host_lower == "localhost"
        || host
            .parse::<std::net::IpAddr>()
            .is_ok_and(|a| a.is_loopback())
        || env("no_proxy").is_some_and(|s| {
            s.split(',').any(|part| {
                let mut rule = part.trim().to_lowercase();
                if rule == "*" {
                    return true;
                }
                if let Some((h, p)) = rule.rsplit_once(':') {
                    if p.parse::<u16>().ok() != Some(port) {
                        return false;
                    }
                    rule = h.into();
                }
                let rule = rule.trim_start_matches('.');
                host_lower == rule || host_lower.ends_with(&format!(".{rule}"))
            })
        });
    if proxy.is_none() && !bypass {
        return Ok(None);
    }
    let name = if bypass {
        String::new()
    } else {
        let mut value = proxy.unwrap();
        if let Some(v) = value.strip_prefix("http://") {
            value = v.into();
        } else if value.contains("://") {
            return Err(87);
        }
        value = value.trim_end_matches('/').into();
        if value.contains(['@', '/', '?', '#', '\r', '\n'])
            || !value
                .rsplit_once(':')
                .is_some_and(|(_, p)| p.parse::<u16>().is_ok_and(|p| p > 0))
        {
            return Err(87);
        }
        value
    };
    Ok(Some(name))
}
fn palert_apply_proxy(handle: Handle, route: &str) -> Result<(), u32> {
    let name = wide(route);
    let info = ProxyInfo {
        access: if route.is_empty() { 1 } else { 3 },
        proxy: if route.is_empty() {
            ptr::null()
        } else {
            name.as_ptr()
        },
        bypass: ptr::null(),
    };
    check(unsafe {
        WinHttpSetOption(
            handle,
            38,
            (&info as *const ProxyInfo).cast(),
            std::mem::size_of::<ProxyInfo>() as u32,
        )
    })
}
#[no_mangle]
pub extern "C" fn rq_http_client_close(id: u64) {
    let _ = reactor().send(Command::CloseClient(id));
}
#[no_mangle]
pub extern "C" fn rq_http_client_finalizer(id: *mut c_void) {
    rq_http_client_close(id as u64);
}
/// All strings copied as UTF-8 before return; body bytes are copied unchanged.
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
    let string = |p: *const u8| {
        unsafe { CStr::from_ptr(p.cast()) }
            .to_str()
            .map(str::to_owned)
    };
    let (Ok(host), Ok(path), Ok(method), Ok(headers)) =
        (string(host), string(path), string(method), string(headers))
    else {
        return 0;
    };
    let body = if body_len == 0 {
        vec![]
    } else {
        unsafe { std::slice::from_raw_parts(body, body_len) }.to_vec()
    };
    let id = NEXT.fetch_add(1, Ordering::Relaxed);
    let session = Arc::new(Session {
        events: Mutex::new(Events::default()),
        port: dart_port,
        post,
        buffered: flags & 4 != 0,
    });
    registry().lock().unwrap().insert(id, session.clone());
    let _ = reactor().send(Command::Start(
        id,
        Config {
            client,
            host,
            path,
            method,
            headers,
            body,
            port: port as u16,
            flags,
        },
        session,
    ));
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
    let session = registry().lock().unwrap().get(&id).cloned();
    let Some(session) = session else {
        return ptr::null();
    };
    let mut events = session.events.lock().unwrap();
    let Some(event) = events.queue.pop_front() else {
        return ptr::null();
    };
    events.bytes -= event.bytes.len();
    drop(events);
    let bytes = Box::new(event.bytes);
    let data = bytes.as_ptr();
    unsafe {
        *size = bytes.len();
        *kind = event.kind;
        *code = event.code;
        *owner = Box::into_raw(bytes).cast();
    }
    if !session.buffered {
        let _ = reactor().send(Command::Drain(id));
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
    let mut registry = registry().lock().unwrap();
    registry.remove(&id);
    if registry.is_empty() {
        registry.shrink_to_fit();
    }
    drop(registry);
    let _ = reactor().send(Command::Cancel(id));
}
#[no_mangle]
pub extern "C" fn rq_http_release_finalizer(id: *mut c_void) {
    rq_http_release(id as u64);
}
#[no_mangle]
pub extern "C" fn rq_http_clients() -> usize {
    CLIENTS.load(Ordering::Relaxed)
}
#[no_mangle]
pub extern "C" fn rq_http_requests() -> usize {
    REQUESTS.load(Ordering::Relaxed)
}
#[no_mangle]
pub extern "C" fn rq_http_queue_peak() -> usize {
    PEAK.load(Ordering::Relaxed)
}
