//! Replay preparation and publication-time policy. Original payloads are
//! borrowed per command, never changed or retained; Flutter owns timers/UI/IO.
use crate::unified_event_policy::wall;
use serde_json::{json, Value};
use std::sync::atomic::{AtomicUsize, Ordering};

static CALLS: AtomicUsize = AtomicUsize::new(0);
static OUTPUTS: AtomicUsize = AtomicUsize::new(0);
const HOUR: i64 = 3_600_000_000;

// Match savedReportTime's existing field precedence and date precision. Source
// wall-clock strings without an explicit ISO offset retain millisecond precision;
// ISO offsets retain microseconds. Numeric values are epoch seconds/milliseconds.
fn source_time(value: &Value, zone: i64) -> Option<i64> {
    if let Some(value) = value.as_f64() {
        let milliseconds = if value.abs() >= 100_000_000_000. {
            value.trunc()
        } else {
            (value * 1000.).trunc()
        };
        return (milliseconds.is_finite() && milliseconds.abs() <= 8_640_000_000_000_000.)
            .then_some(milliseconds as i64 * 1000);
    }
    let text = value.as_str()?.trim().replace('/', "-");
    let bytes = text.as_bytes();
    let offset = if text.ends_with('Z') || text.ends_with('z') {
        Some(0)
    } else if bytes.len() >= 6 {
        let tail = &bytes[bytes.len() - 6..];
        if matches!(tail[0], b'+' | b'-')
            && tail[3] == b':'
            && [tail[1], tail[2], tail[4], tail[5]]
                .iter()
                .all(u8::is_ascii_digit)
        {
            let hours = (tail[1] - b'0') as i64 * 10 + (tail[2] - b'0') as i64;
            let minutes = (tail[4] - b'0') as i64 * 10 + (tail[5] - b'0') as i64;
            Some((hours * 60 + minutes) * 60_000_000 * if tail[0] == b'-' { -1 } else { 1 })
        } else {
            None
        }
    } else {
        None
    };
    if bytes.iter().any(|v| matches!(v, b'z' | b'Z')) && offset.is_none() {
        return None;
    }
    fn digits(bytes: &[u8], at: &mut usize, min: usize, max: usize) -> Option<i64> {
        let start = *at;
        let mut number = 0;
        while *at < bytes.len() && *at - start < max && bytes[*at].is_ascii_digit() {
            number = number * 10 + (bytes[*at] - b'0') as i64;
            *at += 1;
        }
        (*at - start >= min).then_some(number)
    }
    let mut at = 0;
    let year = digits(bytes, &mut at, 4, 4)?;
    let separated = bytes.get(at) == Some(&b'-');
    if separated {
        at += 1;
    }
    let min = if separated && offset.is_none() { 1 } else { 2 };
    let month = digits(bytes, &mut at, min, 2)?;
    if separated {
        if bytes.get(at) != Some(&b'-') {
            return None;
        }
        at += 1;
    }
    let day = digits(bytes, &mut at, min, 2)?;
    let (mut hour, mut minute, mut second, mut fraction) = (0, 0, 0, 0);
    if offset.is_some() {
        // DateTime.parse's explicit-zone ISO branch requires a complete clock
        // and suffix, while allowing hour-only/minute-only ISO clocks.
        if !matches!(bytes.get(at), Some(b' ' | b'T' | b't')) {
            return None;
        }
        at += 1;
        hour = digits(bytes, &mut at, 2, 2)?;
        if bytes.get(at) == Some(&b':') {
            at += 1;
            minute = digits(bytes, &mut at, 2, 2)?;
        } else if bytes.get(at).is_some_and(u8::is_ascii_digit) {
            minute = digits(bytes, &mut at, 2, 2)?;
        }
        if bytes.get(at) == Some(&b':') {
            at += 1;
            second = digits(bytes, &mut at, 2, 2)?;
        } else if bytes.get(at).is_some_and(u8::is_ascii_digit) {
            second = digits(bytes, &mut at, 2, 2)?;
        }
        if matches!(bytes.get(at), Some(b'.' | b',')) {
            at += 1;
            let start = at;
            let number = digits(bytes, &mut at, 1, 6)?;
            fraction = number * 10_i64.pow((6 - (at - start)) as u32);
            while bytes.get(at).is_some_and(u8::is_ascii_digit) {
                at += 1;
            }
        }
        while bytes.get(at) == Some(&b' ') {
            at += 1;
        }
        let suffix = if text.ends_with('Z') || text.ends_with('z') {
            bytes.len() - 1
        } else {
            bytes.len() - 6
        };
        if at != suffix {
            return None;
        }
    } else if matches!(bytes.get(at), Some(b' ' | b'T')) {
        at += 1;
        let mut cursor = at;
        if let Some(h) = digits(bytes, &mut cursor, if separated { 1 } else { 2 }, 2) {
            let colon = bytes.get(cursor) == Some(&b':');
            if colon {
                cursor += 1;
            }
            if (!separated || colon) && bytes.get(cursor).is_some_and(u8::is_ascii_digit) {
                if let Some(m) = digits(bytes, &mut cursor, if separated { 1 } else { 2 }, 2) {
                    hour = h;
                    minute = m;
                    if bytes.get(cursor) == Some(&b':') || !separated {
                        if separated {
                            cursor += 1;
                        }
                        second = digits(bytes, &mut cursor, if separated { 1 } else { 2 }, 2)
                            .unwrap_or(0);
                        if bytes.get(cursor) == Some(&b'.') {
                            cursor += 1;
                            let precision = if offset.is_some() { 6 } else { 3 };
                            let start = cursor;
                            let number = digits(bytes, &mut cursor, 1, precision).unwrap_or(0);
                            fraction = number * 10_i64.pow((6 - (cursor - start)) as u32);
                        }
                    }
                }
            }
        }
    }
    // Dart DateTime normalizes out-of-range month/day/time components.
    let month0 = month - 1;
    let year = year + month0.div_euclid(12);
    let month = month0.rem_euclid(12) + 1;
    let base = wall(&format!("{year:04}-{month:02}-01T00:00:00"))?;
    Some(
        base + (day - 1) * 24 * HOUR
            + hour * HOUR
            + minute * 60_000_000
            + second * 1_000_000
            + fraction
            - offset.unwrap_or(zone * HOUR),
    )
}

