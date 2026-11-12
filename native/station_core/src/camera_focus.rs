//! Camera business decisions and fixed-anchor extent fitting. Flutter owns
//! projection and animation; neither changes event coordinates or observations.
use serde_json::{json, Value};
use std::sync::atomic::{AtomicUsize, Ordering};

static CALLS: AtomicUsize = AtomicUsize::new(0);
static OUTPUTS: AtomicUsize = AtomicUsize::new(0);
const MAX_INPUT: usize = 16 * 1024 * 1024;

fn s<'a>(v: &'a Value, k: &str) -> &'a str {
    v[k].as_str().unwrap_or("")
}
fn number(v: &Value, k: &str) -> Result<f64, String> {
    v[k].as_f64()
        .filter(|x| x.is_finite())
        .ok_or_else(|| format!("Invalid {k}"))
}

// Geometry may use continuous longitudes across the date line. This is not
// epicenter admission: source/event coordinate validation stays unchanged.
fn prepare_geometry(coordinates: &[f64]) -> Value {
    let mut indices = Vec::new();
    let mut longitudes = Vec::new();
    let mut south = f64::INFINITY;
    let mut north = f64::NEG_INFINITY;
    for (index, point) in coordinates.chunks_exact(2).enumerate() {
        let (lat, lng) = (point[0], point[1]);
        if !lat.is_finite() || lat.abs() > 90. || !lng.is_finite() {
            continue;
        }
        indices.push(index);
        if lat < south { south = lat; }
        if lat > north { north = lat; }
        // Same positive-circle representation as the previous Dart range
        // calculation. Inputs are borrowed original float64 values, unmodified.
        let positive = lng % 360.;
        longitudes.push(if positive < 0. { positive + 360. } else { positive });
    }
    if indices.is_empty() {
        return json!({"indices":[],"view":null});
    }
    longitudes.sort_by(f64::total_cmp);
    let mut largest_gap = -1.;
    let mut largest_index = 0;
    for (index, &current) in longitudes.iter().enumerate() {
        let next = if index + 1 == longitudes.len() { longitudes[0] + 360. }
            else { longitudes[index + 1] };
        let gap = next - current;
        if gap > largest_gap {
            largest_gap = gap;
            largest_index = index;
        }
    }
    let start_index = (largest_index + 1) % longitudes.len();
    let start = longitudes[start_index];
    let end = longitudes[largest_index] + if start_index == 0 { 0. } else { 360. };
    json!({"indices":indices,"view":{
        "latitude":(south+north)/2.,"longitude":(start+end)/2.,
        "latDiff":north-south,"lngDiff":end-start}})
}

