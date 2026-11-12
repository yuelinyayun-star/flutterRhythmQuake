//! Static epicentral naming regions, not sovereignty or maritime boundaries.
//! No JSON parsing, polygon allocation or mutable global state per query.
use std::sync::OnceLock;

pub(crate) struct Regions {
    data: &'static [u8],
    features: usize,
    strings: usize,
    names: usize,
    feature_offset: usize,
    polygon_offset: usize,
    ring_offset: usize,
    point_offset: usize,
    feature_size: usize,
    point_size: usize,
}
impl Regions {
    pub(crate) fn new(data: &'static [u8]) -> Self {
        assert!(data.len() >= 64 && (&data[..4] == b"CWR1" || &data[..4] == b"CWR2"));
        let double = &data[..4] == b"CWR2";
        assert_eq!(read_u32(data, 4), 1);
        assert_eq!(read_u32(data, 48), if double { 48 } else { 32 });
        assert_eq!(read_u32(data, 52), 8);
        assert_eq!(read_u32(data, 56), 8);
        let result = Self {
            data,
            features: read_u32(data, 8),
            names: read_u32(data, 24),
            strings: read_u32(data, 28),
            feature_offset: read_u32(data, 32),
            polygon_offset: read_u32(data, 36),
            ring_offset: read_u32(data, 40),
            point_offset: read_u32(data, 44),
            feature_size: if double { 48 } else { 32 },
            point_size: if double { 16 } else { 8 },
        };
        assert!(result.feature_offset + result.features * result.feature_size <= data.len());
        assert!(result.polygon_offset + read_u32(data, 12) * 8 <= data.len());
        assert!(result.ring_offset + read_u32(data, 16) * 8 <= data.len());
        assert!(result.point_offset + read_u32(data, 20) * result.point_size <= data.len());
        for i in 0..result.names {
            assert!(result.name(i).is_some());
        }
        result
    }
    fn name(&self, index: usize) -> Option<&'static str> {
        if index >= self.names {
            return None;
        }
        let base = self.strings + (self.names + 1) * 4;
        let start = read_u32(self.data, self.strings + index * 4);
        let end = read_u32(self.data, self.strings + (index + 1) * 4);
        std::str::from_utf8(self.data.get(base + start..base + end)?).ok()
    }
    pub(crate) fn lookup(&self, lat: f64, lon: f64) -> Option<&'static str> {
        let mut best = None;
        let mut best_area = f64::INFINITY;
        for i in 0..self.features {
            let o = self.feature_offset + i * self.feature_size;
            let scalar = self.point_size / 2;
            let read = if self.point_size == 16 {
                read_f64
            } else {
                read_f32
            };
            let ymin = read(self.data, o);
            let ymax = read(self.data, o + scalar);
            let xmin = read(self.data, o + 2 * scalar);
            let xmax = read(self.data, o + 3 * scalar);
            if lat < ymin || lat > ymax || lon < xmin || lon > xmax {
                continue;
            }
            let area = (ymax - ymin) * (xmax - xmin);
            if area >= best_area {
                continue;
            }
            let fields = o + 4 * scalar;
            let first = read_u32(self.data, fields + 4);
            let count = read_u32(self.data, fields + 8);
            if (first..first + count).any(|p| self.polygon(p, lat, lon)) {
                best = self.name(read_u32(self.data, fields));
                best_area = area;
            }
        }
        best
    }
    fn polygon(&self, index: usize, lat: f64, lon: f64) -> bool {
        let o = self.polygon_offset + index * 8;
        let first = read_u32(self.data, o);
        let count = read_u32(self.data, o + 4);
        count > 0
            && self.ring(first, lat, lon)
            && !(first + 1..first + count).any(|r| self.ring(r, lat, lon))
    }
    fn ring(&self, index: usize, lat: f64, lon: f64) -> bool {
        let o = self.ring_offset + index * 8;
        let first = read_u32(self.data, o);
        let count = read_u32(self.data, o + 4);
        if count < 3 {
            return false;
        }
        let mut previous = self.point(first + count - 1);
        let mut inside = false;
        let epsilon = if self.point_size == 16 { 1e-12 } else { 1e-6 };
        for i in first..first + count {
            let current = self.point(i);
            let (x1, y1) = previous;
            let (x2, y2) = current;
            let cross = (lon - x1) * (y2 - y1) - (lat - y1) * (x2 - x1);
            if cross.abs() <= epsilon
                && lon >= x1.min(x2) - epsilon
                && lon <= x1.max(x2) + epsilon
                && lat >= y1.min(y2) - epsilon
                && lat <= y1.max(y2) + epsilon
            {
                return true;
            }
            if (y1 > lat) != (y2 > lat) && lon < (x1 - x2) * (lat - y2) / (y1 - y2) + x2 {
                inside = !inside;
            }
            previous = current;
        }
        inside
    }
    fn point(&self, index: usize) -> (f64, f64) {
        let o = self.point_offset + index * self.point_size;
        if self.point_size == 16 {
            (read_f64(self.data, o), read_f64(self.data, o + 8))
        } else {
            (read_f32(self.data, o), read_f32(self.data, o + 4))
        }
    }
}
fn read_u32(d: &[u8], o: usize) -> usize {
    u32::from_le_bytes(d[o..o + 4].try_into().unwrap()) as usize
}
fn read_f32(d: &[u8], o: usize) -> f64 {
    f32::from_le_bytes(d[o..o + 4].try_into().unwrap()) as f64
}
fn read_f64(d: &[u8], o: usize) -> f64 {
    f64::from_le_bytes(d[o..o + 8].try_into().unwrap())
}
fn domestic_regions() -> &'static Regions {
    static DATA: OnceLock<Regions> = OnceLock::new();
    DATA.get_or_init(|| {
        Regions::new(include_bytes!(
            "../../../assets/regions/diaoyu_official_regions.bin"
        ))
    })
}
fn seas() -> &'static Regions {
    static DATA: OnceLock<Regions> = OnceLock::new();
    DATA.get_or_init(|| {
        Regions::new(include_bytes!(
            "../../../assets/regions/japan_sea_regions.bin"
        ))
    })
}
fn land() -> &'static Regions {
    static DATA: OnceLock<Regions> = OnceLock::new();
    DATA.get_or_init(|| {
        Regions::new(include_bytes!(
            "../../../assets/regions/japan_land_regions.bin"
        ))
    })
}
fn lookup(lat: f64, lon: f64, domestic: bool) -> Option<&'static str> {
    if !lat.is_finite()
        || !lon.is_finite()
        || !(-90.0..=90.0).contains(&lat)
        || !(-180.0..=180.0).contains(&lon)
    {
        return None;
    }
    if domestic {
        if crate::east_asia_regions::prefers_base_fe(lat, lon) {
            return None;
        }
        return domestic_regions().lookup(lat, lon);
    }
    // Do not turn coarse epicentral polygons into land administrative names.
    // Preserve the existing FE land behavior. China/CWA priority is in caller.
    if land().lookup(lat, lon).is_some() {
        return None;
    }
    seas().lookup(lat, lon)
}

