//! Windows websocket transport. WinHTTP is asynchronous; only this worker
//! calls handle APIs. Callbacks copy completion metadata onto its command
//! queue. Dart receives a coalesced native-port notification, never a poll.
#![cfg(windows)]

use std::{
    collections::{HashMap, VecDeque},
    ffi::c_void,
    ptr,
    sync::{
        atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering},
        mpsc, Arc, Condvar, Mutex, OnceLock,
    },
    thread,
    time::{Duration, Instant},
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
    fn WinHttpWebSocketCompleteUpgrade(request: Handle, context: usize) -> Handle;
    fn WinHttpWebSocketReceive(
        socket: Handle,
        buffer: *mut c_void,
        length: u32,
        read: *mut u32,
        kind: *mut u32,
    ) -> u32;
    fn WinHttpWebSocketSend(socket: Handle, kind: u32, buffer: *const c_void, length: u32) -> u32;
    fn WinHttpWebSocketShutdown(
        socket: Handle,
        code: u16,
        reason: *const c_void,
        length: u32,
    ) -> u32;
    fn WinHttpWebSocketQueryCloseStatus(
        socket: Handle,
        code: *mut u16,
        reason: *mut c_void,
        length: u32,
        used: *mut u32,
    ) -> u32;
    fn WinHttpCloseHandle(handle: Handle) -> i32;
}
#[link(name = "kernel32")]
extern "system" {
    fn GetLastError() -> u32;
}

const LIMIT: usize = 64 * 1024 * 1024;
const CLOSING: u32 = 0x800;
const HEADERS: u32 = 0x20000;
const READ: u32 = 0x80000;
const WRITE: u32 = 0x100000;
const ERROR: u32 = 0x200000;
const SENT: u32 = 0x400000;
const SHUTDOWN: u32 = 0x4000000;
const FLAGS: u32 = CLOSING | HEADERS | READ | WRITE | ERROR | SENT | SHUTDOWN;

