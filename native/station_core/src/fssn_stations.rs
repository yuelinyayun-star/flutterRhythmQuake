//! Original FSSN layout and binary overlay frames, in upstream station order.
use serde_json::Value;
use std::sync::atomic::{AtomicUsize, Ordering};

static SESSIONS: AtomicUsize = AtomicUsize::new(0);
const STOPS: [f64; 16] = [
    0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1., 2., 5., 10., 20., 50., 100., 200., 500., 1000.,
];
const COLORS: [u32; 16] = [
    0x0008d2, 0x0012d8, 0x0035dc, 0x0071d0, 0x01c784, 0x25ec4a, 0x70f517, 0xcdff08, 0xfefe00,
    0xfff100, 0xffc600, 0xff8d00, 0xff5500, 0xff2300, 0xe00400, 0x8b0000,
];

fn color(pga: Option<f64>) -> u32 {
    let Some(pga) = pga else { return 0xffc0c0c0 };
    if pga >= 1000. {
        return 0xff000000;
    }
    if pga <= STOPS[0] {
        return 0xff000000 | COLORS[0];
    }
    for i in 0..STOPS.len() - 1 {
        if pga <= STOPS[i + 1] {
            let t = (pga.log10() - STOPS[i].log10()) / (STOPS[i + 1].log10() - STOPS[i].log10());
            let mut rgb = 0xff000000;
            for shift in [16, 8, 0] {
                let a = ((COLORS[i] >> shift) & 255) as f64;
                let b = ((COLORS[i + 1] >> shift) & 255) as f64;
                rgb |= ((a + (b - a) * t).round() as u32) << shift;
            }
            return rgb;
        }
    }
    0xff000000 | COLORS[0]
}

pub struct FssnStations {
    coordinates: Vec<(f64, f64)>,
}
impl FssnStations {
    fn new(bytes: &[u8]) -> Option<Self> {
        let layout: Value = serde_json::from_slice(bytes).ok()?;
        let stations = layout["stations"].as_array()?;
        if layout["img_w"].as_u64()? != 1200
            || layout["img_h"].as_u64()? != 900
            || stations.is_empty()
            || stations.len() > 255
        {
            return None;
        }
        let mut coordinates = Vec::with_capacity(stations.len());
        let mut names = std::collections::HashSet::new();
        for station in stations {
            let name = station["name"].as_str()?;
            let x = station["x"].as_f64()?;
            let y = station["y"].as_f64()?;
            if name.is_empty()
                || !names.insert(name)
                || !x.is_finite()
                || !y.is_finite()
                || !(0.0..=1200.).contains(&x)
                || !(0.0..=900.).contains(&y)
            {
                return None;
            }
            // The API exposes pixels only. These bounds were calibrated against
            // the original 1200x900 basemap's province boundaries (2026-11-18).
            // They are an inverse map projection, not official station metadata.
            coordinates.push((39.5 - y * 15.5 / 900., 100.5 + x * 20.5 / 1200.));
        }
        Some(Self { coordinates })
    }

    fn process(&self, bytes: &[u8], output: &mut [f64]) -> bool {
        let count = self.coordinates.len();
        let bitmap_len = (count * 2).div_ceil(8);
        if bytes.len() != 7 + bitmap_len + count * 2
            || output.len() != 1 + count * 5
            || bytes[0] != 0x46
            || bytes[5] as usize != count
            || bytes.iter().fold(0, |checksum, byte| checksum ^ byte) != 0
        {
            return false;
        }
        output[0] = u32::from_le_bytes(bytes[1..5].try_into().unwrap()) as f64;
        for (i, &(lat, lon)) in self.coordinates.iter().enumerate() {
            let status = (bytes[6 + i * 2 / 8] >> (i * 2 % 8)) & 3;
            let offset = 6 + bitmap_len + i * 2;
            let raw = u16::from_le_bytes([bytes[offset], bytes[offset + 1]]);
            let pga = (raw != u16::MAX).then_some(raw as f64 / 10.);
            output[1 + i * 5..1 + (i + 1) * 5].copy_from_slice(&[
                lat,
                lon,
                pga.unwrap_or(-1.),
                status as f64,
                color(pga) as f64,
            ]);
        }
        true
    }
}

