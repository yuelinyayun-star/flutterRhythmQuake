//! Independent JMA forecast/observation revisions. Never rewrite sourcePayload.
use super::*;

fn rows(v: &Value) -> Vec<Value> {
    v.as_array().cloned().unwrap_or_default()
}
fn stamp(v: &Value) -> Option<i64> {
    absolute(&s(v, "reportTime"), 9 * 60)
}
fn observation_report(v: &Value) -> bool {
    s(&v["jmaDetails"], "telegramType") == "VTSE51"
}
fn report(message: &Value, cancelled: bool) -> Value {
    json!({"eventId":message["eventId"],"reportTime":message["reportTime"],
        "reportNumber":message["reportNumber"],"headline":message["titleText"],"cancelled":cancelled})
}
pub(super) fn attach(transport: &str, raw: &Value, message: &mut Value) {
    let telegram = if transport == "jian" {
        s(raw, "telegram")
    } else {
        s(raw, "telegramType")
    };
    let telegram = if telegram.is_empty() {
        if rows(&raw["observations"]).is_empty() {
            "VTSE41"
        } else {
            "VTSE51"
        }
        .to_owned()
    } else {
        telegram
    };
    let mut forecasts = vec![];
    for region in raw[if transport == "jian" { "area" } else { "areas" }]
        .as_array()
        .into_iter()
        .flatten()
    {
        for station in region["stations"]
            .as_array()
            .into_iter()
            .flatten()
            .filter(|v| v.is_object())
        {
            let mut row = station.clone();
            row["regionName"] = region["name"].clone();
            row["regionCode"] = region["code"].clone();
            forecasts.push(row);
        }
    }
    let mut observed = vec![];
    // Documented WHEWS VTSE51 shape. A matching source shape is carried unchanged.
    for region in raw["observations"].as_array().into_iter().flatten() {
        for station in region["stations"]
            .as_array()
            .into_iter()
            .flatten()
            .filter(|v| v.is_object())
        {
            let mut row = station.clone();
            row["regionName"] = region["name"].clone();
            row["regionCode"] = region["code"].clone();
            observed.push(row);
        }
    }
    let cancelled = raw["cancel"] == true || s(raw, "infoTypeName") == "取消";
    let mut details = json!({"transport":transport,"telegramType":telegram,
        "infoTypeName":s(raw,"infoTypeName"),"forecastStations":forecasts,"observations":observed});
    let key = if telegram == "VTSE51" {
        "observationReport"
    } else {
        "forecastReport"
    };
    details[key] = report(
        message,
        cancelled || (key == "forecastReport" && s(message, "grade") == "none"),
    );
    if cancelled {
        details["observations"] = json!([]);
        details["forecastStations"] = json!([]);
    }
    message["jmaDetails"] = details;
    sync_observations(message);
}
fn sync_observations(message: &mut Value) {
    message["observations"] = Value::Array(rows(&message["jmaDetails"]["observations"]).iter().map(|row| {
        let height = s(row,"maxHeightDesc");
        let height = if !height.is_empty() { height } else if let Some(n) = number(&row["maxHeight"]) { format!("{n}m") } else { s(row,"maxCondition") };
        json!({"stationId":s(row,"code"),"stationName":s(row,"name"),"location":s(row,"regionName"),
            "latitude":null,"longitude":null,"time":s(row,"maxTime"),"maxWaveHeight":height,
            "maxWaveHeightMeters":number(&row["maxHeight"]),"condition":s(row,"maxCondition")})
    }).collect());
}
fn older(next: &Value, previous: &Value) -> bool {
    if previous.is_null() {
        return false;
    }
    let same_event = !s(next, "eventId").is_empty() && next["eventId"] == previous["eventId"];
    if same_event {
        if let (Some(n), Some(p)) = (
            next["reportNumber"].as_i64(),
            previous["reportNumber"].as_i64(),
        ) {
            if n != p {
                return n < p;
            }
        }
    }
    match (stamp(next), stamp(previous)) {
        (Some(n), Some(p)) => n < p,
        (None, Some(_)) => true,
        _ => false,
    }
}
fn enrich(next: &Value, previous: &Value) -> Value {
    let mut out = next.clone();
    if let (Some(target), Some(old)) = (out.as_object_mut(), previous.as_object()) {
        for (key, value) in old {
            if target
                .get(key)
                .is_none_or(|v| v.is_null() || v.as_str() == Some(""))
            {
                target.insert(key.clone(), value.clone());
            }
        }
    }
    out
}
fn enrich_rows(next: &Value, previous: &Value, identity: &str) -> Value {
    Value::Array(
        rows(next)
            .iter()
            .map(|row| {
                let old = previous
                    .as_array()
                    .into_iter()
                    .flatten()
                    .find(|old| old[identity] == row[identity]);
                old.map_or_else(|| row.clone(), |old| enrich(row, old))
            })
            .collect(),
    )
}
fn operational(v: &Value) -> Value {
    let mut areas = rows(&v["areas"])
        .iter()
        .filter(|r| grade(&s(r, "grade")) >= 2)
        .map(|r| json!([r["name"], r["grade"], r["height"]]))
        .collect::<Vec<_>>();
    areas.sort_by_key(|r| r.to_string());
    json!([v["grade"], areas])
}
pub(super) fn accept(previous: &Value, incoming: &Value) -> Value {
    // Projection timestamps are not source revisions.
    let mut previous_source = previous.clone();
    if let Some(object) = previous_source.as_object_mut() { object.remove("waveData"); }
    let previous = &previous_source;
    let mut incoming_source = incoming.clone();
    if let Some(object) = incoming_source.as_object_mut() { object.remove("waveData"); }
    let incoming = &incoming_source;

    let obs = observation_report(incoming);
    let key = if obs {
        "observationReport"
    } else {
        "forecastReport"
    };
    let next_report = &incoming["jmaDetails"][key];
    let old_report = &previous["jmaDetails"][key];
    let different_event = !s(incoming, "eventId").is_empty()
        && !s(previous, "eventId").is_empty()
        && incoming["eventId"] != previous["eventId"];
    if (different_event && older(incoming, previous))
        || (!different_event && older(next_report, old_report))
    {
        return json!({"accepted":false});
    }
    // A delayed observation must not restore a cleared/cancelled warning series.
    let forecast = &previous["jmaDetails"]["forecastReport"];
    if obs
        && !different_event
        && forecast["cancelled"] == true
        && stamp(next_report)
            .zip(stamp(forecast))
            .is_some_and(|(n, p)| n <= p)
    {
        return json!({"accepted":false});
    }
    if !obs
        && previous["grade"] == "forecast"
        && incoming["sourcePayload"]["cancelled"] == true
        && stamp(incoming) == stamp(previous)
    {
        return json!({"accepted":false});
    }
    if old_report.is_null()
        && !previous["jmaDetails"].is_object()
        && !previous.is_null()
        && !obs
        && older(incoming, previous)
    {
        return json!({"accepted":false});
    }
    let old = if different_event {
        &Value::Null
    } else {
        previous
    };
    let same_report =
        !old.is_null() && stamp(next_report).is_some() && stamp(next_report) == stamp(old_report);
    let mut out = if obs && !old.is_null() {
        old.clone()
    } else {
        incoming.clone()
    };
    let mut details = if old["jmaDetails"].is_object() {
        old["jmaDetails"].clone()
    } else {
        json!({})
    };
    details["transport"] = incoming["jmaDetails"]["transport"].clone();
    details["telegramType"] = incoming["jmaDetails"]["telegramType"].clone();
    details["infoTypeName"] = incoming["jmaDetails"]["infoTypeName"].clone();
    details[key] = if same_report {
        enrich(next_report, old_report)
    } else {
        next_report.clone()
    };
    let cancelled = next_report["cancelled"] == true;
    if obs {
        details["observations"] = if cancelled {
            json!([])
        } else if same_report && rows(&incoming["jmaDetails"]["observations"]).is_empty() {
            old["jmaDetails"]["observations"].clone()
        } else {
            incoming["jmaDetails"]["observations"].clone()
        };
        if !incoming["areas"].as_array().is_none_or(Vec::is_empty)
            && !older(incoming, &old["jmaDetails"]["forecastReport"])
            && !cancelled
        {
            for field in ["areas", "grade", "className", "bulletinLevel"] {
                out[field] = incoming[field].clone();
            }
        }
        if !rows(&incoming["jmaDetails"]["forecastStations"]).is_empty() && !cancelled {
            details["forecastStations"] = incoming["jmaDetails"]["forecastStations"].clone();
        }
    } else {
        let stations = &incoming["jmaDetails"]["forecastStations"];
        if cancelled {
            details["forecastStations"] = json!([]);
            details["observations"] = json!([]);
        } else if !rows(stations).is_empty() || !same_report {
            // VTSE41 often omits station forecasts supplied by VTSE51.
            if !rows(stations).is_empty() {
                details["forecastStations"] = stations.clone();
            }
        }
        if same_report && !cancelled {
            out["id"] = old["id"].clone();
            out["reportNumber"] = details[key]["reportNumber"].clone();
            out["areas"] = enrich_rows(&out["areas"], &old["areas"], "name");
            for field in ["eventId", "expires"] {
                if s(&out, field).is_empty() {
                    out[field] = old[field].clone();
                }
            }
            // P2P does not carry sub-advisory forecast regions.
            if incoming["sourcePayload"]["issue"].is_object() {
                let mut areas = rows(&out["areas"]);
                for area in rows(&old["areas"]) {
                    if area["grade"] == "forecast"
                        && !areas.iter().any(|v| v["name"] == area["name"])
                    {
                        areas.push(area);
                    }
                }
                out["areas"] = json!(areas);
            }
        }
    }
    if !obs || old.is_null() || stamp(incoming) >= stamp(old) {
        for field in ["reportTime", "sourcePayload", "isInitialSnapshot"] {
            out[field] = incoming[field].clone();
        }
    }
    if s(&out, "eventId").is_empty() {
        out["eventId"] = old["eventId"].clone();
    }
    out["jmaDetails"] = details;
    if !old.is_null() && stamp(old) > stamp(incoming) {
        out["reportTime"] = old["reportTime"].clone();
    }
    sync_observations(&mut out);
    let mut old_state = old.clone();
    let mut next_state = out.clone();
    // Transport/raw envelope changes alone do not create another UI update or alarm.
    for v in [&mut old_state, &mut next_state] {
        if let Some(map) = v.as_object_mut() {
            map.remove("sourcePayload");
            map.remove("isInitialSnapshot");
            if let Some(details) = map.get_mut("jmaDetails").and_then(Value::as_object_mut) {
                details.remove("transport");
                details.remove("telegramType");
                details.remove("infoTypeName");
            }
        }
    }
    let changed = old_state != next_state;
    // Restore the unmodified incoming raw envelope, outside the comparison.
    out["sourcePayload"] = if stamp(incoming) >= stamp(old) || old.is_null() {
        incoming["sourcePayload"].clone()
    } else {
        old["sourcePayload"].clone()
    };
    out["isInitialSnapshot"] = json!(
        incoming["isInitialSnapshot"] == true
            && (old.is_null() || old["isInitialSnapshot"] == true)
    );
    let should_alert = !obs
        && (old.is_null()
            || operational(&out) != operational(old)
            || stamp(next_report) > stamp(old_report));
    json!({"accepted":changed,"message":out,"useIncoming":out == *incoming,"shouldAlert":should_alert})
}