fn execute(v: &Value) -> Result<Value, String> {
    match s(v, "op") {
        "eventCameraTarget" => {
            // Wave bounds determine scale, never replace the established
            // epicenter-group center with a Mercator bounds midpoint.
            let latitude = number(v, "latitude")?;
            let longitude = number(v, "longitude")?;
            let min_zoom = number(v, "minZoom")?;
            let max_zoom = number(v, "maxZoom")?;
            if min_zoom > max_zoom { return Err("Invalid zoom limits".into()); }
            let zoom = if v["fittedZoom"].is_null() {
                let diff = number(v, "latDiff")?.max(number(v, "lngDiff")?)
                    + number(v, "padding")? * 2.;
                let coarse: f64 = if diff > 20. { 3. } else if diff > 10. { 4. }
                    else if diff > 5. { 5. } else if diff > 2. { 6. }
                    else if diff > 1. { 7. } else { 8. };
                coarse.clamp(min_zoom, max_zoom)
            } else { number(v, "fittedZoom")? };
            Ok(json!({"latitude":latitude,"longitude":longitude,"zoom":zoom}))
        }
        "informationAnchor" => {
            let p2p = s(v, "source") == "p2pJmaEqlist"
                || (s(v, "source") == "jmaEqlist" && v["origin"].as_i64() == Some(2));
            // Aug 17 requirement applies to these two stages only. Ordinary
            // reports keep the already established epicenter position.
            let special = matches!(s(v, "issueType"), "ScalePrompt" | "Destination")
                || (s(v, "issueType").is_empty()
                    && matches!(s(v, "title"), "震度速報" | "震源に関する情報"));
            Ok(json!(
                v["locatable"] == true
                    && v["isEew"] != true
                    && (s(v, "source") == "nowQuakeCencIr" || (p2p && !special)
                        || (v["hasInformationFill"] == true && !special))
            ))
        }
        "renderedRegionBounds" => {
            let regions = v["regions"].as_array().ok_or("Invalid rendered regions")?;
            let mut result = serde_json::Map::new();
            for region in regions {
                let mut bounds = [f64::INFINITY, f64::NEG_INFINITY, f64::INFINITY, f64::NEG_INFINITY];
                for point in region["points"].as_array().ok_or("Invalid rendered points")? {
                    let lat = point[0].as_f64().filter(|x| x.is_finite()).ok_or("Invalid latitude")?;
                    let lng = point[1].as_f64().filter(|x| x.is_finite()).ok_or("Invalid longitude")?;
                    bounds[0] = bounds[0].min(lat); bounds[1] = bounds[1].max(lat);
                    bounds[2] = bounds[2].min(lng); bounds[3] = bounds[3].max(lng);
                }
                if bounds[0].is_finite() {
                    if let Some(previous) = result.get(s(region, "name")).and_then(Value::as_array) {
                        for point in previous {
                            let lat = point[0].as_f64().unwrap();
                            let lng = point[1].as_f64().unwrap();
                            bounds[0] = bounds[0].min(lat); bounds[1] = bounds[1].max(lat);
                            bounds[2] = bounds[2].min(lng); bounds[3] = bounds[3].max(lng);
                        }
                    }
                    result.insert(s(region, "name").into(), json!([[bounds[0],bounds[2]],[bounds[0],bounds[3]],[bounds[1],bounds[2]],[bounds[1],bounds[3]]]));
                }
            }
            Ok(Value::Object(result))
        }
        "informationFillBounds" => {
            if v["isEew"] == true { return Ok(json!([])); }
            let names: std::collections::HashSet<String> = if v["namedRegions"] == true {
                let rows: Value = serde_json::from_str(s(v, "warnArea")).unwrap_or(Value::Null);
                rows.as_array().into_iter().flatten().filter_map(|r| r["name"].as_str().map(str::to_owned)).collect()
            } else { std::collections::HashSet::new() };
            // A combined JMA layer with no observed areas uses its existing
            // representative only; never attribute its modeled fill to EEW.
            let all = v["namedRegions"] != true || (names.is_empty() && v["representative"] == true);
            let mut bounds = [f64::INFINITY, f64::NEG_INFINITY, f64::INFINITY, f64::NEG_INFINITY];
            for (name, points) in v["regions"].as_object().ok_or("Invalid region bounds")? {
                if !all && !names.contains(name) { continue; }
                for point in points.as_array().ok_or("Invalid bounds points")? {
                    let lat = point[0].as_f64().filter(|x| x.is_finite()).ok_or("Invalid latitude")?;
                    let lng = point[1].as_f64().filter(|x| x.is_finite()).ok_or("Invalid longitude")?;
                    bounds[0] = bounds[0].min(lat); bounds[1] = bounds[1].max(lat);
                    bounds[2] = bounds[2].min(lng); bounds[3] = bounds[3].max(lng);
                }
            }
            Ok(if bounds[0].is_finite() { json!([[bounds[0],bounds[2]],[bounds[0],bounds[3]],[bounds[1],bounds[2]],[bounds[1],bounds[3]]]) } else { json!([]) })
        }
        "groupAnchor" => Ok(json!(v["hasProduct"] == true || v["stationFit"] == true)),
        "retainInformationGroup" => Ok(json!(v["sameViewport"] == true && v["hasPreviousMember"] == true && v["allVisible"] == true)),
        "fitAnchor" => {
            let width = number(v, "width")?;
            let height = number(v, "height")?;
            if width <= 0. || height <= 0. {
                return Ok(Value::Null);
            }
            let rotation = number(v, "rotation")?;
            let cos = rotation.cos();
            let sin = rotation.sin();
            let mut half_width: f64 = 0.;
            let mut half_height: f64 = 0.;
            let points = v["offsets"].as_array().ok_or("Invalid offsets")?;
            if points.len() > 2_000_000 {
                return Err("Too many offsets".into());
            }
            for pair in points {
                let x = pair[0]
                    .as_f64()
                    .filter(|x| x.is_finite())
                    .ok_or("Invalid x")?;
                let y = pair[1]
                    .as_f64()
                    .filter(|x| x.is_finite())
                    .ok_or("Invalid y")?;
                // Same rotation and operation order as the original UI adapter.
                half_width = half_width.max((x * cos + y * sin).abs());
                half_height = half_height.max((-x * sin + y * cos).abs());
            }
            let scale = (if half_width == 0. {
                f64::INFINITY
            } else {
                width / (2. * half_width)
            })
            .min(if half_height == 0. {
                f64::INFINITY
            } else {
                height / (2. * half_height)
            });
            let min_zoom = number(v, "minZoom")?;
            let max_zoom = number(v, "maxZoom")?;
            if min_zoom > max_zoom {
                return Err("Invalid zoom limits".into());
            }
            // EPSG:3857 is the production map CRS. Match flutter_map's scale
            // multiplication before log, rather than rounding zoom to buckets.
            let zoom = if scale.is_finite() {
                ((number(v, "currentScale")? * scale / 256.).ln() / std::f64::consts::LN_2)
                    .clamp(min_zoom, max_zoom)
            } else {
                max_zoom
            };
            let px = number(v, "paddingX")?;
            let py = number(v, "paddingY")?;
            Ok(json!({"zoom":zoom,"offsetX":px*cos-py*sin,"offsetY":px*sin+py*cos}))
        }
        _ => Err("Unknown camera focus operation".into()),
    }
}

