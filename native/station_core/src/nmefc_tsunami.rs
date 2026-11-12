//! NMEFC source decoding, report acceptance and sidebar projection.
//! Source objects are retained unchanged; absent positions never discard text.
use crate::unified_event_policy::absolute;
use serde_json::{json, Value};
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
fn num(v: &Value) -> Option<f64> {
    v.as_f64()
        .or_else(|| v.as_str()?.trim().parse().ok())
        .filter(|n| n.is_finite())
}
fn rows(v: &Value) -> impl Iterator<Item = &Value> {
    v.as_array().into_iter().flatten().filter(|v| v.is_object())
}
/// Official bulletin body cells only. The product-definition note must never
/// be interpreted as the conclusion about the current earthquake.
pub fn bulletin(c: &Value) -> Value {
    let html = c["html"].as_str().unwrap_or("");
    let mut rest = html;
    let mut paragraphs = Vec::new();
    while let Some(start) = rest.find("<td") {
        rest = &rest[start + 3..];
        let Some(end) = rest.find('>') else { break };
        let tag = &rest[..end];
        rest = &rest[end + 1..];
        let Some(end) = rest.find("</td>") else { break };
        if !tag.contains("class=\"hui_14\"") && !tag.contains("class='hui_14'") { continue; }
        let fragment = rest[..end].replace("&nbsp;", "&#160;");
        let wrapped = format!("<body>{fragment}</body>");
        let Ok(document) = roxmltree::Document::parse(&wrapped) else { continue; };
        let text = document.descendants().filter(|n| n.is_text())
            .filter_map(|n| n.text()).collect::<String>().trim().to_owned();
        if text.starts_with("注：") || text.starts_with("注:") { break; }
        if !text.is_empty() { paragraphs.push(text); }
    }
    json!({"bulletinText":paragraphs.join("\n")})
}
fn level(v: &str) -> (&'static str, &'static str) {
    match v {
        "红色" => ("majorWarning", "red"),
        "橙色" => ("warning", "orange"),
        "黄色" => ("watch", "yellow"),
        "蓝色" => ("watch", "blue"),
        _ => ("none", "gray"),
    }
}
fn height_text(v: &Value) -> String {
    let value = text(v);
    if !value.is_empty()
        && value
            .chars()
            .all(|c| c.is_ascii_digit() || ".-~～—–至< >≤≥".contains(c))
    {
        format!("{value}cm")
    } else {
        value
    }
}
fn height_metres(v: &Value) -> Option<f64> {
    let value = text(v);
    for suffix in ["厘米", "公分", "cm"] {
        if let Some(n) = value.strip_suffix(suffix) {
            return n
                .trim()
                .parse::<f64>()
                .ok()
                .filter(|v| v.is_finite() && *v >= 0.0)
                .map(|v| v / 100.0);
        }
    }
    for suffix in ["米", "m"] {
        if let Some(n) = value.strip_suffix(suffix) {
            return n
                .trim()
                .parse::<f64>()
                .ok()
                .filter(|v| v.is_finite() && *v >= 0.0);
        }
    }
    // The source's NMEFC table uses centimetres. Ranges are kept as text,
    // never promoted to a measured maximum or a single predicted height.
    value
        .parse::<f64>()
        .ok()
        .filter(|v| v.is_finite() && *v >= 0.0)
        .map(|v| v / 100.0)
}
/// Resolve only the image explicitly attached to this accepted report. Do not
/// infer a filename from the bulletin or substitute the deep-ocean amplitude map.
pub fn coastal_map(m: &Value) -> Value {
    let url = s(m, "coastalMapUrl");
    let tail = url.strip_prefix("https://").or_else(|| url.strip_prefix("http://"));
    let available = s(m, "source") == "nmefc"
        && s(m, "bulletinLevel") != "cancellation"
        && tail.is_some_and(|v| !v.split('/').next().unwrap_or("").is_empty())
        && !url.chars().any(char::is_whitespace);
    let number = m["reportNumber"].as_u64();
    json!({"url":if available {url.as_str()} else {""},
        "cacheKey":if available {json!([m["eventId"],m["reportNumber"],m["reportTime"],url]).to_string()}else{String::new()},
        "caption":number.map_or_else(||"NMEFC 岸段预报图".to_owned(),|n|format!("NMEFC 岸段预报图 · 第{n}报"))})
}
pub fn parse(raw: &Value) -> Value {
    let warning = &raw["warningInfo"];
    let details = &raw["details"];
    let times = &raw["timeInfo"];
    let shock = &raw["shockInfo"];
    let raw_level = s(warning, "level");
    let (grade, color) = level(&raw_level);
    let bulletin = match raw_level.as_str() {
        "信息" => "information",
        "解除" => "cancellation",
        _ => raw_level.as_str(),
    };
    let raw_title = s(warning, "title");
    let title = if !raw_title.is_empty() {
        raw_title
    } else {
        match raw_level.as_str() {
            "红色" | "橙色" | "黄色" | "蓝色" => format!("海啸警报（{raw_level}）"),
            "解除" => "海啸预警解除".into(),
            _ => "海啸信息".into(),
        }
    };
    let subtitle = s(warning, "subtitle");
    let report_time = if s(times, "alarmDate").is_empty() {
        s(times, "updateDate")
    } else {
        s(times, "alarmDate")
    };
    let code = s(raw, "code");
    let id = if code.is_empty() {
        s(raw, "id")
    } else {
        code.clone()
    };
    let batch = text(&details["batch"]);
    let digits = batch
        .trim_start_matches('第')
        .trim_end_matches(['报', '期']);
    let number = digits.parse::<u64>().ok().filter(|v| *v > 0);
    let areas = if bulletin == "cancellation" {
        vec![]
    } else {
        rows(&raw["forecasts"]).map(|a|{
        let (grade,color)=level(&s(a,"warningLevel"));
        json!({"name":s(a,"forecastArea"),"grade":grade,"className":color,"height":height_metres(&a["maxWaveHeight"]),
            "description":height_text(&a["maxWaveHeight"]),"arrivalTime":s(a,"estimatedArrivalTime"),"condition":s(a,"province")})
    }).collect::<Vec<_>>()
    };
    let observations = if bulletin == "cancellation" {
        vec![]
    } else {
        rows(&raw["waterLevelMonitoring"]).map(|o|{
        json!({"stationId":s(o,"stationId"),"stationName":s(o,"stationName"),"location":s(o,"location"),"condition":s(o,"infoStatus"),
            "latitude":num(&o["coordinates"]["latitude"]).filter(|v|(-90.0..=90.0).contains(v)),
            "longitude":num(&o["coordinates"]["longitude"]).filter(|v|(-180.0..=180.0).contains(v)),
            "time":s(o,"time"),"maxWaveHeight":height_text(&o["maxWaveHeight"]),"maxWaveHeightMeters":height_metres(&o["maxWaveHeight"])})
    }).collect::<Vec<_>>()
    };
    json!({"source":"nmefc","id":id,"eventId":code,"reportNumber":number,"sourcePayload":raw,"timeZone":8,
        "reportTime":report_time,"title":title,"titleText":if subtitle.is_empty(){title.clone()}else{subtitle},
        "grade":grade,"className":color,"bulletinLevel":bulletin,"expires":s(raw,"expires"),"areas":areas,"observations":observations,
        "epicenterLat":num(&shock["latitude"]),"epicenterLng":num(&shock["longitude"]),"magnitude":num(&shock["magnitude"]),"depth":num(&shock["depth"]),
        "epicenterName":s(shock,"placeName"),"originTime":s(shock,"shockTime"),"htmlUrl":s(details,"htmlUrl"),
        "earthquakeMapUrl":s(&details["maps"],"earthquakeMapUrl"),"amplitudeMapUrl":s(&details["maps"],"amplitudeMapUrl"),"coastalMapUrl":s(&details["maps"],"coastalMapUrl")})
}
fn stamp(v: &Value) -> Option<i64> {
    absolute(&s(v, "reportTime"), 8 * 60)
}
fn active(v: &Value) -> bool {
    matches!(s(v, "grade").as_str(), "watch" | "warning" | "majorWarning")
}
fn operation(v: &Value) -> Value {
    json!([v["grade"], v["bulletinLevel"], v["areas"]])
}
pub fn accept(old: &Value, next: &Value) -> Value {
    // Projection timestamps are not source revisions.
    let mut old_source = old.clone();
    if let Some(object) = old_source.as_object_mut() { object.remove("waveData"); }
    let old = &old_source;
    let mut next_source = next.clone();
    if let Some(object) = next_source.as_object_mut() { object.remove("waveData"); }
    let next = &next_source;

    // An unrecognised/missing level cannot clear an accepted warning.
    if active(old)
        && !active(next)
        && !matches!(
            s(next, "bulletinLevel").as_str(),
            "information" | "cancellation"
        )
    {
        return json!({"accepted":false});
    }
    let same_event = !s(next, "eventId").is_empty() && next["eventId"] == old["eventId"];
    let order = if same_event {
        old["reportNumber"]
            .as_u64()
            .zip(next["reportNumber"].as_u64())
            .map(|(a, b)| b.cmp(&a))
    } else {
        None
    };
    if !old.is_null()
        && (order == Some(std::cmp::Ordering::Less)
            || order != Some(std::cmp::Ordering::Greater)
                && stamp(old).is_some_and(|t| stamp(next).is_none_or(|n| n < t)))
    {
        return json!({"accepted":false});
    }
    let same_report = same_event
        && order != Some(std::cmp::Ordering::Greater)
        && stamp(old).is_some()
        && stamp(old) == stamp(next);
    if same_report
        && s(old, "bulletinLevel") == "cancellation"
        && s(next, "bulletinLevel") != "cancellation"
    {
        return json!({"accepted":false});
    }
    let mut merged = next.clone();
    if same_report && s(next, "bulletinLevel") != "cancellation" && old["grade"] == next["grade"] {
        for key in ["areas", "observations"] {
            let mut items = rows(&next[key]).cloned().collect::<Vec<_>>();
            for item in rows(&old[key]) {
                let found = items.iter().any(|v| {
                    if key == "areas" {
                        v["name"] == item["name"]
                    } else {
                        !s(item, "stationId").is_empty() && v["stationId"] == item["stationId"]
                            || !s(item, "stationName").is_empty()
                                && v["stationName"] == item["stationName"]
                                && v["location"] == item["location"]
                    }
                });
                if !found {
                    items.push(item.clone());
                }
            }
            merged[key] = json!(items);
        }
    }
    if old == &merged {
        return json!({"accepted":false});
    }
    let should_alert = (active(&merged)
        || s(&merged, "bulletinLevel") == "cancellation" && active(old))
        && (!same_report || operation(old) != operation(&merged));
    json!({"accepted":true,"useIncoming":merged==*next,"message":merged,"shouldAlert":should_alert})
}
fn display_row(name: &str, height: &str, time: &str) -> Value {
    // A time-only source field has no proven calendar date to convert. Keep its
    // explicit BJT meaning rather than inventing a date or displaying unknown.
    let time_only = time.len() == 5
        && time.as_bytes()[2] == b':'
        && time.chars().all(|c| c.is_ascii_digit() || c == ':');
    json!({"name":name,"height":if height.is_empty(){"未知"}else{height},"arrivalTime":if time_only{""}else{time},"arrivalLabel":if time_only{format!("{time} BJT")}else{String::new()},"heightTime":"","condition":"","secondary":[],"details":[]})
}
pub fn sidebar(m: &Value) -> Value {
    let mut cells = vec![];
    let mut used = std::collections::HashSet::new();
    let areas = rows(&m["areas"]).collect::<Vec<_>>();
    let observations = rows(&m["observations"]).collect::<Vec<_>>();
    for (i, a) in areas.iter().enumerate() {
        let name = s(a, "name");
        let stations = observations
            .iter()
            .enumerate()
            .filter(|(_, o)| !name.is_empty() && s(o, "location") == name)
            .collect::<Vec<_>>();
        let forecast = display_row(&name, &s(a, "description"), &s(a, "arrivalTime"));
        let cell = |index: Option<usize>, o: Option<&&Value>| {
            json!({"key":format!("nmefc:{i}:{index:?}"),"region":if name.is_empty(){"未知"}else{&name},"grade":a["grade"],"gradeLabel":s(a,"condition"),"className":a["className"],"regionForecast":forecast,
            "stationName":o.map(|v|s(v,"stationName")).unwrap_or_default(),"forecast":null,
            "observation":o.map(|v|display_row(&s(v,"stationName"),&s(v,"maxWaveHeight"),&s(v,"time")))})
        };
        if stations.is_empty() {
            cells.push(cell(None, None));
        } else {
            for (j, o) in stations {
                used.insert(j);
                cells.push(cell(Some(j), Some(o)));
            }
        }
    }
    // No province/nearest-station guess: unassociated readings remain separate.
    for (i, o) in observations
        .iter()
        .enumerate()
        .filter(|(i, _)| !used.contains(i))
    {
        let location = s(o, "location");
        cells.push(json!({"key":format!("nmefc:observation:{i}"),"region":if location.is_empty(){"未知"}else{&location},"grade":"none","gradeLabel":"独立观测位置","className":"gray","regionForecast":null,"stationName":s(o,"stationName"),"forecast":null,
            "observation":display_row(&s(o,"stationName"),&s(o,"maxWaveHeight"),&s(o,"time"))}));
    }
    if cells.is_empty() {
        cells.push(json!({"key":"nmefc:bulletin","region":if s(m,"epicenterName").is_empty(){s(m,"titleText")}else{s(m,"epicenterName")},"grade":m["grade"],"gradeLabel":"","className":m["className"],"regionForecast":null,"stationName":"","forecast":null,"observation":null}));
    }
    let original_title=s(&m["sourcePayload"]["warningInfo"],"title");
    json!({"caption":format!("NMEFC {}",if original_title.is_empty(){s(m,"title")}else{original_title}),"regionCount":areas.len(),"stationCount":observations.len(),"cells":cells,
        "bulletins":[{"label":"公报","reportTime":m["reportTime"],"reportNumber":m["reportNumber"],
        "headline":if s(&m["officialDetail"],"bulletinText").is_empty(){s(m,"titleText")}else{s(&m["officialDetail"],"bulletinText")},
        "rawText":serde_json::to_string_pretty(&json!({"sourcePayload":m["sourcePayload"],"officialDetail":m["officialDetail"]})).unwrap_or_default()}],
        "columnHeadings":["地区/位置","实测波幅","预计波幅"]})
}

