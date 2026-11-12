//! Directory replay storage. A serial storage isolate lends original JSON bytes;
//! Rust owns paths, immutable files, SHA-256, gzip streams and durable commits.
//! No report/frame JSON is reserialized or retained by the native owner.
use flate2::{read::MultiGzDecoder, Compression, GzBuilder};
use sha2::{Digest, Sha256};
use std::{
    collections::{HashMap, VecDeque},
    ffi::c_void,
    fs::{self, File, OpenOptions},
    io::{self, BufWriter, Read, Write},
    path::{Path, PathBuf},
    ptr,
    sync::{
        atomic::{AtomicUsize, Ordering},
        Arc, Condvar, Mutex,
    },
    thread::{self, JoinHandle},
};

const LIMIT: usize = 128 * 1024 * 1024;
static SESSIONS: AtomicUsize = AtomicUsize::new(0);
static RESULTS: AtomicUsize = AtomicUsize::new(0);
static CALLS: AtomicUsize = AtomicUsize::new(0);

struct Store {
    root: PathBuf,
    gate: Mutex<()>,
    writer: Mutex<Option<Writer>>,
}
// Only encoded bytes cross this boundary. A slow disk cannot retain an
// unbounded queue of Dart observation graphs (or an unbounded native queue).
const QUEUE_LIMIT: usize = 8 * 1024 * 1024;
struct Job {
    file: PathBuf,
    bytes: Vec<u8>,
    gzip: bool,
}
#[derive(Default)]
struct Queue {
    jobs: VecDeque<Job>,
    bytes: usize, // includes the job currently being written
    peak_bytes: usize,
    count: usize,
    error: Option<String>,
    closing: bool,
}
struct Writer {
    state: Arc<(Mutex<Queue>, Condvar)>,
    thread: Option<JoinHandle<()>>,
}
impl Writer {
    fn new() -> io::Result<Self> {
        let state = Arc::new((Mutex::new(Queue::default()), Condvar::new()));
        let worker = state.clone();
        let thread = thread::Builder::new()
            .name("replay-file-writer".into())
            .spawn(move || {
                let (lock, wake) = &*worker;
                loop {
                    let job = {
                        let mut q = lock.lock().unwrap();
                        while q.jobs.is_empty() && !q.closing {
                            q = wake.wait(q).unwrap();
                        }
                        match q.jobs.pop_front() {
                            Some(job) => job,
                            None => break,
                        }
                    };
                    let result = commit_immutable(&job.file, &job.bytes, job.gzip);
                    let mut q = lock.lock().unwrap();
                    match result {
                        Ok(()) => {
                            q.bytes -= job.bytes.len();
                            q.count -= 1;
                        }
                        Err(error) => {
                            // Keep this job and the rest for explicit retry.
                            // Never report a failed write as committed.
                            q.error = Some(error.to_string());
                            q.jobs.push_front(job);
                            wake.notify_all();
                            while q.error.is_some() && !q.closing {
                                q = wake.wait(q).unwrap();
                            }
                            if q.closing {
                                break;
                            }
                        }
                    }
                    wake.notify_all();
                }
            })?;
        Ok(Self { state, thread: Some(thread) })
    }
    fn submit(&self, file: PathBuf, bytes: &[u8], gzip: bool) -> io::Result<()> {
        let (lock, wake) = &*self.state;
        let mut q = lock.lock().map_err(|_| invalid("Replay queue lock poisoned"))?;
        // A single valid large frame is allowed, alone. All other producers
        // apply backpressure instead of allocating more queued payloads.
        while q.count > 0 && q.bytes.saturating_add(bytes.len()) > QUEUE_LIMIT {
            if let Some(error) = &q.error {
                return Err(io::Error::other(error.clone()));
            }
            q = wake.wait(q).map_err(|_| invalid("Replay queue lock poisoned"))?;
        }
        if let Some(error) = &q.error {
            return Err(io::Error::other(error.clone()));
        }
        q.bytes += bytes.len();
        q.peak_bytes = q.peak_bytes.max(q.bytes);
        q.count += 1;
        q.jobs.push_back(Job { file, bytes: bytes.to_vec(), gzip });
        wake.notify_all();
        Ok(())
    }
    fn status(&self) -> io::Result<Vec<u8>> {
        let q = self.state.0.lock().map_err(|_| invalid("Replay queue lock poisoned"))?;
        if let Some(error) = &q.error {
            return Err(io::Error::other(error.clone()));
        }
        Ok(serde_json::to_vec(&serde_json::json!({
            "pending": q.count, "bytes": q.bytes,
            "peakBytes": q.peak_bytes, "limitBytes": QUEUE_LIMIT,
        }))?)
    }
    fn retry(&self) {
        let mut q = self.state.0.lock().unwrap();
        q.error = None;
        self.state.1.notify_all();
    }
}
impl Drop for Writer {
    fn drop(&mut self) {
        {
            let mut q = self.state.0.lock().unwrap();
            q.closing = true;
            self.state.1.notify_all();
        }
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
    }
}
struct Reply {
    code: i32,
    bytes: Vec<u8>,
}
impl Drop for Reply {
    fn drop(&mut self) {
        RESULTS.fetch_sub(1, Ordering::Relaxed);
    }
}
impl Drop for Store {
    fn drop(&mut self) {
        SESSIONS.fetch_sub(1, Ordering::Relaxed);
    }
}
fn invalid(message: &str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, message)
}
fn hash(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}
fn digest_file(file: &Path) -> io::Result<String> {
    let mut input = File::open(file)?;
    let mut digest = Sha256::new();
    let mut buffer = [0u8; 32768];
    loop {
        let count = input.read(&mut buffer)?;
        if count == 0 {
            break;
        }
        digest.update(&buffer[..count]);
    }
    Ok(format!("{:x}", digest.finalize()))
}
fn valid_digest(value: &str) -> io::Result<()> {
    if value.len() != 64
        || !value
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
    {
        return Err(invalid("Invalid report file identity"));
    }
    Ok(())
}
fn read_bounded(mut reader: impl Read, limit: usize) -> io::Result<Vec<u8>> {
    let mut bytes = Vec::new();
    reader
        .by_ref()
        .take(limit as u64 + 1)
        .read_to_end(&mut bytes)?;
    if bytes.len() > limit {
        return Err(invalid("Replay file exceeds expanded size limit"));
    }
    Ok(bytes)
}
fn same_expanded(file: &Path, expected: &[u8]) -> io::Result<bool> {
    let mut input = MultiGzDecoder::new(File::open(file)?);
    let mut buffer = [0u8; 32768];
    let mut offset = 0;
    loop {
        let count = input.read(&mut buffer)?;
        if count == 0 {
            return Ok(offset == expected.len());
        }
        let end = offset + count;
        if expected.get(offset..end) != Some(&buffer[..count]) {
            return Ok(false);
        }
        offset = end;
    }
}
fn commit_immutable(file: &Path, bytes: &[u8], gzip: bool) -> io::Result<()> {
    if file.try_exists()? {
        let matches = if gzip {
            same_expanded(file, bytes)?
        } else {
            digest_file(file)? == hash(bytes)
        };
        if !matches {
            return Err(invalid("Conflicting or corrupted replay file identity"));
        }
        return Ok(());
    }
    atomic(file, bytes, gzip)
}
fn atomic(file: &Path, bytes: &[u8], gzip: bool) -> io::Result<()> {
    fs::create_dir_all(
        file.parent()
            .ok_or_else(|| invalid("Missing replay parent"))?,
    )?;
    let mut pending_name = file.as_os_str().to_os_string();
    pending_name.push(".pending");
    let pending = PathBuf::from(pending_name);
    let target = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .open(&pending)?;
    let mut writer = if gzip {
        let mut encoder = GzBuilder::new()
            .mtime(0)
            .write(BufWriter::new(target), Compression::fast());
        encoder.write_all(bytes)?;
        encoder.finish()?
    } else {
        let mut output = BufWriter::new(target);
        output.write_all(bytes)?;
        output
    };
    writer.flush()?;
    writer.get_ref().sync_all()?;
    drop(writer);
    fs::rename(pending, file)
}
impl Store {
    fn event(&self, key: &str) -> PathBuf {
        self.root.join("events").join(hash(key.as_bytes()))
    }
    fn record(&self, key: &str) -> PathBuf {
        if key.contains("_event_") {
            self.event(key).join("event.json")
        } else {
            self.root
                .join("index")
                .join(format!("{}.json", hash(key.as_bytes())))
        }
    }
    fn frame(&self, key: &str) -> PathBuf {
        self.root
            .join("frames")
            .join(format!("{}.json.gz", hash(key.as_bytes())))
    }
    fn report(&self, key: &str, digest: &str) -> io::Result<PathBuf> {
        valid_digest(digest)?;
        Ok(self
            .event(key)
            .join("reports")
            .join(format!("{digest}.json")))
    }
    fn apply(&self, op: u32, key: &str, digest: &str, bytes: &[u8]) -> io::Result<Option<Vec<u8>>> {
        if (8..=13).contains(&op) {
            let mut writer = self.writer.lock().map_err(|_| invalid("Replay writer lock poisoned"))?;
            if writer.is_none() {
                *writer = Some(Writer::new()?);
            }
            let writer = writer.as_ref().unwrap();
            return match op {
                8 => {
                    writer.submit(self.frame(key), bytes, true)?;
                    Ok(Some(Vec::new()))
                }
                9 => {
                    let checksum = hash(bytes);
                    writer.submit(self.report(key, &checksum)?, bytes, false)?;
                    Ok(Some(checksum.into_bytes()))
                }
                10 => Ok(Some(writer.status()?)),
                11 => { writer.retry(); Ok(Some(Vec::new())) }
                12 | 13 => {
                    // Collector-relative directories, never an arbitrary path.
                    if key.is_empty() || key.split('/').any(|s| s.is_empty() || s == "." || s == ".."
                        || s.contains('\\') || s.contains(':'))
                        || !digest.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'_')
                    {
                        return Err(invalid("Invalid collector file identity"));
                    }
                    let compressed;
                    let (bytes, suffix) = if op == 13 {
                        let mut encoder = GzBuilder::new().mtime(0)
                            .write(Vec::new(), Compression::fast());
                        encoder.write_all(bytes)?;
                        compressed = encoder.finish()?;
                        (compressed.as_slice(), ".json.gz")
                    } else {
                        (bytes, ".json")
                    };
                    let name = format!("{digest}{}{suffix}", hash(bytes));
                    writer.submit(self.root.join(key).join(&name), bytes, false)?;
                    Ok(Some(name.into_bytes()))
                }
                _ => unreachable!(),
            };
        }
        let _guard = self
            .gate
            .lock()
            .map_err(|_| invalid("Replay store lock poisoned"))?;
        match op {
            0 => {
                let input = match File::open(self.record(key)) {
                    Ok(input) => input,
                    Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(None),
                    Err(error) => return Err(error),
                };
                let saved = read_bounded(input, LIMIT)?;
                let fields: HashMap<&str, &serde_json::value::RawValue> =
                    serde_json::from_slice(&saved).map_err(|_| invalid("Invalid replay record"))?;
                let actual: String = serde_json::from_str(
                    fields
                        .get("key")
                        .ok_or_else(|| invalid("Missing replay key"))?
                        .get(),
                )
                .map_err(|_| invalid("Invalid replay key"))?;
                if actual != key {
                    return Err(invalid("History key mismatch"));
                }
                Ok(Some(saved))
            }
            1 => {
                atomic(&self.record(key), bytes, false)?;
                Ok(Some(Vec::new()))
            }
            2 => {
                let checksum = hash(bytes);
                let file = self.report(key, &checksum)?;
                if file.try_exists()? {
                    if digest_file(&file)? != checksum {
                        return Err(invalid("Saved report file is corrupted"));
                    }
                } else {
                    atomic(&file, bytes, false)?;
                }
                Ok(Some(checksum.into_bytes()))
            }
            3 => {
                let saved = read_bounded(File::open(self.report(key, digest)?)?, LIMIT)?;
                if hash(&saved) != digest {
                    return Err(invalid("Saved report checksum mismatch"));
                }
                Ok(Some(saved))
            }
            4 => {
                let file = self.frame(key);
                if file.try_exists()? {
                    // Old Dart gzip and native gzip need not have identical headers
                    // or deflate bytes. Preserve the file if its full JSON matches.
                    if !same_expanded(&file, bytes)? {
                        return Err(invalid("Conflicting station frame identity"));
                    }
                } else {
                    atomic(&file, bytes, true)?;
                }
                Ok(Some(Vec::new()))
            }
            5 => Ok(Some(read_bounded(
                MultiGzDecoder::new(File::open(self.frame(key))?),
                LIMIT,
            )?)),
            6 | 7 => {
                let file = if op == 7 {
                    self.frame(key)
                } else {
                    self.record(key)
                };
                let result = if op == 6 && key.contains("_event_") {
                    fs::remove_dir_all(self.event(key))
                } else {
                    fs::remove_file(file)
                };
                match result {
                    Ok(()) => (),
                    Err(error) if error.kind() == io::ErrorKind::NotFound => (),
                    Err(error) => return Err(error),
                }
                Ok(Some(Vec::new()))
            }
            _ => Err(invalid("Unknown replay file operation")),
        }
    }
}
fn reply(code: i32, bytes: Vec<u8>) -> *mut c_void {
    RESULTS.fetch_add(1, Ordering::Relaxed);
    Box::into_raw(Box::new(Reply { code, bytes })).cast()
}
unsafe fn input<'a>(data: *const u8, len: usize, limit: usize) -> io::Result<&'a [u8]> {
    if len > limit || (data.is_null() && len != 0) {
        return Err(invalid("Invalid replay input size"));
    }
    if len == 0 {
        return Ok(&[]);
    }
    Ok(unsafe { std::slice::from_raw_parts(data, len) })
}
#[no_mangle]
pub unsafe extern "C" fn rq_replay_files_open(data: *const u8, len: usize) -> *mut c_void {
    let result = std::panic::catch_unwind(|| {
        let root = std::str::from_utf8(unsafe { input(data, len, 65536) }.ok()?).ok()?;
        let root = PathBuf::from(root);
        if !root.is_absolute() {
            return None;
        }
        SESSIONS.fetch_add(1, Ordering::Relaxed);
        Some(
            Box::into_raw(Box::new(Store {
                root,
                gate: Mutex::new(()),
                writer: Mutex::new(None),
            }))
            .cast(),
        )
    });
    result.ok().flatten().unwrap_or(ptr::null_mut())
}
#[no_mangle]
pub unsafe extern "C" fn rq_replay_files_apply(
    owner: *const c_void,
    op: u32,
    key: *const u8,
    key_len: usize,
    digest: *const u8,
    digest_len: usize,
    data: *const u8,
    len: usize,
) -> *mut c_void {
    CALLS.fetch_add(1, Ordering::Relaxed);
    let result = std::panic::catch_unwind(|| -> io::Result<Option<Vec<u8>>> {
        if owner.is_null() {
            return Err(invalid("Closed replay store"));
        }
        let key = std::str::from_utf8(unsafe { input(key, key_len, 65536)? })
            .map_err(|_| invalid("Invalid UTF-8 replay key"))?;
        let digest = std::str::from_utf8(unsafe { input(digest, digest_len, 64)? })
            .map_err(|_| invalid("Invalid report digest"))?;
        let data = unsafe { input(data, len, LIMIT)? };
        unsafe { &*owner.cast::<Store>() }.apply(op, key, digest, data)
    });
    match result {
        Ok(Ok(Some(bytes))) => reply(0, bytes),
        Ok(Ok(None)) => reply(1, Vec::new()),
        Ok(Err(error)) => reply(
            if error.kind() == io::ErrorKind::InvalidData {
                2
            } else {
                3
            },
            error.to_string().into_bytes(),
        ),
        Err(_) => reply(9, b"Native replay file operation panicked".to_vec()),
    }
}
#[no_mangle]
pub unsafe extern "C" fn rq_replay_files_result(
    owner: *const c_void,
    len: *mut usize,
    code: *mut i32,
) -> *const u8 {
    if owner.is_null() || len.is_null() || code.is_null() {
        return ptr::null();
    }
    let result = unsafe { &*owner.cast::<Reply>() };
    unsafe {
        *len = result.bytes.len();
        *code = result.code;
    }
    result.bytes.as_ptr()
}
#[no_mangle]
pub unsafe extern "C" fn rq_replay_files_result_free(owner: *mut c_void) {
    if !owner.is_null() {
        drop(unsafe { Box::from_raw(owner.cast::<Reply>()) });
    }
}
#[no_mangle]
pub unsafe extern "C" fn rq_replay_files_close(owner: *mut c_void) {
    if !owner.is_null() {
        drop(unsafe { Box::from_raw(owner.cast::<Store>()) });
    }
}
#[no_mangle]
pub extern "C" fn rq_replay_files_sessions() -> usize {
    SESSIONS.load(Ordering::Relaxed)
}
#[no_mangle]
pub extern "C" fn rq_replay_files_results() -> usize {
    RESULTS.load(Ordering::Relaxed)
}
#[no_mangle]
pub extern "C" fn rq_replay_files_calls() -> usize {
    CALLS.load(Ordering::Relaxed)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn temporary() -> PathBuf {
        use std::time::{SystemTime, UNIX_EPOCH};
        std::env::temp_dir().join(format!(
            "rq-native-files-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ))
    }
    fn store(root: PathBuf) -> Store {
        SESSIONS.fetch_add(1, Ordering::Relaxed);
        Store {
            root,
            gate: Mutex::new(()),
            writer: Mutex::new(None),
        }
    }
    #[test]
    fn exact_json_and_immutable_reports() {
        let root = temporary();
        let store = store(root.clone());
        // Original retained report document, unchanged; this is a storage test.
        let original = include_bytes!("../../../test/fixtures/history_replay/cwa_1150074.rqreplay");
        let digest = String::from_utf8(
            store
                .apply(2, "ns_event_中文日本語", "", original)
                .unwrap()
                .unwrap(),
        )
        .unwrap();
        assert_eq!(
            store
                .apply(3, "ns_event_中文日本語", &digest, &[])
                .unwrap()
                .unwrap(),
            original
        );
        store.apply(2, "ns_event_中文日本語", "", original).unwrap();
        fs::write(
            store.report("ns_event_中文日本語", &digest).unwrap(),
            b"corrupt",
        )
        .unwrap();
        assert!(store.apply(3, "ns_event_中文日本語", &digest, &[]).is_err());
        assert!(store.apply(2, "ns_event_中文日本語", "", original).is_err());
        assert!(store.report("ns_event_中文日本語", "../outside").is_err());
        store.apply(6, "ns_event_中文日本語", "", &[]).unwrap();
        fs::remove_dir_all(root).unwrap();
    }
    #[test]
    fn frames_stream_and_detect_conflicts_and_limits() {
        let root = temporary();
        let store = store(root.clone());
        // Explicit JSON serialization values, not earthquake observations.
        let bytes = "{\"中文\":\"日本語\",\"int\":9223372036854775807,\"float\":-0.0}".as_bytes();
        store.apply(4, "frame", "", bytes).unwrap();
        let before = fs::read(store.frame("frame")).unwrap();
        store.apply(4, "frame", "", bytes).unwrap();
        assert_eq!(fs::read(store.frame("frame")).unwrap(), before);
        assert_eq!(store.apply(5, "frame", "", &[]).unwrap().unwrap(), bytes);
        assert!(store.apply(4, "frame", "", b"{}").is_err());
        assert!(read_bounded(MultiGzDecoder::new(before.as_slice()), 3).is_err());
        store.apply(7, "frame", "", &[]).unwrap();
        fs::remove_dir_all(root).unwrap();
    }
    #[test]
    fn missing_records_and_failed_commits_do_not_replace_committed_data() {
        let root = temporary();
        let store = store(root.clone());
        assert!(store.apply(0, "ns", "", &[]).unwrap().is_none());
        store
            .apply(1, "ns", "", br#"{"key":"ns","value":1}"#)
            .unwrap();
        let file = store.record("ns");
        fs::create_dir(file.with_extension("json.pending")).unwrap();
        assert!(store
            .apply(1, "ns", "", br#"{"key":"ns","value":2}"#)
            .is_err());
        assert_eq!(
            store.apply(0, "ns", "", &[]).unwrap().unwrap(),
            br#"{"key":"ns","value":1}"#
        );
        fs::remove_dir(file.with_extension("json.pending")).unwrap();
        store.apply(1, "ns", "", br#"{"key":"other"}"#).unwrap();
        assert!(store.apply(0, "ns", "", &[]).is_err());
        fs::remove_dir_all(root).unwrap();
    }
    fn wait(writer: &Writer) {
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(10);
        loop {
            let status: serde_json::Value = serde_json::from_slice(&writer.status().unwrap()).unwrap();
            if status["pending"] == 0 { break; }
            assert!(std::time::Instant::now() < deadline);
            std::thread::sleep(std::time::Duration::from_millis(1));
        }
    }
    #[test]
    fn live_writer_is_byte_bounded_and_close_drains_every_file() {
        let root = temporary();
        let writer = Writer::new().unwrap();
        // Queue mechanics fixture, not earthquake/station data.
        let bytes = vec![b'x'; 1024 * 1024];
        for n in 0..40 {
            writer.submit(root.join(format!("{n}.json")), &bytes, false).unwrap();
        }
        wait(&writer);
        let q = writer.state.0.lock().unwrap();
        assert!(q.peak_bytes <= QUEUE_LIMIT);
        assert_eq!(q.bytes, 0);
        assert_eq!(q.count, 0);
        drop(q);
        let original = include_bytes!("../../../test/fixtures/history_replay/cwa_1150074.rqreplay");
        writer.submit(root.join("original.json"), original, false).unwrap();
        drop(writer); // must join and drain, not abandon pending originals
        assert_eq!(fs::read(root.join("original.json")).unwrap(), original);
        assert_eq!(fs::read_dir(&root).unwrap().count(), 41);
        fs::remove_dir_all(root).unwrap();
    }
    #[test]
    fn failed_live_write_stays_owned_until_explicit_retry() {
        let root = temporary();
        fs::create_dir_all(root.join("original.json.pending")).unwrap();
        let writer = Writer::new().unwrap();
        let original = include_bytes!("../../../test/fixtures/history_replay/cwa_1150074.rqreplay");
        writer.submit(root.join("original.json"), original, false).unwrap();
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(10);
        while writer.status().is_ok() {
            assert!(std::time::Instant::now() < deadline);
            std::thread::sleep(std::time::Duration::from_millis(1));
        }
        {
            let q = writer.state.0.lock().unwrap();
            assert_eq!(q.bytes, original.len());
            assert_eq!(q.count, 1);
        }
        assert!(writer.submit(root.join("later.json"), original, false).is_err());
        fs::remove_dir(root.join("original.json.pending")).unwrap();
        writer.retry();
        wait(&writer);
        assert_eq!(fs::read(root.join("original.json")).unwrap(), original);
        drop(writer);
        fs::remove_dir_all(root).unwrap();
    }
}
