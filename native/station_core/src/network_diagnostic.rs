//! Opt-in diagnostic capture, configured only by the dedicated Debug entrypoint.
//! Payloads are the original bytes; never use this file as processed source data.
use base64::{engine::general_purpose::STANDARD, Engine};
use serde_json::{json, Value};
use std::{
    ffi::CStr,
    fs::File,
    io::{BufWriter, Write},
    path::Path,
    sync::{
        atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering},
        mpsc::{self, SyncSender},
        Mutex, OnceLock,
    },
    time::{SystemTime, UNIX_EPOCH},
};

enum Message {
    Data(Vec<u8>, usize),
    Flush(mpsc::Sender<u64>),
}
struct Capture {
    sender: SyncSender<Message>,
    path: String,
    accepting: Mutex<bool>,
}
static ENABLED: AtomicBool = AtomicBool::new(false);
static CAPTURE: OnceLock<Capture> = OnceLock::new();
static QUEUED: AtomicUsize = AtomicUsize::new(0);
static LOST: AtomicU64 = AtomicU64::new(0);
static WRITTEN: AtomicU64 = AtomicU64::new(0);
static ERRORS: AtomicU64 = AtomicU64::new(0);
static SEQUENCE: AtomicU64 = AtomicU64::new(0);
static START: Mutex<()> = Mutex::new(());
const BUDGET: usize = 32 * 1024 * 1024;
const FILE_LIMIT: u64 = 1024 * 1024 * 1024;

pub(crate) fn active() -> bool {
    ENABLED.load(Ordering::Relaxed)
}
pub(crate) fn record(transport: &str, id: u64, event: &str, details: Value, bytes: &[u8]) {
    let Some(capture) = CAPTURE.get() else {
        return;
    };
    if !active() {
        return;
    }
    // Reserve before allocating base64, bounding diagnostic backlog memory.
    let charge = bytes
        .len()
        .saturating_mul(2)
        .saturating_add(details.to_string().len())
        .saturating_add(1024);
    if QUEUED
        .fetch_add(charge, Ordering::Relaxed)
        .saturating_add(charge)
        > BUDGET
    {
        QUEUED.fetch_sub(charge, Ordering::Relaxed);
        LOST.fetch_add(1, Ordering::Relaxed);
        return;
    }
    let row = json!({"timeUnixMs":SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_millis(),"sequence":SEQUENCE.fetch_add(1,Ordering::Relaxed),"pid":std::process::id(),"transport":transport,"connectionId":id,"event":event,"details":details,"bytes":bytes.len(),"base64":STANDARD.encode(bytes),"queueCharge":charge});
    let mut line = serde_json::to_vec(&row).unwrap_or_default();
    line.push(b'\n');
    let accepting = capture.accepting.lock().unwrap();
    if !*accepting {
        QUEUED.fetch_sub(charge, Ordering::Relaxed);
        return;
    }
    if capture
        .sender
        .try_send(Message::Data(line, charge))
        .is_err()
    {
        QUEUED.fetch_sub(charge, Ordering::Relaxed);
        LOST.fetch_add(1, Ordering::Relaxed);
    }
}

