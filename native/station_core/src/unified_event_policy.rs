//! Unified event policy. Original DTO fields remain immutable; comparison
//! identities, deadlines and retained revisions belong to the native session.
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};

pub const SECOND: i64 = 1_000_000;
pub fn s<'a>(v: &'a Value, k: &str) -> &'a str {
    v[k].as_str().unwrap_or("")
}
pub fn b(v: &Value, k: &str) -> bool {
    v[k].as_bool().unwrap_or(false)
}
pub fn n(v: &Value, k: &str) -> f64 {
    number(&v[k]).unwrap_or(f64::NAN)
}
pub fn number(v: &Value) -> Option<f64> {
    v.as_f64().or_else(|| {
        v["$rqF64"]
            .as_str()
            .and_then(|v| u64::from_str_radix(v, 16).ok())
            .map(f64::from_bits)
    })
}
pub fn i(v: &Value, k: &str) -> i64 {
    v[k].as_i64().unwrap_or(0)
}
pub fn eqnum(a: &Value, b: &Value, k: &str) -> bool {
    if a[k].is_null() || b[k].is_null() {
        a[k] == b[k]
    } else {
        (n(a, k) - n(b, k)).abs() < 0.000001
    }
}
fn same_volcano_tree(a: &Value, b: &Value) -> bool {
    match (a, b) {
        (Value::Array(a), Value::Array(b)) => {
            a.len() == b.len() && a.iter().zip(b).all(|(a, b)| same_volcano_tree(a, b))
        }
        (Value::Object(a), Value::Object(b)) => {
            if a.len() != b.len() {
                return false;
            }
            if a.len() == 2 && a.contains_key("latitude") && a.contains_key("longitude") {
                return ["latitude", "longitude"].iter().all(|k| {
                    number(&a[*k])
                        .zip(number(&b[*k]))
                        .is_some_and(|(a, b)| (a - b).abs() < 0.000001)
                });
            }
            a.iter().all(|(k, a)| {
                b.get(k).is_some_and(|b| {
                    matches!(
                        k.as_str(),
                        "reportTime" | "targetTime" | "windTime" | "startTime" | "endTime"
                    ) || same_volcano_tree(a, b)
                })
            })
        }
        _ => a == b,
    }
}
fn same_volcano(a: &Value, b: &Value) -> bool {
    if a["$volcanoInstants"].is_null() || b["$volcanoInstants"].is_null() {
        a["volcanoEvent"] == b["volcanoEvent"]
    } else {
        a["$volcanoInstants"] == b["$volcanoInstants"]
            && same_volcano_tree(&a["volcanoEvent"], &b["volcanoEvent"])
    }
}
pub fn csis_level(m: f64, mut dep: f64) -> i64 {
    if m.is_nan() {
        return 0;
    }
    if dep.is_nan() || dep < 10.0 {
        dep = 10.0;
    }
    let earth = 6371.0_f64;
    let a = earth - dep;
    let line = (a * a + earth * earth - 2.0 * a * earth).sqrt();
    let length = 10_f64.powf((m - 3.821) / 1.86);
    let hypo = [line - 10.0 - length, -length, 0.2 * (line - 10.0), 0.0]
        .into_iter()
        .reduce(|a, b| if a > b { a } else { b })
        .unwrap();
    let cea = |d: f64| 1.297 * m - 4.368 * (d + 15.0).ln() / std::f64::consts::LN_10 + 5.363;
    let value = (cea(0.0) + cea(hypo)) / 2.0;
    if value.is_nan() {
        12
    } else {
        value.clamp(0.0, 12.0).round() as i64
    }
}
pub fn message_fields(e: &Value) -> Value {
    let text = s(e, "maxIntensity").trim().to_uppercase();
    let numeric = text
        .parse::<f64>()
        .ok()
        .or_else(|| {
            let t = text.strip_prefix("MMI").unwrap_or(&text).trim();
            [
                "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII",
            ]
            .iter()
            .position(|v| *v == t)
            .or_else(|| {
                ["Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ", "Ⅴ", "Ⅵ", "Ⅶ", "Ⅷ", "Ⅸ", "Ⅹ", "Ⅺ", "Ⅻ"]
                    .iter()
                    .position(|v| *v == t)
            })
            .map(|v| (v + 1) as f64)
        })
        .filter(|v| v.is_finite() && *v >= 0.0 && *v <= 12.0);
    let reviewed = review(e);
    let labels = format!("{} {}", s(e, "reportNumText"), s(e, "titleText")).to_lowercase();
    let cenc = if labels.contains("正式") || labels.contains("reviewed") {
        "正式测定"
    } else {
        "自动测定"
    };
    let info = if s(e, "apiTypeLabel") == "Jian Project"
        && !reviewed.is_empty()
        && !e["sourcePayload"]["infoTypeName"].is_null()
    {
        s(&e["sourcePayload"], "infoTypeName")
    } else {
        s(e, "titleText")
    };
    json!({"reportedIntensity":numeric.filter(|v|*v>0.0).map(|v|v.round() as i64),"fallbackIntensity":csis_level(n(e,"magnitude"),n(e,"depth")),"reviewType":if reviewed.is_empty(){Value::Null}else{json!(reviewed)},"cencReviewLabel":cenc,"cencReviewType":if cenc=="正式测定"{"reviewed"}else{"automatic"},"infoTypeName":info})
}
// Same derived Jian CEA effect as the existing badge. Source isWarn and the
// source intensity remain unchanged in the immutable event descriptor.
pub fn effective_warn(e: &Value) -> bool {
    if !b(e, "isEew")
        || s(e, "source") != "ceaEew"
        || s(e, "apiTypeLabel") != "Jian Project"
        || b(e, "isWarn")
    {
        return b(e, "isWarn");
    }
    let raw = &e["sourcePayload"];
    if b(e, "isCanceled")
        || b(e, "isAssumption")
        || b(e, "isHistory")
        || b(raw, "isTraining")
        || raw["isWarn"].is_boolean()
    {
        return false;
    }
    let text = s(e, "maxIntensity").trim();
    let value = if matches!(text, "" | "-")
        && !b(e, "useShindo")
        && !b(raw, "isCancel")
        && !b(raw, "cancel")
        && n(e, "magnitude").is_finite()
        && n(e, "magnitude") > 0.0
        && n(e, "depth").is_finite()
        && n(e, "depth") >= 0.0
    {
        if b(e, "$payloadAbsent") && b(e, "displayEstimateResolved") {
            s(e, "displayEstimatedIntensity")
                .parse::<i64>()
                .ok()
                .map(|v| v as f64)
        } else {
            Some(csis_level(n(e, "magnitude"), n(e, "depth")) as f64)
        }
    } else {
        text.parse::<f64>().ok()
    };
    value.is_some_and(|v| v.is_finite() && v >= 6.5 && v <= 12.0)
}
pub fn digits(v: &str) -> String {
    v.chars().filter(char::is_ascii_digit).collect()
}
pub fn report(v: &Value) -> i64 {
    first_number(s(v, "reportNumText")).unwrap_or(1)
}
pub fn first_number(v: &str) -> Option<i64> {
    let start = v.find(|c: char| c.is_ascii_digit())?;
    v[start..]
        .split(|c: char| !c.is_ascii_digit())
        .next()?
        .parse()
        .ok()
}
fn days(y: i64, m: i64, d: i64) -> i64 {
    let y = y - i64::from(m <= 2);
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let mp = m + if m > 2 { -3 } else { 9 };
    era * 146097 + yoe * 365 + yoe / 4 - yoe / 100 + (153 * mp + 2) / 5 + d - 1 - 719468
}
pub fn wall(v: &str) -> Option<i64> {
    let a = v.as_bytes();
    if a.len() < 19 {
        return None;
    }
    let part = |a: usize, b: usize| v.get(a..b)?.parse::<i64>().ok();
    let (y, m, d, h, mi, se) = (
        part(0, 4)?,
        part(5, 7)?,
        part(8, 10)?,
        part(11, 13)?,
        part(14, 16)?,
        part(17, 19)?,
    );
    let mut us = 0;
    let mut p = 20;
    if a.get(19) == Some(&b'.') {
        let mut factor = 100000;
        while p < a.len() && a[p].is_ascii_digit() {
            if factor > 0 {
                us += (a[p] - b'0') as i64 * factor;
                factor /= 10;
            }
            p += 1;
        }
    }
    Some((days(y, m, d) * 86400 + h * 3600 + mi * 60 + se) * SECOND + us)
}
pub fn absolute(v: &str, local_offset: i64) -> Option<i64> {
    let value = wall(v)?;
    if v.ends_with('Z') {
        return Some(value);
    }
    let rest = v.get(19..)?;
    let shift = rest.find(['+', '-']).and_then(|index| {
        let text = &rest[index..];
        let h = text.get(1..3)?.parse::<i64>().ok()?;
        let m = text.get(4..6)?.parse::<i64>().ok()?;
        Some((h * 60 + m) * 60 * SECOND * if text.starts_with('-') { -1 } else { 1 })
    });
    Some(value - shift.unwrap_or(local_offset * 60 * SECOND))
}
pub fn time(e: &Value, k: &str) -> Option<i64> {
    wall(s(e, k))
}
pub fn instant(e: &Value, k: &str) -> Option<i64> {
    time(e, k).map(|v| v - i(e, "timeZone") * 3600 * SECOND)
}