#[no_mangle]
pub extern "C" fn rq_camera_focus_calls() -> u64 {
    CALLS.load(Ordering::Relaxed) as u64
}
#[no_mangle]
pub extern "C" fn rq_camera_focus_outputs() -> u64 {
    OUTPUTS.load(Ordering::Relaxed) as u64
}
#[no_mangle]
pub unsafe extern "C" fn rq_camera_focus_prepare(
    input: *const u8,
    len: usize,
    size: *mut usize,
) -> *mut u8 {
    if input.is_null() || size.is_null() || len > MAX_INPUT {
        return std::ptr::null_mut();
    }
    unsafe {
        *size = 0;
    }
    std::panic::catch_unwind(|| {
        let result =
            serde_json::from_slice::<Value>(unsafe { std::slice::from_raw_parts(input, len) })
                .map_err(|e| e.to_string())
                .and_then(|v| execute(&v));
        let value = result.unwrap_or_else(|e| json!({"error":e}));
        let mut bytes = serde_json::to_vec(&value).unwrap().into_boxed_slice();
        unsafe {
            *size = bytes.len();
        }
        let p = bytes.as_mut_ptr();
        std::mem::forget(bytes);
        CALLS.fetch_add(1, Ordering::Relaxed);
        OUTPUTS.fetch_add(1, Ordering::Relaxed);
        p
    })
    .unwrap_or(std::ptr::null_mut())
}
#[no_mangle]
pub unsafe extern "C" fn rq_camera_focus_free(p: *mut u8, len: usize) {
    if !p.is_null() {
        drop(unsafe { Box::from_raw(std::ptr::slice_from_raw_parts_mut(p, len)) });
        OUTPUTS.fetch_sub(1, Ordering::Relaxed);
    }
}

// Raw latitude/longitude float64 pairs preserve even invalid nonfinite values
// until Rust validates them. No JSON substitution or source-coordinate rewrite.
#[no_mangle]
pub unsafe extern "C" fn rq_camera_geometry_prepare(
    input: *const f64,
    count: usize,
    size: *mut usize,
) -> *mut u8 {
    if size.is_null() { return std::ptr::null_mut(); }
    unsafe { *size = 0; }
    if count > 2_000_000 || (count != 0 && input.is_null()) {
        return std::ptr::null_mut();
    }
    std::panic::catch_unwind(|| {
        let coordinates = if count == 0 { &[][..] }
            else { unsafe { std::slice::from_raw_parts(input, count * 2) } };
        let mut bytes = serde_json::to_vec(&prepare_geometry(coordinates))
            .unwrap().into_boxed_slice();
        unsafe { *size = bytes.len(); }
        let pointer = bytes.as_mut_ptr();
        std::mem::forget(bytes);
        CALLS.fetch_add(1, Ordering::Relaxed);
        OUTPUTS.fetch_add(1, Ordering::Relaxed);
        pointer
    }).unwrap_or(std::ptr::null_mut())
}

