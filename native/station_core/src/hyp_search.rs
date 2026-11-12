//! Ordered reference four-stage search. Exact geodesic distances are provided
//! by the native owner. The callback entry is retained for reference tests.
use crate::hyp_score::{Scorer, OUTPUT};
use std::ffi::c_void;
use std::sync::atomic::{AtomicU64, Ordering};

static SEARCHES: AtomicU64 = AtomicU64::new(0);
static DISTANCE_CALLS: AtomicU64 = AtomicU64::new(0);
static DISTANCE_HITS: AtomicU64 = AtomicU64::new(0);
type Distance = unsafe extern "C" fn(f64, f64, *mut f64, usize) -> i32;
#[derive(Clone, Copy)]
enum DistanceSource<'a> {
    Callback(Distance),
    Coordinates(&'a Coordinates),
}
pub(crate) struct Coordinates {
    rows: Vec<[f64; 3]>,
}
impl Coordinates {
    fn new(values: &[f64]) -> Self {
        Self {
            rows: values
                .chunks_exact(2)
                .map(|xy| [xy[0], xy[1], (xy[0] * std::f64::consts::PI / 180.0).cos()])
                .collect(),
        }
    }
    fn write(&self, lat: f64, lng: f64, output: &mut [f64]) {
        let radians = |v: f64| v * std::f64::consts::PI / 180.0;
        let cosine = radians(lat).cos();
        for (xy, out) in self.rows.iter().zip(output) {
            let x = (radians(xy[0] - lat) / 2.0).sin();
            let y = (radians(xy[1] - lng) / 2.0).sin();
            let a = x * x + cosine * xy[2] * (y * y);
            *out = 6371.0088 * (2.0 * a.sqrt().atan2((1.0 - a).sqrt()));
        }
    }
}
const STEPS: [(f64, f64); 4] = [(3.0, 100.0), (1.0, 50.0), (0.3, 20.0), (0.1, 10.0)];
const ROW: usize = 32;
const JOINT_OFFSETS: [(i32, i32, i32); 20] = [
    (-1, -1, -1),
    (-1, -1, 0),
    (-1, -1, 1),
    (-1, 0, -1),
    (-1, 0, 1),
    (-1, 1, -1),
    (-1, 1, 0),
    (-1, 1, 1),
    (0, -1, -1),
    (0, -1, 1),
    (0, 1, -1),
    (0, 1, 1),
    (1, -1, -1),
    (1, -1, 0),
    (1, -1, 1),
    (1, 0, -1),
    (1, 0, 1),
    (1, 1, -1),
    (1, 1, 0),
    (1, 1, 1),
];

#[derive(Clone, Copy)]
struct SearchOptions {
    final_joint: bool,
    final_joint_min_count: usize,
    final_joint_max_score: f64,
}
impl Default for SearchOptions {
    fn default() -> Self {
        Self {
            final_joint: false,
            final_joint_min_count: usize::MAX,
            final_joint_max_score: f64::INFINITY,
        }
    }
}

fn candidate_point(current: [f64; 3], direction: usize, degree: f64, depth: f64) -> [f64; 3] {
    match direction {
        0 => [current[0] + 0.0, current[1] + degree, current[2]],
        1 => [current[0] - degree, current[1] + 0.0, current[2]],
        2 => [current[0] + 0.0, current[1] - degree, current[2]],
        3 => [current[0] + degree, current[1] + 0.0, current[2]],
        4 => [current[0], current[1], current[2] - depth],
        5 => [current[0], current[1], current[2] + depth],
        _ => {
            let (lat, lng, dep) = JOINT_OFFSETS[direction - 6];
            [
                current[0] + lat as f64 * degree,
                current[1] + lng as f64 * degree,
                current[2] + dep as f64 * depth,
            ]
        }
    }
}

