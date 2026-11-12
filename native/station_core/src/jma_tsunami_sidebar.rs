//! Region/station association and viewport-sized pages. Input views stay unchanged.
use super::*;

pub(super) fn prepare(groups: &Value) -> Value {
    let mut regions = Vec::<Value>::new();
    let mut bulletins = Vec::<Value>::new();
    for group in groups.as_array().into_iter().flatten() {
        let kind = s(group, "grade");
        let station_group = kind == "stationForecast" || kind == "observation";
        let bulletin_kind = if kind == "observation" {
            "观测"
        } else {
            "预报"
        };
        let bulletin = json!({"label":bulletin_kind,"reportTime":group["reportTime"],"reportNumber":group["reportNumber"],"headline":group["headline"]});
        if !bulletins.iter().any(|v| *v == bulletin) {
            bulletins.push(bulletin);
        }
        for (index, row) in group["rows"].as_array().into_iter().flatten().enumerate() {
            let mut region_name = if station_group {
                s(row, "regionName")
            } else {
                s(row, "name")
            };
            // Older stored views carry the same association in the detail fields.
            if region_name.is_empty() && station_group {
                region_name = row["details"]
                    .as_array()
                    .into_iter()
                    .flatten()
                    .find(|v| v["label"] == "区域")
                    .map(|v| s(v, "text"))
                    .unwrap_or_default();
            }
            if region_name.is_empty() {
                region_name = "未知".into();
            }
            let region_index = regions.iter().position(|v|v["name"] == region_name).unwrap_or_else(|| {
                regions.push(json!({"name":region_name,"grade":"none","gradeLabel":"","className":"blue","forecast":null,"stations":[]}));
                regions.len()-1
            });
            let region = &mut regions[region_index];
            if !station_group {
                region["forecast"] = row.clone();
                region["grade"] = group["grade"].clone();
                region["gradeLabel"] = group["label"].clone();
                region["className"] = group["className"].clone();
                continue;
            }
            let mut code = s(row, "stationCode");
            if code.is_empty() {
                code = row["details"]
                    .as_array()
                    .into_iter()
                    .flatten()
                    .find(|v| v["label"] == "站号")
                    .map(|v| s(v, "text"))
                    .unwrap_or_default();
            }
            let name = s(row, "name");
            let stations = region["stations"].as_array_mut().unwrap();
            let station_index = stations.iter().position(|v| {
                (!code.is_empty() && v["code"] == code)
                    || (!name.is_empty() && v["name"] == name && (code.is_empty() || s(v,"code").is_empty()))
            }).unwrap_or_else(|| {
                stations.push(json!({"key":if !code.is_empty(){code.clone()}else if !name.is_empty(){name.clone()}else{format!("{kind}:{index}")},
                    "name":name,"code":code,"forecast":null,"observation":null}));
                stations.len()-1
            });
            stations[station_index][if kind == "observation" {
                "observation"
            } else {
                "forecast"
            }] = row.clone();
        }
    }
    // Stable grade order; station order remains the original order within each region.
    regions.sort_by_key(|v| std::cmp::Reverse(grade(&s(v, "grade"))));
    let mut cells = vec![];
    let mut station_count = 0;
    for region in &regions {
        let stations = region["stations"].as_array().unwrap();
        if stations.is_empty() {
            cells.push(json!({"key":format!("{}:region",s(region,"name")),"region":region["name"],"grade":region["grade"],
                "gradeLabel":region["gradeLabel"],"className":region["className"],"regionForecast":region["forecast"],
                "stationName":"","forecast":null,"observation":null}));
        } else {
            for station in stations {
                station_count += 1;
                cells.push(json!({"key":format!("{}:{}",s(region,"name"),s(station,"key")),"region":region["name"],"grade":region["grade"],
                    "gradeLabel":region["gradeLabel"],"className":region["className"],"regionForecast":region["forecast"],
                    "stationName":station["name"],"forecast":station["forecast"],"observation":station["observation"]}));
            }
        }
    }
    let caption = regions
        .iter()
        .find(|v| grade(&s(v, "grade")) > 0)
        .map(|v| format!("JMA {}", s(v, "gradeLabel")))
        .unwrap_or_else(|| "JMA 津波情報".into());
    json!({"caption":caption,"regionCount":regions.len(),"stationCount":station_count,"bulletins":bulletins,"cells":cells})
}

pub(super) fn paginate(command: &Value) -> Value {
    let Some(heights) = command["itemHeights"].as_array() else {
        return json!({"error":"Missing tsunami sidebar measurements"});
    };
    let columns = if command["columns"] == 1 { 1 } else { 2 };
    let viewport = number(&command["maxHeight"])
        .filter(|v| *v > 0.0)
        .unwrap_or(1.0);
    let overhead = number(&command["overhead"]).unwrap_or(0.0).max(0.0);
    let gap = number(&command["rowGap"]).unwrap_or(0.0).max(0.0);
    let available = (viewport - overhead).max(1.0);
    let mut pages = Vec::<Value>::new();
    let mut lines = Vec::<Value>::new();
    let mut used = 0.0_f64;
    let mut maximum = 0.0_f64;
    for start in (0..heights.len()).step_by(columns) {
        let indices = (start..(start + columns).min(heights.len())).collect::<Vec<_>>();
        let height = indices
            .iter()
            .filter_map(|i| number(&heights[*i]))
            .fold(1.0_f64, f64::max);
        let next = used + if lines.is_empty() { 0.0 } else { gap } + height;
        if !lines.is_empty() && next > available {
            maximum = maximum.max(used);
            pages.push(json!({"lines":std::mem::take(&mut lines)}));
            used = 0.0;
        }
        if !lines.is_empty() {
            used += gap;
        }
        used += height;
        lines.push(json!({"indices":indices,"height":height}));
    }
    if !lines.is_empty() {
        maximum = maximum.max(used);
        pages.push(json!({"lines":lines}));
    }
    // A single oversized text row stays readable and is reached through the parent scroll.
    let height = if pages.len() > 1 {
        viewport.max(maximum + overhead)
    } else {
        maximum + overhead
    };
    json!({"pages":pages,"columns":columns,"height":height,"intervalMs":12000})
}