pub fn voice(m: &Value, update: bool) -> Value {
    let unit = s(&m["sourcePayload"]["warningInfo"], "orgUnit");
    let source = if unit.is_empty() {
        "国家海洋预报台"
    } else {
        &unit
    };
    let message = if s(m, "bulletinLevel") == "cancellation" {
        format!("{source}，海啸预警已经解除。")
    } else if s(m, "bulletinLevel") == "information" {
        format!("{source}，发布海啸信息。")
    } else if active(m) {
        let action = if update { "更新" } else { "发布" };
        let number = m["reportNumber"]
            .as_u64()
            .map(|n| format!("，第{n}报"))
            .unwrap_or_default();
        let areas = rows(&m["areas"])
            .filter(|a| s(a, "grade") != "none")
            .map(|a| s(a, "name"))
            .filter(|a| !a.is_empty())
            .take(3)
            .collect::<Vec<_>>()
            .join("、");
        format!(
            "{source}{action}{}{number}。{}",
            s(m, "title"),
            if areas.is_empty() {
                String::new()
            } else {
                format!("预警区域：{areas}。")
            }
        )
    } else {
        String::new()
    };
    json!({"text":message})
}

#[cfg(test)]
mod tests {
    use super::*;
    fn captured() -> Value {
        let all: Value = serde_json::from_str(include_str!(
            "../../../test/fixtures/catalog_20260917/whews_all.json"
        ))
        .unwrap();
        all.as_array()
            .unwrap()
            .iter()
            .find(|v| v["source"] == "tsunami")
            .unwrap()["Data"]
            .clone()
    }
    // Protocol edge cases only; never represented as observed tsunami messages.
    fn protocol(batch: u64, level: &str, time: &str) -> Value {
        json!({"code":"protocol-event","details":{"batch":batch},"timeInfo":{"alarmDate":time},"warningInfo":{"level":level}})
    }
    #[test]
    fn captured_raw_report_keeps_identity_number_time_and_original_object() {
        let raw = captured();
        let parsed = parse(&raw);
        assert_eq!(parsed["sourcePayload"], raw);
        assert_eq!(parsed["eventId"], "202608251500");
        assert_eq!(parsed["reportNumber"], 2);
        assert_eq!(parsed["reportTime"], "2026-08-25 15:46:46");
        assert_eq!(parsed["bulletinLevel"], "information");
        assert_eq!(parsed["title"], "海啸信息");
        assert_eq!(stamp(&parsed), absolute("2026-08-25T07:46:46Z", 0));
    }
    #[test]
    fn coastal_map_uses_only_attached_report_image_and_revisions_its_cache() {
        let mut raw = protocol(2, "橙色", "2026-01-01 12:00:00");
        raw["details"]["maps"] = json!({
            "coastalMapUrl":"https://obs.nmefc.cn/protocol/Coastal_Forecast_Point.jpg",
            "amplitudeMapUrl":"https://obs.nmefc.cn/protocol/Tsunami_Maximum_Amplitude.jpg"});
        let original = raw.clone();
        let parsed = parse(&raw);
        let first = coastal_map(&parsed);
        assert_eq!(first["url"], raw["details"]["maps"]["coastalMapUrl"]);
        assert_eq!(first["caption"], "NMEFC 岸段预报图 · 第2报");
        raw["details"]["batch"] = json!(3);
        assert_ne!(coastal_map(&parse(&raw))["cacheKey"], first["cacheKey"]);
        raw["details"]["maps"]["coastalMapUrl"] = json!("");
        assert_eq!(coastal_map(&parse(&raw))["url"], "");
        assert_eq!(parsed["sourcePayload"], original);
        raw["details"]["maps"]["coastalMapUrl"] = first["url"].clone();
        raw["warningInfo"]["level"] = json!("解除");
        assert_eq!(coastal_map(&parse(&raw))["url"], "");
    }
    #[test]
    fn source_colours_and_unknown_level_do_not_invent_cancellation() {
        for (level, grade, color) in [
            ("黄色", "watch", "yellow"),
            ("橙色", "warning", "orange"),
            ("红色", "majorWarning", "red"),
            ("蓝色", "watch", "blue"),
            ("未识别", "none", "gray"),
        ] {
            let p = parse(&protocol(1, level, "2026-01-01 12:00:00"));
            assert_eq!(p["grade"], grade);
            assert_eq!(p["className"], color);
            assert!(!s(&p, "title").contains("解除"));
        }
    }
    #[test]
    fn coordinate_less_observations_stay_and_ranges_do_not_become_measurements() {
        let mut raw = protocol(1, "橙色", "2026-01-01 12:00:00");
        raw["waterLevelMonitoring"] = json!([{"stationName":"protocol station","location":"protocol location","maxWaveHeight":"0"}]);
        raw["forecasts"] = json!([{"forecastArea":"protocol region","maxWaveHeight":"100-300","warningLevel":"橙色"}]);
        let p = parse(&raw);
        assert_eq!(p["observations"].as_array().unwrap().len(), 1);
        assert!(p["observations"][0]["latitude"].is_null());
        assert_eq!(p["observations"][0]["maxWaveHeightMeters"], 0.0);
        assert!(p["areas"][0]["height"].is_null());
        assert_eq!(p["areas"][0]["description"], "100-300cm");
        assert_eq!(p["sourcePayload"], raw);
    }
    #[test]
    fn unit_conversion_does_not_double_append_units_or_pick_a_range_endpoint() {
        for (value, expected) in [
            ("80", Some(0.8)),
            ("80cm", Some(0.8)),
            ("0.8米", Some(0.8)),
            ("30-100", None),
            ("小于30", None),
            ("-1", None),
        ] {
            assert_eq!(height_metres(&json!(value)), expected);
        }
        assert_eq!(height_text(&json!("80cm")), "80cm");
    }
    #[test]
    fn report_order_cancellation_and_new_event_do_not_restore_old_data() {
        let first = parse(&protocol(2, "橙色", "2026-01-01 12:00:00"));
        let old = parse(&protocol(1, "红色", "2026-01-01 12:01:00"));
        assert_eq!(accept(&first, &old)["accepted"], false);
        let cancel = parse(&protocol(3, "解除", "2026-01-01 12:02:00"));
        assert_eq!(accept(&first, &cancel)["accepted"], true);
        assert_eq!(accept(&cancel, &first)["accepted"], false);
        let mut unrelated = protocol(1, "黄色", "2026-01-01 12:03:00");
        unrelated["code"] = json!("another-event");
        assert_eq!(accept(&cancel, &parse(&unrelated))["accepted"], true);
        assert_eq!(accept(&first, &first)["accepted"], false);
        let unknown = parse(&protocol(4, "未识别", "2026-01-01 12:05:00"));
        assert_eq!(accept(&first, &unknown)["accepted"], false);
    }
    #[test]
    fn same_report_can_add_observations_without_realert_or_raw_mutation() {
        let raw = protocol(2, "橙色", "2026-01-01 12:00:00");
        let old = parse(&raw);
        let mut enrichment = raw.clone();
        enrichment["waterLevelMonitoring"] =
            json!([{"stationName":"protocol station","maxWaveHeight":"60"}]);
        let next = parse(&enrichment);
        let accepted = accept(&old, &next);
        assert_eq!(accepted["accepted"], true);
        assert_eq!(accepted["shouldAlert"], false);
        assert_eq!(accepted["message"]["sourcePayload"], enrichment);
        assert_eq!(old["sourcePayload"], raw);
    }
    #[test]
    fn distinct_event_or_same_report_geometry_update_is_not_discarded() {
        let raw = protocol(2, "橙色", "2026-01-01 12:00:00");
        let old = parse(&raw);
        let mut other = raw.clone();
        other["code"] = json!("another-event");
        assert_eq!(accept(&old, &parse(&other))["accepted"], true);
        let mut detail = old.clone();
        detail["sourcePayload"]["details"]["coastalMapUrl"] = json!("protocol-map-link");
        let result = accept(&old, &detail);
        assert_eq!(result["accepted"], true);
        assert_eq!(result["shouldAlert"], false);
    }
    #[test]
    fn sidebar_keeps_every_region_and_unmatched_observation_without_false_association() {
        let mut raw = protocol(2, "橙色", "2026-01-01 12:00:00");
        raw["forecasts"]=json!((0..13).map(|i|json!({"forecastArea":format!("protocol region {i}"),"maxWaveHeight":"100-300","estimatedArrivalTime":"12:30","warningLevel":"橙色"})).collect::<Vec<_>>());
        raw["waterLevelMonitoring"] = json!([{"stationName":"protocol station","location":"unmatched location","maxWaveHeight":"60"}]);
        let p = parse(&raw);
        let view = sidebar(&p);
        assert_eq!(view["regionCount"], 13);
        assert_eq!(view["stationCount"], 1);
        assert_eq!(view["cells"].as_array().unwrap().len(), 14);
        assert_eq!(view["cells"][13]["region"], "unmatched location");
        assert!(view["cells"][13]["regionForecast"].is_null());
        assert!(view["cells"][0]["observation"].is_null());
        assert_eq!(
            view["cells"][0]["regionForecast"]["arrivalLabel"],
            "12:30 BJT"
        );
        let pages = super::super::sidebar::paginate(
            &json!({"itemHeights":vec![20;14],"columns":2,"maxHeight":120,"overhead":40,"rowGap":6}),
        );
        let indices = pages["pages"]
            .as_array()
            .unwrap()
            .iter()
            .flat_map(|p| p["lines"].as_array().unwrap())
            .flat_map(|l| l["indices"].as_array().unwrap())
            .cloned()
            .collect::<Vec<_>>();
        assert_eq!(indices, (0..14).map(|i| json!(i)).collect::<Vec<_>>());
        assert_eq!(pages["intervalMs"], 12000);
    }
}
