//! Replay archive owner. A single ordered worker owns caches, journals, counters
//! and files. UI producers enqueue new records; accumulated JSON never returns
//! to Dart during automatic saving. Journals retain original record bytes.
#![cfg(any(windows, target_os = "android"))]
use serde_json::{json, Value};
use std::{
    collections::{HashMap, HashSet, VecDeque},
    ffi::c_void,
    fs::{self, File, OpenOptions},
    io::{self, BufWriter, Read, Seek, SeekFrom, Write},
    path::{Component, Path, PathBuf},
    ptr,
    sync::{
        atomic::{AtomicU64, AtomicUsize, Ordering},
        mpsc, Arc, Mutex, OnceLock,
    },
    thread,
    time::{SystemTime, UNIX_EPOCH},
};
#[repr(C)]
pub struct DartObject {
    kind: i32,
    value: [i64; 5],
}
type Post = unsafe extern "C" fn(i64, *mut DartObject) -> bool;
struct Notice {
    serial: u64,
    bytes: Vec<u8>,
}
struct Session {
    sender: mpsc::Sender<Command>,
    notices: Mutex<VecDeque<Notice>>,
    port: i64,
    post: Post,
    queued: AtomicUsize,
    peak: AtomicUsize,
}
impl Session {
    fn notify(&self, serial: u64, bytes: Vec<u8>) {
        let mut q = self.notices.lock().unwrap();
        let notify = q.is_empty();
        q.push_back(Notice { serial, bytes });
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
enum Command {
    Apply {
        op: u32,
        json: Vec<u8>,
        blob: Vec<u8>,
        serial: u64,
    },
    Query {
        records: bool,
        reply: mpsc::Sender<Vec<u8>>,
    },
    Barrier(mpsc::Sender<()>),
    Shutdown,
}
static NEXT: AtomicU64 = AtomicU64::new(1);
static OWNERS: OnceLock<Mutex<HashMap<u64, Arc<Session>>>> = OnceLock::new();
static WORKERS: AtomicUsize = AtomicUsize::new(0);
fn owners() -> &'static Mutex<HashMap<u64, Arc<Session>>> {
    OWNERS.get_or_init(Default::default)
}
fn owner(id: u64) -> Option<Arc<Session>> {
    owners().lock().unwrap().get(&id).cloned()
}
fn invalid(message: &str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, message)
}
fn number() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_micros() as i64
}
#[repr(C)]
#[cfg(windows)]
struct FileTime {
    low: u32,
    high: u32,
}
#[repr(C)]
#[derive(Default)]
#[cfg(windows)]
struct SysTime {
    year: u16,
    month: u16,
    week: u16,
    day: u16,
    hour: u16,
    minute: u16,
    second: u16,
    millis: u16,
}
#[link(name = "kernel32")]
#[cfg(windows)]
extern "system" {
    fn GetSystemTimePreciseAsFileTime(time: *mut FileTime);
    fn FileTimeToLocalFileTime(utc: *const FileTime, local: *mut FileTime) -> i32;
    fn FileTimeToSystemTime(file: *const FileTime, time: *mut SysTime) -> i32;
}
#[cfg(windows)]
fn local_iso() -> String {
    let mut utc = FileTime { low: 0, high: 0 };
    let mut local = FileTime { low: 0, high: 0 };
    let mut t = SysTime::default();
    unsafe {
        GetSystemTimePreciseAsFileTime(&mut utc);
        FileTimeToLocalFileTime(&utc, &mut local);
        FileTimeToSystemTime(&local, &mut t);
    }
    let ticks = ((utc.high as u64) << 32) | utc.low as u64;
    let micros = (ticks % 10_000_000) / 10;
    let base = format!(
        "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}.{:03}",
        t.year,
        t.month,
        t.day,
        t.hour,
        t.minute,
        t.second,
        micros / 1000
    );
    if micros % 1000 == 0 {
        base
    } else {
        format!("{base}{:03}", micros % 1000)
    }
}
#[cfg(target_os = "android")]
use crate::android_platform::local_iso;
/// Length-prefixed spool supports original pretty JSON as well as compact JSON.
struct Journal {
    path: PathBuf,
    writer: Option<BufWriter<File>>,
    memory: Vec<Vec<u8>>,
    count: u64,
}
impl Journal {
    fn new(id: u64, kind: &str, disk: bool) -> io::Result<Self> {
        #[cfg(windows)]
        let temporary = std::env::temp_dir();
        #[cfg(target_os = "android")]
        let temporary = crate::android_platform::cache()?.clone();
        let path = temporary.join(format!(
            "rq-replay-{}-{id}-{}-{kind}.journal",
            std::process::id(),
            number()
        ));
        let writer = if disk {
            Some(BufWriter::with_capacity(
                64 * 1024,
                OpenOptions::new()
                    .create_new(true)
                    .write(true)
                    .open(&path)?,
            ))
        } else {
            None
        };
        Ok(Self {
            path,
            writer,
            memory: vec![],
            count: 0,
        })
    }
    fn append(&mut self, bytes: Vec<u8>) -> io::Result<()> {
        if let Some(w) = self.writer.as_mut() {
            w.write_all(&(bytes.len() as u64).to_le_bytes())?;
            w.write_all(&bytes)?;
        } else {
            self.memory.push(bytes);
        }
        self.count += 1;
        Ok(())
    }
    fn flush(&mut self) -> io::Result<()> {
        if let Some(w) = self.writer.as_mut() {
            w.flush()?;
        }
        Ok(())
    }
    fn copy_from(&self, offset: u64, w: &mut impl Write, mut count: u64) -> io::Result<(u64, u64)> {
        let mut f = File::open(&self.path)?;
        f.seek(SeekFrom::Start(offset))?;
        let mut size = [0u8; 8];
        let mut buffer = vec![0u8; 32 * 1024];
        loop {
            let start = f.stream_position()?;
            if f.read(&mut size[..1])? == 0 {
                return Ok((start, count));
            }
            f.read_exact(&mut size[1..])?;
            let mut remaining = u64::from_le_bytes(size);
            if remaining > 64 * 1024 * 1024 {
                return Err(invalid("oversized replay record"));
            }
            if count != 0 {
                w.write_all(b",\n")?;
            }
            while remaining != 0 {
                let n = (remaining as usize).min(buffer.len());
                f.read_exact(&mut buffer[..n])?;
                w.write_all(&buffer[..n])?;
                remaining -= n as u64;
            }
            count += 1;
        }
    }
    fn records(&mut self) -> io::Result<Vec<u8>> {
        self.flush()?;
        let mut bytes = vec![b'['];
        if self.writer.is_some() {
            self.copy_from(0, &mut bytes, 0)?;
        } else {
            for (i, row) in self.memory.iter().enumerate() {
                if i != 0 {
                    bytes.push(b',');
                }
                bytes.extend(row);
            }
        }
        bytes.push(b']');
        Ok(bytes)
    }
}
impl Drop for Journal {
    fn drop(&mut self) {
        self.writer.take();
        let _ = fs::remove_file(&self.path);
    }
}
struct JsonSink {
    path: PathBuf,
    anchor: u64,
    cursor: u64,
    count: u64,
    initialized: bool,
}
impl JsonSink {
    fn new(path: PathBuf) -> Self {
        Self {
            path,
            anchor: 11,
            cursor: 0,
            count: 0,
            initialized: false,
        }
    }
    fn write(
        &mut self,
        records: &Journal,
        tail: impl FnOnce(&mut File) -> io::Result<()>,
    ) -> io::Result<()> {
        let mut f = OpenOptions::new()
            .create(true)
            .truncate(false)
            .write(true)
            .open(&self.path)?;
        if !self.initialized {
            f.set_len(0)?;
            f.write_all(b"{\"frames\":[")?;
        } else {
            f.seek(SeekFrom::Start(self.anchor))?;
        }
        let (cursor, count) = records.copy_from(self.cursor, &mut f, self.count)?;
        let anchor = f.stream_position()?;
        f.write_all(b"],")?;
        tail(&mut f)?;
        f.write_all(b"}")?;
        let length = f.stream_position()?;
        f.set_len(length)?;
        f.flush()?;
        self.anchor = anchor;
        self.cursor = cursor;
        self.count = count;
        self.initialized = true;
        Ok(())
    }
}
struct Gif {
    jst: String,
    url: String,
    layer: String,
    file_name: String,
    bytes: Vec<u8>,
}
struct State {
    id: u64,
    enabled: bool,
    disk: bool,
    start: String,
    stamp: String,
    out: PathBuf,
    records: Option<Journal>,
    gifs: Option<Journal>,
    pending: VecDeque<Gif>,
    keys: HashSet<String>,
    log: Option<JsonSink>,
    package: Option<JsonSink>,
    manifest: Option<JsonSink>,
    capture_dir: Option<PathBuf>,
    frames: u64,
    detections: u64,
    epicenters: u64,
    last_saved: u64,
    last_auto_at: Option<i64>,
    error: Option<String>,
}
impl State {
    fn new(id: u64) -> Self {
        Self {
            id,
            enabled: false,
            disk: true,
            start: String::new(),
            stamp: String::new(),
            out: PathBuf::new(),
            records: None,
            gifs: None,
            pending: VecDeque::new(),
            keys: HashSet::new(),
            log: None,
            package: None,
            manifest: None,
            capture_dir: None,
            frames: 0,
            detections: 0,
            epicenters: 0,
            last_saved: 0,
            last_auto_at: None,
            error: None,
        }
    }
    fn status(&self, session: &Session) -> Vec<u8> {
        serde_json::to_vec(&json!({"enabled":self.enabled,"records":self.records.as_ref().map_or(0,|j|j.count),"frames":self.frames,"detections":self.detections,"epicenters":self.epicenters,"gif_count":self.gifs.as_ref().map_or(0,|j|j.count),"log_path":self.log.as_ref().filter(|s|s.initialized).map(|s|s.path.to_string_lossy()),"capture_dir":self.capture_dir.as_ref().map(|p|p.to_string_lossy()),"error":self.error,"queued_bytes":session.queued.load(Ordering::Relaxed),"peak_queued_bytes":session.peak.load(Ordering::Relaxed)})).unwrap()
    }
    fn start(&mut self, data: &[u8]) -> io::Result<()> {
        // Complete the preceding session before dropping its journals.
        if self.enabled {
            self.save()?;
        }
        let config: Value =
            serde_json::from_slice(data).map_err(|_| invalid("invalid replay configuration"))?;
        let text = |key: &str| {
            config[key]
                .as_str()
                .map(str::to_owned)
                .ok_or_else(|| invalid("missing replay configuration"))
        };
        let start = text("session_start")?;
        let stamp = text("stamp")?;
        let out = text("out_dir")?;
        if stamp.is_empty() || !stamp.bytes().all(|b| b.is_ascii_digit() || b == b'_') {
            return Err(invalid("invalid session stamp"));
        }
        self.enabled = false;
        self.records.take();
        self.gifs.take();
        self.start = start;
        self.stamp = stamp;
        self.out = PathBuf::from(out);
        self.disk = config["write_to_disk"].as_bool().unwrap_or(true);
        self.frames = 0;
        self.detections = 0;
        self.epicenters = 0;
        self.last_saved = 0;
        self.last_auto_at = None;
        self.keys.clear();
        self.log = None;
        self.package = None;
        self.manifest = None;
        self.capture_dir = None;
        self.error = None;
        self.records = Some(Journal::new(self.id, "records", self.disk)?);
        self.gifs = Some(Journal::new(self.id, "gifs", self.disk)?);
        self.enabled = true;
        self.flush_pending()
    }
    fn append(&mut self, op: u32, bytes: Vec<u8>) -> io::Result<bool> {
        if !self.enabled {
            return Ok(false);
        }
        // Validate but do not parse numbers or rewrite original field literals.
        let _: &serde_json::value::RawValue =
            serde_json::from_slice(&bytes).map_err(|_| invalid("invalid replay JSON record"))?;
        self.records.as_mut().unwrap().append(bytes)?;
        match op {
            2 => self.frames += 1,
            3 => self.detections += 1,
            4 => self.epicenters += 1,
            _ => {}
        }
        let count = self.records.as_ref().unwrap().count;
        let now = number();
        if self.disk
            && count - self.last_saved >= 80
            && self
                .last_auto_at
                .is_none_or(|last| now - last >= 15_000_000)
        {
            self.last_saved = count;
            self.last_auto_at = Some(now);
            // Match the original retry cadence even if saving fails. A locked
            // or full disk must not cause a save attempt on every new record.
            self.save()?;
            return Ok(true);
        }
        Ok(false)
    }
    fn capture(&mut self, data: &[u8], bytes: Vec<u8>) -> io::Result<()> {
        let v: Value = serde_json::from_slice(data).map_err(|_| invalid("invalid GIF metadata"))?;
        let get = |key: &str| {
            v[key]
                .as_str()
                .map(str::to_owned)
                .ok_or_else(|| invalid("missing GIF metadata"))
        };
        let url = get("url")?;
        let fallback = get("fallback_name")?;
        let path = url.split(['?', '#']).next().unwrap_or("");
        let name = path.rsplit('/').next().unwrap_or("");
        let decoded = percent_decode(name);
        let file_name = if decoded.to_lowercase().ends_with(".gif") {
            decoded
        } else {
            fallback
        };
        let gif = Gif {
            jst: get("jst")?,
            url,
            layer: get("layer")?,
            file_name,
            bytes,
        };
        self.pending.push_back(gif);
        while self.pending.len() > 30 {
            self.pending.pop_front();
        }
        if self.enabled {
            let gif = self.pending.back().unwrap();
            Self::write_gif(
                &self.out,
                &self.stamp,
                self.disk,
                &mut self.capture_dir,
                &mut self.keys,
                self.gifs.as_mut().unwrap(),
                gif,
            )?;
        }
        Ok(())
    }
    fn flush_pending(&mut self) -> io::Result<()> {
        if !self.enabled {
            return Ok(());
        }
        for gif in &self.pending {
            Self::write_gif(
                &self.out,
                &self.stamp,
                self.disk,
                &mut self.capture_dir,
                &mut self.keys,
                self.gifs.as_mut().unwrap(),
                gif,
            )?;
        }
        Ok(())
    }
    fn write_gif(
        out: &Path,
        stamp: &str,
        disk: bool,
        dir: &mut Option<PathBuf>,
        keys: &mut HashSet<String>,
        journal: &mut Journal,
        gif: &Gif,
    ) -> io::Result<()> {
        if !disk {
            return Ok(());
        }
        for component in [&gif.layer, &gif.file_name] {
            let mut c = Path::new(component).components();
            if !matches!(c.next(), Some(Component::Normal(_))) || c.next().is_some() {
                return Err(invalid("invalid GIF path component"));
            }
        }
        let key = format!("{}/{}", gif.layer, gif.file_name);
        if keys.contains(&key) {
            return Ok(());
        }
        let capture = dir.get_or_insert_with(|| out.join(format!("nied_capture_{stamp}")));
        let layer = capture.join("raw").join(&gif.layer);
        fs::create_dir_all(&layer)?;
        fs::write(layer.join(&gif.file_name), &gif.bytes)?;
        let row=serde_json::to_vec(&json!({"jst":gif.jst,"layer":gif.layer,"url":gif.url,"path":format!("raw/{key}"),"bytes":gif.bytes.len()})).unwrap();
        journal.append(row)?;
        keys.insert(key);
        Ok(())
    }
    fn save(&mut self) -> io::Result<()> {
        let Some(records) = self.records.as_mut() else {
            return Ok(());
        };
        if !self.disk || records.count == 0 {
            return Ok(());
        }
        records.flush()?;
        let gifs = self.gifs.as_mut().unwrap();
        gifs.flush()?;
        fs::create_dir_all(&self.out)?;
        let log_path = self.out.join(format!("nied_replay_{}.json", self.stamp));
        let now = local_iso();
        let metadata=serde_json::to_vec(&json!({"session_start":self.start,"written_at":now,"frame_count":self.frames,"detection_count":self.detections,"epicenter_count":self.epicenters,"gif_capture_count":gifs.count,"capture_directory":self.capture_dir.as_ref().map(|p|p.to_string_lossy())})).unwrap();
        let tail = |f: &mut File| -> io::Result<()> {
            f.write_all(&metadata[1..metadata.len() - 1])?;
            f.write_all(b",\"captured_gifs\":[")?;
            gifs.copy_from(0, f, 0)?;
            f.write_all(b"]")
        };
        self.log
            .get_or_insert_with(|| JsonSink::new(log_path.clone()))
            .write(records, tail)?;
        if let Some(dir) = self.capture_dir.as_ref() {
            self.package
                .get_or_insert_with(|| JsonSink::new(dir.join("nied_replay.json")))
                .write(records, tail)?;
            let m=serde_json::to_vec(&json!({"schemaVersion":"nied_capture_v1","createdAt":local_iso(),"sessionStart":self.start,"sourceReplayPath":log_path.to_string_lossy(),"gifCount":gifs.count})).unwrap();
            self.manifest
                .get_or_insert_with(|| JsonSink::new(dir.join("capture_manifest.json")))
                .write(gifs, |f| f.write_all(&m[1..m.len() - 1]))?;
        }
        Ok(())
    }
    fn apply(&mut self, op: u32, data: Vec<u8>, blob: Vec<u8>) -> io::Result<bool> {
        match op {
            1 => {
                self.start(&data)?;
                Ok(true)
            }
            2..=5 => self.append(op, data),
            6 => {
                let had_directory = self.capture_dir.is_some();
                self.capture(&data, blob)?;
                Ok(!had_directory && self.capture_dir.is_some())
            }
            7 => {
                self.save()?;
                self.enabled = false;
                Ok(true)
            }
            8 => {
                self.save()?;
                Ok(true)
            }
            _ => Err(invalid("unknown replay operation")),
        }
    }
}
fn percent_decode(s: &str) -> String {
    let b = s.as_bytes();
    let mut result = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'%' && i + 2 < b.len() {
            if let Some(v) = std::str::from_utf8(&b[i + 1..i + 3])
                .ok()
                .and_then(|s| u8::from_str_radix(s, 16).ok())
            {
                result.push(v);
                i += 3;
                continue;
            }
        }
        result.push(b[i]);
        i += 1;
    }
    String::from_utf8(result).unwrap_or_else(|_| s.into())
}
#[no_mangle]
pub extern "C" fn rq_replay_open(port: i64, post: Post) -> u64 {
    let id = NEXT.fetch_add(1, Ordering::Relaxed);
    let (sender, receiver) = mpsc::channel();
    let session = Arc::new(Session {
        sender,
        notices: Mutex::new(VecDeque::new()),
        port,
        post,
        queued: AtomicUsize::new(0),
        peak: AtomicUsize::new(0),
    });
    let target = session.clone();
    if thread::Builder::new()
        .name("rq-replay-archive".into())
        .stack_size(256 * 1024)
        .spawn(move || {
            WORKERS.fetch_add(1, Ordering::Relaxed);
            let mut state = State::new(id);
            while let Ok(command) = receiver.recv() {
                match command {
                    Command::Apply {
                        op,
                        json,
                        blob,
                        serial,
                    } => {
                        let length = json.len() + blob.len();
                        let result = state.apply(op, json, blob);
                        target.queued.fetch_sub(length, Ordering::Relaxed);
                        match result {
                            Ok(notify) => {
                                state.error = None;
                                if notify || serial != 0 {
                                    target.notify(serial, state.status(&target));
                                }
                            }
                            Err(e) => {
                                state.error = Some(e.to_string());
                                target.notify(serial, state.status(&target));
                            }
                        }
                    }
                    Command::Query { records, reply } => {
                        let bytes = if records {
                            state
                                .records
                                .as_mut()
                                .map_or_else(|| Ok(b"[]".to_vec()), Journal::records)
                                .unwrap_or_else(|e| {
                                    serde_json::to_vec(
                                        &json!({"error":e.to_string(),"records_unavailable":true}),
                                    )
                                    .unwrap()
                                })
                        } else {
                            state.status(&target)
                        };
                        let _ = reply.send(bytes);
                    }
                    Command::Barrier(reply) => {
                        let _ = reply.send(());
                    }
                    Command::Shutdown => {
                        let _ = state.save();
                        break;
                    }
                }
            }
            WORKERS.fetch_sub(1, Ordering::Relaxed);
        })
        .is_err()
    {
        return 0;
    }
    owners().lock().unwrap().insert(id, session);
    id
}
#[no_mangle]
pub unsafe extern "C" fn rq_replay_send(
    id: u64,
    op: u32,
    json: *const u8,
    length: usize,
    blob: *const u8,
    blob_length: usize,
    serial: u64,
) -> u32 {
    if (length != 0 && json.is_null())
        || (blob_length != 0 && blob.is_null())
        || length > 64 * 1024 * 1024
        || blob_length > 64 * 1024 * 1024
    {
        return 1;
    }
    let Some(session) = owner(id) else {
        return 2;
    };
    let json = if length == 0 {
        vec![]
    } else {
        unsafe { std::slice::from_raw_parts(json, length) }.to_vec()
    };
    let blob = if blob_length == 0 {
        vec![]
    } else {
        unsafe { std::slice::from_raw_parts(blob, blob_length) }.to_vec()
    };
    let size = json.len() + blob.len();
    let queued = session.queued.fetch_add(size, Ordering::Relaxed) + size;
    session.peak.fetch_max(queued, Ordering::Relaxed);
    if session
        .sender
        .send(Command::Apply {
            op,
            json,
            blob,
            serial,
        })
        .is_err()
    {
        session.queued.fetch_sub(size, Ordering::Relaxed);
        return 2;
    }
    0
}
#[no_mangle]
pub unsafe extern "C" fn rq_replay_query(
    id: u64,
    records: u32,
    length: *mut usize,
    allocation: *mut *mut c_void,
) -> *const u8 {
    if length.is_null() || allocation.is_null() {
        return ptr::null();
    }
    let Some(session) = owner(id) else {
        return ptr::null();
    };
    let (tx, rx) = mpsc::channel();
    if session
        .sender
        .send(Command::Query {
            records: records != 0,
            reply: tx,
        })
        .is_err()
    {
        return ptr::null();
    }
    let Ok(bytes) = rx.recv() else {
        return ptr::null();
    };
    let bytes = Box::new(bytes);
    let p = bytes.as_ptr();
    unsafe {
        *length = bytes.len();
        *allocation = Box::into_raw(bytes).cast();
    }
    p
}
#[no_mangle]
pub unsafe extern "C" fn rq_replay_take(
    id: u64,
    length: *mut usize,
    serial: *mut u64,
    allocation: *mut *mut c_void,
) -> *const u8 {
    if length.is_null() || serial.is_null() || allocation.is_null() {
        return ptr::null();
    }
    let Some(session) = owner(id) else {
        return ptr::null();
    };
    let Some(notice) = session.notices.lock().unwrap().pop_front() else {
        return ptr::null();
    };
    let bytes = Box::new(notice.bytes);
    let p = bytes.as_ptr();
    unsafe {
        *length = bytes.len();
        *serial = notice.serial;
        *allocation = Box::into_raw(bytes).cast();
    }
    p
}
#[no_mangle]
pub unsafe extern "C" fn rq_replay_free(allocation: *mut c_void) {
    if !allocation.is_null() {
        drop(unsafe { Box::from_raw(allocation as *mut Vec<u8>) });
    }
}
#[no_mangle]
pub extern "C" fn rq_replay_barrier(id: u64) {
    if let Some(s) = owner(id) {
        let (tx, rx) = mpsc::channel();
        let _ = s.sender.send(Command::Barrier(tx));
        let _ = rx.recv();
    }
}
#[no_mangle]
pub extern "C" fn rq_replay_release(id: u64) {
    let mut owners = owners().lock().unwrap();
    if let Some(session) = owners.remove(&id) {
        let _ = session.sender.send(Command::Shutdown);
    }
    if owners.is_empty() {
        owners.shrink_to_fit();
    }
}
#[no_mangle]
pub extern "C" fn rq_replay_finalizer(id: *mut c_void) {
    rq_replay_release(id as u64);
}
#[no_mangle]
pub extern "C" fn rq_replay_workers() -> usize {
    WORKERS.load(Ordering::Relaxed)
}