// Dart_CObject union is 40 bytes on Windows x64. Only kInt64 is used.
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
    Completion {
        handle: usize,
        status: u32,
        length: u32,
        kind: u32,
        error: u32,
    },
    Send(Vec<u8>, u32),
    Close(u16, Vec<u8>),
    Dispose,
}
struct Session {
    diagnostic_id: u64,
    sender: mpsc::Sender<Command>,
    events: Mutex<Events>,
    stopped: AtomicBool,
    outgoing: AtomicUsize,
    finished: (Mutex<bool>, Condvar),
    port: i64,
    post: Post,
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
impl Session {
    fn event(&self, event: Event) -> bool {
        if crate::network_diagnostic::active() {
            crate::network_diagnostic::record(
                "native_ws",
                self.diagnostic_id,
                "receive",
                serde_json::json!({"kind":event.kind,"code":event.code}),
                &event.bytes,
            );
        }
        if self.stopped.load(Ordering::Acquire) {
            return false;
        }
        let mut events = self.events.lock().unwrap();
        if events.bytes + event.bytes.len() > LIMIT {
            return false;
        }
        let notify = events.queue.is_empty();
        events.bytes += event.bytes.len();
        events.queue.push_back(event);
        if notify {
            let mut object = DartObject {
                kind: 3,
                value: [1, 0, 0, 0, 0],
            };
            // NativeApi.postCObject is safe for a closed ReceivePort as well.
            if !unsafe { (self.post)(self.port, &mut object) } {
                return false;
            }
        }
        true
    }
}

#[repr(C)]
struct SocketStatus {
    length: u32,
    kind: u32,
}
#[repr(C)]
struct AsyncError {
    operation: usize,
    error: u32,
}
unsafe extern "system" fn callback(
    handle: Handle,
    context: usize,
    status: u32,
    info: *mut c_void,
    length: u32,
) {
    if context == 0 {
        return;
    }
    // The worker keeps this Sender alive until HANDLE_CLOSING for both handles.
    let sender = unsafe { &*(context as *const mpsc::Sender<Command>) };
    let (n, kind, error) = if status == READ && length >= 8 && !info.is_null() {
        let s = unsafe { &*info.cast::<SocketStatus>() };
        (s.length, s.kind, 0)
    } else if status == ERROR && !info.is_null() {
        (0, 0, unsafe { (*info.cast::<AsyncError>()).error })
    } else {
        (0, 0, 0)
    };
    let _ = sender.send(Command::Completion {
        handle: handle as usize,
        status,
        length: n,
        kind,
        error,
    });
}
fn wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(Some(0)).collect()
}
fn last_error() -> u32 {
    unsafe { GetLastError() }
}
fn check(ok: i32) -> Result<(), u32> {
    if ok != 0 {
        Ok(())
    } else {
        Err(last_error())
    }
}
fn option(handle: Handle, name: u32, value: u32) -> Result<(), u32> {
    check(unsafe { WinHttpSetOption(handle, name, (&value as *const u32).cast(), 4) })
}
struct Config {
    host: String,
    path: String,
    headers: String,
    port: u16,
    secure: bool,
    insecure: bool,
    timeout: u32,
    keepalive: u32,
}
struct Worker {
    session: Arc<Session>,
    receiver: mpsc::Receiver<Command>,
    context: Box<mpsc::Sender<Command>>,
    http: Handle,
    connection: Handle,
    request: Handle,
    socket: Handle,
    closing: usize,
    keepalive: u32,
    buffer: Vec<u8>,
    fragments: Vec<u8>,
    fragment_kind: Option<u32>,
    sends: VecDeque<(Vec<u8>, u32)>,
    sending: bool,
    close: Option<(u16, Vec<u8>)>,
    shutdown_started: bool,
    remote_closed: bool,
    deadline: Option<Instant>,
}
impl Worker {
    fn start(&mut self, config: Config) -> Result<(), u32> {
        if crate::network_diagnostic::active() {
            crate::network_diagnostic::record(
                "native_ws",
                self.session.diagnostic_id,
                "connect",
                serde_json::json!({"host":config.host,"path":config.path,"port":config.port,"secure":config.secure,"headers":config.headers}),
                &[],
            );
        }
        self.keepalive = config.keepalive;
        unsafe {
            // These sources previously used Dart's direct HttpClient; do not
            // silently opt them into a different system/PAC proxy route.
            self.http = WinHttpOpen(
                wide("Dart/3 RhythmQuake").as_ptr(),
                1,
                ptr::null(),
                ptr::null(),
                0x10000000,
            );
            if self.http.is_null() {
                return Err(last_error());
            }
            check(WinHttpSetTimeouts(
                self.http,
                config.timeout as i32,
                config.timeout as i32,
                config.timeout as i32,
                config.timeout as i32,
            ))?;
            self.connection =
                WinHttpConnect(self.http, wide(&config.host).as_ptr(), config.port, 0);
            if self.connection.is_null() {
                return Err(last_error());
            }
            self.request = WinHttpOpenRequest(
                self.connection,
                wide("GET").as_ptr(),
                wide(&config.path).as_ptr(),
                ptr::null(),
                ptr::null(),
                ptr::null(),
                if config.secure { 0x800000 } else { 0 },
            );
            if self.request.is_null() {
                return Err(last_error());
            }
            check(WinHttpSetOption(self.request, 114, ptr::null(), 0))?;
            if config.insecure {
                option(self.request, 31, 0x3300)?;
            }
            // Disable redirects: auth headers must not migrate to another host.
            option(self.request, 88, 0)?;
            let context = &*self.context as *const mpsc::Sender<Command> as usize;
            check(WinHttpSetOption(
                self.request,
                45,
                (&context as *const usize).cast(),
                std::mem::size_of::<usize>() as u32,
            ))?;
            if WinHttpSetStatusCallback(self.request, Some(callback), FLAGS, 0) == usize::MAX {
                return Err(last_error());
            }
            self.closing += 1;
            let headers = wide(&config.headers);
            check(WinHttpSendRequest(
                self.request,
                headers.as_ptr(),
                (headers.len() - 1) as u32,
                ptr::null(),
                0,
                0,
                context,
            ))?;
        }
        Ok(())
    }
    fn receive(&mut self) -> Result<(), u32> {
        let result = unsafe {
            WinHttpWebSocketReceive(
                self.socket,
                self.buffer.as_mut_ptr().cast(),
                self.buffer.len() as u32,
                ptr::null_mut(),
                ptr::null_mut(),
            )
        };
        if result == 0 {
            Ok(())
        } else {
            Err(result)
        }
    }
    fn pump_send(&mut self) -> Result<(), u32> {
        if self.sending || self.socket.is_null() {
            return Ok(());
        }
        if let Some((bytes, kind)) = self.sends.front() {
            self.sending = true;
            let result = unsafe {
                WinHttpWebSocketSend(
                    self.socket,
                    *kind,
                    if bytes.is_empty() {
                        ptr::null()
                    } else {
                        bytes.as_ptr().cast()
                    },
                    bytes.len() as u32,
                )
            };
            if result != 0 {
                return Err(result);
            }
        } else if let Some((code, reason)) = &self.close {
            if self.shutdown_started {
                return Ok(());
            }
            let result = unsafe {
                WinHttpWebSocketShutdown(
                    self.socket,
                    *code,
                    if reason.is_empty() {
                        ptr::null()
                    } else {
                        reason.as_ptr().cast()
                    },
                    reason.len() as u32,
                )
            };
            if result != 0 {
                return Err(result);
            }
            // Keep the reason buffer alive through SHUTDOWN_COMPLETE.
            self.shutdown_started = true;
        }
        Ok(())
    }
    fn completed(
        &mut self,
        handle: usize,
        status: u32,
        length: u32,
        kind: u32,
        error: u32,
    ) -> Result<bool, u32> {
        if status == CLOSING {
            self.closing -= 1;
            return Ok(true);
        }
        if status == ERROR {
            return Err(error);
        }
        if handle == self.request as usize {
            if status == SENT {
                check(unsafe { WinHttpReceiveResponse(self.request, ptr::null_mut()) })?;
            }
            if status == HEADERS {
                let mut code = 0u32;
                let mut size = 4;
                check(unsafe {
                    WinHttpQueryHeaders(
                        self.request,
                        19 | 0x20000000,
                        ptr::null(),
                        (&mut code as *mut u32).cast(),
                        &mut size,
                        ptr::null_mut(),
                    )
                })?;
                if crate::network_diagnostic::active() {
                    crate::network_diagnostic::record(
                        "native_ws",
                        self.session.diagnostic_id,
                        "handshake_response",
                        serde_json::json!({"httpStatus":code}),
                        &[],
                    );
                }
                if code != 101 {
                    return Err(0x10000 | code);
                }
                self.socket = unsafe {
                    WinHttpWebSocketCompleteUpgrade(
                        self.request,
                        &*self.context as *const mpsc::Sender<Command> as usize,
                    )
                };
                if self.socket.is_null() {
                    return Err(last_error());
                }
                // The upgraded handle inherits the request callback.
                self.closing += 1;
                if self.keepalive != 0 {
                    option(self.socket, 116, self.keepalive.max(15000))?;
                }
                unsafe {
                    WinHttpCloseHandle(self.request);
                }
                self.request = ptr::null_mut();
                if !self.session.event(Event {
                    kind: 1,
                    code: 0,
                    bytes: vec![],
                }) {
                    return Ok(false);
                }
                self.receive()?;
                self.pump_send()?;
            }
        } else if handle == self.socket as usize {
            if status == READ {
                if kind == 4 {
                    let mut code = 1005u16;
                    let mut reason = [0u8; 123];
                    let mut used = 0;
                    let result = unsafe {
                        WinHttpWebSocketQueryCloseStatus(
                            self.socket,
                            &mut code,
                            reason.as_mut_ptr().cast(),
                            123,
                            &mut used,
                        )
                    };
                    if result != 0 {
                        return Err(result);
                    }
                    self.session.event(Event {
                        kind: 5,
                        code: code as u32,
                        bytes: reason[..used as usize].to_vec(),
                    });
                    if self.shutdown_started {
                        return Ok(false);
                    }
                    self.remote_closed = true;
                    self.deadline = Some(Instant::now() + Duration::from_secs(2));
                    self.close = Some((code, reason[..used as usize].to_vec()));
                    self.pump_send()?;
                    return Ok(true);
                }
                if length as usize > self.buffer.len()
                    || self.fragments.len() + length as usize > LIMIT
                {
                    return Err(1009);
                }
                let text = kind == 2 || kind == 3;
                if self
                    .fragment_kind
                    .is_some_and(|previous| previous != u32::from(text))
                {
                    return Err(1002);
                }
                self.fragment_kind = Some(u32::from(text));
                self.fragments
                    .extend_from_slice(&self.buffer[..length as usize]);
                if kind == 0 || kind == 2 {
                    let bytes = std::mem::take(&mut self.fragments);
                    self.fragment_kind = None;
                    if text && std::str::from_utf8(&bytes).is_err() {
                        return Err(1007);
                    }
                    if !self.session.event(Event {
                        kind: if text { 2 } else { 3 },
                        code: 0,
                        bytes,
                    }) {
                        return Err(1009);
                    }
                }
                self.receive()?;
            } else if status == SHUTDOWN {
                self.close = None;
                if self.remote_closed {
                    return Ok(false);
                }
            } else if status == WRITE {
                if let Some((bytes, _)) = self.sends.pop_front() {
                    self.session
                        .outgoing
                        .fetch_sub(bytes.len(), Ordering::Relaxed);
                }
                self.sending = false;
                self.pump_send()?;
            }
        }
        Ok(true)
    }
    fn run(&mut self, config: Config) {
        let result = self.start(config).and_then(|()| {
            loop {
                let command = if let Some(deadline) = self.deadline {
                    match self
                        .receiver
                        .recv_timeout(deadline.saturating_duration_since(Instant::now()))
                    {
                        Ok(c) => c,
                        Err(_) => break,
                    }
                } else {
                    match self.receiver.recv() {
                        Ok(c) => c,
                        Err(_) => break,
                    }
                };
                match command {
                    Command::Dispose => break,
                    Command::Close(code, reason) => {
                        if crate::network_diagnostic::active() {
                            crate::network_diagnostic::record(
                                "native_ws",
                                self.session.diagnostic_id,
                                "close_requested",
                                serde_json::json!({"code":code}),
                                &reason,
                            );
                        }
                        if self.socket.is_null() {
                            break;
                        }
                        self.deadline = Some(Instant::now() + Duration::from_secs(2));
                        self.close = Some((code, reason));
                        self.pump_send()?;
                    }
                    Command::Send(bytes, kind) => {
                        if crate::network_diagnostic::active() {
                            crate::network_diagnostic::record(
                                "native_ws",
                                self.session.diagnostic_id,
                                "send_queued",
                                serde_json::json!({"kind":kind}),
                                &bytes,
                            );
                        }
                        self.sends.push_back((bytes, kind));
                        self.pump_send()?;
                    }
                    Command::Completion {
                        handle,
                        status,
                        length,
                        kind,
                        error,
                    } => {
                        if !self.completed(handle, status, length, kind, error)? {
                            break;
                        }
                    }
                }
            }
            Ok(())
        });
        if crate::network_diagnostic::active() {
            crate::network_diagnostic::record(
                "native_ws",
                self.session.diagnostic_id,
                "worker_end",
                serde_json::json!({"errorCode":result.as_ref().err().copied()}),
                &[],
            );
        }
        if let Err(code) = result {
            if self.deadline.is_none() {
                self.session.event(Event {
                    kind: 4,
                    code,
                    bytes: vec![],
                });
            }
        }
        // Cancellation is legal here: all calls on these asynchronous handles
        // have returned. No callback invokes a handle API or accesses buffers.
        unsafe {
            if !self.request.is_null() {
                WinHttpCloseHandle(self.request);
            }
            if !self.socket.is_null() {
                WinHttpCloseHandle(self.socket);
            }
        }
        // Keep callback context AND receive/send buffers alive until callbacks
        // for both handles have fully quiesced.
        while self.closing != 0 {
            if let Ok(Command::Completion {
                status: CLOSING, ..
            }) = self.receiver.recv()
            {
                self.closing -= 1;
            }
        }
        unsafe {
            if !self.connection.is_null() {
                WinHttpCloseHandle(self.connection);
            }
            if !self.http.is_null() {
                WinHttpCloseHandle(self.http);
            }
        }
        self.session.event(Event {
            kind: 6,
            code: 0,
            bytes: vec![],
        });
    }
}