/// Renderer-only version of the existing CENC-IR binding contract: explicit ID
/// or <=1s origin plus <=0.011 degree coordinates; no place-name matching.
pub fn render_cenc_ir_index(c: &Value) -> Value {
    let event = &c["event"];
    if s(event, "source") != "cencEqlist" { return Value::Null; }
    let Some(reports) = c["reports"].as_array() else { return Value::Null; };
    let parse_num = |v: &Value| v.as_f64().or_else(|| v.as_str()?.parse::<f64>().ok());
    // Unified originTime carries source wall-clock components, as in
    // QuakeTime.eventInstantUtc; its serialized Z flag is not the source zone.
    let event_time = instant(event, "originTime");
    let mut best: Option<usize> = None;
    for (index, report) in reports.iter().enumerate() {
        let id_match = ["id", "reportId", "uniEventId"].iter().any(|key| {
            !report[*key].is_null() && (s(report, key) == s(event, "eventId") ||
                report[*key].as_i64().is_some_and(|id| id.to_string() == s(event, "eventId")))
        });
        let raw_time = report.get("oriTime").filter(|v| !v.is_null()).unwrap_or(&report["shockTime"]);
        let report_time = raw_time.as_str().and_then(|v| absolute(v, 8 * 60));
        if report_time.zip(event_time).is_some_and(|(a, b)| (a - b).abs() > SECOND) { continue; }
        let lat = parse_num(&report["epiLat"]);
        let lng = parse_num(&report["epiLon"]);
        let coordinates_match = lat.zip(lng).is_some_and(|(lat, lng)|
            (lat - n(event, "lat")).abs() <= 0.011 && (lng - n(event, "lng")).abs() <= 0.011);
        if lat.is_some() && lng.is_some() && !coordinates_match { continue; }
        if !id_match && !(report_time.is_some() && coordinates_match) { continue; }
        if best.is_none_or(|old| s(report, "gmtCreate") > s(&reports[old], "gmtCreate")) { best = Some(index); }
    }
    best.map_or(Value::Null, |index| json!(index))
}
pub fn review(e: &Value) -> &'static str {
    if b(e, "$historyRecord") {
        let text = format!("{} {}", s(e, "reviewType"), s(e, "titleText")).to_lowercase();
        return if text.contains("正式") || text.contains("reviewed") {
            "reviewed"
        } else if text.contains("自动") || text.contains("automatic") {
            "automatic"
        } else {
            ""
        };
    }
    let fields = [
        if s(e, "apiTypeLabel") == "Jian Project" {
            s(&e["sourcePayload"], "infoTypeName")
        } else {
            ""
        },
        "",
        s(e, "reportNumText"),
        s(e, "titleText"),
    ];
    let text = format!("{} {}", fields[0], format!("{} {}", fields[2], fields[3])).to_lowercase();
    // Source status has priority over display labels.
    for text in [
        fields[0].to_lowercase(),
        format!("{} {}", fields[2], fields[3]).to_lowercase(),
    ] {
        let word = |w: &str| {
            text.split(|c: char| !c.is_ascii_alphanumeric() && c != '_')
                .any(|p| p == w)
        };
        if text.contains("自动")
            || text.contains("待核实")
            || word("automatic")
            || word("unverified")
        {
            return "automatic";
        }
        if text.contains("正式") || text.contains("已核实") || word("reviewed") || word("confirmed")
        {
            return "reviewed";
        }
    }
    let _ = text;
    ""
}
pub fn catalog(source: &str) -> bool {
    matches!(
        source,
        "earlyEst"
            | "ipgp"
            | "infp"
            | "isc"
            | "knmi"
            | "ncedc"
            | "lmu"
            | "koeri"
            | "csn"
            | "igepn"
            | "whews_bmkg"
            | "whews_geonet"
            | "whews_tmd"
            | "whews_ingv"
            | "whews_nrcan"
            | "whews_mmd"
            | "whews_phivolcs"
            | "whews_sgc"
            | "whews_ga"
            | "whews_cenais"
            | "whews_gsras"
            | "whews_bgs"
            | "whews_ipma"
            | "whews_ssn"
            | "whews_afad"
            | "whews_sed"
            | "whews_noa"
            | "whews_scsn"
            | "whews_iag"
            | "whews_igp"
            | "whews_nepal"
            | "whews_funvisis"
    )
}
pub fn agency(source: &str) -> Option<&str> {
    if catalog(source) {
        Some(source)
    } else {
        match source {
            "usgsEqlist" | "kmaEqlist" | "cwaEqlist" => Some(source),
            "emsc" | "emscEqlist" => Some("emsc"),
            "hko" | "hkoEqlist" => Some("hko"),
            "bcsf" | "bcsfEqlist" => Some("bcsf"),
            "gfz" | "gfzEqlist" => Some("gfz"),
            "usp" | "uspEqlist" => Some("usp"),
            "geonet" => Some("whews_geonet"),
            _ => None,
        }
    }
}
pub fn no_update(source: &str) -> Option<&str> {
    match source {
        "hko" | "hkoEqlist" => Some("hko"),
        "emsc" | "emscEqlist" => Some("emsc"),
        "bcsf" | "bcsfEqlist" => Some("bcsf"),
        "gfz" | "gfzEqlist" => Some("gfz"),
        "usp" | "uspEqlist" => Some("usp"),
        "fssnCmt" | "cencCmt" | "usgsCmt" | "jmaCmt" | "fnetCmt" | "hinetAquaCmt" => Some(source),
        _ => None,
    }
}
pub fn slot(e: &Value) -> String {
    let source = s(e, "source");
    if b(e, "isEew") {
        source.into()
    } else {
        agency(source)
            .or_else(|| no_update(source))
            .unwrap_or(if source == "p2pJmaEqlist" {
                "jmaEqlist"
            } else {
                source
            })
            .into()
    }
}
/// Link a Japanese earthquake report with a separately sourced VXSE62.
/// The source event IDs remain untouched. An official ID match is preferred;
/// a non-official ID may match only with independent physical evidence.
pub fn jma_lpgm_same_event(info: &Value, bulletin: &Value) -> bool {
    if b(info, "isEew")
        || !matches!(s(info, "source"), "jmaEqlist" | "p2pJmaEqlist")
    {
        return false;
    }
    let id = s(info, "eventId").trim();
    let companion_id = s(bulletin, "eventId").trim();
    if !id.is_empty() && id == companion_id {
        return true;
    }
    // A 14-digit time-based transport identifier (YYYYMMDDHHMMSS) is not
    // always the official EventID. Only allow this exception when it exactly
    // equals the provided source-local origin timestamp.
    let official = |id: &str| {
        id.len() == 14 && id.bytes().all(|v| v.is_ascii_digit())
    };
    let origin_time_id = time(info, "originTime")
        .map(iso_utc)
        .map(|v| digits(&v[..19]))
        .unwrap_or_default();
    if official(id) && official(companion_id) && id != origin_time_id {
        return false;
    }

    // The bulletin timestamp is a real UTC instant from XML parsing, while
    // ordinary UnifiedQuakeData stores a source-local wall clock. Avoid
    // interpreting the bulletin UTC value as another JST wall clock.
    let (Some(a), Some(bulletin_time)) = (
        instant(info, "originTime"),
        bulletin["originEpochUs"].as_i64(),
    ) else { return false; };
    if (a - bulletin_time).abs() > 45 * SECOND {
        return false;
    }
    let (a_lat, a_lon, b_lat, b_lon) = (
        n(info, "lat"), n(info, "lng"),
        n(bulletin, "lat"), n(bulletin, "lng"),
    );
    if ![a_lat, a_lon, b_lat, b_lon].iter().all(|v| v.is_finite())
        || !(20.0..=50.0).contains(&a_lat)
        || !(20.0..=50.0).contains(&b_lat)
        || !(120.0..=155.0).contains(&a_lon)
        || !(120.0..=155.0).contains(&b_lon)
    {
        return false;
    }
    let radians = std::f64::consts::PI / 180.0;
    let north_km = (a_lat - b_lat).abs() * 111.2;
    let east_km = (a_lon - b_lon).abs() * 111.2
        * ((a_lat + b_lat) * 0.5 * radians).cos().abs();
    if north_km.hypot(east_km) > 18.0 {
        return false;
    }
    let (m, companion_m) = (n(info, "magnitude"), n(bulletin, "magnitude"));
    if !m.is_finite() || !companion_m.is_finite()
        || !(0.0..=10.0).contains(&m) || !(0.0..=10.0).contains(&companion_m)
        || (m - companion_m).abs() > 0.5
    {
        return false;
    }
    let (dep, companion_dep) = (n(info, "depth"), n(bulletin, "depth"));
    if !dep.is_finite() || !companion_dep.is_finite()
        || dep < 0.0 || companion_dep < 0.0
        || (dep - companion_dep).abs() > 30.0
    {
        return false;
    }
    true
}

