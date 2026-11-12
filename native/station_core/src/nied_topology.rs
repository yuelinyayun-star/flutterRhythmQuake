//! Complete NIED neighbour preparation from original directory coordinates.
//! Preserve distance/ID ordering, sparse fallback and four-direction coverage.
use serde_json::{json, Value};
use std::f64::consts::PI;
use std::ffi::c_void;

fn distance(a: &[f64], b: &[f64]) -> f64 {
    let dlat = (b[0] - a[0]) * PI / 180.0;
    let dlon = (b[1] - a[1]) * PI / 180.0;
    let lat1 = a[0] * PI / 180.0;
    let lat2 = b[0] * PI / 180.0;
    let x = (dlat / 2.0).sin();
    let y = (dlon / 2.0).sin();
    let value = x * x + lat1.cos() * lat2.cos() * y * y;
    let value = if value.is_nan() {
        1.0
    } else {
        value.clamp(0.0, 1.0)
    };
    6371.0 * 2.0 * value.sqrt().atan2((1.0 - value).sqrt())
}
fn direction(a: &[f64], b: &[f64]) -> usize {
    let phi1 = a[0] * PI / 180.0;
    let phi2 = b[0] * PI / 180.0;
    let delta = (b[1] - a[1]) * PI / 180.0;
    let y = delta.sin() * phi2.cos();
    let x = phi1.cos() * phi2.sin() - phi1.sin() * phi2.cos() * delta.cos();
    let bearing = (y.atan2(x) * 180.0 / PI + 360.0).rem_euclid(360.0);
    (((bearing + 45.0).rem_euclid(360.0) / 90.0) as usize) % 4
}
fn build(ids: &[i64], xy: &[f64], codes: &[String]) -> Result<Vec<u8>, ()> {
    let count = ids.len();
    let mut rows = Vec::<Value>::with_capacity(count);
    let mut distances = vec![0.0; count];
    let mut indices = vec![0u32; count];
    for i in 0..count {
        let first = &xy[i * 2..i * 2 + 2];
        for (j, value) in distances.iter_mut().enumerate() {
            *value = distance(first, &xy[j * 2..j * 2 + 2]);
        }
        let used = unsafe {
            crate::topology_sort::rq_topology_sort(
                distances.as_ptr(),
                ids.as_ptr(),
                count,
                indices.as_mut_ptr(),
            )
        };
        if used < 0 {
            return Err(());
        }
        let sorted = &indices[..used as usize];
        let mut nearby = Vec::new();
        let mut nearby_count = 0;
        for &j in sorted {
            let j = j as usize;
            if distances[j] > 30.0 {
                break;
            }
            nearby_count += 1;
            if nearby.len() < 6 {
                nearby.push(codes[j].clone());
            }
        }
        if nearby_count <= 1 {
            if let Some(&j) = sorted
                .iter()
                .find(|&&j| distances[j as usize] > 30.0 && distances[j as usize] <= 40.0)
            {
                if nearby.len() < 6 {
                    nearby.push(codes[j as usize].clone());
                }
            }
        }
        let mut selected = Vec::new();
        let mut covered = [false; 4];
        for &j in sorted {
            let j = j as usize;
            if distances[j] > 30.0 {
                break;
            }
            selected.push(ids[j]);
            if ids[j] != ids[i] {
                covered[direction(first, &xy[j * 2..j * 2 + 2])] = true;
            }
        }
        for &j in sorted {
            if covered.iter().all(|&v| v) {
                break;
            }
            let j = j as usize;
            if ids[j] == ids[i] || distances[j] <= 30.0 {
                continue;
            }
            let d = direction(first, &xy[j * 2..j * 2 + 2]);
            if !covered[d] {
                covered[d] = true;
                selected.push(ids[j]);
            }
        }
        rows.push(json!([ids[i].to_string(), codes[i], selected, nearby]));
    }
    Ok(crate::station_json::pack_value(&Value::Array(rows)))
}
/// Caller owns original ids[count], coordinates[count*2] and UTF-8 codes array.
/// The returned immutable tree owns its bytes and retains no caller pointers.
#[no_mangle]
pub unsafe extern "C" fn rq_nied_topology_build(
    ids: *const i64,
    coordinates: *const f64,
    count: usize,
    codes: *const u8,
    codes_len: usize,
) -> *mut c_void {
    if ids.is_null()
        || coordinates.is_null()
        || codes.is_null()
        || count > 1048576
        || codes_len > 64 * 1024 * 1024
    {
        return std::ptr::null_mut();
    }
    std::panic::catch_unwind(|| unsafe {
        let Ok(codes) =
            serde_json::from_slice::<Vec<String>>(std::slice::from_raw_parts(codes, codes_len))
        else {
            return std::ptr::null_mut();
        };
        if codes.len() != count {
            return std::ptr::null_mut();
        }
        match build(
            std::slice::from_raw_parts(ids, count),
            std::slice::from_raw_parts(coordinates, count * 2),
            &codes,
        ) {
            Ok(bytes) => Box::into_raw(Box::new(bytes)).cast(),
            Err(()) => std::ptr::null_mut(),
        }
    })
    .unwrap_or(std::ptr::null_mut())
}
#[no_mangle]
pub unsafe extern "C" fn rq_nied_topology_bytes(
    handle: *const c_void,
    len: *mut usize,
) -> *const u8 {
    if handle.is_null() || len.is_null() {
        return std::ptr::null();
    }
    let bytes = unsafe { &*handle.cast::<Vec<u8>>() };
    unsafe {
        *len = bytes.len();
    }
    bytes.as_ptr()
}
#[no_mangle]
pub unsafe extern "C" fn rq_nied_topology_free(handle: *mut c_void) {
    if !handle.is_null() {
        unsafe {
            drop(Box::from_raw(handle.cast::<Vec<u8>>()));
        }
    }
}

