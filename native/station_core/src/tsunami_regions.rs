//! Source warning geometry or explicitly named coastal base-map zones only.
//! No bounding boxes, station buffers or lines inferred from endpoint coordinates.
use serde_json::{json, Value};
use std::io::Read;
use std::ptr;
const MAX: usize = 16 * 1024 * 1024;
fn s<'a>(v: &'a Value, k: &str) -> &'a str {
    v[k].as_str().unwrap_or("")
}
fn color(v: &str) -> Option<&'static str> {
    match v.trim_start_matches('#').to_lowercase().as_str() {
        "majorwarning" | "extreme" | "threat" | "purple" => Some("purple"),
        "warning" | "alert" | "severe" | "red" | "红色" | "紅色" => Some("red"),
        "advisory" | "orange" | "橙色" => Some("orange"),
        "watch" | "moderate" | "yellow" | "黄色" | "黃色" => Some("yellow"),
        "forecast" | "blue" | "蓝色" | "藍色" => Some("blue"),
        _ => None,
    }
}
fn source_color(m: &Value, value: &str) -> Option<&'static str> {
    // INCOIS Alert is orange; its Warning is red. Do not merge those statuses.
    if s(m, "source") == "incois" && value.eq_ignore_ascii_case("alert") {
        Some("orange")
    } else if s(m, "source") == "incois" && value.eq_ignore_ascii_case("threat") {
        Some("red")
    } else {
        color(value)
    }
}
fn named_argb(c: &str) -> u32 {
    match c {
        "red" => 0xffff0000,
        "orange" => 0xffffa500,
        "yellow" => 0xffffff00,
        "blue" => 0xff0000ff,
        "purple" => 0xff800080,
        _ => 0xff888888,
    }
}
fn cat_bulletin_color(m: &Value) -> Option<(&'static str, u32)> {
    if s(m, "source") != "cat" {
        return None;
    }
    let raw = &m["sourcePayload"];
    let id = if s(raw, "id").is_empty() {
        s(raw, "eventId")
    } else {
        s(raw, "id")
    };
    // Same type and primary colors as CAT's official aplicarEstilo().
    if id.starts_with("BOLETIN_ALERTA_") {
        Some(("red", 0xffd71717))
    } else if id.starts_with("BOLETIN_SEGUIMIENTO_") {
        Some(("orange", 0xffec8210))
    } else {
        None
    }
}
fn official_url(url: &str, hosts: &[&str]) -> bool {
    let url = url
        .strip_prefix("https://")
        .or_else(|| url.strip_prefix("http://"));
    url.is_some_and(|v| {
        let host = v.split('/').next().unwrap_or("");
        hosts.contains(&host) && !v.contains(['\\', '\r', '\n'])
    })
}
fn plan(m: &Value) -> Value {
    let raw = &m["sourcePayload"];
    let mut resources = vec![];
    if matches!(s(m, "source"), "ptwc" | "ntwc") {
        let url = s(raw, "jsonUrl");
        if official_url(url, &["www.tsunami.gov", "tsunami.gov"])
            && url.contains("/events/")
            && url.ends_with(".json")
        {
            let base = url
                .rsplit_once('/')
                .unwrap()
                .0
                .replace("http://", "https://");
            let center = if s(m, "source") == "ptwc" {
                "PHEB"
            } else {
                "PAAQ"
            };
            resources.push(json!({"url":format!("{base}/{center}event.kmz"),"format":"kmz"}));
        }
    }
    let hosts: &[&str] = match s(m, "source") {
        "ptwc" | "ntwc" => &["www.tsunami.gov", "tsunami.gov"],
        "cat" => &["diredimoat.semar.gob.mx", "digaohm.semar.gob.mx"],
        "cwa" => &[
            "scweb.cwa.gov.tw",
            "www.cwa.gov.tw",
            "alerts.ncdr.nat.gov.tw",
        ],
        "incois" => &[
            "tsunami.incois.gov.in",
            "incois.gov.in",
            "www.incois.gov.in",
        ],
        "nmefc" => &["www.nmefc.cn", "nmefc.cn", "tsunami.nmefc.cn"],
        _ => &[],
    };
    if s(m, "source") == "incois" {
        let detail = s(raw, "detailUrl");
        if official_url(detail, hosts) && detail.contains("/itews/DSSProducts/OPR/") {
            if let Some((dir, file)) = detail.rsplit_once('/') {
                if let Some(stem) = file.strip_suffix("_Pub.json") {
                    if !stem.is_empty()
                        && stem.bytes().all(|c| c.is_ascii_alphanumeric() || c == b'_')
                    {
                        resources.push(json!({"url":format!("{dir}/level2/{stem}_threatmap.geojson"),"format":"incoisGeojson"}));
                    }
                }
            }
        }
        // Older official public bulletins link their per-report SHP/KMZ archive.
        if official_url(detail, hosts) {
            if let Some((origin, file)) = detail.split_once("/DSSProducts/Product_NTWC/Web/") {
                if let Some((event, suffix)) = file.split_once("_Bulletin") {
                    let report = suffix
                        .strip_suffix("_box_pub_A.html")
                        .or_else(|| suffix.strip_suffix("_box_pub_M.html"));
                    if let Some(report) = report {
                        if !event.is_empty()
                            && event.bytes().all(|c| c.is_ascii_alphanumeric())
                            && !report.is_empty()
                            && report.bytes().all(|c| c.is_ascii_digit())
                        {
                            resources.push(json!({"url":format!("{origin}/DSSProducts/Product_NTWC/SHP/{event}/B{report}/{event}_B{report}_pub.kmz"),"format":"kmz"}));
                        }
                    }
                }
            }
        }
    }
    // CAT publishes per-bulletin CAP files. Avoid a rolling latest URL.
    if s(m, "source") == "cat" {
        let id = if s(raw, "id").is_empty() {
            s(raw, "eventId")
        } else {
            s(raw, "id")
        };
        if id.starts_with("BOLETIN_")
            && id.len() <= 128
            && id
                .bytes()
                .all(|c| c.is_ascii_uppercase() || c.is_ascii_digit() || c == b'_')
        {
            resources.push(json!({"url":format!("https://diredimoat.semar.gob.mx/cat/rss/{id}.xml"),"format":"cap"}));
            return json!({"resources":resources});
        }
    }
    let cap = s(raw, "capUrl");
    if official_url(cap, hosts) {
        resources.push(json!({"url":cap.replace("http://","https://"),"format":"cap"}));
    }
    json!({"resources":resources})
}
fn xy(x: f64, y: f64) -> Option<[f64; 2]> {
    (x.is_finite() && y.is_finite() && x.abs() <= 180.0 && y.abs() <= 90.0).then_some([x, y])
}
fn coordinates(text: &str, cap: bool) -> Option<Vec<[f64; 2]>> {
    text.split_whitespace()
        .map(|point| {
            let mut p = point.split(',');
            let a = p.next()?.parse().ok()?;
            let b = p.next()?.parse().ok()?;
            if cap {
                xy(b, a)
            } else {
                xy(a, b)
            }
        })
        .collect()
}
fn split(line: Vec<[f64; 2]>, close: bool) -> Vec<Vec<[f64; 2]>> {
    if line.len() < if close { 3 } else { 2 } || line.len() > 200_000 {
        return vec![];
    }
    let mut line = line;
    if close && line.first() != line.last() {
        line.push(line[0]);
    }
    let mut out = vec![];
    let mut part = vec![line[0]];
    for pair in line.windows(2) {
        let (a, b) = (pair[0], pair[1]);
        if (b[0] - a[0]).abs() > 180.0 {
            let bx = b[0] + if b[0] < a[0] { 360.0 } else { -360.0 };
            let edge = if bx > a[0] { 180.0 } else { -180.0 };
            let y = a[1] + (b[1] - a[1]) * (edge - a[0]) / (bx - a[0]);
            part.push([edge, y]);
            out.push(std::mem::take(&mut part));
            part.push([-edge, y]);
        }
        part.push(b);
    }
    if part.len() > 1 {
        out.push(part);
    }
    out
}
fn cat_wkt(text: &str) -> Option<Vec<Vec<[f64; 2]>>> {
    // CAT's actual CAP polygon is WKT longitude latitude, not CAP latitude,longitude.
    let text = text.trim();
    let (body, ring_depth) = if text.get(..7)?.eq_ignore_ascii_case("POLYGON") {
        (&text[7..], 2usize)
    } else if text.get(..12)?.eq_ignore_ascii_case("MULTIPOLYGON") {
        (&text[12..], 3usize)
    } else {
        return None;
    };
    let mut depth = 0;
    let mut start = 0;
    let mut lines = vec![];
    for (i, c) in body.char_indices() {
        match c {
            '(' => {
                depth += 1;
                if depth > ring_depth {
                    return None;
                }
                if depth == ring_depth {
                    start = i + 1;
                }
            }
            ')' => {
                if depth == 0 {
                    return None;
                }
                if depth == ring_depth {
                    let points = body[start..i]
                        .split(',')
                        .map(|v| {
                            let mut parts = v.split_whitespace();
                            let x = parts.next()?.parse().ok()?;
                            let y = parts.next()?.parse().ok()?;
                            if parts.next().is_some() {
                                return None;
                            }
                            xy(x, y)
                        })
                        .collect::<Option<Vec<_>>>()?;
                    let ring = split(points, true);
                    if ring.is_empty() {
                        return None;
                    }
                    lines.extend(ring);
                }
                depth -= 1;
            }
            _ if depth < ring_depth && !c.is_whitespace() && c != ',' => return None,
            _ => {}
        }
    }
    (depth == 0 && !lines.is_empty()).then_some(lines)
}
fn child_text<'a>(n: roxmltree::Node<'a, 'a>, name: &str) -> &'a str {
    n.children()
        .find(|n| n.is_element() && n.tag_name().name() == name)
        .and_then(|n| n.text())
        .unwrap_or("")
}
fn kml_stroke_argb(doc: &roxmltree::Document<'_>, place: roxmltree::Node<'_, '_>) -> Option<u32> {
    let style_id = child_text(place, "styleUrl").strip_prefix('#');
    let style = place
        .children()
        .find(|n| n.is_element() && n.tag_name().name() == "Style")
        .or_else(|| {
            doc.descendants().find(|n| {
                n.is_element()
                    && n.tag_name().name() == "Style"
                    && n.attribute("id") == style_id
                    && style_id.is_some()
            })
        })?;
    let line = style
        .children()
        .find(|n| n.is_element() && n.tag_name().name() == "LineStyle")?;
    // KML uses aabbggrr, Flutter uses aarrggbb. Keep the source opacity.
    let value = child_text(line, "color").trim();
    if value.len() != 8 {
        return None;
    }
    let abgr = u32::from_str_radix(value, 16).ok()?;
    Some((abgr & 0xff00ff00) | ((abgr & 0xff) << 16) | ((abgr >> 16) & 0xff))
}
fn xml(bytes: &[u8], cap: bool, message: &Value) -> Result<Vec<Value>, String> {
    let text = std::str::from_utf8(bytes).map_err(|e| e.to_string())?;
    let doc = roxmltree::Document::parse(text).map_err(|e| e.to_string())?;
    let mut out = vec![];
    if cap {
        if child_text(doc.root_element(), "msgType") == "Cancel" {
            return Ok(out);
        }
        // The URL may point to a rolling 'latest' document. Bind it to this
        // bulletin's identifier before using its area, never to another event.
        let id = child_text(doc.root_element(), "identifier");
        let raw = &message["sourcePayload"];
        if id.is_empty() || ![s(raw, "id"), s(raw, "eventId")].contains(&id) {
            return Ok(out);
        }
        for info in doc
            .descendants()
            .filter(|n| n.is_element() && n.tag_name().name() == "info")
        {
            let Some(c) = cat_bulletin_color(message)
                .map(|v| v.0)
                .or_else(|| source_color(message, s(raw, "reportColor")))
                .or_else(|| source_color(message, s(raw, "level")))
                .or_else(|| color(child_text(info, "severity")))
                .or_else(|| color(s(message, "grade")))
            else {
                continue;
            };
            for area in info
                .children()
                .filter(|n| n.is_element() && n.tag_name().name() == "area")
            {
                let mut lines = vec![];
                for p in area
                    .children()
                    .filter(|n| n.is_element() && n.tag_name().name() == "polygon")
                {
                    let text = p.text().unwrap_or("");
                    if let Some(rings) = (s(message, "source") == "cat")
                        .then(|| cat_wkt(text))
                        .flatten()
                    {
                        lines.extend(rings);
                    } else if let Some(points) = coordinates(text, true) {
                        lines.extend(split(points, true));
                    }
                }
                if !lines.is_empty() {
                    out.push(json!({"name":child_text(area,"areaDesc"),"className":c,
                            "strokeArgb":cat_bulletin_color(message).map(|v|v.1).unwrap_or_else(||named_argb(c)),"lines":lines}));
                }
            }
        }
    } else {
        for place in doc
            .descendants()
            .filter(|n| n.is_element() && n.tag_name().name() == "Placemark")
        {
            // NOAA's own event.kmz distinguishes warning/advisory/watch styles.
            let Some(c) = color(child_text(place, "styleUrl")).or_else(|| {
                (s(message, "source") == "incois")
                    .then(|| source_color(message, child_text(place, "name")))
                    .flatten()
            }) else {
                continue;
            };
            let mut lines = vec![];
            for geom in place.descendants().filter(|n| {
                n.is_element() && matches!(n.tag_name().name(), "LinearRing" | "LineString")
            }) {
                let text = child_text(geom, "coordinates");
                if let Some(points) = coordinates(text, false) {
                    lines.extend(split(points, geom.tag_name().name() == "LinearRing"));
                }
            }
            if !lines.is_empty() {
                out.push(json!({"name":child_text(place,"name"),"className":c,
                    "strokeArgb":kml_stroke_argb(&doc,place).unwrap_or_else(||named_argb(c)),"lines":lines}));
            }
        }
    }
    Ok(out)
}
fn u16at(b: &[u8], i: usize) -> Option<usize> {
    Some(u16::from_le_bytes(b.get(i..i + 2)?.try_into().ok()?) as usize)
}
fn u32at(b: &[u8], i: usize) -> Option<usize> {
    Some(u32::from_le_bytes(b.get(i..i + 4)?.try_into().ok()?) as usize)
}
pub(crate) fn kml_from_zip(b: &[u8]) -> Result<Vec<u8>, String> {
    let fail = || "Invalid or unsupported KMZ".to_owned();
    let end = b
        .windows(4)
        .rposition(|w| w == b"PK\x05\x06")
        .ok_or_else(fail)?;
    let count = u16at(b, end + 10).ok_or_else(fail)?;
    if count > 256 {
        return Err(fail());
    }
    let mut p = u32at(b, end + 16).ok_or_else(fail)?;
    for _ in 0..count {
        if b.get(p..p + 4) != Some(b"PK\x01\x02") {
            return Err(fail());
        }
        let method = u16at(b, p + 10).ok_or_else(fail)?;
        let size = u32at(b, p + 20).ok_or_else(fail)?;
        let expanded = u32at(b, p + 24).ok_or_else(fail)?;
        let n = u16at(b, p + 28).ok_or_else(fail)?;
        let extra = u16at(b, p + 30).ok_or_else(fail)?;
        let comment = u16at(b, p + 32).ok_or_else(fail)?;
        let name =
            std::str::from_utf8(b.get(p + 46..p + 46 + n).ok_or_else(fail)?).map_err(|_| fail())?;
        if name.to_lowercase().ends_with(".kml") {
            if expanded > MAX || size > MAX || u16at(b, p + 8).ok_or_else(fail)? & 1 != 0 {
                return Err(fail());
            }
            let local = u32at(b, p + 42).ok_or_else(fail)?;
            if b.get(local..local + 4) != Some(b"PK\x03\x04") {
                return Err(fail());
            }
            let start = local
                + 30
                + u16at(b, local + 26).ok_or_else(fail)?
                + u16at(b, local + 28).ok_or_else(fail)?;
            let bytes = b.get(start..start + size).ok_or_else(fail)?;
            let mut out = vec![];
            match method {
                0 => out.extend_from_slice(bytes),
                8 => {
                    flate2::read::DeflateDecoder::new(bytes)
                        .take(MAX as u64 + 1)
                        .read_to_end(&mut out)
                        .map_err(|e| e.to_string())?;
                }
                _ => return Err(fail()),
            }
            if out.len() != expanded
                || crc32fast::hash(&out) as usize != u32at(b, p + 16).ok_or_else(fail)?
            {
                return Err(fail());
            }
            return Ok(out);
        }
        p += 46 + n + extra + comment;
    }
    Err("KMZ contains no KML".into())
}
fn geo_lines(v: &Value) -> Vec<Vec<[f64; 2]>> {
    let points = |v: &Value| -> Option<Vec<[f64; 2]>> {
        v.as_array()?
            .iter()
            .map(|v| xy(v.get(0)?.as_f64()?, v.get(1)?.as_f64()?))
            .collect()
    };
    let coordinates = &v["coordinates"];
    match s(v, "type") {
        "Polygon" => coordinates
            .as_array()
            .into_iter()
            .flatten()
            .filter_map(points)
            .flat_map(|p| split(p, true))
            .collect(),
        "MultiPolygon" => coordinates
            .as_array()
            .into_iter()
            .flatten()
            .flat_map(|v| geo_lines(&json!({"type":"Polygon","coordinates":v})))
            .collect(),
        "LineString" => points(coordinates)
            .map(|p| split(p, false))
            .unwrap_or_default(),
        "MultiLineString" => coordinates
            .as_array()
            .into_iter()
            .flatten()
            .filter_map(points)
            .flat_map(|p| split(p, false))
            .collect(),
        _ => vec![],
    }
}
fn inline(m: &Value) -> Vec<Value> {
    let mut out = vec![];
    let raw = &m["sourcePayload"];
    // Only explicit standardized geometry in a source warning area is usable.
    for area in ["warningAreas", "forecasts"]
        .iter()
        .flat_map(|k| raw[*k].as_array().into_iter().flatten())
    {
        let name = area["areaName"]
            .as_str()
            .or_else(|| area["forecastArea"].as_str())
            .unwrap_or("");
        let matched = m["areas"]
            .as_array()
            .into_iter()
            .flatten()
            .find(|v| s(v, "name") == name && s(v, "grade") != "none");
        let Some(c) = matched.and_then(|v| {
            source_color(m, s(area, "areaColor"))
                .or_else(|| source_color(m, s(area, "warningLevel")))
                .or_else(|| source_color(m, s(area, "level")))
                .or_else(|| {
                    (s(v, "grade") == s(m, "grade"))
                        .then(|| source_color(m, s(raw, "level")))
                        .flatten()
                })
                .or_else(|| color(s(v, "className")))
                .or_else(|| color(s(v, "grade")))
        }) else {
            continue;
        };
        let lines = geo_lines(&area["geometry"]);
        if !lines.is_empty() {
            out.push(json!({"name":name,"className":c,"strokeArgb":named_argb(c),"lines":lines}));
        }
    }
    out
}
fn cwa_zone(name: &str) -> Option<&'static str> {
    match name.trim() {
        "北部沿海地區" | "北部沿海地区" => Some("北部沿海地區"),
        "東北沿海地區" | "东北沿海地区" => Some("東北沿海地區"),
        "東部沿海地區" | "东部沿海地区" => Some("東部沿海地區"),
        "東南沿海地區" | "东南沿海地区" => Some("東南沿海地區"),
        "西南沿海地區" | "西南沿海地区" => Some("西南沿海地區"),
        "海峽沿海地區" | "海峡沿海地区" => Some("海峽沿海地區"),
        _ => None,
    }
}
fn cwa_coastlines(bytes: &[u8], m: &Value) -> Result<Vec<Value>, String> {
    // The unchanged ExpTech base map is separate from the warning document.
    // Only areas actually named in this report can activate its coastal lines.
    let map: Value = serde_json::from_slice(bytes).map_err(|e| e.to_string())?;
    if s(&map, "type") != "FeatureCollection" {
        return Err("Invalid CWA coastal base map".into());
    }
    let mut out = vec![];
    for area in m["sourcePayload"]["warningAreas"]
        .as_array()
        .into_iter()
        .flatten()
    {
        let name = s(area, "areaName");
        let Some(zone) = cwa_zone(name) else { continue };
        let Some(prepared) = m["areas"]
            .as_array()
            .into_iter()
            .flatten()
            .find(|v| cwa_zone(s(v, "name")) == Some(zone) && s(v, "grade") != "none")
        else {
            continue;
        };
        let c = if s(area, "areaColor").trim().is_empty() {
            color(s(prepared, "grade"))
        } else {
            // Green/unknown colors never inherit the overall warning color.
            color(s(area, "areaColor").trim())
        };
        let Some(c) = c else { continue };
        for feature in map["features"].as_array().into_iter().flatten() {
            if s(&feature["properties"], "AREANAME") != zone {
                continue;
            }
            let lines = geo_lines(&feature["geometry"]);
            if !lines.is_empty() {
                out.push(
                    json!({"name":name,"className":c,"strokeArgb":named_argb(c),"lines":lines}),
                );
            }
        }
    }
    Ok(out)
}
fn incois_geojson(bytes: &[u8]) -> Result<Vec<Value>, String> {
    let v: Value = serde_json::from_slice(bytes).map_err(|e| e.to_string())?;
    if s(&v, "type") != "FeatureCollection" {
        return Err("Invalid INCOIS feature collection".into());
    }
    let mut out = vec![];
    for feature in v["features"].as_array().into_iter().flatten() {
        let p = &feature["properties"];
        let c = match s(p, "THREAT_CAT") {
            "Warning" | "Threat" => "red",
            "Alert" => "orange",
            "Watch" => "yellow",
            _ => continue,
        };
        let lines = geo_lines(&feature["geometry"]);
        if !lines.is_empty() {
            out.push(json!({"name":s(p,"BOX_NAME"),"className":c,"strokeArgb":named_argb(c),"lines":lines}));
        }
    }
    Ok(out)
}
fn nmefc_named_coasts(bytes: &[u8], m: &Value) -> Result<Value, String> {
    let map: Value = serde_json::from_slice(bytes).map_err(|e| e.to_string())?;
    if s(&map, "type") != "FeatureCollection" {
        return Err("Invalid NMEFC named coastal base map".into());
    }
    let mut regions = Vec::<Value>::new();
    let mut unmatched = Vec::<Value>::new();
    for raw in m["sourcePayload"]["forecasts"]
        .as_array()
        .into_iter()
        .flatten()
    {
        let name = s(raw, "forecastArea").trim();
        let province = s(raw, "province").trim();
        // Level and name come from this forecast, never the source-wide level
        // or a measurement station. Unknown/cleared rows do not activate a coast.
        let Some(c) = color(s(raw, "warningLevel")) else {
            continue;
        };
        if !m["areas"]
            .as_array()
            .into_iter()
            .flatten()
            .any(|a| s(a, "name") == name && s(a, "grade") != "none")
        {
            continue;
        }
        let named = map["features"]
            .as_array()
            .into_iter()
            .flatten()
            .filter(|f| {
                f["properties"]["aliases"]
                    .as_array()
                    .into_iter()
                    .flatten()
                    .any(|a| a.as_str() == Some(name))
            })
            .collect::<Vec<_>>();
        let candidates = named
            .iter()
            .copied()
            .filter(|f| {
                province.is_empty()
                    || s(&f["properties"], "province") == province
                    || f["properties"]["provinceAliases"]
                        .as_array()
                        .into_iter()
                        .flatten()
                        .any(|a| a.as_str() == Some(province))
            })
            .collect::<Vec<_>>();
        if candidates.len() != 1 {
            let reason = if !named.is_empty() && candidates.is_empty() {
                "provinceMismatch"
            } else if candidates.is_empty() {
                "unknownName"
            } else {
                "ambiguousName"
            };
            unmatched.push(json!({"forecastArea":name,"province":province,"warningLevel":s(raw,"warningLevel"),"reason":reason}));
            continue;
        }
        let feature = candidates[0];
        let lines = geo_lines(&feature["geometry"]);
        if lines.is_empty() {
            continue;
        }
        let key = s(&feature["properties"], "name");
        // Distinct forecast points may name the same region. Draw its shoreline
        // once at the highest explicitly published regional warning colour.
        let rank = |v: &str| match v {
            "red" => 4,
            "orange" => 3,
            "yellow" => 2,
            "blue" => 1,
            _ => 0,
        };
        let value = json!({"name":name,"coastName":key,"className":c,"strokeArgb":named_argb(c),"lines":lines,"matchKind":"namedAdministrativeCoastline"});
        if let Some(old) = regions.iter_mut().find(|v| s(v, "coastName") == key) {
            if rank(c) > rank(s(old, "className")) {
                *old = value;
            }
        } else {
            regions.push(value);
        }
    }
    Ok(json!({"regions":regions,"unmatchedAreas":unmatched}))
}
fn execute(c: &Value, bytes: &[u8]) -> Result<Value, String> {
    let m = &c["message"];
    if s(c, "op") == "plan" {
        return Ok(plan(m));
    }
    if s(c, "op") != "geometry" {
        return Err("Unknown tsunami region operation".into());
    }
    if s(m, "bulletinLevel").eq_ignore_ascii_case("cancellation")
        || s(m, "grade") == "none"
            && m["areas"]
                .as_array()
                .is_none_or(|a| a.iter().all(|v| s(v, "grade") == "none"))
    {
        return Ok(json!({"regions":[]}));
    }
    if s(c, "format") == "nmefcNamedCoasts" && s(m, "source") == "nmefc" {
        return nmefc_named_coasts(bytes, m);
    }
    let regions = if bytes.is_empty() {
        inline(m)
    } else {
        match s(c, "format") {
            "kmz" => xml(&kml_from_zip(bytes)?, false, m)?,
            "kml" => xml(bytes, false, m)?,
            "cap" => xml(bytes, true, m)?,
            "incoisGeojson" if s(m, "source") == "incois" => incois_geojson(bytes)?,
            "cwaCoastlines" if s(m, "source") == "cwa" => cwa_coastlines(bytes, m)?,
            _ => return Err("Unsupported warning geometry document".into()),
        }
    };
    Ok(json!({"regions":regions}))
}
#[no_mangle]
pub unsafe extern "C" fn rq_tsunami_regions_prepare(
    input: *const u8,
    len: usize,
    document: *const u8,
    document_len: usize,
    size: *mut usize,
) -> *mut u8 {
    if input.is_null()
        || size.is_null()
        || len > MAX
        || document_len > MAX
        || document_len > 0 && document.is_null()
    {
        return ptr::null_mut();
    }
    let result = std::panic::catch_unwind(|| {
        let c = serde_json::from_slice::<Value>(unsafe { std::slice::from_raw_parts(input, len) });
        let bytes = if document_len == 0 {
            &[]
        } else {
            unsafe { std::slice::from_raw_parts(document, document_len) }
        };
        let value = c
            .map_err(|e| e.to_string())
            .and_then(|c| execute(&c, bytes))
            .unwrap_or_else(|e| json!({"error":e}));
        let mut out = crate::station_json::pack_value(&value).into_boxed_slice();
        unsafe { *size = out.len() };
        let p = out.as_mut_ptr();
        std::mem::forget(out);
        p
    });
    result.unwrap_or(ptr::null_mut())
}
#[no_mangle]
pub unsafe extern "C" fn rq_tsunami_regions_free(p: *mut u8, len: usize) {
    if !p.is_null() {
        drop(unsafe { Box::from_raw(std::ptr::slice_from_raw_parts_mut(p, len)) });
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    const NMEFC_COASTS: &[u8] = include_bytes!("../../../assets/maps/nmefc.named-coasts.geo.json");
    fn nmefc_protocol(forecasts: Value) -> Value {
        // Explicit format/alias cases, not captured WHEWS reports.
        let areas = forecasts
            .as_array()
            .unwrap()
            .iter()
            .map(|f| json!({"name":f["forecastArea"],"grade":"warning"}))
            .collect::<Vec<_>>();
        json!({"source":"nmefc","grade":"warning","areas":areas,"sourcePayload":{"forecasts":forecasts}})
    }
    #[test]
    fn nmefc_matches_short_regional_names_to_county_shores_without_using_cwa_six_zones() {
        let message = nmefc_protocol(json!([
            {"province":"台湾","forecastArea":"花莲","warningLevel":"橙色"},
            {"province":"台湾","forecastArea":"宜兰","warningLevel":"黄色"},
            {"province":"台湾","forecastArea":"台东北","warningLevel":"黄色"}
        ]));
        let before = message.clone();
        let result = execute(
            &json!({"op":"geometry","format":"nmefcNamedCoasts","message":message}),
            NMEFC_COASTS,
        )
        .unwrap();
        assert_eq!(message, before);
        assert_eq!(result["regions"].as_array().unwrap().len(), 2);
        assert_eq!(result["regions"][0]["coastName"], "台湾省花莲县");
        assert_eq!(result["regions"][0]["className"], "orange");
        assert_eq!(result["regions"][1]["coastName"], "台湾省宜兰县");
        assert_eq!(result["regions"][1]["className"], "yellow");
        assert_eq!(result["unmatchedAreas"][0]["forecastArea"], "台东北");
        assert!(!result["regions"][0]["lines"].as_array().unwrap().is_empty());
    }
    #[test]
    fn nmefc_county_policy_does_not_pick_a_same_named_city_or_ambiguous_coast() {
        let message = nmefc_protocol(json!([
            {"province":"台湾","forecastArea":"花莲市","warningLevel":"红色"},
            {"province":"台湾","forecastArea":"宜兰市","warningLevel":"黄色"},
            {"province":"台湾","forecastArea":"新竹","warningLevel":"黄色"},
            {"province":"台湾","forecastArea":"臺灣省宜蘭","warningLevel":"黄色"}
        ]));
        let result = nmefc_named_coasts(NMEFC_COASTS, &message).unwrap();
        assert_eq!(result["regions"].as_array().unwrap().len(), 1);
        assert_eq!(result["regions"][0]["coastName"], "台湾省宜兰县");
        assert_eq!(result["unmatchedAreas"].as_array().unwrap().len(), 3);
        assert_eq!(result["unmatchedAreas"][2]["reason"], "ambiguousName");
    }
    #[test]
    fn nmefc_mainland_all_coastal_provinces_use_their_own_city_shores_and_original_colours() {
        let examples = [
            ("辽宁", "丹东", "辽宁省丹东市", "红色", "red"),
            ("河北省", "秦皇岛市", "河北省秦皇岛市", "橙色", "orange"),
            ("天津", "天津", "天津市", "黄色", "yellow"),
            ("山东", "青岛", "山东省青岛市", "蓝色", "blue"),
            ("江苏", "连云港", "江苏省连云港市", "红色", "red"),
            ("上海市", "上海", "上海市", "橙色", "orange"),
            ("浙江", "温州", "浙江省温州市", "黄色", "yellow"),
            ("福建", "福州", "福建省福州市", "蓝色", "blue"),
            ("广东省", "深圳市", "广东省深圳市", "红色", "red"),
            ("广西", "防城港", "广西壮族自治区防城港市", "橙色", "orange"),
            ("海南", "文昌", "海南省文昌市", "黄色", "yellow"),
            ("香港", "香港", "香港特别行政区", "蓝色", "blue"),
            ("澳门", "澳门", "澳门特别行政区", "黄色", "yellow"),
        ];
        let forecasts = examples
            .iter()
            .map(|(p, n, _, level, _)| json!({"province":p,"forecastArea":n,"warningLevel":level}))
            .collect::<Vec<_>>();
        let message = nmefc_protocol(json!(forecasts));
        let before = message.clone();
        let result = nmefc_named_coasts(NMEFC_COASTS, &message).unwrap();
        assert_eq!(message, before);
        assert_eq!(result["unmatchedAreas"], json!([]));
        assert_eq!(result["regions"].as_array().unwrap().len(), examples.len());
        for (row, (_, _, expected, _, colour)) in
            result["regions"].as_array().unwrap().iter().zip(examples)
        {
            assert_eq!(row["coastName"], expected);
            assert_eq!(row["className"], colour);
            assert!(!row["lines"].as_array().unwrap().is_empty());
        }
    }
    #[test]
    fn nmefc_mainland_province_mismatch_unknown_sectors_and_cancellation_stay_off() {
        let mut message = nmefc_protocol(json!([
            {"province":"福建","forecastArea":"深圳","warningLevel":"红色"},
            {"province":"广东","forecastArea":"广州南部","warningLevel":"橙色"},
            {"province":"浙江","forecastArea":"温州","warningLevel":"解除"},
            {"province":"海南","forecastArea":"海口","warningLevel":"未识别"}
        ]));
        let result = nmefc_named_coasts(NMEFC_COASTS, &message).unwrap();
        assert_eq!(result["regions"], json!([]));
        assert_eq!(result["unmatchedAreas"][0]["reason"], "provinceMismatch");
        assert_eq!(result["unmatchedAreas"][1]["reason"], "unknownName");
        message = nmefc_protocol(
            json!([{"province":"广东","forecastArea":"深圳","warningLevel":"红色"}]),
        );
        message["bulletinLevel"] = json!("cancellation");
        assert_eq!(
            execute(
                &json!({"op":"geometry","format":"nmefcNamedCoasts","message":message}),
                NMEFC_COASTS
            )
            .unwrap()["regions"],
            json!([])
        );
    }
    #[test]
    fn nmefc_directional_unknown_wrong_province_and_cleared_rows_do_not_expand_coasts() {
        let message = nmefc_protocol(json!([
            {"province":"福建","forecastArea":"花莲","warningLevel":"橙色"},
            {"province":"台湾","forecastArea":"花莲南部","warningLevel":"红色"},
            {"province":"台湾","forecastArea":"新竹","warningLevel":"黄色"},
            {"province":"台湾","forecastArea":"宜兰","warningLevel":"解除"},
            {"province":"台湾","forecastArea":"花莲","warningLevel":"未识别"}
        ]));
        let result = nmefc_named_coasts(NMEFC_COASTS, &message).unwrap();
        assert_eq!(result["regions"], json!([]));
        assert_eq!(result["unmatchedAreas"].as_array().unwrap().len(), 3);
    }
    #[test]
    fn nmefc_aliases_and_duplicate_regions_use_highest_explicit_regional_colour_once() {
        let message = nmefc_protocol(json!([
            {"province":"臺灣省","forecastArea":"花蓮縣","warningLevel":"黄色"},
            {"province":"台湾省","forecastArea":"台湾省花莲县","warningLevel":"红色"}
        ]));
        let result = nmefc_named_coasts(NMEFC_COASTS, &message).unwrap();
        assert_eq!(result["regions"].as_array().unwrap().len(), 1);
        assert_eq!(result["regions"][0]["className"], "red");
        assert_eq!(result["regions"][0]["strokeArgb"], 0xffff0000_u32);
        let mut cancelled = message.clone();
        cancelled["bulletinLevel"] = json!("cancellation");
        assert_eq!(
            execute(
                &json!({"op":"geometry","format":"nmefcNamedCoasts","message":cancelled}),
                NMEFC_COASTS
            )
            .unwrap()["regions"],
            json!([])
        );
    }
    #[test]
    fn real_noaa_kmz() {
        let m = json!({"source":"ntwc","grade":"watch"});
        let v = execute(
            &json!({"op":"geometry","format":"kmz","message":m}),
            include_bytes!(
                "../../../test/fixtures/tsunami_regions/noaa_ntwc_20250918.original.kmz"
            ),
        )
        .unwrap();
        assert_eq!(v["regions"][0]["name"], "AK791");
        assert_eq!(v["regions"][0]["className"], "orange");
        assert_eq!(v["regions"][0]["strokeArgb"], 0x50FFA014_u32);
        assert!(v["regions"][0]["lines"].as_array().unwrap().len() > 10);
    }
    #[test]
    fn original_incois_20120411_kmz_keeps_all_55_forecast_zones_and_original_colors() {
        let url="https://tsunami.incois.gov.in/DSSProducts/Product_NTWC/Web/dss120411083800_Bulletin2_box_pub_A.html";
        let m = json!({"source":"incois","grade":"warning","sourcePayload":{"detailUrl":url}});
        assert_eq!(plan(&m)["resources"][0]["url"],"https://tsunami.incois.gov.in/DSSProducts/Product_NTWC/SHP/dss120411083800/B2/dss120411083800_B2_pub.kmz");
        let command = json!({"op":"geometry","format":"kmz","message":m});
        let v = execute(
            &command,
            include_bytes!(
                "../../../test/fixtures/tsunami_regions/incois_20120411_B2.original.kmz"
            ),
        )
        .unwrap();
        let regions = v["regions"].as_array().unwrap();
        assert_eq!(regions.len(), 55);
        for (c, count, argb) in [
            ("yellow", 38, 0xffffff00_u32),
            ("orange", 14, 0xffe69800_u32),
            ("red", 3, 0xffe60000_u32),
        ] {
            let items = regions
                .iter()
                .filter(|v| s(v, "className") == c)
                .collect::<Vec<_>>();
            assert_eq!(items.len(), count);
            assert!(items.iter().all(|v| v["strokeArgb"] == argb));
        }
        assert_eq!(regions[0]["lines"][0][0], json!([68.749187, 22.412124]));
    }
    #[test]
    fn original_plan_stays_unchanged() {
        let m = json!({"source":"ntwc","sourcePayload":{"jsonUrl":"http://www.tsunami.gov/events/PAAQ/2025/09/18/t2ssp5/1/WEAK51/PAAQ.json"}});
        let old = m.clone();
        assert!(plan(&m)["resources"][0]["url"]
            .as_str()
            .unwrap()
            .ends_with("/PAAQevent.kmz"));
        assert_eq!(m, old);
        assert_eq!(
            plan(
                &json!({"source":"ntwc","sourcePayload":{"jsonUrl":"https://www.tsunami.gov@evil.test/events/a.json"}})
            )["resources"],
            json!([])
        );
    }
    #[test]
    fn antimeridian_and_bad_coordinates() {
        let p = split(vec![[179.0, 10.0], [-179.0, 12.0]], false);
        assert_eq!(p.len(), 2);
        assert_eq!(p[0][1], [180.0, 11.0]);
        assert_eq!(p[1][0], [-180.0, 11.0]);
        assert!(coordinates("NaN,12 1,2", false).is_none());
        assert!(coordinates("181,12 1,2", false).is_none());
    }
    #[test]
    fn no_inferred_areas_or_cancelled_geometry() {
        let m = json!({"source":"ntwc","grade":"watch","areas":[{"name":"Amchitka - Attu","grade":"watch"}],"sourcePayload":{"bkp_start_lon":12,"bkp_end_lon":20}});
        assert_eq!(
            execute(&json!({"op":"geometry","message":m}), &[]).unwrap()["regions"],
            json!([])
        );
        let mut m = m;
        m["grade"] = json!("none");
        m["bulletinLevel"] = json!("Cancellation");
        assert_eq!(
            execute(
                &json!({"op":"geometry","format":"kmz","message":m}),
                include_bytes!(
                    "../../../test/fixtures/tsunami_regions/noaa_ntwc_20250918.original.kmz"
                )
            )
            .unwrap()["regions"],
            json!([])
        );
    }
    #[test]
    fn cap_identity_and_coordinate_order() {
        let doc=br#"<alert xmlns="urn:oasis:names:tc:emergency:cap:1.2"><identifier>protocol-id</identifier><msgType>Alert</msgType><info><severity>Severe</severity><area><areaDesc>protocol-zone</areaDesc><polygon>10,120 11,121 12,120 10,120</polygon></area></info></alert>"#;
        let m = json!({"source":"cat","grade":"warning","sourcePayload":{"id":"protocol-id"}});
        let v = xml(doc, true, &m).unwrap();
        assert_eq!(v[0]["lines"][0][0], json!([120.0, 10.0]));
        assert!(
            xml(doc, true, &json!({"sourcePayload":{"id":"other-event"}}))
                .unwrap()
                .is_empty()
        );
    }

    #[test]
    fn protocol_area_colors_are_source_specific_and_cleared_areas_stay_off() {
        // Protocol-only inputs: these triangles are not claimed as live areas.
        for (source, field, level, normalized, expected) in [
            ("ntwc", "level", "Advisory", "watch", "orange"),
            ("incois", "level", "Alert", "warning", "orange"),
            ("cwa", "areaColor", "橙色", "warning", "orange"),
            ("nmefc", "warningLevel", "红色", "majorWarning", "red"),
        ] {
            let mut area = json!({"areaName":"protocol-area","geometry":{"type":"Polygon","coordinates":[[[120,10],[121,11],[120,12],[120,10]]]}});
            area[field] = json!(level);
            let mut m = json!({"source":source,"grade":"warning","areas":[{"name":"protocol-area","grade":normalized}],"sourcePayload":{"warningAreas":[area]}});
            let v = inline(&m);
            assert_eq!(v[0]["className"], expected, "{source}");
            assert_eq!(v[0]["strokeArgb"], named_argb(expected));
            m["areas"][0]["grade"] = json!("none");
            assert!(inline(&m).is_empty());
        }
    }

    #[test]
    fn damaged_kmz_is_rejected() {
        let original = include_bytes!(
            "../../../test/fixtures/tsunami_regions/noaa_ntwc_20250918.original.kmz"
        );
        assert!(kml_from_zip(&original[..original.len() / 2]).is_err());
        let mut corrupt = original.to_vec();
        corrupt[100] ^= 0xff;
        assert!(kml_from_zip(&corrupt).is_err());
    }

    #[test]
    fn cwa_original_base_map_preserves_all_six_named_coastlines() {
        let bytes = include_bytes!("../../../assets/maps/tw.tsunami.geo.json");
        let map: Value = serde_json::from_slice(bytes).unwrap();
        // Protocol-only report metadata; coordinates come from the unchanged asset.
        let zones: Vec<Value> = map["features"]
            .as_array()
            .unwrap()
            .iter()
            .map(|f| json!({"name":f["properties"]["AREANAME"],"grade":"warning"}))
            .collect();
        assert_eq!(zones.len(), 6);
        let areas: Vec<Value> = zones
            .iter()
            .map(|a| json!({"areaName":a["name"],"areaColor":"橙色"}))
            .collect();
        let m = json!({"source":"cwa","grade":"warning","areas":zones,"sourcePayload":{"warningAreas":areas}});
        let original = m.clone();
        let result = execute(
            &json!({"op":"geometry","format":"cwaCoastlines","message":m}),
            bytes,
        )
        .unwrap();
        let regions = result["regions"].as_array().unwrap();
        assert_eq!(regions.len(), 6);
        for (f, r) in map["features"].as_array().unwrap().iter().zip(regions) {
            assert_eq!(r["name"], f["properties"]["AREANAME"]);
            assert_eq!(r["className"], "orange");
            assert_eq!(r["strokeArgb"], 0xffffa500_u32);
            assert_eq!(r["lines"], f["geometry"]["coordinates"]);
        }
        assert_eq!(m, original);
    }

    #[test]
    fn original_ptwc_hawaii_warning_keeps_all_39_zones_and_original_opacity() {
        let raw: Value = serde_json::from_slice(include_bytes!(
            "../../../test/fixtures/tsunami_regions/ptwc_hawaii_20250730.original.json"
        ))
        .unwrap();
        assert_eq!(raw["segments"][0]["category"], "Warning");
        assert_eq!(raw["bulletinIssueTime"], "2025-07-30T01:51:32Z");
        let m = json!({"source":"ptwc","grade":"warning","sourcePayload":raw});
        let result = execute(
            &json!({"op":"geometry","format":"kmz","message":m}),
            include_bytes!(
                "../../../test/fixtures/tsunami_regions/ptwc_hawaii_20250730.original.kmz"
            ),
        )
        .unwrap();
        let regions = result["regions"].as_array().unwrap();
        assert_eq!(regions.len(), 39);
        assert_eq!(
            regions
                .iter()
                .filter(|r| s(r, "className") == "red")
                .count(),
            35
        );
        assert_eq!(
            regions
                .iter()
                .filter(|r| s(r, "className") == "orange")
                .count(),
            4
        );
        // Original KML has 82 rings; 33 have only one/two points and cannot
        // form polygon outlines. All 39 zones retain their valid rings.
        assert_eq!(
            regions
                .iter()
                .map(|r| r["lines"].as_array().unwrap().len())
                .sum::<usize>(),
            49
        );
        for r in regions {
            assert_eq!(
                r["strokeArgb"],
                if s(r, "className") == "red" {
                    0x66ff0000_u32
                } else {
                    0x50ffa014_u32
                }
            );
        }
    }

    #[test]
    fn cwa_only_reported_active_zones_render_and_cancellation_removes_them() {
        let bytes = include_bytes!("../../../assets/maps/tw.tsunami.geo.json");
        // Deliberately inconsistent green grade verifies raw clearance wins.
        let m = json!({"source":"cwa","grade":"warning","areas":[
            {"name":"东部沿海地区","grade":"warning"},
            {"name":"北部沿海地區","grade":"warning"},
            {"name":"海峽沿海地區","grade":"none"},
            {"name":"宜蘭縣","grade":"warning"}
        ],"sourcePayload":{"warningAreas":[
            {"areaName":"东部沿海地区","areaColor":"黃色"},
            {"areaName":"北部沿海地區","areaColor":"綠色"},
            {"areaName":"海峽沿海地區","areaColor":"橙色"},
            {"areaName":"宜蘭縣","areaColor":"紅色"}
        ]}});
        let result = execute(
            &json!({"op":"geometry","format":"cwaCoastlines","message":m}),
            bytes,
        )
        .unwrap();
        assert_eq!(result["regions"].as_array().unwrap().len(), 1);
        assert_eq!(result["regions"][0]["name"], "东部沿海地区");
        assert_eq!(result["regions"][0]["className"], "yellow");
        let mut cancel = m;
        cancel["bulletinLevel"] = json!("Cancellation");
        assert_eq!(
            execute(
                &json!({"op":"geometry","format":"cwaCoastlines","message":cancel}),
                bytes
            )
            .unwrap()["regions"],
            json!([])
        );
        cancel["bulletinLevel"] = json!("Warning");
        cancel["source"] = json!("nmefc");
        assert!(execute(
            &json!({"op":"geometry","format":"cwaCoastlines","message":cancel}),
            bytes
        )
        .is_err());
    }

    #[test]
    fn original_cat_wkt_alert_and_followup_are_renderable() {
        for (id, bytes, expected) in [
            (
                "BOLETIN_ALERTA_001_20260717_090502",
                include_bytes!(
                    "../../../test/fixtures/tsunami_regions/cat_20260717_alert.original.xml"
                )
                .as_slice(),
                0xffd71717_u32,
            ),
            (
                "BOLETIN_SEGUIMIENTO_003_20260717_110847",
                include_bytes!(
                    "../../../test/fixtures/tsunami_regions/cat_20260717_followup.original.xml"
                )
                .as_slice(),
                0xffec8210_u32,
            ),
        ] {
            let m = json!({"source":"cat","grade":"warning","sourcePayload":{"id":id,"capUrl":"https://diredimoat.semar.gob.mx/cat/rss/ultimo_boletin.xml"}});
            assert_eq!(
                plan(&m)["resources"][0]["url"],
                format!("https://diredimoat.semar.gob.mx/cat/rss/{id}.xml")
            );
            let v = execute(&json!({"op":"geometry","format":"cap","message":m}), bytes).unwrap();
            assert_eq!(v["regions"][0]["strokeArgb"], expected);
            let p = &v["regions"][0]["lines"][0][0];
            assert!(p[0].as_f64().unwrap() < -90.0);
            assert!(p[1].as_f64().unwrap() > 10.0);
        }
        assert!(cat_wkt("POLYGON ((1 2,3 4, NaN 5))").is_none());
        assert!(cat_wkt("POLYGON ((1 2,3 4, 1 5)) junk").is_none());
    }

    #[test]
    fn incois_geometry_plan_follows_official_frontend_and_status() {
        let m = json!({"source":"incois","sourcePayload":{"detailUrl":"https://tsunami.incois.gov.in/itews/DSSProducts/OPR/incois2026qmbb/NTWC/B1/incois2026qmbb_B1_NTWC_Pub.json"}});
        assert_eq!(plan(&m)["resources"][0]["url"],"https://tsunami.incois.gov.in/itews/DSSProducts/OPR/incois2026qmbb/NTWC/B1/level2/incois2026qmbb_B1_NTWC_threatmap.geojson");
        // Protocol-only geometry. Actual advisory borders are fetched verbatim.
        let mut f = json!({"type":"Feature","properties":{"THREAT_CAT":"Alert","BOX_NAME":"protocol-only"},"geometry":{"type":"Polygon","coordinates":[[[80,10],[81,11],[80,12],[80,10]]]}});
        let c =
            |f| serde_json::to_vec(&json!({"type":"FeatureCollection","features":[f]})).unwrap();
        assert_eq!(
            incois_geojson(&c(f.clone())).unwrap()[0]["strokeArgb"],
            0xffffa500_u32
        );
        f["properties"]["THREAT_CAT"] = json!("NoThreat");
        assert!(incois_geojson(&c(f.clone())).unwrap().is_empty());
        f["properties"]["THREAT_CAT"] = json!("Threatpa");
        assert!(incois_geojson(&c(f)).unwrap().is_empty());
    }
}
