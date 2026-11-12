//! Ordered KA spatial detection with native geometry owners and reference input.
use std::collections::{HashMap, VecDeque};
use std::sync::atomic::{AtomicU64, Ordering};

const MAX_STATIONS: usize = 1_048_576;
const MAX_PAIRS_PER_STATION: usize = 30;
static SESSIONS: AtomicU64 = AtomicU64::new(0);
static CALLS: AtomicU64 = AtomicU64::new(0);

pub(crate) struct Detector {
    offsets: Vec<u32>,
    neighbors: Vec<u32>,
    checked: Vec<bool>,
    queued: Vec<bool>,
    pub(crate) active: Vec<u32>,
    pending: VecDeque<u32>,
    abnormal: HashMap<(u32, u32), bool>,
    distances: HashMap<(u32, u32), f64>,
}

fn activity(info: &[i64], index: usize) -> f64 {
    f64::from_bits(info[index * 6 + 1] as u64)
}

impl Detector {
    pub(crate) fn from_topology(adj: &[Vec<usize>], distances: HashMap<(u32, u32), f64>) -> Self {
        let mut offsets = vec![0];
        let mut neighbors = vec![];
        for row in adj {
            neighbors.extend(row.iter().map(|&i| i as u32));
            offsets.push(neighbors.len() as u32);
        }
        Self {
            offsets,
            neighbors,
            checked: vec![false; adj.len()],
            queued: vec![false; adj.len()],
            active: vec![],
            pending: VecDeque::new(),
            abnormal: HashMap::new(),
            distances,
        }
    }
    fn chain(&mut self, start: u32, info: &[i64]) {
        self.pending.push_back(start);
        self.queued[start as usize] = true;
        while let Some(current) = self.pending.pop_front() {
            let index = current as usize;
            self.queued[index] = false;
            self.checked[index] = true;
            // Preserve Dart's <= comparison, including NaN behavior.
            if activity(info, index) <= 0.0 {
                continue;
            }
            self.active.push(current);
            for &neighbor in
                &self.neighbors[self.offsets[index] as usize..self.offsets[index + 1] as usize]
            {
                let next = neighbor as usize;
                if !self.checked[next] && !self.queued[next] {
                    self.pending.push_back(neighbor);
                    self.queued[next] = true;
                }
            }
        }
    }

    fn detect(&mut self, info: &[i64], sensitivity: i64, held: bool) -> Result<i64, ()> {
        self.detect_policy(info, sensitivity, held, true, 0)
    }
    pub(crate) fn detect_policy(
        &mut self,
        info: &[i64],
        sensitivity: i64,
        held: bool,
        shortcut: bool,
        minimum: i64,
    ) -> Result<i64, ()> {
        self.checked.fill(false);
        self.queued.fill(false);
        self.active.clear();
        self.pending.clear();
        self.abnormal.clear();
        for index in 0..self.checked.len() {
            if !(activity(info, index) > 0.0) || self.checked[index] {
                continue;
            }
            if shortcut && info[index * 6 + 3] == 1 && info[index * 6 + 2] > 0 {
                self.chain(index as u32, info);
                continue;
            }
            let mut nearby = [0usize; 6];
            let mut count = 0;
            for &neighbor in
                &self.neighbors[self.offsets[index] as usize..self.offsets[index + 1] as usize]
            {
                let neighbor = neighbor as usize;
                if info[neighbor * 6] > -1 {
                    nearby[count] = neighbor;
                    count += 1;
                }
            }
            if count == 0 {
                continue;
            }
            let mut possible = 0;
            let mut weak = 0;
            for &neighbor in &nearby[..count] {
                if activity(info, neighbor) > 0.0 {
                    possible += 1;
                    if info[neighbor * 6 + 2] <= 1 && info[neighbor * 6 + 3] == 0 {
                        weak += 1;
                    }
                }
            }
            let active_count = possible as f64 - weak as f64 / 2.0;
            let station_threshold = match sensitivity {
                1 => count as f64 / 2.0 + 1.0,
                2 if count <= 2 => (count as f64 + 1.0) / 2.0,
                2 | 3 => count as f64 / 2.0,
                _ => f64::INFINITY,
            };
            if active_count < station_threshold.max(minimum as f64) {
                continue;
            }
            let mut threshold = match sensitivity {
                1 => [f64::INFINITY, 10.0, 14.0, 16.0, 18.0, 19.0, 20.0][count],
                2 => [f64::INFINITY, 8.0, 11.0, 13.0, 14.0, 15.0, 16.0][count],
                3 => [f64::INFINITY, 6.0, 9.0, 11.0, 12.0, 13.0, 14.0][count],
                _ => f64::INFINITY,
            };
            let mut candidates = [0usize; 6];
            let mut candidates_len = 0;
            for &neighbor in &nearby[..count] {
                if info[neighbor * 6 + 3] == 0 && info[neighbor * 6 + 2] > 2 {
                    candidates[candidates_len] = neighbor;
                    candidates_len += 1;
                }
            }
            let mut abnormal_pair = false;
            'pairs: for first in 0..candidates_len {
                for second in first + 1..candidates_len {
                    let a = candidates[first] as u32;
                    let b = candidates[second] as u32;
                    let key = (a.min(b), a.max(b));
                    let abnormal = if let Some(&cached) = self.abnormal.get(&key) {
                        cached
                    } else {
                        let first_stamp = info[a as usize * 6 + 5];
                        let second_stamp = info[b as usize * 6 + 5];
                        // Distances keep the original ordered Dart result, but are
                        // copied once at configuration instead of calling Dart for
                        // every active frame.
                        let Some(&km) = self.distances.get(&(a, b)) else {
                            return Err(());
                        };
                        let value = first_stamp > 0
                            && second_stamp > 0
                            && km.is_finite()
                            && km >= 0.0
                            && km / 3.5 + 2.0 < (first_stamp - second_stamp).abs() as f64 / 1000.0;
                        self.abnormal.insert(key, value);
                        value
                    };
                    if abnormal {
                        abnormal_pair = true;
                        break 'pairs;
                    }
                }
            }
            if abnormal_pair {
                threshold *= 2.0;
            }
            let mut total = active_count * (active_count + 1.0) / 2.0;
            for &neighbor in &nearby[..count] {
                total += activity(info, neighbor);
            }
            if total >= threshold {
                self.chain(index as u32, info);
            }
        }
        let mut strongest = -1;
        if !held {
            for &index in &self.active {
                if strongest < 0 || info[strongest as usize * 6] < info[index as usize * 6] {
                    strongest = index as i64;
                }
            }
        }
        self.active.sort_unstable();
        Ok(strongest)
    }
}