// Fixed eight-point FIFO, scoped to this search. Keys are original Float64
// bits, with no coordinate rounding. Reuse the evicted numeric buffer.
struct DistanceCache {
    entries: Vec<((u64, u64), Vec<f64>)>,
    next: usize,
    count: usize,
    calls: u64,
    hits: u64,
}
impl DistanceCache {
    fn new(count: usize) -> Self {
        Self {
            entries: Vec::with_capacity(8),
            next: 0,
            count,
            calls: 0,
            hits: 0,
        }
    }
    unsafe fn get(&mut self, point: [f64; 3], source: DistanceSource<'_>) -> Result<&[f64], i32> {
        let key = (point[0].to_bits(), point[1].to_bits());
        if let Some(index) = self.entries.iter().position(|entry| entry.0 == key) {
            self.hits += 1;
            return Ok(&self.entries[index].1);
        }
        let index = if self.entries.len() < 8 {
            self.entries.push((key, vec![0.0; self.count]));
            self.entries.len() - 1
        } else {
            let index = self.next;
            self.next = (self.next + 1) % 8;
            self.entries[index].0 = key;
            index
        };
        let data = &mut self.entries[index].1;
        let status = match source {
            DistanceSource::Callback(callback) => unsafe {
                callback(point[0], point[1], data.as_mut_ptr(), data.len())
            },
            DistanceSource::Coordinates(coordinates) => {
                coordinates.write(point[0], point[1], data);
                0
            }
        };
        if status != 0 {
            return Err(6);
        }
        self.calls += 1;
        Ok(data)
    }
}

