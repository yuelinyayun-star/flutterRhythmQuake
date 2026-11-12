//! Isolated diagnostic DLL only. No network probe, credential read or retry.
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{collections::HashSet, path::PathBuf, sync::{atomic::{AtomicU64, Ordering}, Mutex, OnceLock}, time::{Instant, SystemTime, UNIX_EPOCH}};
static IDS: AtomicU64 = AtomicU64::new(1);
static ATTEMPTS: OnceLock<Mutex<HashSet<String>>> = OnceLock::new();
static LOG_LOCK: OnceLock<Mutex<()>> = OnceLock::new();

fn stamp() -> u128 { SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_millis() }
fn fingerprint(value: &str) -> String { format!("{:x}", Sha256::digest(value.as_bytes()))[..12].to_owned() }
fn authorization(headers: &str) -> Option<&str> {
    headers.lines().find_map(|line| {
        let (name, value) = line.split_once(':')?;
        name.trim().eq_ignore_ascii_case("Authorization").then_some(value.trim())
    })
}
fn access_token(headers: &str) -> Option<&str> {
    let mut values = authorization(headers)?.split_whitespace();
    if !values.next()?.eq_ignore_ascii_case("Bearer") { return None; }
    let token = values.next()?;
    (values.next().is_none() && token.starts_with("at_") && token.len() > 3).then_some(token)
}
fn query_token(path: &str) -> Option<&str> {
    path.split_once('?')?.1.split('&').find_map(|part| {
        let (key, value) = part.split_once('=')?;
        (key == "token" && value.starts_with("ja_") && value.len() > 3).then_some(value)
    })
}
fn redact(text: &str) -> String {
    let mut out = String::new();
    let mut tail = text;
    while !tail.is_empty() {
        if ["at_", "rt_", "ja_", "lk_"].iter().any(|prefix| tail.starts_with(prefix)) {
            let end = tail.bytes().position(|b| !(b.is_ascii_alphanumeric() || b"_-%.~".contains(&b))).unwrap_or(tail.len());
            out.push_str("[TOKEN_REDACTED]"); tail = &tail[end..];
        } else {
            let ch = tail.chars().next().unwrap(); out.push(ch); tail = &tail[ch.len_utf8()..];
        }
    }
    out.chars().take(512).collect()
}
pub(crate) struct Trace { path: PathBuf, id: u64, endpoint: String, started: Instant, pub allowed: bool, messages: u32 }
impl Trace {
    pub(crate) fn open(host: &str, path: &str, headers: &str) -> Option<Self> {
        if !host.eq_ignore_ascii_case("api.sismotide.top") { return None; }
        let log = std::env::var_os("RHYTHMQUAKE_JIAN_LOG")?;
        let endpoint = format!("wss://{}{}", host, path.split('?').next().unwrap_or("/"));
        let token = access_token(headers).or_else(|| query_token(path));
        let has_authorization = authorization(headers).is_some();
        let duplicate = !ATTEMPTS.get_or_init(Default::default).lock().unwrap().insert(endpoint.clone());
        let result = Self { path: log.into(), id: IDS.fetch_add(1, Ordering::Relaxed), endpoint, started: Instant::now(), allowed: token.is_some() && !duplicate, messages: 0 };
        result.event("handshake_attempt", json!({"authorizationHeaderPresent": has_authorization, "validAccessTokenShape": access_token(headers).is_some(), "queryCredentialPresent": query_token(path).is_some(), "credentialFingerprint": token.map(fingerprint), "allowed": result.allowed, "blockReason": if duplicate { Some("diagnostic_one_attempt_per_endpoint") } else if token.is_none() { Some("diagnostic_blocks_unauthenticated_connection") } else { None }}));
        Some(result)
    }
    pub(crate) fn event(&self, event: &str, details: Value) {
        use std::io::Write;
        let _guard = LOG_LOCK.get_or_init(Default::default).lock().unwrap();
        let row = json!({"timeUnixMs":stamp(),"processId":std::process::id(),"connectionId":self.id,"endpoint":self.endpoint,"elapsedMs":self.started.elapsed().as_millis(),"event":event,"details":details});
        if let Ok(mut file) = std::fs::OpenOptions::new().create(true).append(true).open(&self.path) { let _ = writeln!(file, "{}", row); }
    }
    pub(crate) fn message(&mut self, direction: &str, bytes: &[u8]) {
        let value = serde_json::from_slice::<Value>(bytes).ok();
        let is_error = value.as_ref().is_some_and(|v| v["type"] == "error" || !v["error"].is_null() || v["ok"] == false);
        if self.messages >= 32 && !is_error { return; }
        self.messages += 1;
        let mut details = json!({"direction":direction,"bytes":bytes.len()});
        if let Some(v) = value {
            for key in ["type", "code", "error", "message", "ok", "authenticated"] {
                match &v[key] { Value::String(s) => details[key] = json!(redact(s)), Value::Number(n) => details[key] = json!(n), Value::Bool(b) => details[key] = json!(b), _ => {} }
            }
        } else if let Ok(text) = std::str::from_utf8(bytes) {
            if ["at_", "rt_", "ja_", "lk_"].iter().any(|prefix| text.starts_with(prefix)) {
                details["credentialFrame"] = json!(true); details["credentialFingerprint"] = json!(fingerprint(text));
            } else if direction == "incoming" && text.len() <= 1024 && ["鉴权", "封禁", "auth", "banned"].iter().any(|word| text.contains(word)) {
                details["message"] = json!(redact(text));
            }
        }
        self.event("application_frame", details);
    }
    pub(crate) fn peer_close(&self, code: u16, reason: &[u8]) {
        self.event("peer_close", json!({"code":code,"reasonBytes":reason.len(),"reason":redact(&String::from_utf8_lossy(reason))}));
    }
}
#[no_mangle]
pub extern "C" fn rq_jian_diagnostic_mode() -> u32 { 1 }

