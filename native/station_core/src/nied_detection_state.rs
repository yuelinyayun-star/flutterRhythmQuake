//! NIED display detection owner: KA association, 10.5 s holds, expiry,
//! grid preparation, notification decisions and immutable UI projections.
use crate::{ka_detector::Detector, station_json::pack_value};
use serde_json::{json, Value};
use std::fmt::Write as _;
use std::{
    collections::{HashMap, VecDeque},
    ffi::c_void,
    ptr,
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc, Condvar, Mutex,
    },
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};
static SESSIONS: AtomicU64 = AtomicU64::new(0);
static WORKERS: AtomicU64 = AtomicU64::new(0);
static FRAMES: AtomicU64 = AtomicU64::new(0);
const ROW: usize = 8;
#[repr(C)]
struct DartObject {
    kind: i32,
    value: [i64; 5],
}
type Post = unsafe extern "C" fn(i64, *mut DartObject) -> bool;

#[derive(Clone, PartialEq)]
struct View {
    active: bool,
    state: i64,
    reason: String,
}
struct State {
    detector: Detector,
    xy: Vec<f64>,
    codes: Vec<String>,
    ids: Vec<i64>,
    view: Vec<View>,
    missing: Vec<bool>,
    sent: Vec<View>,
    until: Vec<Option<i64>>,
    info: Vec<i64>,
    clock: i64,
    source_time: Option<(i64, bool)>,
    decimal: [f64; 2],
    has_grid: bool,
    previous: i64,
    alert_previous: i64,
    notified_one: bool,
    notified_two: bool,
    focused: bool,
    event: Option<(i64, bool)>,
    signature: Option<Value>,
    layer: String,
    pending_layer: Option<String>,
    pending: Option<i64>,
    queue: VecDeque<Vec<u8>>,
    closed: bool,
}
fn shindo(level: i64) -> i64 {
    if level < 0 {
        -1
    } else if level <= 7 {
        0
    } else if level <= 15 {
        (level - 6) / 2
    } else if level <= 17 {
        5
    } else if level <= 19 {
        6
    } else {
        7
    }
}
fn stamp() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_micros() as i64
}
impl State {
    fn new(xy: Vec<f64>, rows: Vec<(String, bool, i64, String, i64)>) -> Self {
        let view = rows
            .iter()
            .map(|r| View {
                active: r.1,
                state: r.2,
                reason: r.3.clone(),
            })
            .collect::<Vec<_>>();
        Self {
            detector: crate::nied_topology::display_detector(&xy),
            xy,
            ids: rows.iter().map(|r| r.4).collect(),
            codes: rows.into_iter().map(|r| r.0).collect(),
            sent: view.clone(),
            until: vec![None; view.len()],
            missing: vec![false; view.len()],
            info: vec![0; view.len() * 6],
            view,
            clock: 0,
            source_time: None,
            decimal: [0.0; 2],
            has_grid: false,
            previous: -1,
            alert_previous: -1,
            notified_one: false,
            notified_two: false,
            focused: false,
            event: None,
            signature: None,
            layer: String::new(),
            pending_layer: None,
            pending: None,
            queue: VecDeque::new(),
            closed: false,
        }
    }
    fn expire(&mut self) -> bool {
        let mut expired = false;
        for i in 0..self.view.len() {
            if self.until[i].is_some_and(|t| t <= self.clock) {
                self.view[i].active = false;
                self.until[i] = None;
                expired = true;
            }
        }
        if expired && self.pending.is_none() {
            self.pending = Some(self.clock.saturating_add(16));
        }
        expired
    }
    fn next(&self) -> Option<i64> {
        self.until
            .iter()
            .flatten()
            .copied()
            .chain(self.pending)
            .min()
    }
    fn changes(&mut self) -> Vec<Value> {
        let mut rows = vec![];
        for (i, (value, previous)) in self.view.iter().zip(&mut self.sent).enumerate() {
            if value != previous {
                rows.push(json!([i, value.active, value.state, value.reason]));
                *previous = value.clone();
            }
        }
        rows
    }
    fn emit(&mut self, actions: Vec<Value>, projection: Option<Value>) {
        let changes = self.changes();
        let layer = self.pending_layer.take();
        if !changes.is_empty() || !actions.is_empty() || projection.is_some() || layer.is_some() {
            self.queue
                .push_back(pack_value(&json!([changes, actions, projection, layer])));
        }
    }
    fn advance(&mut self) {
        let expired = self.expire();
        if self.pending.is_some_and(|t| t <= self.clock) {
            self.project();
        } else if expired {
            self.emit(vec![], None);
        }
    }
    fn apply(&mut self, rows: &[i64], sensitivity: i64) -> Result<(), ()> {
        self.expire();
        for i in 0..self.view.len() {
            // Station deltas must also acknowledge sampler invalidations even
            // if this frame immediately detects the station again.
            self.sent[i].active = rows[i * ROW + 7] & 1 != 0;
            self.missing[i] = rows[i * ROW + 7] & 2 != 0;
            // The existing raw sampler explicitly invalidates a station on a
            // missing/reset observation. Accept that command before detection;
            // never keep a native hold alive behind an invalidated Dart view.
            if rows[i * ROW + 7] & 1 == 0 {
                self.view[i].active = false;
                self.until[i] = None;
            }
            if !self.view[i].active {
                self.view[i].state = 0;
                self.view[i].reason.clear();
            }
            let from = i * ROW;
            let to = i * 6;
            self.info[to] = rows[from];
            self.info[to + 1] = rows[from + 1];
            self.info[to + 2] = rows[from + 2];
            self.info[to + 3] = i64::from(self.view[i].active);
            self.info[to + 4] = rows[from + 3];
            self.info[to + 5] = rows[from + 4];
        }
        // Latest original source timestamp, retaining the first UTC/local flag
        // on equal instants, exactly like the previous ordered fold.
        self.source_time = None;
        for row in rows.chunks_exact(ROW) {
            if row[5] != i64::MIN && self.source_time.is_none_or(|v| row[5] > v.0) {
                self.source_time = Some((row[5], row[6] != 0));
            }
        }
        let strongest =
            self.detector
                .detect_policy(&self.info, sensitivity, self.has_grid, true, 0)?;
        if strongest >= 0 {
            let i = strongest as usize;
            for axis in 0..2 {
                let fraction = (self.xy[i * 2 + axis] + 180.0).rem_euclid(1.0);
                self.decimal[axis] = (fraction * 10.0).round() / 10.0;
            }
        }
        for &index in &self.detector.active {
            let i = index as usize;
            let v = shindo(self.info[i * 6]);
            self.view[i] = View {
                active: true,
                state: if v >= 4 {
                    6
                } else if v >= 1 {
                    5
                } else if v >= 0 {
                    1
                } else {
                    0
                },
                reason: "kanameishi-chain".into(),
            };
            self.until[i] = Some(self.clock.saturating_add(10500));
        }
        self.project();
        FRAMES.fetch_add(1, Ordering::Relaxed);
        Ok(())
    }
    fn project(&mut self) {
        self.pending = None;
        let mut cells = Vec::<(String, f64, f64, i64)>::new();
        let mut cell_index = HashMap::new();
        let mut entries = Vec::<usize>::new();
        let (mut weak, mut detected, mut strong, mut maximum) = (0, 0, 0, -1);
        for i in 0..self.view.len() {
            if self.view[i].active {
                let level = self.info[i * 6];
                let value = shindo(level);
                maximum = maximum.max(level);
                if value >= 4 {
                    strong += 1;
                } else if value >= 1 {
                    detected += 1;
                } else if value == 0 {
                    weak += 1;
                }
                entries.push(i);
                if level < 0 {
                    continue;
                }
                let lat = (self.xy[i * 2] - self.decimal[0]).round() + self.decimal[0];
                let lng = (self.xy[i * 2 + 1] - self.decimal[1]).round() + self.decimal[1];
                let key = format!("{lat:?},{lng:?}");
                if let Some(&position) = cell_index.get(&key) {
                    let cell: &mut (String, f64, f64, i64) = &mut cells[position];
                    cell.3 = cell.3.max(level);
                } else {
                    cell_index.insert(key.clone(), cells.len());
                    cells.push((key, lat, lng, level));
                }
            }
        }
        self.has_grid = !cells.is_empty();
        if !self.has_grid {
            self.decimal = [0.0; 2];
        }
        // Dart compares Unicode code units rather than UTF-8 bytes.
        entries.sort_by(|&a, &b| {
            self.info[b * 6].cmp(&self.info[a * 6]).then_with(|| {
                self.codes[a]
                    .encode_utf16()
                    .cmp(self.codes[b].encode_utf16())
            })
        });
        let current = cells.iter().map(|c| c.3).max().map_or(-1, shindo);
        let rise = current >= 0 && current > self.alert_previous;
        self.alert_previous = if current < 0 { -1 } else { current };
        let mut actions = vec![];
        if rise {
            actions.push(json!([0, current]));
            if (1..=3).contains(&current) && !self.notified_one {
                actions.push(json!([1, "揺れを検出", "揺れに注意してください。"]));
                self.notified_one = true;
            } else if current >= 4 && !self.notified_two {
                actions.push(json!([1, "強い揺れを検出", "強い揺れに警戒してください。"]));
                self.notified_one = true;
                self.notified_two = true;
            }
            if current >= 1 && !self.focused {
                actions.push(json!([2]));
                self.focused = true;
            }
        } else if current == -1 && self.previous >= 0 {
            actions.push(json!([3]));
            self.notified_one = false;
            self.notified_two = false;
            self.focused = false;
        }
        self.previous = current;
        let stage = if entries.is_empty() {
            0
        } else if strong > 0 {
            3
        } else if detected > 0 {
            2
        } else {
            1
        };
        let observed = self.source_time.unwrap_or_else(|| (stamp(), false));
        let event_state = if stage == 0 {
            if self.event.is_some() {
                4
            } else {
                0
            }
        } else {
            stage
        };
        if stage != 0 && self.event.is_none() {
            self.event = Some(observed);
        }
        let started = self.event;
        if stage == 0 {
            self.event = None;
        }
        let max = if maximum >= 0 { shindo(maximum) } else { -1 };
        let stage_name = ["idle", "weak", "detected", "strong"][stage];
        let mut layer = format!(
            "{}|{stage_name}:{weak}:{detected}:{strong}:{max}",
            self.ids.len()
        );
        let mut sorted_cells = cells.iter().collect::<Vec<_>>();
        // Grid keys consist of ASCII coordinates; same order as Dart strings.
        sorted_cells.sort_by(|a, b| a.0.cmp(&b.0));
        for cell in sorted_cells {
            write!(&mut layer, ":{}={}", cell.0, cell.3).unwrap();
        }
        for i in 0..self.ids.len() {
            write!(
                &mut layer,
                "|{}:{}:{}",
                self.ids[i],
                self.info[i * 6],
                self.view[i].state
            )
            .unwrap();
            if self.missing[i] {
                layer.push_str(":missing");
            }
        }
        if layer != self.layer {
            self.pending_layer = Some(layer.clone());
            self.layer = layer;
        }
        let grid_signature = cells.iter().map(|c| json!([c.0, c.3])).collect::<Vec<_>>();
        let station_signature = entries
            .iter()
            .map(|&i| {
                json!([
                    self.codes[i],
                    self.info[i * 6],
                    shindo(self.info[i * 6]),
                    self.view[i].state
                ])
            })
            .collect::<Vec<_>>();
        let signature = json!([
            stage,
            entries.len(),
            strong,
            max,
            grid_signature,
            station_signature
        ]);
        let projection = if self.signature.as_ref() == Some(&signature) {
            None
        } else {
            self.signature = Some(signature);
            Some(json!([
                stage,
                weak,
                detected,
                strong,
                max,
                entries
                    .iter()
                    .map(|&i| json!([
                        i,
                        self.info[i * 6],
                        shindo(self.info[i * 6]),
                        self.view[i].state,
                        self.view[i].reason
                    ]))
                    .collect::<Vec<_>>(),
                cells
                    .iter()
                    .map(|c| json!([c.0, c.1, c.2, c.3, (c.3 as f64 + 0.5 - 7.0) / 2.0]))
                    .collect::<Vec<_>>(),
                observed.0,
                observed.1,
                started.map(|t| json!([t.0, t.1])),
                event_state,
                if stage == 0 {
                    0.0
                } else {
                    weak as f64 + detected as f64 * 2.0 + strong as f64 * 3.0
                }
            ]))
        };
        self.emit(actions, projection);
    }
    fn reset(&mut self, clear: bool) {
        self.decimal = [0.0; 2];
        self.has_grid = false;
        self.previous = -1;
        self.alert_previous = -1;
        self.notified_one = false;
        self.notified_two = false;
        self.focused = false;
        self.event = None;
        self.signature = None;
        self.layer.clear();
        self.pending_layer = None;
        self.pending = None;
        self.queue.clear();
        if clear {
            for i in 0..self.view.len() {
                self.view[i] = View {
                    active: false,
                    state: 0,
                    reason: String::new(),
                };
                self.until[i] = None;
            }
        }
        self.sent = self.view.clone();
    }
}
struct Shared {
    state: Mutex<State>,
    wake: Condvar,
    start: Instant,
    manual: bool,
    port: i64,
    post: Option<Post>,
}
struct Owner {
    shared: Arc<Shared>,
    thread: Option<thread::JoinHandle<()>>,
    delivered: Vec<u8>,
}
fn notify(s: &Shared) {
    if let Some(post) = s.post {
        let mut value = DartObject {
            kind: 3,
            value: [1, 0, 0, 0, 0],
        };
        unsafe {
            post(s.port, &mut value);
        }
    }
}
fn run(s: Arc<Shared>) {
    WORKERS.fetch_add(1, Ordering::Relaxed);
    let mut state = s.state.lock().unwrap();
    loop {
        if state.closed {
            break;
        }
        if state.queue.len() >= 128 {
            state = s.wake.wait(state).unwrap();
            continue;
        }
        let now = s.start.elapsed().as_millis().min(i64::MAX as u128) as i64;
        state.clock = now;
        let before = state.queue.is_empty();
        state.advance();
        if before && !state.queue.is_empty() {
            notify(&s);
        }
        if let Some(deadline) = state.next() {
            let wait = Duration::from_millis(deadline.saturating_sub(now).max(1) as u64);
            state = s.wake.wait_timeout(state, wait).unwrap().0;
        } else {
            state = s.wake.wait(state).unwrap();
        }
    }
    WORKERS.fetch_sub(1, Ordering::Relaxed);
}

