use crate::east_asia_regions;
use crate::japan_sea_regions::{self, read_f64, read_u32, Regions};
use std::sync::OnceLock;

// These original assets live in the library's read-only image. Flutter
// engines in one process share it and never copy it into their Dart heaps.
const GRID_DATA: &[u8] = include_bytes!("../../../assets/regions/china_place_index.bin");
const ADMIN_DATA: &[u8] = include_bytes!("../../../assets/regions/china_admin_regions.bin");

struct ChinaGrid {
    lat_min: f64,
    lon_min: f64,
    lat_step: f64,
    lon_step: f64,
    rows: usize,
    cols: usize,
    names: usize,
    strings: usize,
    cells: usize,
    missing: usize,
}

impl ChinaGrid {
    fn new() -> Self {
        assert_eq!(&GRID_DATA[..4], b"CPR1");
        assert_eq!(read_u32(GRID_DATA, 4), 1);
        let grid = Self {
            lat_min: read_f64(GRID_DATA, 8),
            lon_min: read_f64(GRID_DATA, 16),
            lat_step: read_f64(GRID_DATA, 24),
            lon_step: read_f64(GRID_DATA, 32),
            rows: read_u32(GRID_DATA, 40),
            cols: read_u32(GRID_DATA, 44),
            names: read_u32(GRID_DATA, 48),
            strings: read_u32(GRID_DATA, 52),
            cells: read_u32(GRID_DATA, 56),
            missing: read_u32(GRID_DATA, 64),
        };
        assert!(grid.lat_step > 0.0 && grid.lon_step > 0.0);
        assert_eq!(grid.rows * grid.cols, read_u32(GRID_DATA, 60));
        assert!(grid.cells + grid.rows * grid.cols * 2 <= GRID_DATA.len());
        assert!(grid.strings + (grid.names + 1) * 4 <= GRID_DATA.len());
        grid
    }

    fn lookup(&self, lat: f64, lon: f64) -> Option<&'static str> {
        let row = ((lat - self.lat_min) / self.lat_step).floor();
        let col = ((lon - self.lon_min) / self.lon_step).floor();
        if row < 0.0 || row >= self.rows as f64 || col < 0.0 || col >= self.cols as f64 {
            return None;
        }
        let cell = self.cells + (row as usize * self.cols + col as usize) * 2;
        let name = u16::from_le_bytes(GRID_DATA[cell..cell + 2].try_into().unwrap()) as usize;
        if name == self.missing || name >= self.names {
            return None;
        }
        let string_bytes = self.strings + (self.names + 1) * 4;
        let start = string_bytes + read_u32(GRID_DATA, self.strings + name * 4);
        let end = string_bytes + read_u32(GRID_DATA, self.strings + (name + 1) * 4);
        std::str::from_utf8(GRID_DATA.get(start..end)?)
            .ok()
            .filter(|name| !name.is_empty())
    }
}

fn grid() -> &'static ChinaGrid {
    static GRID: OnceLock<ChinaGrid> = OnceLock::new();
    GRID.get_or_init(ChinaGrid::new)
}

fn admin() -> &'static Regions {
    static ADMIN: OnceLock<Regions> = OnceLock::new();
    ADMIN.get_or_init(|| Regions::new(ADMIN_DATA))
}

fn has_county_detail(name: &str) -> bool {
    // Match Dart's ECMAScript `\s` and the position of the last visible
    // character. A county marker must be followed by more place text.
    let mut chars = name.chars().rev().filter(|c| {
        !matches!(
            c,
            '\u{0009}'..='\u{000d}' | '\u{0020}' | '\u{00a0}' | '\u{1680}'
                | '\u{2000}'..='\u{200a}' | '\u{2028}' | '\u{2029}' | '\u{202f}'
                | '\u{205f}' | '\u{3000}' | '\u{feff}'
        )
    });
    let last = chars.next();
    let mut cities = usize::from(last == Some('市'));
    chars.any(|c| {
        cities += usize::from(c == '市');
        matches!(c, '区' | '县' | '旗') || cities >= 2
    })
}

fn china_place(lat: f64, lon: f64) -> Option<&'static str> {
    let admin = admin().lookup_by_source_order(lat, lon);
    let grid = grid().lookup(lat, lon);
    let (Some(admin), Some(grid)) = (admin, grid) else {
        return admin.or(grid);
    };
    if admin == grid {
        return Some(admin);
    }
    match (has_county_detail(admin), has_county_detail(grid)) {
        (true, false) => Some(admin),
        (false, true) => Some(grid),
        _ if admin.encode_utf16().count() < grid.encode_utf16().count() => Some(grid),
        _ => Some(admin),
    }
}

fn epicenter(lat: f64, lon: f64) -> Option<&'static str> {
    if let Some(domestic) = japan_sea_regions::lookup(lat, lon, true) {
        return Some(domestic);
    }
    if let Some(province) = east_asia_regions::china_land(lat, lon) {
        return admin()
            .lookup_by_source_order(lat, lon)
            .or_else(|| grid().lookup(lat, lon))
            .or(Some(province));
    }
    east_asia_regions::lookup(lat, lon)
}

#[no_mangle]
pub extern "C" fn rq_epicenter_regions_prepare() -> u32 {
    u32::from(
        std::panic::catch_unwind(|| {
            grid();
            admin();
        })
        .is_ok(),
    )
}

/// `length` is caller-owned storage. Returned UTF-8 is immutable and lives
/// for the lifetime of this library, including across concurrent lookups.
#[no_mangle]
pub unsafe extern "C" fn rq_epicenter_regions_lookup(
    lat: f64,
    lon: f64,
    china_only: u32,
    length: *mut usize,
) -> *const u8 {
    if length.is_null() {
        return std::ptr::null();
    }
    unsafe { *length = 0 };
    if !(-90.0..=90.0).contains(&lat) || !(-180.0..=180.0).contains(&lon) {
        return std::ptr::null();
    }
    let result = std::panic::catch_unwind(|| {
        if china_only == 0 {
            epicenter(lat, lon)
        } else {
            china_place(lat, lon)
        }
    });
    if let Ok(Some(name)) = result {
        unsafe { *length = name.len() };
        return name.as_ptr();
    }
    std::ptr::null()
}
