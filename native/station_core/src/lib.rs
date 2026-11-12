#![deny(unsafe_op_in_unsafe_fn)]

mod global_quake_stream;
#[cfg(windows)]
mod http_transport;
#[cfg(target_os = "android")]
#[path = "android_http_transport.rs"]
mod http_transport;
#[cfg(target_os = "android")]
mod android_platform;
#[cfg(target_os = "android")]
mod android_network;
mod hyp_geometry;
mod hyp_score;
mod hyp_search;
#[cfg(any(windows, target_os = "android"))]
mod jma_tile_images;
#[cfg(any(windows, target_os = "android"))]
mod jma_tile_runtime;
mod jma_tsunami;
mod jma_eew;
mod jma_lpgm_display;
mod japan_sea_regions;
mod korea_land_regions;
mod east_asia_regions;
mod tsunami_regions;
mod json_envelope;
mod ka_detector;
mod ka_history;
mod map_coordinates;
mod camera_focus;
mod whews_connection;
mod jian_connection;
mod dyfi_grid;
mod windows_tts;
mod event_render_clipboard;
mod weather_map_policy;
mod weather_playback;
mod nsmc_image;
#[cfg(any(windows, target_os = "android"))]
mod network_diagnostic;
#[cfg(any(windows, target_os = "android"))]
mod field_log;
mod nied_detection_state;
mod nied_gif_sample;
mod nied_topology;
mod observation_history;
mod palert_distance_sort;
mod palert_levels;
mod palert_topology;
#[cfg(any(windows, target_os = "android"))]
mod replay_log;
mod seedlink_codec;
mod seedlink_signal;
mod station_archive;
mod replay_files;
mod replay_policy;
mod obs_automation_policy;
mod station_json;
mod station_record_state;
#[cfg(any(windows, target_os = "android"))]
mod station_runtime;
mod station_summary;
#[cfg(any(windows, target_os = "android"))]
mod tcp_transport;
mod topology_sort;
mod trigger;
mod unified_catalog_bucket;
mod unified_catalog_history;
mod unified_event_policy;
mod unified_event_runtime;
mod unified_event_sort;
mod unified_event_state;
#[cfg(windows)]
mod websocket;
#[cfg(target_os = "android")]
#[path = "android_websocket.rs"]
mod websocket;
#[cfg(any(windows, target_os = "android"))]
mod whews_auth_block;

use image::{ColorType, ImageDecoder, ImageReader, Limits};
use std::alloc::{GlobalAlloc, Layout, System};
use std::io::Cursor;
use std::sync::atomic::{AtomicUsize, Ordering};

const MAX_INPUT: usize = 8 * 1024 * 1024;
const MAX_PIXELS: usize = 1024 * 1024;
const VALID: u64 = 1 << 32;
static CURRENT: AtomicUsize = AtomicUsize::new(0);
static PEAK: AtomicUsize = AtomicUsize::new(0);
static CALLS: AtomicUsize = AtomicUsize::new(0);

struct TrackedAllocator;
fn added(size: usize) {
    let current = CURRENT.fetch_add(size, Ordering::Relaxed) + size;
    PEAK.fetch_max(current, Ordering::Relaxed);
}
unsafe impl GlobalAlloc for TrackedAllocator {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        let ptr = unsafe { System.alloc(layout) };
        if !ptr.is_null() {
            added(layout.size());
        }
        ptr
    }
    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        let ptr = unsafe { System.alloc_zeroed(layout) };
        if !ptr.is_null() {
            added(layout.size());
        }
        ptr
    }
    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        unsafe { System.dealloc(ptr, layout) };
        CURRENT.fetch_sub(layout.size(), Ordering::Relaxed);
    }
    unsafe fn realloc(&self, ptr: *mut u8, old: Layout, size: usize) -> *mut u8 {
        let next = unsafe { System.realloc(ptr, old, size) };
        if !next.is_null() {
            if size >= old.size() {
                added(size - old.size());
            } else {
                CURRENT.fetch_sub(old.size() - size, Ordering::Relaxed);
            }
        }
        next
    }
}
#[global_allocator]
static ALLOCATOR: TrackedAllocator = TrackedAllocator;

#[no_mangle]
pub extern "C" fn rq_station_core_abi_version() -> u32 {
    1
}
#[no_mangle]
pub extern "C" fn rq_station_memory_current() -> u64 {
    CURRENT.load(Ordering::Relaxed) as u64
}
#[no_mangle]
pub extern "C" fn rq_station_memory_peak() -> u64 {
    PEAK.load(Ordering::Relaxed) as u64
}
#[no_mangle]
pub extern "C" fn rq_station_decode_calls() -> u64 {
    CALLS.load(Ordering::Relaxed) as u64
}

