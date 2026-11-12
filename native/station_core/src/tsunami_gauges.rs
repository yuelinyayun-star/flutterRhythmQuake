//! Map presentation plans, prepared only on a bulletin/geometry change.
//! Coordinates are source stations or points on the existing warning coastline.
use super::{number, s, text, wave_data};
use serde_json::{json, Value};
use std::collections::BTreeMap;
use std::sync::{Arc, Mutex, OnceLock};
use sha2::{Digest, Sha256};

type CoastAnchors = BTreeMap<String, [f64; 2]>;
type CoastCache = Option<([u8; 32], Arc<CoastAnchors>)>;
static JMA_ANCHORS: OnceLock<Mutex<CoastCache>> = OnceLock::new();

fn rows(v: &Value) -> impl Iterator<Item = &Value> {
    v.as_array().into_iter().flatten()
}
fn metres(v: &Value) -> Option<f64> {
    number(&v["metres"]).filter(|n| *n >= 0.0)
}
fn scalar(n: f64) -> String {
    if n > 0.0 && n < 0.001 {
        return "<0.001".into();
    }
    let t = if n < 0.1 {
        format!("{n:.3}")
    } else if n < 10.0 {
        format!("{n:.2}")
    } else {
        format!("{n:.1}")
    };
    t.trim_end_matches('0').trim_end_matches('.').to_owned()
}
fn label(v: &Value) -> (String, String) {
    if let Some(n) = metres(v) {
        return (scalar(n), "m".into());
    }
    let raw = text(&v["value"]);
    let qualified = s(v, "heightCondition");
    if !qualified.is_empty() || s(v, "description").contains("以上") {
        let description = s(v, "description");
        if (description.contains("以上") || qualified == "以上") && number(&v["value"]).is_some()
        {
            return (format!("≥{}", text(&v["value"])), s(v, "unit"));
        }
        return (
            if description.is_empty() {
                format!("{}{}{}", raw, s(v, "unit"), qualified)
            } else {
                description
            },
            String::new(),
        );
    }
    if raw.is_empty() {
        return (
            if s(v, "condition").is_empty() {
                "—".into()
            } else {
                s(v, "condition")
            },
            String::new(),
        );
    }
    let unit = s(v, "unit");
    let has_unit = raw.ends_with(&unit) && !unit.is_empty()
        || ["m", "ｍ", "米", "公尺", "公分", "厘米", "feet", "ft"]
            .iter()
            .any(|u| raw.ends_with(u));
    let numeric = raw.chars().any(|c| c.is_numeric());
    (
        raw,
        if has_unit || !numeric {
            String::new()
        } else if unit.is_empty() {
            "?".into()
        } else {
            unit
        },
    )
}
fn best<'a>(items: impl Iterator<Item = &'a Value>) -> Value {
    let nonempty = items
        .filter(|v| {
            metres(v).is_some() || !text(&v["value"]).is_empty() || !s(v, "condition").is_empty()
        })
        .collect::<Vec<_>>();
    if nonempty.len() == 1 {
        return nonempty[0].clone();
    }
    // A range, bound or unknown unit cannot be ranked against exact metres.
    if nonempty
        .iter()
        .any(|v| metres(v).is_none() && text(&v["value"]).chars().any(|c| c.is_numeric()))
    {
        if nonempty.iter().all(|r| {
            r["value"] == nonempty[0]["value"]
                && r["unit"] == nonempty[0]["unit"]
                && r["description"] == nonempty[0]["description"]
                && r["heightCondition"] == nonempty[0]["heightCondition"]
        }) {
            return nonempty[0].clone();
        }
        return json!({"value":"见详情","kind":"reportedWaveHeight"});
    }
    let maximum = nonempty
        .iter()
        .copied()
        .filter(|v| metres(v).is_some())
        .max_by(|a, b| metres(a).unwrap().total_cmp(&metres(b).unwrap()))
        .cloned();
    maximum.unwrap_or_else(|| {
        if nonempty.is_empty() {
            Value::Null
        } else if nonempty
            .iter()
            .all(|r| r["value"] == nonempty[0]["value"] && r["unit"] == nonempty[0]["unit"])
        {
            nonempty[0].clone()
        } else {
            json!({"value":"见详情","kind":"reportedWaveHeight"})
        }
    })
}
fn point(v: &Value) -> Option<[f64; 2]> {
    let p = [number(&v[0])?, number(&v[1])?];
    (p[0].abs() <= 180.0 && p[1].abs() <= 90.0).then_some(p)
}
fn delta_lon(v: f64) -> f64 {
    (v + 180.0).rem_euclid(360.0) - 180.0
}
fn distance(a: [f64; 2], b: [f64; 2]) -> f64 {
    let x = delta_lon(b[0] - a[0]) * ((a[1] + b[1]) / 2.0).to_radians().cos();
    x.hypot(b[1] - a[1])
}
fn coast_anchor(region: &Value) -> Option<[f64; 2]> {
    let lines = rows(&region["lines"])
        .map(|l| rows(l).filter_map(point).collect::<Vec<_>>())
        .filter(|l| l.len() > 1)
        .collect::<Vec<_>>();
    let length = |l: &Vec<[f64; 2]>| l.windows(2).map(|p| distance(p[0], p[1])).sum::<f64>();
    let line = lines
        .iter()
        .max_by(|a, b| length(a).total_cmp(&length(b)))?;
    let mut remaining = length(line) / 2.0;
    for pair in line.windows(2) {
        let len = distance(pair[0], pair[1]);
        if len > 0.0 && remaining <= len {
            let t = remaining / len;
            return Some([
                delta_lon(pair[0][0] + delta_lon(pair[1][0] - pair[0][0]) * t),
                pair[0][1] + (pair[1][1] - pair[0][1]) * t,
            ]);
        }
        remaining -= len;
    }
    line.first().copied()
}
fn arc_ids(v: &Value, out: &mut Vec<i64>) {
    if let Some(n) = v.as_i64() {
        out.push(n);
    } else {
        for child in rows(v) {
            arc_ids(child, out);
        }
    }
}
fn jma_regions(raw: &str) -> Result<Vec<Value>, String> {
    let topo: Value = serde_json::from_str(raw).map_err(|e| e.to_string())?;
    let transformed = topo["transform"].is_object();
    let sx = number(&topo["transform"]["scale"][0]).unwrap_or(1.0);
    let sy = number(&topo["transform"]["scale"][1]).unwrap_or(1.0);
    let tx = number(&topo["transform"]["translate"][0]).unwrap_or(0.0);
    let ty = number(&topo["transform"]["translate"][1]).unwrap_or(0.0);
    let arcs = rows(&topo["arcs"])
        .map(|r| {
            let mut x = 0.0;
            let mut y = 0.0;
            rows(r)
                .filter_map(|v| {
                    let a = number(&v[0])?;
                    let b = number(&v[1])?;
                    if transformed {
                        x += a;
                        y += b;
                    } else {
                        x = a;
                        y = b;
                    }
                    Some(json!([x * sx + tx, y * sy + ty]))
                })
                .collect::<Vec<_>>()
        })
        .collect::<Vec<_>>();
    let mut regions = vec![];
    for object in topo["objects"]
        .as_object()
        .into_iter()
        .flat_map(|o| o.values())
    {
        for g in rows(&object["geometries"]) {
            let mut ids = vec![];
            arc_ids(&g["arcs"], &mut ids);
            let lines = ids
                .iter()
                .filter_map(|id| {
                    let i = if *id < 0 { !*id } else { *id } as usize;
                    let mut line = arcs.get(i)?.clone();
                    if *id < 0 {
                        line.reverse();
                    }
                    Some(line)
                })
                .collect::<Vec<_>>();
            regions.push(json!({"name":g["properties"]["name"],"code":g["properties"]["code"],"lines":lines}));
        }
    }
    Ok(regions)
}
fn jma_anchors(raw: &str) -> Result<Arc<CoastAnchors>, String> {
    let key: [u8; 32] = Sha256::digest(raw.as_bytes()).into();
    // One asset revision only; retain names/anchors, never full decoded arcs.
    let mut cache = JMA_ANCHORS.get_or_init(|| Mutex::new(None))
        .lock().unwrap_or_else(|e| e.into_inner());
    if let Some((old, anchors)) = cache.as_ref() {
        if *old == key { return Ok(Arc::clone(anchors)); }
    }
    let anchors = Arc::new(jma_regions(raw)?.iter()
        .filter_map(|r| coast_anchor(r).map(|p| (s(r, "name"), p)))
        .collect());
    *cache = Some((key, Arc::clone(&anchors)));
    Ok(anchors)
}
fn station_position(v: &Value) -> Option<[f64; 2]> {
    point(&json!([v["longitude"], v["latitude"]]))
}
fn observation_kind(v: &Value) -> &'static str {
    match s(v, "kind").as_str() {
        "maximumWaveHeight" | "maximumPositiveAmplitude" => "最大观测",
        _ => "观测波高",
    }
}
fn reading_detail(v: &Value) -> String {
    let description = s(v, "description");
    if !description.is_empty() {
        return description;
    }
    let (value, unit) = label(v);
    let raw = text(&v["value"]);
    if unit == "?" {
        return format!("{raw}（单位未提供）");
    }
    let formatted = format!("{value}{unit}");
    if !raw.is_empty()
        && !s(v, "unit").is_empty()
        && !raw.ends_with(&s(v, "unit"))
        && formatted != format!("{raw}{}", s(v, "unit"))
    {
        format!("{formatted}（原值 {raw}{}）", s(v, "unit"))
    } else {
        formatted
    }
}
fn entry(
    id: String,
    name: String,
    scope: &str,
    p: [f64; 2],
    forecast: Value,
    observed: Value,
    regional: bool,
    stations: &[&Value],
) -> Value {
    let mut details = vec![json!({"label":if regional{"预报区域"}else{"测站"},"value":name})];
    if !forecast.is_null() {
        details.push(json!({"label":if scope=="stationMaximum"{"站点预计最高"}else if scope=="region"{"区域预计"}else{"预计"},"value":reading_detail(&forecast)}));
        if !s(&forecast, "time").is_empty() {
            details.push(json!({"label":"预计到达（源时间）","value":forecast["time"]}));
        }
    }
    for station in stations {
        let reading = &station["observed"];
        if reading.is_null() {
            continue;
        }
        let station_name = s(station, "stationName");
        details.push(json!({"label":format!("{} · {}",station_name,observation_kind(reading)),"value":reading_detail(reading)}));
        if !s(reading, "time").is_empty() {
            details.push(json!({"label":"观测时间（源时间）","value":format!("{} (UTC{:+})",s(reading,"time"),reading["timeZone"].as_f64().unwrap_or(0.0))}));
        }
        if !s(reading, "condition").is_empty() {
            details.push(json!({"label":"观测状态","value":reading["condition"]}));
        }
    }
    json!({"id":id,"name":name,"isRegion":regional,"longitude":p[0],"latitude":p[1],
        "forecast":forecast,"observed":observed,"forecastScope":scope,"details":details})
}
// Normalized SREV square-root camera scaling, mirrored by the widget.
fn marker_scale(zoom: u32) -> f64 {
    (0.78 * (4.0 + 10.0 * 2.0_f64.powf((zoom as f64 - 5.0) / 2.0)) / 14.0).clamp(0.30, 1.60)
}
fn finalize(cluster: &[usize], entries: &[Value], scale: f64) -> Value {
    let first = &entries[cluster[0]];
    let forecast = best(cluster.iter().map(|i| &entries[*i]["forecast"]));
    let observed = best(cluster.iter().map(|i| &entries[*i]["observed"]));
    let mut value = first.clone();
    let (forecast_text, forecast_unit) = label(&forecast);
    let (mut observation_text, mut observation_unit) = label(&observed);
    if observation_unit.is_empty() {
        for unit in ["cm", "feet", "ft", "m", "ｍ", "米", "公分", "厘米"] {
            if let Some(value) = observation_text.strip_suffix(unit) {
                if value.chars().any(|c| c.is_numeric()) {
                    observation_unit = unit.into();
                    observation_text = value.trim().to_owned();
                    break;
                }
            }
        }
    }
    // Keep the narrow readout legible; the click details retain the full text.
    let cells = observation_text
        .chars()
        .map(|c| if c.is_ascii() { 1 } else { 2 })
        .sum::<usize>();
    if cells > 6 {
        observation_text = "详情".into();
        observation_unit = String::new();
    }
    let unknown_forecasts = cluster.len() > 1
        && cluster.iter().any(|i| {
            !entries[*i]["forecast"].is_null() && metres(&entries[*i]["forecast"]).is_none()
        });
    value["forecastText"] = json!(if unknown_forecasts {
        "分区".to_owned()
    } else {
        forecast_text
    });
    value["forecastUnit"] = json!(if unknown_forecasts {
        String::new()
    } else {
        forecast_unit
    });
    value["forecastLabel"] = json!(if unknown_forecasts {
        "分区预计"
    } else if cluster.len() > 1 {
        "预计最高"
    } else if s(first, "forecastScope") == "stationMaximum" {
        "站点预计最高"
    } else if s(first, "forecastScope") == "region" {
        "区域预计"
    } else {
        "预计"
    });
    value["observationText"] = json!(observation_text);
    value["observationUnit"] = json!(observation_unit);
    value["observationLabel"] = json!(if observed.is_null() {
        "待观测"
    } else {
        observation_kind(&observed)
    });
    value["forecastFraction"] = json!(if unknown_forecasts {
        None
    } else {
        metres(&forecast).map(|m| (m / scale).clamp(0.0, 1.0))
    });
    value["observedFraction"] = json!(metres(&observed).map(|m| (m / scale).clamp(0.0, 1.0)));
    value["name"] = json!(if cluster.len() > 1 {
        format!(
            "{} 等{}{}",
            s(first, "name"),
            cluster.len(),
            if first["isRegion"] == true {
                "区"
            } else {
                "站"
            }
        )
    } else {
        s(first, "name")
    });
    value["members"] = json!(cluster);
    // Details stay on base entries; do not copy every station list per zoom.
    value.as_object_mut().unwrap().remove("details");
    value.as_object_mut().unwrap().remove("forecast");
    value.as_object_mut().unwrap().remove("observed");
    value
}
pub(super) fn prepare(c: &Value) -> Result<Value, String> {
    let m = &c["message"];
    let data = wave_data::project(m, c["nowMs"].as_i64().unwrap_or(0));
    if data["warningActive"] != true {
        return Ok(json!({"entries":[],"markers":[],"levels":[]}));
    }
    let jma = (s(m, "source") == "jma")
        .then(|| jma_anchors(c["jmaTopology"].as_str().unwrap_or("{}")))
        .transpose()?;
    let regions = rows(&c["regions"]).collect::<Vec<_>>();
    let stations = rows(&data["stations"]).collect::<Vec<_>>();
    let mut stations_by_region: BTreeMap<String, Vec<&Value>> = BTreeMap::new();
    for station in &stations {
        if station["areaActive"] == true {
            stations_by_region.entry(s(station, "regionName")).or_default().push(station);
        }
    }
    let mut entries = vec![];
    let mut regional_indices = vec![];
    let mut station_indices = vec![];
    let mut regional_station_indices: BTreeMap<String, Vec<usize>> = BTreeMap::new();
    let mut area_names = rows(&data["areaForecasts"])
        .filter(|a| a["active"] == true)
        .map(|a| s(a, "name"))
        .collect::<Vec<_>>();
    for station in &stations {
        let name = s(station, "regionName");
        if station["areaActive"] == true && !name.is_empty() && !area_names.contains(&name) {
            area_names.push(name);
        }
    }
    for name in &area_names {
        let matching = stations_by_region.get(name).map(Vec::as_slice).unwrap_or_default();
        let area = rows(&data["areaForecasts"]).find(|a| s(a, "name") == *name);
        let region = regions.iter().find(|r| s(r, "name") == *name);
        let anchor = jma.as_ref().and_then(|anchors| anchors.get(name).copied())
            .or_else(|| region.and_then(|r| coast_anchor(r))).or_else(|| {
            matching
                .iter()
                .filter(|r| r["mapEligible"] == true)
                .find_map(|r| station_position(r))
        });
        let Some(anchor) = anchor else {
            continue;
        };
        let official_forecast = area.map(|a| a["forecast"].clone()).unwrap_or(Value::Null);
        let regional_height =
            metres(&official_forecast).is_some() || !text(&official_forecast["value"]).is_empty();
        let (forecast, scope) = if regional_height {
            (official_forecast, "region")
        } else {
            (
                best(matching.iter().map(|r| &r["forecast"])),
                "stationMaximum",
            )
        };
        let observed = best(matching.iter().map(|r| &r["observed"]));
        let i = entries.len();
        entries.push(entry(
            format!("region:{name}"),
            name.clone(),
            scope,
            anchor,
            forecast,
            observed,
            true,
            matching,
        ));
        regional_indices.push(i);
    }
    for station in stations {
        if station["mapEligible"] != true {
            continue;
        }
        let Some(p) = station_position(station) else {
            continue;
        };
        let name = s(station, "regionName");
        let own = &station["forecast"];
        let (forecast, scope) = if !own.is_null() {
            (own.clone(), "station")
        } else {
            (station["areaForecast"].clone(), "region")
        };
        let i = entries.len();
        entries.push(entry(
            format!(
                "station:{}:{}",
                s(station, "stationId"),
                s(station, "stationName")
            ),
            s(station, "stationName"),
            scope,
            p,
            forecast,
            station["observed"].clone(),
            false,
            &[station],
        ));
        entries[i]["regionName"] = json!(name);
        station_indices.push(i);
        regional_station_indices.entry(name).or_default().push(i);
    }
    let max = entries
        .iter()
        .flat_map(|r| [metres(&r["forecast"]), metres(&r["observed"])])
        .flatten()
        .fold(0.0, f64::max);
    let scale = [
        0.5, 1.0, 2.0, 3.0, 5.0, 10.0, 20.0, 30.0, 50.0, 100.0, 200.0, 500.0, 1000.0,
    ]
    .into_iter()
    .find(|v| *v >= max * 1.1)
    .unwrap_or(max * 1.1)
    .max(0.5);
    // As in SREV, an observed station stays at its own geographic position.
    // Forecast-only station catalogs are not hundreds of "waiting" markers:
    // their forecasts remain in the regional gauge and full sidebar details.
    let mut candidates=vec![];
    for i in &regional_indices {
        let name=s(&entries[*i],"name");
        let measured=regional_station_indices.get(&name).into_iter().flatten()
            .copied().filter(|n| !entries[*n]["observed"].is_null()).collect::<Vec<_>>();
        if measured.is_empty(){candidates.push(*i);}else{candidates.extend(measured);}
    }
    let regional_names=regional_indices.iter().map(|i|s(&entries[*i],"name"))
        .collect::<std::collections::BTreeSet<_>>();
    candidates.extend(station_indices.iter().copied().filter(|i|
        !entries[*i]["observed"].is_null() && !regional_names.contains(&s(&entries[*i],"regionName"))));
    let projected=entries.iter().map(|r|{
        let lon=number(&r["longitude"]).unwrap();let lat=number(&r["latitude"]).unwrap().clamp(-85.05112878,85.05112878).to_radians();
        [(lon+180.0)/360.0,(1.0-(lat.tan()+1.0/lat.cos()).ln()/std::f64::consts::PI)/2.0]
    }).collect::<Vec<_>>();
    let mut markers=vec![];let mut levels=vec![];let mut cache=BTreeMap::<Vec<usize>,usize>::new();
    for zoom in 0..=18 {
        let world=256.0*2.0_f64.powi(zoom as i32);let size=marker_scale(zoom);
        let mut groups:Vec<Vec<usize>>=vec![];
        for &i in &candidates {
            let p=projected[i];
            if let Some(group)=groups.iter_mut().find(|group|{
                let q=projected[group[0]];let dx=(p[0]-q[0]).abs();
                dx.min(1.0-dx)*world<108.0*size+6.0 && (p[1]-q[1]).abs()*world<140.0*size+6.0
            }) {group.push(i);}else{groups.push(vec![i]);}
        }
        levels.push(groups.into_iter().map(|group|{
            if let Some(&i)=cache.get(&group){return i;}
            let i=markers.len();markers.push(finalize(&group,&entries,scale));cache.insert(group,i);i
        }).collect::<Vec<_>>());
    }
    Ok(
        json!({"entries":entries,"markers":markers,"levels":levels,"scaleMetres":scale,"expiresUtcMs":data["expiresUtcMs"]}),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn documented_jma_forecast_uses_existing_coast_without_inventing_observations() {
        let raw: Value = serde_json::from_str(include_str!(
            "../../../test/fixtures/jma_tsunami/whews.forecast_stations.documented.json"
        ))
        .unwrap();
        let m = super::super::parse("whews", &raw["Data"]).unwrap();
        let original = m.clone();
        let result=prepare(&json!({"message":m,"jmaTopology":include_str!("../../../assets/maps/jp.tsunami.topo.json")})).unwrap();
        assert_eq!(m, original);
        assert_eq!(result["entries"].as_array().unwrap().len(), 1);
        let r = &result["markers"][0];
        assert_eq!(r["name"], "有明・八代海");
        assert_eq!(r["forecastText"], "1");
        assert_eq!(r["forecastUnit"], "m");
        assert_eq!(r["observationText"], "—");
        assert_eq!(r["observationLabel"], "待观测");
        assert!(r["observedFraction"].is_null());
        assert!((30.0..35.0).contains(&number(&r["latitude"]).unwrap()));
        assert!((129.0..134.0).contains(&number(&r["longitude"]).unwrap()));
    }
    #[test]
    fn original_noaa_stations_respect_active_segments_and_missing_reading_times() {
        let detail: Value = serde_json::from_str(include_str!(
            "../../../test/fixtures/noaa_ntwc_advisory_20250918.json"
        ))
        .unwrap();
        let m = json!({"source":"ntwc","grade":"watch","officialDetail":detail});
        let result = prepare(&json!({"message":m})).unwrap();
        let entries = result["entries"].as_array().unwrap();
        assert!(entries.len() > 5);
        assert!(!entries.iter().any(|r| s(r, "name").contains("DART 21415")));
        assert!(result["markers"]
            .as_array()
            .unwrap()
            .iter()
            .all(|r| r["observedFraction"].is_null()));
        assert_eq!(result["levels"][18],result["levels"][0]);
        let low = &result["markers"][result["levels"][0][0].as_u64().unwrap() as usize];
        assert_eq!(low["forecastLabel"], "站点预计最高");
        assert_eq!(low["forecastText"], "0");
    }
    #[test]
    fn missing_original_observation_times_do_not_create_hundreds_of_waiting_station_markers() {
        let detail: Value = serde_json::from_str(include_str!(
            "../../../test/fixtures/noaa_ntwc_advisory_20250918.json"
        )).unwrap();
        let message = json!({"source":"ntwc","grade":"watch","officialDetail":detail});
        let original = message.clone();
        let result = prepare(&json!({"message":message})).unwrap();
        let overview = result["levels"][5].as_array().unwrap();
        assert_eq!(overview.len(),1);
        for index in overview {
            let marker = &result["markers"][index.as_u64().unwrap() as usize];
            for member in marker["members"].as_array().unwrap() {
                assert_eq!(result["entries"][member.as_u64().unwrap() as usize]["isRegion"], true);
            }
        }
        assert_eq!(message, original);
        assert!((marker_scale(5) - 0.78).abs() < 1e-12);
        assert!((0.30..0.35).contains(&marker_scale(0)));
        assert!(marker_scale(7) > marker_scale(5));
        assert_eq!(marker_scale(18), 1.60);
    }
    #[test]
    fn original_observed_stations_keep_coordinates_at_every_zoom_without_spider_offsets() {
        let detail:Value=serde_json::from_str(include_str!("../../../test/fixtures/tsunami_regions/ntwc_kamchatka_20250730_B12.original.json")).unwrap();
        let parsed=wave_data::noaa_detail(&json!({"json":detail.to_string()})).unwrap();
        let message=json!({"source":"ntwc","grade":"warning","officialDetail":parsed["detail"],"areas":parsed["areas"]});
        let result=prepare(&json!({"message":message})).unwrap();
        let overview=result["levels"][5].as_array().unwrap();
        assert!(overview.len()>1);
        let mut covered=std::collections::BTreeSet::new();
        for index in overview {
            let marker=&result["markers"][index.as_u64().unwrap() as usize];
            let members=marker["members"].as_array().unwrap();
            let entry=&result["entries"][members[0].as_u64().unwrap() as usize];
            assert_eq!(marker["latitude"],entry["latitude"]);
            assert_eq!(marker["longitude"],entry["longitude"]);
            assert!(marker["offsetX"].is_null());assert!(marker["offsetY"].is_null());
            if entry["isRegion"]==false{assert!(!entry["observed"].is_null());}
            for member in members {assert!(covered.insert(member.as_u64().unwrap()));}
        }
        let detailed=result["levels"][18].as_array().unwrap().iter().flat_map(|i|
          result["markers"][i.as_u64().unwrap() as usize]["members"].as_array().unwrap().iter().map(|v|v.as_u64().unwrap()))
          .collect::<std::collections::BTreeSet<_>>();
        assert_eq!(covered,detailed);
        assert!(result["levels"][18].as_array().unwrap().len()>=overview.len());
    }
    // All following inputs are explicit protocol edge cases, not live events.
    fn protocol(forecast: &str, observed: &str) -> Value {
        super::super::nmefc::parse(
            &json!({"code":"gauge-protocol","warningInfo":{"level":"红色"},
            "forecasts":[{"forecastArea":"protocol coast","warningLevel":"红色","maxWaveHeight":forecast}],
            "waterLevelMonitoring":[{"stationName":"protocol gauge","location":"protocol coast",
                "coordinates":{"latitude":25,"longitude":121},"time":"2026-10-22 12:00:00","maxWaveHeight":observed}]}),
        )
    }
    #[test]
    fn one_common_scale_allows_observed_height_to_exceed_forecast_and_accepts_zero() {
        let m = protocol("100", "200");
        let original = m.clone();
        let result = prepare(&json!({"message":m})).unwrap();
        let r = &result["markers"][0];
        assert_eq!(r["forecastText"], "1");
        assert_eq!(r["observationText"], "2");
        assert!(number(&r["observedFraction"]).unwrap() > number(&r["forecastFraction"]).unwrap());
        assert!(number(&r["observedFraction"]).unwrap() < 1.0);
        assert_eq!(m, original);
        let zero = prepare(&json!({"message":protocol("100","0")})).unwrap();
        assert_eq!(zero["markers"][0]["observationText"], "0");
        assert_eq!(zero["markers"][0]["observedFraction"], 0.0);
        assert_eq!(zero["markers"][0]["observationLabel"], "最大观测");
    }
    #[test]
    fn ranges_never_become_a_single_predicted_height_and_invalid_units_do_not_fill() {
        let result = prepare(&json!({"message":protocol("100-300","80")})).unwrap();
        assert_eq!(result["markers"][0]["forecastText"], "100-300");
        assert_eq!(result["markers"][0]["forecastUnit"], "cm");
        assert!(result["markers"][0]["forecastFraction"].is_null());
        let empty = prepare(&json!({"message":protocol("100","")})).unwrap();
        assert_eq!(empty["markers"][0]["observationLabel"], "待观测");
    }
    #[test]
    fn unbound_or_positionless_stations_do_not_acquire_a_fake_map_anchor() {
        let mut m = protocol("100", "80");
        m["observations"][0]["location"] = json!("unmatched coast");
        let result = prepare(&json!({"message":m})).unwrap();
        assert!(result["markers"].as_array().unwrap().is_empty());
        let mut m = protocol("100", "80");
        m["observations"][0]["latitude"] = Value::Null;
        assert!(prepare(&json!({"message":m})).unwrap()["markers"]
            .as_array()
            .unwrap()
            .is_empty());
    }
    #[test]
    fn cancellation_expiry_and_information_do_not_leave_a_gauge() {
        let mut m = protocol("100", "80");
        m["bulletinLevel"] = json!("Cancellation");
        assert!(prepare(&json!({"message":m})).unwrap()["markers"]
            .as_array()
            .unwrap()
            .is_empty());
        let mut m = protocol("100", "80");
        m["expires"] = json!("2026-10-22T04:00:00Z");
        assert!(prepare(
            &json!({"message":m,"nowMs":super::super::absolute("2026-10-22T04:00:00Z",0).map(|t|t/1000)})
        )
        .unwrap()["markers"]
            .as_array()
            .unwrap()
            .is_empty());
        let mut m = protocol("100", "80");
        m["grade"] = json!("none");
        assert!(prepare(&json!({"message":m})).unwrap()["markers"]
            .as_array()
            .unwrap()
            .is_empty());
    }
    #[test]
    fn coastline_anchor_stays_on_the_line_and_handles_antimeridian() {
        let p = coast_anchor(&json!({"lines":[[[179.0,25.0],[-179.0,25.0]]]})).unwrap();
        assert!((p[0].abs() - 180.0).abs() < 1e-6);
        assert_eq!(p[1], 25.0);
        let p = coast_anchor(&json!({"lines":[[[120.0,20.0],[121.0,20.0],[121.0,22.0]]]})).unwrap();
        assert!(p[0] == 121.0 || p[1] == 20.0);
    }
    #[test]
    fn qualified_unknown_unit_and_qualitative_readings_are_not_false_exact_metres() {
        let qualified =
            json!({"value":"0.8","unit":"m","heightCondition":"以上","description":"０．８ｍ以上"});
        assert_eq!(label(&qualified), ("≥0.8".into(), "m".into()));
        assert_eq!(reading_detail(&qualified), "０．８ｍ以上");
        assert_eq!(
            label(&json!({"value":"巨大","unit":"m"})),
            ("巨大".into(), String::new())
        );
        assert_eq!(
            label(&json!({"value":"0.8","unit":""})),
            ("0.8".into(), "?".into())
        );
        let exact = json!({"value":"0.6","unit":"m","metres":0.6});
        assert_eq!(label(&best([&qualified, &exact].into_iter())).0, "见详情");
        assert_eq!(scalar(0.003), "0.003");
        assert_eq!(label(&json!({"value":"小於1公尺","unit":""})),("小於1公尺".into(),String::new()));
    }
}
