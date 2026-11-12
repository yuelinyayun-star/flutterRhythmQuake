//! Opt-in rolling field log for cloud/field diagnostic builds.
//!
//! The Dart entrypoint enables it only when the build was made with
//! `--dart-define=RQ_FIELD_LOG=true`. Lines are plain text written by one
//! native thread, so they keep flowing while the Dart isolate or the raster
//! thread is stalled, and every line is flushed to the OS before the next one.
use std::{
    ffi::CStr,
    fs::{self, File, OpenOptions},
    io::Write,
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicU64, Ordering},
        mpsc::{self, Receiver, SyncSender},
        Mutex, OnceLock,
    },
};

/// One segment never exceeds this size (a single longer line is still kept whole).
const SEGMENT_BYTES: u64 = 5 * 1024 * 1024;
/// `field.log`, `field.log.1`, `field.log.2`, `field.log.3`: 20 MB at most.
const SEGMENTS: usize = 4;
const QUEUE_LINES: usize = 4096;
const MAX_LINE_BYTES: usize = 64 * 1024;

struct FieldLog {
    sender: SyncSender<Vec<u8>>,
    path: String,
}

static LOG: OnceLock<FieldLog> = OnceLock::new();
static START: Mutex<()> = Mutex::new(());
static LOST: AtomicU64 = AtomicU64::new(0);
static ERRORS: AtomicU64 = AtomicU64::new(0);
static WRITTEN: AtomicU64 = AtomicU64::new(0);

fn segment(base: &Path, index: usize) -> PathBuf {
    if index == 0 {
        return base.to_path_buf();
    }
    let mut name = base.as_os_str().to_owned();
    name.push(format!(".{index}"));
    PathBuf::from(name)
}

/// Shifts `base` -> `base.1` -> ... and drops the oldest. The caller must have
/// closed its handle on `base` first (Windows cannot rename an open file).
fn rotate(base: &Path) {
    let _ = fs::remove_file(segment(base, SEGMENTS - 1));
    for index in (0..SEGMENTS - 1).rev() {
        let from = segment(base, index);
        if from.exists() {
            let _ = fs::rename(&from, segment(base, index + 1));
        }
    }
}

fn open(base: &Path) -> Option<(File, u64)> {
    let file = OpenOptions::new()
        .create(true)
        .append(true)
        .open(base)
        .ok()?;
    let size = file.metadata().map(|m| m.len()).unwrap_or(0);
    Some((file, size))
}

fn run_writer(base: PathBuf, receiver: Receiver<Vec<u8>>, segment_bytes: u64) {
    let mut current = open(&base);
    for line in receiver {
        let length = line.len() as u64;
        if matches!(&current, Some((_, size)) if *size > 0 && *size + length > segment_bytes) {
            drop(current.take());
            rotate(&base);
            current = open(&base);
        }
        if current.is_none() {
            current = open(&base);
        }
        let Some((file, size)) = current.as_mut() else {
            ERRORS.fetch_add(1, Ordering::Relaxed);
            continue;
        };
        match file.write_all(&line).and_then(|_| file.flush()) {
            Ok(()) => {
                *size += length;
                WRITTEN.fetch_add(1, Ordering::Relaxed);
            }
            Err(_) => {
                ERRORS.fetch_add(1, Ordering::Relaxed);
                current = None;
            }
        }
    }
}

/// Starts the writer for the absolute log file `path`. Returns 1 on success or
/// when the same path is already active, otherwise 0.
///
/// # Safety
/// `path` must be null or a valid NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn rq_field_log_start(path: *const u8) -> u32 {
    if path.is_null() {
        return 0;
    }
    let Ok(path) = unsafe { CStr::from_ptr(path.cast()) }.to_str() else {
        return 0;
    };
    let _guard = START.lock().unwrap();
    if let Some(log) = LOG.get() {
        return u32::from(log.path == path);
    }
    let base = PathBuf::from(path);
    if !base.is_absolute() {
        return 0;
    }
    if let Some(parent) = base.parent() {
        if fs::create_dir_all(parent).is_err() {
            return 0;
        }
    }
    if open(&base).is_none() {
        return 0;
    }
    let (sender, receiver) = mpsc::sync_channel::<Vec<u8>>(QUEUE_LINES);
    let writer_base = base.clone();
    if std::thread::Builder::new()
        .name("rq-field-log".into())
        .spawn(move || run_writer(writer_base, receiver, SEGMENT_BYTES))
        .is_err()
    {
        return 0;
    }
    let _ = LOG.set(FieldLog {
        sender,
        path: path.to_owned(),
    });
    1
}

/// Queues one UTF-8 line (a trailing newline is added). Returns 1 when queued;
/// 0 when the log is not started, the line is empty/too long, or the queue is
/// full (counted by `rq_field_log_lost`).
///
/// # Safety
/// `data` must point to `length` readable bytes.
#[no_mangle]
pub unsafe extern "C" fn rq_field_log_write(data: *const u8, length: usize) -> u32 {
    let Some(log) = LOG.get() else {
        return 0;
    };
    if data.is_null() || length == 0 || length > MAX_LINE_BYTES {
        return 0;
    }
    let mut line = unsafe { std::slice::from_raw_parts(data, length) }.to_vec();
    if line.last() != Some(&b'\n') {
        line.push(b'\n');
    }
    if log.sender.try_send(line).is_err() {
        LOST.fetch_add(1, Ordering::Relaxed);
        return 0;
    }
    1
}

/// Lines dropped because the writer queue was full.
#[no_mangle]
pub extern "C" fn rq_field_log_lost() -> u64 {
    LOST.load(Ordering::Relaxed)
}

/// Lines the writer failed to persist.
#[no_mangle]
pub extern "C" fn rq_field_log_errors() -> u64 {
    ERRORS.load(Ordering::Relaxed)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rotates_by_size_and_keeps_newest_segments() {
        let dir = std::env::temp_dir().join(format!("rq_field_log_test_{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        let base = dir.join("field.log");
        let (sender, receiver) = mpsc::sync_channel::<Vec<u8>>(64);
        let writer_base = base.clone();
        let handle = std::thread::spawn(move || run_writer(writer_base, receiver, 100));
        for index in 0..40u32 {
            sender
                .send(format!("{index:04} {}\n", "x".repeat(40)).into_bytes())
                .unwrap();
        }
        drop(sender);
        handle.join().unwrap();

        let mut names: Vec<String> = fs::read_dir(&dir)
            .unwrap()
            .map(|e| e.unwrap().file_name().to_string_lossy().into_owned())
            .collect();
        names.sort();
        assert_eq!(
            names,
            vec!["field.log", "field.log.1", "field.log.2", "field.log.3"]
        );
        for name in &names {
            assert!(fs::metadata(dir.join(name)).unwrap().len() <= 100);
        }
        let newest = fs::read_to_string(&base).unwrap();
        assert!(newest.contains("0039 "), "newest line must be in field.log");
        let all: String = names
            .iter()
            .map(|n| fs::read_to_string(dir.join(n)).unwrap())
            .collect();
        assert!(!all.contains("0000 "), "oldest lines must have been dropped");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn rejects_relative_path_and_unstarted_write() {
        let relative = b"relative.log\0";
        assert_eq!(unsafe { rq_field_log_start(relative.as_ptr()) }, 0);
        assert_eq!(unsafe { rq_field_log_write(b"x".as_ptr(), 1) }, 0);
        assert_eq!(unsafe { rq_field_log_start(std::ptr::null()) }, 0);
    }
}
