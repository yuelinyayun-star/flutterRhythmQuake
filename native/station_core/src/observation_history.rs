//! Ordered raw observation rows. Values are copied as bits, never normalized.
use std::collections::{HashMap, VecDeque};
use std::sync::atomic::{AtomicU64, Ordering};
static SESSIONS: AtomicU64 = AtomicU64::new(0);
static CALLS: AtomicU64 = AtomicU64::new(0);
static BATCH_CALLS: AtomicU64 = AtomicU64::new(0);
static SUMMARY_CALLS: AtomicU64 = AtomicU64::new(0);
static SNAPSHOT_CALLS: AtomicU64 = AtomicU64::new(0);
const WORDS: usize = 7;
#[derive(Clone, Copy)]
struct Row([u64; WORDS]);
impl Row {
    fn data_us(self) -> i64 {
        self.0[0] as i64
    }
    fn usable(self) -> bool {
        self.0[5] & 64 == 0
    }
    fn detect(self) -> Option<i64> {
        (self.0[5] & 4 != 0).then_some(self.0[4] as i64)
    }
    fn signal(self) -> Option<f64> {
        let value = f64::from_bits(self.0[2]);
        if self.0[5] & 1 != 0 && value.is_finite() {
            return Some(value);
        }
        let level = if self.0[5] & 2 != 0 {
            Some(self.0[3] as i64)
        } else {
            self.detect()
        }?;
        Some(if level <= 0 {
            -3.0
        } else if level >= 20 {
            6.5
        } else {
            (level as f64 + 0.5 - 7.0) / 2.0
        })
    }
}
fn milliseconds_between(a: i64, b: i64) -> i128 {
    (i128::from(a) - i128::from(b)) / 1000
}
#[derive(Clone, Copy)]
#[repr(C)]
struct CompactRow {
    value: u64,
    data_delta: i32,
    received_delta: i32,
    metadata: u32,
    raw: i8,
    detect: i8,
    flags: u8,
    wide: u8,
}
struct History {
    rows: VecDeque<CompactRow>,
    base_us: i64,
    wide_rows: HashMap<u64, Row>,
    next_wide: u64,
}
impl History {
    // Result: changes at 1/4/9 s, immediate change, recent-slot count, three
    // recent converted values, and a four-bit presence mask. Missing changes
    // mean the caller's record.lastAscend, not zero. Raw rows remain untouched.
    fn nied_summary(&self, observed_us: Option<i64>) -> [f64; 9] {
        let mut out = [0.0; 9];
        let Some(last) = self.rows.back() else {
            return out;
        };
        let latest = self.expand(last);
        let mut slots = 0;
        for row in self.rows.iter().rev().map(|r| self.expand(r)) {
            if observed_us
                .is_some_and(|now| i128::from(row.data_us()) > i128::from(now) + 1_500_000)
            {
                continue;
            }
            if let Some(value) = row.signal() {
                out[5 + slots] = value;
                slots += 1;
                if slots == 3 {
                    break;
                }
            }
        }
        out[4] = slots as f64;
        let too_old =
            observed_us.is_some_and(|now| milliseconds_between(now, latest.data_us()).abs() > 1500);
        let Some(current) = latest.signal().filter(|_| latest.usable() && !too_old) else {
            // History changes return zero for an invalid latest frame. The
            // immediate query checks validity only when there are >=2 rows.
            out[8] = if self.rows.len() >= 2 { 15.0 } else { 7.0 };
            return out;
        };
        let mut references: [Option<Row>; 3] = [None; 3];
        let mut oldest = None;
        let mut immediate = None;
        let targets = [1_000_000i128, 4_000_000, 9_000_000];
        for row in self.rows.iter().rev().skip(1).map(|r| self.expand(r)) {
            if !row.usable() {
                continue;
            }
            if immediate.is_none() {
                immediate = Some(row);
            }
            oldest = Some(row);
            for index in 0..3 {
                if references[index].is_none()
                    && i128::from(row.data_us()) <= i128::from(latest.data_us()) - targets[index]
                {
                    references[index] = Some(row);
                }
            }
            if references.iter().all(Option::is_some) {
                break;
            }
        }
        let mut mask = 0;
        for index in 0..3 {
            if let Some(reference) = references[index].or(oldest) {
                out[index] = reference.signal().map_or(0.0, |value| current - value);
                mask |= 1 << index;
            }
        }
        if let Some(reference) = immediate {
            out[3] = reference.signal().map_or(0.0, |value| current - value);
            mask |= 8;
        }
        out[8] = mask as f64;
        out
    }

