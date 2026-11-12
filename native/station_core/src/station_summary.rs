//! Incremental station-to-sidebar projection. This owner is independent of
//! station inference/recording owners; no observation is coalesced or edited.
use std::{
    cmp::Ordering as Cmp,
    collections::HashMap,
    ffi::c_void,
    sync::atomic::{AtomicU64, Ordering},
};
const LIMIT: usize = 1_000_000;
static SESSIONS: AtomicU64 = AtomicU64::new(0);
static CALLS: AtomicU64 = AtomicU64::new(0);
static ROWS: AtomicU64 = AtomicU64::new(0);
type Row = [f64; 5]; // value, level, active, latitude, longitude
type Text = (Vec<u16>, Vec<u16>); // code, region
struct Summary {
    indices: [i32; 17], // selected six, top count, five indices, five JMA ranks
    nied: Vec<Row>,
    text: Vec<Text>,
    cells: Vec<[f64; 3]>, // latitude, longitude, KA level (original order)
    areas: Vec<(Vec<u16>, i32)>,
    areas_dirty: bool,
}
impl Default for Summary {
    fn default() -> Self {
        let mut indices = [-1; 17];
        indices[6] = 0;
        Self {
            indices,
            nied: vec![],
            text: vec![],
            cells: vec![],
            areas: vec![],
            areas_dirty: false,
        }
    }
}
fn jma(value: f64) -> i32 {
    [0.5, 1.5, 2.5, 3.5, 4.5, 5.0, 5.5, 6.0, 6.5]
        .iter()
        .position(|&n| value < n)
        .unwrap_or(9) as i32
}
fn ka_number(level: i32) -> i32 {
    match level {
        i32::MIN..=-1 => -1,
        0..=7 => 0,
        8..=9 => 1,
        10..=11 => 2,
        12..=13 => 3,
        14..=15 => 4,
        16..=17 => 5,
        18..=19 => 6,
        _ => 7,
    }
}
fn dart_trim(value: &[u16]) -> &[u16] {
    fn space(c: u16) -> bool {
        matches!(c,9..=13|32|0x85|0xa0|0x1680|0x2000..=0x200a|0x2028|0x2029|0x202f|0x205f|0x3000|0xfeff)
    }
    let start = value.iter().position(|&c| !space(c)).unwrap_or(value.len());
    let end = value
        .iter()
        .rposition(|&c| !space(c))
        .map_or(start, |i| i + 1);
    &value[start..end]
}
// Dart double.compareTo orders -0 before +0, and String.compareTo orders UTF-16.
fn double_order(a: f64, b: f64) -> Cmp {
    a.partial_cmp(&b).unwrap_or(Cmp::Equal).then_with(|| {
        if a == 0.0 && b == 0.0 {
            b.is_sign_negative().cmp(&a.is_sign_negative())
        } else {
            Cmp::Equal
        }
    })
}
impl Summary {
    fn update(&mut self, kind: usize, rows: Vec<Row>, text: Vec<Text>) {
        if kind == 0 {
            let targets = [
                "六分街".encode_utf16().collect::<Vec<_>>(),
                "新艾利都".encode_utf16().collect(),
            ];
            self.indices[0] = text
                .iter()
                .position(|(_, region)| {
                    targets
                        .iter()
                        .any(|s| region.windows(s.len()).any(|v| v == s))
                })
                .map_or(-1, |i| i as i32);
        }
        if kind < 5 {
            let (slot, mut maximum) = match kind {
                0 => (1, f64::NEG_INFINITY),
                1 => (2, -1.0),
                2 => (3, -1.0),
                3 => (4, -1.0),
                _ => (5, -1.0),
            };
            self.indices[slot] = -1;
            for (i, row) in rows.iter().enumerate() {
                let value = match kind {
                    2 => {
                        if row[2] != 0.0 {
                            row[1]
                        } else {
                            row[0]
                        }
                    }
                    4 => {
                        if !row[0].is_nan() {
                            row[0]
                        } else if !row[3].is_nan() {
                            row[3]
                        } else {
                            crate::palert_levels::level(row[1], row[2]) as f64
                        }
                    }
                    _ => row[0],
                };
                if kind == 0 && !value.is_finite() {
                    continue;
                }
                if value > maximum {
                    maximum = value;
                    self.indices[slot] = i as i32;
                }
            }
        } else {
            let mut top: Vec<usize> = Vec::with_capacity(5);
            for (i, row) in rows.iter().enumerate() {
                if row[2] == 0.0 || row[1] < 0.0 || !row[0].is_finite() {
                    continue;
                }
                let at = top
                    .iter()
                    .position(|&j| {
                        let order = double_order(row[0], rows[j][0]);
                        order == Cmp::Greater || (order == Cmp::Equal && text[i].0 < text[j].0)
                    })
                    .unwrap_or(top.len());
                if at < 5 {
                    top.insert(at, i);
                    if top.len() > 5 {
                        top.pop();
                    }
                }
            }
            if top.first().is_some_and(|&i| jma(rows[i][0]) <= 0) {
                top.clear();
            }
            self.indices[6] = top.len() as i32;
            self.indices[7..].fill(-1);
            for (i, &index) in top.iter().enumerate() {
                self.indices[7 + i] = index as i32;
                self.indices[12 + i] = jma(rows[index][0]);
            }
        }
        if kind == 1 {
            self.nied = rows;
            if !text.is_empty() || self.nied.is_empty() {
                self.text = text;
            }
            self.areas_dirty = true;
        }
    }
    fn refresh_areas(&mut self) {
        self.areas_dirty = false;
        self.areas.clear();
        if self.cells.is_empty() {
            return;
        }
        let mut buckets: HashMap<(i32, i32), Vec<usize>> = HashMap::new();
        for (i, row) in self.nied.iter().enumerate() {
            if row[2] != 0.0 && row[1] >= 0.0 {
                buckets
                    .entry((row[3].floor() as i32, row[4].floor() as i32))
                    .or_default()
                    .push(i);
            }
        }
        let mut pref: HashMap<Vec<u16>, i32> = HashMap::new();
        for cell in &self.cells {
            let mut names: Vec<&[u16]> = vec![];
            let mut nearby = Vec::new();
            let mut nearest: Option<usize> = None;
            let mut distance = f64::INFINITY;
            let lat = cell[0].floor() as i32;
            let lng = cell[1].floor() as i32;
            for y in lat - 1..=lat + 1 {
                for x in lng - 1..=lng + 1 {
                    for &i in buckets.get(&(y, x)).into_iter().flatten() {
                        nearby.push(i);
                        let row = &self.nied[i];
                        let name = if dart_trim(&self.text[i].1).is_empty() {
                            &self.text[i].0
                        } else {
                            &self.text[i].1
                        };
                        if (row[3] - cell[0]).abs() <= 0.500001
                            && (row[4] - cell[1]).abs() <= 0.500001
                        {
                            names.push(name);
                        }
                    }
                }
            }
            if names.is_empty() {
                for i in nearby {
                    let row = &self.nied[i];
                    let a = (((row[3] - cell[0]) * std::f64::consts::PI / 180.0) / 2.0).sin();
                    let b = (((row[4] - cell[1]) * std::f64::consts::PI / 180.0) / 2.0).sin();
                    let h = a * a
                        + (cell[0] * std::f64::consts::PI / 180.0).cos()
                            * (row[3] * std::f64::consts::PI / 180.0).cos()
                            * b
                            * b;
                    let d = 2.0 * 6371.0 * h.sqrt().atan2((1.0 - h).sqrt());
                    if d < distance {
                        distance = d;
                        nearest = Some(i);
                    }
                }
                if let Some(i) = nearest {
                    names.push(if dart_trim(&self.text[i].1).is_empty() {
                        &self.text[i].0
                    } else {
                        &self.text[i].1
                    });
                }
            }
            let level = ka_number(cell[2] as i32);
            for name in names {
                let name = dart_trim(name);
                if !name.is_empty() {
                    let entry = pref.entry(name.to_vec()).or_insert(-1);
                    if level > *entry {
                        *entry = level;
                    }
                }
            }
        }
        self.areas = pref.into_iter().collect();
        self.areas
            .sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0)));
    }
}
#[no_mangle]
pub extern "C" fn rq_station_summary_abi_version() -> u32 {
    1
}
#[no_mangle]
pub extern "C" fn rq_station_summary_sessions() -> u64 {
    SESSIONS.load(Ordering::Relaxed)
}
#[no_mangle]
pub extern "C" fn rq_station_summary_calls() -> u64 {
    CALLS.load(Ordering::Relaxed)
}
#[no_mangle]
pub extern "C" fn rq_station_summary_rows() -> u64 {
    ROWS.load(Ordering::Relaxed)
}
#[no_mangle]
pub extern "C" fn rq_station_summary_create() -> *mut c_void {
    SESSIONS.fetch_add(1, Ordering::Relaxed);
    Box::into_raw(Box::new(Summary::default())).cast()
}
#[no_mangle]
pub unsafe extern "C" fn rq_station_summary_destroy(owner: *mut c_void) {
    if !owner.is_null() {
        unsafe {
            drop(Box::from_raw(owner.cast::<Summary>()));
        }
        SESSIONS.fetch_sub(1, Ordering::Relaxed);
    }
}
#[no_mangle]
pub unsafe extern "C" fn rq_station_summary_update(
    owner: *mut c_void,
    kind: u32,
    input: *const f64,
    count: usize,
    utf16: *const u16,
    len: usize,
    offsets: *const u32,
) -> i32 {
    if owner.is_null()
        || input.is_null()
        || (offsets.is_null() && (kind == 0 || kind == 5 || len != 0))
        || (!offsets.is_null() && utf16.is_null())
        || kind > 5
        || count > LIMIT
        || len > 16 * 1024 * 1024
    {
        return 1;
    }
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let input = unsafe { std::slice::from_raw_parts(input, count * 5) };
        if kind == 1
            && input.chunks_exact(5).any(|r| {
                !r[3].is_finite() || !r[4].is_finite() || r[3].abs() > 90.0 || r[4].abs() > 180.0
            })
        {
            return Err(2);
        }
        if offsets.is_null() {
            let state = unsafe { &mut *owner.cast::<Summary>() };
            if kind == 1 && count != state.text.len() {
                return Err(2);
            }
            let rows = input
                .chunks_exact(5)
                .map(|r| [r[0], r[1], r[2], r[3], r[4]])
                .collect();
            state.update(kind as usize, rows, vec![]);
            CALLS.fetch_add(1, Ordering::Relaxed);
            ROWS.fetch_add(count as u64, Ordering::Relaxed);
            return Ok(());
        }
        let utf16 = unsafe { std::slice::from_raw_parts(utf16, len) };
        let offsets = unsafe { std::slice::from_raw_parts(offsets, count * 4) };
        let mut text = Vec::with_capacity(count);
        for row in offsets.chunks_exact(4) {
            let code = utf16
                .get(row[0] as usize..(row[0] as usize).saturating_add(row[1] as usize))
                .ok_or(2)?;
            let region = utf16
                .get(row[2] as usize..(row[2] as usize).saturating_add(row[3] as usize))
                .ok_or(2)?;
            text.push((code.to_vec(), region.to_vec()));
        }
        let rows = input
            .chunks_exact(5)
            .map(|r| [r[0], r[1], r[2], r[3], r[4]])
            .collect();
        unsafe { &mut *owner.cast::<Summary>() }.update(kind as usize, rows, text);
        CALLS.fetch_add(1, Ordering::Relaxed);
        ROWS.fetch_add(count as u64, Ordering::Relaxed);
        Ok::<(), i32>(())
    }))
    .map_or(5, |v| v.err().unwrap_or(0))
}
#[no_mangle]
pub unsafe extern "C" fn rq_station_summary_cells(
    owner: *mut c_void,
    input: *const f64,
    count: usize,
) -> i32 {
    if owner.is_null() || input.is_null() || count > LIMIT {
        return 1;
    }
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let input = unsafe { std::slice::from_raw_parts(input, count * 3) };
        if input
            .chunks_exact(3)
            .any(|r| r.iter().any(|v| !v.is_finite()) || r[0].abs() > 90.0 || r[1].abs() > 180.0)
        {
            return Err(2);
        }
        let state = unsafe { &mut *owner.cast::<Summary>() };
        if state.cells.len() == count
            && state
                .cells
                .iter()
                .zip(input.chunks_exact(3))
                .all(|(a, b)| a == b)
        {
            return Ok(());
        }
        state.cells.clear();
        state
            .cells
            .extend(input.chunks_exact(3).map(|v| [v[0], v[1], v[2]]));
        state.areas_dirty = true;
        Ok::<(), i32>(())
    }))
    .map_or(5, |v| v.err().unwrap_or(0))
}
/// Static directory and coordinates stay in this owner; an ordinary NIED frame
/// contains only its original level/activity columns. No per-frame Vec/tree.
#[no_mangle]
pub unsafe extern "C" fn rq_station_summary_nied_levels(
    owner: *mut c_void,
    input: *const i32,
    count: usize,
) -> i32 {
    if owner.is_null() || input.is_null() || count > LIMIT {
        return 1;
    }
    let state = unsafe { &mut *owner.cast::<Summary>() };
    if count != state.nied.len() {
        return 2;
    }
    let input = unsafe { std::slice::from_raw_parts(input, count * 2) };
    let mut maximum = -1;
    let mut selected = -1;
    for (i, (row, value)) in state.nied.iter_mut().zip(input.chunks_exact(2)).enumerate() {
        if row[1] != value[0] as f64 || row[2] != value[1] as f64 {
            state.areas_dirty = true;
        }
        row[0] = value[0] as f64;
        row[1] = value[0] as f64;
        row[2] = value[1] as f64;
        if value[0] > maximum {
            maximum = value[0];
            selected = i as i32;
        }
    }
    state.indices[2] = selected;
    CALLS.fetch_add(1, Ordering::Relaxed);
    ROWS.fetch_add(count as u64, Ordering::Relaxed);
    0
}
#[no_mangle]
pub unsafe extern "C" fn rq_station_summary_indices(owner: *mut c_void) -> *const i32 {
    if owner.is_null() {
        return std::ptr::null();
    }
    unsafe { &*owner.cast::<Summary>() }.indices.as_ptr()
}
/// Consume the producer's native KA result buffer directly. Only active UI hold
/// flags cross the bridge; no level array is copied back through Dart.
/// Safety: live summary, count KA outputs and count active bytes, synchronous
/// exclusive call; no pointer is retained by the summary.
#[no_mangle]
pub unsafe extern "C" fn rq_station_summary_nied_ka_results(
    owner: *mut c_void,
    results: *const crate::ka_history::Output,
    active: *const u8,
    count: usize,
) -> i32 {
    if owner.is_null() || results.is_null() || active.is_null() || count > LIMIT {
        return 1;
    }
    let state = unsafe { &mut *owner.cast::<Summary>() };
    if count != state.nied.len() {
        return 2;
    }
    let results = unsafe { std::slice::from_raw_parts(results, count) };
    let active = unsafe { std::slice::from_raw_parts(active, count) };
    if active.iter().any(|&v| v > 1) {
        return 2;
    }
    let (mut maximum, mut selected) = (-1, -1);
    for (i, ((row, result), &held)) in state.nied.iter_mut().zip(results).zip(active).enumerate() {
        let level = result.level as f64;
        if row[1] != level || row[2] != held as f64 {
            state.areas_dirty = true;
        }
        row[0] = level;
        row[1] = level;
        row[2] = held as f64;
        if result.level > maximum {
            maximum = result.level;
            selected = i as i32;
        }
    }
    state.indices[2] = selected;
    CALLS.fetch_add(1, Ordering::Relaxed);
    ROWS.fetch_add(count as u64, Ordering::Relaxed);
    0
}
#[no_mangle]
pub unsafe extern "C" fn rq_station_summary_area_count(owner: *mut c_void) -> usize {
    if owner.is_null() {
        return 0;
    }
    let state = unsafe { &mut *owner.cast::<Summary>() };
    if state.areas_dirty {
        state.refresh_areas();
    }
    state.areas.len()
}
#[no_mangle]
pub unsafe extern "C" fn rq_station_summary_area(
    owner: *mut c_void,
    index: usize,
    len: *mut usize,
    level: *mut i32,
) -> *const u16 {
    if owner.is_null() || len.is_null() || level.is_null() {
        return std::ptr::null();
    }
    let Some((text, rank)) = unsafe { &*owner.cast::<Summary>() }.areas.get(index) else {
        return std::ptr::null();
    };
    unsafe {
        *len = text.len();
        *level = *rank;
    }
    text.as_ptr()
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn incremental_max_ties_and_clear() {
        let mut s = Summary::default();
        s.update(
            1,
            vec![[3., 3., 1., 0., 0.], [3., 3., 1., 0., 0.]],
            vec![(vec![], vec![]); 2],
        );
        assert_eq!(s.indices[2], 0);
        s.update(
            2,
            vec![[f64::NAN, 0., 0., 0., 0.], [2., 0., 0., 0., 0.]],
            vec![(vec![], vec![]); 2],
        );
        assert_eq!(s.indices[3], 1);
        assert_eq!(s.indices[2], 0);
        s.update(1, vec![], vec![]);
        assert_eq!(s.indices[2], -1);
    }
    #[test]
    fn top_original_signed_zero_utf16_and_visibility() {
        let mut s = Summary::default();
        let text = vec![(vec![98], vec![]), (vec![97], vec![]), (vec![99], vec![])];
        s.update(
            5,
            vec![
                [3., 1., 1., 0., 0.],
                [3., 1., 1., 0., 0.],
                [9., -1., 1., 0., 0.],
            ],
            text.clone(),
        );
        assert_eq!(&s.indices[6..9], &[2, 1, 0]);
        assert_eq!(&s.indices[12..14], &[3, 3]);
        s.update(
            5,
            vec![
                [0., 1., 1., 0., 0.],
                [-0., 1., 1., 0., 0.],
                [f64::NAN, 1., 1., 0., 0.],
            ],
            text,
        );
        assert_eq!(s.indices[6], 0);
        assert_eq!(double_order(0., -0.), Cmp::Greater);
    }
    #[test]
    fn areas_cell_members_nearest_trim_and_order() {
        let mut s = Summary::default();
        s.cells = vec![[35., 140., 16.], [36., 140., 18.]];
        s.update(
            1,
            vec![[1., 1., 1., 35., 140.], [1., 1., 1., 36.6, 140.]],
            vec![(vec![65], vec![0xfeff, 66, 32]), (vec![67], vec![])],
        );
        s.refresh_areas();
        assert_eq!(s.areas, vec![(vec![67], 6), (vec![66], 5)]);
    }
}
