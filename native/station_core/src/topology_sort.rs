//! Sort original Dart-computed distances without recalculating geometry.
use std::sync::atomic::{AtomicU64, Ordering};

const MAX_STATIONS: usize = 1_048_576;
static CALLS: AtomicU64 = AtomicU64::new(0);

#[no_mangle]
pub extern "C" fn rq_topology_sort_abi_version() -> u32 {
    1
}

#[no_mangle]
pub extern "C" fn rq_topology_sort_calls() -> u64 {
    CALLS.load(Ordering::Relaxed)
}

/// Returns the number of indices written, or a negative error code.
/// # Safety
/// Caller owns count distances, count IDs and count output indices in aligned,
/// non-overlapping buffers. IDs must be unique. No buffer is retained.
#[no_mangle]
pub unsafe extern "C" fn rq_topology_sort(
    distances: *const f64,
    ids: *const i64,
    count: usize,
    output: *mut u32,
) -> i64 {
    if count > MAX_STATIONS {
        return -3;
    }
    if count == 0 {
        return 0;
    }
    if distances.is_null() || ids.is_null() || output.is_null() {
        return -1;
    }
    std::panic::catch_unwind(|| unsafe {
        let distances = std::slice::from_raw_parts(distances, count);
        let ids = std::slice::from_raw_parts(ids, count);
        let output = std::slice::from_raw_parts_mut(output, count);
        let mut used = 0;
        for (index, &distance) in distances.iter().enumerate() {
            // Same comparison as Dart; NaN and +infinity are excluded.
            if distance <= 300.0 {
                output[used] = index as u32;
                used += 1;
            }
        }
        output[..used].sort_unstable_by(|&left, &right| {
            let (a, b) = (left as usize, right as usize);
            distances[a]
                .total_cmp(&distances[b])
                .then_with(|| ids[a].cmp(&ids[b]))
        });
        CALLS.fetch_add(1, Ordering::Relaxed);
        used as i64
    })
    .unwrap_or(-5)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ordering_cutoff_and_original_bits() {
        // Kernel boundary cases, not earthquake input or measured fixtures.
        let distances = [
            300.0,
            30.0,
            30.0,
            f64::NAN,
            300.00000000000006,
            -0.0,
            0.0,
            f64::INFINITY,
            40.0,
        ];
        let ids = [90, 20, 10, 40, 50, 60, 70, 80, 100];
        let original = distances.map(f64::to_bits);
        let mut output = [u32::MAX; 9];
        let used =
            unsafe { rq_topology_sort(distances.as_ptr(), ids.as_ptr(), 9, output.as_mut_ptr()) };
        assert_eq!(used, 6);
        assert_eq!(&output[..6], &[5, 6, 2, 1, 8, 0]);
        assert_eq!(distances.map(f64::to_bits), original);
        assert_eq!(output[6], u32::MAX);
    }

    #[test]
    fn empty_and_invalid_buffers() {
        assert_eq!(
            unsafe {
                rq_topology_sort(std::ptr::null(), std::ptr::null(), 0, std::ptr::null_mut())
            },
            0
        );
        assert_eq!(
            unsafe {
                rq_topology_sort(std::ptr::null(), std::ptr::null(), 1, std::ptr::null_mut())
            },
            -1
        );
        assert_eq!(
            unsafe {
                rq_topology_sort(
                    std::ptr::null(),
                    std::ptr::null(),
                    MAX_STATIONS + 1,
                    std::ptr::null_mut(),
                )
            },
            -3
        );
    }
}
