//! Read original USGS grid files; no inferred cells or rewritten observations.
use serde_json::{json, Value};
use std::collections::HashSet;
use std::sync::atomic::{AtomicUsize, Ordering};
static OUTPUTS: AtomicUsize = AtomicUsize::new(0);

fn parse_kmz(bytes: &[u8]) -> Result<Value, String> {
    let kml = crate::tsunami_regions::kml_from_zip(bytes)?;
    let text = std::str::from_utf8(&kml).map_err(|e| e.to_string())?;
    let doc = roxmltree::Document::parse(text).map_err(|e| e.to_string())?;
    let mut features = vec![];
    let mut resolutions = HashSet::new();
    for place in doc
        .descendants()
        .filter(|n| n.is_element() && n.tag_name().name() == "Placemark")
    {
        let polygons: Vec<_> = place
            .descendants()
            .filter(|n| n.is_element() && n.tag_name().name() == "Polygon")
            .collect();
        if polygons.is_empty() {
            continue;
        }
        if polygons.len() != 1 {
            return Err("Unsupported DYFI KML multipolygon".into());
        }
        let value = |key: &str| -> Result<&str, String> {
            place
                .descendants()
                .find(|n| {
                    n.is_element()
                        && n.tag_name().name() == "Data"
                        && n.attribute("name") == Some(key)
                })
                .and_then(|n| {
                    n.children()
                        .find(|v| v.is_element() && v.tag_name().name() == "value")
                })
                .and_then(|n| n.text())
                .ok_or_else(|| format!("Missing DYFI KML {key}"))
        };
        let number = |key: &str| -> Result<f64, String> {
            value(key)?
                .parse::<f64>()
                .ok()
                .filter(|x| x.is_finite())
                .ok_or_else(|| format!("Invalid DYFI KML {key}"))
        };
        let cdi = number("cdi")?;
        let distance = number("dist")?;
        let responses = value("nresp")?
            .parse::<u64>()
            .map_err(|_| "Invalid DYFI KML nresp")?;
        if !(1.0..=12.0).contains(&cdi) || distance < 0. {
            return Err("Invalid DYFI KML observation".into());
        }
        let name = value("id")?;
        if let Some(meters) = name
            .trim_end_matches(')')
            .split_whitespace()
            .last()
            .and_then(|s| s.parse::<u32>().ok())
        {
            if meters > 0 && meters % 1000 == 0 {
                resolutions.insert(meters / 1000);
            }
        }
        let mut rings = vec![];
        for ring in polygons[0]
            .descendants()
            .filter(|n| n.is_element() && n.tag_name().name() == "LinearRing")
        {
            let coordinates = ring
                .children()
                .find(|n| n.is_element() && n.tag_name().name() == "coordinates")
                .and_then(|n| n.text())
                .ok_or("Missing DYFI KML coordinates")?;
            let mut points = vec![];
            for point in coordinates.split_whitespace() {
                let mut pair = point.split(',');
                let lon = pair
                    .next()
                    .and_then(|s| s.parse::<f64>().ok())
                    .filter(|x| x.is_finite() && x.abs() <= 360.)
                    .ok_or("Invalid DYFI KML longitude")?;
                let lat = pair
                    .next()
                    .and_then(|s| s.parse::<f64>().ok())
                    .filter(|x| x.is_finite() && x.abs() <= 90.)
                    .ok_or("Invalid DYFI KML latitude")?;
                points.push(json!([lon, lat]));
            }
            if points.len() < 3 {
                return Err("Invalid DYFI KML ring".into());
            }
            rings.push(points);
        }
        if rings.is_empty() {
            return Err("Missing DYFI KML polygon".into());
        }
        features.push(json!({"type":"Feature","properties":{"name":name,"cdi":cdi,"nresp":responses,"dist":distance},"geometry":{"type":"Polygon","coordinates":rings}}));
    }
    Ok(
        json!({"geojson":{"type":"FeatureCollection","features":features},"gridKm":if resolutions.len()==1 {resolutions.iter().copied().next()}else{None}}),
    )
}
fn execute(command: &Value, bytes: &[u8]) -> Result<Value, String> {
    match command["op"].as_str().unwrap_or("") {
        "select" => {
            let files = command["files"].as_array().ok_or("Invalid DYFI files")?;
            for (name, format, km) in [
                ("dyfi_geo_10km.geojson", "geojson", Some(10)),
                ("dyfi_geo_1km.geojson", "geojson", Some(1)),
                ("dyfi_geo.kmz", "kmz", None),
            ] {
                if files.iter().any(|v| v.as_str() == Some(name)) {
                    return Ok(json!({"name":name,"format":format,"gridKm":km}));
                }
            }
            Ok(json!({}))
        }
        "kmz" => parse_kmz(bytes),
        _ => Err("Unknown DYFI grid operation".into()),
    }
}
#[no_mangle]
pub unsafe extern "C" fn rq_dyfi_grid_prepare(
    command: *const u8,
    len: usize,
    document: *const u8,
    document_len: usize,
    size: *mut usize,
) -> *mut u8 {
    if command.is_null()
        || size.is_null()
        || len > 65536
        || document_len > 16 * 1024 * 1024
        || (document_len > 0 && document.is_null())
    {
        return std::ptr::null_mut();
    }
    unsafe {
        *size = 0;
    }
    std::panic::catch_unwind(|| {
        let body = if document_len == 0 {
            &[]
        } else {
            unsafe { std::slice::from_raw_parts(document, document_len) }
        };
        let result =
            serde_json::from_slice::<Value>(unsafe { std::slice::from_raw_parts(command, len) })
                .map_err(|e| e.to_string())
                .and_then(|v| execute(&v, body));
        let mut bytes = serde_json::to_vec(&result.unwrap_or_else(|error| json!({"error":error})))
            .unwrap()
            .into_boxed_slice();
        unsafe {
            *size = bytes.len();
        }
        let p = bytes.as_mut_ptr();
        std::mem::forget(bytes);
        OUTPUTS.fetch_add(1, Ordering::Relaxed);
        p
    })
    .unwrap_or(std::ptr::null_mut())
}
#[no_mangle]
pub unsafe extern "C" fn rq_dyfi_grid_free(p: *mut u8, len: usize) {
    if !p.is_null() {
        drop(unsafe { Box::from_raw(std::ptr::slice_from_raw_parts_mut(p, len)) });
        OUTPUTS.fetch_sub(1, Ordering::Relaxed);
    }
}
#[no_mangle]
pub extern "C" fn rq_dyfi_grid_outputs() -> usize {
    OUTPUTS.load(Ordering::Relaxed)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn original_kenai_kmz_retains_observations_and_geometry() {
        let original =
            include_bytes!("../../../test/fixtures/usgs_dyfi/aka2026vqjriv/dyfi_geo.original.kmz");
        let result = parse_kmz(original).unwrap();
        let features = result["geojson"]["features"].as_array().unwrap();
        assert_eq!(features.len(), 71);
        assert_eq!(result["gridKm"], 1);
        assert_eq!(
            features
                .iter()
                .map(|f| f["properties"]["nresp"].as_u64().unwrap())
                .sum::<u64>(),
            87
        );
        assert_eq!(features[0]["properties"]["cdi"], 3.9);
        assert_eq!(
            features[0]["geometry"]["coordinates"][0][0],
            json!([-150.6321, 60.5140])
        );
        assert!(parse_kmz(&original[..original.len() / 2]).is_err());
    }
    #[test]
    fn preserve_geojson_priority_and_true_absence() {
        assert_eq!(
            execute(
                &json!({"op":"select","files":["dyfi_geo.kmz","dyfi_geo_10km.geojson"]}),
                &[]
            )
            .unwrap()["name"],
            "dyfi_geo_10km.geojson"
        );
        assert_eq!(
            execute(&json!({"op":"select","files":[]}), &[]).unwrap(),
            json!({})
        );
    }
}