#[cfg(test)]
mod tests {
    use super::*;
    fn row(region: &str, name: &str, code: &str) -> Value {
        // Explicit layout/association cases, not live station reports.
        json!({"name":name,"regionName":region,"stationCode":code,"height":"0.8m",
            "arrivalTime":"2026-08-11 05:25:00","arrivalLabel":"","condition":"","details":[],"secondary":[]})
    }
    fn group(kind: &str, region: &str, rows: Vec<Value>) -> Value {
        json!({"grade":kind,"label":region,"className":"red","reportTime":"2026-08-11 05:30:00",
            "reportNumber":1,"headline":"protocol bulletin","rows":rows})
    }
    #[test]
    fn groups_regions_and_combines_same_station_forecast_and_observation_without_mutation() {
        let groups = json!([
            group("warning", "津波警報", vec![row("", "地域A", "")]),
            group("watch", "津波注意報", vec![row("", "地域B", "")]),
            group("stationForecast", "", vec![row("地域A", "station 1", "1")]),
            group(
                "observation",
                "",
                vec![
                    row("地域B", "station 2", "2"),
                    row("地域A", "station 1", "1"),
                    row("地域A", "station 3", "3")
                ]
            )
        ]);
        let original = groups.clone();
        let view = prepare(&groups);
        assert_eq!(groups, original);
        assert_eq!(view["regionCount"], 2);
        assert_eq!(view["stationCount"], 3);
        assert_eq!(view["cells"].as_array().unwrap().len(), 3);
        assert_eq!(view["cells"][0]["region"], "地域A");
        assert_eq!(view["cells"][1]["region"], "地域A");
        assert_eq!(view["cells"][2]["region"], "地域B");
        assert!(view["cells"][0]["forecast"].is_object());
        assert!(view["cells"][0]["observation"].is_object());
        assert!(view["cells"][0]["regionForecast"].is_object());
    }
    #[test]
    fn forecast_only_regions_and_distinct_station_codes_are_kept() {
        let groups = json!([
            group("warning", "津波警報", vec![row("", "地域A", "")]),
            group(
                "observation",
                "",
                vec![
                    row("地域B", "same name", "1"),
                    row("地域B", "same name", "2")
                ]
            )
        ]);
        let view = prepare(&groups);
        assert_eq!(view["cells"].as_array().unwrap().len(), 3);
        assert_eq!(view["cells"][0]["stationName"], "");
        assert_ne!(view["cells"][1]["key"], view["cells"][2]["key"]);
    }
    #[test]
    fn viewport_pages_use_all_available_rows_in_one_or_two_columns() {
        for columns in [1, 2] {
            let heights = (0..37).map(|_| json!(40)).collect::<Vec<_>>();
            let result = paginate(
                &json!({"itemHeights":heights,"columns":columns,"maxHeight":500,"overhead":60,"rowGap":5}),
            );
            assert_eq!(result["intervalMs"], 12000);
            assert_eq!(result["height"], 500.0);
            let mut seen = vec![];
            for page in result["pages"].as_array().unwrap() {
                let lines = page["lines"].as_array().unwrap();
                let used = lines
                    .iter()
                    .map(|v| v["height"].as_f64().unwrap())
                    .sum::<f64>()
                    + (lines.len() - 1) as f64 * 5.0;
                assert!(used <= 440.0);
                for line in lines {
                    assert!(line["indices"].as_array().unwrap().len() <= columns);
                    seen.extend(
                        line["indices"]
                            .as_array()
                            .unwrap()
                            .iter()
                            .map(|v| v.as_u64().unwrap()),
                    );
                }
            }
            assert_eq!(seen, (0..37).collect::<Vec<_>>());
            assert_eq!(result["pages"][0]["lines"].as_array().unwrap().len(), 9);
        }
    }
    #[test]
    fn resize_changes_page_capacity_and_short_content_does_not_fill_history_space() {
        let heights = vec![json!(40); 25];
        let small = paginate(
            &json!({"itemHeights":heights,"columns":2,"maxHeight":220,"overhead":60,"rowGap":5}),
        );
        let large = paginate(
            &json!({"itemHeights":heights,"columns":2,"maxHeight":600,"overhead":60,"rowGap":5}),
        );
        assert!(
            small["pages"].as_array().unwrap().len() > large["pages"].as_array().unwrap().len()
        );
        let single =
            paginate(&json!({"itemHeights":[40],"columns":1,"maxHeight":600,"overhead":60}));
        assert_eq!(single["height"], 100.0);
        let tall = paginate(&json!({"itemHeights":[160],"maxHeight":100,"overhead":60}));
        assert_eq!(tall["height"], 220.0);
    }
}
