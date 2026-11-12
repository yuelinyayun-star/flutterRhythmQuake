//! Reference HYP P/S scenarios, shared by native geometry owners and test input.
//! All iteration and floating-point accumulation orders match the frozen Dart
//! scorer; work vectors belong to one ordered search and are reused per point.
use crate::hyp_geometry::travel_pair;
use std::cmp::Ordering as Compare;
use std::sync::atomic::{AtomicU64, Ordering};

const MAX_STATIONS: usize = 1_048_576;
const WORDS: usize = 16;
pub(crate) const OUTPUT: usize = 3 + 6 * WORDS;
static SESSIONS: AtomicU64 = AtomicU64::new(0);
static CALLS: AtomicU64 = AtomicU64::new(0);

fn max(a: f64, b: f64) -> f64 {
    if a.is_nan() || a > b {
        a
    } else if b.is_nan() || b > a {
        b
    } else if a == 0.0 {
        if a.is_sign_negative() {
            b
        } else {
            a
        }
    } else {
        a
    }
}
fn min(a: f64, b: f64) -> f64 {
    -max(-a, -b)
}
fn compare(a: &f64, b: &f64) -> Compare {
    if a.is_nan() {
        if b.is_nan() {
            Compare::Equal
        } else {
            Compare::Greater
        }
    } else if b.is_nan() {
        Compare::Less
    } else {
        a.total_cmp(b)
    }
}
fn palert_weight(level: i64) -> f64 {
    match level {
        6 => 0.1,
        7 => 0.4,
        8 => 1.6,
        n if n < 6 => 0.0,
        n => min(max(2.0 + (n - 8) as f64 * 0.4, 0.0), 4.0),
    }
}
fn middle_out(count: usize) -> Vec<usize> {
    let middle = (count - 1) / 2;
    let mut out = Vec::with_capacity(count);
    out.push(middle);
    for offset in 1..count {
        if middle + offset < count {
            out.push(middle + offset);
        }
        if offset <= middle {
            out.push(middle - offset);
        }
    }
    out
}
fn anchor(
    weights: &[f64],
    preferred: usize,
    center: usize,
    forward: bool,
    used: Option<usize>,
) -> Option<usize> {
    let count = weights.len();
    let mut seen = vec![false; count];
    let mut order = Vec::with_capacity(count);
    let mut add = |index: usize| {
        if !seen[index] {
            seen[index] = true;
            order.push(index);
        }
    };
    if forward {
        for i in preferred..=center {
            add(i);
        }
    } else {
        for i in (center..=preferred).rev() {
            add(i);
        }
    }
    for offset in 1..count {
        if offset <= preferred {
            add(preferred - offset);
        }
        if preferred + offset < count {
            add(preferred + offset);
        }
    }
    order
        .into_iter()
        .find(|&i| Some(i) != used && weights[i] > 0.0)
}
fn origin(p: &[f64], s: &[f64], waves: &[i8], index: usize) -> f64 {
    if waves[index] == 1 {
        s[index]
    } else {
        p[index]
    }
}
fn center(
    weights: &[f64],
    p: &[f64],
    s: &[f64],
    waves: &[i8],
    indexes: impl Iterator<Item = usize>,
) -> Option<f64> {
    let (mut sum, mut weight_sum) = (0.0, 0.0);
    for i in indexes {
        if waves[i] < 0 || weights[i] <= 0.0 {
            continue;
        }
        sum += origin(p, s, waves, i) * weights[i];
        weight_sum += weights[i];
    }
    if weight_sum > 0.0 {
        Some(sum / weight_sum)
    } else {
        None
    }
}
struct Scenario {
    waves: Vec<i8>,
    indexes: Vec<usize>,
    values: [f64; WORDS],
}
impl Scenario {
    fn new(count: usize) -> Self {
        Self {
            waves: vec![-1; count],
            indexes: Vec::with_capacity(count),
            values: [0.0; WORDS],
        }
    }
    fn reset(&mut self) {
        self.waves.fill(-1);
        self.indexes.clear();
        self.values.fill(0.0);
    }
}
pub(crate) struct Scorer {
    pub(crate) coordinates: Option<std::sync::Arc<crate::hyp_search::Coordinates>>,
    pub(crate) coordinate_distances: Vec<f64>,
    pub(crate) count: usize,
    pub(crate) inactive_count: usize,
    pub(crate) search_log: Vec<[f64; 32]>,
    palert: bool,
    weights: Vec<f64>,
    observed: Vec<f64>,
    reference_indexes: Vec<usize>,
    prior: [Vec<i8>; 2],
    middle: Vec<usize>,
    anchors: Option<(usize, usize)>,
    p: Vec<f64>,
    s: Vec<f64>,
    reference_distances: Vec<f64>,
    inactive_distances: Vec<f64>,
    outliers: Vec<bool>,
    scenarios: [Scenario; 6],
}
impl Scorer {
    pub(crate) fn new(info: &[i64], observed: &[f64], inactive_count: usize) -> Self {
        let count = observed.len();
        let palert = info.chunks_exact(8).any(|r| r[3] != 0);
        let mut weights = Vec::with_capacity(count);
        let mut reference_indexes = Vec::new();
        let mut prior = [Vec::with_capacity(count), Vec::with_capacity(count)];
        for (i, r) in info.chunks_exact(8).enumerate() {
            let density = 1.0 / (r[0].max(1) as f64).sqrt();
            let ratio = (i + 1) as f64 / count.max(100) as f64;
            let rank = if ratio <= 0.2 {
                1.0
            } else if ratio <= 0.4 {
                1.5 - ratio * 2.5
            } else if ratio <= 0.8 {
                0.9 - ratio
            } else {
                0.1
            };
            let ascend = if r[3] != 0 {
                palert_weight(r[4])
            } else if r[1] >= 4 {
                min(0.2 * r[1] as f64, 2.0)
            } else if r[1] >= 3 {
                0.3
            } else if r[1] >= 2 {
                0.1
            } else {
                0.0
            };
            weights.push(density * rank * ascend);
            if if palert {
                r[5] >= 9
            } else {
                r[1] >= 3 && r[2] >= 4
            } {
                reference_indexes.push(i);
            }
            for side in 0..2 {
                prior[side].push(r[6 + side] as i8);
            }
        }
        let last = count - 1;
        let first = anchor(
            &weights,
            (last as f64 * 0.25).ceil() as usize,
            (last as f64 * 0.75).floor() as usize,
            true,
            None,
        );
        let anchors = first.and_then(|first| {
            anchor(
                &weights,
                (last as f64 * 0.75).floor() as usize,
                (last as f64 * 0.25).ceil() as usize,
                false,
                Some(first),
            )
            .map(|last| (first, last))
        });
        Self {
            coordinates: None,
            coordinate_distances: Vec::new(),
            count,
            inactive_count,
            palert,
            weights,
            observed: observed.to_vec(),
            reference_indexes,
            prior,
            middle: middle_out(count),
            anchors,
            p: vec![0.0; count],
            s: vec![0.0; count],
            reference_distances: Vec::with_capacity(count),
            inactive_distances: Vec::with_capacity(inactive_count),
            outliers: vec![false; count],
            scenarios: std::array::from_fn(|_| Scenario::new(count)),
            search_log: Vec::new(),
        }
    }
    fn infer(&mut self, slot: usize, inherited: bool) -> bool {
        let scenario = &mut self.scenarios[slot];
        let side = slot / 3;
        let mut selected_filter: Option<(usize, f64, f64)> = None;
        let mut bias = 2.0;
        let mut filter_level = 0;
        if inherited {
            for i in 0..self.count {
                scenario.waves[i] = if self.weights[i] > 0.0 {
                    self.prior[side][i]
                } else {
                    -1
                };
            }
            for &i in &self.middle {
                if scenario.waves[i] >= 0 {
                    scenario.indexes.push(i);
                }
            }
            let Some(initial) = center(
                &self.weights,
                &self.p,
                &self.s,
                &scenario.waves,
                0..self.count,
            ) else {
                return false;
            };
            if scenario.indexes.is_empty() {
                return false;
            }
            let mut sum = 0.0;
            for &i in &scenario.indexes {
                sum += (origin(&self.p, &self.s, &scenario.waves, i) - initial).abs();
            }
            let mean = sum / scenario.indexes.len() as f64;
            let weighted_count = self.weights.iter().filter(|&&w| w > 0.0).count();
            for (level, min_count, remaining_ratio, ratio, min_residual, max_mean, p_bias) in [
                (3, 100, 0.9, 2.0, 3.0, Some(1.5), 1.0),
                (2, 30, 0.8, 2.5, 4.0, Some(2.0), 1.5),
                (1, 10, 0.5, 3.0, 5.0, None, 2.0),
            ] {
                if scenario.indexes.len() < min_count || max_mean.is_some_and(|limit| mean > limit)
                {
                    continue;
                }
                let threshold = max(mean * ratio, min_residual);
                self.outliers.fill(false);
                let mut rejected = 0;
                for &i in &scenario.indexes {
                    if i > 0
                        && (origin(&self.p, &self.s, &scenario.waves, i) - initial).abs()
                            > threshold
                    {
                        self.outliers[i] = true;
                        rejected += 1;
                    }
                }
                let remaining = scenario.indexes.len() - rejected;
                if remaining < min_count
                    || (remaining as f64) < weighted_count as f64 * remaining_ratio
                {
                    continue;
                }
                for &i in &scenario.indexes {
                    if self.outliers[i] {
                        scenario.waves[i] = -1;
                    }
                }
                scenario.indexes.retain(|&i| !self.outliers[i]);
                filter_level = level;
                bias = p_bias;
                selected_filter = Some((min_count, ratio, min_residual));
                break;
            }
        } else {
            let Some((first, last)) = self.anchors else {
                return false;
            };
            scenario.waves[first] = side as i8;
            scenario.waves[last] = (slot % 3) as i8;
            scenario.indexes.push(first);
            scenario.indexes.push(last);
        }
        for &i in &self.middle {
            if scenario.waves[i] >= 0 {
                continue;
            }
            if inherited && self.weights[i] <= 0.0 {
                continue;
            }
            let value = center(
                &self.weights,
                &self.p,
                &self.s,
                &scenario.waves,
                scenario.indexes.iter().copied(),
            );
            let Some(value) = value else {
                if inherited {
                    return false;
                } else {
                    continue;
                }
            };
            if self.weights[i] <= 0.0 {
                continue;
            }
            let pd = (self.p[i] - value).abs();
            let sd = (self.s[i] - value).abs();
            let filter = if inherited {
                selected_filter
            } else {
                Some((30, 3.0, 5.0))
            };
            if let Some((min_count, ratio, min_residual)) = filter {
                if scenario.indexes.len() >= min_count {
                    let mut sum = 0.0;
                    for &j in &scenario.indexes {
                        sum += (origin(&self.p, &self.s, &scenario.waves, j) - value).abs();
                    }
                    let threshold = max(sum / scenario.indexes.len() as f64 * ratio, min_residual);
                    if pd > threshold && sd > threshold {
                        continue;
                    }
                }
            }
            scenario.waves[i] = if pd <= sd * bias { 0 } else { 1 };
            scenario.indexes.push(i);
        }
        scenario.values[15] = filter_level as f64;
        true
    }
    fn score(&mut self, slot: usize, reference: Option<f64>, penalized: usize) {
        let v = &mut self.scenarios[slot];
        let Some(origin_seconds) = center(
            &self.weights,
            &self.p,
            &self.s,
            &v.waves,
            v.indexes.iter().copied(),
        ) else {
            return;
        };
        let (mut weight_sum, mut squares) = (0.0, 0.0);
        for &i in &v.indexes {
            let residual = origin(&self.p, &self.s, &v.waves, i) - origin_seconds;
            weight_sum += self.weights[i];
            squares += self.weights[i] * residual * residual;
        }
        let (mut pc, mut sc, mut lc, mut oc) = (0, 0, 0, 0);
        for i in 0..self.count {
            match v.waves[i] {
                -1 => {
                    if self.weights[i] <= 0.0 {
                        lc += 1;
                    } else {
                        oc += 1;
                    }
                }
                1 => sc += 1,
                _ => pc += 1,
            }
        }
        let count = pc + sc;
        if weight_sum <= 0.0 || count == 0 {
            return;
        }
        let mut penalty = 0.0;
        if let Some(reference) = reference {
            if self.inactive_distances.len() > count && self.inactive_distances[count] <= reference
            {
                return;
            }
            penalty = penalized as f64 / count as f64;
        }
        let rmse = (squares / weight_sum).sqrt();
        let inactive_weight = if count >= 50 {
            0.0
        } else {
            (if self.palert { 8.0 } else { 10.0 }) * (1.0 - count as f64 / 50.0)
        };
        let multiplier = if self.palert {
            1.0 + min(
                max(
                    0.5 * (sc as f64 / pc.max(1) as f64 - (8.0 + v.values[15])),
                    0.0,
                ),
                2.0 - 0.5 * v.values[15],
            )
        } else {
            min(max(sc as f64 / pc.max(1) as f64 - 2.0, 1.0), 3.0)
        };
        let score = (rmse + penalty * inactive_weight) * multiplier;
        let quality = 3.8 + (count as f64 / 10.0).sqrt() * 0.2 - score * 5.0 / 3.0;
        v.values[..15].copy_from_slice(&[
            1.0,
            origin_seconds,
            score,
            rmse,
            weight_sum,
            squares,
            penalty,
            inactive_weight,
            multiplier,
            count as f64,
            quality,
            pc as f64,
            sc as f64,
            lc as f64,
            oc as f64,
        ]);
    }
    pub(crate) fn evaluate(
        &mut self,
        distances: &[f64],
        depth: f64,
        output: &mut [f64],
        waves: &mut [i8],
    ) {
        for i in 0..self.count {
            let (p, s) = travel_pair(distances[i], depth);
            self.p[i] = self.observed[i] - p;
            self.s[i] = self.observed[i] - s;
        }
        self.reference_distances.clear();
        for &i in &self.reference_indexes {
            self.reference_distances.push(distances[i]);
        }
        self.reference_distances.sort_by(compare);
        let reference = if self.reference_distances.is_empty() {
            None
        } else {
            let index = (self.reference_distances.len() as f64
                * (if self.palert { 0.8 } else { 0.9 }))
            .floor() as usize;
            Some(self.reference_distances[index.saturating_sub(1)])
        };
        self.inactive_distances.clear();
        if reference.is_some() {
            self.inactive_distances
                .extend_from_slice(&distances[self.count..]);
            self.inactive_distances.sort_by(compare);
        }
        let penalized = reference.map_or(0, |r| {
            self.inactive_distances
                .iter()
                .take_while(|&&d| d <= r)
                .count()
        });
        let mut best = [None; 2];
        for slot in 0..6 {
            self.scenarios[slot].reset();
            if !self.infer(slot, slot % 3 == 2) {
                continue;
            }
            self.score(slot, reference, penalized);
            if self.scenarios[slot].values[0] == 0.0 {
                continue;
            }
            let side = slot / 3;
            if best[side].is_none_or(|old: usize| {
                self.scenarios[slot].values[2] < self.scenarios[old].values[2]
            }) {
                best[side] = Some(slot);
            }
        }
        let selected = match (best[0], best[1]) {
            (Some(p), Some(s)) => Some(
                if self.scenarios[s].values[2] < self.scenarios[p].values[2] {
                    s
                } else {
                    p
                },
            ),
            (p, s) => p.or(s),
        };
        output[0] = selected.map_or(-1.0, |i| i as f64);
        for side in 0..2 {
            output[1 + side] = best[side].map_or(-1.0, |i| i as f64);
            let target = &mut waves[side * self.count..(side + 1) * self.count];
            if let Some(i) = best[side] {
                target.copy_from_slice(&self.scenarios[i].waves);
            } else {
                target.fill(-1);
            }
        }
        for slot in 0..6 {
            output[3 + slot * WORDS..3 + (slot + 1) * WORDS]
                .copy_from_slice(&self.scenarios[slot].values);
        }
        CALLS.fetch_add(1, Ordering::Relaxed);
    }
}
#[no_mangle]
pub extern "C" fn rq_hyp_score_abi_version() -> u32 {
    1
}
#[no_mangle]
pub extern "C" fn rq_hyp_score_sessions() -> u64 {
    SESSIONS.load(Ordering::Relaxed)
}
#[no_mangle]
pub extern "C" fn rq_hyp_score_calls() -> u64 {
    CALLS.load(Ordering::Relaxed)
}
/// # Safety
/// Caller owns count*8 info words and count observed seconds. Both are copied.
#[no_mangle]
pub unsafe extern "C" fn rq_hyp_score_create(
    info: *const i64,
    observed: *const f64,
    count: usize,
    inactive_count: usize,
) -> *mut std::ffi::c_void {
    if count < 5
        || count > MAX_STATIONS
        || inactive_count > MAX_STATIONS
        || info.is_null()
        || observed.is_null()
    {
        return std::ptr::null_mut();
    }
    std::panic::catch_unwind(|| unsafe {
        let info = std::slice::from_raw_parts(info, count * 8);
        if info
            .chunks_exact(8)
            .any(|r| r[6] < -1 || r[6] > 1 || r[7] < -1 || r[7] > 1)
        {
            return std::ptr::null_mut();
        }
        let session = Scorer::new(
            info,
            std::slice::from_raw_parts(observed, count),
            inactive_count,
        );
        SESSIONS.fetch_add(1, Ordering::Relaxed);
        Box::into_raw(Box::new(session)).cast()
    })
    .unwrap_or(std::ptr::null_mut())
}
/// # Safety
/// Live handle and count+inactive_count distances, output[99], waves[2*count].
/// Caller buffers must not overlap; no pointers are retained.
#[no_mangle]
pub unsafe extern "C" fn rq_hyp_score_evaluate(
    handle: *mut std::ffi::c_void,
    distances: *const f64,
    depth: f64,
    output: *mut f64,
    waves: *mut i8,
) -> i32 {
    if handle.is_null() || distances.is_null() || output.is_null() || waves.is_null() {
        return 1;
    }
    std::panic::catch_unwind(|| unsafe {
        let session = &mut *handle.cast::<Scorer>();
        session.evaluate(
            std::slice::from_raw_parts(distances, session.count + session.inactive_count),
            depth,
            std::slice::from_raw_parts_mut(output, OUTPUT),
            std::slice::from_raw_parts_mut(waves, session.count * 2),
        );
        0
    })
    .unwrap_or(5)
}
/// # Safety
/// Handle returned by create, destroyed exactly once.
#[no_mangle]
pub unsafe extern "C" fn rq_hyp_score_destroy(handle: *mut std::ffi::c_void) {
    if !handle.is_null() {
        unsafe {
            drop(Box::from_raw(handle.cast::<Scorer>()));
        }
        SESSIONS.fetch_sub(1, Ordering::Relaxed);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn buffer_validation_reuse_and_release() {
        assert_eq!(OUTPUT, 99);
        assert!(unsafe { rq_hyp_score_create(std::ptr::null(), std::ptr::null(), 5, 0) }.is_null());
        assert!(unsafe {
            rq_hyp_score_create(std::ptr::null(), std::ptr::null(), MAX_STATIONS + 1, 0)
        }
        .is_null());
        assert_eq!(
            unsafe {
                rq_hyp_score_evaluate(
                    std::ptr::null_mut(),
                    std::ptr::null(),
                    0.0,
                    std::ptr::null_mut(),
                    std::ptr::null_mut(),
                )
            },
            1
        );
        let mut info = vec![0; 5 * 8];
        for row in info.chunks_exact_mut(8) {
            row[1] = 4;
            row[2] = 12;
            row[6] = -1;
            row[7] = -1;
        }
        let observed = [0.0; 5];
        unsafe {
            let handle = rq_hyp_score_create(info.as_ptr(), observed.as_ptr(), 5, 0);
            assert!(!handle.is_null());
            let mut output = [0.0; OUTPUT];
            let mut waves = [-1; 10];
            let distances = [5.0; 5];
            assert_eq!(
                rq_hyp_score_evaluate(
                    handle,
                    distances.as_ptr(),
                    10.0,
                    output.as_mut_ptr(),
                    waves.as_mut_ptr()
                ),
                0
            );
            assert!(output[0] >= 0.0);
            let expected: Vec<_> = output.iter().map(|v| v.to_bits()).collect();
            let expected_waves = waves;
            for _ in 0..10 {
                assert_eq!(
                    rq_hyp_score_evaluate(
                        handle,
                        distances.as_ptr(),
                        10.0,
                        output.as_mut_ptr(),
                        waves.as_mut_ptr()
                    ),
                    0
                );
                assert_eq!(
                    output.iter().map(|v| v.to_bits()).collect::<Vec<_>>(),
                    expected
                );
                assert_eq!(waves, expected_waves);
            }
            rq_hyp_score_destroy(handle);
            rq_hyp_score_destroy(std::ptr::null_mut());
        }
        info[6] = 2;
        assert!(unsafe { rq_hyp_score_create(info.as_ptr(), observed.as_ptr(), 5, 0) }.is_null());
        assert_eq!(middle_out(6), vec![2, 3, 1, 4, 0, 5]);
        assert!(max(f64::NAN, 5.0).is_nan());
        assert_eq!(compare(&f64::NAN, &1.0), Compare::Greater);
        assert_eq!(compare(&-0.0, &0.0), Compare::Less);
    }
}
