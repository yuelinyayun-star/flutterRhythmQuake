//! NIED event-record state. One owner per active event; samples are borrowed,
//! timestamps/value bits are preserved and no Dart callbacks are invoked.
use std::ffi::c_void;
use std::sync::atomic::{AtomicU64, Ordering};
const INPUT: usize = 42;
const OUTPUT: usize = 28;
static SESSIONS: AtomicU64 = AtomicU64::new(0);
static FRAMES: AtomicU64 = AtomicU64::new(0);
type Time = [u64; 2];
#[derive(Default)]
struct Record {
    first: Time,
    last: Option<Time>,
    peak_at: Option<Time>,
    end: Option<Time>,
    peak: Option<u64>,
    value: Option<u64>,
    physical_last: [Option<u64>; 3],
    raw: Option<i64>,
    detect: Option<i64>,
    activity: u64,
    ascend: i64,
    count: u64,
    state: u64,
    rise: [u64; 3],
    trigger: [u64; 3],
    physical_peaks: [Option<(i64, u64)>; 6],
}
struct Owner {
    started: i64,
    records: Vec<Option<Record>>,
}
fn independent(code: u64) -> bool {
    code & 8 != 0 && code & 7 != 3 && code & 16 == 0
}
fn finite(bits: u64) -> bool {
    f64::from_bits(bits).is_finite()
}
impl Record {
    fn write_changes(&self, status: u64, actions: u64, before: &[u64; OUTPUT], out: &mut [u64]) {
        self.write(status, actions, out);
        let mut changed = 0;
        for (at, width, presence) in [
            (1, 1, 0),
            (4, 2, 64),
            (6, 2, 32),
            (8, 2, 128),
            (10, 1, 1),
            (11, 1, 2),
            (12, 1, 4),
            (13, 1, 8),
            (14, 1, 16),
            (15, 1, 256),
            (16, 1, 512),
            (17, 1, 0),
            (18, 1, 0),
            (19, 1, 0),
            (20, 3, 0),
            (23, 3, 0),
        ] {
            if before[at..at + width] != out[at..at + width]
                || (before[26] ^ out[26]) & presence != 0
            {
                changed |= 1 << at;
            }
        }
        // Word 2 is the binding-change mask; station firstObservedAt is bound
        // directly from its original creation frame, not reconstructed in Dart.
        out[2] = changed;
    }
    fn apply(&mut self, s: &[u64], now: Time, member: bool, started: i64) -> u64 {
        let present = s[6];
        let triggered = s[5] != 0;
        let activity = f64::from_bits(s[3]);
        let ascend = s[4] as i64;
        let detect = (present & 4 != 0).then_some(s[2] as i64);
        self.last = Some(now);
        self.raw = (present & 2 != 0).then_some(s[1] as i64);
        self.detect = detect;
        self.activity = s[3];
        self.ascend = ascend;
        self.count += 1;
        self.state = if triggered && detect.unwrap_or(-1) >= 14 {
            3
        } else if triggered {
            2
        } else if activity > 0.0 || ascend > 0 {
            1
        } else {
            0
        };
        if present & 1 != 0 && finite(s[7]) {
            self.value = Some(s[7]);
            if self
                .peak
                .is_none_or(|v| f64::from_bits(s[7]) > f64::from_bits(v))
            {
                self.peak = Some(s[7]);
                self.peak_at = Some(now);
            }
        }
        for quantity in 0..3 {
            if present & (8 << quantity) != 0
                && finite(s[8 + quantity])
                && independent(s[18 + quantity + 2])
            {
                self.physical_last[quantity] = Some(s[8 + quantity]);
            }
        }
        if (activity > 0.0 || ascend > 0 || member) && self.rise[2] & 1 == 0 && s[13] & 1 != 0 {
            self.rise.copy_from_slice(&s[11..14]);
        }
        if triggered {
            if self.trigger[2] & 1 == 0 && s[16] & 1 != 0 {
                self.trigger.copy_from_slice(&s[14..17]);
            }
            self.end = None;
        } else if self.trigger[2] & 1 != 0 && self.end.is_none() {
            self.end = Some(now);
        }
        let start = if self.trigger[2] & 1 != 0 {
            self.trigger[1] as i64
        } else if self.rise[2] & 1 != 0 {
            self.rise[1] as i64
        } else {
            started
        };
        let mut actions = 0;
        for quantity in 0..6 {
            if self.physical_peaks[quantity].is_some_and(|(time, _)| time < start) {
                self.physical_peaks[quantity] = None;
                actions |= 1 << (quantity * 4);
            }
        }
        for slot in 0..6 {
            let at = 24 + slot * 3;
            let bits = s[at];
            let time = s[at + 1] as i64;
            let flags = s[at + 2];
            let quantity = ((flags >> 8) & 7) as usize;
            if flags & 1 == 0
                || flags & 14 != 0
                || !finite(bits)
                || time < start
                || !independent(s[18 + quantity])
            {
                continue;
            }
            if self.physical_peaks[quantity]
                .is_none_or(|(_, old)| f64::from_bits(bits) > f64::from_bits(old))
            {
                self.physical_peaks[quantity] = Some((time, bits));
                actions =
                    (actions & !(15 << (quantity * 4))) | ((2 + slot as u64) << (quantity * 4));
            }
        }
        actions
    }
    fn write(&self, status: u64, actions: u64, out: &mut [u64]) {
        out.fill(0);
        out[0] = status;
        out[1] = self.state;
        out[2..4].copy_from_slice(&self.first);
        let mut mask = 0u64;
        for (offset, time, bit) in [
            (4, self.last, 64),
            (6, self.peak_at, 32),
            (8, self.end, 128),
        ] {
            if let Some(time) = time {
                out[offset..offset + 2].copy_from_slice(&time);
                mask |= bit;
            }
        }
        for (index, value) in [
            self.peak,
            self.value,
            self.physical_last[0],
            self.physical_last[1],
            self.physical_last[2],
        ]
        .into_iter()
        .enumerate()
        {
            if let Some(value) = value {
                out[10 + index] = value;
                mask |= 1 << index;
            }
        }
        if let Some(value) = self.raw {
            out[15] = value as u64;
            mask |= 256;
        }
        if let Some(value) = self.detect {
            out[16] = value as u64;
            mask |= 512;
        }
        out[17] = self.activity;
        out[18] = self.ascend as u64;
        out[19] = self.count;
        out[20..23].copy_from_slice(&self.rise);
        out[23..26].copy_from_slice(&self.trigger);
        out[26] = mask;
        out[27] = actions;
    }
}
#[no_mangle]
pub extern "C" fn rq_station_record_create(started_us: i64) -> *mut c_void {
    SESSIONS.fetch_add(1, Ordering::Relaxed);
    Box::into_raw(Box::new(Owner {
        started: started_us,
        records: Vec::new(),
    }))
    .cast()
}
/// # Safety
/// A live owner released exactly once, with no concurrent use.
#[no_mangle]
pub unsafe extern "C" fn rq_station_record_destroy(owner: *mut c_void) {
    if !owner.is_null() {
        drop(unsafe { Box::from_raw(owner.cast::<Owner>()) });
        SESSIONS.fetch_sub(1, Ordering::Relaxed);
    }
}
#[no_mangle]
pub extern "C" fn rq_station_record_sessions() -> u64 {
    SESSIONS.load(Ordering::Relaxed)
}
#[no_mangle]
pub extern "C" fn rq_station_record_frames() -> u64 {
    FRAMES.load(Ordering::Relaxed)
}
/// # Safety
/// Live owner, input[count*42], output[count*28], no alias. Single inference
/// owner only. Original values are copied as bits; no pointer is retained.
#[no_mangle]
pub unsafe extern "C" fn rq_station_record_apply(
    owner: *mut c_void,
    input: *const u64,
    count: usize,
    observed_us: i64,
    observed_utc: u32,
    output: *mut u64,
) -> i32 {
    if owner.is_null() || count > 100_000 {
        return 1;
    }
    if count == 0 {
        return 0;
    }
    if input.is_null() || output.is_null() {
        return 1;
    }
    std::panic::catch_unwind(|| unsafe {
        let owner = &mut *owner.cast::<Owner>();
        let samples = std::slice::from_raw_parts(input, count * INPUT);
        if samples
            .chunks_exact(INPUT)
            .any(|s| s[0] >= 100_000 || (0..6).any(|slot| (s[24 + slot * 3 + 2] >> 8) & 7 >= 6))
        {
            return 2;
        }
        let results = std::slice::from_raw_parts_mut(output, count * OUTPUT);
        let now = [observed_us as u64, u64::from(observed_utc != 0)];
        for (s, out) in samples
            .chunks_exact(INPUT)
            .zip(results.chunks_exact_mut(OUTPUT))
        {
            let id = s[0] as usize;
            if owner.records.len() <= id {
                owner.records.resize_with(id + 1, || None);
            }
            let member = s[17] != 0;
            let meaningful = s[6] & 6 != 0
                || f64::from_bits(s[3]) > 0.0
                || (s[4] as i64) > 0
                || s[5] != 0
                || member;
            if !meaningful {
                out.fill(0);
                if let Some(record) = &mut owner.records[id] {
                    let mut before = [0; OUTPUT];
                    record.write(0, 0, &mut before);
                    if (1..=3).contains(&record.state) && record.end.is_none() {
                        record.state = 4;
                        record.end = Some(now);
                        record.last = Some(now);
                    }
                    record.write_changes(2, 0, &before, out);
                }
                continue;
            }
            let record = owner.records[id].get_or_insert_with(|| Record {
                first: now,
                ..Record::default()
            });
            let mut before = [0; OUTPUT];
            record.write(0, 0, &mut before);
            let actions = record.apply(s, now, member, owner.started);
            record.write_changes(1, actions, &before, out);
        }
        FRAMES.fetch_add(1, Ordering::Relaxed);
        0
    })
    .unwrap_or(5)
}