pub fn catalog_id(source: &str, id: &str) -> String {
    if source == "cwaEqlist" {
        let numeric = |s: &str| s.bytes().all(|b| b.is_ascii_digit());
        if id.is_ascii() {
            if id.len() == 15 && &id[8..9] == "."
                && numeric(&id[..8]) && numeric(&id[9..]) {
                return format!("cwa|{}{}", &id[..8], &id[9..]);
            }
            let parts = id.split('-').collect::<Vec<_>>();
            if parts.len() == 4
                && parts.iter().zip([6, 4, 4, 6]).all(|(p, len)| p.len() == len && numeric(p)) {
                return format!("cwa|{}{}{}", parts[1], parts[2], parts[3]);
            }
            if let Some(epoch) = id.strip_prefix("cwa_") {
                if epoch.len() == 13 && numeric(epoch) {
                    if let Ok(ms) = epoch.parse::<i64>() {
                        let clock = iso_utc(ms * 1000 + 8 * 3600 * SECOND);
                        return format!("cwa|{}", digits(&clock[..19]));
                    }
                }
            }
        }
    }
    if source == "cencEqlist"
        && id.ends_with("_M")
        && (id.starts_with("CD.") || id.starts_with("CC."))
    {
        let parts = id[..id.len() - 2].split('.').collect::<Vec<_>>();
        if parts.len() == 3
            && parts[1].len() == 14
            && parts[1].chars().all(|v| v.is_ascii_digit())
            && parts[2].chars().all(|v| v.is_ascii_digit())
        {
            return id[..id.len() - 2].into();
        }
    }
    if source == "earlyEst" {
        if let Some(t) = id.strip_prefix("EARLY_event_") {
            if t.len() == 13 && t.chars().all(|v| v.is_ascii_digit()) {
                return t.into();
            }
        }
    }
    if source == "whews_gsras" {
        if let Some(t) = id.strip_prefix("gsras_") {
            if t.len() == 8 && t.chars().all(|v| v.is_ascii_digit()) {
                return t.into();
            }
        }
    }
    if source == "whews_ingv" {
        if let Ok(v) = id.parse::<f64>() {
            if v > 0.0 && v <= 9007199254740991.0 && v.trunc() == v {
                return format!("{v:.0}");
            }
        }
    }
    id.into()
}
pub fn eew_id(e: &Value) -> String {
    let original = s(e, "eventId").trim();
    if !b(e, "isEew") || s(e, "source") != "cwaEew" {
        return original.into();
    }
    let prefix = if s(e, "$replaySessionId").is_empty() {
        String::new()
    } else {
        format!("{}:", s(e, "$replaySessionId"))
    };
    let id = original.strip_prefix(&prefix).unwrap_or(original);
    let id = id.strip_prefix("cwa.gov.tw_earthquakeEW_").unwrap_or(id);
    if id.len() == 7 && id.chars().all(|v| v.is_ascii_digit()) {
        format!("{prefix}{id}")
    } else {
        original.into()
    }
}
pub fn observation(e: &Value) -> Option<String> {
    let a = agency(s(e, "source"))?;
    let t = instant(e, "originTime")?;
    let (lat, lng, depth) = (n(e, "lat"), n(e, "lng"), n(e, "depth"));
    if !lat.is_finite()
        || !lng.is_finite()
        || lat.abs() > 90.0
        || lng.abs() > 180.0
        || (lat == 0.0 && lng == 0.0)
        || !depth.is_finite()
        || depth < 0.0
    {
        return None;
    }
    Some(format!(
        "{a}|{}|{}|{}|{}",
        t / SECOND,
        fixed(lat, 3),
        fixed(lng, 3),
        if a == "whews_ga" {
            format!("{:.0}", depth.round())
        } else {
            fixed(depth, 1)
        }
    ))
}
pub fn cenc_obs(e: &Value) -> Option<String> {
    let t = instant(e, "originTime")?;
    let (lat, lng) = (n(e, "lat"), n(e, "lng"));
    if !lat.is_finite()
        || !lng.is_finite()
        || lat.abs() > 90.0
        || lng.abs() > 180.0
        || (lat == 0.0 && lng == 0.0)
    {
        return None;
    }
    Some(format!(
        "cencEqlist|observation|{t}|{}|{}",
        dart_double(lat),
        dart_double(lng)
    ))
}
pub fn dart_double(v: f64) -> String {
    if v.is_nan() {
        "NaN".into()
    } else if v == f64::INFINITY {
        "Infinity".into()
    } else if v == f64::NEG_INFINITY {
        "-Infinity".into()
    } else {
        let text = format!("{v:?}");
        let Some((mantissa, exponent)) = text.split_once('e') else {
            return text;
        };
        let exponent = exponent.parse::<i32>().unwrap();
        if v.abs() < 1e-6 || v.abs() >= 1e21 {
            return format!(
                "{mantissa}e{}{exponent}",
                if exponent >= 0 { "+" } else { "" }
            );
        }
        let sign = if v.is_sign_negative() { "-" } else { "" };
        let mantissa = mantissa.trim_start_matches('-');
        let decimal = mantissa.find('.').unwrap_or(mantissa.len()) as i32 + exponent;
        let digits = mantissa.replace('.', "");
        if decimal <= 0 {
            format!("{sign}0.{}{digits}", "0".repeat((-decimal) as usize))
        } else if decimal >= digits.len() as i32 {
            format!(
                "{sign}{digits}{}.0",
                "0".repeat(decimal as usize - digits.len())
            )
        } else {
            format!(
                "{sign}{}.{}",
                &digits[..decimal as usize],
                &digits[decimal as usize..]
            )
        }
    }
}

