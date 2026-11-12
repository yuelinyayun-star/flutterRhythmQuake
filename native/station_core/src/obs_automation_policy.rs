//! Select enabled OBS rules without changing program steps or parameters.
//! Flutter retains platform IO, event delivery, timers and rendering.
use serde_json::{json, Value};
use std::sync::atomic::{AtomicUsize, Ordering};

static CALLS: AtomicUsize = AtomicUsize::new(0);
static OUTPUTS: AtomicUsize = AtomicUsize::new(0);

fn select(root: &Value) -> Result<Value, String> {
    let presets = root["presets"].as_array().ok_or("Missing OBS presets")?;
    let mut selected = Vec::new();
    for (preset_index, preset) in presets.iter().enumerate() {
        if preset["enabled"] != true { continue; }
        let stacks = preset["stacks"].as_array().ok_or("Missing OBS rules")?;
        let indices: Vec<usize> = stacks.iter().enumerate()
            .filter(|(_, stack)| stack["enabled"] != false)
            .map(|(index, _)| index).collect();
        // Keep enabled presets with no newly enabled rules. Existing executions
        // can still finish under their original stop/wait conditions.
        selected.push(json!({"presetIndex":preset_index,"stackIndices":indices}));
    }
    Ok(json!(selected))
}

fn prepare(root: &Value) -> Result<Value, String> {
    match root["op"].as_str() {
        None => select(root),
        Some("missingShakeAlertRules") => {
            let presets = root["presets"].as_array().ok_or("Missing OBS presets")?;
            let mut indices = Vec::new();
            for (index, preset) in presets.iter().enumerate() {
                if !matches!(preset["name"].as_str(), Some("EEW 分机构自动录制" | "EEW M5 分机构自动录制")) {
                    continue;
                }
                let stacks = preset["stacks"].as_array().ok_or("Missing OBS rules")?;
                let exists = stacks.iter().any(|stack| {
                    stack["blocks"].as_array().is_some_and(|blocks| blocks.iter().any(|block| {
                        block["type"] == "eewAgency" && block["parameters"]["value"] == "shakeAlert"
                    }))
                });
                if !exists { indices.push(index); }
            }
            Ok(json!(indices))
        }
        Some("sourceMatch") => {
            let Some(actual) = root["source"].as_str() else {
                return Ok(json!({"matches":false}));
            };
            let expected = root["expected"].as_str().unwrap_or("").trim().to_lowercase();
            let actual = actual.trim().to_lowercase();
            // Only OBS's existing LPGM source selector gains this alias. The
            // original event source and all other selectors remain untouched.
            let actual = if expected == "jmalpgm" && root["isJmaLpgm"] == true {
                "jmalpgm"
            } else { &actual };
            let matched = match root["operator"].as_str().unwrap_or("equals") {
                "equals" => actual == expected,
                "notEquals" => actual != expected,
                "contains" => actual.contains(&expected),
                "notContains" => !actual.contains(&expected),
                _ => false,
            };
            Ok(json!({"matches":matched}))
        }
        Some("tsunamiProjection") => {
            let m = &root["message"];
            let offset_minutes = m["timeZone"].as_i64().unwrap_or(0) * 60;
            let instant = |key: &str| m[key].as_str()
                .and_then(|v| {
                    // NMEFC supplies minute precision. Interpret that precision
                    // only in the OBS projection; never rewrite the bulletin.
                    if v.len() == 16 {
                        crate::unified_event_policy::absolute(&format!("{v}:00"), offset_minutes)
                    } else {
                        crate::unified_event_policy::absolute(v, offset_minutes)
                    }
                })
                .map(|micros| micros / 1000);
            Ok(json!({
                "source":format!("obs_tsunami_{}", m["source"].as_str().unwrap_or("")),
                "eventId":m["eventId"].as_str().filter(|s| !s.is_empty()).or(m["id"].as_str()).unwrap_or(""),
                "originUtcMs":instant("originTime"), "reportUtcMs":instant("reportTime"),
                "latitude":m["epicenterLat"], "longitude":m["epicenterLng"],
                "magnitude":m["magnitude"], "depth":m["depth"],
            }))
        }
        _ => Err("Unknown OBS policy operation".into()),
    }
}

#[no_mangle]
pub extern "C" fn rq_obs_automation_calls() -> u64 { CALLS.load(Ordering::Relaxed) as u64 }
#[no_mangle]
pub extern "C" fn rq_obs_automation_outputs() -> u64 { OUTPUTS.load(Ordering::Relaxed) as u64 }