/// The display detector intentionally uses its original distance-only sort
/// (including equal-distance ordering), rather than the HYP distance/ID sort.
pub(crate) fn display_detector(xy: &[f64]) -> crate::ka_detector::Detector {
    fn km(a: &[f64], b: &[f64]) -> f64 {
        let r = 0.017453292519943295;
        let lat = (b[0] - a[0]) * r;
        let lng = (b[1] - a[1]) * r;
        let lat1 = a[0] * r;
        let lat2 = b[0] * r;
        let x = (lat / 2.0).sin();
        let y = (lng / 2.0).sin();
        2.0 * 6371.0 * (x * x + y * y * lat1.cos() * lat2.cos()).sqrt().asin()
    }
    let count = xy.len() / 2;
    let mut adjacency = Vec::with_capacity(count);
    for i in 0..count {
        let mut near = vec![];
        let mut fallback: Option<(usize, f64)> = None;
        for j in 0..count {
            let d = if i == j {
                0.0
            } else {
                km(&xy[i * 2..i * 2 + 2], &xy[j * 2..j * 2 + 2])
            };
            if d <= 30.0 {
                near.push((j, d));
            } else if d <= 40.0 && fallback.is_none_or(|(_, old)| d <= old) {
                fallback = Some((j, d));
            }
        }
        if near.len() <= 1 {
            if let Some(v) = fallback {
                near.push(v);
            }
        }
        crate::palert_distance_sort::sort(&mut near);
        near.truncate(6);
        adjacency.push(near.into_iter().map(|(i, _)| i).collect::<Vec<_>>());
    }
    let mut distances = std::collections::HashMap::new();
    for row in &adjacency {
        for (a, &first) in row.iter().enumerate() {
            for &second in &row[a + 1..] {
                distances
                    .entry((first as u32, second as u32))
                    .or_insert_with(|| {
                        km(
                            &xy[first * 2..first * 2 + 2],
                            &xy[second * 2..second * 2 + 2],
                        )
                    });
            }
        }
    }
    crate::ka_detector::Detector::from_topology(&adjacency, distances)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn immutable_result_keeps_directory_order_unicode_and_equal_distance_id_order() {
        // Codec/tie boundary inputs, not earthquake fixtures or measurements.
        let ids = [2, 1];
        let xy = [35.0, 140.0, 35.0, 140.0];
        let codes = vec!["日本\0".to_owned(), "站点".to_owned()];
        let encoded = serde_json::to_vec(&codes).unwrap();
        unsafe {
            let owner = rq_nied_topology_build(
                ids.as_ptr(),
                xy.as_ptr(),
                2,
                encoded.as_ptr(),
                encoded.len(),
            );
            assert!(!owner.is_null());
            let mut size = 0;
            let bytes = rq_nied_topology_bytes(owner, &mut size);
            let value =
                crate::station_json::unpack_value(std::slice::from_raw_parts(bytes, size), 0)
                    .unwrap();
            assert_eq!(
                value,
                json!([
                    ["2", "日本\0", [1, 2], ["站点", "日本\0"]],
                    ["1", "站点", [1, 2], ["站点", "日本\0"]]
                ])
            );
            rq_nied_topology_free(owner);
            assert_eq!(ids, [2, 1]);
            assert_eq!(xy, [35.0, 140.0, 35.0, 140.0]);
            assert!(rq_nied_topology_build(
                ids.as_ptr(),
                xy.as_ptr(),
                1,
                encoded.as_ptr(),
                encoded.len()
            )
            .is_null());
            rq_nied_topology_free(std::ptr::null_mut());
        }
    }
}
