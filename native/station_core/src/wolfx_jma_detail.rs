use crate::unified_event_policy::absolute;
use serde_json::{json, Value};
use std::{ptr, slice};

const MAX_INPUT: usize = 16 * 1024 * 1024;

fn indexed<'a>(items: &'a Value, index: &Value) -> Option<&'a Value> {
    items.get(usize::try_from(index.as_u64()?).ok()?)
}

fn product_index(product: &Value) -> Option<usize> {
    match product.as_str()? {
        "VXSE51" => Some(0),
        "VXSE52" => Some(1),
        "VXSE53" => Some(2),
        "VXSE62" => Some(3),
        _ => None,
    }
}

fn report_order(report: &Value) -> (Option<i64>, bool) {
    let published = ["issuedAt", "time"]
        .iter()
        .find_map(|key| absolute(report[*key].as_str()?, 0));
    (published, report["status"] == "cancelled")
}

fn reports(root: &Value) -> Option<Value> {
    let mut rows = Vec::new();
    for event in root.get("events")?.as_array()? {
        let Some(event_id) = event["eventId"].as_str().filter(|id| !id.is_empty()) else {
            continue;
        };
        let Some(event_reports) = event["reports"].as_array() else {
            continue;
        };
        let mut latest: [Option<&Value>; 4] = [None; 4];
        for report in event_reports {
            let Some(index) = product_index(&report["product"]) else {
                continue;
            };
            if !matches!(
                report["status"].as_str(),
                Some("issued" | "corrected" | "cancelled")
            ) || !report["id"].as_str().is_some_and(|id| !id.is_empty())
            {
                continue;
            }
            if latest[index].is_none_or(|previous| report_order(report) > report_order(previous)) {
                latest[index] = Some(report);
            }
        }
        // These three products share one ordinary JMA information slot. A
        // later partial report cannot replace the active combined bulletin.
        let ordinary = latest[..3]
            .iter()
            .rev()
            .flatten()
            .copied()
            .find(|report| report["status"] != "cancelled")
            .or_else(|| {
                latest[..3]
                    .iter()
                    .flatten()
                    .copied()
                    .max_by_key(|report| report_order(report))
            });
        for report in ordinary.into_iter().chain(latest[3]) {
            let hypocenter = indexed(&event["hypocenters"], &report["hypocenter"]);
            let observation = &report["observation"];
            let mut prefectures = Vec::new();
            if report["product"] == "VXSE62" {
                if let Some(areas) = observation["areas"].as_array() {
                    prefectures.extend(areas.iter().map(|area| {
                        indexed(&observation["prefs"], &area["pref"])
                            .and_then(|pref| pref["name"].as_str())
                            .unwrap_or("")
                    }));
                }
            }
            rows.push(json!({
                "eventId": event_id,
                "hypocenter": hypocenter,
                "prefectures": prefectures,
                "report": report,
            }));
        }
    }
    Some(json!({"md5": root["md5"], "reports": rows}))
}

#[no_mangle]
pub unsafe extern "C" fn rq_wolfx_jma_detail(
    input: *const u8,
    len: usize,
    out_len: *mut usize,
) -> *mut u8 {
    if out_len.is_null() {
        return ptr::null_mut();
    }
    unsafe { *out_len = 0 };
    if input.is_null() || len == 0 || len > MAX_INPUT {
        return ptr::null_mut();
    }
    let result = std::panic::catch_unwind(|| {
        let bytes = unsafe { slice::from_raw_parts(input, len) };
        let root = serde_json::from_slice(bytes).ok()?;
        let value = reports(&root)?;
        let mut output = serde_json::to_vec(&value).ok()?.into_boxed_slice();
        unsafe { *out_len = output.len() };
        let result = output.as_mut_ptr();
        std::mem::forget(output);
        Some(result)
    });
    result.ok().flatten().unwrap_or(ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "C" fn rq_wolfx_jma_detail_free(output: *mut u8, len: usize) {
    if !output.is_null() {
        unsafe { drop(Box::from_raw(ptr::slice_from_raw_parts_mut(output, len))) };
    }
}
