//! Shared nonblocking TCP reactor. Mio uses IOCP/epoll; no thread or polling
//! timer is created per connection. DNS and source policy stay with the caller.
#![cfg(any(windows, target_os = "android"))]

use mio::{net::TcpStream, Events, Interest, Poll, Token, Waker};
use std::{
    collections::{HashMap, HashSet, VecDeque},
    ffi::{c_void, CStr},
    io::{self, IoSlice, Read, Write},
    net::{IpAddr, SocketAddr},
    ptr,
    sync::{
        atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering},
        mpsc, Arc, Mutex, OnceLock,
    },
    thread,
    time::{Duration, Instant},
};

const LIMIT: usize = 64 * 1024 * 1024;
const READ_HIGH: usize = 64 * 1024;
const READ_LOW: usize = 32 * 1024;
const QUEUE_LIMIT: usize = 65536;
const WAKE: Token = Token(0);
const TIMEOUT: u32 = 10060;
const CLOSED: u32 = 10053;
const OVERFLOW: u32 = 10055;
const PROXY_HEADER: u32 = 0x10000;
#[repr(C)]
pub(crate) struct DartObject {
    kind: i32,
    value: [i64; 5],
}
type Post = unsafe extern "C" fn(i64, *mut DartObject) -> bool;
struct Event {
    kind: u32,
    code: u32,
    serial: u64,
    bytes: Vec<u8>,
}
#[derive(Default)]
struct Queue {
    events: VecDeque<Event>,
    bytes: usize,
    delivered: Vec<u8>,
    peak_bytes: usize,
}
struct Session {
    diagnostic_id: u64,
    queue: Mutex<Queue>,
    stopped: AtomicBool,
    outgoing: AtomicUsize,
    dart_port: i64,
    post: Post,
}
impl Session {
    fn event(&self, kind: u32, code: u32, serial: u64, bytes: Vec<u8>) -> bool {
        if crate::network_diagnostic::active() {
            crate::network_diagnostic::record(
                "native_tcp",
                self.diagnostic_id,
                "receive",
                serde_json::json!({"kind":kind,"code":code,"serial":serial}),
                &bytes,
            );
        }
        if self.stopped.load(Ordering::Acquire) {
            return false;
        }
        let mut q = self.queue.lock().unwrap();
        if kind != 4
            && kind != 5
            && (q.bytes + bytes.len() > LIMIT || q.events.len() >= QUEUE_LIMIT)
        {
            return false;
        }
        let notify = q.events.is_empty();
        q.bytes += bytes.len();
        q.peak_bytes = q.peak_bytes.max(q.bytes);
        if kind == 2 {
            if let Some(last) = q.events.back_mut() {
                if last.kind == 2 && last.bytes.len() + bytes.len() <= 32768 {
                    last.bytes.extend_from_slice(&bytes);
                    return true;
                }
            }
        }
        q.events.push_back(Event {
            kind,
            code,
            serial,
            bytes,
        });
        if notify {
            let mut object = DartObject {
                kind: 3,
                value: [1, 0, 0, 0, 0],
            };
            return unsafe { (self.post)(self.dart_port, &mut object) };
        }
        true
    }
    fn finish(&self, error: Option<u32>) {
        if let Some(code) = error {
            self.event(4, code, 0, vec![]);
        }
        self.event(5, 0, 0, vec![]);
    }
}
static SESSIONS: OnceLock<Mutex<HashMap<u64, Arc<Session>>>> = OnceLock::new();
static NEXT: AtomicU64 = AtomicU64::new(1);
static SOCKETS: AtomicUsize = AtomicUsize::new(0);
static THREADS: AtomicUsize = AtomicUsize::new(0);
fn registry() -> &'static Mutex<HashMap<u64, Arc<Session>>> {
    SESSIONS.get_or_init(Default::default)
}
fn session(id: u64) -> Option<Arc<Session>> {
    registry().lock().unwrap().get(&id).cloned()
}
fn code(error: io::Error) -> u32 {
    error.raw_os_error().unwrap_or(CLOSED as i32) as u32
}
struct Pending {
    bytes: Vec<u8>,
    offset: usize,
    serial: u64,
}
enum Phase {
    Connecting,
    Proxy(Vec<u8>),
    Ready,
}
struct Connection {
    socket: TcpStream,
    session: Arc<Session>,
    deadline: Instant,
    phase: Phase,
    authority: String,
    sends: VecDeque<Pending>,
    paused: bool,
}
impl Drop for Connection {
    fn drop(&mut self) {
        SOCKETS.fetch_sub(1, Ordering::Relaxed);
        self.session.outgoing.store(0, Ordering::Relaxed);
    }
}
impl Connection {
    fn connected(&mut self) -> Result<(), u32> {
        if let Some(error) = self.socket.take_error().map_err(code)? {
            return Err(code(error));
        }
        if self.socket.peer_addr().is_err() {
            return Ok(());
        }
        // Windows can reject TCP_NODELAY with WSAEINVAL while the nonblocking
        // connect is pending. Apply it only after peer_addr confirms success.
        self.socket.set_nodelay(true).map_err(code)?;
        if self.authority.is_empty() {
            self.phase = Phase::Ready;
            if !self.session.event(1, 0, 0, vec![]) {
                return Err(CLOSED);
            }
        } else {
            self.phase = Phase::Proxy(vec![]);
            self.sends.push_front(Pending {
                bytes: format!(
                    "CONNECT {} HTTP/1.1\r\nHost: {}\r\n\r\n",
                    self.authority, self.authority
                )
                .into_bytes(),
                offset: 0,
                serial: 0,
            });
        }
        self.write()
    }
    fn write(&mut self) -> Result<(), u32> {
        if matches!(self.phase, Phase::Connecting) {
            return Ok(());
        }
        while let Some(front) = self.sends.front() {
            // User writes may not precede a successful CONNECT response.
            if matches!(self.phase, Phase::Proxy(_)) && front.serial != 0 {
                break;
            }
            let proxy = matches!(self.phase, Phase::Proxy(_));
            let mut sent = if front.offset == front.bytes.len() {
                0
            } else {
                let buffers: Vec<IoSlice<'_>> = self
                    .sends
                    .iter()
                    .take_while(|p| !proxy || p.serial == 0)
                    .take(128)
                    .map(|p| IoSlice::new(&p.bytes[p.offset..]))
                    .collect();
                match self.socket.write_vectored(&buffers) {
                    Ok(0) => return Err(CLOSED),
                    Ok(n) => n,
                    Err(e) if e.kind() == io::ErrorKind::WouldBlock => return Ok(()),
                    Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
                    Err(e) => return Err(code(e)),
                }
            };
            while let Some(front) = self.sends.front_mut() {
                let n = sent.min(front.bytes.len() - front.offset);
                front.offset += n;
                sent -= n;
                if front.offset != front.bytes.len() {
                    break;
                }
                let done = self.sends.pop_front().unwrap();
                if done.serial != 0 {
                    self.session
                        .outgoing
                        .fetch_sub(done.bytes.len(), Ordering::Relaxed);
                    // add() has no completion consumer. Only an explicit empty
                    // flush barrier needs a Dart acknowledgement; hundreds of
                    // subscription-write ACKs must not delay incoming records.
                    if done.bytes.is_empty() && !self.session.event(3, 0, done.serial, vec![]) {
                        return Err(CLOSED);
                    }
                }
                if sent == 0 {
                    break;
                }
            }
        }
        Ok(())
    }
    // true means work may remain after the fairness budget; false is EOF.
    fn read(&mut self) -> Result<(bool, bool), u32> {
        let mut buffer = [0u8; 32768];
        for _ in 0..32 {
            let available = READ_HIGH.saturating_sub(self.session.queue.lock().unwrap().bytes);
            if available == 0 {
                return Ok((true, false));
            }
            let capacity = available.min(buffer.len());
            match self.socket.read(&mut buffer[..capacity]) {
                Ok(0) => return Ok((false, false)),
                Ok(n) => {
                    if let Phase::Proxy(header) = &mut self.phase {
                        header.extend_from_slice(&buffer[..n]);
                        if let Some(end) = header.windows(4).position(|p| p == b"\r\n\r\n") {
                            if end + 4 > 16384 {
                                return Err(PROXY_HEADER);
                            }
                            let status = proxy_status(&header[..end + 4])?;
                            if status != 200 {
                                return Err(PROXY_HEADER + status);
                            }
                            let pending = header[end + 4..].to_vec();
                            self.phase = Phase::Ready;
                            if !self.session.event(1, 0, 0, vec![]) {
                                return Err(CLOSED);
                            }
                            if !pending.is_empty() && !self.session.event(2, 0, 0, pending) {
                                return Err(OVERFLOW);
                            }
                            self.write()?;
                        } else if header.len() > 16384 {
                            return Err(PROXY_HEADER);
                        }
                    } else if !self.session.event(2, 0, 0, buffer[..n].to_vec()) {
                        return Err(OVERFLOW);
                    }
                }
                Err(e) if e.kind() == io::ErrorKind::WouldBlock => return Ok((true, false)),
                Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
                Err(e) => return Err(code(e)),
            }
        }
        Ok((true, true))
    }
}
fn proxy_status(header: &[u8]) -> Result<u32, u32> {
    let line = header.split(|&b| b == b'\n').next().ok_or(PROXY_HEADER)?;
    if !(line.starts_with(b"HTTP/1.0 ") || line.starts_with(b"HTTP/1.1 ")) || line.len() < 13 {
        return Err(PROXY_HEADER);
    }
    if line[12] != b' ' && line[12] != b'\r' {
        return Err(PROXY_HEADER);
    }
    std::str::from_utf8(&line[9..12])
        .ok()
        .and_then(|s| s.parse().ok())
        .ok_or(PROXY_HEADER)
}
enum Command {
    Open(u64, SocketAddr, String, Duration),
    Send(u64, Vec<u8>, u64),
    Pause(u64, bool),
    Drain(u64),
    Release(u64),
}
struct Reactor {
    sender: mpsc::Sender<Command>,
    waker: Arc<Waker>,
}
impl Reactor {
    fn send(&self, command: Command) -> bool {
        self.sender.send(command).is_ok() && self.waker.wake().is_ok()
    }
    fn create() -> Result<Self, u32> {
        let poll = Poll::new().map_err(code)?;
        let waker = Arc::new(Waker::new(poll.registry(), WAKE).map_err(code)?);
        let (sender, receiver) = mpsc::channel();
        thread::Builder::new()
            .name("rq-tcp-reactor".into())
            .stack_size(256 * 1024)
            .spawn(move || run(poll, receiver))
            .map_err(code)?;
        Ok(Self { sender, waker })
    }
}
static REACTOR: OnceLock<Result<Reactor, u32>> = OnceLock::new();
fn reactor() -> Result<&'static Reactor, u32> {
    REACTOR
        .get_or_init(Reactor::create)
        .as_ref()
        .map_err(|&e| e)
}
fn remove(poll: &Poll, connections: &mut HashMap<u64, Connection>, id: u64, error: Option<u32>) {
    if let Some(mut connection) = connections.remove(&id) {
        let _ = poll.registry().deregister(&mut connection.socket);
        connection.session.finish(error);
    }
    if connections.is_empty() {
        connections.shrink_to_fit();
    }
}
fn run(mut poll: Poll, commands: mpsc::Receiver<Command>) {
    THREADS.fetch_add(1, Ordering::Relaxed);
    let mut connections = HashMap::<u64, Connection>::new();
    let mut events = Events::with_capacity(1024);
    let mut pending = VecDeque::<u64>::new();
    let mut writes = HashSet::<u64>::new();
    loop {
        for command in commands.try_iter() {
            match command {
                Command::Release(id) => remove(&poll, &mut connections, id, None),
                Command::Pause(id, paused) => {
                    if let Some(c) = connections.get_mut(&id) {
                        c.paused = paused;
                        if !paused {
                            pending.push_back(id);
                        }
                    }
                }
                Command::Drain(id) => {
                    pending.push_back(id);
                }
                Command::Send(id, bytes, serial) => {
                    if crate::network_diagnostic::active() {
                        crate::network_diagnostic::record(
                            "native_tcp",
                            id,
                            "send_queued",
                            serde_json::json!({"serial":serial}),
                            &bytes,
                        );
                    }
                    if let Some(c) = connections.get_mut(&id) {
                        c.sends.push_back(Pending {
                            bytes,
                            offset: 0,
                            serial,
                        });
                        writes.insert(id);
                    }
                }
                Command::Open(id, address, authority, timeout) => {
                    if crate::network_diagnostic::active() {
                        crate::network_diagnostic::record(
                            "native_tcp",
                            id,
                            "connect",
                            serde_json::json!({"address":address.to_string(),"authority":authority}),
                            &[],
                        );
                    }
                    let Some(s) = session(id).filter(|s| !s.stopped.load(Ordering::Acquire)) else {
                        continue;
                    };
                    let opened = TcpStream::connect(address).and_then(|mut socket| {
                        poll.registry().register(
                            &mut socket,
                            Token(id as usize),
                            Interest::READABLE | Interest::WRITABLE,
                        )?;
                        Ok(socket)
                    });
                    match opened {
                        Ok(socket) => {
                            SOCKETS.fetch_add(1, Ordering::Relaxed);
                            connections.insert(
                                id,
                                Connection {
                                    socket,
                                    session: s,
                                    deadline: Instant::now() + timeout,
                                    phase: Phase::Connecting,
                                    authority,
                                    sends: VecDeque::new(),
                                    paused: false,
                                },
                            );
                        }
                        Err(error) => {
                            s.finish(Some(code(error)));
                        }
                    }
                }
            }
        }
        for id in writes.drain() {
            if let Some(c) = connections.get_mut(&id) {
                if let Err(error) = c.write() {
                    remove(&poll, &mut connections, id, Some(error));
                }
            }
        }
        let now = Instant::now();
        let expired: Vec<u64> = connections
            .iter()
            .filter_map(|(&id, c)| {
                (!matches!(c.phase, Phase::Ready) && c.deadline <= now).then_some(id)
            })
            .collect();
        for id in expired {
            remove(&poll, &mut connections, id, Some(TIMEOUT));
        }
        // Budgeted reads must resume even when an edge-triggered socket is
        // still readable. Round-robin continuation does not require a timer.
        for _ in 0..pending.len() {
            let id = pending.pop_front().unwrap();
            if let Some(c) = connections.get_mut(&id) {
                if c.paused || matches!(c.phase, Phase::Connecting) {
                    continue;
                }
                match c.read() {
                    Ok((true, true)) => pending.push_back(id),
                    Ok((false, _)) => remove(&poll, &mut connections, id, None),
                    Err(error) => remove(&poll, &mut connections, id, Some(error)),
                    _ => {}
                }
            }
        }
        let timeout = if !pending.is_empty() {
            Some(Duration::ZERO)
        } else {
            connections
                .values()
                .filter(|c| !matches!(c.phase, Phase::Ready))
                .map(|c| c.deadline.saturating_duration_since(Instant::now()))
                .min()
        };
        if let Err(error) = poll.poll(&mut events, timeout) {
            if error.kind() == io::ErrorKind::Interrupted {
                continue;
            }
            let error = code(error);
            for id in connections.keys().copied().collect::<Vec<_>>() {
                remove(&poll, &mut connections, id, Some(error));
            }
            break;
        }
        for event in events.iter() {
            let id = event.token().0 as u64;
            if id == 0 {
                continue;
            }
            let Some(c) = connections.get_mut(&id) else {
                continue;
            };
            let result = (|| -> Result<bool, u32> {
                if matches!(c.phase, Phase::Connecting) {
                    c.connected()?;
                }
                if matches!(c.phase, Phase::Connecting) {
                    return Ok(true);
                }
                if event.is_writable() {
                    c.write()?;
                }
                if !c.paused && (event.is_readable() || event.is_read_closed() || event.is_error())
                {
                    let (alive, more) = c.read()?;
                    if more {
                        pending.push_back(id);
                    }
                    return Ok(alive);
                }
                Ok(true)
            })();
            match result {
                Ok(false) => remove(&poll, &mut connections, id, None),
                Err(error) => remove(&poll, &mut connections, id, Some(error)),
                _ => {}
            }
        }
    }
    THREADS.fetch_sub(1, Ordering::Relaxed);
}