#[cfg(test)]
mod tests {
    use super::*;
    #[test] fn header_case_and_credential_types_are_distinct() {
        assert_eq!(access_token("Other: X\r\naUtHoRiZaTiOn: Bearer at_contract_only\r\n"), Some("at_contract_only"));
        assert_eq!(access_token("Authorization: Bearer rt_contract_only"), None);
        assert_eq!(access_token("Authorization: Bearer at_x extra"), None);
        assert_eq!(access_token("Other: Authorization: Bearer at_x"), None);
        assert!(query_token("/icl?token=ja_contract_only").is_some());
    }
    #[test] fn secrets_are_never_written_as_message_text() {
        let text = "鉴权失败 rt_example_only / token=at_other_only, ja_test_only lk_test_only";
        let redacted = redact(text);
        for secret in ["rt_example_only", "at_other_only", "ja_test_only", "lk_test_only"] { assert!(!redacted.contains(secret)); }
        assert!(redacted.contains("鉴权失败"));
    }
    #[test] fn message_log_contains_evidence_without_token_or_event_payload() {
        let path = std::env::temp_dir().join(format!("rq-jian-log-contract-{}.jsonl", std::process::id()));
        let mut trace = Trace { path: path.clone(), id: 1, endpoint: "wss://api.sismotide.top/all".into(), started: Instant::now(), allowed: true, messages: 0 };
        trace.message("incoming", br#"{"type":"error","code":4001,"message":"token at_contract_only rejected","payload":"private body"}"#);
        let line = std::fs::read_to_string(&path).unwrap();
        assert!(line.contains("4001")); assert!(!line.contains("at_contract_only")); assert!(!line.contains("private body"));
        let _ = std::fs::remove_file(path);
    }
    #[test] fn diagnostic_guard_blocks_missing_auth_and_duplicate_without_network() {
        let path = std::env::temp_dir().join(format!("rq-jian-guard-contract-{}.jsonl",std::process::id()));
        std::env::set_var("RHYTHMQUAKE_JIAN_LOG",&path);
        let missing=Trace::open("api.sismotide.top","/unit-no-network","").unwrap();
        assert!(!missing.allowed);
        let first=Trace::open("api.sismotide.top","/unit-credential-no-network","Authorization: Bearer at_contract_only").unwrap();
        assert!(first.allowed);
        let duplicate=Trace::open("api.sismotide.top","/unit-credential-no-network","Authorization: Bearer at_contract_only").unwrap();
        assert!(!duplicate.allowed);
        assert!(Trace::open("localhost","/","").is_none());
        std::env::remove_var("RHYTHMQUAKE_JIAN_LOG");
        let line=std::fs::read_to_string(&path).unwrap();
        assert!(!line.contains("at_contract_only"));
        assert!(line.contains("diagnostic_blocks_unauthenticated_connection"));
        let _=std::fs::remove_file(path);
    }
    #[test] fn close_reason_preserves_auth_evidence_and_redacts_secrets() {
        let path = std::env::temp_dir().join(format!("rq-jian-close-contract-{}.jsonl", std::process::id()));
        let trace=Trace {path:path.clone(),id:1,endpoint:"wss://api.sismotide.top/all".into(),started:Instant::now(),allowed:true,messages:0};
        trace.peer_close(4401,"未鉴权连接 at_contract_only".as_bytes());
        let line=std::fs::read_to_string(&path).unwrap();
        assert!(line.contains("未鉴权连接"));assert!(!line.contains("at_contract_only"));
        let _=std::fs::remove_file(path);
    }
}