#[cfg(test)]
mod tests {
    use super::*;
    // Controlled ABI/lifecycle cases; real-source parity is exercised with
    // unmodified captured GIF samples in native_station_record_owner_test.dart.
    #[test]
    fn strict_trigger_does_not_invent_timing_and_missing_ends_then_reopens() {
        unsafe {
            let owner = rq_station_record_create(0);
            let mut sample = [0u64; INPUT];
            sample[2] = 15;
            sample[5] = 1;
            sample[6] = 4;
            let mut out = [0; OUTPUT];
            assert_eq!(
                rq_station_record_apply(owner, sample.as_ptr(), 1, 10, 1, out.as_mut_ptr()),
                0
            );
            assert_eq!(out[1], 3);
            assert_eq!(out[19], 1);
            assert_eq!(out[25], 0);
            let missing = [0; INPUT];
            assert_eq!(
                rq_station_record_apply(owner, missing.as_ptr(), 1, 20, 0, out.as_mut_ptr()),
                0
            );
            assert_eq!(out[0], 2);
            assert_eq!(out[1], 4);
            assert_eq!(out[19], 1);
            assert_eq!(out[8], 20);
            assert_eq!(out[26] & 128, 128);
            sample[14] = 29;
            sample[15] = 30;
            sample[16] = 7;
            assert_eq!(
                rq_station_record_apply(owner, sample.as_ptr(), 1, 30, 1, out.as_mut_ptr()),
                0
            );
            assert_eq!(out[26] & 128, 0);
            assert_eq!(&out[23..26], &[29, 30, 7]);
            rq_station_record_destroy(owner);
        }
    }
    #[test]
    fn physical_independence_and_duplicate_quantity_keep_first_maximum() {
        let mut record = Record::default();
        let mut sample = [0; INPUT];
        sample[6] = 4 | 8;
        sample[8] = 6f64.to_bits();
        sample[20] = 8; // independent PGA
        sample[24] = 5f64.to_bits();
        sample[25] = 10;
        sample[26] = 1 | (2 << 8);
        sample[27] = 4f64.to_bits();
        sample[28] = 10;
        sample[29] = 1 | (2 << 8);
        let actions = record.apply(&sample, [10, 1], false, 0);
        assert_eq!((actions >> 8) & 15, 2); // first original physical slot
        assert_eq!(record.physical_last[0], Some(6f64.to_bits()));
        sample[20] = 8 | 3;
        sample[8] = 99f64.to_bits(); // derived, reject
        assert_eq!(record.apply(&sample, [20, 1], false, 0), 0);
        assert_eq!(record.physical_last[0], Some(6f64.to_bits()));
    }
    #[test]
    fn invalid_batch_is_rejected_before_any_record_mutation() {
        unsafe {
            let owner = rq_station_record_create(0);
            let mut rows = [0u64; INPUT * 2];
            rows[6] = 4;
            rows[INPUT] = 100_000;
            let mut out = [0; OUTPUT * 2];
            assert_eq!(
                rq_station_record_apply(owner, rows.as_ptr(), 2, 0, 0, out.as_mut_ptr()),
                2
            );
            assert!((&*owner.cast::<Owner>()).records.is_empty());
            assert_eq!(
                rq_station_record_apply(owner, std::ptr::null(), 0, 0, 0, std::ptr::null_mut()),
                0
            );
            rq_station_record_destroy(owner);
        }
    }
}

#[cfg(test)]
mod n229_repeat_trigger_tests {
    use super::*;
    #[test]
    fn repeat_trigger_does_not_overwrite_first_and_new_owner_resets() {
        let mut rec = Record::default();
        let mut sample = [0u64; INPUT];
        sample[5] = 1;
        sample[14] = 10;
        sample[15] = 10;
        sample[16] = 1;
        rec.apply(&sample, [10, 1], false, 0);
        assert_eq!(rec.trigger, [10, 10, 1]);
        sample[5] = 0;
        sample[16] = 0;
        rec.apply(&sample, [11, 1], false, 0);
        assert_eq!(rec.trigger, [10, 10, 1]);
        assert_eq!(rec.end, Some([11, 1]));
        sample[5] = 1;
        sample[14] = 20;
        sample[15] = 20;
        sample[16] = 1;
        rec.apply(&sample, [20, 1], false, 0);
        assert_eq!(rec.trigger, [10, 10, 1]);
        assert_eq!(rec.end, None);
        let mut new_event_record = Record::default();
        new_event_record.apply(&sample, [20, 1], false, 20);
        assert_eq!(new_event_record.trigger, [20, 20, 1]);
    }
}
