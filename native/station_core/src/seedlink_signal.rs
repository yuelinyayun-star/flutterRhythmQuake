//! Continuous SeedLink signal state. Coefficients are original Dart doubles.
use std::ffi::c_void;
use std::sync::atomic::{AtomicU64, Ordering};

static SESSIONS: AtomicU64 = AtomicU64::new(0);
static CALLS: AtomicU64 = AtomicU64::new(0);

struct Signal {
    rate: f64,
    coefficients: [f64; 15],
    delays: [[f64; 2]; 3],
    last: Option<i64>,
    progress: i64,
    offset_count: i64,
    ratio_count: i64,
    records: i64,
    offset_sum: f64,
    ratio_sum: f64,
    offset: f64,
    short: f64,
    medium: f64,
    third: f64,
    long: f64,
    event_timer: i64,
    event_start: Option<i64>,
    ready: bool,
    has_previous: bool,
    peak: f64,
    reset_peak: bool,
    second: Option<i64>,
    history: [f64; 59],
    head: usize,
    count: usize,
    history_max: f64,
    ratio: Option<f64>,
    event: bool,
}

impl Default for Signal {
    fn default() -> Self {
        Self {
            rate: 0.0,
            coefficients: [0.0; 15],
            delays: [[0.0; 2]; 3],
            last: None,
            progress: 0,
            offset_count: 0,
            ratio_count: 0,
            records: 0,
            offset_sum: 0.0,
            ratio_sum: 0.0,
            offset: 0.0,
            short: 0.0,
            medium: 0.0,
            third: 0.0,
            long: 0.0,
            event_timer: 0,
            event_start: None,
            ready: false,
            has_previous: false,
            peak: 0.0,
            reset_peak: true,
            second: None,
            history: [0.0; 59],
            head: 0,
            count: 0,
            history_max: 0.0,
            ratio: None,
            event: false,
        }
    }
}

impl Signal {
    fn reset(&mut self, rate: f64, coefficients: &[f64]) {
        // Dart's reset intentionally retains the last accepted sample timestamp.
        let last = self.last;
        *self = Self::default();
        self.last = last;
        self.rate = rate;
        self.reset_peak = true;
        self.coefficients.copy_from_slice(coefficients);
    }

    fn filter(&mut self, mut sample: f64) -> f64 {
        for stage in 0..3 {
            let c = &self.coefficients[stage * 5..stage * 5 + 5];
            let d = &mut self.delays[stage];
            let w = sample - c[0] * d[0] - c[1] * d[1];
            sample = c[2] * w + c[3] * d[0] + c[4] * d[1];
            d[1] = d[0];
            d[0] = w;
        }
        sample
    }

    fn finish_second(&mut self) {
        if self.peak <= 0.0 || !self.peak.is_finite() {
            return;
        }
        let evicted = self.history[self.head];
        self.history[self.head] = self.peak;
        self.head = (self.head + 1) % self.history.len();
        if self.count < self.history.len() {
            self.count += 1;
        }
        if self.peak >= self.history_max {
            self.history_max = self.peak;
        } else if evicted == self.history_max {
            self.history_max = 0.0;
            for &value in &self.history[..self.count] {
                if value > self.history_max {
                    self.history_max = value;
                }
            }
        }
        self.reset_peak = true;
    }