#[no_mangle]
pub extern "C" fn rq_ka_detector_abi_version() -> u32 {
    2
}
#[no_mangle]
pub extern "C" fn rq_ka_detector_sessions() -> u64 {
    SESSIONS.load(Ordering::Relaxed)
}
#[no_mangle]
pub extern "C" fn rq_ka_detector_calls() -> u64 {
    CALLS.load(Ordering::Relaxed)
}

/// # Safety
/// Caller provides count+1 offsets and edge_count indices, without retaining
/// access to the returned handle outside its owning thread/isolate.
#[no_mangle]
pub unsafe extern "C" fn rq_ka_detector_create(
    offsets: *const u32,
    neighbors: *const u32,
    count: usize,
    edge_count: usize,
    pair_first: *const u32,
    pair_second: *const u32,
    pair_distances: *const f64,
    pair_count: usize,
) -> *mut std::ffi::c_void {
    if offsets.is_null()
        || count > MAX_STATIONS
        || edge_count > count * 6
        || (edge_count > 0 && neighbors.is_null())
        || pair_count > count.saturating_mul(MAX_PAIRS_PER_STATION)
        || (pair_count > 0
            && (pair_first.is_null() || pair_second.is_null() || pair_distances.is_null()))
    {
        return std::ptr::null_mut();
    }
    std::panic::catch_unwind(|| unsafe {
        let offsets = std::slice::from_raw_parts(offsets, count + 1);
        let neighbors = if edge_count == 0 {
            &[]
        } else {
            std::slice::from_raw_parts(neighbors, edge_count)
        };
        let pair_first = if pair_count == 0 {
            &[]
        } else {
            std::slice::from_raw_parts(pair_first, pair_count)
        };
        let pair_second = if pair_count == 0 {
            &[]
        } else {
            std::slice::from_raw_parts(pair_second, pair_count)
        };
        let pair_distances = if pair_count == 0 {
            &[]
        } else {
            std::slice::from_raw_parts(pair_distances, pair_count)
        };
        if offsets[0] != 0
            || offsets[count] as usize != edge_count
            || neighbors.iter().any(|&n| n as usize >= count)
            || pair_first.iter().any(|&n| n as usize >= count)
            || pair_second.iter().any(|&n| n as usize >= count)
            || offsets.windows(2).any(|v| v[0] > v[1] || v[1] - v[0] > 6)
        {
            return std::ptr::null_mut();
        }
        let state = Detector {
            offsets: offsets.to_vec(),
            neighbors: neighbors.to_vec(),
            checked: vec![false; count],
            queued: vec![false; count],
            active: Vec::with_capacity(count),
            pending: VecDeque::with_capacity(count),
            abnormal: HashMap::new(),
            distances: pair_first
                .iter()
                .copied()
                .zip(pair_second.iter().copied())
                .zip(pair_distances.iter().copied())
                .map(|((first, second), distance)| ((first, second), distance))
                .collect(),
        };
        let result = Box::into_raw(Box::new(state)).cast();
        SESSIONS.fetch_add(1, Ordering::Relaxed);
        result
    })
    .unwrap_or(std::ptr::null_mut())
}