    fn pretrigger_seconds(&self, earliest_us: i64, fallback_us: i64) -> Option<f64> {
        let mut cache = None;
        let mut previous_signal = None;
        let mut previous_detect = None;
        for row in self.rows.iter().map(|r| self.expand(r)) {
            if row.data_us() > fallback_us {
                break;
            }
            if !row.usable() {
                continue;
            }
            let signal = row.signal();
            let detect = row.detect();
            let triggered = row.0[5] & 8 != 0;
            let active =
                triggered || detect.is_some_and(|v| v > 0) || signal.is_some_and(|v| v > 0.0);
            if !active {
                cache = None;
            } else {
                let rising_signal = signal
                    .is_some_and(|v| previous_signal.is_none_or(|previous| v > previous + 0.01));
                let rising_detect =
                    detect.is_some_and(|v| previous_detect.is_none_or(|previous| v > previous));
                if rising_signal || rising_detect || triggered {
                    cache.get_or_insert(
                        milliseconds_between(row.data_us(), earliest_us) as f64 / 1000.0,
                    );
                } else {
                    cache = None;
                }
            }
            previous_signal = signal.or(previous_signal);
            previous_detect = detect.or(previous_detect);
        }
        cache.filter(|v| milliseconds_between(fallback_us, earliest_us) as f64 / 1000.0 - v <= 20.0)
    }
    fn expand(&self, row: &CompactRow) -> Row {
        if row.wide != 0 {
            return self.wide_rows[&row.value];
        }
        Row([
            (self.base_us + i64::from(row.data_delta)) as u64,
            (self.base_us + i64::from(row.received_delta)) as u64,
            row.value,
            i64::from(row.raw) as u64,
            i64::from(row.detect) as u64,
            u64::from(row.flags),
            u64::from(row.metadata),
        ])
    }
    fn rebase(&mut self, base: i64) {
        let delta = i128::from(self.base_us) - i128::from(base);
        if self.rows.iter().any(|r| {
            r.wide == 0
                && (i32::try_from(i128::from(r.data_delta) + delta).is_err()
                    || i32::try_from(i128::from(r.received_delta) + delta).is_err())
        }) {
            return;
        }
        for r in &mut self.rows {
            if r.wide == 0 {
                r.data_delta = (i128::from(r.data_delta) + delta) as i32;
                r.received_delta = (i128::from(r.received_delta) + delta) as i32;
            }
        }
        self.base_us = base;
    }
    fn pack(&mut self, row: Row) -> CompactRow {
        let data = row.0[0] as i64;
        let received = row.0[1] as i64;
        if self.rows.is_empty() {
            self.base_us = data;
        }
        let mut d = i32::try_from(i128::from(data) - i128::from(self.base_us));
        let mut r = i32::try_from(i128::from(received) - i128::from(self.base_us));
        if d.is_err() || r.is_err() {
            self.rebase(data);
            d = i32::try_from(i128::from(data) - i128::from(self.base_us));
            r = i32::try_from(i128::from(received) - i128::from(self.base_us));
        }
        if let (Ok(data_delta), Ok(received_delta), Ok(metadata), Ok(raw), Ok(detect), Ok(flags)) = (
            d,
            r,
            u32::try_from(row.0[6]),
            i8::try_from(row.0[3] as i64),
            i8::try_from(row.0[4] as i64),
            u8::try_from(row.0[5]),
        ) {
            return CompactRow {
                value: row.0[2],
                data_delta,
                received_delta,
                metadata,
                raw,
                detect,
                flags,
                wide: 0,
            };
        }
        let id = self.next_wide;
        self.next_wide += 1;
        self.wide_rows.insert(id, row);
        CompactRow {
            value: id,
            data_delta: 0,
            received_delta: 0,
            metadata: 0,
            raw: 0,
            detect: 0,
            flags: 0,
            wide: 1,
        }
    }
    fn evict(&mut self, cutoff: i64) {
        while self
            .rows
            .front()
            .is_some_and(|r| (self.expand(r).0[0] as i64) < cutoff)
        {
            let row = self.rows.pop_front().unwrap();
            if row.wide != 0 {
                self.wide_rows.remove(&row.value);
            }
        }
        if self.wide_rows.is_empty() {
            self.wide_rows = HashMap::new();
        }
    }
    fn packed_size(&self) -> usize {
        self.rows.len() * 24 + self.wide_rows.len() * 64
    }
}
#[no_mangle]
pub extern "C" fn rq_observation_abi_version() -> u32 {
    1
}
#[no_mangle]
pub extern "C" fn rq_observation_sessions() -> u64 {
    SESSIONS.load(Ordering::Relaxed)
}
#[no_mangle]
pub extern "C" fn rq_observation_calls() -> u64 {
    CALLS.load(Ordering::Relaxed)
}
#[no_mangle]
pub extern "C" fn rq_observation_summary_calls() -> u64 {
    SUMMARY_CALLS.load(Ordering::Relaxed)
}
#[no_mangle]
pub extern "C" fn rq_observation_snapshot_calls() -> u64 {
    SNAPSHOT_CALLS.load(Ordering::Relaxed)
}
/// # Safety
/// A live history and caller-owned output[9]. No pointer retained.
#[no_mangle]
pub unsafe extern "C" fn rq_observation_nied_summary(
    handle: *const std::ffi::c_void,
    observed_us: i64,
    has_observed: u32,
    output: *mut f64,
) -> i32 {
    if handle.is_null() || output.is_null() {
        return 1;
    }
    std::panic::catch_unwind(|| unsafe {
        let history = &*handle.cast::<History>();
        std::slice::from_raw_parts_mut(output, 9)
            .copy_from_slice(&history.nied_summary((has_observed != 0).then_some(observed_us)));
        SUMMARY_CALLS.fetch_add(1, Ordering::Relaxed);
        0
    })
    .unwrap_or(5)
}
/// # Safety
/// A live history and caller-owned output[1]. Return 0 absent, 1 present;
/// negative values denote errors. No pointer retained.
#[no_mangle]
pub unsafe extern "C" fn rq_observation_pretrigger(
    handle: *const std::ffi::c_void,
    earliest_us: i64,
    fallback_us: i64,
    output: *mut f64,
) -> i32 {
    if handle.is_null() || output.is_null() {
        return -1;
    }
    std::panic::catch_unwind(|| unsafe {
        match (&*handle.cast::<History>()).pretrigger_seconds(earliest_us, fallback_us) {
            Some(value) => {
                *output = value;
                1
            }
            None => 0,
        }
    })
    .unwrap_or(-5)
}
/// # Safety
/// A live history. Exact Scratch three-slot fast-rise threshold decision.
#[no_mangle]
pub unsafe extern "C" fn rq_observation_fast_rise(
    handle: *const std::ffi::c_void,
    observed_us: i64,
    digit: i64,
) -> i32 {
    if handle.is_null() {
        return -1;
    }
    std::panic::catch_unwind(|| unsafe {
        let out = (&*handle.cast::<History>()).nied_summary(Some(observed_us));
        if out[4] < 3.0 {
            return 0;
        }
        let current = 3.0 + out[5];
        let previous = 3.0 + out[7];
        let limit = if digit == 0 {
            75.0
        } else {
            digit as f64 * digit as f64
        };
        i32::from(limit < current * current - previous * previous)
    })
    .unwrap_or(-5)
}
#[no_mangle]
pub extern "C" fn rq_observation_create() -> *mut std::ffi::c_void {
    SESSIONS.fetch_add(1, Ordering::Relaxed);
    Box::into_raw(Box::new(History {
        rows: VecDeque::new(),
        base_us: 0,
        wide_rows: HashMap::new(),
        next_wide: 0,
    }))
    .cast()
}
/// # Safety
/// A live handle returned by create, destroyed exactly once.
#[no_mangle]
pub unsafe extern "C" fn rq_observation_destroy(handle: *mut std::ffi::c_void) {
    if !handle.is_null() {
        unsafe {
            drop(Box::from_raw(handle.cast::<History>()));
        }
        SESSIONS.fetch_sub(1, Ordering::Relaxed);
    }
}
/// # Safety
/// Live handle, aligned row[7] and output[3], with no overlap. No pointer retained.
#[no_mangle]
pub unsafe extern "C" fn rq_observation_push(
    handle: *mut std::ffi::c_void,
    row: *const u64,
    cutoff_us: i64,
    output: *mut i64,
) -> i32 {
    if handle.is_null() || row.is_null() || output.is_null() {
        return 1;
    }
    std::panic::catch_unwind(|| unsafe {
        let h = &mut *handle.cast::<History>();
        let values = std::slice::from_raw_parts(row, WORDS);
        if h.rows
            .back()
            .is_some_and(|last| (values[0] as i64) < h.expand(last).0[0] as i64)
        {
            return 4;
        }
        let mut copy = [0; WORDS];
        copy.copy_from_slice(values);
        h.evict(cutoff_us);
        if (copy[0] as i64) >= cutoff_us {
            let packed = h.pack(Row(copy));
            h.rows.push_back(packed);
        }
        let out = std::slice::from_raw_parts_mut(output, 3);
        out[0] = h.rows.len() as i64;
        out[1] = h.rows.front().map_or(-1, |r| h.expand(r).0[6] as i64);
        out[2] = (h.rows.capacity() * 24) as i64;
        CALLS.fetch_add(1, Ordering::Relaxed);
        0
    })
    .unwrap_or(5)
}
#[no_mangle]
pub extern "C" fn rq_observation_batch_abi_version() -> u32 {
    1
}
#[no_mangle]
pub extern "C" fn rq_observation_batch_calls() -> u64 {
    BATCH_CALLS.load(Ordering::Relaxed)
}
/// # Safety
/// Live handles[count], input[count * 8] and output[count * 4], no overlap.
/// Input is the original seven words followed by an i64 cutoff. Duplicate
/// handles are legal and processed in order; no simultaneous mutable borrows.
/// Output: status, length, oldest metadata, capacity. A failing row stops the
/// batch; later rows have status 6 (not processed). No pointers are retained.
#[no_mangle]
pub unsafe extern "C" fn rq_observation_push_batch(
    handles: *const *mut std::ffi::c_void,
    input: *const u64,
    count: usize,
    output: *mut i64,
) -> i32 {
    if count == 0 {
        return 0;
    }
    if count > 100_000 {
        return 2;
    }
    if handles.is_null() || input.is_null() || output.is_null() {
        return 1;
    }
    std::panic::catch_unwind(|| unsafe {
        let handles = std::slice::from_raw_parts(handles, count);
        let rows = std::slice::from_raw_parts(input, count * 8);
        let results = std::slice::from_raw_parts_mut(output, count * 4);
        for result in results.chunks_exact_mut(4) {
            result.copy_from_slice(&[6, 0, -1, 0]);
        }
        BATCH_CALLS.fetch_add(1, Ordering::Relaxed);
        for (index, handle) in handles.iter().enumerate() {
            let row = &rows[index * 8..index * 8 + 8];
            let result = &mut results[index * 4..index * 4 + 4];
            let status = rq_observation_push(
                *handle,
                row.as_ptr(),
                row[7] as i64,
                result[1..].as_mut_ptr(),
            );
            result[0] = i64::from(status);
            if status != 0 {
                return status;
            }
        }
        0
    })
    .unwrap_or(5)
}
/// # Safety
/// Live handle and output of capacity rows (7 u64 words each). No pointer retained.
#[no_mangle]
pub unsafe extern "C" fn rq_observation_copy(
    handle: *const std::ffi::c_void,
    output: *mut u64,
    capacity: usize,
) -> i32 {
    if handle.is_null() {
        return 1;
    }
    std::panic::catch_unwind(|| unsafe {
        let h = &*handle.cast::<History>();
        if capacity < h.rows.len() {
            return 3;
        }
        if h.rows.is_empty() {
            return 0;
        }
        if output.is_null() {
            return 1;
        }
        let out = std::slice::from_raw_parts_mut(output, h.rows.len() * WORDS);
        for (row, dest) in h.rows.iter().zip(out.chunks_exact_mut(WORDS)) {
            dest.copy_from_slice(&h.expand(row).0);
        }
        0
    })
    .unwrap_or(5)
}
/// # Safety
/// A live history handle. Clear releases the entire numeric window allocation.
#[no_mangle]
pub unsafe extern "C" fn rq_observation_clear(handle: *mut std::ffi::c_void) -> i32 {
    if handle.is_null() {
        return 1;
    }
    std::panic::catch_unwind(|| unsafe {
        let h = &mut *handle.cast::<History>();
        h.rows = VecDeque::new();
        h.wide_rows = HashMap::new();
        0
    })
    .unwrap_or(5)
}
/// # Safety
/// A live handle. Returns the exact caller buffer size for packed snapshot ABI 1.
#[no_mangle]
pub unsafe extern "C" fn rq_observation_packed_size(handle: *const std::ffi::c_void) -> usize {
    if handle.is_null() {
        return 0;
    }
    unsafe { (&*handle.cast::<History>()).packed_size() }
}
/// # Safety
/// Live handle, output[capacity] and header[3], no overlap. Little-endian ABI 1.
/// Header: row count, base microseconds, wide-record count. No pointers retained.
#[no_mangle]
pub unsafe extern "C" fn rq_observation_copy_packed(
    handle: *const std::ffi::c_void,
    output: *mut u8,
    capacity: usize,
    header: *mut i64,
) -> i32 {
    if handle.is_null() || header.is_null() {
        return 1;
    }
    std::panic::catch_unwind(|| unsafe {
        let h = &*handle.cast::<History>();
        let size = h.packed_size();
        if capacity < size {
            return 3;
        }
        if size != 0 && output.is_null() {
            return 1;
        }
        let head = std::slice::from_raw_parts_mut(header, 3);
        SNAPSHOT_CALLS.fetch_add(1, Ordering::Relaxed);
        head.copy_from_slice(&[h.rows.len() as i64, h.base_us, h.wide_rows.len() as i64]);
        if size == 0 {
            return 0;
        }
        let out = std::slice::from_raw_parts_mut(output, size);
        for (r, dest) in h.rows.iter().zip(out.chunks_exact_mut(24)) {
            dest[0..8].copy_from_slice(&r.value.to_le_bytes());
            dest[8..12].copy_from_slice(&r.data_delta.to_le_bytes());
            dest[12..16].copy_from_slice(&r.received_delta.to_le_bytes());
            dest[16..20].copy_from_slice(&r.metadata.to_le_bytes());
            dest[20] = r.raw as u8;
            dest[21] = r.detect as u8;
            dest[22] = r.flags;
            dest[23] = r.wide;
        }
        for ((id, row), dest) in h
            .wide_rows
            .iter()
            .zip(out[h.rows.len() * 24..].chunks_exact_mut(64))
        {
            dest[0..8].copy_from_slice(&id.to_le_bytes());
            for (v, word) in row.0.iter().zip(dest[8..].chunks_exact_mut(8)) {
                word.copy_from_slice(&v.to_le_bytes());
            }
        }
        0
    })
    .unwrap_or(5)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn chronological_cutoff_duplicates_and_bits() {
        assert_eq!(std::mem::size_of::<CompactRow>(), 24);
        unsafe {
            let handle = rq_observation_create();
            let mut out = [0; 3];
            let a = [100u64, 200, 0x7ff8000000000042, 0xffffffffffffffff, 0, 0, 0];
            assert_eq!(
                rq_observation_push(handle, a.as_ptr(), 100, out.as_mut_ptr()),
                0
            );
            assert_eq!(
                rq_observation_push(handle, a.as_ptr(), 100, out.as_mut_ptr()),
                0
            );
            assert_eq!(out[0], 2);
            let mut copy = [0; 14];
            assert_eq!(rq_observation_copy(handle, copy.as_mut_ptr(), 1), 3);
            assert_eq!(rq_observation_copy(handle, copy.as_mut_ptr(), 2), 0);
            assert_eq!(&copy[..7], &a);
            assert_eq!(&copy[7..], &a);
            let mut earlier = a;
            earlier[0] = 99;
            assert_eq!(
                rq_observation_push(handle, earlier.as_ptr(), 100, out.as_mut_ptr()),
                4
            );
            let mut next = a;
            next[0] = 101;
            next[6] = 1;
            assert_eq!(
                rq_observation_push(handle, next.as_ptr(), 101, out.as_mut_ptr()),
                0
            );
            assert_eq!(out[0], 1);
            assert_eq!(out[1], 1);
            assert_eq!(
                rq_observation_push(handle, next.as_ptr(), 102, out.as_mut_ptr()),
                0
            );
            assert_eq!(out[0], 0);
            assert_eq!(out[1], -1);
            assert_eq!(rq_observation_clear(handle), 0);
            rq_observation_destroy(handle);
        }
    }
    #[test]
    fn rebase_and_wide_records_round_trip_without_rounding() {
        unsafe {
            let handle = rq_observation_create();
            let mut output = [0; 3];
            let mut expected: Vec<Row> = Vec::new();
            // Controlled ABI edge cases; performance uses untouched raw GIFs.
            for index in 0..=4000i64 {
                let time = -4_000_000_000 + index * 1_000_000;
                let wide = index % 11 == 0;
                let row = Row([
                    time as u64,
                    (time + if wide { 5_000_000_001 } else { 137 }) as u64,
                    0x7ff8000000000042 + index as u64,
                    if wide {
                        (-201i64) as u64
                    } else {
                        (-1i64) as u64
                    },
                    if wide { 301 } else { 7 },
                    63,
                    if wide {
                        u32::MAX as u64 + index as u64 + 1
                    } else {
                        index as u64
                    },
                ]);
                let cutoff = time - 60_000_000;
                assert_eq!(
                    rq_observation_push(handle, row.0.as_ptr(), cutoff, output.as_mut_ptr()),
                    0
                );
                expected.retain(|r| (r.0[0] as i64) >= cutoff);
                expected.push(row);
                assert_eq!(output[0] as usize, expected.len());
                let mut raw = vec![0; expected.len() * WORDS];
                assert_eq!(
                    rq_observation_copy(handle, raw.as_mut_ptr(), expected.len()),
                    0
                );
                let h = &*handle.cast::<History>();
                let mut packed = vec![0; rq_observation_packed_size(handle)];
                let mut header = [0; 3];
                assert_eq!(
                    rq_observation_copy_packed(
                        handle,
                        packed.as_mut_ptr(),
                        packed.len(),
                        header.as_mut_ptr()
                    ),
                    0
                );
                assert_eq!(header[0] as usize, expected.len());
                let read =
                    |offset| u64::from_le_bytes(packed[offset..offset + 8].try_into().unwrap());
                for (i, reference) in expected.iter().enumerate() {
                    assert_eq!(&raw[i * WORDS..(i + 1) * WORDS], &reference.0);
                    let at = i * 24;
                    let decoded = if packed[at + 23] != 0 {
                        let id = read(at);
                        let offset = (expected.len() * 24..packed.len())
                            .step_by(64)
                            .find(|&at| read(at) == id)
                            .unwrap()
                            + 8;
                        std::array::from_fn(|j| read(offset + j * 8))
                    } else {
                        let delta = |at| i32::from_le_bytes(packed[at..at + 4].try_into().unwrap());
                        [
                            (header[1] + i64::from(delta(at + 8))) as u64,
                            (header[1] + i64::from(delta(at + 12))) as u64,
                            read(at),
                            i64::from(packed[at + 20] as i8) as u64,
                            i64::from(packed[at + 21] as i8) as u64,
                            packed[at + 22] as u64,
                            u32::from_le_bytes(packed[at + 16..at + 20].try_into().unwrap()) as u64,
                        ]
                    };
                    assert_eq!(decoded, reference.0);
                }
                assert!(h.wide_rows.len() < 7);
            }
            assert_eq!(rq_observation_clear(handle), 0);
            let h = &*handle.cast::<History>();
            assert_eq!(h.rows.capacity(), 0);
            assert_eq!(h.wide_rows.capacity(), 0);
            rq_observation_destroy(handle);
        }
    }
}

