//! P-Alert PGA/PGV thresholds and three-second display history.
//! Original thresholds from kanameishi 8748cf7 (AGPL-3.0), as in Dart.
use std::{
    collections::VecDeque,
    ffi::c_void,
    sync::atomic::{AtomicU64, Ordering},
};

static SESSIONS: AtomicU64 = AtomicU64::new(0);
static CALLS: AtomicU64 = AtomicU64::new(0);
type History = VecDeque<(i64, i32)>;
#[derive(Default)]
pub(crate) struct Levels {
    stations: Vec<History>,
}

pub(crate) fn level(pga: f64, pgv: f64) -> i32 {
    if !pga.is_finite() || pga < 0.0 {
        return -1;
    }
    if pga < 80.0 {
        [
            0.1, 0.14, 0.18, 0.25, 0.33, 0.44, 0.59, 0.8, 1.4, 2.5, 4.4, 8.0, 14.0, 25.0, 44.0,
        ]
        .iter()
        .filter(|&&threshold| pga >= threshold)
        .count() as i32
    } else if !pgv.is_finite() || pgv < 0.0 {
        15
    } else {
        15 + [15.0, 30.0, 50.0, 80.0, 140.0]
            .iter()
            .filter(|&&v| pgv >= v)
            .count() as i32
    }
}

impl Levels {
    pub(crate) fn configure(&mut self, remap: &[i32]) -> Result<(), i32> {
        // Validate before moving any station history; a failed call is atomic.
        let mut used = vec![false; self.stations.len()];
        for &index in remap {
            if index < -1 || index >= self.stations.len() as i32 {
                return Err(2);
            }
            if index >= 0 {
                if used[index as usize] {
                    return Err(2);
                }
                used[index as usize] = true;
            }
        }
        self.stations = remap
            .iter()
            .map(|&index| {
                if index < 0 {
                    History::new()
                } else {
                    std::mem::take(&mut self.stations[index as usize])
                }
            })
            .collect();
        Ok(())
    }

    pub(crate) fn process(&mut self, time: i64, input: &[f64], output: &mut [i32]) {
        let cutoff = time.saturating_sub(3_000_000);
        for ((history, row), out) in self
            .stations
            .iter_mut()
            .zip(input.chunks_exact(3))
            .zip(output.chunks_exact_mut(2))
        {
            out.fill(-1);
            // Missing PGA must not age or otherwise update this station's history.
            if row[0] == 0.0 {
                continue;
            }
            let current = level(row[1], row[2]);
            history.retain(|&(stamp, _)| stamp >= cutoff && stamp <= time);
            if current >= 0 {
                history.push_back((time, current));
            }
            out[0] = current;
            out[1] = history
                .iter()
                .map(|&(_, value)| value)
                .max()
                .unwrap_or(current);
        }
    }
}

#[no_mangle]
pub extern "C" fn rq_palert_levels_abi_version() -> u32 {
    1
}
#[no_mangle]
pub extern "C" fn rq_palert_levels_sessions() -> u64 {
    SESSIONS.load(Ordering::Relaxed)
}
#[no_mangle]
pub extern "C" fn rq_palert_levels_calls() -> u64 {
    CALLS.load(Ordering::Relaxed)
}
#[no_mangle]
pub extern "C" fn rq_palert_levels_create() -> *mut c_void {
    let pointer = Box::into_raw(Box::new(Levels::default())).cast();
    SESSIONS.fetch_add(1, Ordering::Relaxed);
    pointer
}
#[no_mangle]
pub unsafe extern "C" fn rq_palert_levels_configure(
    owner: *mut c_void,
    remap: *const i32,
    count: usize,
) -> i32 {
    if owner.is_null() || remap.is_null() {
        return 1;
    }
    if count > 1_000_000 {
        return 3;
    }
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        unsafe { &mut *owner.cast::<Levels>() }
            .configure(unsafe { std::slice::from_raw_parts(remap, count) })
    }))
    .map_or(5, |result| result.err().unwrap_or(0))
}
#[no_mangle]
pub unsafe extern "C" fn rq_palert_levels_process(
    owner: *mut c_void,
    time: i64,
    input: *const f64,
    count: usize,
    output: *mut i32,
) -> i32 {
    if owner.is_null() || input.is_null() || output.is_null() {
        return 1;
    }
    if count > 1_000_000 {
        return 3;
    }
    let state = unsafe { &mut *owner.cast::<Levels>() };
    if count != state.stations.len() {
        return 2;
    }
    CALLS.fetch_add(1, Ordering::Relaxed);
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        state.process(
            time,
            unsafe { std::slice::from_raw_parts(input, count * 3) },
            unsafe { std::slice::from_raw_parts_mut(output, count * 2) },
        );
    }))
    .map_or(5, |_| 0)
}
#[no_mangle]
pub unsafe extern "C" fn rq_palert_levels_destroy(owner: *mut c_void) {
    if !owner.is_null() {
        unsafe {
            drop(Box::from_raw(owner.cast::<Levels>()));
        }
        SESSIONS.fetch_sub(1, Ordering::Relaxed);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn thresholds_and_missing_values() {
        assert_eq!(level(f64::NAN, 150.0), -1);
        assert_eq!(level(-0.0, 150.0), 0);
        assert_eq!(level(0.8, 150.0), 8);
        assert_eq!(level(79.999, 150.0), 15);
        assert_eq!(level(80.0, f64::NAN), 15);
        assert_eq!(level(80.0, 15.0), 16);
        assert_eq!(level(80.0, 140.0), 20);
    }
    #[test]
    fn inclusive_cutoff_missing_invalid_and_remap() {
        let mut state = Levels::default();
        state.configure(&[-1, -1]).unwrap();
        let mut out = [0; 4];
        state.process(0, &[1.0, 80.0, 140.0, 1.0, 0.8, 0.0], &mut out);
        assert_eq!(out, [20, 20, 8, 8]);
        state.process(3_000_000, &[1.0, 0.0, 0.0, 0.0, 0.0, 0.0], &mut out);
        assert_eq!(out, [0, 20, -1, -1]);
        state.configure(&[1, 0]).unwrap();
        state.process(3_000_001, &[1.0, f64::NAN, 0.0, 1.0, 0.0, 0.0], &mut out);
        assert_eq!(out, [-1, -1, 0, 0]);
        assert!(state.configure(&[0, 0]).is_err());
        assert_eq!(state.stations.len(), 2);
    }
}