/// Caller owns `length`; the returned UTF-8 slice has static library lifetime.
/// `domestic=1` selects official Diaoyu island names and the baseline-derived
/// 12-nm regional envelope; 0 selects the existing sea-name source.
/// # Safety
/// `length` must point to writable usize storage; no pointers escape to Rust.
#[no_mangle]
pub unsafe extern "C" fn rq_japan_sea_lookup(
    lat: f64,
    lon: f64,
    domestic: u32,
    length: *mut usize,
) -> *const u8 {
    if length.is_null() {
        return std::ptr::null();
    }
    unsafe {
        *length = 0;
    }
    let result = std::panic::catch_unwind(|| lookup(lat, lon, domestic != 0));
    if let Ok(Some(name)) = result {
        unsafe {
            *length = name.len();
        }
        return name.as_ptr();
    }
    std::ptr::null()
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn regional_sea_queries() {
        assert_eq!(lookup(38.1, 142.0, false), Some("宫城县海域"));
        assert_eq!(lookup(38.1, 142.8, false), Some("三陆海域"));
        assert_eq!(lookup(37.4, 142.0, false), Some("福岛县海域"));
        assert_eq!(lookup(39.5, 142.3, false), Some("岩手县海域"));
        assert_eq!(lookup(35.6762, 139.6503, false), None);
        assert_eq!(lookup(32.6817, 130.7217, false), None);
        assert_eq!(lookup(45.5152, -122.6784, false), None);
        assert_eq!(lookup(f64::NAN, 140.0, false), None);
        assert_eq!(lookup(91.0, 140.0, false), None);
    }
    #[test]
    fn domestic_baselines_are_not_japanese_seas() {
        assert_eq!(
            domestic_regions().lookup(25.0 + 44.6 / 60.0, 123.0 + 28.4 / 60.0),
            Some("钓鱼岛")
        );
        assert_eq!(
            domestic_regions().lookup(25.0 + 55.3 / 60.0, 124.0 + 33.5 / 60.0),
            // Published reference coordinates are not precise shoreline data.
            Some("钓鱼岛及其附属岛屿")
        );
        assert_eq!(
            domestic_regions().lookup(25.9225440715, 124.55905788159185),
            Some("赤尾屿")
        );
        assert_eq!(lookup(25.743333333333, 123.473333333333, true), None);
        assert_eq!(lookup(26.5, 124.5, false), Some("东海"));
        assert_eq!(lookup(26.5, 124.5, true), None);
        assert_eq!(lookup(38.1, 142.8, true), None);
    }
    #[test]
    fn ffi_static_utf8_and_null_output() {
        unsafe {
            assert!(rq_japan_sea_lookup(38.1, 142.8, 0, std::ptr::null_mut()).is_null());
            let mut n = 0;
            let p = rq_japan_sea_lookup(38.1, 142.0, 0, &mut n);
            assert_eq!(
                std::str::from_utf8(std::slice::from_raw_parts(p, n)).unwrap(),
                "宫城县海域"
            );
            assert!(rq_japan_sea_lookup(f64::NAN, 142.8, 0, &mut n).is_null());
            assert_eq!(n, 0);
        }
    }
}
