//! JMA forecast source decoding and grade-group projection. Original reports are immutable.
use crate::unified_event_policy::absolute;
use serde_json::{json, Value};
use std::ptr;
#[path = "tsunami_gauges.rs"]
mod gauges;
#[path = "international_tsunami_presentation.rs"]
mod international_presentation;
#[path = "nmefc_tsunami.rs"]
mod nmefc;
#[path = "jma_tsunami_observations.rs"]
mod observations;
#[path = "jma_tsunami_sidebar.rs"]
mod sidebar;
#[path = "tsunami_wave_data.rs"]
mod wave_data;
const GRADES: [&str; 5] = ["none", "forecast", "watch", "warning", "majorWarning"];
const LABELS: [&str; 5] = [
    "津波なし",
    "津波予報",
    "津波注意報",
    "津波警報",
    "大津波警報",
];
const COLORS: [&str; 5] = ["gray", "blue", "yellow", "red", "purple"];
fn text(v: &Value) -> String {
    match v {
        Value::String(s) => s.trim().to_owned(),
        Value::Number(n) => n.to_string(),
        _ => String::new(),
    }
}
fn s(v: &Value, k: &str) -> String {
    text(&v[k])
}
fn number(v: &Value) -> Option<f64> {
    v.as_f64()
        .or_else(|| v.as_str()?.trim().parse().ok())
        .filter(|n| n.is_finite())
}
// The upstream XML quantity is sometimes a JSON object, sometimes Go's
// map[type:... unit:m value:...] string. Decode only that explicit metre
// quantity; never extract an arbitrary number from qualitative descriptions.
fn quantity_height(v: &Value) -> Option<f64> {
    let value = if v.is_object() {
        if s(v, "type") != "津波の高さ" || s(v, "unit") != "m" {
            return None;
        }
        number(&v["value"])?
    } else {
        let raw = v.as_str()?.trim();
        let body = raw.strip_prefix("map[")?.strip_suffix(']')?;
        let mut kind = None;
        let mut unit = None;
        let mut value = None;
        for field in body.split_whitespace() {
            let (key, text) = field.split_once(':')?;
            match key {
                "type" if kind.is_none() => kind = Some(text),
                "unit" if unit.is_none() => unit = Some(text),
                "value" if value.is_none() => value = text.parse::<f64>().ok(),
                _ => return None,
            }
        }
        if kind != Some("津波の高さ") || unit != Some("m") {
            return None;
        }
        value?
    };
    (value.is_finite() && value >= 0.0).then_some(value)
}
fn grade(kind: &str) -> usize {
    if ["解除", "取消", "なし", "失効"]
        .iter()
        .any(|s| kind.contains(s))
    {
        0
    } else if kind.contains("大津波警報")
        || kind.eq_ignore_ascii_case("MajorWarning")
        || ["52", "53"].contains(&kind)
    {
        4
    } else if kind.contains("津波警報") || kind.eq_ignore_ascii_case("Warning") || kind == "51"
    {
        3
    } else if kind.contains("注意報") || kind.eq_ignore_ascii_case("Watch") || kind == "62" {
        2
    } else if kind.contains("予報")
        || kind.contains("海面変動")
        || kind.eq_ignore_ascii_case("Forecast")
        || ["71", "72"].contains(&kind)
    {
        1
    } else {
        0
    }
}
fn epoch(v: &Value) -> String {
    let Some(ms) = v.as_i64().or_else(|| v.as_str()?.parse().ok()) else {
        return String::new();
    };
    let day = ms.div_euclid(86_400_000) + 719468;
    let era = day.div_euclid(146097);
    let doe = day - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let mut y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = mp + if mp < 10 { 3 } else { -9 };
    y += i64::from(m <= 2);
    let sec = ms.div_euclid(1000).rem_euclid(86400);
    format!(
        "{y:04}-{m:02}-{d:02}T{:02}:{:02}:{:02}.{:03}Z",
        sec / 3600,
        sec / 60 % 60,
        sec % 60,
        ms.rem_euclid(1000)
    )
}
fn area(
    name: String,
    g: usize,
    height: Option<f64>,
    desc: String,
    arrival: String,
    condition: String,
) -> Value {
    json!({"name":name,"grade":GRADES[g],"height":height,"description":desc,"arrivalTime":arrival,"condition":condition,"className":COLORS[g]})
}
fn parse(transport: &str, raw: &Value) -> Result<Value, String> {
    let jian = transport == "jian";
    let p2p = transport == "p2p";
    if !["jian", "p2p", "whews"].contains(&transport) {
        return Err("Unknown JMA tsunami transport".into());
    }
    let issued = if jian {
        epoch(&raw["originTime"])
    } else if p2p {
        s(&raw["issue"], "time").replace('/', "-")
    } else {
        s(raw, "createTime")
    };
    if jian && issued.is_empty() {
        return Err("Missing JMA issue time".into());
    }
    let cancelled =
        raw[if p2p { "cancelled" } else { "cancel" }] == true || s(raw, "infoTypeName") == "取消";
    let mut areas = vec![];
    if let Some(rows) = raw[if jian { "area" } else { "areas" }].as_array() {
        for row in rows {
            if !row.is_object() {
                continue;
            }
            let kind = if p2p { s(row, "grade") } else { s(row, "kind") };
            let g = if row["cleared"] == true {
                0
            } else {
                grade(if kind.is_empty() {
                    row["kindCode"].as_str().unwrap_or("")
                } else {
                    &kind
                })
            };
            let h = if p2p {
                &row["maxHeight"]["value"]
            } else {
                &row["maxHeight"]
            };
            let desc = if p2p {
                s(&row["maxHeight"], "description")
            } else {
                s(row, "maxHeightDesc")
            };
            let desc = if desc.is_empty() {
                if p2p || text(h) == "NaN" {
                    String::new()
                } else {
                    text(h)
                }
            } else {
                desc
            };
            let height = number(h)
                .or_else(|| quantity_height(h))
                .or_else(|| quantity_height(&row["maxHeightDesc"]))
                .or_else(|| quantity_height(&json!(desc)));
            let desc = if let Some(value) = quantity_height(h).filter(|_| desc.is_empty()) {
                format!("{value}m")
            } else {
                desc
            };
            let a = if p2p {
                s(&row["firstHeight"], "arrivalTime")
            } else {
                s(row, "arrivalTime")
            };
            let c = if p2p {
                let condition = s(&row["firstHeight"], "condition");
                if condition.is_empty() && row["immediate"] == true {
                    "ただちに津波来襲と予測".to_owned()
                } else {
                    condition
                }
            } else {
                s(row, "condition")
            };
            areas.push(area(s(row, "name"), g, height, desc, a, c));
        }
    } else if jian {
        // Older archived Jian reports use a semicolon-delimited region string.
        let source = s(raw, "area");
        for region in source.split([';', '；']) {
            let found = LABELS[1..]
                .iter()
                .filter_map(|label| region.find(label).map(|i| (i, *label)))
                .min_by_key(|v| v.0);
            if let Some((i, label)) = found {
                let name = region[..i].trim();
                if name.is_empty() {
                    continue;
                }
                let tail = region[i + label.len()..].trim();
                let tail = tail
                    .strip_prefix("（若干の海面変動）")
                    .or_else(|| tail.strip_prefix("(若干の海面変動)"))
                    .unwrap_or(tail)
                    .trim();
                areas.push(area(
                    name.to_owned(),
                    grade(label),
                    None,
                    tail.to_owned(),
                    String::new(),
                    String::new(),
                ));
            }
        }
    }
    let level = s(raw, "level");
    let mut top = areas
        .iter()
        .map(|v| grade(&s(v, "grade")))
        .max()
        .unwrap_or(0);
    // Canonical enum names are case-insensitive but `majorWarning` is supported above.
    if areas.is_empty() {
        top = grade(&level);
    }
    if cancelled {
        top = 0;
        areas.clear();
    }
    let mut id = s(raw, "id");
    if id.is_empty() && p2p {
        id = issued.chars().filter(char::is_ascii_digit).collect();
    }
    let legacy = id.strip_prefix("jma_tsu_").and_then(|v| v.rsplit_once('_'));
    let headline = s(raw, "headline");
    let is_id = |v: &str| v.len() == 14 && v.bytes().all(|c| c.is_ascii_digit());
    let event = if jian {
        if is_id(&id) {
            id.clone()
        } else if is_id(&headline) {
            headline.clone()
        } else {
            legacy.map(|v| v.0.to_owned()).unwrap_or_default()
        }
    } else {
        let event_id = s(raw, "eventId");
        if !event_id.is_empty() {
            event_id
        } else if !p2p && is_id(&id) {
            id.clone()
        } else {
            String::new()
        }
    };
    let report = raw["number"]
        .as_i64()
        .or_else(|| raw["number"].as_str()?.parse().ok())
        .or_else(|| {
            if !jian && !p2p {
                raw["updates"].as_i64()
            } else {
                None
            }
        })
        .or_else(|| legacy.and_then(|v| v.1.parse().ok()));
    let title = if jian && cancelled {
        format!(
            "{}（取消）",
            if s(raw, "title").is_empty() {
                "津波警報・注意報・予報".into()
            } else {
                s(raw, "title")
            }
        )
    } else if cancelled {
        if p2p {
            "津波警報・注意報なし"
        } else {
            "津波警報・注意報解除"
        }
        .to_owned()
    } else if jian && !level.is_empty() {
        level.clone()
    } else if !s(raw, "title").is_empty() {
        s(raw, "title")
    } else {
        LABELS[top].to_owned()
    };
    let description = s(raw, "description");
    let body = if jian && !description.is_empty() {
        description
    } else if !headline.is_empty() && !is_id(&headline) {
        headline
    } else {
        title.clone()
    };
    let mut message = json!({"source":"jma","id":id,"eventId":event,"reportNumber":report,"reportTime":issued,"timeZone":9,
      "title":title,"titleText":body,"grade":GRADES[top],"areas":areas,"className":COLORS[top],
      "sourcePayload":raw,"expires":if jian{epoch(&raw["endTime"])}else if !p2p && !s(raw,"validDateTime").is_empty(){s(raw,"validDateTime")}else{s(raw,"expires")},
      "bulletinLevel":if cancelled || (top==0 && ["解除","なし","取消"].iter().any(|w|level.contains(w))){"cancellation"}else if top==1{"information"}else{&level},
      "epicenterLat":number(&raw["latitude"]),"epicenterLng":number(&raw["longitude"]),"magnitude":number(&raw["magnitude"]),"depth":number(&raw["depth"]),
      "epicenterName":if !s(raw,"place").is_empty(){s(raw,"place")}else{s(raw,"title")},"htmlUrl":s(raw,"htmlUrl")});
    observations::attach(transport, raw, &mut message);
    Ok(message)
}
// Typography normalization applies only to display text; raw values remain in sourcePayload.
fn compact_height(v: &str) -> String {
    if let Some(value) = quantity_height(&json!(v)) {
        return format!("{value}m");
    }
    let normalized = v
        .chars()
        .map(|c| match c {
            '０'..='９' => char::from_u32(c as u32 - '０' as u32 + '0' as u32).unwrap(),
            '．' => '.',
            'ｍ' | 'Ｍ' | 'M' => 'm',
            '　' => ' ',
            _ => c,
        })
        .collect::<String>()
        .replace("メートル", "m")
        .trim()
        .to_owned();
    if let Ok(n) = normalized.parse::<f64>() {
        if n.is_finite() {
            return format!("{n}m");
        }
    }
    normalized
}
fn arrival_label(condition: &str) -> &str {
    match condition {
        "津波到達中と推測" => "到達と推測",
        "ただちに津波来襲と予測" => "すぐ来る",
        _ => condition,
    }
}