fn execute(v: &Value) -> Result<Value, String> {
    match v["op"].as_str() {
        Some("needsHistory") => Ok(json!(
            (v["hasStoredReports"] == true
                && (v["storedSelection"] == true || v["hasFileReports"] != true))
                || v["hasStoredStations"] == true
        )),
        Some("reportInstant") => {
            let zone = v["timeZone"].as_i64().ok_or("Invalid replay time zone")?;
            if !(-12..=14).contains(&zone) {
                return Err("Invalid replay time zone".into());
            }
            let report = v["reportTime"]
                .as_str()
                .and_then(wall)
                .map(|us| us - zone * HOUR);
            let stored = v["storedReportInstant"].as_i64();
            let payload = &v["sourcePayload"];
            let body = if payload["Data"].is_object() {
                &payload["Data"]
            } else if payload["data"].is_object() {
                &payload["data"]
            } else {
                payload
            };
            let raw = [
                "ReportTime",
                "reportTime",
                "AnnouncedTime",
                "createTime",
                "updateTime",
            ]
            .iter()
            .map(|key| &body[*key])
            .find(|value| !value.is_null())
            .unwrap_or(&body["issue"]["time"]);
            let instant = report.or(stored).or_else(|| source_time(raw, zone));
            Ok(json!({"micros":instant, "needsPayload":instant.is_none()
                && v["hasStoredRef"] == true && payload.is_null()}))
        }
        _ => Err("Unknown replay policy operation".into()),
    }
}

#[no_mangle]
pub extern "C" fn rq_replay_policy_calls() -> u64 {
    CALLS.load(Ordering::Relaxed) as u64
}
#[no_mangle]
pub extern "C" fn rq_replay_policy_outputs() -> u64 {
    OUTPUTS.load(Ordering::Relaxed) as u64
}
#[no_mangle]
pub unsafe extern "C" fn rq_replay_policy_prepare(
    input: *const u8,
    len: usize,
    size: *mut usize,
) -> *mut u8 {
    if size.is_null() {
        return std::ptr::null_mut();
    }
    unsafe {
        *size = 0;
    }
    if input.is_null() || len > 128 * 1024 * 1024 {
        return std::ptr::null_mut();
    }
    std::panic::catch_unwind(|| {
        let result =
            serde_json::from_slice::<Value>(unsafe { std::slice::from_raw_parts(input, len) })
                .map_err(|e| e.to_string())
                .and_then(|v| execute(&v));
        let mut bytes = serde_json::to_vec(&result.unwrap_or_else(|e| json!({"error":e})))
            .unwrap()
            .into_boxed_slice();
        unsafe {
            *size = bytes.len();
        }
        let p = bytes.as_mut_ptr();
        std::mem::forget(bytes);
        CALLS.fetch_add(1, Ordering::Relaxed);
        OUTPUTS.fetch_add(1, Ordering::Relaxed);
        p
    })
    .unwrap_or(std::ptr::null_mut())
}
#[no_mangle]
pub unsafe extern "C" fn rq_replay_policy_free(p: *mut u8, len: usize) {
    if !p.is_null() {
        drop(unsafe { Box::from_raw(std::ptr::slice_from_raw_parts_mut(p, len)) });
        OUTPUTS.fetch_sub(1, Ordering::Relaxed);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn imports_and_saved_history_remain_distinct() {
        for selected in [false, true] {
            for stored in [false, true] {
                for files in [false, true] {
                    for stations in [false, true] {
                        assert_eq!(
                            execute(&json!({"op":"needsHistory","hasStoredReports":stored,
                "hasFileReports":files,"hasStoredStations":stations,"storedSelection":selected}))
                            .unwrap(),
                            (stored && (selected || !files)) || stations
                        );
                    }
                }
            }
        }
    }
    #[test]
    fn original_cea_publication_and_wrapped_payloads_preserve_time() {
        let raw = json!({"ReportTime":"2026-09-29 02:20:44"});
        for payload in [raw.clone(), json!({"Data":raw}), json!({"data":raw})] {
            assert_eq!(
                execute(&json!({"op":"reportInstant","timeZone":8,
                "sourcePayload":payload}))
                .unwrap()["micros"],
                wall("2026-09-28T18:20:44").unwrap()
            );
        }
        assert_eq!(
            source_time(&json!("2026-09-29T02:20:44.123456+08:00"), 9),
            wall("2026-09-28T18:20:44.123456")
        );
        assert_eq!(
            source_time(&json!("2026/9/29 2:20:44.123456"), 8),
            wall("2026-09-28T18:20:44.123000")
        );
    }
    #[test]
    fn missing_index_requires_one_original_payload_without_inventing_time() {
        let request = json!({"op":"reportInstant","timeZone":8,"hasStoredRef":true});
        assert_eq!(
            execute(&request).unwrap(),
            json!({"micros":null,"needsPayload":true})
        );
        let mut stored = request.clone();
        stored["storedReportInstant"] = json!(1234);
        assert_eq!(execute(&stored).unwrap()["micros"], 1234);
    }
}