// Dart toStringAsFixed rounds the exact binary value halfway away from zero.
// Rust's fixed formatter uses ties-to-even, which changes persisted dedupe keys.
pub fn fixed(v: f64, places: u32) -> String {
    if !v.is_finite() || v.abs() >= 1e21 {
        return dart_double(v);
    }
    let bits = v.abs().to_bits();
    let exp = ((bits >> 52) & 0x7ff) as i32;
    let significand = (bits & ((1_u64 << 52) - 1)) | if exp == 0 { 0 } else { 1_u64 << 52 };
    let shift = if exp == 0 { -1074 } else { exp - 1023 - 52 };
    let scaled = significand as u128 * 10_u128.pow(places);
    let rounded = if shift >= 0 {
        scaled << shift
    } else {
        let shift = (-shift) as u32;
        if shift >= 128 {
            0
        } else {
            let unit = 1_u128 << shift;
            (scaled >> shift) + u128::from(scaled & (unit - 1) >= unit / 2)
        }
    };
    let sign = if v.is_sign_negative() { "-" } else { "" };
    if places == 0 {
        return format!("{sign}{rounded}");
    }
    let scale = 10_u128.pow(places);
    format!(
        "{sign}{}.{:0width$}",
        rounded / scale,
        rounded % scale,
        width = places as usize
    )
}

pub fn iso_utc(us: i64) -> String {
    let seconds = us.div_euclid(SECOND);
    let day = seconds.div_euclid(86400);
    let clock = seconds.rem_euclid(86400);
    let z = day + 719468;
    let era = z.div_euclid(146097);
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = mp + if mp < 10 { 3 } else { -9 };
    let y = y + i64::from(m <= 2);
    let fraction = us.rem_euclid(SECOND);
    format!(
        "{y:04}-{m:02}-{d:02}T{:02}:{:02}:{:02}.{}Z",
        clock / 3600,
        clock / 60 % 60,
        clock % 60,
        if fraction % 1000 == 0 {
            format!("{:03}", fraction / 1000)
        } else {
            format!("{fraction:06}")
        }
    )
}

#[derive(Default)]
pub struct Times {
    pub values: HashMap<String, i64>,
    pub order: Vec<String>,
    pub decoded: HashMap<String, Value>,
}
impl Times {
    pub fn put(&mut self, key: String, stamp: i64) {
        if !self.values.contains_key(&key) {
            self.order.push(key.clone());
            if let Some(p) = key.find('{') {
                if let Ok(v) = serde_json::from_str(&key[p..]) {
                    self.decoded.insert(key.clone(), v);
                }
            }
        }
        self.values.insert(key, stamp);
    }
    pub fn prune(&mut self, now: i64, ttl: i64, max: usize) {
        self.values.retain(|_, v| now - *v <= ttl);
        if self.values.len() > max {
            let mut entries = self
                .order
                .iter()
                .filter_map(|k| self.values.get(k).map(|v| (k.clone(), *v)))
                .collect::<Vec<_>>();
            entries.sort_by_key(|v| v.1);
            for (k, _) in entries.into_iter().take(self.values.len() - max) {
                self.values.remove(&k);
            }
        }
        self.order.retain(|k| self.values.contains_key(k));
        self.decoded.retain(|k, _| self.values.contains_key(k));
    }
    pub fn import(&mut self, rows: &Value) {
        if let Some(rows) = rows.as_array() {
            for row in rows {
                if let (Some(k), Some(t)) = (row[0].as_str(), row[1].as_i64()) {
                    self.put(
                        k.into(),
                        self.values.get(k).copied().unwrap_or(i64::MIN).max(t),
                    );
                }
            }
        }
    }
}