fn field(label: &str, text: String, time: String) -> Value {
    json!({"label":label,"text":text,"time":time})
}
pub(super) fn snapshot(frames: &Value) -> Value {
    let mut selected: std::collections::BTreeMap<String, (usize, Value)> = Default::default();
    for (index, frame) in frames.as_array().into_iter().flatten().enumerate() {
        if frame["source"] != "jma_tsunami" {
            continue;
        }
        if let Ok(parsed) = super::parse("whews", &frame["Data"]) {
            let key = if observation_report(&parsed) {
                "observationReport"
            } else {
                "forecastReport"
            };
            let next = &parsed["jmaDetails"][key];
            let choose = selected.get(key).is_none_or(|(_, old)| !older(next, old));
            if choose {
                selected.insert(key.into(), (index, next.clone()));
            }
        }
    }
    let mut indices = selected
        .values()
        .map(|(index, _)| *index)
        .collect::<Vec<_>>();
    indices.sort_unstable();
    json!({"indices":indices})
}
pub(super) fn frame_key(frame: &Value) -> Value {
    use sha2::{Digest, Sha256};
    if !frame["Data"].is_object() {
        return json!({"key":null});
    }
    let bytes = serde_json::to_vec(&frame["Data"]).unwrap_or_default();
    json!({"key":format!("jma_tsunami|{:x}",Sha256::digest(bytes))})
}
pub(super) fn append_groups(message: &Value, groups: &mut Vec<Value>, show_forecast: bool) {
    let details = &message["jmaDetails"];
    if show_forecast {
        for group in groups.iter_mut() {
            if !details["forecastReport"].is_null() {
                for k in ["reportTime", "reportNumber", "headline"] {
                    group[k] = details["forecastReport"][k].clone();
                }
            }
        }
        let stations = rows(&details["forecastStations"]);
        if !stations.is_empty() {
            let list = stations.iter().map(|r| json!({"name":s(r,"name"),"regionName":s(r,"regionName"),"stationCode":s(r,"code"),"height":"","heightTime":s(r,"highTide"),
                "arrivalTime":s(r,"arrivalTime"),"arrivalLabel":arrival_label(&s(r,"condition")),"condition":s(r,"condition"),
                "details":[field("区域",s(r,"regionName"),String::new()),field("站号",s(r,"code"),String::new())]})).collect::<Vec<_>>();
            groups.push(group(
                message,
                "stationForecast",
                "JMA 各地の満潮時刻・津波到達予想時刻に関する情報",
                list,
                &details["forecastReport"],
                "地点",
                "到达",
                "满潮",
            ));
        }
    }
    let observed = rows(&details["observations"]);
    if !observed.is_empty() && details["observationReport"]["cancelled"] != true {
        let list = observed.iter().map(|r| {
            let height = s(r,"maxHeightDesc");
            let height = if !height.is_empty() { compact_height(&height) } else if let Some(n) = number(&r["maxHeight"]) { format!("{n}m") } else if !s(r,"maxCondition").is_empty() { s(r,"maxCondition") } else { "未知".into() };
            let first = [s(r,"firstInitial"),s(r,"firstCondition")].into_iter().filter(|v|!v.is_empty()).collect::<Vec<_>>().join(" · ");
            json!({"name":s(r,"name"),"regionName":s(r,"regionName"),"stationCode":s(r,"code"),"height":height,"arrivalTime":s(r,"maxTime"),"arrivalLabel":"","condition":s(r,"maxCondition"),
                "secondary":[field("第1波",if first.is_empty() && s(r,"firstArrivalTime").is_empty(){"未知".into()}else{first},s(r,"firstArrivalTime")),field("",s(r,"maxCondition"),String::new()),field("",s(r,"maxHeightCond"),String::new())],
                "details":[field("区域",s(r,"regionName"),String::new()),field("站号",s(r,"code"),String::new()),field("仪器",s(r,"sensor"),String::new()),
                    field("第一波修正",s(r,"firstRevise"),String::new()),field("最大波修正",s(r,"maxRevise"),String::new())]})
        }).collect::<Vec<_>>();
        groups.push(group(
            message,
            "observation",
            "JMA 津波観測に関する情報",
            list,
            &details["observationReport"],
            "观测点",
            "最大波",
            "波高",
        ));
    }
}
fn group(
    message: &Value,
    kind: &str,
    caption: &str,
    list: Vec<Value>,
    report: &Value,
    name: &str,
    time: &str,
    height: &str,
) -> Value {
    let report = if report.is_object() {
        report
    } else if message["jmaDetails"]["observationReport"].is_object() {
        &message["jmaDetails"]["observationReport"]
    } else {
        message
    };
    json!({"key":format!("{}:{kind}",s(message,"eventId")),"grade":kind,"label":caption,"caption":caption,"className":"blue",
        "reportTime":s(report,"reportTime"),"reportNumber":report["reportNumber"],"headline":if !s(report,"headline").is_empty(){s(report,"headline")}else{s(message,"titleText")},
        "regionCount":list.len(),"rows":list,"nameLabel":name,"timeLabel":time,"heightLabel":height,"countLabel":"站"})
}

