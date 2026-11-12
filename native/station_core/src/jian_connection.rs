//! Paired JIAN business/auth routing; transport failures cannot change credentials.
use serde_json::{json, Value};
use std::sync::atomic::{AtomicUsize, Ordering};
static OUTPUTS: AtomicUsize = AtomicUsize::new(0);
pub fn api_host(index: usize) -> &'static str {
    if index % 2 == 0 { "api.sismotide.top" } else { "api.jianproject.cloud" }
}
fn auth_host(index: usize) -> &'static str {
    if index % 2 == 0 { "auth.sismotide.top" } else { "auth.jianproject.cloud" }
}
fn execute(v: &Value) -> Result<Value, String> {
    match v["op"].as_str().unwrap_or("") {
        "transportAuthFailure" => Ok(match v["code"].as_u64().unwrap_or(0) {
            401 | 4003 => json!("invalid_api_key"),
            403 | 1008 => json!("handshake_rejected"),
            429 => json!("cooldown"),
            4001 => json!("missing_api_key"), 4002 => json!("invalid_token_format"),
            4004 => json!("expired_access_token"), 4005 => json!("conn_limit"),
            4006 => json!("account_banned"), _ => Value::Null,
        }),
        "endpoint" => {
            let index = v["index"].as_u64().filter(|n| *n < 2).ok_or("Invalid JIAN endpoint index")? as usize;
            let path = v["path"].as_str().ok_or("Invalid JIAN path")?;
            if !matches!(path, "/all" | "/kmoni" | "/s-net" | "/kma-station") { return Err("Unsupported JIAN failover path".into()); }
            Ok(json!({"url":format!("wss://{}{path}",api_host(index)),"authHost":auth_host(index),"needsAuth":path=="/all"}))
        }
        "authHost" => {
            let host = v["host"].as_str().ok_or("Invalid JIAN host")?;
            let index = if host == api_host(0) { 0 } else if host == api_host(1) { 1 } else { return Err("Untrusted JIAN API host".into()); };
            Ok(json!(auth_host(index)))
        }
        "retry" => {
            let index = v["index"].as_u64().filter(|n| *n < 2).ok_or("Invalid JIAN endpoint index")?;
            let mut failures = v["failures"].as_u64().ok_or("Invalid failure count")?;
            if v["stableMillis"].as_i64().is_some_and(|ms| ms > 120000) { failures = 0; }
            let delay = if let Some(ms) = v["cooldownMs"].as_u64() { ms } else {
                let ms = (45000_u64 * (1 << failures.min(3))).min(300000);
                failures = failures.saturating_add(1); ms
            };
            Ok(json!({"index":if v["switchEndpoint"]==true {1-index}else{index},"failures":failures,"delayMs":delay}))
        }
        _ => Err("Unknown JIAN connection operation".into()),
    }
}
#[no_mangle]
pub unsafe extern "C" fn rq_jian_connection_prepare(input: *const u8, len: usize, size: *mut usize) -> *mut u8 {
    if input.is_null() || size.is_null() || len > 16384 { return std::ptr::null_mut(); }
    unsafe { *size=0; }
    std::panic::catch_unwind(|| {
        let result=serde_json::from_slice::<Value>(unsafe {std::slice::from_raw_parts(input,len)})
            .map_err(|e|e.to_string()).and_then(|v|execute(&v));
        let mut bytes=serde_json::to_vec(&result.unwrap_or_else(|error|json!({"error":error}))).unwrap().into_boxed_slice();
        unsafe { *size=bytes.len(); }
        let p=bytes.as_mut_ptr();std::mem::forget(bytes);OUTPUTS.fetch_add(1,Ordering::Relaxed);p
    }).unwrap_or(std::ptr::null_mut())
}
#[no_mangle]
pub unsafe extern "C" fn rq_jian_connection_free(p: *mut u8,len: usize) {
    if !p.is_null() {drop(unsafe {Box::from_raw(std::ptr::slice_from_raw_parts_mut(p,len))});OUTPUTS.fetch_sub(1,Ordering::Relaxed);}
}
#[no_mangle]
pub extern "C" fn rq_jian_connection_outputs() -> usize {OUTPUTS.load(Ordering::Relaxed)}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn paired_hosts_and_exempt_stations() {
        for i in 0..2 {
            for path in ["/all","/kmoni","/s-net","/kma-station"] {
                let r=execute(&json!({"op":"endpoint","index":i,"path":path})).unwrap();
                assert_eq!(r["url"],format!("wss://{}{path}",api_host(i)));
                assert_eq!(r["authHost"],auth_host(i));assert_eq!(r["needsAuth"],path=="/all");
            }
        }
        assert!(execute(&json!({"op":"authHost","host":"untrusted.invalid"})).is_err());
        assert!(execute(&json!({"op":"endpoint","index":0,"path":"/icl"})).is_err());
    }
    #[test]
    fn backoff_and_auth_cooldowns_are_preserved() {
        let mut v=json!({"op":"retry","index":0,"failures":0,"switchEndpoint":true});
        for expected in [45000,90000,180000,300000,300000] {
            let r=execute(&v).unwrap();assert_eq!(r["delayMs"],expected);
            assert_ne!(r["index"],v["index"]);v["index"]=r["index"].clone();v["failures"]=r["failures"].clone();
        }
        v["switchEndpoint"]=json!(false);v["cooldownMs"]=json!(300000);
        let r=execute(&v).unwrap();assert_eq!(r["index"],v["index"]);assert_eq!(r["delayMs"],300000);
        v["cooldownMs"]=Value::Null;v["stableMillis"]=json!(120001);
        assert_eq!(execute(&v).unwrap()["delayMs"],45000);
    }
}