/// # Safety
/// The caller must provide valid, non-overlapping buffers of the sizes stated
/// in rq_station_core.h, aligned for their element types. No buffer is retained.
#[no_mangle]
pub unsafe extern "C" fn rq_station_decode_sample(
    bytes: *const u8,
    length: usize,
    xy: *const i64,
    count: usize,
    result: *mut u64,
    dimensions: *mut u32,
) -> i32 {
    if bytes.is_null()
        || dimensions.is_null()
        || length == 0
        || (count != 0 && (xy.is_null() || result.is_null()))
    {
        return 1;
    }
    if length > MAX_INPUT || count > MAX_PIXELS {
        return 3;
    }
    CALLS.fetch_add(1, Ordering::Relaxed);
    std::panic::catch_unwind(|| unsafe {
        let input = std::slice::from_raw_parts(bytes, length);
        let coords = if count == 0 {
            &[]
        } else {
            std::slice::from_raw_parts(xy, count * 2)
        };
        let out = if count == 0 {
            &mut []
        } else {
            std::slice::from_raw_parts_mut(result, count)
        };
        let dims = std::slice::from_raw_parts_mut(dimensions, 2);
        decode_sample(input, coords, out, dims)
    })
    .unwrap_or(5)
}

fn decode_sample(input: &[u8], xy: &[i64], out: &mut [u64], dims: &mut [u32]) -> i32 {
    dims.fill(0);
    out.fill(0);
    let Ok(mut reader) = ImageReader::new(Cursor::new(input)).with_guessed_format() else {
        return 2;
    };
    let mut limits = Limits::default();
    limits.max_image_width = Some(MAX_PIXELS as u32);
    limits.max_image_height = Some(MAX_PIXELS as u32);
    limits.max_alloc = Some(16 * 1024 * 1024);
    reader.limits(limits);
    let decoder = match reader.into_decoder() {
        Ok(d) => d,
        Err(image::ImageError::Unsupported(_)) => return 4,
        Err(image::ImageError::Limits(_)) => return 3,
        Err(_) => return 2,
    };
    let (width, height) = decoder.dimensions();
    if width == 0 || height == 0 || width as u64 * height as u64 > MAX_PIXELS as u64 {
        return 3;
    }
    let color = decoder.color_type();
    let channels = match color {
        ColorType::L8 => 1,
        ColorType::La8 => 2,
        ColorType::Rgb8 => 3,
        ColorType::Rgba8 => 4,
        _ => return 4,
    };
    let expected = width as usize * height as usize * channels;
    if decoder.total_bytes() != expected as u64 {
        return 2;
    }
    let mut pixels = vec![0; expected];
    if decoder.read_image(&mut pixels).is_err() {
        return 2;
    }
    for (index, coord) in xy.chunks_exact(2).enumerate() {
        let (x, y) = (coord[0], coord[1]);
        if x < 0 || y < 0 || x >= width as i64 || y >= height as i64 {
            continue;
        }
        let offset = (y as usize * width as usize + x as usize) * channels;
        let (r, g, b, a) = match color {
            ColorType::L8 => (pixels[offset], pixels[offset], pixels[offset], 255),
            ColorType::La8 => (
                pixels[offset],
                pixels[offset],
                pixels[offset],
                pixels[offset + 1],
            ),
            ColorType::Rgb8 => (pixels[offset], pixels[offset + 1], pixels[offset + 2], 255),
            ColorType::Rgba8 => (
                pixels[offset],
                pixels[offset + 1],
                pixels[offset + 2],
                pixels[offset + 3],
            ),
            _ => unreachable!(),
        };
        out[index] = VALID | ((a as u64) << 24) | ((r as u64) << 16) | ((g as u64) << 8) | b as u64;
    }
    dims[0] = width;
    dims[1] = height;
    0
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rejects_empty_null_oversized_and_bad_images() {
        let mut dimensions = [7, 7];
        assert_eq!(
            unsafe {
                rq_station_decode_sample(
                    std::ptr::null(),
                    0,
                    std::ptr::null(),
                    0,
                    std::ptr::null_mut(),
                    dimensions.as_mut_ptr(),
                )
            },
            1
        );
        let input = [0u8];
        assert_eq!(
            unsafe {
                rq_station_decode_sample(
                    input.as_ptr(),
                    MAX_INPUT + 1,
                    std::ptr::null(),
                    0,
                    std::ptr::null_mut(),
                    dimensions.as_mut_ptr(),
                )
            },
            3
        );
        assert_ne!(
            unsafe {
                rq_station_decode_sample(
                    input.as_ptr(),
                    1,
                    std::ptr::null(),
                    0,
                    std::ptr::null_mut(),
                    dimensions.as_mut_ptr(),
                )
            },
            0
        );
        assert_eq!(dimensions, [0, 0]);
    }
}

mod knet_features;

mod knet_batch;