#[cfg(test)]
mod tests {
    #[test]
    fn continuous_geometry_keeps_original_points_and_rejects_bad_coordinates() {
        let coordinates = [51.707,178.854,49.867,176.083,53.483,181.883,
            f64::NAN,1.,10.,f64::INFINITY,91.,100.];
        let bits: Vec<_> = coordinates.iter().map(|x| x.to_bits()).collect();
        let result = prepare_geometry(&coordinates);
        assert_eq!(result["indices"], json!([0,1,2]));
        assert!((result["view"]["longitude"].as_f64().unwrap()-178.983).abs()<1e-10);
        assert!((result["view"]["lngDiff"].as_f64().unwrap()-5.8).abs()<1e-10);
        assert_eq!(coordinates.iter().map(|x| x.to_bits()).collect::<Vec<_>>(),bits);
        assert!(prepare_geometry(&[f64::NAN,0.,0.,f64::NEG_INFINITY])["view"].is_null());
    }

    #[test]
    fn geometry_world_copies_and_zero_keep_the_smallest_circular_extent() {
        let result = prepare_geometry(&[0.,179.,0.,181.,0.,-179.,0.,541.]);
        assert_eq!(result["indices"],json!([0,1,2,3]));
        assert_eq!(result["view"]["longitude"],180.);
        assert_eq!(result["view"]["lngDiff"],2.);
        let zero = prepare_geometry(&[0.,0.]);
        assert_eq!(zero["indices"],json!([0]));
        assert_eq!(zero["view"]["latitude"],0.);
        assert_eq!(zero["view"]["longitude"],0.);
    }

    #[test]
    fn raw_geometry_ffi_borrows_input_and_releases_output() {
        let input = [53.483,181.883,f64::NAN,0.];
        let mut length = 0;
        let output = unsafe { rq_camera_geometry_prepare(input.as_ptr(),2,&mut length) };
        assert!(!output.is_null());
        let result: Value = serde_json::from_slice(unsafe {
            std::slice::from_raw_parts(output,length)
        }).unwrap();
        assert_eq!(result["indices"],json!([0]));
        unsafe { rq_camera_focus_free(output,length); }
        assert_eq!(rq_camera_focus_outputs(),0);
        let empty = unsafe { rq_camera_geometry_prepare(std::ptr::null(),0,&mut length) };
        assert!(!empty.is_null());
        unsafe { rq_camera_focus_free(empty,length); }
        assert!(unsafe { rq_camera_geometry_prepare(std::ptr::null(),1,&mut length) }.is_null());
        assert_eq!(length,0);
        assert!(unsafe { rq_camera_geometry_prepare(input.as_ptr(),2_000_001,&mut length) }.is_null());
        assert_eq!(rq_camera_focus_outputs(),0);
    }