#[no_mangle]
pub unsafe extern "C" fn rq_fssn_stations_create(
    bytes: *const u8,
    len: usize,
) -> *mut FssnStations {
    if bytes.is_null() || len == 0 || len > 256 * 1024 {
        return std::ptr::null_mut();
    }
    std::panic::catch_unwind(|| {
        let Some(owner) = FssnStations::new(unsafe { std::slice::from_raw_parts(bytes, len) })
        else {
            return std::ptr::null_mut();
        };
        SESSIONS.fetch_add(1, Ordering::Relaxed);
        Box::into_raw(Box::new(owner))
    })
    .unwrap_or(std::ptr::null_mut())
}
#[no_mangle]
pub unsafe extern "C" fn rq_fssn_stations_count(owner: *const FssnStations) -> usize {
    if owner.is_null() {
        return 0;
    }
    unsafe { &*owner }.coordinates.len()
}
#[no_mangle]
pub unsafe extern "C" fn rq_fssn_stations_process(
    owner: *const FssnStations,
    bytes: *const u8,
    len: usize,
    output: *mut f64,
    output_len: usize,
) -> i32 {
    if owner.is_null() || bytes.is_null() || output.is_null() || len > 1024 || output_len > 1276 {
        return -1;
    }
    std::panic::catch_unwind(|| {
        let valid = unsafe { &*owner }
            .process(unsafe { std::slice::from_raw_parts(bytes, len) }, unsafe {
                std::slice::from_raw_parts_mut(output, output_len)
            });
        if valid {
            0
        } else {
            -2
        }
    })
    .unwrap_or(-3)
}
#[no_mangle]
pub unsafe extern "C" fn rq_fssn_stations_destroy(owner: *mut FssnStations) {
    if !owner.is_null() {
        drop(unsafe { Box::from_raw(owner) });
        SESSIONS.fetch_sub(1, Ordering::Relaxed);
    }
}
#[no_mangle]
pub extern "C" fn rq_fssn_stations_sessions() -> usize {
    SESSIONS.load(Ordering::Relaxed)
}

#[cfg(test)]
mod tests {
    use super::*;
    const LAYOUT: &[u8] =
        include_bytes!("../../../test/fixtures/fssn_stations/stations.original.json");
    const FRAME: &[u8] =
        include_bytes!("../../../test/fixtures/fssn_stations/overlay.original.bin");
    #[test]
    fn original_overlay_preserves_order_values_and_missing_data() {
        let owner = FssnStations::new(LAYOUT).unwrap();
        let mut output = vec![0.; 76];
        assert!(owner.process(FRAME, &mut output));
        assert_eq!(owner.coordinates.len(), 15);
        assert!((output[1] - 30.64907).abs() < 1e-10);
        assert!((output[2] - 104.00932).abs() < 1e-10);
        for i in 0..15 {
            let raw = u16::from_le_bytes([FRAME[10 + i * 2], FRAME[11 + i * 2]]);
            assert_eq!(
                output[3 + i * 5],
                if raw == 65535 { -1. } else { raw as f64 / 10. }
            );
            assert_eq!(
                output[4 + i * 5] as u8,
                (FRAME[6 + i * 2 / 8] >> (i * 2 % 8)) & 3
            );
        }
    }
    #[test]
    fn malformed_frames_leave_output_untouched() {
        let owner = FssnStations::new(LAYOUT).unwrap();
        for bytes in [b"<html>upstream error</html>".as_slice(), &FRAME[..40], &[]] {
            let mut output = vec![123.; 76];
            assert!(!owner.process(bytes, &mut output));
            assert!(output.iter().all(|x| *x == 123.));
        }
        let mut corrupt = FRAME.to_vec();
        corrupt[10] ^= 1;
        assert!(!owner.process(&corrupt, &mut [123.; 76]));
        assert!(FssnStations::new(b"<html>error</html>").is_none());
    }
    #[test]
    fn original_palette_stops_and_log_interpolation() {
        assert_eq!(color(None), 0xffc0c0c0);
        assert_eq!(color(Some(0.)), 0xff0008d2);
        for i in 0..15 {
            assert_eq!(color(Some(STOPS[i])), 0xff000000 | COLORS[i]);
        }
        assert_eq!(color(Some(1000.)), 0xff000000);
        assert_eq!(color(Some(2000.)), 0xff000000);
        assert_eq!(color(Some((0.01_f64 * 0.02).sqrt())), 0xff000dd5);
    }
}
