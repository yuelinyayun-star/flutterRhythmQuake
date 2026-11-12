//! WHEWS routing and FAN-compatible retry decisions; no credentials or frames.
use serde_json::{json, Value};
use std::sync::atomic::{AtomicUsize, Ordering};

pub const PRIMARY: &str = "api.beecld.com";
pub const BACKUP: &str = "api.2v8.cn";
static OUTPUTS: AtomicUsize = AtomicUsize::new(0);

pub fn host(index: usize) -> &'static str {
    if index % 2 == 0 { PRIMARY } else { BACKUP }
}
pub fn terminal(code: u32) -> bool {
    matches!(code, 401 | 403 | 404 | 429 | 4401 | 4403 | 4008 | 1008)
}
pub fn retry(index: usize, seconds: u64, count: usize, code: u32) -> Option<(usize, u64, u64)> {
    if terminal(code) { return None; }
    let seconds = seconds.clamp(3, 300);
    let next = if seconds >= 30 && count > 1 { (index + 1) % count } else { index };
    let delay = if code == 4503 { seconds.max(15) } else { seconds };
    Some((next, delay, (delay * 2).min(300)))
}
fn execute(v: &Value) -> Result<Value, String> {
    match v["op"].as_str().unwrap_or("") {
        "endpoints" => {
            let original = v["url"].as_str().ok_or("Invalid URL")?;
            // Only the shared feeds currently consumed by this application.
            // CEA-only routes and arbitrary/custom endpoints remain untouched.
            let prefix = format!("wss://{PRIMARY}");
            let shared = original.strip_prefix(&prefix).is_some_and(|suffix| {
                let path = suffix.split('?').next().unwrap_or("");
                matches!(path, "/ws/all" | "/ws/nied" | "/ws/snet" | "/ws/kma_station")
            });
            Ok(if shared { json!([original, original.replacen(PRIMARY, BACKUP, 1)]) }
                else { json!([original]) })
        }
        "retry" => {
            let index = v["index"].as_u64().ok_or("Invalid index")? as usize;
            let count = v["count"].as_u64().filter(|n| *n > 0).ok_or("Invalid endpoint count")? as usize;
            if index >= count { return Err("Invalid endpoint index".into()); }
            let seconds = v["seconds"].as_u64().ok_or("Invalid delay")?;
            let code = v["code"].as_u64().unwrap_or(0) as u32;
            Ok(match retry(index, seconds, count, code) {
                Some((index, delay, next)) => json!({"index":index,"delay":delay,"next":next}),
                None => Value::Null,
            })
        }
        _ => Err("Unknown WHEWS connection operation".into()),
    }
}
#[no_mangle]
pub unsafe extern "C" fn rq_whews_connection_prepare(input: *const u8, len: usize, size: *mut usize) -> *mut u8 {
    if input.is_null() || size.is_null() || len > 16384 { return std::ptr::null_mut(); }
    unsafe { *size = 0; }
    std::panic::catch_unwind(|| {
        let result = serde_json::from_slice::<Value>(unsafe { std::slice::from_raw_parts(input, len) })
            .map_err(|e| e.to_string()).and_then(|v| execute(&v));
        let mut bytes = serde_json::to_vec(&result.unwrap_or_else(|error| json!({"error":error}))).unwrap().into_boxed_slice();
        unsafe { *size = bytes.len(); }
        let p = bytes.as_mut_ptr();
        std::mem::forget(bytes);
        OUTPUTS.fetch_add(1, Ordering::Relaxed);
        p
    }).unwrap_or(std::ptr::null_mut())
}
#[no_mangle]
pub unsafe extern "C" fn rq_whews_connection_free(p: *mut u8, len: usize) {
    if !p.is_null() {
        drop(unsafe { Box::from_raw(std::ptr::slice_from_raw_parts_mut(p, len)) });
        OUTPUTS.fetch_sub(1, Ordering::Relaxed);
    }
}
#[no_mangle]
pub extern "C" fn rq_whews_connection_outputs() -> usize { OUTPUTS.load(Ordering::Relaxed) }

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn fan_schedule_and_auth_stop() {
        let mut index = 0;
        let mut seconds = 3;
        for expected in [(0,3),(0,6),(0,12),(0,24),(1,48),(0,96),(1,192),(0,300)] {
            let (next, delay, retry_seconds) = retry(index, seconds, 2, 0).unwrap();
            assert_eq!((next, delay), expected);
            index = next; seconds = retry_seconds;
        }
        for code in [401,403,404,429,4401,4403,4008,1008] { assert!(retry(0,300,2,code).is_none()); }
        assert_eq!(retry(0,3,2,4503), Some((0,15,30)));
        assert_eq!(retry(0,300,1,0), Some((0,300,300)));
    }
    #[test]
    fn only_documented_shared_endpoints_have_a_backup() {
        for path in ["all","nied","snet","kma_station"] {
            let result = execute(&json!({"op":"endpoints","url":format!("wss://{PRIMARY}/ws/{path}?lang=zh")})).unwrap();
            assert_eq!(result[1], format!("wss://{BACKUP}/ws/{path}?lang=zh"));
        }
        for url in ["wss://api.2v8.cn/ws/cea_all","wss://api.beecld.com/ws/cea_all","ws://localhost/ws/all","wss://api.beecld.com.evil/ws/all"] {
            assert_eq!(execute(&json!({"op":"endpoints","url":url})).unwrap(), json!([url]));
        }
        assert_eq!(host(0), PRIMARY); assert_eq!(host(1), BACKUP);
    }
}
