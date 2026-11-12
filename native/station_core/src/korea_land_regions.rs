//! Official SGIS land polygons. No marine jurisdiction inferred from land data.
use crate::japan_sea_regions::Regions;
use std::sync::OnceLock;

fn lookup(lat: f64, lon: f64) -> Option<&'static str> {
    if !lat.is_finite()
        || !lon.is_finite()
        || !(32.0..=40.0).contains(&lat)
        || !(123.0..=133.0).contains(&lon)
    {
        return None;
    }
    static DATA: OnceLock<Regions> = OnceLock::new();
    DATA.get_or_init(|| {
        Regions::new(include_bytes!(
            "../../../assets/regions/korea_land_regions.bin"
        ))
    })
    .lookup(lat, lon)
}

/// # Safety
/// `length` must point to writable usize storage. Returned UTF-8 has static
/// lifetime and must not be freed or mutated by the caller.
#[no_mangle]
pub unsafe extern "C" fn rq_korea_land_lookup(lat: f64, lon: f64, length: *mut usize) -> *const u8 {
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

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn official_land_polygons_instead_of_old_rectangles() {
        assert_eq!(lookup(37.5750, 126.9800), Some("韩国首尔特别市"));
        assert_eq!(lookup(35.1796, 129.0756), Some("韩国釜山广域市"));
        assert_eq!(lookup(33.4996, 126.5312), Some("韩国济州特别自治道"));
        assert_eq!(lookup(36.1, 128.2), Some("韩国庆尚北道"));
        assert_eq!(lookup(37.55, 126.5), None);
        assert_eq!(lookup(32.122, 125.182), None);
        assert_eq!(lookup(32.6817, 130.7217), None);
        assert_eq!(lookup(39.9042, 116.4074), None);
        assert_eq!(lookup(23.11, 121.35), None);
    }
    #[test]
    fn island_name_does_not_assign_disputed_ownership() {
        // An unchanged vertex from the compiled official source, not the sea
        // between the two islands; CWR1 stores the source transform as Float32.
        assert_eq!(
            lookup(37.24125289916992, 131.87033081054688),
            Some("独岛（竹岛）")
        );
    }
    #[test]
    fn utf8_ffi_rejects_invalid_values() {
        unsafe {
            assert!(rq_korea_land_lookup(37.575, 126.98, std::ptr::null_mut()).is_null());
            let mut n = 0;
            let p = rq_korea_land_lookup(37.575, 126.98, &mut n);
            assert_eq!(
                std::str::from_utf8(std::slice::from_raw_parts(p, n)).unwrap(),
                "韩国首尔特别市"
            );
            assert!(rq_korea_land_lookup(f64::NAN, 126.98, &mut n).is_null());
            assert_eq!(n, 0);
        }
    }
}