#[no_mangle]
pub unsafe extern "C" fn rq_network_diagnostic_start(path: *const u8) -> u32 {
    if path.is_null() {
        return 0;
    }
    let Ok(path) = unsafe { CStr::from_ptr(path.cast()) }.to_str() else {
        return 0;
    };
    let _guard = START.lock().unwrap();
    if let Some(c) = CAPTURE.get() {
        return u32::from(c.path == path);
    }
    if !Path::new(path).is_absolute() {
        return 0;
    }
    let Ok(file) = File::create(path) else {
        return 0;
    };
    let status_path = format!("{path}.status.json");
    let (sender, receiver) = mpsc::sync_channel::<Message>(128);
    let started=std::thread::Builder::new().name("rq-network-capture".into()).stack_size(256*1024).spawn(move || {
        let mut out=BufWriter::new(file);let mut size=0u64;let mut last_flush=std::time::Instant::now();
        loop {
            match receiver.recv_timeout(std::time::Duration::from_millis(250)) {
                Ok(Message::Data(line,charge)) => {
                    if size+line.len() as u64 > FILE_LIMIT { LOST.fetch_add(1,Ordering::Relaxed); }
                    else if out.write_all(&line).is_err() { ERRORS.fetch_add(1,Ordering::Relaxed); }
                    else { size+=line.len() as u64;WRITTEN.fetch_add(1,Ordering::Relaxed); }
                    QUEUED.fetch_sub(charge,Ordering::Relaxed);
                },
                Ok(Message::Flush(reply)) => {
                    if out.flush().is_ok(){let _=reply.send(size);}else{ERRORS.fetch_add(1,Ordering::Relaxed);let _=reply.send(0);}
                },
                Err(mpsc::RecvTimeoutError::Disconnected) => break,
                Err(mpsc::RecvTimeoutError::Timeout) => {}
            }
            if last_flush.elapsed()>=std::time::Duration::from_millis(250) {
                    last_flush=std::time::Instant::now();
                    if out.flush().is_err(){ERRORS.fetch_add(1,Ordering::Relaxed);}
                    let status=json!({"written":WRITTEN.load(Ordering::Relaxed),"lost":LOST.load(Ordering::Relaxed),"writeErrors":ERRORS.load(Ordering::Relaxed),"queuedBytes":QUEUED.load(Ordering::Relaxed),"fileBytes":size,"limitBytes":FILE_LIMIT});
                    let staging=format!("{status_path}.pending");
                    if std::fs::write(&staging,status.to_string()).and_then(|_|std::fs::rename(&staging,&status_path)).is_err(){ERRORS.fetch_add(1,Ordering::Relaxed);}
            }
        }
        let _=out.flush();
    });
    if started.is_err() {
        return 0;
    }
    if CAPTURE
        .set(Capture {
            sender,
            path: path.into(),
            accepting: Mutex::new(true),
        })
        .is_err()
    {
        return 0;
    }
    ENABLED.store(true, Ordering::Relaxed);
    record(
        "native",
        0,
        "capture_started",
        json!({"abi":1,"queueBudgetBytes":BUDGET,"fileLimitBytes":FILE_LIMIT,"rawCredentialsPresent":true}),
        &[],
    );
    1
}

#[no_mangle]
pub unsafe extern "C" fn rq_network_diagnostic_record(
    metadata: *const u8,
    bytes: *const u8,
    length: usize,
) {
    if !active()
        || metadata.is_null()
        || (length != 0 && bytes.is_null())
        || length > 64 * 1024 * 1024
    {
        return;
    }
    let Ok(metadata) = unsafe { CStr::from_ptr(metadata.cast()) }.to_str() else {
        return;
    };
    let Ok(v) = serde_json::from_str::<Value>(metadata) else {
        return;
    };
    let payload = if length == 0 {
        &[]
    } else {
        unsafe { std::slice::from_raw_parts(bytes, length) }
    };
    record(
        v["transport"].as_str().unwrap_or("dart"),
        v["connectionId"].as_u64().unwrap_or(0),
        v["event"].as_str().unwrap_or("event"),
        v["details"].clone(),
        payload,
    );
}

#[no_mangle]
pub extern "C" fn rq_network_diagnostic_flush() -> u64 {
    let Some(capture) = CAPTURE.get() else {
        return 0;
    };
    let (tx, rx) = mpsc::channel();
    if capture.sender.try_send(Message::Flush(tx)).is_err() {
        return 0;
    }
    rx.recv_timeout(std::time::Duration::from_secs(2))
        .unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn rq_network_diagnostic_stop() -> u64 {
    let Some(capture) = CAPTURE.get() else {
        return 0;
    };
    record("native", 0, "capture_stop_requested", json!({}), &[]);
    {
        let mut accepting = capture.accepting.lock().unwrap();
        *accepting = false;
        ENABLED.store(false, Ordering::Relaxed);
    }
    // No queued producer can append after this barrier. Existing network
    // sessions keep running; only the diagnostic observer is disabled.
    rq_network_diagnostic_flush()
}