#[no_mangle]
pub unsafe extern "C" fn rq_nied_detection_create(
    xy: *const f64,
    count: usize,
    catalogue: *const u8,
    len: usize,
    port: i64,
    post: *const c_void,
    manual: u8,
) -> *mut c_void {
    if count > 100_000
        || (count > 0 && xy.is_null())
        || catalogue.is_null()
        || len > 16 * 1024 * 1024
    {
        return ptr::null_mut();
    }
    std::panic::catch_unwind(|| {
        let rows = unsafe { std::slice::from_raw_parts(catalogue, len) };
        let Ok(rows) = serde_json::from_slice::<Vec<(String, bool, i64, String, i64)>>(rows) else {
            return ptr::null_mut();
        };
        if rows.len() != count {
            return ptr::null_mut();
        }
        let xy = if count == 0 {
            vec![]
        } else {
            unsafe { std::slice::from_raw_parts(xy, count * 2) }.to_vec()
        };
        if xy.iter().any(|v| !v.is_finite()) {
            return ptr::null_mut();
        }
        let shared = Arc::new(Shared {
            state: Mutex::new(State::new(xy, rows)),
            wake: Condvar::new(),
            start: Instant::now(),
            manual: manual != 0,
            port,
            post: if post.is_null() {
                None
            } else {
                Some(unsafe { std::mem::transmute::<*const c_void, Post>(post) })
            },
        });
        let worker = if manual == 0 {
            let cloned = shared.clone();
            match thread::Builder::new()
                .name("rq-nied-detection".into())
                .stack_size(256 * 1024)
                .spawn(move || run(cloned))
            {
                Ok(v) => Some(v),
                Err(_) => return ptr::null_mut(),
            }
        } else {
            None
        };
        SESSIONS.fetch_add(1, Ordering::Relaxed);
        Box::into_raw(Box::new(Owner {
            shared,
            thread: worker,
            delivered: vec![],
        }))
        .cast()
    })
    .unwrap_or(ptr::null_mut())
}
#[no_mangle]
pub unsafe extern "C" fn rq_nied_detection_apply(
    owner: *mut c_void,
    rows: *const i64,
    count: usize,
    sensitivity: i64,
    clock: i64,
) -> i32 {
    if owner.is_null() || (count > 0 && rows.is_null()) || !(1..=3).contains(&sensitivity) {
        return 1;
    }
    let owner = unsafe { &mut *owner.cast::<Owner>() };
    let shared = &owner.shared;
    let mut state = shared.state.lock().unwrap();
    if state.codes.len() != count || state.closed {
        return 2;
    }
    if state.queue.len() >= 128 {
        return 3;
    }
    let rows = if count == 0 {
        &[]
    } else {
        unsafe { std::slice::from_raw_parts(rows, count * ROW) }
    };
    state.clock = if shared.manual {
        clock
    } else {
        shared.start.elapsed().as_millis() as i64
    };
    let before = state.queue.is_empty();
    if state.apply(rows, sensitivity).is_err() {
        return 4;
    }
    if before && !state.queue.is_empty() {
        notify(shared);
    }
    shared.wake.notify_one();
    0
}
#[no_mangle]
pub unsafe extern "C" fn rq_nied_detection_tick(owner: *mut c_void, clock: i64) -> i32 {
    if owner.is_null() {
        return 1;
    }
    let owner = unsafe { &mut *owner.cast::<Owner>() };
    if !owner.shared.manual {
        return 2;
    }
    let mut state = owner.shared.state.lock().unwrap();
    state.clock = clock;
    let before = state.queue.is_empty();
    state.advance();
    if before && !state.queue.is_empty() {
        notify(&owner.shared);
    }
    0
}
#[no_mangle]
pub unsafe extern "C" fn rq_nied_detection_take(owner: *mut c_void, len: *mut usize) -> *const u8 {
    if owner.is_null() || len.is_null() {
        return ptr::null();
    }
    let owner = unsafe { &mut *owner.cast::<Owner>() };
    let Some(bytes) = owner.shared.state.lock().unwrap().queue.pop_front() else {
        unsafe { *len = 0 };
        return ptr::null();
    };
    owner.delivered = bytes;
    unsafe { *len = owner.delivered.len() };
    owner.shared.wake.notify_one();
    owner.delivered.as_ptr()
}
#[no_mangle]
pub unsafe extern "C" fn rq_nied_detection_reset(owner: *mut c_void, clear: u8) {
    if !owner.is_null() {
        let owner = unsafe { &mut *owner.cast::<Owner>() };
        owner.shared.state.lock().unwrap().reset(clear != 0);
        owner.shared.wake.notify_one();
    }
}
#[no_mangle]
pub unsafe extern "C" fn rq_nied_detection_destroy(owner: *mut c_void) {
    if owner.is_null() {
        return;
    }
    let mut owner = unsafe { Box::from_raw(owner.cast::<Owner>()) };
    owner.shared.state.lock().unwrap().closed = true;
    owner.shared.wake.notify_one();
    if let Some(worker) = owner.thread.take() {
        let _ = worker.join();
    }
    SESSIONS.fetch_sub(1, Ordering::Relaxed);
}
#[no_mangle]
pub extern "C" fn rq_nied_detection_sessions() -> u64 {
    SESSIONS.load(Ordering::Relaxed)
}
#[no_mangle]
pub extern "C" fn rq_nied_detection_workers() -> u64 {
    WORKERS.load(Ordering::Relaxed)
}
#[no_mangle]
pub extern "C" fn rq_nied_detection_frames() -> u64 {
    FRAMES.load(Ordering::Relaxed)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn expiry_keeps_station_transition_separate_from_coalesced_projection() {
        let mut state = State::new(
            vec![35.0, 140.0],
            vec![("test".into(), false, 0, String::new(), 0)],
        );
        let mut row = [0; ROW];
        row[0] = 10;
        row[1] = 30f64.to_bits() as i64;
        row[2] = 4;
        row[5] = 1_000_000;
        row[6] = 1;
        state.apply(&row, 2).unwrap();
        assert!(state.view[0].active);
        state.queue.clear();
        state.clock = 10500;
        state.advance();
        assert!(!state.view[0].active);
        assert!(state.pending.is_some());
        state.clock = 10516;
        state.advance();
        assert!(state.event.is_none());
        assert_eq!(state.previous, -1);
    }

    #[test]
    fn sampler_invalidation_is_acknowledged_when_detection_immediately_resumes() {
        let mut state = State::new(
            vec![35.0, 140.0],
            vec![("test".into(), false, 0, String::new(), 0)],
        );
        let mut row = [0; ROW];
        row[0] = 10;
        row[1] = 30f64.to_bits() as i64;
        row[2] = 4;
        row[5] = 1_000_000;
        state.apply(&row, 2).unwrap();
        state.queue.clear();
        state.clock = 20000;
        // The sampler invalidated its view, but these untouched observations
        // satisfy the detector again. Publish true even when last sent was true.
        state.apply(&row, 2).unwrap();
        let bytes = state.queue.pop_front().unwrap();
        let result = crate::station_json::unpack_value(&bytes, 0).unwrap();
        assert_eq!(result[0][0], json!([0, true, 5, "kanameishi-chain"]));
    }
}
