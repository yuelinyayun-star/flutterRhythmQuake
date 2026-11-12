//! Additive station data for future map labels. No geometry or presentation changes.
//! Raw reports are retained; regional predictions are never labelled station predictions.
use super::{absolute, number, s, text};
use serde_json::{json, Value};
use std::collections::BTreeMap;

fn rows(v: &Value) -> impl Iterator<Item = &Value> {
    v.as_array().into_iter().flatten().filter(|v| v.is_object())
}
fn active(v: &Value) -> bool {
    matches!(s(v, "grade").as_str(), "watch" | "warning" | "majorWarning")
}
fn position(lat: &Value, lon: &Value) -> (Option<f64>, Option<f64>) {
    (
        number(lat).filter(|v| (-90.0..=90.0).contains(v)),
        number(lon).filter(|v| (-180.0..=180.0).contains(v)),
    )
}
fn metres(value: &Value, unit: &str) -> Option<f64> {
    let raw = text(value);
    let lower = raw.to_lowercase();
    let (numeric, suffix) = ["厘米", "公分", "公尺", "cm", "feet", "ft", "米", "m"]
        .iter()
        .find_map(|u| lower.strip_suffix(u).map(|n| (n.trim(), *u)))
        .unwrap_or((lower.as_str(), unit));
    let n = numeric
        .parse::<f64>()
        .ok()
        .filter(|n| n.is_finite() && *n >= 0.0)?;
    match suffix.to_lowercase().as_str() {
        "m" | "米" | "公尺" | "meters" | "metres" => Some(n),
        "cm" | "厘米" | "公分" => Some(n / 100.0),
        "feet" | "ft" => Some(n * 0.3048),
        _ => None,
    }
}
fn reading(value: &Value, unit: &str, time: &str, zone: i64, kind: &str, condition: &str) -> Value {
    json!({"value":value,"unit":unit,"metres":metres(value,unit),"time":time,
        "timeUtcMs":absolute(time,zone*60).map(|t|t/1000),"timeZone":zone,"kind":kind,"condition":condition})
}
fn base(id: String, name: String, lat: &Value, lon: &Value, region: &str, code: &str) -> Value {
    let (latitude, longitude) = position(lat, lon);
    json!({"stationId":id,"stationName":name,"latitude":latitude,"longitude":longitude,
        "regionName":region,"regionCode":code,"forecast":null,"areaForecast":null,
        "observed":null,"firstArrivalTime":"","firstArrivalCondition":"",
        "forecastSourcePath":null,"observationSourcePath":null,"binding":"unresolved","areaActive":false,
        "mapEligible":false})
}
fn area_forecasts(m: &Value) -> Vec<Value> {
    let source = s(m, "source");
    let zone = m["timeZone"].as_i64().unwrap_or(9);
    rows(&m["areas"])
        .map(|a| {
            let unit = match source.as_str() {
                "jma" => "m",
                "nmefc" => "cm",
                _ => "",
            };
            let mut value = if s(a, "description").is_empty() {
                a["height"].clone()
            } else {
                a["description"].clone()
            };
            let raw = if source == "nmefc" {
                rows(&m["sourcePayload"]["forecasts"])
                    .find(|r| r["forecastArea"] == a["name"])
                    .map(|r| &r["maxWaveHeight"])
            } else if source == "cwa" {
                rows(&m["sourcePayload"]["warningAreas"])
                    .find(|r| r["areaName"] == a["name"])
                    .map(|r| &r["waveHeight"])
            } else {
                None
            };
            if let Some(raw) = raw {
                value = raw.clone();
            }
            let height = if source=="cwa" {metres(&value,"").map_or(a["height"].clone(),|n|json!(n))}else{a["height"].clone()};
            json!({"name":a["name"],"grade":a["grade"],
        "province":if source=="nmefc" {a["condition"].clone()}else{Value::Null},
        "active":active(a),"forecast":{"value":value,"metres":height,"unit":unit,
        "kind":"regionalForecastMaximum","time":a["arrivalTime"],"timeZone":m["timeZone"],
        "timeUtcMs":absolute(&s(a,"arrivalTime"),zone*60).map(|t|t/1000),
        "condition":if source=="nmefc"{Value::Null}else{a["condition"].clone()}}})
        })
        .collect()
}
fn bind(row: &mut Value, areas: &[Value]) {
    let name = s(row, "regionName");
    if let Some(a) = areas
        .iter()
        .find(|a| !name.is_empty() && s(a, "name") == name)
    {
        row["binding"] = json!("sourceRegion");
        row["areaActive"] = a["active"].clone();
        row["areaForecast"] = a["forecast"].clone();
        row["grade"] = a["grade"].clone();
    }
}
fn station_key(row: &Value) -> String {
    // An absent ID must never merge unrelated stations. Name + source region is
    // the only alternative identity supplied by these reports.
    let id = s(row, "stationId");
    if id.is_empty() {
        format!("name:{}|{}", s(row, "stationName"), s(row, "regionName"))
    } else {
        format!("id:{id}")
    }
}
fn jma(m: &Value, areas: &[Value]) -> Vec<Value> {
    let mut stations = BTreeMap::new();
    for (field, observed) in [("forecastStations", false), ("observations", true)] {
        for (index, r) in rows(&m["jmaDetails"][field]).enumerate() {
            let mut row = base(
                s(r, "code"),
                s(r, "name"),
                &r["latitude"],
                &r["longitude"],
                &s(r, "regionName"),
                &s(r, "regionCode"),
            );
            let key = station_key(&row);
            if let Some(previous) = stations.remove(&key) {
                row = previous;
            }
            if observed {
                row["observed"] = reading(
                    &r["maxHeight"],
                    "m",
                    &s(r, "maxTime"),
                    9,
                    "maximumWaveHeight",
                    &s(r, "maxCondition"),
                );
                row["observed"]["description"] = r["maxHeightDesc"].clone();
                row["observed"]["heightCondition"] = r["maxHeightCond"].clone();
                row["observed"]["revision"] = r["maxRevise"].clone();
                // Qualified/lower-bound values remain text, not an exact scalar.
                if !s(r, "maxHeightCond").is_empty() || s(r, "maxHeightDesc").contains("以上") {
                    row["observed"]["metres"] = Value::Null;
                }
                row["firstArrivalTime"] = r["firstArrivalTime"].clone();
                row["firstArrivalCondition"] = r["firstCondition"].clone();
                row["firstInitial"] = r["firstInitial"].clone();
                row["observationSourcePath"] = json!(format!("jmaDetails.{field}[{index}]"));
            } else {
                // JMA supplies a station arrival and regional forecast height;
                // do not promote the latter to a station-specific prediction.
                row["forecastArrivalTime"] = r["arrivalTime"].clone();
                row["forecastArrivalCondition"] = r["condition"].clone();
                row["highTideTime"] = r["highTide"].clone();
                row["forecastSourcePath"] = json!(format!("jmaDetails.{field}[{index}]"));
            }
            bind(&mut row, areas);
            stations.insert(key, row);
        }
    }
    stations.into_values().collect()
}
fn nmefc(m: &Value, areas: &[Value]) -> Vec<Value> {
    rows(&m["observations"])
        .map(|r| {
            let mut row = base(
                s(r, "stationId"),
                s(r, "stationName"),
                &r["latitude"],
                &r["longitude"],
                &s(r, "location"),
                "",
            );
            row["observed"] = reading(
                &r["maxWaveHeight"],
                "cm",
                &s(r, "time"),
                8,
                "maximumWaveHeight",
                &s(r, "condition"),
            );
            if let Some((index, _)) = rows(&m["sourcePayload"]["waterLevelMonitoring"])
                .enumerate()
                .find(|(_, a)| {
                    (!s(a, "stationId").is_empty() && a["stationId"] == r["stationId"])
                        || (a["stationName"] == r["stationName"] && a["location"] == r["location"])
                })
            {
                row["observationSourcePath"] =
                    json!(format!("sourcePayload.waterLevelMonitoring[{index}]"));
            }
            bind(&mut row, areas);
            row
        })
        .collect()
}
fn cwa(m: &Value) -> Vec<Value> {
    rows(&m["observations"])
        .map(|r| {
            let mut row = base(
                s(r, "stationId"),
                s(r, "stationName"),
                &r["latitude"],
                &r["longitude"],
                "",
                "",
            );
            // The documented arrivalTime is an arrival, not the sampling time.
            // Nor does this contract identify waveHeight as the maximum so far.
            row["observed"] = reading(
                &r["maxWaveHeight"],
                "",
                "",
                8,
                "reportedWaveHeight",
                &s(r, "condition"),
            );
            row["firstArrivalTime"] = r["time"].clone();
            row["bulletinTime"] = m["reportTime"].clone();
            if let Some((index, _)) =
                rows(&m["sourcePayload"]["stations"])
                    .enumerate()
                    .find(|(_, a)| {
                        (!s(a, "stationId").is_empty() && a["stationId"] == r["stationId"])
                            || (!s(a, "stationName").is_empty()
                                && a["stationName"] == r["stationName"])
                    })
            {
                row["observationSourcePath"] = json!(format!("sourcePayload.stations[{index}]"));
            }
            row
        })
        .collect()
}
fn noaa_grade(category: &str) -> &'static str {
    match category.to_lowercase().as_str() {
        "warning" => "warning",
        "advisory" | "watch" => "watch",
        _ => "none",
    }
}
fn coast_name(a: &Value) -> String {
    let start = s(a, "bkp_start_location");
    let end = s(a, "bkp_end_location");
    if start.is_empty() {
        end
    } else if end.is_empty() || start == end {
        start
    } else {
        format!("{start} - {end}")
    }
}
pub(super) fn is_current(previous: &Value, incoming: &Value) -> bool {
    let stamp = |m: &Value| {
        absolute(
            &s(m, "reportTime"),
            m["timeZone"].as_i64().unwrap_or(8) * 60,
        )
    };
    match (stamp(previous), stamp(incoming)) {
        (Some(_), None) => false,
        (Some(p), Some(n)) if n < p => false,
        (Some(p), Some(n)) if n == p => {
            !(s(previous, "bulletinLevel").eq_ignore_ascii_case("cancellation") && active(incoming))
        }
        _ => true,
    }
}
pub(super) fn noaa_detail(c: &Value) -> Result<Value, String> {
    let detail: Value =
        serde_json::from_str(c["json"].as_str().unwrap_or("")).map_err(|e| e.to_string())?;
    if !detail.is_object() {
        return Err("NOAA detail must be an object".into());
    }
    let path = s(c, "requestedPath");
    let event_dir = s(&detail, "eventDir");
    if !path.is_empty() && !event_dir.is_empty() && !path.starts_with(&event_dir) {
        return Err("NOAA response belongs to a different event directory".into());
    }
    let mut areas = vec![];
    for group in detail["alerts"]["areaList"]
        .as_array()
        .into_iter()
        .flatten()
    {
        let entries = if group.is_array() {
            group.as_array().unwrap().iter().collect::<Vec<_>>()
        } else {
            vec![group]
        };
        for a in entries {
            let grade = noaa_grade(&s(a, "category"));
            let name = coast_name(a);
            if grade != "none" && !name.is_empty() {
                let category=s(a,"category");
                let colour=match category.to_lowercase().as_str(){"warning"=>"red","advisory"=>"orange","watch"=>"yellow",_=>"gray"};
                areas.push(json!({"name":name,"grade":grade,"condition":category,"className":colour}));
            }
        }
    }
    Ok(json!({"detail":detail,"areas":areas}))
}
pub(super) fn incois_detail(c: &Value) -> Result<Value, String> {
    let documents: Value =
        serde_json::from_str(c["json"].as_str().unwrap_or("")).map_err(|e| e.to_string())?;
    if !documents.is_array() {
        return Err("INCOIS bulletin must be an array".into());
    }
    Ok(json!({"documents":documents}))
}
fn incois(m: &Value) -> (Vec<Value>, Vec<Value>) {
    let mut forecasts = vec![];
    let mut stations = vec![];
    for (document_index, document) in rows(&m["officialDetail"]["documents"]).enumerate() {
        for (event_index, event) in rows(&document["event_info"]).enumerate() {
            // Reject a mismatched official response; never mix earthquake series.
            if !s(m, "eventId").is_empty() && s(event, "eventid") != s(m, "eventId") {
                continue;
            }
            if m["reportNumber"]
                .as_u64()
                .is_some_and(|n| s(event, "bulletinNumber") != n.to_string())
            {
                continue;
            }
            for group in rows(&event["ZONES"]) {
                for r in rows(&group["ZONE"]) {
                    let status = s(r, "THREAT_STATUS");
                    let grade = match status.as_str() {
                        "Warning" | "Threat" | "Alert" => "warning",
                        "Watch" => "watch",
                        _ => "none",
                    };
                    let mut forecast = reading(
                        &r["MAX_BEACH"],
                        "m",
                        &s(r, "T2"),
                        0,
                        "forecastCoastalAmplitude",
                        &status,
                    );
                    // Official NTWC tables use IST. Preserve source time strings,
                    // including those lacking a full date, without inventing one.
                    forecast["timeZone"] = json!(5.5);
                    forecast["timeUtcMs"] = json!(absolute(&s(r, "T2"), 330).map(|t|t/1000));
                    forecasts.push(json!({"name":r["PLACE_NAME"],"state":r["STATE_PROV"],
                        "country":r["COUNTRY_NAME"],"grade":grade,"active":grade!="none","forecast":forecast}));
                }
            }
            for (group_index, group) in rows(&event["SeaLevelObservations"]).enumerate() {
                for (index, r) in rows(&group["Station"]).enumerate() {
                    let legacy = r["NAME"].is_null() && r["StationName"].is_string();
                    let coordinate = |key: &str| {
                        let raw=s(r,key); let value=raw.trim();
                        let (numeric,sign)=match value.chars().last(){
                            Some('N'|'E')=>(value[..value.len()-1].trim(),1.0),
                            Some('S'|'W')=>(value[..value.len()-1].trim(),-1.0),
                            _=>(value,1.0),
                        };
                        json!(numeric.parse::<f64>().ok().filter(|n|n.is_finite()).map(|n|n*sign))
                    };
                    let lat=if legacy{coordinate("Latitude")}else{r["STATIONLAT"].clone()};
                    let lon=if legacy{coordinate("Longitude")}else{r["STATIONLON"].clone()};
                    let mut row = base(
                        String::new(),
                        s(r, if legacy{"StationName"}else{"NAME"}),
                        &lat,
                        &lon,
                        "",
                        "",
                    );
                    let mut observed = reading(
                        &r[if legacy{"WAVEAMPLITUDE"}else{"WAVEHEIGHT"}],
                        if legacy{""}else{"m"}, "", 0, "reportedWaveAmplitude", "");
                    observed["timeZone"] = json!(5.5);
                    row["observed"] = observed;
                    row["firstArrivalTime"] = r["WAVEARRIVALTIME"].clone();
                    row["country"] = r["COUNTRY"].clone();
                    row["bulletinTime"] = event["bulletinIssueTime"].clone();
                    row["observationSourcePath"] = json!(format!("officialDetail.documents[{document_index}].event_info[{event_index}].SeaLevelObservations[{group_index}].Station[{index}]"));
                    // These tables do not prove which coastal forecast area a
                    // tide gauge belongs to. Geometry binding is a later step.
                    stations.push(row);
                }
            }
        }
    }
    (forecasts, stations)
}
fn noaa(m: &Value) -> Vec<Value> {
    let detail = &m["officialDetail"];
    rows(&detail["observations"])
        .enumerate()
        .map(|(index, r)| {
            let code = text(&r["siteSegmentID"]);
            let segment = rows(&detail["segments"])
                .find(|a| text(&a["id"]) == code && code != "0" && !code.is_empty());
            let name = segment.map(coast_name).unwrap_or_default();
            let mut row = base(
                s(r, "id"),
                s(r, "locationName"),
                &r["lat"],
                &r["lon"],
                &name,
                &code,
            );
            row["country"] = r["locationCountry"].clone();
            row["forecast"] = reading(
                &r["predictedPosAmplitude"],
                &s(r, "predictedPosAmplitudeUnits"),
                &s(r, "predictedArrivalTime"),
                0,
                "predictedPositiveAmplitude",
                "",
            );
            // NOAA includes zero-filled placeholders before any observation. A
            // zero with a valid measurement time remains a real observation.
            let observed_time = absolute(&s(r, "observedMaxTime"), 0);
            let origin = absolute(&s(detail, "originTime"), 0);
            let issued = absolute(&s(detail, "bulletinIssueTime"), 0);
            if observed_time.is_some_and(|t| t > 0
                && origin.is_none_or(|o| t >= o)
                && issued.is_none_or(|i| t <= i)) {
                row["observed"] = reading(
                    &r["observedPosAmplitude"],
                    &s(r, "observedPosAmplitudeUnits"),
                    &s(r, "observedMaxTime"),
                    0,
                    "maximumPositiveAmplitude",
                    "",
                );
            }
            row["forecastSourcePath"] = json!(format!("officialDetail.observations[{index}]"));
            row["observationSourcePath"] = row["forecastSourcePath"].clone();
            if let Some(a) = segment {
                let grade = noaa_grade(&s(a, "category"));
                row["binding"] = json!("sourceSegment");
                row["grade"] = json!(grade);
                row["areaActive"] = json!(grade != "none");
            }
            row
        })
        .collect()
}
pub(super) fn project(m: &Value, now_ms: i64) -> Value {
    let mut areas = area_forecasts(m);
    let zone = m["timeZone"].as_i64().unwrap_or(9);
    let expires = absolute(&s(m, "expires"), zone * 60);
    let warning_active = active(m)
        && !s(m, "bulletinLevel").eq_ignore_ascii_case("cancellation")
        && expires.is_none_or(|t| now_ms <= 0 || t / 1000 > now_ms);
    let mut stations = match s(m, "source").as_str() {
        "jma" => jma(m, &areas),
        "nmefc" => nmefc(m, &areas),
        "cwa" => cwa(m),
        "ptwc" | "ntwc" => noaa(m),
        "incois" => {
            let (forecasts, stations) = incois(m);
            areas.extend(forecasts);
            stations
        }
        _ => vec![],
    };
    for r in &mut stations {
        r["mapEligible"] = json!(
            warning_active
                && r["areaActive"] == true
                && r["latitude"].is_number()
                && r["longitude"].is_number()
        );
    }
    json!({"schemaVersion":1,"warningActive":warning_active,"expiresUtcMs":expires.map(|t|t/1000),
        "reportTime":m["reportTime"],"areaForecasts":areas,"stations":stations})
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn kamchatka_original_b12_keeps_30_timed_observations() {
        let detail: Value = serde_json::from_str(include_str!(
            "../../../test/fixtures/tsunami_regions/ntwc_kamchatka_20250730_B12.original.json"
        )).unwrap();
        let message = json!({"source":"ntwc","grade":"watch","officialDetail":detail});
        let original = message.clone();
        let view = project(&message, 0);
        let stations = view["stations"].as_array().unwrap();
        assert_eq!(stations.len(), 298);
        assert_eq!(stations.iter().filter(|s| !s["observed"].is_null()).count(), 30);
        assert_eq!(stations.iter().filter(|s| !s["observed"].is_null() && s["mapEligible"] == true).count(), 30);
        assert_eq!(message, original);
    }
    #[test]
    fn noaa_epoch_placeholder_and_readings_outside_the_event_are_not_observations() {
        // Explicit protocol validation, not an altered historical capture.
        for time in ["1970-01-01T00:00:00Z", "2025-07-28T00:00:00Z", "2025-08-01T00:00:00Z"] {
            let message = json!({"source":"ntwc","grade":"watch","officialDetail":{
                "originTime":"2025-07-29T23:24:52Z", "bulletinIssueTime":"2025-07-30T10:20:48Z",
                "observations":[{"id":1,"locationName":"protocol validation","lat":50,"lon":170,
                    "observedMaxTime":time,"observedPosAmplitude":"0.79","observedPosAmplitudeUnits":"feet"}]}});
            let original = message.clone();
            assert!(project(&message,0)["stations"][0]["observed"].is_null());
            assert_eq!(message, original);
        }
    }
    #[test]
    fn original_noaa_detail_keeps_all_295_stations_and_rejects_unmeasured_zeros() {
        let raw = include_str!("../../../test/fixtures/noaa_ntwc_advisory_20250918.json");
        let detail = noaa_detail(&json!({"json":raw})).unwrap();
        assert_eq!(
            detail["detail"],
            serde_json::from_str::<Value>(raw).unwrap()
        );
        assert_eq!(detail["areas"].as_array().unwrap().len(), 1);
        let message = json!({"source":"ntwc","grade":"watch","officialDetail":detail["detail"]});
        let data = project(&message, 0);
        let stations = data["stations"].as_array().unwrap();
        assert_eq!(stations.len(), 295);
        assert!(stations.iter().all(|r| r["observed"].is_null()));
        assert_eq!(stations[0]["forecast"]["unit"], "feet");
        assert_eq!(stations[0]["forecast"]["metres"], 0.0);
        assert_eq!(stations[0]["mapEligible"], false); // Segment 0 is unassigned.
        assert_eq!(stations[1]["mapEligible"], true);
        assert_eq!(stations[1]["binding"], "sourceSegment");
        assert_eq!(stations[1]["regionName"], detail["areas"][0]["name"]);
    }
    // These are protocol edge cases, not captured measurements.
    #[test]
    fn measured_zero_feet_conversion_and_qualified_values_are_distinct() {
        assert_eq!(metres(&json!("2"), "feet"), Some(0.6096));
        assert_eq!(metres(&json!("80cm"), ""), Some(0.8));
        assert_eq!(metres(&json!("80-100"), "cm"), None);
        assert_eq!(metres(&json!("80以上"), "cm"), None);
        assert_eq!(metres(&json!("1"), ""), None);
        let m = json!({"source":"ptwc","grade":"warning","officialDetail":{"observations":[{
            "id":1,"observedMaxTime":"2026-10-22T04:00:00Z","observedPosAmplitude":"0.0",
            "observedPosAmplitudeUnits":"feet"}]}});
        let data = project(&m, 0);
        assert_eq!(data["stations"][0]["observed"]["metres"], 0.0);
        assert_eq!(
            data["stations"][0]["observed"]["kind"],
            "maximumPositiveAmplitude"
        );
    }
    #[test]
    fn jma_documented_stations_keep_forecast_and_observation_meanings_separate() {
        let raw: Value = serde_json::from_str(include_str!(
            "../../../test/fixtures/jma_tsunami/whews.forecast_stations.documented.json"
        ))
        .unwrap();
        let mut m = super::super::parse("whews", &raw["Data"]).unwrap();
        let observation: Value = serde_json::from_str(&format!(
            "{{{}}}",
            include_str!(
                "../../../test/fixtures/jma_tsunami/whews.observations.documented.fragment.txt"
            )
        ))
        .unwrap();
        super::super::observations::attach("whews", &observation, &mut m);
        // Independent actual source records, not a claimed co-located pair.
        let observed = project(&m, 0);
        let r = &observed["stations"][0];
        assert_eq!(r["observed"]["metres"], 0.8);
        assert_eq!(r["firstInitial"], "押し");
        assert_eq!(r["latitude"], Value::Null); // No invented position.
        let forecast = super::super::parse("whews", &raw["Data"]).unwrap();
        let data = project(&forecast, 0);
        assert_eq!(data["stations"][0]["stationId"], "71201");
        assert_eq!(data["stations"][0]["forecast"], Value::Null);
        assert_eq!(data["stations"][0]["areaForecast"]["metres"], 1.0);
        assert_eq!(
            data["stations"][0]["forecastArrivalTime"],
            "2026-07-28 17:00:00"
        );
    }
    #[test]
    fn nmefc_exact_region_binding_expiry_and_unknown_positions() {
        let m = json!({"source":"nmefc","grade":"watch","timeZone":8,"expires":"2026-10-22 12:30:00",
            "areas":[{"name":"protocol region","grade":"watch","height":1.0}],
            "observations":[{"stationName":"protocol station","location":"protocol region","latitude":25,
                "longitude":121,"time":"2026-10-22 12:00:00","maxWaveHeight":"60cm"},
                {"stationName":"unknown region station","location":"other region","maxWaveHeight":"80-100cm"}]});
        let before = project(&m, absolute("2026-10-22 12:00:00", 480).unwrap()/1000);
        assert_eq!(before["stations"][0]["observed"]["metres"], 0.6);
        assert_eq!(
            before["stations"][0]["observed"]["timeUtcMs"],
            json!(absolute("2026-10-22T04:00:00Z", 0).map(|t|t/1000))
        );
        assert_eq!(before["stations"][0]["mapEligible"], true);
        assert_eq!(before["stations"][1]["areaForecast"], Value::Null);
        assert_eq!(before["stations"][1]["observed"]["metres"], Value::Null);
        let after = project(&m, absolute("2026-10-22 12:30:00", 480).unwrap()/1000);
        assert_eq!(after["warningActive"], false);
        assert_eq!(after["stations"][0]["mapEligible"], false);
        let mut cancelled = m.clone();
        cancelled["bulletinLevel"] = json!("Cancellation");
        let cancel = project(&cancelled, 0);
        assert_eq!(cancel["stations"][0]["mapEligible"], false);
    }
    #[test]
    fn cwa_arrival_is_not_measurement_time_and_missing_unit_is_not_metres() {
        let m = json!({"source":"cwa","grade":"warning","observations":[{"stationId":"protocol",
            "stationName":"protocol station","latitude":24,"longitude":121,
            "maxWaveHeight":"0.8","time":"2026-10-22 12:00:00"}]});
        let data = project(&m, 0);
        let r = &data["stations"][0];
        assert_eq!(r["observed"]["kind"], "reportedWaveHeight");
        assert_eq!(r["observed"]["metres"], Value::Null);
        assert_eq!(r["observed"]["timeUtcMs"], Value::Null);
        assert_eq!(r["firstArrivalTime"], "2026-10-22 12:00:00");
        assert_eq!(r["binding"], "unresolved");
    }
    #[test]
    fn incois_original_information_has_no_fabricated_stations() {
        let source =
            include_str!("../../../test/fixtures/tsunami_regions/incois_20260820_B1.original.json");
        let detail = incois_detail(&json!({"json":source})).unwrap();
        assert_eq!(
            detail["documents"],
            serde_json::from_str::<Value>(source).unwrap()
        );
        let data = project(
            &json!({"source":"incois","grade":"none","eventId":"incois2026qmbb","officialDetail":detail}),
            0,
        );
        assert_eq!(data["stations"], json!([]));
    }
    #[test]
    fn documented_incois_protocol_keeps_station_wave_and_coastal_prediction_separate() {
        // Protocol cases using field names from INCOIS's official frontend.
        // Not actual observations or a historical warning.
        let m = json!({"source":"incois","grade":"warning","eventId":"protocol","reportNumber":3,
            "officialDetail":{"documents":[{"event_info":[{"eventid":"protocol","bulletinNumber":"3",
            "ZONES":[{"ZONE":[{"PLACE_NAME":"protocol coast","THREAT_STATUS":"Warning","MAX_BEACH":"1.5","T2":"12:00"}]}],
            "SeaLevelObservations":[{"Station":[{"NAME":"protocol station","STATIONLAT":"12.5","STATIONLON":"80.2",
                "WAVEHEIGHT":"0.6","WAVEARRIVALTIME":"11:50","COUNTRY":"India"}]}]}]}]}});
        let data = project(&m, 0);
        assert_eq!(data["areaForecasts"][0]["forecast"]["metres"], 1.5);
        assert_eq!(data["areaForecasts"][0]["forecast"]["timeZone"], 5.5);
        assert_eq!(
            data["areaForecasts"][0]["forecast"]["timeUtcMs"],
            Value::Null
        );
        assert_eq!(data["stations"][0]["observed"]["metres"], 0.6);
        assert_eq!(data["stations"][0]["firstArrivalTime"], "11:50");
        assert_eq!(data["stations"][0]["areaForecast"], Value::Null);
        let mut other = m.clone();
        other["eventId"] = json!("different-event");
        assert_eq!(project(&other, 0)["stations"], json!([]));
    }
    #[test]
    fn late_older_bulletin_does_not_invalidate_pending_current_detail() {
        let latest = json!({"reportTime":"2026-10-22 12:02:00","timeZone":8,"grade":"warning"});
        let old = json!({"reportTime":"2026-10-22 12:00:00","timeZone":8,"grade":"warning"});
        assert!(!is_current(&latest, &old));
        let mut cancelled = latest.clone();
        cancelled["bulletinLevel"] = json!("Cancellation");
        assert!(!is_current(&cancelled, &latest));
    }
}