#[cfg(test)]
mod batch_tests {
    use super::*;
    #[test]
    fn ordered_duplicates_wide_bits_and_partial_failure() {
        unsafe {
            let a = rq_observation_create();
            let b = rq_observation_create();
            let ra = rq_observation_create();
            let rb = rq_observation_create();
            let handles = [a, b, a, a, b];
            let references = [ra, rb, ra, ra, rb];
            let rows: [[u64; 8]; 5] = [
                [100, 110, 0x8000000000000000, 1, 2, 7, 0, 100],
                [200, 205, 0x7ff8000000000042, 1 << 40, 2, 15, 0, 150],
                [100, 111, 0x7ff0000000000000, 3, 4, 7, 1, 100],
                [101, 112, 0, 5, 6, 7, 2, 101],
                [201, 206, 0, 7, 8, 7, 1, 200],
            ];
            let mut expected = [[0i64; 3]; 5];
            for index in 0..rows.len() {
                assert_eq!(
                    rq_observation_push(
                        references[index],
                        rows[index].as_ptr(),
                        rows[index][7] as i64,
                        expected[index].as_mut_ptr()
                    ),
                    0
                );
            }
            let mut out = [[0i64; 4]; 5];
            assert_eq!(
                rq_observation_push_batch(
                    handles.as_ptr(),
                    rows.as_ptr().cast(),
                    rows.len(),
                    out.as_mut_ptr().cast()
                ),
                0
            );
            for index in 0..rows.len() {
                assert_eq!(out[index][0], 0);
                assert_eq!(out[index][1..], expected[index]);
            }
            for (h, r) in [(a, ra), (b, rb)] {
                let count = (&*h.cast::<History>()).rows.len();
                let mut actual = vec![0; count * 7];
                let mut reference = vec![0; count * 7];
                assert_eq!(rq_observation_copy(h, actual.as_mut_ptr(), count), 0);
                assert_eq!(rq_observation_copy(r, reference.as_mut_ptr(), count), 0);
                assert_eq!(actual, reference);
            }
            let handles = [a, a, b];
            let mut bad = [[102u64, 112, 0, 1, 1, 7, 3, 100]; 3];
            bad[1][0] = 99;
            bad[2][0] = 202;
            let mut failure = [[-9i64; 4]; 3];
            assert_eq!(
                rq_observation_push_batch(
                    handles.as_ptr(),
                    bad.as_ptr().cast(),
                    3,
                    failure.as_mut_ptr().cast()
                ),
                4
            );
            assert_eq!(failure[0][0], 0);
            assert_eq!(failure[1][0], 4);
            assert_eq!(failure[2][0], 6);
            assert_eq!((&*b.cast::<History>()).rows.len(), 2);
            for handle in [a, b, ra, rb] {
                rq_observation_destroy(handle);
            }
        }
    }
    #[test]
    fn batch_bounds_empty_and_null_handles() {
        unsafe {
            assert_eq!(
                rq_observation_push_batch(
                    std::ptr::null(),
                    std::ptr::null(),
                    0,
                    std::ptr::null_mut()
                ),
                0
            );
            assert_eq!(
                rq_observation_push_batch(
                    std::ptr::null(),
                    std::ptr::null(),
                    100001,
                    std::ptr::null_mut()
                ),
                2
            );
            assert_eq!(
                rq_observation_push_batch(
                    std::ptr::null(),
                    std::ptr::null(),
                    1,
                    std::ptr::null_mut()
                ),
                1
            );
            let handles = [std::ptr::null_mut()];
            let row = [0u64; 8];
            let mut out = [0i64; 4];
            assert_eq!(
                rq_observation_push_batch(handles.as_ptr(), row.as_ptr(), 1, out.as_mut_ptr()),
                1
            );
            assert_eq!(out[0], 1);
        }
    }
}