#[derive(Default)]
pub struct Identity {
    pub seen: Times,
    pub aliases: HashMap<String, String>,
    alias_order: Vec<String>,
}
impl Identity {
    fn scope(e: &Value) -> String {
        format!("{}|{}|", s(e, "$replaySessionId"), s(e, "source"))
    }
    pub fn eew(&self, e: &Value) -> String {
        let id = eew_id(e);
        self.aliases
            .get(&format!("{}{id}", Self::scope(e)))
            .cloned()
            .unwrap_or(id)
    }
    pub fn same_eew(&mut self, a: &Value, bv: &Value) -> bool {
        if s(a, "$replaySessionId") != s(bv, "$replaySessionId")
            || !b(a, "isEew")
            || !b(bv, "isEew")
            || s(a, "source") != s(bv, "source")
        {
            return false;
        }
        let (x, y) = (self.eew(a), self.eew(bv));
        if !x.is_empty() && !y.is_empty() && x == y {
            return true;
        }
        let token = |id: &str| {
            let bytes = id.as_bytes();
            (0..bytes.len().saturating_sub(13)).find_map(|j| {
                let v = std::str::from_utf8(&bytes[j..j + 14]).ok()?;
                if (v.starts_with("19") || v.starts_with("20"))
                    && v.bytes().all(|v| v.is_ascii_digit())
                {
                    Some(v.to_owned())
                } else {
                    None
                }
            })
        };
        if let (Some(x), Some(y)) = (token(&x), token(&y)) {
            if x != y {
                return false;
            }
        }
        if let (Some(x), Some(y)) = (time(a, "originTime"), time(bv, "originTime")) {
            if ((x - y) / SECOND).abs() > 2 {
                return false;
            }
        } else {
            return false;
        }
        if ["lat", "lng"]
            .iter()
            .any(|k| a[*k].is_null() || bv[*k].is_null())
        {
            return true;
        }
        if (n(a, "lat") == 0.0 && n(a, "lng") == 0.0)
            || (n(bv, "lat") == 0.0 && n(bv, "lng") == 0.0)
        {
            return true;
        }
        let matches = (n(a, "lat") - n(bv, "lat")).abs() <= 0.05
            && (n(a, "lng") - n(bv, "lng")).abs() <= 0.05;
        if matches {
            self.remember_alias(a, bv, false);
        }
        matches
    }
    pub fn remember_alias(&mut self, a: &Value, bv: &Value, saved: bool) {
        if !saved
            && (instant(a, "originTime").is_none()
                || instant(a, "originTime") != instant(bv, "originTime")
                || a["lat"].is_null()
                || a["lng"].is_null()
                || n(a, "lat") != n(bv, "lat")
                || n(a, "lng") != n(bv, "lng")
                || !n(a, "magnitude").is_finite()
                || n(a, "magnitude") <= 0.0
                || n(a, "magnitude") != n(bv, "magnitude")
                || (n(a, "depth") >= 0.0
                    && n(bv, "depth") >= 0.0
                    && n(a, "depth") != n(bv, "depth")))
        {
            return;
        }
        let old = eew_id(a);
        let new = eew_id(bv);
        if old.is_empty() || new.is_empty() {
            return;
        }
        let root = self.eew(a);
        let other = self.eew(bv);
        if root == other {
            return;
        }
        let scope = Self::scope(a);
        for (k, v) in &mut self.aliases {
            if k.starts_with(&scope) && *v == other {
                *v = root.clone();
            }
        }
        for id in [old, new] {
            let key = format!("{scope}{id}");
            if !self.aliases.contains_key(&key) {
                self.alias_order.push(key.clone());
            }
            self.aliases.insert(key, root.clone());
        }
        while self.alias_order.len() > 256 {
            self.aliases.remove(&self.alias_order.remove(0));
        }
    }
    pub fn canonical(&self, e: &Value) -> String {
        if b(e, "isEew") {
            return self.eew(e);
        }
        let source = s(e, "source");
        if slot(e) == "jmaEqlist" {
            if let Some(t) = e["originTime"].as_str() {
                let d = digits(t.get(..19).unwrap_or(t));
                return d;
            }
            let d = digits(s(e, "eventId"));
            if d.len() >= 12 {
                return d;
            }
        }
        let raw = catalog_id(source, s(e, "eventId"));
        if source == "cencEqlist" {
            if let Some(obs) = cenc_obs(e) {
                let mut matched = None;
                let mut precision = HashSet::new();
                let incoming = cenc_precision(e);
                for key in &self.seen.order {
                    if !key.starts_with("cencEqlist|identity-v1|") {
                        continue;
                    }
                    let Some(old) = self.seen.decoded.get(key) else {
                        continue;
                    };
                    if !raw.is_empty() && catalog_id(source, s(old, "id")) == raw {
                        return s(old, "identity").into();
                    }
                    if s(old, "observation") == obs && matched.is_none() {
                        matched = Some(s(old, "identity").to_owned());
                    }
                    if let Some((ref r, m)) = incoming {
                        if s(old, "precisionReport") == *r
                            && old["minutePrecision"].as_bool().is_some_and(|v| v != m)
                        {
                            precision.insert(s(old, "identity").to_owned());
                        }
                    }
                }
                return matched
                    .or_else(|| {
                        if precision.len() == 1 {
                            precision.into_iter().next()
                        } else {
                            None
                        }
                    })
                    .unwrap_or(obs);
            }
        }
        if let Some(obs) = observation(e) {
            let mut matched = None;
            let api = format!("{}|{}", i(e, "origin"), s(e, "apiTypeLabel"));
            for key in &self.seen.order {
                if !key.starts_with("catalog|agency-identity-v1|") {
                    continue;
                }
                let Some(old) = self.seen.decoded.get(key) else {
                    continue;
                };
                if s(old, "source") != agency(source).unwrap_or("") {
                    continue;
                }
                if !raw.is_empty()
                    && catalog_id(source, s(old, "id")) == raw
                    && (s(old, "api") == api || source == "earlyEst")
                {
                    return catalog_id(source, s(old, "identity"));
                }
                if s(old, "observation") == obs && matched.is_none() {
                    matched = Some(s(old, "identity").to_owned());
                }
            }
            if let Some(m) = matched {
                return m;
            }
            if raw.is_empty() {
                return obs;
            }
        }
        if let Some(incoming) = ga_report(e) {
            let mut first: Option<(&Value, i64)> = None;
            for key in &self.seen.order {
                if !key.starts_with("whews_ga|cross-api-v1|") {
                    continue;
                }
                let Some(old) = self.seen.decoded.get(key) else {
                    continue;
                };
                if (old["id"] == incoming["id"] && old["api"] == incoming["api"])
                    || (old["api"] != incoming["api"]
                        && old["observation"] == incoming["observation"])
                {
                    let t = self.seen.values[key];
                    if first.is_none_or(|(_, v)| t < v) {
                        first = Some((old, t));
                    }
                }
            }
            return format!(
                "ga-cross-api|{}",
                first
                    .map(|(v, _)| s(v, "identity"))
                    .unwrap_or(s(&incoming, "identity"))
            );
        }
        raw
    }
    pub fn key(&self, e: &Value) -> String {
        format!(
            "{}|{}",
            if s(e, "$replaySessionId").is_empty() {
                slot(e)
            } else {
                s(e, "source").into()
            },
            self.canonical(e)
        )
    }
    pub fn same_info(&self, a: &Value, bv: &Value) -> bool {
        !b(a, "isEew")
            && !b(bv, "isEew")
            && slot(a) == slot(bv)
            && !self.canonical(a).trim().is_empty()
            && self.canonical(a).trim() == self.canonical(bv).trim()
    }
    pub fn same_body(&self, a: &Value, bv: &Value) -> bool {
        self.canonical(a) == self.canonical(bv)
            && review(a) == review(bv)
            && [
                "titleText",
                "reportNumText",
                "hypocenter",
                "maxIntensity",
                "className",
                "warnArea",
                "isWarn",
                "isFinal",
                "isAssumption",
                "isCanceled",
                "nodalPlane1",
                "nodalPlane2",
                "momentTensor",
                "cmtMetadata",
            ]
            .iter()
            .all(|k| a[*k] == bv[*k])
            && same_volcano(a, bv)
            && ["lat", "lng", "depth", "magnitude", "centroidDepth"]
                .iter()
                .all(|k| eqnum(a, bv, k))
            && instant(a, "originTime").unwrap_or(0) == instant(bv, "originTime").unwrap_or(0)
    }
    pub fn same_revision(&mut self, a: &Value, bv: &Value) -> bool {
        if !self.same_eew(a, bv) {
            return false;
        }
        if cancellation_transition(a, bv) {
            return true;
        }
        if report(a) != report(bv) || self.same_body(a, bv) {
            return false;
        }
        if s(a, "source") == "ceaEew"
            && s(bv, "source") == "ceaEew"
            && s(a, "apiTypeLabel") == "Jian Project"
            && s(bv, "apiTypeLabel") == "Jian Project"
            && i(a, "origin") == i(bv, "origin")
            && !b(bv, "isSnapshot")
            && !b(bv, "isHistory")
            && !b(a, "isCanceled")
            && !b(bv, "isCanceled")
            && !b(&bv["sourcePayload"], "isTraining")
        {
            if let (Some(x), Some(y)) = (instant(a, "reportTime"), instant(bv, "reportTime")) {
                if y > x {
                    return true;
                }
            } else if s(a, "maxIntensity").parse::<f64>().is_err()
                && s(bv, "maxIntensity")
                    .parse::<f64>()
                    .ok()
                    .is_some_and(|v| v.is_finite() && (0.0..=12.0).contains(&v))
                && instant(a, "originTime").is_some()
                && instant(a, "originTime") == instant(bv, "originTime")
                && ["lat", "lng", "magnitude", "depth"]
                    .iter()
                    .all(|k| a[*k] == bv[*k])
            {
                return true;
            }
        }
        if !b(a, "hasReportSequence") && !b(bv, "hasReportSequence") {
            return !b(bv, "isSnapshot") && a["origin"] == bv["origin"];
        }
        i(bv, "origin") == 3
            && time(a, "reportTime")
                .zip(time(bv, "reportTime"))
                .is_some_and(|(a, b)| b >= a)
    }
    pub fn merge(&self, a: &Value, bv: &Value) -> Value {
        if !self.same_info(a, bv) {
            return bv.clone();
        }
        let mut result = bv.clone();
        if agency(s(bv, "source")).is_none() && s(bv, "source") != "cencEqlist" {
            result["eventId"] = a["eventId"].clone();
        }
        let rank = |t: &str| {
            if t.contains("各地の震度") {
                4
            } else if t.contains("震度・震源") || t.contains("震源・震度") {
                3
            } else if t.contains("震源") {
                2
            } else if t.contains("震度速報") {
                1
            } else {
                0
            }
        };
        if rank(s(bv, "titleText")) < rank(s(a, "titleText")) {
            result["titleText"] = a["titleText"].clone();
        }
        let known = |e: &Value| !matches!(s(e, "maxIntensity").trim(), "" | "-" | "?" | "不明");
        if !known(bv) && known(a) {
            for k in ["maxIntensity", "className"] {
                result[k] = a[k].clone();
            }
        }
        for k in [
            "titleText",
            "reportNumText",
            "hypocenter",
            "depthText",
            "warnArea",
            "apiTypeLabel",
        ] {
            if s(bv, k).trim().is_empty()
                && !s(a, k).trim().is_empty()
                && !(k == "reportNumText" && i(bv, "origin") == 2)
                && !(k == "warnArea" && b(bv, "isCanceled"))
            {
                result[k] = a[k].clone();
            }
        }
        for k in [
            "lat",
            "lng",
            "centroidDepth",
            "momentTensor",
            "cmtMetadata",
            "volcanoEvent",
        ] {
            if bv[k].is_null() && !a[k].is_null() {
                result[k] = a[k].clone();
            }
        }
        let hypo = |e: &Value| {
            let t = s(e, "hypocenter").trim();
            !t.is_empty()
                && !t.contains("調査中")
                && !t.contains("调查中")
                && !e["lat"].is_null()
                && !e["lng"].is_null()
        };
        if !hypo(bv) && hypo(a) {
            for k in ["hypocenter", "lat", "lng"] {
                result[k] = a[k].clone();
            }
        }
        for k in ["magnitude", "depth"] {
            if n(bv, k) < 0.0 && n(a, k) >= 0.0 {
                result[k] = a[k].clone();
                if k == "depth" {
                    result["depthText"] = a["depthText"].clone();
                }
            }
        }
        result
    }
}
pub fn cancellation_transition(a: &Value, bv: &Value) -> bool {
    b(a, "isEew")
        && b(bv, "isEew")
        && !b(a, "isCanceled")
        && b(bv, "isCanceled")
        && s(a, "source") == s(bv, "source")
        && instant(a, "reportTime")
            .zip(instant(bv, "reportTime"))
            .is_none_or(|(a, b)| b >= a)
}
pub fn cenc_precision(e: &Value) -> Option<(String, bool)> {
    if review(e) != "reviewed" || s(e, "hypocenter").is_empty() {
        return None;
    }
    let t = instant(e, "originTime")?;
    for k in ["lat", "lng", "magnitude", "depth"] {
        if !n(e, k).is_finite() {
            return None;
        }
    }
    if n(e, "magnitude") < 0.0
        || n(e, "depth") < 0.0
        || (n(e, "lat") == 0.0 && n(e, "lng") == 0.0)
        || n(e, "lat").abs() > 90.0
        || n(e, "lng").abs() > 180.0
    {
        return None;
    }
    let id = s(e, "eventId");
    let minute = s(e, "apiTypeLabel") == "Jian Project"
        && id.starts_with("CD.")
        && id.ends_with("_M")
        && t.rem_euclid(60 * SECOND) == 0;
    if !minute {
        let parts = id.split('.').collect::<Vec<_>>();
        let wall_id = digits(s(e, "originTime").get(..19).unwrap_or(""));
        if !matches!(s(e, "apiTypeLabel"), "Wolfx" | "FAN" | "WHEWS")
            || parts.len() != 3
            || parts[0] != "AU"
            || parts[1] != wall_id
            || t.rem_euclid(60 * SECOND) == 0
        {
            return None;
        }
    }
    Some((
        serde_json::to_string(&json!([
            t / (60 * SECOND),
            n(e, "lat"),
            n(e, "lng"),
            n(e, "magnitude"),
            n(e, "depth"),
            s(e, "hypocenter"),
            review(e)
        ]))
        .unwrap(),
        minute,
    ))
}
pub fn cenc_order(a: &Value, bv: &Value) -> Option<i32> {
    if s(a, "source") != "cencEqlist"
        || s(bv, "source") != "cencEqlist"
        || b(a, "isEew")
        || b(bv, "isEew")
        || ["lat", "lng", "magnitude", "depth"]
            .iter()
            .any(|k| n(a, k) != n(bv, k))
    {
        return None;
    }
    let ta = instant(a, "originTime")?;
    let tb = instant(bv, "originTime")?;
    let id = catalog_id("cencEqlist", s(a, "eventId"));
    if id != catalog_id("cencEqlist", s(bv, "eventId"))
        || !(id.starts_with("CD.") || id.starts_with("CC."))
    {
        let (x, y) = (cenc_precision(a)?, cenc_precision(bv)?);
        return if x.0 == y.0 && x.1 != y.1 {
            Some(if x.1 { 1 } else { -1 })
        } else {
            None
        };
    }
    if review(a) != review(bv) || ta / (60 * SECOND) != tb / (60 * SECOND) {
        return None;
    }
    let minute = |e: &Value| {
        s(e, "apiTypeLabel") == "Jian Project"
            && s(e, "eventId").ends_with("_M")
            && time(e, "originTime").is_some_and(|v| v % (60 * SECOND) == 0)
    };
    if minute(a) && s(bv, "eventId") == id && tb % (60 * SECOND) != 0 {
        Some(1)
    } else if minute(bv) && s(a, "eventId") == id && ta % (60 * SECOND) != 0 {
        Some(-1)
    } else {
        None
    }
}
pub fn ga_report(e: &Value) -> Option<Value> {
    if s(e, "source") != "whews_ga" || b(e, "isEew") {
        return None;
    }
    let id = s(e, "eventId");
    let api = s(e, "apiTypeLabel");
    let valid = match api {
        "WHEWS" => {
            id.starts_with("ga")
                && id.len() > 6
                && id[2..6].bytes().all(|v| v.is_ascii_digit())
                && id[6..].bytes().all(|v| v.is_ascii_lowercase())
        }
        "Jian Project" => {
            let parts = id.split('_').collect::<Vec<_>>();
            let pattern = |v: &str, shape: &str| {
                v.len() == shape.len()
                    && v.bytes().zip(shape.bytes()).all(|(a, b)| {
                        if b == b'd' {
                            a.is_ascii_digit()
                        } else {
                            a == b
                        }
                    })
            };
            let coordinate = |v: &str| {
                let text = v.strip_prefix('-').unwrap_or(v);
                let parts = text.split('.').collect::<Vec<_>>();
                (1..=2).contains(&parts.len())
                    && parts
                        .iter()
                        .all(|p| !p.is_empty() && p.bytes().all(|c| c.is_ascii_digit()))
            };
            parts.len() == 5
                && parts[0] == "ga"
                && pattern(parts[1], "dddd-dd-dd")
                && pattern(parts[2], "dd:dd:dd")
                && coordinate(parts[3])
                && coordinate(parts[4])
        }
        _ => false,
    };
    if !valid {
        return None;
    }
    observation(e)?;
    let t = instant(e, "originTime")?;
    let observation = format!(
        "{t}|{}|{}|{}|{:.0}",
        fixed(n(e, "lat"), 3),
        fixed(n(e, "lng"), 3),
        dart_double(n(e, "magnitude")),
        n(e, "depth").round()
    );
    Some(
        json!({"observation":observation,"identity":id,"id":id,"api":api,"review":review(e),"state":serde_json::to_string(&json!([intensity(s(e,"maxIntensity")),b(e,"isCanceled"),b(e,"isWarn"),b(e,"isFinal"),s(e,"warnArea")])).unwrap()}),
    )
}
pub fn intensity(v: &str) -> String {
    v.parse::<f64>().map(dart_double).unwrap_or(v.into())
}