#[no_mangle]
pub unsafe extern "C" fn rq_obs_automation_select(input: *const u8, len: usize, size: *mut usize) -> *mut u8 {
    if size.is_null() { return std::ptr::null_mut(); }
    unsafe { *size = 0; }
    if input.is_null() || len > 16 * 1024 * 1024 { return std::ptr::null_mut(); }
    std::panic::catch_unwind(|| {
        let result = serde_json::from_slice::<Value>(unsafe { std::slice::from_raw_parts(input, len) })
            .map_err(|error| error.to_string()).and_then(|root| prepare(&root));
        let bytes = serde_json::to_vec(&result.unwrap_or_else(|error| json!({"error":error})))
            .unwrap().into_boxed_slice();
        unsafe { *size = bytes.len(); }
        CALLS.fetch_add(1, Ordering::Relaxed);
        OUTPUTS.fetch_add(1, Ordering::Relaxed);
        Box::into_raw(bytes).cast::<u8>()
    }).unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "C" fn rq_obs_automation_free(pointer: *mut u8, len: usize) {
    if !pointer.is_null() {
        drop(unsafe { Box::from_raw(std::ptr::slice_from_raw_parts_mut(pointer, len)) });
        OUTPUTS.fetch_sub(1, Ordering::Relaxed);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn shake_alert_addition_only_targets_missing_managed_rows() {
        let existing = json!({"type":"eewAgency","parameters":{"value":"shakeAlert"}});
        let input = json!({"op":"missingShakeAlertRules","presets":[
            {"name":"EEW 分机构自动录制","enabled":false,"stacks":[]},
            {"name":"custom","stacks":[]},
            {"name":"EEW 分机构自动录制","stacks":[{"enabled":false,"blocks":[existing]}]},
            {"name":"EEW M5 分机构自动录制","stacks":[{"blocks":[{"type":"magnitude","parameters":{"value":"6.2"}}]}]}
        ]});
        let before = input.clone();
        assert_eq!(prepare(&input).unwrap(), json!([0,3]));
        assert_eq!(input, before);
    }
    #[test]
    fn lpgm_alias_is_limited_to_its_existing_obs_selector() {
        for (source, flag, expected, matched) in [
            ("jmaLpgm", false, "jmaLpgm", true),
            ("jmaEqlist", true, "jmaLpgm", true),
            ("jmaEqlist", false, "jmaLpgm", false),
            ("jmaEqlist", true, "jmaEqlist", true),
            ("cwaEqlist", false, "jmaLpgm", false),
        ] {
            let input = json!({"op":"sourceMatch","source":source,"isJmaLpgm":flag,"expected":expected,"operator":"equals"});
            let before = input.clone();
            assert_eq!(prepare(&input).unwrap()["matches"], matched);
            assert_eq!(input, before);
        }
        assert_eq!(prepare(&json!({"op":"sourceMatch","source":" JMAEQLIST ","expected":"jmaeqlist","operator":"equals"})).unwrap()["matches"], true);
        assert_eq!(prepare(&json!({"op":"sourceMatch","source":null,"expected":"jmaLpgm","operator":"notEquals"})).unwrap()["matches"], false);
    }

    #[test]
    fn tsunami_projection_keeps_missing_origin_missing_and_obeys_source_zone() {
        // Protocol metadata unit inputs; not fabricated received bulletins.
        let japanese = json!({"op":"tsunamiProjection","message":{
            "source":"jma","eventId":"unit","originTime":"2025-07-30 08:25:00","reportTime":"2025-07-30T00:00:00Z","timeZone":9,
            "epicenterLat":52.0,"epicenterLng":160.0}});
        let before = japanese.clone();
        let projection = prepare(&japanese).unwrap();
        let utc = prepare(&json!({"op":"tsunamiProjection","message":{"source":"jma","originTime":"2025-07-29T23:25:00Z","timeZone":0}})).unwrap();
        assert_eq!(projection["originUtcMs"], utc["originUtcMs"]);
        assert_eq!(projection["latitude"], 52.0);
        assert_eq!(japanese, before);
        let missing = prepare(&json!({"op":"tsunamiProjection","message":{"source":"jma","reportTime":"2025-07-30T00:00:00Z","timeZone":9}})).unwrap();
        assert!(missing["originUtcMs"].is_null());
        assert!(missing["latitude"].is_null());
        let minute = prepare(&json!({"op":"tsunamiProjection","message":{"source":"nmefc","originTime":"2026-10-24 10:31","timeZone":8}})).unwrap();
        let second = prepare(&json!({"op":"tsunamiProjection","message":{"source":"nmefc","originTime":"2026-10-24T02:31:00Z","timeZone":0}})).unwrap();
        assert!(minute["originUtcMs"].is_number());
        assert_eq!(minute["originUtcMs"], second["originUtcMs"]);
    }
    #[test]
    fn legacy_rules_default_on_and_switches_are_independent() {
        let original = json!({"presets":[
            {"enabled":true,"stacks":[{"id":"old","blocks":[{"type":"magnitude","parameters":{"value":"1.0"}}]},
                {"id":"off","enabled":false},{"id":"on","enabled":true}]},
            {"enabled":false,"stacks":[{"enabled":true}]},
            {"enabled":true,"stacks":[{"enabled":false}]}
        ]});
        let before = original.clone();
        assert_eq!(select(&original).unwrap(), json!([
            {"presetIndex":0,"stackIndices":[0,2]}, {"presetIndex":2,"stackIndices":[]}
        ]));
        assert_eq!(before, original);
    }
    #[test]
    fn ffi_output_is_released() {
        let baseline = OUTPUTS.load(Ordering::Relaxed);
        for input in [
            br#"{"presets":[]}"#.as_slice(),
            "{\"op\":\"missingShakeAlertRules\",\"presets\":[{\"name\":\"EEW 分机构自动录制\",\"stacks\":[]}]}".as_bytes(),
            br#"{"op":"sourceMatch","source":"jmaEqlist","expected":"jmaLpgm","isJmaLpgm":true}"#.as_slice(),
            br#"{"op":"tsunamiProjection","message":{"originTime":"2026-10-24 10:31","timeZone":8}}"#.as_slice(),
        ] {
          for _ in 0..100 {
            let mut size = 0;
            let output = unsafe { rq_obs_automation_select(input.as_ptr(), input.len(), &mut size) };
            assert!(!output.is_null());
            let result: Value = serde_json::from_slice(unsafe { std::slice::from_raw_parts(output, size) }).unwrap();
            assert!(result.get("error").is_none());
            unsafe { rq_obs_automation_free(output, size); }
          }
        }
        assert_eq!(OUTPUTS.load(Ordering::Relaxed), baseline);
    }
}
