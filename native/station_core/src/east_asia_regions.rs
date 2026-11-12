//! Effective, physically clipped place names. No geometry processing in Dart.
use crate::japan_sea_regions::Regions;
use sha2::{Digest, Sha256};
use std::sync::OnceLock;
const PLACE_DATA: &[u8] = include_bytes!("../../../assets/regions/east_asia_names.bin");
fn regions() -> &'static Regions {
    static DATA: OnceLock<Regions> = OnceLock::new();
    DATA.get_or_init(|| Regions::new(PLACE_DATA))
}
pub(crate) fn prefers_base_fe(lat: f64, lon: f64) -> bool {
    lat.is_finite() && lon.is_finite()
        && (0.0..=65.0).contains(&lat) && (70.0..=180.0).contains(&lon)
        && regions().lookup(lat, lon) == Some("__BASE_FE__")
}
fn china_land(lat: f64, lon: f64) -> Option<&'static str> {
    if !lat.is_finite()
        || !lon.is_finite()
        || !(0.0..=65.0).contains(&lat)
        || !(70.0..=180.0).contains(&lon)
    {
        return None;
    }
    if prefers_base_fe(lat, lon) { return None; }
    static DATA: OnceLock<Regions> = OnceLock::new();
    DATA.get_or_init(|| {
        Regions::new(include_bytes!(
            "../../../assets/regions/east_asia_china_coast.bin"
        ))
    })
    .lookup(lat, lon)
    .and_then(|name| name.strip_prefix("中国|"))
}
fn lookup(lat: f64, lon: f64) -> Option<&'static str> {
    if !lat.is_finite()
        || !lon.is_finite()
        || !(0.0..=65.0).contains(&lat)
        || !(70.0..=180.0).contains(&lon)
    {
        return None;
    }
    regions().lookup(lat, lon).filter(|name| *name != "__BASE_FE__")
}
/// Read-only identity for inspection: verify the loaded library contains the
/// same dataset as the rendered map. UTF-8 storage has static lifetime.
/// # Safety
/// `length` must point to writable usize storage.
#[no_mangle]
pub unsafe extern "C" fn rq_east_asia_dataset_sha256(length: *mut usize) -> *const u8 {
    if length.is_null() {
        return std::ptr::null();
    }
    static HASH: OnceLock<String> = OnceLock::new();
    let hash = HASH.get_or_init(|| format!("{:x}", Sha256::digest(PLACE_DATA)));
    unsafe {
        *length = hash.len();
    }
    hash.as_ptr()
}
/// # Safety
/// `length` points to writable usize storage; returned UTF-8 is static and must
/// never be freed or changed by the caller.
#[no_mangle]
pub unsafe extern "C" fn rq_east_asia_place_lookup(
    lat: f64,
    lon: f64,
    length: *mut usize,
) -> *const u8 {
    if length.is_null() {
        return std::ptr::null();
    }
    unsafe {
        *length = 0;
    }
    if let Ok(Some(name)) = std::panic::catch_unwind(|| lookup(lat, lon)) {
        unsafe {
            *length = name.len();
        }
        name.as_ptr()
    } else {
        std::ptr::null()
    }
}
/// # Safety
/// `length` must point to writable usize storage. Returned UTF-8 is static.
#[no_mangle]
pub unsafe extern "C" fn rq_east_asia_china_land_lookup(
    lat: f64,
    lon: f64,
    length: *mut usize,
) -> *const u8 {
    if length.is_null() {
        return std::ptr::null();
    }
    unsafe {
        *length = 0;
    }
    if let Ok(Some(name)) = std::panic::catch_unwind(|| china_land(lat, lon)) {
        unsafe {
            *length = name.len();
        }
        name.as_ptr()
    } else {
        std::ptr::null()
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn land_before_base_fe() {
        assert_eq!(lookup(35.6762, 139.6503), Some("日本东京都23区"));
        assert_eq!(lookup(32.6817, 130.7217), Some("日本熊本县熊本"));
        assert_eq!(
            // Representative interior point of the actual Tsushima polygon;
            // an old Float32 shoreline vertex may lie just outside the source.
            lookup(34.50392228886581, 129.36411689363132),
            Some("日本长崎县对马")
        );
        assert_eq!(lookup(38.1, 142.0), Some("宫城县海域"));
        assert_eq!(lookup(37.575, 126.98), Some("韩国首尔特别市"));
    }
    #[test]
    fn domestic_and_neutral_islands_keep_names() {
        assert_eq!(
            lookup(37.24125289916992, 131.87033081054688),
            Some("独岛（竹岛）")
        );
        assert!(!lookup(44.0, 145.8).unwrap_or("").starts_with("日本"));
        assert!(!lookup(25.7433, 123.4733).unwrap_or("").starts_with("日本"));
        assert_eq!(lookup(f64::NAN, 140.0), None);
    }
}
