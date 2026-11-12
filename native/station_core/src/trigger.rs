use std::collections::VecDeque;
use std::sync::atomic::{AtomicUsize, Ordering};

const MAX_BATCH: usize = 1_048_576;
static SESSIONS: AtomicUsize = AtomicUsize::new(0);
static CALLS: AtomicUsize = AtomicUsize::new(0);

#[repr(C)]
#[derive(Clone, Copy)]
pub struct Config {
    history_us: i64,
    minimum_samples: i64,
    rising_delta: f64,
    triggered_delta: f64,
    rising_frames: i64,
    triggered_frames: i64,
    decay_frames: i64,
    missing_frames: i64,
    strong_level: i64,
}

#[repr(C)]
pub struct Input {
    station: u64,
    time: i64,
    signal: f64,
    detect_level: i64,
    flags: u64, // signal present, usable observation, detect level present
}

#[repr(C)]
#[derive(Default)]
pub struct Output {
    state: u32,
    reason: u32,
    ascend: i64,
    activity: f64,
    rise_start: i64,
    rise_end: i64,
    trigger_start: i64,
    trigger_end: i64,
    flags: u64, // rise interval present, trigger interval present
}

struct History {
    samples: VecDeque<(i64, f64)>,
    counts: [u32; 96],
    distinct_integers: u32,
    fractional: bool,
    disordered: bool,
    state: u32,
    last_time: Option<(i64, bool)>,
    rise: Option<(i64, i64, bool, bool)>,
    trigger: Option<(i64, i64, bool, bool)>,
    rising_streak: i64,
    triggered_streak: i64,
    decay_streak: i64,
    missing: i64,
}

impl Default for History {
    fn default() -> Self {
        Self {
            samples: VecDeque::new(),
            counts: [0; 96],
            distinct_integers: 0,
            fractional: false,
            disordered: false,
            state: 0,
            last_time: None,
            rise: None,
            trigger: None,
            rising_streak: 0,
            triggered_streak: 0,
            decay_streak: 0,
            missing: 0,
        }
    }
}

fn histogram_index(value: f64) -> Option<usize> {
    if value.is_finite() && value == value.trunc() && (-32.0..=63.0).contains(&value) {
        Some((value as i64 + 32) as usize)
    } else {
        None
    }
}

impl History {
    fn median(&self, sorted: &mut Vec<f64>) -> Option<f64> {
        let len = self.samples.len();
        if len == 0 {
            return None;
        }
        if !self.fractional {
            if self.distinct_integers == 1 {
                // The exact histogram median for a single integer bin, with
                // positive zero just like the original histogram conversion.
                return Some(self.samples.back().unwrap().1 as i64 as f64);
            }
            let lower = (len - 1) / 2;
            let upper = len / 2;
            let mut seen = 0;
            let mut low = None;
            for (index, count) in self.counts.iter().enumerate() {
                let next = seen + *count as usize;
                let value = index as i64 - 32;
                if low.is_none() && lower < next {
                    low = Some(value);
                }
                if upper < next {
                    return Some((low.unwrap() + value) as f64 / 2.0);
                }
                seen = next;
            }
        }
        sorted.clear();
        sorted.extend(self.samples.iter().map(|s| s.1));
        sorted.sort_unstable_by(f64::total_cmp);
        if len % 2 == 1 {
            Some(sorted[len / 2])
        } else {
            Some((sorted[len / 2 - 1] + sorted[len / 2]) / 2.0)
        }
    }