    #[test]
    fn wave_fit_retains_epicenter_and_existing_zoom() {
        let mut request = json!({"op":"eventCameraTarget", "latitude":70.93610382080078,
          "longitude":-6.487203121185303,"latDiff":26.,"lngDiff":60.,"padding":0.8,
          "minZoom":4.5,"maxZoom":8.,"fittedZoom":4.5});
        let target = execute(&request).unwrap();
        assert_eq!(target["latitude"], request["latitude"]);
        assert_eq!(target["longitude"], request["longitude"]);
        assert_eq!(target["zoom"], 4.5);
        request["fittedZoom"] = Value::Null;
        assert_eq!(execute(&request).unwrap()["zoom"], 4.5);
        for (span, zoom) in [(21.,3.),(11.,4.),(6.,5.),(3.,6.),(1.5,7.),(0.5,8.)] {
            request["minZoom"] = json!(3.);
            request["latDiff"] = json!(span);
            request["lngDiff"] = json!(0.);
            request["padding"] = json!(0.);
            assert_eq!(execute(&request).unwrap()["zoom"], zoom);
        }
    }
    use super::*;
    #[test]
    fn rendered_fill_extent_and_eew_boundary() {
        let regions = execute(&json!({"op":"renderedRegionBounds","regions":[
            {"name":"same","points":[[1.,2.],[2.,3.]]},
            {"name":"same","points":[[4.,5.],[6.,7.]]},
            {"name":"other","points":[[10.,20.],[20.,30.]]}]})).unwrap();
        assert_eq!(regions["same"], json!([[1.,2.],[1.,7.],[6.,2.],[6.,7.]]));
        let mut input = json!({"op":"informationFillBounds","regions":regions,"namedRegions":true,
            "warnArea":"[{\"name\":\"same\"}]","isEew":false});
        assert_eq!(execute(&input).unwrap(), regions["same"]);
        input["isEew"] = json!(true);
        assert_eq!(execute(&input).unwrap(), json!([]));
        assert_eq!(execute(&json!({"op":"informationAnchor","source":"cwaEqlist","locatable":true,"hasInformationFill":true})).unwrap(), true);
        assert_eq!(execute(&json!({"op":"informationAnchor","source":"cwaEqlist","locatable":true,"hasInformationFill":true,"isEew":true})).unwrap(), false);
    }
    #[test]
    fn contained_information_never_refits_but_disjoint_and_resize_do() {
        for viewport in [true,false] { for member in [true,false] { for visible in [true,false] {
            assert_eq!(execute(&json!({"op":"retainInformationGroup","sameViewport":viewport,"hasPreviousMember":member,"allVisible":visible})).unwrap(), viewport && member && visible);
        }}}
    }
    #[test]
    fn contracts_remain_separate() {
        let mut event = json!({"op":"informationAnchor","source":"jmaEqlist","origin":2,
            "issueType":"DetailScale","locatable":true});
        assert_eq!(execute(&event).unwrap(), true);
        for special in ["ScalePrompt", "Destination"] {
            event["issueType"] = json!(special);
            assert_eq!(execute(&event).unwrap(), false);
        }
        event["source"] = json!("nowQuakeCencIr");
        assert_eq!(execute(&event).unwrap(), true);
        event["source"] = json!("jmaVolcano");
        assert_eq!(execute(&event).unwrap(), false);
        event["source"] = json!("usgsShakeMap");
        assert_eq!(execute(&event).unwrap(), false);
        event["source"] = json!("p2pJmaEqlist");
        event["issueType"] = json!("DetailScale");
        event["locatable"] = json!(false);
        assert_eq!(execute(&event).unwrap(), false);
    }
    #[test]
    fn asymmetric_extent_keeps_anchor_and_padding() {
        let c = json!({"op":"fitAnchor","offsets":[[-50.,10.],[10.,20.]],
          "width":800.,"height":600.,"currentScale":256.,"rotation":0.,
          "minZoom":0.,"maxZoom":12.,"paddingX":-70.,"paddingY":-20.});
        let r = execute(&c).unwrap();
        assert_eq!(r["zoom"], 3.);
        assert_eq!(r["offsetX"], -70.);
        assert_eq!(r["offsetY"], -20.);
        let mut bad = c.clone();
        bad["width"] = json!(0.);
        assert!(execute(&bad).unwrap().is_null());
        bad["width"] = json!(800.);
        bad["minZoom"] = json!(13.);
        assert!(execute(&bad).is_err());
    }
    #[test]
    fn ffi_output_is_released() {
        let input = br#"{"op":"groupAnchor","stationFit":true}"#;
        let mut len = 0;
        let p = unsafe { rq_camera_focus_prepare(input.as_ptr(), input.len(), &mut len) };
        assert!(!p.is_null());
        assert_eq!(len, 4);
        unsafe {
            rq_camera_focus_free(p, len);
        }
        assert_eq!(rq_camera_focus_outputs(), 0);
    }
}