#[cfg(test)]
mod tests {
    use super::*;
    fn documented_observations() -> Value {
        // This is the provider's original documentation fragment, not a live event.
        serde_json::from_str(&format!(
            "{{{}}}",
            include_str!(
                "../../../test/fixtures/jma_tsunami/whews.observations.documented.fragment.txt"
            )
        ))
        .unwrap()
    }
    fn protocol(telegram: &str, number: i64, time: &str) -> Value {
        // Explicit protocol ordering fixture, never emitted as a real bulletin.
        let mut raw = json!({"id":"20260811050000","telegramType":telegram,"updates":number,
            "createTime":time,"title":"津波情報","infoTypeName":"発表"});
        if telegram == "VTSE51" {
            raw["observations"] = documented_observations()["observations"].clone();
        } else {
            raw["title"] = json!("津波警報");
            raw["areas"] = json!([{"name":"岩手県","kind":"津波警報","maxHeight":"3"}]);
        }
        super::super::parse("whews", &raw).unwrap()
    }
    fn accepted(previous: &Value, incoming: &Value) -> Value {
        let result = accept(previous, incoming);
        assert_eq!(result["accepted"], true, "{result}");
        result["message"].clone()
    }
    #[test]
    fn documented_station_forecasts_and_observations_keep_original_values() {
        let raw: Value = serde_json::from_str(include_str!(
            "../../../test/fixtures/jma_tsunami/whews.forecast_stations.documented.json"
        ))
        .unwrap();
        let parsed = super::super::parse("whews", &raw["Data"]).unwrap();
        assert_eq!(parsed["sourcePayload"], raw["Data"]);
        assert_eq!(
            parsed["jmaDetails"]["forecastStations"][0]["highTide"],
            "2026-07-28 21:04:00"
        );
        let doc = documented_observations();
        let observed = super::super::parse("whews", &doc).unwrap();
        assert_eq!(observed["sourcePayload"], doc);
        let row = &observed["jmaDetails"]["observations"][0];
        assert_eq!(row["firstInitial"], "押し");
        assert_eq!(row["firstArrivalTime"], "2026-08-11 05:20:00");
        assert_eq!(row["maxTime"], "2026-08-11 05:25:00");
        assert_eq!(row["maxHeight"], "0.8");
        assert!(observed["observations"][0]["latitude"].is_null());
    }
    #[test]
    fn observation_report_number_does_not_compete_with_warning_number() {
        let warning = protocol("VTSE41", 7, "2026-08-11 05:10:00");
        let obs = protocol("VTSE51", 1, "2026-08-11 05:30:00");
        let result = accept(&warning, &obs);
        assert_eq!(result["accepted"], true);
        assert_eq!(result["shouldAlert"], false);
        let state = &result["message"];
        assert_eq!(state["grade"], "warning");
        assert_eq!(state["areas"], warning["areas"]);
        assert_eq!(state["sourcePayload"], obs["sourcePayload"]);
        assert_eq!(state["jmaDetails"]["forecastReport"]["reportNumber"], 7);
        assert_eq!(state["jmaDetails"]["observationReport"]["reportNumber"], 1);
        let view = super::super::project(state, 0);
        assert_eq!(view["groups"][0]["grade"], "warning");
        assert_eq!(view["groups"][1]["grade"], "observation");
        assert_eq!(view["groups"][1]["rows"][0]["height"], "0.8m");
        assert_eq!(view["groups"][1]["rows"][0]["secondary"][0]["text"], "押し");
    }
    #[test]
    fn corrections_replace_observations_even_when_height_decreases_and_old_reports_stay_out() {
        let old = protocol("VTSE51", 1, "2026-08-11 05:30:00");
        let mut raw = old["sourcePayload"].clone();
        raw["updates"] = json!(2);
        raw["infoTypeName"] = json!("訂正");
        raw["createTime"] = json!("2026-08-11 05:31:00");
        raw["observations"][0]["stations"][0]["maxHeight"] = json!("0.4");
        raw["observations"][0]["stations"][0]["maxHeightDesc"] = json!("０．４ｍ");
        raw["observations"][0]["stations"][0]["firstArrivalTime"] = json!("2026-08-11 05:19:00");
        let next = super::super::parse("whews", &raw).unwrap();
        let state = accepted(&old, &next);
        assert_eq!(state["jmaDetails"]["observations"][0]["maxHeight"], "0.4");
        assert_eq!(state["sourcePayload"], raw);
        assert_eq!(accept(&state, &old)["accepted"], false);
        assert_eq!(accept(&state, &next)["accepted"], false);
    }
    #[test]
    fn first_wave_only_update_and_observation_cancel_do_not_cancel_warning() {
        let warning = protocol("VTSE41", 7, "2026-08-11 05:10:00");
        let obs = protocol("VTSE51", 1, "2026-08-11 05:30:00");
        let state = accepted(&warning, &obs);
        let mut raw = obs["sourcePayload"].clone();
        raw["observations"][0]["stations"][0]["firstInitial"] = json!("引き");
        let revised = super::super::parse("whews", &raw).unwrap();
        let state = accepted(&state, &revised);
        assert_eq!(
            state["jmaDetails"]["observations"][0]["firstInitial"],
            "引き"
        );
        raw["updates"] = json!(2);
        raw["infoTypeName"] = json!("取消");
        raw["cancel"] = json!(true);
        let cancelled = super::super::parse("whews", &raw).unwrap();
        let state = accepted(&state, &cancelled);
        assert_eq!(state["grade"], "warning");
        assert_eq!(state["jmaDetails"]["observations"], json!([]));
    }
    #[test]
    fn p2p_same_forecast_keeps_observations_and_does_not_reset_number() {
        let warning = protocol("VTSE41", 7, "2026-08-11 05:10:00");
        let obs = protocol("VTSE51", 1, "2026-08-11 05:30:00");
        let state = accepted(&warning, &obs);
        let p2p = super::super::parse(
            "p2p",
            &json!({"id":"p2p-envelope","issue":{"time":"2026/08/11 05:10:00"},
            "areas":[{"name":"岩手県","grade":"Warning","maxHeight":{"value":3}}]}),
        )
        .unwrap();
        let result = accept(&state, &p2p);
        let merged = &result["message"];
        assert_eq!(
            merged["jmaDetails"]["observations"],
            state["jmaDetails"]["observations"]
        );
        assert_eq!(merged["jmaDetails"]["forecastReport"]["reportNumber"], 7);
        assert_eq!(merged["reportTime"], state["reportTime"]);
        assert_eq!(result["shouldAlert"], false);
    }
    #[test]
    fn cancellation_rejects_delayed_observation_and_new_event_drops_old_stations() {
        let warning = protocol("VTSE41", 7, "2026-08-11 05:10:00");
        let obs = protocol("VTSE51", 1, "2026-08-11 05:30:00");
        let state = accepted(&warning, &obs);
        let mut raw = warning["sourcePayload"].clone();
        raw["updates"] = json!(8);
        raw["createTime"] = json!("2026-08-11 06:00:00");
        raw["cancel"] = json!(true);
        let cancelled = super::super::parse("whews", &raw).unwrap();
        let state = accepted(&state, &cancelled);
        assert_eq!(state["jmaDetails"]["observations"], json!([]));
        assert_eq!(accept(&state, &obs)["accepted"], false);
        raw["id"] = json!("20260812050000");
        raw["createTime"] = json!("2026-08-12 05:10:00");
        raw["updates"] = json!(1);
        raw["cancel"] = json!(false);
        let new = super::super::parse("whews", &raw).unwrap();
        let state = accepted(&state, &new);
        assert!(rows(&state["jmaDetails"]["observations"]).is_empty());
    }
    #[test]
    fn initial_snapshot_keeps_latest_of_both_telegram_types() {
        let warning = protocol("VTSE41", 7, "2026-08-11 05:10:00");
        let old_obs = protocol("VTSE51", 1, "2026-08-11 05:30:00");
        let obs = protocol("VTSE51", 2, "2026-08-11 05:40:00");
        let frames = json!([
            {"source":"jma_tsunami","Data":warning["sourcePayload"]},
            {"source":"jma_tsunami","Data":obs["sourcePayload"]},
            {"source":"jma_tsunami","Data":old_obs["sourcePayload"]}]);
        assert_eq!(snapshot(&frames)["indices"], json!([0, 1]));
    }
    #[test]
    fn content_dedupe_keeps_first_wave_changes_and_distinct_telegrams() {
        let first = protocol("VTSE51", 1, "2026-08-11 05:30:00");
        let a = json!({"Data":first["sourcePayload"]});
        let mut b = a.clone();
        b["Data"]["observations"][0]["stations"][0]["firstInitial"] = json!("引き");
        assert_eq!(frame_key(&a), frame_key(&a));
        assert_ne!(frame_key(&a), frame_key(&b));
        b["Data"]["telegramType"] = json!("VTSE41");
        assert_ne!(frame_key(&a), frame_key(&b));
    }
    #[test]
    fn observation_status_and_missing_values_are_not_converted_to_zero_or_wave_numbers() {
        for (value, desc, condition, expected) in [
            ("", "", "観測中", "観測中"),
            ("", "", "欠測", "欠測"),
            ("NaN", "", "", "未知"),
            ("0", "", "", "0m"),
            ("1.2", "１．２ｍ以上", "上昇中", "1.2m以上"),
        ] {
            let message = protocol("VTSE51", 1, "2026-08-11 05:30:00");
            let mut raw = message["sourcePayload"].clone();
            let station = &mut raw["observations"][0]["stations"][0];
            station["maxHeight"] = json!(value);
            station["maxHeightDesc"] = json!(desc);
            station["maxCondition"] = json!(condition);
            let parsed = super::super::parse("whews", &raw).unwrap();
            let view = super::super::project(&parsed, 0);
            let row = &view["groups"][0]["rows"][0];
            assert_eq!(row["height"], expected);
            assert_eq!(row["secondary"][0]["label"], "第1波");
            assert_eq!(parsed["sourcePayload"], raw);
        }
    }
}