    fn update(
        &mut self,
        input: &Input,
        cfg: Config,
        scratch: &mut Vec<f64>,
    ) -> Result<Output, i32> {
        let has_signal = input.flags & 1 != 0;
        let signal = input.signal;
        if has_signal && !signal.is_finite() {
            return Err(2);
        }
        let ascend = if !has_signal || self.samples.is_empty() {
            0
        } else {
            let difference = signal - self.samples.back().unwrap().1;
            if !difference.is_finite() {
                return Err(2);
            }
            difference.round() as i64
        };
        let delta = if has_signal {
            self.median(scratch).map_or(0.0, |v| signal - v)
        } else {
            0.0
        };
        let was_active = (1..=4).contains(&self.state);
        let state;
        let reason;
        if input.flags & 2 == 0 || !has_signal {
            self.missing += 1;
            self.rising_streak = 0;
            self.triggered_streak = 0;
            if was_active && self.missing >= cfg.missing_frames {
                state = 5;
                reason = 0;
            } else if was_active {
                state = 4;
                reason = 1;
            } else {
                state = 0;
                reason = 2;
            }
        } else {
            self.missing = 0;
            if (self.samples.len() as i64) < cfg.minimum_samples {
                state = 0;
                reason = 3;
            } else {
                self.rising_streak = if delta >= cfg.rising_delta && ascend >= 0 {
                    self.rising_streak + 1
                } else {
                    0
                };
                self.triggered_streak = if delta >= cfg.triggered_delta && ascend >= 0 {
                    self.triggered_streak + 1
                } else {
                    0
                };
                if input.flags & 4 != 0
                    && input.detect_level >= cfg.strong_level
                    && self.triggered_streak >= cfg.triggered_frames
                {
                    state = 3;
                    reason = 4;
                } else if self.triggered_streak >= cfg.triggered_frames {
                    state = 2;
                    reason = 5;
                } else if self.rising_streak >= cfg.rising_frames {
                    state = 1;
                    reason = 6;
                } else if was_active {
                    self.decay_streak += 1;
                    if self.decay_streak >= cfg.decay_frames {
                        state = 5;
                        reason = 7;
                    } else {
                        state = 4;
                        reason = 8;
                    }
                } else {
                    state = 0;
                    reason = 9;
                }
            }
            if (1..=3).contains(&state) {
                self.decay_streak = 0;
            }
        }
        let utc = input.flags & 8 != 0;
        let previous = self.last_time.filter(|v| v.0 < input.time);
        let (interval_start, start_utc) =
            previous.unwrap_or((input.time.checked_sub(1_000_000).ok_or(2)?, utc));
        if (1..=3).contains(&state) && self.rise.is_none() {
            self.rise = Some((interval_start, input.time, start_utc, utc));
        }
        if (2..=3).contains(&state) && self.trigger.is_none() {
            self.trigger = Some((interval_start, input.time, start_utc, utc));
        }
        self.state = state;
        self.last_time = Some((input.time, utc));
        if has_signal {
            let cutoff = input.time.checked_sub(cfg.history_us).ok_or(2)?;
            if self.samples.back().is_some_and(|s| s.0 > input.time) {
                self.disordered = true;
            }
            self.samples.push_back((input.time, signal));
            if let Some(index) = histogram_index(signal) {
                if self.counts[index] == 0 {
                    self.distinct_integers += 1;
                }
                self.counts[index] += 1;
            } else {
                self.fractional = true;
            }
            if !self.disordered {
                while self.samples.front().is_some_and(|s| s.0 < cutoff) {
                    let (_, value) = self.samples.pop_front().unwrap();
                    if let Some(index) = histogram_index(value) {
                        self.counts[index] -= 1;
                        if self.counts[index] == 0 {
                            self.distinct_integers -= 1;
                        }
                    }
                }
            } else {
                // Stable filtering preserves duplicate and out-of-order input.
                let counts = &mut self.counts;
                let distinct = &mut self.distinct_integers;
                let mut previous = None;
                self.disordered = false;
                let disordered = &mut self.disordered;
                self.samples.retain(|(time, value)| {
                    if *time < cutoff {
                        if let Some(index) = histogram_index(*value) {
                            counts[index] -= 1;
                            if counts[index] == 0 {
                                *distinct -= 1;
                            }
                        }
                        false
                    } else {
                        if previous.is_some_and(|p| p > *time) {
                            *disordered = true;
                        }
                        previous = Some(*time);
                        true
                    }
                });
            }
        }
        let mut out = Output {
            state,
            reason,
            ascend,
            activity: if delta > 0.0 { delta } else { 0.0 },
            ..Output::default()
        };
        if let Some((start, end, start_utc, end_utc)) = self.rise {
            out.flags |= 1 | ((start_utc as u64) << 2) | ((end_utc as u64) << 3);
            out.rise_start = start;
            out.rise_end = end;
        }
        if let Some((start, end, start_utc, end_utc)) = self.trigger {
            out.flags |= 2 | ((start_utc as u64) << 4) | ((end_utc as u64) << 5);
            out.trigger_start = start;
            out.trigger_end = end;
        }
        if state == 5 {
            self.rise = None;
            self.trigger = None;
            self.rising_streak = 0;
            self.triggered_streak = 0;
            self.decay_streak = 0;
            self.missing = 0;
        }
        Ok(out)
    }
}