impl Identity {
    fn exact_report(&self, e: &Value) -> Option<String> {
        let source = s(e, "source");
        if b(e, "isEew") {
            return None;
        }
        if source == "cencEqlist" {
            let obs = cenc_obs(e)?;
            if !n(e, "magnitude").is_finite()
                || n(e, "magnitude") < 0.0
                || !n(e, "depth").is_finite()
                || n(e, "depth") < 0.0
            {
                return None;
            }
            return Some(format!(
                "{obs}|report|{}|{}|{}|{}",
                dart_double(n(e, "magnitude")),
                dart_double(n(e, "depth")),
                review(e),
                b(e, "isCanceled")
            ));
        }
        if !catalog(source) || !n(e, "magnitude").is_finite() || n(e, "magnitude") < 0.0 {
            return None;
        }
        observation(e)?;
        let t = instant(e, "originTime")?;
        Some(format!(
            "{source}|observation|{t}|{}|{}|{}|{}|report|{}|{}|{}|{}|{}|{}",
            dart_double(n(e, "lat")),
            dart_double(n(e, "lng")),
            dart_double(n(e, "magnitude")),
            dart_double(n(e, "depth")),
            intensity(s(e, "maxIntensity")),
            review(e),
            b(e, "isCanceled"),
            b(e, "isWarn"),
            b(e, "isFinal"),
            s(e, "warnArea")
        ))
    }
    fn agency_report(&self, e: &Value) -> Option<String> {
        if b(e, "isEew")
            || !s(e, "$replaySessionId").is_empty()
            || !e["volcanoEvent"].is_null()
            || !n(e, "magnitude").is_finite()
        {
            return None;
        }
        observation(e)?;
        Some(format!(
            "catalog|agency-report-v1|{}",
            serde_json::to_string(&json!([
                agency(s(e, "source"))?,
                self.canonical(e),
                instant(e, "originTime")?,
                e["lat"],
                e["lng"],
                e["depth"],
                e["magnitude"],
                intensity(s(e, "maxIntensity")),
                review(e),
                b(e, "isCanceled"),
                b(e, "isWarn"),
                b(e, "isFinal"),
                s(e, "warnArea")
            ]))
            .unwrap()
        ))
    }
    pub fn seen_report(&self, e: &Value) -> bool {
        if self
            .agency_report(e)
            .is_some_and(|v| self.seen.values.contains_key(&v))
            || self
                .exact_report(e)
                .is_some_and(|v| self.seen.values.contains_key(&v))
        {
            return true;
        }
        let Some(incoming) = ga_report(e) else {
            return false;
        };
        let mut matched = false;
        for key in &self.seen.order {
            if !key.starts_with("whews_ga|cross-api-v1|") {
                continue;
            }
            let Some(old) = self.seen.decoded.get(key) else {
                continue;
            };
            if old["api"] == incoming["api"]
                && old["id"] == incoming["id"]
                && old["exact"] != self.exact_report(e).map_or(Value::Null, Value::String)
            {
                return false;
            }
            if old["api"] != incoming["api"]
                && old["observation"] == incoming["observation"]
                && old["state"] == incoming["state"]
                && (old["review"] == incoming["review"]
                    || s(old, "review").is_empty()
                    || s(&incoming, "review").is_empty())
            {
                matched = true;
            }
        }
        matched
    }
    pub fn unseen_review(&self, e: &Value) -> bool {
        if review(e) != "reviewed" {
            return false;
        }
        let Some(a) = agency(s(e, "source")) else {
            return false;
        };
        let id = self.canonical(e);
        let mut automatic = false;
        for key in &self.seen.order {
            let Some(raw) = key.strip_prefix("catalog|agency-report-v1|") else {
                continue;
            };
            let Ok(v) = serde_json::from_str::<Value>(raw) else {
                continue;
            };
            if v[0] != a || v[1] != id {
                continue;
            }
            if v[8] == "reviewed" {
                return false;
            }
            if v[8] == "automatic" {
                automatic = true;
            }
        }
        automatic
    }
    pub fn remember(&mut self, e: &Value, now: i64) {
        let id = self.canonical(e);
        let mut keys = vec![self.key(e)];
        if !b(e, "isEew") && s(e, "$replaySessionId").is_empty() && e["volcanoEvent"].is_null() {
            if let Some(obs) = observation(e) {
                let a = agency(s(e, "source")).unwrap();
                keys.push(format!("catalog|agency-identity-v1|{a}|{}",serde_json::to_string(&json!({"source":a,"id":catalog_id(s(e,"source"),s(e,"eventId")),"api":format!("{}|{}",i(e,"origin"),s(e,"apiTypeLabel")),"observation":obs,"identity":id})).unwrap()));
                if let Some(key) = self.agency_report(e) {
                    keys.push(key);
                }
            }
        }
        if let Some(key) = self.exact_report(e) {
            keys.push(key);
        }
        if s(e, "source") == "cencEqlist" && !b(e, "isEew") && !s(e, "eventId").trim().is_empty() {
            if let Some(obs) = cenc_obs(e) {
                let mut row = json!({"id":s(e,"eventId"),"api":s(e,"apiTypeLabel"),"observation":obs,"identity":id});
                if let Some((r, m)) = cenc_precision(e) {
                    row["precisionReport"] = json!(r);
                    row["minutePrecision"] = json!(m);
                }
                keys.push(format!(
                    "cencEqlist|identity-v1|{}",
                    serde_json::to_string(&row).unwrap()
                ));
            }
        }
        if let Some(mut ga) = ga_report(e) {
            ga["identity"] = json!(id.strip_prefix("ga-cross-api|").unwrap_or(&id));
            ga["exact"] = self.exact_report(e).map_or(Value::Null, Value::String);
            keys.push(format!(
                "whews_ga|cross-api-v1|{}",
                serde_json::to_string(&ga).unwrap()
            ));
        }
        for key in keys {
            self.seen.put(key, now);
        }
        self.seen.prune(now, 48 * 3600 * SECOND, 1000);
    }
}
pub fn no_update_key(id: &Identity, e: &Value) -> Option<String> {
    if b(e, "isEew") || i(e, "origin") == 3 {
        return None;
    }
    let source = no_update(s(e, "source"))?;
    let canonical = id.canonical(e);
    if canonical.trim().is_empty() {
        None
    } else {
        Some(format!("{source}|{}", canonical.trim()))
    }
}
pub fn body_cache_key(e: &Value) -> Option<String> {
    let source = s(e, "source");
    if !matches!(source, "usgsEqlist" | "emsc" | "emscEqlist" | "cwaEqlist") {
        return None;
    }
    let mut fields = vec![
        s(e, "eventId").to_owned(),
        s(e, "titleText").to_owned(),
        s(e, "hypocenter").to_owned(),
        if e["lat"].is_null() {
            String::new()
        } else {
            fixed(n(e, "lat"), 6)
        },
        if e["lng"].is_null() {
            String::new()
        } else {
            fixed(n(e, "lng"), 6)
        },
        fixed(n(e, "depth"), 3),
        fixed(n(e, "magnitude"), 3),
        s(e, "maxIntensity").to_owned(),
    ];
    if matches!(source, "usgsEqlist" | "cwaEqlist") {
        fields.push(review(e).into());
    }
    // Native comparison stores the exact UTC instant, rather than repeatedly
    // formatting ISO strings. Imported legacy cache rows are normalized once.
    fields.push(iso_utc(instant(e, "originTime").unwrap_or(0)));
    if source == "cwaEqlist" {
        fields.push(s(e, "warnArea").into());
    }
    Some(fields.join("|"))
}
pub fn observed_revision(a: &Value, bv: &Value) -> bool {
    if b(a, "isEew")
        || b(bv, "isEew")
        || b(bv, "isCanceled")
        || s(a, "source") != "cwaEqlist"
        || s(a, "source") != s(bv, "source")
        || s(a, "eventId").is_empty()
        || s(a, "eventId") != s(bv, "eventId")
        || [
            "origin",
            "originTime",
            "reportTime",
            "lat",
            "lng",
            "depth",
            "magnitude",
        ]
        .iter()
        .any(|k| a[*k] != bv[*k])
        || a["warnArea"] == bv["warnArea"]
    {
        return false;
    }
    let Ok(rows) = serde_json::from_str::<Value>(s(bv, "warnArea")) else {
        return false;
    };
    rows.as_array().is_some_and(|rows| {
        rows.iter().any(|r| {
            if s(r, "kind") != "observed" {
                return false;
            }
            let name = s(r, "name").trim();
            let name = match name {
                "台北市" => "臺北市",
                "台中市" => "臺中市",
                "台南市" => "臺南市",
                "宜兰县" => "宜蘭縣",
                "桃园市" => "桃園市",
                "嘉义市" => "嘉義市",
                "新竹县" => "新竹縣",
                "苗栗县" => "苗栗縣",
                "南投县" => "南投縣",
                "彰化县" => "彰化縣",
                "云林县" => "雲林縣",
                "嘉义县" => "嘉義縣",
                "屏东县" => "屏東縣",
                "花莲县" => "花蓮縣",
                "台东县" => "臺東縣",
                "澎湖县" => "澎湖縣",
                "金门县" => "金門縣",
                "连江县" => "連江縣",
                _ => name,
            };
            if ![
                "高雄市",
                "花蓮縣",
                "基隆市",
                "嘉義市",
                "嘉義縣",
                "金門縣",
                "連江縣",
                "苗栗縣",
                "南投縣",
                "澎湖縣",
                "屏東縣",
                "臺北市",
                "臺東縣",
                "臺南市",
                "臺中市",
                "桃園市",
                "新北市",
                "新竹市",
                "新竹縣",
                "宜蘭縣",
                "雲林縣",
                "彰化縣",
            ]
            .contains(&name)
            {
                return false;
            }
            let text = if let Some(t) = r["intensity"].as_str() {
                t.to_owned()
            } else {
                r["intensity"].to_string()
            };
            let text = text.trim().replace('弱', "-").replace(['強', '强'], "+");
            [
                "0", "1", "2", "3", "4", "5-", "5+", "6-", "6+", "7", "5", "6",
            ]
            .contains(&text.as_str())
                || text
                    .parse::<f64>()
                    .ok()
                    .is_some_and(|v| v.is_finite() && v.fract() == 0.0 && (0.0..=7.0).contains(&v))
        })
    })
}
pub fn timeout(e: &Value) -> i64 {
    if b(e, "isCanceled") {
        20
    } else {
        (n(e, "magnitude").max(if b(e, "isWarn") { 6.0 } else { 3.0 }) * 60.0).ceil() as i64
    }
}
pub fn duration(e: &Value) -> i64 {
    if !e["volcanoEvent"].is_null() {
        if b(e, "isCanceled") {
            60
        } else {
            900
        }
    } else if b(e, "isJmaLpgm") {
        60
    } else if b(e, "isEew") {
        if b(e, "isCanceled") {
            20
        } else {
            n(e, "magnitude")
                .max(if b(e, "isWarn") { 6.0 } else { 3.0 })
                .ceil() as i64
                * 60
        }
    } else {
        let m = n(e, "magnitude");
        let c = s(e, "className");
        if b(e, "isCanceled") {
            60
        } else if c == "purple" || m >= 7.5 {
            1200
        } else if c.contains("red") || m >= 7.0 {
            900
        } else if c.contains("orange") || m >= 6.0 {
            600
        } else {
            300
        }
    }
}
pub fn uses_catalog(e: &Value) -> bool {
    !b(e, "isEew") && (catalog(s(e, "source")) || matches!(s(e, "source"), "emsc" | "emscEqlist"))
}
pub fn uses_window(e: &Value) -> bool {
    uses_catalog(e)
        || b(e, "useSourceTimeForExpiry")
        || i(e, "origin") == 3
        || matches!(s(e, "source"), "usgsEqlist" | "cwaEqlist" | "cencEqlist")
}
pub fn elapsed(e: &Value, now: i64, source_now: i64, offset: i64, show_stale: bool) -> i64 {
    if b(e, "isJmaLpgm") {
        // VXSE62 dates have already been parsed as absolute instants. They
        // must not pass through the source-wall-clock conversion a second time.
        let bulletin = &e["jmaLpgmBulletin"];
        let stamp = bulletin["reportEpochUs"]
            .as_i64()
            .or_else(|| bulletin["originEpochUs"].as_i64());
        return stamp.map_or(0, |v| ((source_now - v) / SECOND).clamp(0, 999999));
    }
    if b(e, "isEew") && b(e, "isCanceled") {
        return absolute(s(e, "arrivedAt"), offset)
            .map_or(0, |v| ((now - v) / SECOND).clamp(0, 999999));
    }
    if b(e, "isEew") {
        return instant(e, "originTime").map_or(
            if b(e, "useSourceTimeForExpiry") {
                999999
            } else {
                0
            },
            |v| ((source_now - i(e, "$replayOffsetUs") - v) / SECOND).clamp(0, 999999),
        );
    }
    if i(e, "origin") != 3
        && !b(e, "useSourceTimeForExpiry")
        && (show_stale
            || no_update(s(e, "source")).is_some()
            || matches!(
                s(e, "source"),
                "ningxia" | "guangxi" | "shanxi" | "beijing" | "yunnan"
            ))
    {
        return 0;
    }
    let key = if catalog(s(e, "source")) || matches!(s(e, "source"), "emsc" | "emscEqlist") {
        "originTime"
    } else if !e["reportTime"].is_null() {
        "reportTime"
    } else {
        "originTime"
    };
    instant(e, key).map_or(0, |v| ((source_now - v) / SECOND).clamp(0, 999999))
}
pub fn remaining(
    e: &Value,
    first: Option<&Value>,
    now: i64,
    source_now: i64,
    offset: i64,
    show_stale: bool,
) -> i64 {
    let total = duration(e);
    if uses_catalog(e) {
        if b(e, "isHistory") || e["originTime"].is_null() || s(e, "eventId").trim().is_empty() {
            return 0;
        }
        let age = ((source_now - instant(e, "originTime").unwrap_or(0)) / SECOND).clamp(0, 999999);
        if b(e, "isSnapshot") {
            return total - age;
        }
        let arrival = first
            .and_then(|v| absolute(s(v, "arrivedAt"), offset))
            .or_else(|| absolute(s(e, "arrivedAt"), offset));
        let age_local = arrival.map_or(0, |v| ((now - v) / SECOND).clamp(0, 999999));
        return if age - age_local >= 1800 {
            0
        } else {
            total - age_local
        };
    }
    if (b(e, "useSourceTimeForExpiry") && e["originTime"].is_null() && e["reportTime"].is_null())
        || (catalog(s(e, "source")) && e["originTime"].is_null())
    {
        return 0;
    }
    total - elapsed(e, now, source_now, offset, show_stale)
}