// The UI supplies measured text heights. Pairing, page boundaries, stable cell
// size and rotation cadence are prepared here without changing report rows.
fn paginate(c: &Value) -> Value {
    let Some(heights) = c["itemHeights"].as_array() else {
        return json!({"error":"Missing JMA layout measurements"});
    };
    let unit = number(&c["unitHeight"])
        .filter(|n| *n > 0.0)
        .unwrap_or(76.0);
    let overhead = number(&c["overhead"]).unwrap_or(0.0).max(0.0);
    let gap = number(&c["rowGap"]).unwrap_or(0.0).max(0.0);
    let max_units = number(&c["maxUnits"]).unwrap_or(2.0).clamp(1.0, 2.0);
    let columns = c["columns"].as_u64().unwrap_or(2).clamp(1, 2) as usize;
    let available = (unit * max_units - overhead).max(1.0);
    let mut pages = Vec::<Value>::new();
    let mut lines = Vec::<Value>::new();
    let mut content_height = 0.0_f64;
    let mut max_height = 0.0_f64;
    for start in (0..heights.len()).step_by(columns) {
        let indices = (start..(start + columns).min(heights.len())).collect::<Vec<_>>();
        let height = indices
            .iter()
            .filter_map(|i| number(&heights[*i]))
            .fold(1.0_f64, f64::max);
        let next = content_height + if lines.is_empty() { 0.0 } else { gap } + height;
        if !lines.is_empty() && next > available {
            max_height = max_height.max(content_height);
            pages.push(json!({"lines":std::mem::take(&mut lines),"contentHeight":content_height}));
            content_height = 0.0;
        }
        if !lines.is_empty() {
            content_height += gap;
        }
        content_height += height;
        lines.push(json!({"indices":indices,"height":height}));
    }
    if !lines.is_empty() {
        max_height = max_height.max(content_height);
        pages.push(json!({"lines":lines,"contentHeight":content_height}));
    }
    let units = ((max_height + overhead) / unit)
        .ceil()
        .clamp(1.0, max_units) as usize;
    json!({"pages":pages,"units":units,"intervalMs":12000})
}