pub struct Session {
    config: Config,
    histories: Vec<History>,
    scratch: Vec<f64>,
}

#[no_mangle]
pub extern "C" fn rq_trigger_abi_version() -> u32 {
    1
}
#[no_mangle]
pub extern "C" fn rq_trigger_sessions() -> u64 {
    SESSIONS.load(Ordering::Relaxed) as u64
}
#[no_mangle]
pub extern "C" fn rq_trigger_calls() -> u64 {
    CALLS.load(Ordering::Relaxed) as u64
}

/// # Safety
/// config points to an initialized Config valid for the duration of this call.
#[no_mangle]
pub unsafe extern "C" fn rq_trigger_create(config: *const Config) -> *mut Session {
    if config.is_null() {
        return std::ptr::null_mut();
    }
    let pointer = std::panic::catch_unwind(|| {
        Box::into_raw(Box::new(Session {
            config: unsafe { *config },
            histories: Vec::new(),
            scratch: Vec::new(),
        }))
    })
    .unwrap_or(std::ptr::null_mut());
    if !pointer.is_null() {
        SESSIONS.fetch_add(1, Ordering::Relaxed);
    }
    pointer
}

/// # Safety
/// session must be null or a live pointer returned by create, destroyed once.
#[no_mangle]
pub unsafe extern "C" fn rq_trigger_destroy(session: *mut Session) {
    if !session.is_null() {
        drop(unsafe { Box::from_raw(session) });
        SESSIONS.fetch_sub(1, Ordering::Relaxed);
    }
}

/// # Safety
/// session is exclusively owned by the caller for this call.
#[no_mangle]
pub unsafe extern "C" fn rq_trigger_reset_station(session: *mut Session, station: u64) -> i32 {
    if session.is_null() {
        return 1;
    }
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let session = unsafe { &mut *session };
        if station < session.histories.len() as u64 {
            session.histories[station as usize] = History::default();
        }
        0
    }))
    .unwrap_or(5)
}

/// # Safety
/// session is live and exclusively owned. inputs/output are non-overlapping
/// aligned arrays of count elements, valid for the entire call. No input is retained.
#[no_mangle]
pub unsafe extern "C" fn rq_trigger_process(
    session: *mut Session,
    inputs: *const Input,
    count: usize,
    output: *mut Output,
) -> i32 {
    if session.is_null() || (count != 0 && (inputs.is_null() || output.is_null())) {
        return 1;
    }
    if count > MAX_BATCH {
        return 3;
    }
    if count == 0 {
        return 0;
    }
    CALLS.fetch_add(1, Ordering::Relaxed);
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let session = unsafe { &mut *session };
        let inputs = unsafe { std::slice::from_raw_parts(inputs, count) };
        let output = unsafe { std::slice::from_raw_parts_mut(output, count) };
        for (row, out) in inputs.iter().zip(output) {
            if row.station >= MAX_BATCH as u64 {
                return 3;
            }
            let index = row.station as usize;
            if session.histories.len() <= index {
                session.histories.resize_with(index + 1, History::default);
            }
            match session.histories[index].update(row, session.config, &mut session.scratch) {
                Ok(value) => *out = value,
                Err(status) => return status,
            }
        }
        0
    }))
    .unwrap_or(5)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn layouts_match_abi_and_nulls_are_rejected() {
        assert_eq!(std::mem::size_of::<Config>(), 72);
        assert_eq!(std::mem::size_of::<Input>(), 40);
        assert_eq!(std::mem::size_of::<Output>(), 64);
        assert!(unsafe { rq_trigger_create(std::ptr::null()) }.is_null());
        assert_eq!(
            unsafe {
                rq_trigger_process(
                    std::ptr::null_mut(),
                    std::ptr::null(),
                    0,
                    std::ptr::null_mut(),
                )
            },
            1
        );
    }
}