struct Candidate {
    point: [f64; 3],
    values: [f64; OUTPUT],
    waves: Vec<i8>,
}
impl Candidate {
    fn new(count: usize) -> Self {
        Self {
            point: [0.0; 3],
            values: [0.0; OUTPUT],
            waves: vec![-1; count * 2],
        }
    }
    fn summary(&self) -> [f64; 10] {
        let mut out = [0.0; 10];
        out[..3].copy_from_slice(&self.point);
        let selected = self.values[0];
        if selected >= 0.0 {
            let v = &self.values[3 + selected as usize * 16..];
            out[3] = v[2]; // score == error level
            out[4] = v[5]; // residual squares
            out[5] = v[4]; // weight sum
            out[6] = v[6]; // inactive penalty
            out[8] = 1.0; // station scale
            out[9] = v[8]; // wave multiplier
        } else {
            let rejected = if selected == -2.0 {
                f64::INFINITY
            } else {
                1e12
            };
            out[3] = rejected;
            out[4] = rejected;
            out[6] = if selected == -2.0 { 0.0 } else { rejected };
            out[8] = if selected == -2.0 { f64::INFINITY } else { 1.0 };
            out[9] = 1.0;
        }
        out
    }
    fn copy_from(&mut self, other: &Self) {
        self.point = other.point;
        self.values = other.values;
        self.waves.copy_from_slice(&other.waves);
    }
}
// Preserve original rejection precedence. Reference longitude is unbounded.
fn reject([latitude, longitude, depth]: [f64; 3]) -> usize {
    if !depth.is_finite() {
        1
    } else if depth < 0.0 {
        2
    } else if depth > 700.0 {
        3
    } else if !longitude.is_finite() || !latitude.is_finite() {
        4
    } else if !(-90.0..=90.0).contains(&latitude) {
        5
    } else {
        0
    }
}
unsafe fn evaluate(
    scorer: &mut Scorer,
    candidate: &mut Candidate,
    cache: &mut DistanceCache,
    callback: DistanceSource<'_>,
) -> Result<(), i32> {
    if reject(candidate.point) != 0 {
        candidate.values.fill(0.0);
        candidate.values[0] = -2.0;
        candidate.waves.fill(-1);
        return Ok(());
    }
    let distances = unsafe { cache.get(candidate.point, callback)? };
    scorer.evaluate(
        distances,
        candidate.point[2],
        &mut candidate.values,
        &mut candidate.waves,
    );
    Ok(())
}
unsafe fn search(
    scorer: &mut Scorer,
    start: [f64; 3],
    callback: DistanceSource<'_>,
    summary: &mut [f64],
    output: &mut [f64],
    waves: &mut [i8],
    capture_log: bool,
    options: SearchOptions,
) -> Result<(), i32> {
    scorer.search_log.clear();
    let mut current = Candidate::new(scorer.count);
    let mut best = Candidate::new(scorer.count);
    let mut candidate = Candidate::new(scorer.count);
    let mut cache = DistanceCache::new(scorer.count + scorer.inactive_count);
    current.point = start;
    unsafe {
        evaluate(scorer, &mut current, &mut cache, callback)?;
    }
    let mut calls = 1;
    let mut total = 0;
    for (step, &(degree, depth)) in STEPS.iter().enumerate() {
        let mut iterations = 0;
        let mut evaluated = 0;
        let mut rejected = [0; 6];
        let mut moves: Vec<[f64; ROW]> = Vec::new();
        let mut move_count = 0;
        while total < 1000 {
            total += 1;
            iterations += 1;
            let mut best_direction = None;
            let mut terminal = [[0.0; ROW]; 6];
            let joint_enabled = options.final_joint
                && step == STEPS.len() - 1
                && scorer.count >= options.final_joint_min_count
                && current.summary()[3] <= options.final_joint_max_score;
            let direction_count = if joint_enabled { 26 } else { 6 };
            for direction in 0..direction_count {
                candidate.point = candidate_point(current.point, direction, degree, depth);
                let mut row = if direction < 6 {
                    let row = &mut terminal[direction];
                    row[0] = 2.0;
                    row[1] = step as f64;
                    row[2] = direction as f64;
                    row[3..6].copy_from_slice(&candidate.point);
                    Some(row)
                } else {
                    None
                };
                let reason = reject(candidate.point);
                if let Some(row) = row.as_deref_mut() {
                    row[7] = reason as f64;
                }
                if reason != 0 {
                    rejected[reason] += 1;
                    continue;
                }
                calls += 1;
                evaluated += 1;
                unsafe {
                    evaluate(scorer, &mut candidate, &mut cache, callback)?;
                }
                let values = candidate.summary();
                if let Some(row) = row.as_deref_mut() {
                    row[6] = 1.0;
                    row[8] = values[3];
                    row[9] = values[3];
                    row[10] = values[6];
                }
                if best_direction.is_none() || values[3] < best.summary()[3] {
                    best.copy_from(&candidate);
                    best_direction = Some(direction);
                }
            }
            let improved =
                best_direction.is_some() && best.summary()[3] + 1e-9 < current.summary()[3];
            if improved {
                move_count += 1;
                if capture_log {
                    let mut row = [0.0; ROW];
                    row[..5].copy_from_slice(&[
                        1.0,
                        step as f64,
                        iterations as f64,
                        total as f64,
                        best_direction.unwrap() as f64,
                    ]);
                    row[5..15].copy_from_slice(&current.summary());
                    row[15..25].copy_from_slice(&best.summary());
                    moves.push(row);
                }
                std::mem::swap(&mut current, &mut best);
            }
            if !improved || move_count > 1000 {
                if capture_log {
                    scorer.search_log.extend_from_slice(&moves);
                    let mut row = [0.0; ROW];
                    row[..6].copy_from_slice(&[
                        0.0,
                        step as f64,
                        iterations as f64,
                        total as f64,
                        evaluated as f64,
                        rejected.iter().sum::<usize>() as f64,
                    ]);
                    for i in 1..6 {
                        row[5 + i] = rejected[i] as f64;
                    }
                    row[11] = if improved { 1.0 } else { 0.0 };
                    row[12..22].copy_from_slice(&current.summary());
                    scorer.search_log.push(row);
                    scorer.search_log.extend_from_slice(&terminal);
                }
                break;
            }
        }
    }
    summary[..3].copy_from_slice(&current.point);
    summary[3] = calls as f64;
    output.copy_from_slice(&current.values);
    waves.copy_from_slice(&current.waves);
    SEARCHES.fetch_add(1, Ordering::Relaxed);
    DISTANCE_CALLS.fetch_add(cache.calls, Ordering::Relaxed);
    DISTANCE_HITS.fetch_add(cache.hits, Ordering::Relaxed);
    Ok(())
}
#[no_mangle]
pub extern "C" fn rq_hyp_search_abi_version() -> u32 {
    1
}
#[no_mangle]
pub extern "C" fn rq_hyp_search_calls() -> u64 {
    SEARCHES.load(Ordering::Relaxed)
}
#[no_mangle]
pub extern "C" fn rq_hyp_search_distance_calls() -> u64 {
    DISTANCE_CALLS.load(Ordering::Relaxed)
}
#[no_mangle]
pub extern "C" fn rq_hyp_search_distance_hits() -> u64 {
    DISTANCE_HITS.load(Ordering::Relaxed)
}
/// Native owner entry: geometry, scoring and search stay on the owner thread.
pub(crate) fn search_coordinates(
    scorer: &mut Scorer,
    start: [f64; 3],
    coordinates: &[f64],
) -> Result<([f64; 4], Vec<f64>, Vec<i8>), i32> {
    let mut summary = [0.0; 4];
    let mut output = vec![0.0; OUTPUT];
    let mut waves = vec![-1; scorer.count * 2];
    if coordinates.len() != (scorer.count + scorer.inactive_count) * 2 {
        return Err(1);
    }
    let coordinates = Coordinates::new(coordinates);
    unsafe {
        search(
            scorer,
            start,
            DistanceSource::Coordinates(&coordinates),
            &mut summary,
            &mut output,
            &mut waves,
            false,
            SearchOptions::default(),
        )?;
    }
    Ok((summary, output, waves))
}
pub(crate) fn write_distances(
    latitude: f64,
    longitude: f64,
    coordinates: &[f64],
    output: &mut [f64],
) {
    Coordinates::new(coordinates).write(latitude, longitude, output);
}
#[no_mangle]
pub unsafe extern "C" fn rq_hyp_owner_distances(
    lat: f64,
    lon: f64,
    coordinates: *const f64,
    count: usize,
    output: *mut f64,
) -> u32 {
    if coordinates.is_null() || output.is_null() || count > 1048576 {
        return 1;
    }
    write_distances(
        lat,
        lon,
        unsafe { std::slice::from_raw_parts(coordinates, count * 2) },
        unsafe { std::slice::from_raw_parts_mut(output, count) },
    );
    0
}
/// # Safety
/// The callback is synchronous on this calling thread and owns writing exactly
/// count+inactive_count doubles. It must not reenter/mutate/destroy this scorer.
/// Live handle; start[3], summary[4], output[99], waves[2*count], no overlap.
#[no_mangle]
pub unsafe extern "C" fn rq_hyp_score_geometry_set(
    handle: *mut c_void,
    coordinates: *const f64,
    count: usize,
) -> i32 {
    if handle.is_null() || coordinates.is_null() {
        return 1;
    }
    std::panic::catch_unwind(|| unsafe {
        let scorer = &mut *handle.cast::<Scorer>();
        if count != scorer.count + scorer.inactive_count {
            return 1;
        }
        scorer.coordinates = Some(std::sync::Arc::new(Coordinates::new(
            std::slice::from_raw_parts(coordinates, count * 2),
        )));
        scorer.coordinate_distances.resize(count, 0.0);
        0
    })
    .unwrap_or(5)
}
/// A complete candidate search including geometry. No Dart callback is invoked
/// or retained; all input/output buffers are borrowed for this call only.
#[no_mangle]
pub unsafe extern "C" fn rq_hyp_score_search_owned(
    handle: *mut c_void,
    start: *const f64,
    summary: *mut f64,
    output: *mut f64,
    waves: *mut i8,
) -> i32 {
    if handle.is_null()
        || start.is_null()
        || summary.is_null()
        || output.is_null()
        || waves.is_null()
    {
        return 1;
    }
    std::panic::catch_unwind(|| unsafe {
        let scorer = &mut *handle.cast::<Scorer>();
        let Some(coordinates) = scorer.coordinates.clone() else {
            return 1;
        };
        let start = std::slice::from_raw_parts(start, 3);
        search(
            scorer,
            [start[0], start[1], start[2]],
            DistanceSource::Coordinates(&coordinates),
            std::slice::from_raw_parts_mut(summary, 4),
            std::slice::from_raw_parts_mut(output, OUTPUT),
            std::slice::from_raw_parts_mut(waves, scorer.count * 2),
            true,
            SearchOptions::default(),
        )
        .map_or_else(|code| code, |()| 0)
    })
    .unwrap_or(5)
}
#[no_mangle]
pub unsafe extern "C" fn rq_hyp_score_search_owned_options(
    handle: *mut c_void,
    start: *const f64,
    final_joint: u32,
    final_joint_min_count: usize,
    final_joint_max_score: f64,
    summary: *mut f64,
    output: *mut f64,
    waves: *mut i8,
) -> i32 {
    if handle.is_null()
        || start.is_null()
        || summary.is_null()
        || output.is_null()
        || waves.is_null()
    {
        return 1;
    }
    std::panic::catch_unwind(|| unsafe {
        let scorer = &mut *handle.cast::<Scorer>();
        let Some(coordinates) = scorer.coordinates.clone() else {
            return 1;
        };
        let start = std::slice::from_raw_parts(start, 3);
        let options = SearchOptions {
            final_joint: final_joint != 0,
            final_joint_min_count,
            final_joint_max_score,
        };
        search(
            scorer,
            [start[0], start[1], start[2]],
            DistanceSource::Coordinates(&coordinates),
            std::slice::from_raw_parts_mut(summary, 4),
            std::slice::from_raw_parts_mut(output, OUTPUT),
            std::slice::from_raw_parts_mut(waves, scorer.count * 2),
            true,
            options,
        )
        .map_or_else(|code| code, |()| 0)
    })
    .unwrap_or(5)
}
#[no_mangle]
pub unsafe extern "C" fn rq_hyp_score_evaluate_owned(
    handle: *mut c_void,
    lat: f64,
    lng: f64,
    depth: f64,
    output: *mut f64,
    waves: *mut i8,
) -> i32 {
    if handle.is_null() || output.is_null() || waves.is_null() {
        return 1;
    }
    std::panic::catch_unwind(|| unsafe {
        let scorer = &mut *handle.cast::<Scorer>();
        let Some(coordinates) = scorer.coordinates.clone() else {
            return 1;
        };
        let mut distances = std::mem::take(&mut scorer.coordinate_distances);
        coordinates.write(lat, lng, &mut distances);
        scorer.evaluate(
            &distances,
            depth,
            std::slice::from_raw_parts_mut(output, OUTPUT),
            std::slice::from_raw_parts_mut(waves, scorer.count * 2),
        );
        scorer.coordinate_distances = distances;
        0
    })
    .unwrap_or(5)
}
#[no_mangle]
pub unsafe extern "C" fn rq_hyp_score_search(
    handle: *mut c_void,
    start: *const f64,
    callback: Option<Distance>,
    summary: *mut f64,
    output: *mut f64,
    waves: *mut i8,
) -> i32 {
    if handle.is_null()
        || start.is_null()
        || callback.is_none()
        || summary.is_null()
        || output.is_null()
        || waves.is_null()
    {
        return 1;
    }
    std::panic::catch_unwind(|| unsafe {
        let scorer = &mut *handle.cast::<Scorer>();
        let start = std::slice::from_raw_parts(start, 3);
        search(
            scorer,
            [start[0], start[1], start[2]],
            DistanceSource::Callback(callback.unwrap()),
            std::slice::from_raw_parts_mut(summary, 4),
            std::slice::from_raw_parts_mut(output, OUTPUT),
            std::slice::from_raw_parts_mut(waves, scorer.count * 2),
            true,
            SearchOptions::default(),
        )
        .map_or_else(|code| code, |()| 0)
    })
    .unwrap_or(5)
}
#[no_mangle]
pub unsafe extern "C" fn rq_hyp_search_log_words(handle: *const c_void) -> usize {
    if handle.is_null() {
        return 0;
    }
    unsafe { (*handle.cast::<Scorer>()).search_log.len() * ROW }
}
/// # Safety
/// Live handle, output[capacity] aligned, caller owned. Capacity is in doubles.
#[no_mangle]
pub unsafe extern "C" fn rq_hyp_search_log_copy(
    handle: *const c_void,
    output: *mut f64,
    capacity: usize,
) -> i32 {
    if handle.is_null() || output.is_null() {
        return 1;
    }
    unsafe {
        let log = &(*handle.cast::<Scorer>()).search_log;
        if capacity < log.len() * ROW {
            return 3;
        }
        std::ptr::copy_nonoverlapping(log.as_ptr().cast::<f64>(), output, log.len() * ROW);
    }
    0
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::hyp_score::{rq_hyp_score_create, rq_hyp_score_destroy};

    #[test]
    fn owned_geometry_rejects_invalid_setup_without_losing_the_live_session() {
        let mut info = [0i64; 40];
        for row in info.chunks_exact_mut(8) {
            row[1] = 4;
            row[2] = 12;
            row[6] = -1;
            row[7] = -1;
        }
        let observed = [0.0; 5];
        let xy = [35.0, 140.0].repeat(5);
        let start = [35.0, 140.0, 10.0];
        let mut summary = [0.0; 4];
        let mut output = [0.0; OUTPUT];
        let mut waves = [-1; 10];
        unsafe {
            assert_eq!(
                rq_hyp_score_geometry_set(std::ptr::null_mut(), xy.as_ptr(), 5),
                1
            );
            let handle = rq_hyp_score_create(info.as_ptr(), observed.as_ptr(), 5, 0);
            assert!(!handle.is_null());
            assert_eq!(
                rq_hyp_score_search_owned(
                    handle,
                    start.as_ptr(),
                    summary.as_mut_ptr(),
                    output.as_mut_ptr(),
                    waves.as_mut_ptr()
                ),
                1
            );
            assert_eq!(rq_hyp_score_geometry_set(handle, xy.as_ptr(), 4), 1);
            assert_eq!(rq_hyp_score_geometry_set(handle, xy.as_ptr(), 5), 0);
            assert_eq!(
                rq_hyp_score_evaluate_owned(
                    handle,
                    35.0,
                    140.0,
                    10.0,
                    output.as_mut_ptr(),
                    waves.as_mut_ptr()
                ),
                0
            );
            assert_eq!(
                rq_hyp_score_search_owned(
                    handle,
                    start.as_ptr(),
                    summary.as_mut_ptr(),
                    output.as_mut_ptr(),
                    waves.as_mut_ptr()
                ),
                0
            );
            rq_hyp_score_destroy(handle);
        }
    }

    unsafe extern "C" fn distances(_: f64, _: f64, output: *mut f64, count: usize) -> i32 {
        unsafe {
            std::slice::from_raw_parts_mut(output, count).fill(5.0);
        }
        0
    }
    unsafe extern "C" fn failure(_: f64, _: f64, _: *mut f64, _: usize) -> i32 {
        6
    }

    unsafe extern "C" fn exact_coordinates(
        lat: f64,
        lng: f64,
        output: *mut f64,
        count: usize,
    ) -> i32 {
        assert_eq!(count, 2);
        unsafe {
            output.write(lat);
            output.add(1).write(lng);
        }
        0
    }
    #[test]
    fn distance_cache_uses_exact_bits_and_evicts_with_a_fixed_bound() {
        let mut cache = DistanceCache::new(2);
        unsafe {
            assert_eq!(
                cache
                    .get(
                        [-0.0, 1.0, 0.0],
                        DistanceSource::Callback(exact_coordinates)
                    )
                    .unwrap()[0]
                    .to_bits(),
                (-0.0f64).to_bits()
            );
            assert_eq!(
                cache
                    .get(
                        [-0.0, 1.0, 700.0],
                        DistanceSource::Callback(exact_coordinates)
                    )
                    .unwrap()[0]
                    .to_bits(),
                (-0.0f64).to_bits()
            );
            assert_eq!(
                cache
                    .get([0.0, 1.0, 0.0], DistanceSource::Callback(exact_coordinates))
                    .unwrap()[0]
                    .to_bits(),
                0.0f64.to_bits()
            );
            for i in 1..9 {
                assert_eq!(
                    cache
                        .get(
                            [i as f64, 2.0, 10.0],
                            DistanceSource::Callback(exact_coordinates)
                        )
                        .unwrap(),
                    &[i as f64, 2.0]
                );
            }
            assert_eq!(
                cache
                    .get(
                        [-0.0, 1.0, 0.0],
                        DistanceSource::Callback(exact_coordinates)
                    )
                    .unwrap()[0]
                    .to_bits(),
                (-0.0f64).to_bits()
            );
        }
        assert_eq!(cache.entries.len(), 8);
        assert!(cache.entries.iter().all(|entry| entry.1.len() == 2));
        assert_eq!(cache.calls, 11);
        assert_eq!(cache.hits, 1);
    }

    #[test]
    fn ties_bounds_log_capacity_callback_failure_and_reuse() {
        let mut info = [0; 40];
        for row in info.chunks_exact_mut(8) {
            row[6] = -1;
            row[7] = -1;
        }
        let observed = [0.0; 5];
        let start = [0.0, 181.0, 0.0]; // reference does not reject longitude
        let mut summary = [0.0; 4];
        let mut output = [0.0; OUTPUT];
        let mut waves = [-1; 10];
        unsafe {
            assert_eq!(
                rq_hyp_score_search(
                    std::ptr::null_mut(),
                    start.as_ptr(),
                    Some(distances),
                    summary.as_mut_ptr(),
                    output.as_mut_ptr(),
                    waves.as_mut_ptr()
                ),
                1
            );
            let handle = rq_hyp_score_create(info.as_ptr(), observed.as_ptr(), 5, 0);
            assert!(!handle.is_null());
            assert_eq!(
                rq_hyp_score_search(
                    handle,
                    start.as_ptr(),
                    None,
                    summary.as_mut_ptr(),
                    output.as_mut_ptr(),
                    waves.as_mut_ptr()
                ),
                1
            );
            assert_eq!(
                rq_hyp_score_search(
                    handle,
                    start.as_ptr(),
                    Some(distances),
                    summary.as_mut_ptr(),
                    output.as_mut_ptr(),
                    waves.as_mut_ptr()
                ),
                0
            );
            assert_eq!(summary, [0.0, 181.0, 0.0, 21.0]);
            assert_eq!(output[0], -1.0); // zero-weight rejection sentinel
            let words = rq_hyp_search_log_words(handle);
            assert_eq!(words, 28 * ROW);
            let mut log = vec![0.0; words];
            assert_eq!(
                rq_hyp_search_log_copy(handle, log.as_mut_ptr(), words - 1),
                3
            );
            assert_eq!(rq_hyp_search_log_copy(handle, log.as_mut_ptr(), words), 0);
            for step in 0..4 {
                let row = &log[step * 7 * ROW..];
                assert_eq!(row[0], 0.0);
                assert_eq!(row[1], step as f64);
                assert_eq!(row[2], 1.0);
                assert_eq!(row[4], 5.0);
                assert_eq!(row[5], 1.0);
                assert_eq!(row[7], 1.0); // negative-depth rejection
                assert_eq!(row[11], 0.0); // strict tie makes no move
            }
            assert_eq!(
                rq_hyp_score_search(
                    handle,
                    start.as_ptr(),
                    Some(failure),
                    summary.as_mut_ptr(),
                    output.as_mut_ptr(),
                    waves.as_mut_ptr()
                ),
                6
            );
            assert_eq!(rq_hyp_search_log_words(handle), 0);
            assert_eq!(
                rq_hyp_score_search(
                    handle,
                    start.as_ptr(),
                    Some(distances),
                    summary.as_mut_ptr(),
                    output.as_mut_ptr(),
                    waves.as_mut_ptr()
                ),
                0
            );
            let mut repeated = vec![0.0; words];
            assert_eq!(
                rq_hyp_search_log_copy(handle, repeated.as_mut_ptr(), words),
                0
            );
            assert_eq!(repeated, log);
            rq_hyp_score_destroy(handle);
        }
        assert_eq!(reject([91.0, 0.0, -1.0]), 2);
        assert_eq!(reject([91.0, 0.0, 700.1]), 3);
        assert_eq!(reject([90.0, 1000.0, 700.0]), 0);
        assert_eq!(reject([91.0, 0.0, 700.0]), 5);
        assert_eq!(reject([0.0, f64::NAN, 0.0]), 4);
    }
}
