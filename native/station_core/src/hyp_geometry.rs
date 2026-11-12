//! Candidate geometry and unchanged JMA2001 interpolation for the NIED scorer.
mod tables {
    include!("hyp_travel_tables.rs");
}
use std::sync::atomic::{AtomicU64, Ordering};
static CALLS: AtomicU64 = AtomicU64::new(0);
const MAX_STATIONS: usize = 1_048_576;

fn upper_bound(values: &[f64], value: f64) -> usize {
    let (mut lo, mut hi) = (1, values.len() - 1);
    while lo < hi {
        let mid = lo + (hi - lo) / 2;
        if values[mid] < value {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    lo
}

fn travel(distance: f64, depth: f64, times: &[f64]) -> f64 {
    if !distance.is_finite() || !depth.is_finite() {
        return f64::INFINITY;
    }
    let depth = if depth > 0.0 { depth } else { 0.0 };
    let distance = if distance > 0.0 { distance } else { 0.0 };
    let di = upper_bound(&tables::DEPTHS, depth);
    let xi = upper_bound(&tables::DISTANCES, distance);
    let (d0, d1) = (tables::DEPTHS[di - 1], tables::DEPTHS[di]);
    let (x0, x1) = (tables::DISTANCES[xi - 1], tables::DISTANCES[xi]);
    let (w0, w1) = (d1 - depth, depth - d0);
    let sum = w0 + w1;
    let sample = |row, col| times[row * tables::DISTANCES.len() + col];
    let blend = |col| {
        if sum == 0.0 {
            sample(di - 1, col)
        } else {
            (w0 * sample(di - 1, col) + w1 * sample(di, col)) / sum
        }
    };
    let (t0, t1) = (blend(xi - 1), blend(xi));
    if x1 == x0 {
        return t0;
    }
    let slope = (t1 - t0) / (x1 - x0);
    t1 - slope * x1 + slope * distance
}

pub(crate) fn travel_pair(distance: f64, depth: f64) -> (f64, f64) {
    (
        travel(distance, depth, &tables::P_TIMES),
        travel(distance, depth, &tables::S_TIMES),
    )
}

#[no_mangle]
pub extern "C" fn rq_hyp_geometry_abi_version() -> u32 {
    1
}
#[no_mangle]
pub extern "C" fn rq_hyp_geometry_calls() -> u64 {
    CALLS.load(Ordering::Relaxed)
}

/// # Safety
/// Caller owns count distances and count distance/P/S triples, with no
/// overlap. Input is kept in its original order; no pointers are retained.
#[no_mangle]
pub unsafe extern "C" fn rq_hyp_geometry(
    distances: *const f64,
    count: usize,
    depth: f64,
    output: *mut f64,
) -> i32 {
    if count > MAX_STATIONS {
        return 3;
    }
    if count != 0 && (distances.is_null() || output.is_null()) {
        return 1;
    }
    if count == 0 {
        return 0;
    }
    CALLS.fetch_add(1, Ordering::Relaxed);
    std::panic::catch_unwind(|| unsafe {
        let distances = std::slice::from_raw_parts(distances, count);
        let results = std::slice::from_raw_parts_mut(output, count * 3);
        for (&distance, out) in distances.iter().zip(results.chunks_exact_mut(3)) {
            out[0] = distance;
            out[1] = travel(out[0], depth, &tables::P_TIMES);
            out[2] = travel(out[0], depth, &tables::S_TIMES);
        }
        0
    })
    .unwrap_or(5)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn bounds_tables_and_invalid_buffers() {
        assert_eq!(
            tables::P_TIMES.len(),
            tables::DEPTHS.len() * tables::DISTANCES.len()
        );
        assert_eq!(tables::S_TIMES.len(), tables::P_TIMES.len());
        for values in [&tables::DEPTHS[..], &tables::DISTANCES[..]] {
            for &v in values {
                for x in [v - 0.1, v, v + 0.1] {
                    let mut reference = 1;
                    while reference < values.len() - 1 && values[reference] < x {
                        reference += 1;
                    }
                    assert_eq!(upper_bound(values, x), reference);
                }
            }
        }
        assert_eq!(
            unsafe { rq_hyp_geometry(std::ptr::null(), 1, 0., std::ptr::null_mut()) },
            1
        );
        assert_eq!(
            unsafe {
                rq_hyp_geometry(std::ptr::null(), MAX_STATIONS + 1, 0., std::ptr::null_mut())
            },
            3
        );
        assert_eq!(
            unsafe { rq_hyp_geometry(std::ptr::null(), 0, 0., std::ptr::null_mut()) },
            0
        );
        assert_eq!(travel(f64::NAN, 10., &tables::P_TIMES), f64::INFINITY);
    }
}