#[no_mangle]
pub extern "C" fn rq_ws_abi_version() -> u32 {
    1
}
/// Strings are NUL-terminated UTF-8 and copied before returning. Post is
/// NativeApi.postCObject. Session IDs never reuse a former connection ID.
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
        unsafe { std::ffi::CStr::from_ptr(p.cast()) }
            .to_str()
            .map(str::to_owned)
    };
    let (Ok(host), Ok(path), Ok(headers)) = (read(host), read(path), read(headers)) else {
        return 0;
    };
    let config = Config {
        host,
        path,
        headers,
        port: port as u16,
        secure: flags & 1 != 0,
        insecure: flags & 2 != 0,
        timeout: timeout.clamp(1, 120000),
        keepalive,
    };
    let (sender, receiver) = mpsc::channel();
    let context = Box::new(sender.clone());
    let id = NEXT.fetch_add(1, Ordering::Relaxed);
    let session = Arc::new(Session {
        diagnostic_id: id,
        sender,
        events: Mutex::new(Events::default()),
        stopped: AtomicBool::new(false),
        outgoing: AtomicUsize::new(0),
        finished: (Mutex::new(false), Condvar::new()),
        port: dart_port,
        post,
    });
    registry().lock().unwrap().insert(id, session.clone());
    WORKERS.fetch_add(1, Ordering::Relaxed);
    if thread::Builder::new()
        .name(format!("rq-ws-{id}"))
        .stack_size(256 * 1024)
        .spawn(move || {
            let mut worker = Worker {
                session,
                receiver,
                context,
                http: ptr::null_mut(),
                connection: ptr::null_mut(),
                request: ptr::null_mut(),
                socket: ptr::null_mut(),
                closing: 0,
                keepalive: 0,
                buffer: vec![0; 32768],
                fragments: vec![],
                fragment_kind: None,
                sends: VecDeque::new(),
                sending: false,
                close: None,
                shutdown_started: false,
                remote_closed: false,
                deadline: None,
            };
            worker.run(config);
            *worker.session.finished.0.lock().unwrap() = true;
            worker.session.finished.1.notify_all();
            WORKERS.fetch_sub(1, Ordering::Relaxed);
        })
        .is_err()
    {
        registry().lock().unwrap().remove(&id);
        WORKERS.fetch_sub(1, Ordering::Relaxed);
        return 0;
    }
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
    let previous = s.outgoing.fetch_add(length, Ordering::Relaxed);
    if previous + length > LIMIT {
        s.outgoing.fetch_sub(length, Ordering::Relaxed);
        return 2;
    }
    let bytes = if length == 0 {
        vec![]
    } else {
        unsafe { std::slice::from_raw_parts(input, length) }.to_vec()
    };
    if s.sender
        .send(Command::Send(bytes, if text != 0 { 2 } else { 0 }))
        .is_err()
    {
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
    let Some(s) = session(id) else {
        return ptr::null();
    };
    if length.is_null() || kind.is_null() || code.is_null() {
        return ptr::null();
    }
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
#[no_mangle]
pub extern "C" fn rq_ws_release(id: u64) {
    if let Some(s) = registry().lock().unwrap().remove(&id) {
        s.stopped.store(true, Ordering::Release);
        let _ = s.sender.send(Command::Dispose);
    }
}
/// Native source actors wait off the UI thread before handing ownership over.
pub(crate) fn release_and_wait(id: u64) -> bool {
    let owner = registry().lock().unwrap().remove(&id);
    let Some(owner) = owner else {
        return true;
    };
    owner.stopped.store(true, Ordering::Release);
    let _ = owner.sender.send(Command::Dispose);
    let completed = owner.finished.0.lock().unwrap();
    let (completed, _) = owner
        .finished
        .1
        .wait_timeout_while(completed, Duration::from_secs(6), |done| !*done)
        .unwrap();
    *completed
}

#[no_mangle]
pub extern "C" fn rq_ws_release_finalizer(id: *mut c_void) {
    rq_ws_release(id as usize as u64);
}
#[no_mangle]
pub extern "C" fn rq_ws_workers() -> usize {
    WORKERS.load(Ordering::Relaxed)
}