fn project(message: &Value, now_ms: i64) -> Value {
    let expires = s(message, "expires");
    let expired =
        !expires.is_empty() && absolute(&expires, 9 * 60).is_some_and(|t| t / 1000 <= now_ms);
    let top = grade(&s(message, "grade"));
    let cancelled = s(message, "bulletinLevel").eq_ignore_ascii_case("cancellation");
    let has_active_area = message["areas"]
        .as_array()
        .into_iter()
        .flatten()
        .any(|row| grade(&s(row, "grade")) > 0);
    // Keep the cleared report for ordering, but stop displaying it after all
    // warnings/forecasts are gone. Partial clearances still belong to the list.
    let show_forecast = !expired && !cancelled && (top != 0 || has_active_area);
    let mut buckets: [Vec<Value>; 5] = Default::default();
    for row in message["areas"]
        .as_array()
        .into_iter()
        .flatten()
        .filter(|_| show_forecast)
    {
        let g = grade(&s(row, "grade"));
        let desc = s(row, "description");
        let numeric = number(&row["height"]);
        let height = if !desc.is_empty() {
            compact_height(&desc)
        } else if let Some(n) = numeric {
            format!("{n}m")
        } else {
            "未知".into()
        };
        // P2P represents >10m with the sentinel value -1, never display a negative forecast.
        let height = if g == 0 {
            String::new()
        } else if numeric == Some(-1.0) && desc.is_empty() {
            "10m超".into()
        } else {
            height
        };
        buckets[g].push(json!({"name":s(row,"name"),"height":height,"arrivalTime":s(row,"arrivalTime"),"condition":s(row,"condition"),"arrivalLabel":arrival_label(&s(row,"condition"))}));
    }
    let mut groups = vec![];
    if show_forecast && buckets.iter().all(Vec::is_empty) {
        buckets[top]
            .push(json!({"name":"","height":"","arrivalTime":"","condition":"","arrivalLabel":""}));
    }
    for g in (0..5).rev() {
        if buckets[g].is_empty() {
            continue;
        }
        let label = if g == 0 && cancelled {
            s(message, "title")
        } else {
            LABELS[g].to_owned()
        };
        let rows = std::mem::take(&mut buckets[g]);
        groups.push(json!({"key":format!("{}:{}",s(message,"eventId"),GRADES[g]),"grade":GRADES[g],"label":label,
            "caption":format!("JMA {label}"),"className":COLORS[g],"regionCount":rows.iter().filter(|v|!s(v,"name").is_empty()).count(),"rows":rows,
            "reportTime":s(message,"reportTime"),"reportNumber":message["reportNumber"],"headline":s(message,"titleText")}));
    }
    observations::append_groups(message, &mut groups, show_forecast);
    json!({"groups":groups})
}
pub fn execute(c: &Value) -> Value {
    let mut result = match c["op"].as_str().unwrap_or("") {
        "gaugePlan" => gauges::prepare(c).unwrap_or_else(|e| json!({"error":e})),
        "waveData" => wave_data::project(&c["message"], c["nowMs"].as_i64().unwrap_or(0)),
        "prepareWaveData" => {
            let data = wave_data::project(&c["message"], c["nowMs"].as_i64().unwrap_or(0));
            if data == c["message"]["waveData"] {
                json!({"unchanged":true})
            } else {
                json!({"data":data})
            }
        }
        "noaaIsCurrent" => json!({"current":wave_data::is_current(&c["previous"],&c["incoming"])}),
        "noaaDetail" => wave_data::noaa_detail(c).unwrap_or_else(|e| json!({"error":e})),
        "incoisDetail" => wave_data::incois_detail(c).unwrap_or_else(|e| json!({"error":e})),
        "nmefcParse" => nmefc::parse(&c["payload"]),
        "nmefcBulletin" => nmefc::bulletin(c),
        "nmefcAccept" => nmefc::accept(&c["previous"], &c["incoming"]),
        "nmefcSidebar" => nmefc::sidebar(&c["message"]),
        "internationalProject" => {
            international_presentation::project(&c["message"], c["nowMs"].as_i64().unwrap_or(0))
        }
        "internationalSidebar" => {
            international_presentation::sidebar(&c["message"], c["nowMs"].as_i64().unwrap_or(0))
        }
        "internationalListOrder" => international_presentation::list_order(&c),
        "nmefcCoastalMap" => nmefc::coastal_map(&c["message"]),
        "nmefcVoice" => nmefc::voice(&c["message"], c["isUpdate"] == true),
        "parse" => match parse(c["transport"].as_str().unwrap_or(""), &c["payload"]) {
            Ok(v) => v,
            Err(e) => json!({"error":e}),
        },
        "project" => project(&c["message"], c["nowMs"].as_i64().unwrap_or(0)),
        "accept" => observations::accept(&c["previous"], &c["incoming"]),
        "snapshot" => observations::snapshot(&c["frames"]),
        "frameKey" => observations::frame_key(&c["frame"]),
        "paginate" => paginate(c),
        "sidebar" => sidebar::prepare(&c["groups"]),
        "sidebarPaginate" => sidebar::paginate(c),
        _ => json!({"error":"Unknown JMA tsunami command"}),
    };
    if matches!(c["op"].as_str(), Some("parse" | "nmefcParse")) && result.get("error").is_none() {
        result["waveData"] = wave_data::project(&result, c["nowMs"].as_i64().unwrap_or(0));
    }
    result
}
/// Owned packed view; the matching free must use the returned length once.
#[no_mangle]
pub unsafe extern "C" fn rq_jma_tsunami_prepare(
    input: *const u8,
    len: usize,
    out_len: *mut usize,
) -> *mut u8 {
    if input.is_null() || out_len.is_null() || len > 8 * 1024 * 1024 {
        return ptr::null_mut();
    }
    unsafe {
        *out_len = 0;
    }
    std::panic::catch_unwind(|| {
        let bytes = unsafe { std::slice::from_raw_parts(input, len) };
        let value = serde_json::from_slice(bytes)
            .map(|v| execute(&v))
            .unwrap_or_else(|e| json!({"error":e.to_string()}));
        let mut out = crate::station_json::pack_value(&value).into_boxed_slice();
        unsafe {
            *out_len = out.len();
        }
        let ptr = out.as_mut_ptr();
        std::mem::forget(out);
        ptr
    })
    .unwrap_or(ptr::null_mut())
}
#[no_mangle]
pub unsafe extern "C" fn rq_jma_tsunami_free(ptr: *mut u8, len: usize) {
    if !ptr.is_null() {
        unsafe {
            drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(ptr, len)));
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn serialized_quantity_from_reported_ui_field_is_a_height_not_display_text() {
        let field = "map[type:津波の高さ unit:m value:0.2]";
        assert_eq!(quantity_height(&json!(field)), Some(0.2));
        assert_eq!(compact_height(field), "0.2m");
        assert_eq!(
            quantity_height(&json!({"type":"津波の高さ","unit":"m","value":0.2})),
            Some(0.2)
        );
        for field in [
            "map[type:津波の高さ unit:cm value:20]",
            "map[type:津波の高さ unit:m value:NaN]",
            "map[type:津波の高さ unit:m value:-1]",
            "巨大",
            "0.2m未満",
        ] {
            assert_eq!(quantity_height(&json!(field)), None);
        }
    }
    #[test]
    fn quantity_shapes_keep_raw_payload_grade_arrival_and_both_list_projections() {
        // Protocol-shape cases using the exact field text reported in the UI;
        // these are not claimed to be captured complete live bulletins.
        for field in [
            json!("map[type:津波の高さ unit:m value:0.2]"),
            json!({"type":"津波の高さ","unit":"m","value":0.2}),
        ] {
            for transport in ["whews", "jian"] {
                for description_field in [false, true] {
                    let mut row = json!({"name":"千葉県九十九里・外房","kind":"津波予報","arrivalTime":"","condition":""});
                    if description_field {
                        row["maxHeight"] = json!(0.2);
                        row["maxHeightDesc"] = field.clone();
                    } else {
                        row["maxHeight"] = field.clone();
                    }
                    let raw = if transport == "jian" {
                        json!({"originTime":1793962380000i64,"area":[row]})
                    } else {
                        json!({"createTime":"2026-11-06 19:53:00","areas":[row]})
                    };
                    let before = raw.clone();
                    let parsed = parse(transport, &raw).unwrap();
                    assert_eq!(parsed["sourcePayload"], before);
                    assert_eq!(raw, before);
                    assert_eq!(parsed["areas"][0]["height"], 0.2);
                    assert_eq!(parsed["areas"][0]["grade"], "forecast");
                    assert_eq!(parsed["areas"][0]["arrivalTime"], "");
                    assert_eq!(
                        project(&parsed, 0)["groups"][0]["rows"][0]["height"],
                        "0.2m"
                    );
                }
            }
        }
        assert_eq!(compact_height("巨大"), "巨大");
        assert_eq!(compact_height("１０ｍ超"), "10m超");
        assert_eq!(compact_height("０．２ｍ未満"), "0.2m未満");
    }
    #[test]
    fn p2p_immediate_uses_existing_arrival_display_without_changing_raw_report() {
        // Protocol edge cases, not live tsunami observations.
        for first_height in [json!(null), json!({"condition":""})] {
            let raw = json!({"issue":{"time":"2026/10/19 12:00:00"},"areas":[{
                "name":"protocol region","grade":"Warning","immediate":true,
                "firstHeight":first_height,"maxHeight":{"value":3,"description":"３ｍ"}
            }]});
            let parsed = parse("p2p", &raw).unwrap();
            assert_eq!(parsed["sourcePayload"], raw);
            assert_eq!(parsed["areas"][0]["condition"], "ただちに津波来襲と予測");
            assert_eq!(parsed["areas"][0]["grade"], "warning");
            let view = project(&parsed, 0);
            assert_eq!(view["groups"][0]["rows"][0]["arrivalLabel"], "すぐ来る");
            assert_eq!(view["groups"][0]["rows"][0]["height"], "3m");
        }
    }
    #[test]
    fn p2p_immediate_preserves_explicit_conditions_and_arrival_times() {
        for immediate in [json!(true), json!(false), json!(null)] {
            for condition in ["", "津波到達中と推測", "第１波の到達を確認"] {
                let raw = json!({"issue":{"time":"2026/10/19 12:00:00"},"areas":[{
                    "name":"protocol region","grade":"Watch","immediate":immediate,
                    "firstHeight":{"condition":condition,"arrivalTime":"2026/10/19 12:10:00"}
                }]});
                let parsed = parse("p2p", &raw).unwrap();
                let expected = if condition.is_empty() && immediate == true {
                    "ただちに津波来襲と予測"
                } else {
                    condition
                };
                assert_eq!(parsed["areas"][0]["condition"], expected);
                assert_eq!(parsed["areas"][0]["arrivalTime"], "2026/10/19 12:10:00");
                assert_eq!(parsed["sourcePayload"], raw);
            }
        }
    }
    #[test]
    fn pagination_pairs_and_cycles_without_losing_regions() {
        let heights = (0..27).map(|_| json!(28)).collect::<Vec<_>>();
        let result =
            paginate(&json!({"itemHeights":heights,"unitHeight":76,"overhead":50,"rowGap":5}));
        assert_eq!(result["units"], 2);
        assert_eq!(result["intervalMs"], 12000);
        assert_eq!(result["pages"].as_array().unwrap().len(), 5);
        let mut all = Vec::new();
        for page in result["pages"].as_array().unwrap() {
            assert!(page["contentHeight"].as_f64().unwrap() <= 102.0);
            for line in page["lines"].as_array().unwrap() {
                let ids = line["indices"].as_array().unwrap();
                assert!(ids.len() <= 2);
                all.extend(ids.iter().map(|v| v.as_u64().unwrap()));
            }
        }
        assert_eq!(all, (0..27).collect::<Vec<_>>());
    }
    #[test]
    fn no_rotation_pages_when_content_fits() {
        let result =
            paginate(&json!({"itemHeights":[15,15],"unitHeight":76,"overhead":35,"rowGap":5}));
        assert_eq!(result["pages"].as_array().unwrap().len(), 1);
        assert_eq!(result["units"], 1);
        assert_eq!(arrival_label("津波到達中と推測"), "到達と推測");
        assert_eq!(arrival_label("ただちに津波来襲と予測"), "すぐ来る");
    }
    #[test]
    fn single_column_bulletins_keep_one_unit_and_do_not_drop_rows() {
        let view =
            paginate(&json!({"itemHeights":[26.4],"columns":1,"unitHeight":76,"overhead":41.6}));
        assert_eq!(view["units"], 1);
        assert_eq!(view["pages"][0]["lines"][0]["indices"], json!([0]));
        let info = paginate(
            &json!({"itemHeights":[80,80,80],"columns":1,"unitHeight":76,"overhead":20,"maxUnits":1}),
        );
        assert_eq!(info["units"], 1);
        assert_eq!(info["pages"].as_array().unwrap().len(), 3);
        assert_eq!(info["pages"][2]["lines"][0]["indices"], json!([2]));
    }
    #[test]
    fn kinds_and_qualitative_heights() {
        for (k, g) in [
            ("majorWarning", 4),
            ("warning", 3),
            ("watch", 2),
            ("forecast", 1),
            ("津波なし", 0),
        ] {
            assert_eq!(grade(k), g);
        }
        assert_eq!(compact_height("１０ｍ超"), "10m超");
        assert_eq!(compact_height("巨大"), "巨大");
        assert_eq!(compact_height("０．２ｍ未満"), "0.2m未満");
        assert_eq!(epoch(&json!(0)), "1970-01-01T00:00:00.000Z");
    }
}
