//! Same per-token/per-endpoint stop records used by Dart, including its file lock.
use serde_json::{json, Map, Value};
use sha2::{Digest, Sha256};
use std::{
    fs::{self, OpenOptions},
    io::{self, Write},
    path::{Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
};
#[cfg(test)]
const ENDPOINT: &str = "wss://api.beecld.com/ws/kma_station";
static NEXT: AtomicU64 = AtomicU64::new(1);
#[cfg(windows)]
fn state_path() -> io::Result<PathBuf> {
    let root = std::env::var_os("LOCALAPPDATA")
        .ok_or_else(|| io::Error::other("retry state directory unavailable"))?;
    Ok(PathBuf::from(root)
        .join("RhythmQuake")
        .join("whews_auth_block.json"))
}
#[cfg(target_os = "android")]
fn state_path() -> io::Result<PathBuf> {
    Ok(crate::android_platform::support()?.join("whews_auth_block.json"))
}
#[cfg(target_os = "android")]
fn android_lock(file: &fs::File, kind: i32) -> io::Result<()> {
    use std::os::fd::AsRawFd;
    // Dart File.lock uses POSIX record locks. flock (including std File::lock
    // on Unix) would not coordinate with the existing settings-side store.
    let mut lock: libc::flock = unsafe { std::mem::zeroed() };
    lock.l_type = kind as _;
    lock.l_whence = libc::SEEK_SET as _;
    if unsafe { libc::fcntl(file.as_raw_fd(), libc::F_SETLKW, &lock) } == -1 {
        Err(io::Error::last_os_error())
    } else {
        Ok(())
    }
}
fn update<T>(
    path: &Path,
    token: &str,
    action: impl FnOnce(&mut Map<String, Value>) -> io::Result<T>,
) -> io::Result<T> {
    fs::create_dir_all(
        path.parent()
            .ok_or_else(|| io::Error::other("missing directory"))?,
    )?;
    let mut lock = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(format!("{}.lock", path.display()))?;
    #[cfg(windows)]
    lock.try_lock().map_err(io::Error::other)?;
    #[cfg(target_os = "android")]
    android_lock(&lock, libc::F_WRLCK)?;
    let result = (|| {
        let mut records = if path.exists() {
            serde_json::from_slice::<Map<String, Value>>(&fs::read(path)?)?
        } else {
            if lock.metadata()?.len() != 0 {
                return Err(io::Error::other("retry state missing"));
            }
            Map::new()
        };
        let key = format!("{:x}", Sha256::digest(token.trim().as_bytes()));
        let record = records
            .entry(key)
            .or_insert_with(|| json!({}))
            .as_object_mut()
            .ok_or_else(|| io::Error::other("invalid retry state"))?;
        let result = action(record)?;
        let pending = path.with_extension(format!(
            "{}.{}.pending",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        let commit = (|| {
            let mut file = fs::File::create(&pending)?;
            file.write_all(&serde_json::to_vec(&records)?)?;
            file.sync_all()?;
            drop(file);
            fs::rename(&pending, path)
        })();
        if pending.exists() {
            let _ = fs::remove_file(&pending);
        }
        commit?;
        if lock.metadata()?.len() == 0 {
            lock.write_all(&[1])?;
            lock.sync_all()?;
        }
        Ok(result)
    })();
    #[cfg(windows)]
    lock.unlock()?;
    #[cfg(target_os = "android")]
    android_lock(&lock, libc::F_UNLCK)?;
    result
}
fn blocked_endpoint_at(path: &Path, token: &str, endpoint: &str) -> io::Result<Option<u32>> {
    update(path, token, |record| {
        let Some(state) = record.get("paths").and_then(|paths| paths.get(endpoint)) else {
            return Ok(None);
        };
        if state["blocked"] == true {
            Ok(Some(
                state["code"]
                    .as_u64()
                    .ok_or_else(|| io::Error::other("invalid block code"))? as u32,
            ))
        } else {
            Ok(None)
        }
    })
}
fn block_endpoint_at(path: &Path, token: &str, endpoint: &str, code: u32) -> io::Result<()> {
    update(path, token, |record| {
        let paths = record
            .entry("paths")
            .or_insert_with(|| json!({}))
            .as_object_mut()
            .ok_or_else(|| io::Error::other("invalid paths"))?;
        paths.insert(endpoint.into(), json!({"blocked":true,"code":code}));
        Ok(())
    })
}
pub fn blocked_endpoint(token: &str, endpoint: &str) -> io::Result<Option<u32>> {
    blocked_endpoint_at(&state_path()?, token, endpoint)
}
pub fn block_endpoint(token: &str, endpoint: &str, code: u32) -> io::Result<()> {
    block_endpoint_at(&state_path()?, token, endpoint, code)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn blocked_at(path: &Path, token: &str) -> io::Result<Option<u32>> {
        blocked_endpoint_at(path, token, ENDPOINT)
    }
    fn block_at(path: &Path, token: &str, code: u32) -> io::Result<()> {
        block_endpoint_at(path, token, ENDPOINT, code)
    }
    #[test]
    fn native_stop_survives_recreation_and_matches_dart_record_format() {
        let directory = std::env::temp_dir().join(format!(
            "rq-whews-block-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        let path = directory.join("state.json");
        assert_eq!(blocked_at(&path, "wat_controlled").unwrap(), None);
        block_at(&path, "wat_controlled", 4401).unwrap();
        assert_eq!(blocked_at(&path, "wat_controlled").unwrap(), Some(4401));
        assert_eq!(blocked_at(&path, "wat_other").unwrap(), None);
        let backup = "wss://api.2v8.cn/ws/kma_station";
        assert_eq!(blocked_endpoint_at(&path, "wat_controlled", backup).unwrap(), None);
        block_endpoint_at(&path, "wat_controlled", backup, 4403).unwrap();
        assert_eq!(blocked_endpoint_at(&path, "wat_controlled", backup).unwrap(), Some(4403));
        assert_eq!(blocked_at(&path, "wat_controlled").unwrap(), Some(4401));
        let value = fs::read_to_string(&path).unwrap();
        assert!(!value.contains("wat_controlled"));
        let key = format!("{:x}", Sha256::digest(b"wat_controlled"));
        assert_eq!(
            serde_json::from_str::<Value>(&value).unwrap()[&key]["paths"][ENDPOINT]["code"],
            4401
        );
        // Explicit Dart-style save clears just this token's record.
        update(&path, "wat_controlled", |record| {
            record.clear();
            Ok(())
        })
        .unwrap();
        assert_eq!(blocked_at(&path, "wat_controlled").unwrap(), None);
        fs::write(&path, b"invalid controlled metadata").unwrap();
        assert!(blocked_at(&path, "wat_controlled").is_err());
        assert_eq!(fs::read(&path).unwrap(), b"invalid controlled metadata");
        fs::remove_dir_all(directory).unwrap();
    }
}