/// # Safety
/// rows[count*6] contains level, activity bits, ascend, active, shindo bits,
/// trigger milliseconds. output[count], summary[2] do not overlap.
/// Callback is synchronous on this thread and must not reenter/destroy handle.
#[no_mangle]
pub unsafe extern "C" fn rq_ka_detector_create_nied(
    coordinates: *const f64,
    count: usize,
) -> *mut std::ffi::c_void {
    if coordinates.is_null() || count > MAX_STATIONS {
        return std::ptr::null_mut();
    }
    std::panic::catch_unwind(|| unsafe {
        let state = crate::nied_topology::display_detector(std::slice::from_raw_parts(
            coordinates,
            count * 2,
        ));
        let result = Box::into_raw(Box::new(state)).cast();
        SESSIONS.fetch_add(1, Ordering::Relaxed);
        result
    })
    .unwrap_or(std::ptr::null_mut())
}
#[no_mangle]
pub unsafe extern "C" fn rq_ka_detector_process(
    handle: *mut std::ffi::c_void,
    info: *const i64,
    sensitivity: i64,
    held: u8,
    output: *mut u32,
    summary: *mut i64,
) -> i32 {
    if handle.is_null() || info.is_null() || output.is_null() || summary.is_null() {
        return 1;
    }
    std::panic::catch_unwind(|| unsafe {
        let state = &mut *handle.cast::<Detector>();
        let count = state.checked.len();
        let info = std::slice::from_raw_parts(info, count * 6);
        if held > 1 || info.chunks_exact(6).any(|v| v[3] != 0 && v[3] != 1) {
            return 2;
        }
        let strongest = match state.detect(info, sensitivity, held == 1) {
            Ok(value) => value,
            Err(()) => return 4,
        };
        let output = std::slice::from_raw_parts_mut(output, count);
        output[..state.active.len()].copy_from_slice(&state.active);
        *summary = state.active.len() as i64;
        *summary.add(1) = strongest;
        CALLS.fetch_add(1, Ordering::Relaxed);
        0
    })
    .unwrap_or(5)
}

/// # Safety
/// handle was created here, is idle and is destroyed exactly once.
#[no_mangle]
pub unsafe extern "C" fn rq_ka_detector_destroy(handle: *mut std::ffi::c_void) {
    if !handle.is_null() {
        unsafe {
            drop(Box::from_raw(handle.cast::<Detector>()));
        }
        SESSIONS.fetch_sub(1, Ordering::Relaxed);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ordered_chain_and_strongest_tie() {
        let mut state = Detector {
            offsets: vec![0, 2, 4, 6],
            neighbors: vec![0, 2, 1, 0, 2, 1],
            checked: vec![false; 3],
            queued: vec![false; 3],
            active: Vec::new(),
            pending: VecDeque::new(),
            abnormal: HashMap::new(),
            distances: HashMap::from([((0, 1), 0.0), ((1, 2), 0.0)]),
        };
        let mut info = [
            10,
            20.0f64.to_bits() as i64,
            3,
            1,
            0,
            0,
            20,
            20.0f64.to_bits() as i64,
            3,
            1,
            0,
            0,
            20,
            20.0f64.to_bits() as i64,
            3,
            1,
            0,
            0,
        ];
        assert_eq!(state.detect(&info, 2, false), Ok(2));
        assert_eq!(state.active, [0, 1, 2]);
        assert_eq!(state.detect(&info, 2, true), Ok(-1));
        for row in info.chunks_exact_mut(6) {
            row[1] = 0;
        }
        assert_eq!(state.detect(&info, 2, false), Ok(-1));
        assert!(state.active.is_empty());
    }

    #[test]
    fn malformed_topology_is_rejected() {
        assert!(unsafe {
            rq_ka_detector_create(
                [0, 7].as_ptr(),
                [0; 7].as_ptr(),
                1,
                7,
                std::ptr::null(),
                std::ptr::null(),
                std::ptr::null(),
                0,
            )
        }
        .is_null());
        assert!(unsafe {
            rq_ka_detector_create(
                [0, 1].as_ptr(),
                [1].as_ptr(),
                1,
                1,
                std::ptr::null(),
                std::ptr::null(),
                std::ptr::null(),
                0,
            )
        }
        .is_null());
    }
}