#[no_mangle]
pub extern "C" fn rq_tcp_abi_version() -> u32 {
    1
}
#[no_mangle]
pub unsafe extern "C" fn rq_tcp_open(
    ip: *const u8,
    port: u32,
    authority: *const u8,
    timeout: u32,
    dart_port: i64,
    post: Post,
) -> u64 {
    if ip.is_null() || authority.is_null() || port == 0 || port > 65535 {
        return 0;
    }
    let Ok(ip) = unsafe { CStr::from_ptr(ip.cast()) }
        .to_str()
        .ok()
        .and_then(|s| s.parse::<IpAddr>().ok())
        .ok_or(())
    else {
        return 0;
    };
    let Ok(authority) = unsafe { CStr::from_ptr(authority.cast()) }.to_str() else {
        return 0;
    };
    if authority.len() > 1024 || authority.bytes().any(|b| b < 0x21 || b > 0x7e) {
        return 0;
    }
    let Ok(reactor) = reactor() else {
        return 0;
    };
    let id = NEXT.fetch_add(1, Ordering::Relaxed);
    registry().lock().unwrap().insert(
        id,
        Arc::new(Session {
            diagnostic_id: id,
            queue: Mutex::new(Queue::default()),
            stopped: AtomicBool::new(false),
            outgoing: AtomicUsize::new(0),
            dart_port,
            post,
        }),
    );
    if !reactor.send(Command::Open(
        id,
        SocketAddr::new(ip, port as u16),
        authority.into(),
        Duration::from_millis(timeout.clamp(1, 120000) as u64),
    )) {
        registry().lock().unwrap().remove(&id);
        return 0;
    }
    id
}
#[no_mangle]
pub unsafe extern "C" fn rq_tcp_send(id: u64, input: *const u8, length: usize, serial: u64) -> u32 {
    let Some(s) = session(id) else {
        return 1;
    };
    if s.stopped.load(Ordering::Acquire)
        || serial == 0
        || length > LIMIT
        || (length != 0 && input.is_null())
    {
        return 1;
    }
    if s.outgoing
        .try_update(Ordering::Relaxed, Ordering::Relaxed, |n| {
            n.checked_add(length).filter(|n| *n <= LIMIT)
        })
        .is_err()
    {
        return 2;
    }
    let bytes = if length == 0 {
        vec![]
    } else {
        unsafe { std::slice::from_raw_parts(input, length) }.to_vec()
    };
    if !reactor()
        .map(|r| r.send(Command::Send(id, bytes, serial)))
        .unwrap_or(false)
    {
        s.outgoing.fetch_sub(length, Ordering::Relaxed);
        return 1;
    }
    0
}
#[no_mangle]
pub unsafe extern "C" fn rq_tcp_take(
    id: u64,
    length: *mut usize,
    kind: *mut u32,
    code: *mut u32,
    serial: *mut u64,
) -> *const u8 {
    let Some(s) = session(id) else {
        return ptr::null();
    };
    if length.is_null() || kind.is_null() || code.is_null() || serial.is_null() {
        return ptr::null();
    }
    let mut q = s.queue.lock().unwrap();
    let Some(event) = q.events.pop_front() else {
        return ptr::null();
    };
    let was_high = q.bytes >= READ_LOW;
    q.bytes -= event.bytes.len();
    if was_high && q.bytes < READ_LOW {
        if let Ok(r) = reactor() {
            r.send(Command::Drain(id));
        }
    }
    q.delivered = event.bytes;
    unsafe {
        *length = q.delivered.len();
        *kind = event.kind;
        *code = event.code;
        *serial = event.serial;
    }
    q.delivered.as_ptr()
}
/// Transfer a frame's allocation to Dart external typed data. It is independent
/// of the connection, subsequent reads, and release. Control frames own no data.
#[no_mangle]
pub unsafe extern "C" fn rq_tcp_take_owned(
    id: u64,
    length: *mut usize,
    kind: *mut u32,
    code: *mut u32,
    serial: *mut u64,
    owner: *mut *mut c_void,
) -> *const u8 {
    let Some(s) = session(id) else {
        return ptr::null();
    };
    if length.is_null() || kind.is_null() || code.is_null() || serial.is_null() || owner.is_null() {
        return ptr::null();
    }
    let mut q = s.queue.lock().unwrap();
    let Some(event) = q.events.pop_front() else {
        return ptr::null();
    };
    let was_high = q.bytes >= READ_LOW;
    q.bytes -= event.bytes.len();
    if was_high && q.bytes < READ_LOW {
        if let Ok(r) = reactor() {
            r.send(Command::Drain(id));
        }
    }
    unsafe {
        *length = event.bytes.len();
        *kind = event.kind;
        *code = event.code;
        *serial = event.serial;
        *owner = ptr::null_mut();
    }
    if event.bytes.is_empty() {
        return &EMPTY;
    }
    let bytes = Box::new(event.bytes);
    let data = bytes.as_ptr();
    unsafe {
        *owner = Box::into_raw(bytes).cast();
    }
    data
}
static EMPTY: u8 = 0;
#[no_mangle]
pub unsafe extern "C" fn rq_tcp_chunk_release(owner: *mut c_void) {
    if !owner.is_null() {
        drop(unsafe { Box::from_raw(owner.cast::<Vec<u8>>()) });
    }
}
#[no_mangle]
pub extern "C" fn rq_tcp_release(id: u64) {
    let removed = {
        let mut owners = registry().lock().unwrap();
        let removed = owners.remove(&id);
        if owners.is_empty() {
            owners.shrink_to_fit();
        }
        removed
    };
    if let Some(s) = removed {
        s.stopped.store(true, Ordering::Release);
        if let Ok(r) = reactor() {
            r.send(Command::Release(id));
        }
    }
}
#[no_mangle]
pub extern "C" fn rq_tcp_release_finalizer(id: *mut c_void) {
    rq_tcp_release(id as usize as u64);
}
#[no_mangle]
pub extern "C" fn rq_tcp_pause(id: u64, paused: u32) {
    if let Ok(r) = reactor() {
        r.send(Command::Pause(id, paused != 0));
    }
}
#[no_mangle]
pub extern "C" fn rq_tcp_sessions() -> usize {
    registry().lock().unwrap().len()
}
#[no_mangle]
pub extern "C" fn rq_tcp_sockets() -> usize {
    SOCKETS.load(Ordering::Relaxed)
}
#[no_mangle]
pub extern "C" fn rq_tcp_threads() -> usize {
    THREADS.load(Ordering::Relaxed)
}
#[no_mangle]
pub extern "C" fn rq_tcp_queue_peak() -> usize {
    registry()
        .lock()
        .unwrap()
        .values()
        .map(|s| s.queue.lock().unwrap().peak_bytes)
        .max()
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    unsafe extern "C" fn posted(_: i64, _: *mut DartObject) -> bool {
        true
    }
    #[test]
    fn transferred_bytes_outlive_the_connection_owner() {
        let s = Arc::new(Session {
            diagnostic_id: 0,
            queue: Mutex::new(Queue::default()),
            stopped: AtomicBool::new(false),
            outgoing: AtomicUsize::new(0),
            dart_port: 1,
            post: posted,
        });
        let id = NEXT.fetch_add(1, Ordering::Relaxed);
        registry().lock().unwrap().insert(id, s.clone());
        s.event(2, 0, 0, vec![0, 1, 128, 255]);
        let (mut length, mut kind, mut code, mut serial, mut owner) = (0, 0, 0, 0, ptr::null_mut());
        let data = unsafe {
            rq_tcp_take_owned(
                id,
                &mut length,
                &mut kind,
                &mut code,
                &mut serial,
                &mut owner,
            )
        };
        registry().lock().unwrap().remove(&id);
        drop(s);
        assert_eq!((length, kind), (4, 2));
        assert_eq!(
            unsafe { std::slice::from_raw_parts(data, length) },
            &[0, 1, 128, 255]
        );
        unsafe {
            rq_tcp_chunk_release(owner);
        }
    }
    #[test]
    fn connect_header_preserves_status_and_does_not_inspect_waveform_bytes() {
        assert_eq!(
            proxy_status(b"HTTP/1.1 200 Connection established\r\n\r\n"),
            Ok(200)
        );
        assert_eq!(
            proxy_status(b"HTTP/1.0 407 Proxy Authentication Required\r\n\r\n"),
            Ok(407)
        );
        assert_eq!(proxy_status(b"HTTP/1.1 200\r\n\r\n"), Ok(200));
        for bad in [
            b"HTTP/1.1 2000\r\n\r\n".as_slice(),
            b"HTTP/2 200\r\n\r\n",
            b"garbage",
        ] {
            assert!(proxy_status(bad).is_err());
        }
    }
}