    fn accept(&mut self, samples: &[i64], rate: f64, begin: i64, coefficients: &[f64]) {
        if samples.is_empty() || !rate.is_finite() || rate <= 0.0 {
            return;
        }
        let step = 1_000_000.0 / rate;
        let end = begin + ((samples.len() - 1) as f64 * step).round() as i64;
        if self.last.is_some_and(|last| end <= last) {
            return;
        }
        if self.rate <= 10.0
            || (self.rate - rate).abs() > 0.2
            || self.last.is_some_and(|last| begin - last > 1_000_000)
        {
            self.reset(rate, coefficients);
        }
        if self.rate <= 10.0 {
            self.last = Some(end);
            return;
        }
        if self.ready {
            self.records += 1;
        }
        for (i, &raw) in samples.iter().enumerate() {
            let micros = begin + (i as f64 * step).round() as i64;
            if self.last.is_some_and(|last| micros <= last) {
                continue;
            }
            self.last = Some(micros);
            let time = micros / 1000;
            let second = micros / 1_000_000;
            if self.second.is_some_and(|previous| previous != second) {
                self.finish_second();
            }
            self.second = Some(second);
            let value = raw as f64;
            if !self.ready {
                if self.progress as f64 <= 4.0 * rate {
                    self.offset_sum += value;
                    self.offset_count += 1;
                    if self.progress as f64 >= rate {
                        let filtered = self
                            .filter(value - self.offset_sum / self.offset_count as f64)
                            .abs();
                        self.ratio_sum += filtered;
                        self.ratio_count += 1;
                        self.long = self.ratio_sum / self.ratio_count as f64;
                    }
                } else if self.progress as f64 <= 14.0 * rate {
                    let filtered = self
                        .filter(value - self.offset_sum / self.offset_count as f64)
                        .abs();
                    self.long -= (self.long - filtered) / (rate * 6.0);
                } else {
                    self.offset = self.offset_sum / self.offset_count as f64;
                    self.short = self.long;
                    self.medium = self.long;
                    self.third = self.long;
                    self.long *= 0.75;
                    self.ready = true;
                }
                self.progress += 1;
                continue;
            }
            let filtered = self.filter(value - self.offset).abs();
            self.short -= (self.short - filtered) / (rate * 0.5);
            self.medium -= (self.medium - filtered) / (rate * 6.0);
            self.third -= (self.third - filtered) / (rate * 30.0);
            if self.short / self.long < 4.0 {
                self.long -= (self.long - filtered) / (rate * 200.0);
            }
            let ratio = self.short / self.long;
            if self.event_start.is_none()
                && self.has_previous
                && self.short / self.third > 3.0
                && ((ratio >= 4.75 * 1.3 && time - self.event_timer > 200)
                    || (ratio >= 4.75 * 2.05 && time - self.event_timer > 100))
            {
                self.event_start = Some(time);
            }
            if ratio < 4.75 {
                self.event_timer = time;
            }
            if let Some(start) = self.event_start {
                let duration = time - start;
                if duration >= 300_000 {
                    // A timed-out event resets with the current packet's rate.
                    self.reset(rate, coefficients);
                    continue;
                }
                if (duration >= 7000 && self.medium < self.third * 0.95)
                    || (duration >= 1000
                        && ((duration < 7500 && self.short < self.long * 1.25)
                            || self.short < self.medium * 0.12))
                {
                    self.event_start = None;
                }
            }
            if ratio.is_finite() && ratio >= 0.0 && (ratio > self.peak || self.reset_peak) {
                self.peak = ratio * 1.25;
                self.reset_peak = false;
            }
            self.has_previous = true;
        }
        self.ratio = if self.ready && self.records >= 3 && self.history_max > 0.0 {
            Some(self.history_max)
        } else {
            None
        };
        self.event = self.ready && self.records >= 3 && self.event_start.is_some();
    }
}

#[no_mangle]
pub extern "C" fn rq_seedlink_signal_abi_version() -> u32 {
    1
}
#[no_mangle]
pub extern "C" fn rq_seedlink_signal_sessions() -> u64 {
    SESSIONS.load(Ordering::Relaxed)
}
#[no_mangle]
pub extern "C" fn rq_seedlink_signal_calls() -> u64 {
    CALLS.load(Ordering::Relaxed)
}
#[no_mangle]
pub extern "C" fn rq_seedlink_signal_create() -> *mut c_void {
    let result = Box::into_raw(Box::new(Signal::default())).cast();
    SESSIONS.fetch_add(1, Ordering::Relaxed);
    result
}

/// # Safety
/// Owner is idle, input has count int64 samples and coefficients has 15 doubles.
/// Output has 2 doubles (nullable ratio represented by NaN, event 0/1).
/// Buffers are aligned, non-overlapping and borrowed only during this call.
#[no_mangle]
pub unsafe extern "C" fn rq_seedlink_signal_accept(
    handle: *mut c_void,
    input: *const i64,
    count: usize,
    rate: f64,
    begin: i64,
    coefficients: *const f64,
    output: *mut f64,
) -> i32 {
    if handle.is_null()
        || coefficients.is_null()
        || output.is_null()
        || (count > 0 && input.is_null())
    {
        return 1;
    }
    if count > 65535 {
        return 3;
    }
    std::panic::catch_unwind(|| unsafe {
        let state = &mut *handle.cast::<Signal>();
        let samples = if count == 0 {
            &[]
        } else {
            std::slice::from_raw_parts(input, count)
        };
        let coefficients = std::slice::from_raw_parts(coefficients, 15);
        state.accept(samples, rate, begin, coefficients);
        *output = state.ratio.unwrap_or(f64::NAN);
        *output.add(1) = if state.event { 1.0 } else { 0.0 };
        CALLS.fetch_add(1, Ordering::Relaxed);
        0
    })
    .unwrap_or(5)
}

/// # Safety
/// Destroy an idle owner created here exactly once.
#[no_mangle]
pub unsafe extern "C" fn rq_seedlink_signal_destroy(handle: *mut c_void) {
    if !handle.is_null() {
        unsafe {
            drop(Box::from_raw(handle.cast::<Signal>()));
        }
        SESSIONS.fetch_sub(1, Ordering::Relaxed);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn reset_retains_timestamp_and_unsupported_rate_keeps_empty_state() {
        let mut state = Signal::default();
        state.last = Some(10);
        state.reset(100.0, &[0.0; 15]);
        assert_eq!(state.last, Some(10));
        state.accept(&[1, 2], 10.0, 2_000_000, &[0.0; 15]);
        assert_eq!(state.last, Some(2_100_000));
        assert_eq!(state.ratio, None);
        assert!(!state.event);
    }
}
