//! Android supplies its private directories through path_provider before feeds
//! start. Never use Windows environment variables or Android's unwritable /tmp.
use std::{ffi::CStr, path::PathBuf, sync::OnceLock};

static DIRECTORIES: OnceLock<(PathBuf, PathBuf)> = OnceLock::new();

#[no_mangle]
pub unsafe extern "C" fn rq_android_initialize(support: *const u8, cache: *const u8) -> u32 {
    if support.is_null() || cache.is_null() {
        return 1;
    }
    let read = |p| unsafe { CStr::from_ptr(p) }.to_str().map(PathBuf::from);
    let (Ok(support), Ok(cache)) = (read(support.cast()), read(cache.cast())) else {
        return 1;
    };
    if !support.is_absolute() || !cache.is_absolute() {
        return 1;
    }
    let dirs = (support, cache);
    if let Some(current) = DIRECTORIES.get() {
        return u32::from(current != &dirs);
    }
    if std::fs::create_dir_all(&dirs.0)
        .and_then(|_| std::fs::create_dir_all(&dirs.1))
        .is_err()
    {
        return 2;
    }
    match DIRECTORIES.set(dirs.clone()) {
        Ok(()) => 0,
        Err(_) => u32::from(DIRECTORIES.get() != Some(&dirs)),
    }
}

pub fn support() -> std::io::Result<&'static PathBuf> {
    DIRECTORIES
        .get()
        .map(|d| &d.0)
        .ok_or_else(|| std::io::Error::other("Android native directories not initialized"))
}
pub fn cache() -> std::io::Result<&'static PathBuf> {
    DIRECTORIES
        .get()
        .map(|d| &d.1)
        .ok_or_else(|| std::io::Error::other("Android native directories not initialized"))
}

pub fn local_epoch(y: i64, m: i64, d: i64, h: i64, mi: i64, s: i64, ms: i64) -> Option<i64> {
    let mut local: libc::tm = unsafe { std::mem::zeroed() };
    local.tm_year = i32::try_from(y - 1900).ok()?;
    local.tm_mon = i32::try_from(m - 1).ok()?;
    local.tm_mday = i32::try_from(d).ok()?;
    local.tm_hour = i32::try_from(h).ok()?;
    local.tm_min = i32::try_from(mi).ok()?;
    local.tm_sec = i32::try_from(s).ok()?;
    local.tm_isdst = -1;
    let seconds = unsafe { libc::mktime(&mut local) };
    (seconds != -1).then_some(seconds as i64 * 1000 + ms)
}

pub fn local_iso() -> String {
    let time = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default();
    let seconds = time.as_secs() as libc::time_t;
    let mut local: libc::tm = unsafe { std::mem::zeroed() };
    assert!(!unsafe { libc::localtime_r(&seconds, &mut local) }.is_null());
    let micros = time.subsec_micros();
    let base = format!(
        "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}.{:03}",
        local.tm_year + 1900,
        local.tm_mon + 1,
        local.tm_mday,
        local.tm_hour,
        local.tm_min,
        local.tm_sec,
        micros / 1000
    );
    if micros % 1000 == 0 {
        base
    } else {
        format!("{base}{:03}", micros % 1000)
    }
}
