//! KMA/TREM source actors. Network bytes, clocks, catalogues, history, detection
//! and display projection stay native. Dart only receives bounded UI snapshots.
#![cfg(any(windows, target_os = "android"))]
use serde_json::{json, Value};
#[path = "palert_display.rs"]
mod palert_display;
#[path = "palert_inference.rs"]
mod palert_inference;
#[path = "palert_state.rs"]
mod palert_state;
#[path = "replay_block.rs"]
mod replay_block;
#[path = "seisjs_state.rs"]
mod seisjs_state;
#[path = "trem_protocol.rs"]
mod trem_protocol;
use std::{
    collections::{HashMap, VecDeque},
    ffi::{c_void, CString},
    ptr,
    sync::{
        atomic::{AtomicU64, AtomicUsize, Ordering},
        mpsc, Arc, Mutex, OnceLock,
    },
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

#[repr(C)]
pub struct DartObject {
    kind: i32,
    value: [i64; 5],
}
impl DartObject {
    /// Pointer-bearing Dart API fields use intptr_t, not int64_t. Keep the
    /// existing x64 layout while packing arrays correctly on Android ARMv7.
    fn prepared(kind: i32, value: [i64; 5]) -> Self {
        #[cfg(target_pointer_width = "32")]
        let mut value = value;
        #[cfg(target_pointer_width = "32")]
        match kind {
            6 => {
                value[0] = ((value[1] as u32 as u64) << 32 | value[0] as u32 as u64) as i64;
                value[1] = 0;
            }
            7 => {
                let data = value[2];
                value[0] = ((value[1] as u32 as u64) << 32 | value[0] as u32 as u64) as i64;
                value[1] = data as u32 as i64;
                value[2] = 0;
            }
            _ => {}
        }
        Self { kind, value }
    }
}
type Post = unsafe extern "C" fn(i64, *mut DartObject) -> bool;
enum Command {
    Wake,
    Input(Vec<u8>, i64),
    PackedInput(Arc<Vec<u8>>, u32, i64),
    Settings(Value),
    Close,
}
struct Output {
    prepared: Option<Arc<Vec<u8>>>,
    delivered_prepared: Arc<Vec<u8>>,
    original_tree: Arc<Vec<u8>>,
    archive_tree: Arc<Vec<u8>>,
    pinned_original_tree: Arc<Vec<u8>>,
    pinned_archive_tree: Arc<Vec<u8>>,
    delivered_signals: Vec<i32>,
    palert: Option<Arc<palert_display::Frame>>,
    pinned_palert: Option<Arc<palert_display::Frame>>,
    deliveries: HashMap<u64, Arc<palert_display::Frame>>,
    next_delivery: u64,
    snapshot: Option<Vec<u8>>,
    signals: Vec<i32>,
    delivered: Vec<u8>,
    original: Arc<Vec<u8>>,
    pinned_original: Arc<Vec<u8>>,
    archive: Arc<Vec<u8>>,
    pinned_archive: Arc<Vec<u8>>,
}
struct Session {
    tx: mpsc::Sender<Command>,
    out: Mutex<Output>,
    port: i64,
    post: Post,
    testing: bool,
    native_display: bool,
    prepared_tree: bool,
    source_display_only: bool,
    packed_input: Mutex<(u64, Arc<Vec<u8>>)>,
}
static SESSIONS: OnceLock<Mutex<HashMap<u64, Arc<Session>>>> = OnceLock::new();
static NEXT: AtomicU64 = AtomicU64::new(1);
static WORKERS: AtomicUsize = AtomicUsize::new(0);
fn registry() -> &'static Mutex<HashMap<u64, Arc<Session>>> {
    SESSIONS.get_or_init(Default::default)
}
fn session(id: u64) -> Option<Arc<Session>> {
    registry().lock().unwrap().get(&id).cloned()
}
fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_millis() as i64
}
unsafe extern "C" fn wake(port: i64, _: *mut c_void) -> bool {
    session(port as u64).is_some_and(|s| s.tx.send(Command::Wake).is_ok())
}
fn number(v: &Value) -> Option<f64> {
    v.as_f64()
        .or_else(|| v.as_str()?.parse().ok())
        .filter(|n| n.is_finite())
}
fn text(v: &Value) -> String {
    v.as_str()
        .map(str::to_owned)
        .unwrap_or_else(|| v.to_string())
}
fn boolean(v: &Value) -> bool {
    match v {
        Value::Bool(b) => *b,
        Value::Number(_) => number(v) != Some(0.0),
        Value::String(s) => !matches!(
            s.trim().to_lowercase().as_str(),
            "" | "0" | "false" | "null"
        ),
        _ => false,
    }
}
fn days(y: i64, m: i64, d: i64) -> Option<i64> {
    if !(1..=12).contains(&m) {
        return None;
    }
    let leap = y % 4 == 0 && (y % 100 != 0 || y % 400 == 0);
    let limit = [
        31,
        if leap { 29 } else { 28 },
        31,
        30,
        31,
        30,
        31,
        31,
        30,
        31,
        30,
        31,
    ][m as usize - 1];
    if d < 1 || d > limit {
        return None;
    }
    let y = y - i64::from(m <= 2);
    let era = y.div_euclid(400);
    let yo = y - era * 400;
    let mp = m + if m > 2 { -3 } else { 9 };
    let dy = (153 * mp + 2) / 5 + d - 1;
    Some(era * 146097 + yo * 365 + yo / 4 - yo / 100 + dy - 719468)
}
fn timestamp(v: &Value, compact: bool, local_offset: i64) -> Option<i64> {
    if !compact {
        if let Some(n) = number(v) {
            return Some(if n > 100000000000.0 {
                n as i64
            } else {
                n as i64 * 1000
            });
        }
    }
    let s = text(v);
    let b = s.as_bytes();
    let part = |a: usize, z: usize| s.get(a..z)?.parse::<i64>().ok();
    let (y, m, d, h, mi, se, end) = if compact {
        if b.len() != 14 {
            return None;
        }
        (
            part(0, 4)?,
            part(4, 6)?,
            part(6, 8)?,
            part(8, 10)?,
            part(10, 12)?,
            part(12, 14)?,
            14,
        )
    } else {
        if b.len() < 19 {
            return None;
        }
        (
            part(0, 4)?,
            part(5, 7)?,
            part(8, 10)?,
            part(11, 13)?,
            part(14, 16)?,
            part(17, 19)?,
            19,
        )
    };
    if h > 23 || mi > 59 || se > 59 {
        return None;
    }
    let mut t = (days(y, m, d)? * 86400 + h * 3600 + mi * 60 + se) * 1000;
    let mut i = end;
    if b.get(i) == Some(&b'.') {
        i += 1;
        let start = i;
        while b.get(i).is_some_and(u8::is_ascii_digit) {
            i += 1;
        }
        let mut frac = s.get(start..i)?.chars().take(3).collect::<String>();
        while frac.len() < 3 {
            frac.push('0');
        }
        t += frac.parse::<i64>().ok()?;
    }
    if local_offset == i64::MIN && b.get(i).is_none() {
        return local_epoch(y, m, d, h, mi, se, t.rem_euclid(1000));
    }
    let offset = match b.get(i) {
        Some(b'Z' | b'z') => 0,
        Some(b'+' | b'-') => {
            let sign = if b[i] == b'+' { 1 } else { -1 };
            let hh = part(i + 1, i + 3)?;
            let start = if b.get(i + 3) == Some(&b':') {
                i + 4
            } else {
                i + 3
            };
            let mm = part(start, start + 2)?;
            if hh > 23 || mm > 59 {
                return None;
            }
            sign * (hh * 60 + mm) * 60000
        }
        _ => local_offset,
    };
    Some(t - offset)
}
#[repr(C)]
#[cfg(windows)]
struct SystemTimeFields {
    year: u16,
    month: u16,
    weekday: u16,
    day: u16,
    hour: u16,
    minute: u16,
    second: u16,
    millis: u16,
}
#[link(name = "kernel32")]
#[cfg(windows)]
extern "system" {
    fn TzSpecificLocalTimeToSystemTimeEx(
        zone: *const c_void,
        local: *const SystemTimeFields,
        utc: *mut SystemTimeFields,
    ) -> i32;
}
#[cfg(windows)]
fn local_epoch(y: i64, m: i64, d: i64, h: i64, mi: i64, se: i64, ms: i64) -> Option<i64> {
    let local = SystemTimeFields {
        year: u16::try_from(y).ok()?,
        month: m as u16,
        weekday: 0,
        day: d as u16,
        hour: h as u16,
        minute: mi as u16,
        second: se as u16,
        millis: ms as u16,
    };
    let mut utc = SystemTimeFields {
        year: 0,
        month: 0,
        weekday: 0,
        day: 0,
        hour: 0,
        minute: 0,
        second: 0,
        millis: 0,
    };
    if unsafe { TzSpecificLocalTimeToSystemTimeEx(ptr::null(), &local, &mut utc) } == 0 {
        return None;
    }
    Some(
        (days(utc.year as i64, utc.month as i64, utc.day as i64)? * 86400
            + utc.hour as i64 * 3600
            + utc.minute as i64 * 60
            + utc.second as i64)
            * 1000
            + utc.millis as i64,
    )
}
#[cfg(target_os = "android")]
use crate::android_platform::local_epoch;
fn iso(ms: i64) -> String {
    // UTC ISO text is a display/archive projection; the original stays untouched.
    let z = ms.div_euclid(86400000) + 719468;
    let era = z.div_euclid(146097);
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let mut y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = mp + if mp < 10 { 3 } else { -9 };
    y += i64::from(m <= 2);
    let rem = ms.rem_euclid(86400000);
    format!(
        "{y:04}-{m:02}-{d:02}T{:02}:{:02}:{:02}.{:03}Z",
        rem / 3600000,
        rem / 60000 % 60,
        rem / 1000 % 60,
        rem % 1000
    )
}
fn kma_shindo(l: i32) -> i32 {
    match l {
        i32::MIN..=-1 => -1,
        0..=3 => 0,
        4 => 1,
        5..=6 => 2,
        7 => 3,
        8 => 4,
        9..=10 => 5,
        11 => 6,
        _ => 7,
    }
}
fn trem_level(i: f64) -> i32 {
    if i < -3.0 {
        -1
    } else if i == -3.0 {
        0
    } else if i >= 6.5 {
        20
    } else {
        (i * 2.0 + 7.0).floor() as i32
    }
}
fn trem_shindo(l: i32) -> i32 {
    if l < 0 {
        -1
    } else if l <= 7 {
        0
    } else {
        ((l - 6) / 2).min(7)
    }
}
#[derive(Clone)]
struct Kma {
    lat: f64,
    lon: f64,
    value: i32,
    history: VecDeque<i32>,
    activity: i32,
    hold: i32,
    ascend: i32,
    until: i64,
    updated: Option<i64>,
}
impl Kma {
    fn new(lat: f64, lon: f64) -> Self {
        Self {
            lat,
            lon,
            value: -3,
            history: VecDeque::with_capacity(60),
            activity: -1,
            hold: -1,
            ascend: 0,
            until: 0,
            updated: None,
        }
    }
}
struct Engine {
    palert: palert_state::PAlert,
    seisjs: seisjs_state::SeisJs,
    archive_revision: u64,
    next_display: Instant,
    kind: String,
    source: String,
    kma: Vec<Kma>,
    adj: Vec<Vec<usize>>,
    trem: HashMap<String, Value>,
    rows: Vec<Value>,
    last: Option<i64>,
    received: Option<i64>,
    connected: bool,
    status: String,
    sensitivity: i32,
    hold: usize,
    previous: i32,
    notified1: bool,
    notified2: bool,
    signals: Vec<i32>,
    original: Value,
    changed: bool,
    frames: u64,
    grid_decimal: Option<(f64, f64)>,
    grids: Vec<(f64, f64, i32)>,
}
impl Engine {
    fn new(settings: &Value) -> Self {
        let mut palert = palert_state::PAlert::default();
        palert.set_inference(settings["inference"] == true);
        palert.replay_mode = settings["sourceDisplayOnly"] == true;
        Self {
            palert,
            seisjs: seisjs_state::SeisJs::default(),
            archive_revision: 0,
            next_display: Instant::now(),
            kind: settings["kind"].as_str().unwrap_or("kma").into(),
            source: if matches!(settings["kind"].as_str(), Some("cwa" | "seisjs")) {
                settings["kind"].as_str().unwrap().into()
            } else {
                settings["source"].as_str().unwrap_or("pews").into()
            },
            kma: vec![],
            adj: vec![],
            trem: HashMap::new(),
            rows: vec![],
            last: None,
            received: None,
            connected: false,
            status: "connecting".into(),
            sensitivity: settings["sensitivity"].as_i64().unwrap_or(2).clamp(1, 3) as i32,
            hold: settings["hold"].as_u64().unwrap_or(1).clamp(1, 60) as usize,
            previous: -1,
            notified1: false,
            notified2: false,
            signals: vec![],
            original: json!({}),
            changed: true,
            frames: 0,
            grid_decimal: None,
            grids: vec![],
        }
    }
    fn status(&mut self, s: &str) {
        if self.status != s {
            self.status = s.into();
            self.connected = s == "connected";
            self.changed = true;
        }
    }
    fn signal(&mut self, current: i32) {
        if self.kind == "kma" {
            if current >= 0 && current > self.previous {
                self.signals.push(current);
            } else if current < 0 && self.previous >= 0 {
                self.signals.push(-1);
            }
        } else if current > self.previous {
            if (1..=3).contains(&current) && !self.notified1 {
                self.notified1 = true;
                self.signals.push(current);
            } else if current >= 4 && !self.notified2 {
                self.notified1 = true;
                self.notified2 = true;
                self.signals.push(current);
            }
        } else if current == -1 && self.previous >= 0 {
            self.notified1 = false;
            self.notified2 = false;
            self.signals.push(-1);
        }
        self.previous = current;
    }
    fn expire(&mut self, t: i64) {
        if self.kind == "palert" {
            self.changed |= self.palert.expire(t, self.sensitivity);
            self.signals.append(&mut self.palert.signals);
            return;
        }
        if self.kind == "seisjs" {
            self.changed |= self.seisjs.expire(t);
            return;
        }
        if self.kind != "kma" {
            return;
        }
        let mut changed = false;
        for s in &mut self.kma {
            if s.until > 0 && s.until <= t {
                s.until = 0;
                changed = true;
            }
        }
        if changed {
            let max = self
                .kma
                .iter()
                .filter(|s| s.until > t)
                .map(|s| s.activity)
                .max()
                .unwrap_or(-1);
            self.signal(kma_shindo(max));
            self.changed = true;
        }
    }
    fn input(&mut self, v: &Value, t: i64) -> bool {
        if self.kind == "palert" {
            let revision = self.palert.revision;
            let accepted = self.palert.input(v, t, self.sensitivity);
            self.signals.append(&mut self.palert.signals);
            self.changed |= self.palert.revision != revision;
            return accepted;
        }
        if self.kind == "seisjs" {
            let Some(time) = self.seisjs.input(v, t) else {
                return false;
            };
            self.last = Some(time);
            self.received = Some(t);
            self.frames += 1;
            self.original["data"] = v.clone();
            self.changed = true;
            self.status("connected");
            true
        } else if self.kind == "kma" {
            self.kma_input(v, t)
        } else {
            self.trem_input(v, t)
        }
    }
    fn kma_input(&mut self, v: &Value, t: i64) -> bool {
        let Some(typ) = v["type"].as_str() else {
            return false;
        };
        if matches!(typ, "initial_stations" | "kma_stations_update")
            || (self.source == "jian" && typ == "kma-station" && v["stations"].is_array())
        {
            let Some(rows) = v["stations"].as_array().filter(|a| !a.is_empty()) else {
                return false;
            };
            let mut next = vec![];
            for row in rows {
                let lat = number(
                    row.get("latitude")
                        .or_else(|| row.get("lat"))
                        .unwrap_or(&Value::Null),
                );
                let lon = number(
                    row.get("longitude")
                        .or_else(|| row.get("lon"))
                        .unwrap_or(&Value::Null),
                );
                let (Some(lat), Some(lon)) = (lat, lon) else {
                    return false;
                };
                if !(-90.0..=90.0).contains(&lat) || !(-180.0..=180.0).contains(&lon) {
                    return false;
                }
                next.push(Kma::new(lat, lon));
            }
            self.original["metadata"] = v.clone();
            if self.kma.len() == next.len()
                && self
                    .kma
                    .iter()
                    .zip(&next)
                    .all(|(a, b)| a.lat == b.lat && a.lon == b.lon)
            {
                if !matches!(self.source.as_str(), "whews" | "jian") {
                    // PEWS initial metadata starts a new observation run even
                    // when its catalogue is unchanged. Reuse geometry only.
                    self.kma = next;
                    self.last = None;
                    self.previous = -1;
                    self.grid_decimal = None;
                    self.grids.clear();
                }
                return false;
            }
            self.kma = next;
            self.adj = vec![vec![]; self.kma.len()];
            self.last = None;
            self.previous = -1;
            // Store only 30km neighbours; no redundant N*N distance matrix.
            for i in 0..self.kma.len() {
                let mut neighbours = vec![];
                for j in 0..self.kma.len() {
                    let a = &self.kma[i];
                    let b = &self.kma[j];
                    let dlat = (b.lat - a.lat).to_radians();
                    let dlon = (b.lon - a.lon).to_radians();
                    let h = (dlat / 2.0).sin().powi(2)
                        + a.lat.to_radians().cos()
                            * b.lat.to_radians().cos()
                            * (dlon / 2.0).sin().powi(2);
                    let d = 6371.0 * 2.0 * h.sqrt().atan2((1.0 - h).sqrt());
                    if d <= 30.0 {
                        neighbours.push((j, d));
                    }
                }
                neighbours.sort_by(|a, b| a.1.total_cmp(&b.1));
                self.adj[i] = neighbours.into_iter().map(|a| a.0).collect();
            }
            return false;
        }
        let data = if self.source == "jian" { v } else { &v["Data"] };
        let stamp = if self.source == "jian" {
            timestamp(&data["time"], true, 0)
        } else {
            timestamp(
                &data["timestamp"],
                false,
                if self.source == "whews" {
                    9 * 3600000
                } else {
                    i64::MIN
                },
            )
        };
        let Some(stamp) = stamp else {
            return false;
        };
        if self.last.is_some_and(|l| stamp <= l)
            || (self.source == "jian" && (t - stamp > 90000 || stamp - t > 15000))
        {
            return false;
        }
        let Some(values) = data["mmi"]
            .as_array()
            .filter(|a| !a.is_empty() && a.len() == self.kma.len())
        else {
            return false;
        };
        let parsed: Option<Vec<i32>> = values
            .iter()
            .map(|v| {
                let n = number(v)?;
                if self.source == "jian" && !v.is_number() {
                    return None;
                }
                let x = n.round() as i32;
                if !(-3..=11).contains(&x) || x == -3 {
                    None
                } else {
                    Some(x)
                }
            })
            .collect();
        let Some(parsed) = parsed else {
            return false;
        };
        let gap = self.last.map(|l| stamp - l).unwrap_or(0);
        let missing = if gap > 1000 {
            ((gap as f64 / 1000.0).round() as usize)
                .saturating_sub(1)
                .min(60)
        } else {
            0
        };
        for (s, value) in self.kma.iter_mut().zip(parsed) {
            for _ in 0..missing {
                s.history.push_front(-1);
            }
            s.history.truncate(60);
            if gap > 10000 {
                s.until = 0;
                s.ascend = 0;
                s.activity = -1;
                s.hold = -1;
            }
            s.value = value;
            s.updated = Some(t);
            s.history.push_front(value + 2);
            s.history.truncate(60);
            s.activity = s.history.iter().take(12).copied().max().unwrap_or(-1);
            let past = if s.history.iter().skip(12).filter(|&&x| x >= 0).count() >= 36 {
                s.history.iter().skip(12).copied().max().unwrap_or(-1)
            } else {
                -1
            };
            s.ascend = if past >= 0 {
                s.history.iter().take(12).filter(|&&x| x > past).count() as i32
            } else {
                0
            };
            s.hold = s
                .history
                .iter()
                .take(self.hold)
                .copied()
                .max()
                .unwrap_or(-1);
        }
        if gap > 10000 {
            self.signal(-1);
        }
        let mut activated = vec![false; self.kma.len()];
        for i in 0..self.kma.len() {
            let s = &self.kma[i];
            let active = s.until > t;
            let mut flag = active && s.ascend > 0;
            if !flag && (active || s.ascend > 0) {
                let ns = &self.adj[i];
                let count = ns.len() as f64;
                let (mut int1, mut int2, mut asc1, mut asc2) = (0, 0, 0, 0);
                for &j in ns {
                    let n = &self.kma[j];
                    if n.until > t || n.ascend > 0 {
                        if n.activity >= 3 {
                            int1 += 1;
                        }
                        if n.activity >= 4 {
                            int2 += 1;
                        }
                    }
                    if n.ascend >= 1 {
                        asc1 += 1;
                    }
                    if n.ascend >= 2 {
                        asc2 += 1;
                    }
                }
                let pass =
                    |n: i32, ratio: f64, min: f64| n as f64 >= (ratio * count).max(min).ceil();
                flag = if self.sensitivity == 1 {
                    pass(int1, 0.6, 4.0) || pass(int2, 0.2, 2.0) || pass(asc2, 0.7, 4.0)
                } else {
                    pass(int1, 0.5, 3.0)
                        || pass(int2, 0.15, 2.0)
                        || pass(asc2, 0.6, 4.0)
                        || (self.sensitivity == 3 && pass(asc1, 0.8, 5.0))
                };
            }
            if flag {
                for &j in &self.adj[i] {
                    if !activated[j] && (self.kma[j].until > t || self.kma[j].ascend > 0) {
                        self.kma[j].until = t + 12500;
                        activated[j] = true;
                    }
                }
                if !activated[i] {
                    self.kma[i].until = t + 12500;
                    activated[i] = true;
                }
            }
        }
        let max = self
            .kma
            .iter()
            .filter(|s| s.until > t)
            .map(|s| s.activity)
            .max()
            .unwrap_or(-1);
        self.signal(kma_shindo(max));
        self.last = Some(stamp);
        self.received = Some(t);
        self.original["data"] = v.clone();
        self.frames += 1;
        self.changed = true;
        self.status("connected");
        true
    }
    fn trem_input(&mut self, v: &Value, t: i64) -> bool {
        if let Some(csv) = v.as_str() {
            let mut next = HashMap::new();
            for item in trem_protocol::catalogue(csv) {
                let mut s = self.trem.get(&item.id).cloned().unwrap_or_else(|| json!({
                    "id":item.id,"pga":0,"pgv":0,"intensity":-3,
                    "alertIntensity":-3.1,"hasAlert":false,"lastUpdate":null
                }));
                s["code"] = json!(item.code);
                s["net"] = json!(item.net);
                s["work"] = json!(item.work);
                s["coordinate"] = json!({"lat":item.lat,"lng":item.lon});
                next.insert(item.id, s);
            }
            if !next.is_empty() {
                self.trem = next;
                self.original["metadata"] = v.clone();
            }
            return false;
        }
        let v1 = v["stations"].is_object();
        if v.get("station").is_none() && !v1 {
            let Some(map) = v.as_object() else {
                return false;
            };
            let mut next = HashMap::new();
            for (id, item) in map {
                let Some(info) = item["info"].as_array().and_then(|a| a.last()) else {
                    continue;
                };
                let lat = number(&info["lat"]).unwrap_or(0.0);
                let lon = number(&info["lon"]).unwrap_or(0.0);
                if lat == 0.0 && lon == 0.0 {
                    continue;
                }
                let mut s=self.trem.get(id).cloned().unwrap_or_else(||json!({"id":id,"pga":0,"pgv":0,"intensity":-3,"alertIntensity":-3.1,"hasAlert":false,"lastUpdate":null}));
                s["code"] = json!(number(&info["code"]).unwrap_or(0.0) as i64);
                s["net"] = json!(item["net"].as_str().unwrap_or(""));
                s["work"] = json!(item["work"] == true);
                s["coordinate"] = json!({"lat":lat,"lng":lon});
                next.insert(id.clone(), s);
            }
            if !next.is_empty() {
                self.trem = next;
                self.original["metadata"] = v.clone();
            }
            return false;
        }
        let Some(stamp) = timestamp(&v[if v1 { "ts" } else { "time" }], false, i64::MIN) else {
            return false;
        };
        if self.last.is_some_and(|l| stamp <= l) {
            return false;
        }
        let Some(map) = v[if v1 { "stations" } else { "station" }].as_object() else {
            return false;
        };
        let mut rows = vec![];
        let mut max = -1;
        for (id, values) in map {
            if !values.is_object() {
                continue;
            }
            let Some(s) = self.trem.get_mut(id) else {
                continue;
            };
            if s["work"] != true {
                continue;
            }
            if v1 && !values["i"].is_number() { continue; }
            for (from, to) in [
                ("pga", "pga"),
                ("pgv", "pgv"),
                ("i", "intensity"),
                ("I", "alertIntensity"),
            ] {
                if let Some(n) = number(&values[from]) {
                    s[to] = json!(n);
                }
            }
            let alert = if v1 {
                values["alert"] == true || values["alert"] == 1 || values["alert"] == "1"
            } else { boolean(&values["alert"]) };
            if v1 {
                let Some(i) = number(&values["i"]) else { continue; };
                s["alertIntensity"] = json!(i);
            }
            s["hasAlert"] = json!(alert);
            s["gridLevel"] = json!(trem_level(
                number(&s[if alert { "alertIntensity" } else { "intensity" }]).unwrap_or(-3.1)
            ));
            s["lastUpdate"] = json!(iso(t));
            if alert {
                max = max.max(trem_level(number(&s["alertIntensity"]).unwrap_or(-3.1)));
            }
            rows.push(s.clone());
        }
        if rows.is_empty() {
            return false;
        }
        rows.sort_by(|a, b| {
            let val = |x: &Value| {
                number(
                    &x[if x["hasAlert"] == true {
                        "alertIntensity"
                    } else {
                        "intensity"
                    }],
                )
                .unwrap_or(-3.1)
            };
            val(b).total_cmp(&val(a))
        });
        self.rows = rows;
        self.signal(trem_shindo(max));
        self.last = Some(stamp);
        self.received = Some(t);
        self.original["data"] = v.clone();
        self.frames += 1;
        self.changed = true;
        self.status("connected");
        true
    }
    fn clear_trem(&mut self) {
        self.signal(-1);
        for s in self.trem.values_mut() {
            for key in ["pga", "pgv"] {
                s[key] = json!(0);
            }
            for key in ["intensity", "alertIntensity"] {
                s[key] = json!(-3.1);
            }
            s["hasAlert"] = json!(false);
            s["gridLevel"] = json!(-1);
            s["lastUpdate"] = Value::Null;
        }
        self.rows = self.trem.values().cloned().collect();
        self.last = None;
        self.received = None;
        self.changed = true;
    }
    fn refresh_grids(&mut self, t: i64) {
        if matches!(self.kind.as_str(), "seisjs" | "palert") {
            return;
        }
        let active: Vec<(f64, f64, i32, f64)> = if self.kind == "kma" {
            self.kma
                .iter()
                .filter(|s| s.until > t)
                .map(|s| (s.lat, s.lon, s.activity, s.activity as f64))
                .collect()
        } else {
            self.rows
                .iter()
                .filter(|s| s["hasAlert"] == true)
                .map(|s| {
                    (
                        number(&s["coordinate"]["lat"]).unwrap(),
                        number(&s["coordinate"]["lng"]).unwrap(),
                        trem_level(number(&s["alertIntensity"]).unwrap()),
                        number(&s["alertIntensity"]).unwrap(),
                    )
                })
                .collect()
        };
        if active.is_empty() {
            self.grids.clear();
            self.grid_decimal = None;
            return;
        }
        if self.grid_decimal.is_none() {
            let mut best = &active[0];
            for row in &active[1..] {
                if row.3 > best.3 {
                    best = row;
                }
            }
            let decimal = |v: f64| ((v + 180.0).rem_euclid(1.0) * 10.0).round() / 10.0;
            self.grid_decimal = Some((decimal(best.0), decimal(best.1)));
        }
        let (dlat, dlon) = self.grid_decimal.unwrap();
        if self.kind != "kma" {
            self.grids.clear();
        }
        for (lat, lon, level, _) in active {
            if level < 0 {
                continue;
            }
            let lat = (lat - dlat).round() + dlat;
            let lon = (lon - dlon).round() + dlon;
            if let Some(g) = self.grids.iter_mut().find(|g| g.0 == lat && g.1 == lon) {
                g.2 = g.2.max(level);
            } else {
                self.grids.push((lat, lon, level));
            }
        }
    }
    fn snapshot(&self, t: i64) -> Value {
        if self.kind == "seisjs" {
            let mut snapshot = self.seisjs.snapshot(t);
            snapshot["kind"] = json!(self.kind);
            snapshot["source"] = json!(self.source);
            snapshot["status"] = json!(self.status);
            snapshot["dataTime"] = json!(self.last.map(iso));
            snapshot["frames"] = json!(self.frames);
            return snapshot;
        }
        let rows = if self.kind == "kma" {
            self.kma.iter().enumerate().map(|(i,s)|json!({"id":i,"coordinate":{"lat":s.lat,"lng":s.lon},"intensity":s.value,"activityLevel":s.activity,"holdLevel":s.hold,"ascend":s.ascend,"isActive":s.until>t,"lastUpdate":s.updated.map(iso)})).collect::<Vec<_>>()
        } else {
            self.rows.clone()
        };
        let mut signature = String::new();
        let mut automation = vec![];
        for s in &rows {
            if self.kind == "kma" {
                signature.push_str(&format!(
                    "|{}:{}:{}:{}:{}:{}:{}",
                    s["coordinate"],
                    s["id"],
                    s["intensity"],
                    s["activityLevel"],
                    s["holdLevel"],
                    s["ascend"],
                    s["isActive"]
                ));
            } else {
                signature.push_str(&format!(
                    "|{}:{}:{}:{}:{}:{}:{}",
                    s["coordinate"],
                    s["id"],
                    s[if s["hasAlert"] == true {
                        "alertIntensity"
                    } else {
                        "intensity"
                    }],
                    s["alertIntensity"],
                    s["intensity"],
                    s["hasAlert"],
                    s["work"]
                ));
            }
            if s[if self.kind == "kma" {
                "isActive"
            } else {
                "hasAlert"
            }] != true
            {
                continue;
            }
            let intensity = if self.kind == "kma" {
                (s["holdLevel"].as_i64().unwrap_or(-1) - 2).clamp(0, 11) as f64
            } else {
                number(&s["alertIntensity"]).unwrap_or(-3.1)
            };
            let level = if self.kind == "kma" {
                kma_shindo(s["holdLevel"].as_i64().unwrap_or(-1) as i32)
            } else {
                let x = (trem_level(intensity) as f64 + 0.5 - 7.0) / 2.0;
                [0.5, 1.5, 2.5, 3.5, 4.5, 5.0, 5.5, 6.0, 6.5]
                    .iter()
                    .filter(|&&n| x >= n)
                    .count() as i32
            };
            automation.push(json!({"id":if self.kind=="kma" {text(&s["id"])}else{s["id"].as_str().unwrap_or("").into()},"name":if self.kind=="kma" {text(&s["id"])}else{text(&s["code"])},"level":level,"intensity":intensity,"coordinate":s["coordinate"],"time":s["lastUpdate"],"strong":level>=4}));
        }
        json!({"kind":self.kind,"source":self.source,"stations":rows,"dataTime":self.last.map(iso),"receivedAt":iso(t),"status":self.status,"signature":signature,"automation":automation,"frames":self.frames,"grids":self.grids.iter().map(|&(lat,lon,level)|json!({"center":[lat,lon],"level":level,"points":[[lat-0.495,lon-0.495],[lat+0.495,lon-0.495],[lat+0.495,lon+0.495],[lat-0.495,lon+0.495]]})).collect::<Vec<_>>()})
    }
    fn publish(&mut self, s: &Session, t: i64) {
        if !self.changed && self.signals.is_empty() {
            return;
        }
        if self.kind == "seisjs" && Instant::now() < self.next_display {
            return;
        }
        self.next_display = Instant::now() + Duration::from_millis(16);
        self.refresh_grids(t);
        let revision = if self.kind == "palert" {
            self.palert.revision
        } else {
            self.seisjs.revision
        };
        let archive_changed =
            !matches!(self.kind.as_str(), "seisjs" | "palert") || self.archive_revision != revision;
        self.archive_revision = revision;
        if self.kind == "palert" && s.native_display {
            let prepared = Arc::new(if s.source_display_only {
                self.palert.source_frame(t)
            } else {
                self.palert.prepared(t, archive_changed)
            });
            let mut out = s.out.lock().unwrap();
            let notify = out.palert.is_none();
            out.palert = Some(prepared);
            out.signals.append(&mut self.signals);
            self.changed = false;
            if notify {
                let mut object = DartObject {
                    kind: 3,
                    value: [1, 0, 0, 0, 0],
                };
                unsafe {
                    (s.post)(s.port, &mut object);
                }
            }
            return;
        }
        let snapshot = if self.kind == "palert" {
            Value::Null
        } else {
            let mut frame = self.snapshot(t);
            frame["dataChanged"] = json!(archive_changed);
            frame
        };
        if s.prepared_tree {
            let prepared = Arc::new(crate::station_json::pack_value(&snapshot));
            let archive = if archive_changed {
                let mut archive = json!({"kind":self.kind,"source":self.source,"dataTime":snapshot["dataTime"],"stations":snapshot["stations"],"receivedAt":snapshot["receivedAt"]});
                if self.kind == "kma" {
                    for (row, station) in archive["stations"]
                        .as_array_mut()
                        .unwrap()
                        .iter_mut()
                        .zip(&self.kma)
                    {
                        row["recentLevel"] = json!(station.history);
                    }
                }
                Some((
                    Arc::new(crate::station_json::pack_value(&self.original)),
                    Arc::new(crate::station_json::pack_value(&archive)),
                ))
            } else {
                None
            };
            let mut out = s.out.lock().unwrap();
            let notify = out.prepared.is_none();
            out.prepared = Some(prepared);
            out.signals.append(&mut self.signals);
            if let Some((original, archive)) = archive {
                out.original_tree = original;
                out.archive_tree = archive;
            }
            self.changed = false;
            if notify {
                let mut object = DartObject {
                    kind: 3,
                    value: [1, 0, 0, 0, 0],
                };
                unsafe {
                    (s.post)(s.port, &mut object);
                }
            }
            return;
        }
        let mut bytes = if self.kind == "palert" {
            self.palert.encoded_snapshot(t, archive_changed)
        } else {
            serde_json::to_vec(&snapshot).unwrap()
        };
        // P-Alert history is exactly this prepared frame. Reuse its serialized
        // form instead of cloning every station's JSON tree and serializing it
        // a second time on every observation and expiry.
        let palert_archive =
            (archive_changed && self.kind == "palert").then(|| Arc::new(bytes.clone()));
        bytes.pop(); // Append only the small pending effect list under the lock.
        let archive = if archive_changed {
            let mut archive = if self.kind == "palert" {
                Value::Null
            } else {
                json!({"kind":self.kind,"source":self.source,"dataTime":snapshot["dataTime"],"stations":snapshot["stations"],"receivedAt":snapshot["receivedAt"]})
            };
            if self.kind == "kma" {
                for (row, station) in archive["stations"]
                    .as_array_mut()
                    .unwrap()
                    .iter_mut()
                    .zip(&self.kma)
                {
                    row["recentLevel"] = json!(station.history);
                }
            }
            Some((
                Arc::new(if self.kind == "palert" {
                    self.palert.original.encode()
                } else {
                    serde_json::to_vec(&self.original).unwrap()
                }),
                palert_archive.unwrap_or_else(|| Arc::new(serde_json::to_vec(&archive).unwrap())),
            ))
        } else {
            None
        };
        let mut out = s.out.lock().unwrap();
        let notify = out.snapshot.is_none();
        out.signals.append(&mut self.signals);
        bytes.extend_from_slice(b",\"signals\":");
        bytes.extend(serde_json::to_vec(&out.signals).unwrap());
        bytes.push(b'}');
        out.snapshot = Some(bytes);
        if let Some((original, archive)) = archive {
            out.original = original;
            out.archive = archive;
        }
        self.changed = false;
        if notify {
            let mut o = DartObject {
                kind: 3,
                value: [1, 0, 0, 0, 0],
            };
            unsafe {
                (s.post)(s.port, &mut o);
            }
        }
    }
}

// Network orchestration shares the existing native transports; their wake ports
// target this Rust actor, never a Dart raw-response callback.
struct Request {
    id: u64,
    role: &'static str,
    bytes: Vec<u8>,
    started: i64,
    status: u16,
    sse: bool,
    trem_stream: trem_protocol::Stream,
}
static SOCKET_OWNERS: OnceLock<Mutex<HashMap<String, u64>>> = OnceLock::new();
fn socket_owners() -> &'static Mutex<HashMap<String, u64>> {
    SOCKET_OWNERS.get_or_init(Default::default)
}
fn claim_socket_owner(kind: &str, id: u64) -> bool {
    let mut owners = socket_owners().lock().unwrap();
    if let Some(&previous) = owners.get(kind) {
        if previous != id {
            if let Some(owner) = session(previous) {
                let _ = owner.tx.send(Command::Close);
            }
            return false;
        }
    }
    owners.insert(kind.into(), id);
    true
}
fn release_socket_owner(kind: &str, id: u64) {
    let mut owners = socket_owners().lock().unwrap();
    if owners.get(kind) == Some(&id) {
        owners.remove(kind);
    }
}

fn ws_rejection_status(source: &str, code: u32) -> Option<&'static str> {
    if !matches!(source, "whews" | "jian") {
        return None;
    }
    let status = if code & 0xffff0000 == 0x10000 {
        code & 0xffff
    } else {
        code
    };
    if matches!(status, 401 | 403 | 404 | 429 | 4401 | 4403 | 4008 | 1008) {
        Some(if source == "whews" && matches!(status, 401 | 4401) {
            "unauthorized"
        } else {
            "error"
        })
    } else {
        None
    }
}

struct Runtime {
    id: u64,
    engine: Engine,
    s: Arc<Session>,
    rx: mpsc::Receiver<Command>,
    settings: Value,
    ws: u64,
    http: u64,
    requests: Vec<Request>,
    retry: i64,
    heartbeat: i64,
    last_message: i64,
    opened_at: i64,
    alive: bool,
    unauthorized: bool,
    shutdown_failed: bool,
    retry_seconds: i64,
    host: usize,
    failures: i32,
    stream_retry: i64,
    poll_at: i64,
    metadata_at: i64,
    token: String,
    refresh: String,
    expires: i64,
    login_pending: bool,
    testing: bool,
}
impl Runtime {
    fn whews_endpoint(&self) -> String {
        format!("wss://{}/ws/kma_station", crate::whews_connection::host(self.host))
    }
    fn connection_diagnostic(&self, event: &str, details: Value) {
        if self.engine.source != "whews" {
            return;
        }
        let Ok(path) = std::env::var("RHYTHMQUAKE_WHEWS_LOG") else {
            return;
        };
        if path.is_empty() {
            return;
        }
        let mut line = json!({"timeUnixMs":now(),"source":"WHEWS","endpoint":self.whews_endpoint(),"transport":"native_station","event":event,"details":details}).to_string();
        if let Some(token) = self.settings["token"].as_str().filter(|t| !t.is_empty()) {
            line = line.replace(token, "[REDACTED]");
        }
        line.push('\n');
        use std::io::Write;
        match std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(path)
            .and_then(|mut file| file.write_all(line.as_bytes()))
        {
            Ok(()) => {}
            Err(error) => eprintln!("Connection diagnostics write failed: {:?}", error.kind()),
        }
    }
    fn palert_request(&mut self, role: &'static str, t: i64) {
        if self.requests.iter().any(|r| r.role == role) {
            return;
        }
        let endpoint = &self.settings["endpoint"];
        let host = CString::new(
            endpoint["host"]
                .as_str()
                .unwrap_or("palert.earth.sinica.edu.tw"),
        )
        .unwrap();
        let path = CString::new(endpoint["path"].as_str().unwrap_or("/graphql/")).unwrap();
        let secure = endpoint["secure"] != false;
        let query = if role == "metadata" {
            "query ($staFilter: staList_filter_choices) { stationList(staFilter: $staFilter) { staInfos timestamp } }"
        } else {
            "query ($recordTime: Float!, $token: String!) { pga: realtimePGA(recordTime: $recordTime, token: $token, type: 0) { timestamp dataVals } pgv: realtimePGA(recordTime: $recordTime, token: $token, type: 1) { timestamp dataVals } }"
        };
        let body=serde_json::to_vec(&json!({"query":query,"variables":if role=="metadata"{json!({"staFilter":"onlineAll"})}else{json!({"recordTime":0,"token":""})}})).unwrap();
        let headers=c"Accept: application/json, text/plain, */*\r\nContent-Type: application/json;charset=UTF-8\r\nOrigin: https://palert.earth.sinica.edu.tw\r\nReferer: https://palert.earth.sinica.edu.tw/realtime\r\nUser-Agent: FlutterRhythmQuake/1.0\r\n";
        let id = unsafe {
            crate::http_transport::rq_http_open(
                self.http,
                host.as_ptr().cast(),
                path.as_ptr().cast(),
                c"POST".as_ptr().cast(),
                headers.as_ptr().cast(),
                body.as_ptr(),
                body.len(),
                endpoint["port"]
                    .as_u64()
                    .unwrap_or(if secure { 443 } else { 80 }) as u32,
                u32::from(secure) | 8,
                self.id as i64,
                std::mem::transmute::<
                    unsafe extern "C" fn(i64, *mut c_void) -> bool,
                    unsafe extern "C" fn(i64, *mut crate::http_transport::DartObject) -> bool,
                >(wake),
            )
        };
        self.requests.push(Request {
            id,
            role,
            bytes: vec![],
            started: t,
            status: 0,
            sse: false,
            trem_stream: trem_protocol::Stream::default(),
        });
    }
    fn ws_open(&mut self, t: i64) {
        if self.unauthorized {
            return;
        }
        let source = self.engine.source.as_str();
        let token = self.settings["token"].as_str().unwrap_or("").trim();
        if source == "whews" && token.trim().is_empty() {
            self.engine.status("unauthorized");
            self.unauthorized = true;
            return;
        }
        if source == "whews" {
            match crate::whews_auth_block::blocked_endpoint(token, &self.whews_endpoint()) {
                Ok(None) => {}
                result => {
                    self.unauthorized = true;
                    self.retry = i64::MAX;
                    let code = result.ok().flatten();
                    self.engine.status(if matches!(code, Some(401 | 4401)) {
                        "unauthorized"
                    } else {
                        "error"
                    });
                    self.connection_diagnostic(
                        "start_blocked",
                        json!({"code":code,"cause":"previous_rejection_or_retry_storage"}),
                    );
                    return;
                }
            }
        }
        if !claim_socket_owner(&self.engine.kind, self.id) {
            self.retry = t + 100;
            return;
        }
        let (mut host, mut path) = match source {
            "seisjs" => ("seisjs.wolfx.jp".into(), "/all_seis".into()),
            "jian" => (crate::jian_connection::api_host(self.host).to_string(), "/kma-station".into()),
            "whews" => {
                let escaped = token
                    .bytes()
                    .map(|b| {
                        if b.is_ascii_alphanumeric() || b"-._~".contains(&b) {
                            (b as char).to_string()
                        } else {
                            format!("%{b:02X}")
                        }
                    })
                    .collect::<String>();
                (
                    crate::whews_connection::host(self.host).into(),
                    format!("/ws/kma_station?token={escaped}"),
                )
            }
            "fan" => (
                if self.host % 2 == 0 {
                    "ws.fanstudio.tech"
                } else {
                    "ws.fanstudio.hk"
                }
                .into(),
                "/kma-station".into(),
            ),
            _ => ("ws.yuelinrhythm.top".into(), "/kma-station".into()),
        };
        // Explicit endpoint injection for isolated transport verification.
        // Normal SeisJS settings never contain this override.
        if source == "seisjs" {
            if let Some(endpoint) = self.settings.get("seisjsEndpoint") {
                host = endpoint["host"]
                    .as_str()
                    .unwrap_or("seisjs.wolfx.jp")
                    .into();
                path = endpoint["path"].as_str().unwrap_or("/all_seis").into();
            }
        }
        let host = CString::new(host).unwrap();
        let path = CString::new(path).unwrap();
        let headers = c"User-Agent: FlutterRhythmQuake/1.0\r\n";
        self.ws = unsafe {
            crate::websocket::rq_ws_open(
                host.as_ptr().cast(),
                path.as_ptr().cast(),
                headers.as_ptr().cast(),
                if source == "seisjs" {
                    self.settings["seisjsEndpoint"]["port"]
                        .as_u64()
                        .unwrap_or(443) as u32
                } else {
                    443
                },
                u32::from(
                    !(source == "seisjs" && self.settings["seisjsEndpoint"]["secure"] == false),
                ),
                if source == "seisjs" { 20000 } else { 12000 },
                0,
                self.id as i64,
                std::mem::transmute::<
                    unsafe extern "C" fn(i64, *mut c_void) -> bool,
                    unsafe extern "C" fn(i64, *mut crate::websocket::DartObject) -> bool,
                >(wake),
            )
        };
        self.last_message = t;
        self.opened_at = t;
        self.alive = false;
        self.heartbeat = t + if source == "seisjs" { 30000 } else { 25000 };
        self.retry = 0;
        self.engine.status("connecting");
        self.connection_diagnostic("connect", json!({}));
        if self.ws == 0 {
            self.ws_failed(t, 0);
        }
    }
    fn send(&self, b: &[u8]) {
        unsafe {
            crate::websocket::rq_ws_send(self.ws, b.as_ptr(), b.len(), 1);
        }
    }
    fn ws_failed(&mut self, t: i64, code: u32) {
        self.connection_diagnostic("disconnected", json!({"code":code}));
        if self.ws != 0 {
            let closed = crate::websocket::release_and_wait(self.ws);
            self.ws = 0;
            if !closed {
                self.shutdown_failed = true;
                self.unauthorized = true;
                self.engine.status("error");
                self.retry = i64::MAX;
                return;
            }
        }
        self.engine.status("error");
        if self.engine.kind == "seisjs" {
            self.engine.last = None;
            self.retry = t + if self.alive { 5000 } else { 10000 };
            return;
        }
        if self.engine.source == "jian" {
            self.engine.signal(-1);
            self.engine.kma.clear();
            self.engine.adj.clear();
            self.engine.last = None;
            self.engine.received = None;
            self.engine.changed = true;
        }
        let source = self.engine.source.as_str();
        if let Some(status) = ws_rejection_status(source, code) {
            if source == "whews" {
                let status_code = if code & 0xffff0000 == 0x10000 {
                    code & 0xffff
                } else {
                    code
                };
                if crate::whews_auth_block::block_endpoint(
                    self.settings["token"].as_str().unwrap_or(""),
                    &self.whews_endpoint(),
                    status_code,
                )
                .is_err()
                {
                    self.connection_diagnostic("retry_state_write_failed", json!({}));
                }
            }
            self.connection_diagnostic("retry_stopped", json!({"code":code}));
            self.unauthorized = true;
            self.retry = i64::MAX;
            self.engine.status(status);
            return;
        }
        if source == "whews" {
            let (index, delay, next) = crate::whews_connection::retry(
                self.host % 2, self.retry_seconds as u64, 2, code,
            ).expect("authorization rejection was handled before retry");
            let previous = self.whews_endpoint();
            self.host = index;
            self.retry = t + delay as i64 * 1000;
            self.retry_seconds = next as i64;
            if previous != self.whews_endpoint() {
                self.connection_diagnostic("endpoint_switched", json!({"previousEndpoint":previous}));
            }
            self.connection_diagnostic("retry_scheduled", json!({"afterMilliseconds":self.retry-t}));
            return;
        }
        self.host += 1;
        self.retry = t + if source == "jian" { 15000 } else { 10000 };
        self.retry_seconds = (if code == 4503 {
            self.retry_seconds.max(15)
        } else {
            self.retry_seconds
        } * 2)
            .min(300);
        self.connection_diagnostic(
            "retry_scheduled",
            json!({"afterMilliseconds": self.retry-t}),
        );
    }
    fn drain_ws(&mut self, t: i64) {
        loop {
            let (mut len, mut kind, mut code) = (0, 0, 0);
            let p =
                unsafe { crate::websocket::rq_ws_take(self.ws, &mut len, &mut kind, &mut code) };
            if p.is_null() {
                break;
            }
            let b = unsafe { std::slice::from_raw_parts(p, len) }.to_vec();
            match kind {
                1 => {
                    if self.engine.kind == "seisjs" {
                        self.alive = true;
                        self.heartbeat = t + 30000;
                    }
                    if self.engine.source == "whews" {
                        self.opened_at = t;
                        self.send(br#"{"type":"ping"}"#);
                    } else if !matches!(self.engine.source.as_str(), "jian" | "seisjs") {
                        self.engine.status("connected");
                    }
                }
                2 | 3 => {
                    self.last_message = t;
                    if let Ok(v) = serde_json::from_slice::<Value>(&b) {
                        if self.engine.kind == "seisjs" {
                            self.engine.input(&v, t);
                            continue;
                        }
                        if self.engine.source == "jian"
                            && (v["type"] == "error" || v["ok"] == false)
                        {
                            self.ws_failed(t, 4403);
                            break;
                        }
                        if self.engine.source == "whews"
                            && (v["type"] == "error"
                                || v["type"] == "auth_error"
                                || v["type"] == "auth_fail"
                                || v["ok"] == false)
                        {
                            self.connection_diagnostic("server_error", json!({"type":v["type"],"code":v["code"],"message":v["message"],"error":v["error"],"detail":v["detail"]}));
                            let code = v["code"].as_u64().unwrap_or(4403) as u32;
                            self.ws_failed(t, if code == 4503 { 4503 } else { 4403 });
                            break;
                        }
                        self.alive = true;
                        if t - self.opened_at >= 60000 {
                            self.retry_seconds = 3;
                        }
                        if self.engine.source == "whews" {
                            self.engine.status("connected");
                        }
                        if v["type"] == "heartbeat" {
                            self.send(if self.engine.source == "whews" {
                                br#"{"type":"ping"}"#
                            } else {
                                b"ping"
                            });
                        } else if v["type"] == "error"
                            && v["message"]
                                .as_str()
                                .is_some_and(|m| m.contains("连接数超限"))
                        {
                            self.ws_failed(t, 0);
                            self.retry = t + 3000;
                            break;
                        } else {
                            self.engine.input(&v, t);
                        }
                    }
                }
                4 | 5 => {
                    self.connection_diagnostic(
                        if kind == 5 {
                            "peer_close"
                        } else {
                            "transport_error"
                        },
                        json!({"code":code,"reason":String::from_utf8_lossy(&b)}),
                    );
                    self.ws_failed(t, code);
                    break;
                }
                _ => {}
            }
        }
    }
    fn request(&mut self, role: &'static str, t: i64) {
        if self.engine.kind == "palert" {
            self.palert_request(role, t);
            return;
        }
        if self.requests.iter().any(|r| r.role == role) {
            return;
        }
        let (host, path) = match role {
            "metadata" => (
                if self.host % 2 == 0 { "static.core-tnn1.exptech.dev" }
                else { "static.core-tyo1.exptech.dev" },
                "/resource/station",
            ),
            "stream" => (
                if self.host % 2 == 0 { "api.lb-tpe1.exptech.dev" }
                else { "api.lb-khh1.exptech.dev" },
                "/api/v1/trem/sse?topics=trem.rts.v1&mode=live",
            ),
            _ => return,
        };
        let body = String::new();
        let headers = format!("User-Agent: FlutterRhythmQuake/1.0\r\nAccept: {}\r\nCache-Control: no-cache\r\n", if role == "stream" { "text/event-stream" } else { "text/csv" });
        let host = CString::new(host).unwrap();
        let path = CString::new(path).unwrap();
        let method = CString::new("GET").unwrap();
        let headers = CString::new(headers).unwrap();
        let id = unsafe {
            crate::http_transport::rq_http_open(
                self.http,
                host.as_ptr().cast(),
                path.as_ptr().cast(),
                method.as_ptr().cast(),
                headers.as_ptr().cast(),
                body.as_ptr(),
                body.len(),
                443,
                3,
                self.id as i64,
                std::mem::transmute::<
                    unsafe extern "C" fn(i64, *mut c_void) -> bool,
                    unsafe extern "C" fn(i64, *mut crate::http_transport::DartObject) -> bool,
                >(wake),
            )
        };
        self.requests.push(Request {
            id,
            role,
            bytes: vec![],
            started: t,
            status: 0,
            sse: false,
            trem_stream: trem_protocol::Stream::default(),
        });
    }
    fn http_failure(&mut self, role: &str, t: i64) {
        if self.engine.kind == "palert" {
            let revision = self.engine.palert.revision;
            self.engine.palert.fail();
            self.engine.changed |= revision != self.engine.palert.revision;
            self.engine.signals.append(&mut self.engine.palert.signals);
            if role == "metadata" {
                self.metadata_at = t + 3000;
            }
            return;
        }
        if role == "stream" {
            self.stream_retry = t + 3000;
        }
        if role == "metadata" {
            self.metadata_at = t + 3000;
            self.host += 1;
        }
        if matches!(role, "stream" | "poll") {
            self.failures += 1;
            if self.failures >= 3 {
                self.engine.status("error");
                self.host += 1;
                self.failures = 0;
            }
        }
    }
    fn drain_http(&mut self, t: i64) {
        let mut done = vec![];
        let mut payloads = vec![];
        for r in &mut self.requests {
            loop {
                let (mut len, mut kind, mut code, mut owner) = (0, 0, 0, ptr::null_mut());
                let p = unsafe {
                    crate::http_transport::rq_http_take(
                        r.id, &mut len, &mut kind, &mut code, &mut owner,
                    )
                };
                if p.is_null() {
                    break;
                }
                let b = unsafe { std::slice::from_raw_parts(p, len) }.to_vec();
                unsafe {
                    crate::http_transport::rq_http_chunk_release(owner);
                }
                match kind {
                    1 => {
                        let h = String::from_utf8_lossy(&b);
                        r.status = h
                            .split_whitespace()
                            .nth(1)
                            .and_then(|x| x.parse().ok())
                            .unwrap_or(0);
                        r.sse = h.to_lowercase().contains("text/event-stream");
                    }
                    2 => {
                        if r.sse && self.engine.kind == "cwa" {
                            r.started = t;
                            match r.trem_stream.push(&b) {
                                Ok(frames) => payloads.extend(frames.into_iter().map(|v| (r.role, v))),
                                Err(_) => { done.push((r.id, r.role, false)); break; }
                            }
                            continue;
                        }
                        r.bytes.extend(b);
                        if r.bytes.len() > 8 * 1024 * 1024 {
                            done.push((r.id, r.role, false));
                            break;
                        }
                        if r.sse {
                            while let Some(i) = r.bytes.iter().position(|&x| x == b'\n') {
                                let line = r.bytes.drain(..=i).collect::<Vec<_>>();
                                if let Some(data) = line.strip_prefix(b"data:") {
                                    if let Ok(v) = serde_json::from_slice::<Value>(data) {
                                        if v["station"].is_object() {
                                            payloads.push((r.role, v));
                                            r.started = t;
                                        }
                                    }
                                }
                            }
                        }
                    }
                    3 => {
                        let mut valid_json = true;
                        if !r.sse && r.status == 200 {
                            if self.engine.kind == "cwa" && r.role == "metadata" {
                                if let Ok(csv) = std::str::from_utf8(&r.bytes) {
                                    valid_json = !trem_protocol::catalogue(csv).is_empty();
                                    if valid_json { payloads.push((r.role, Value::String(csv.into()))); }
                                } else { valid_json = false; }
                            } else if let Ok(v) = serde_json::from_slice::<Value>(&r.bytes) {
                                payloads.push((r.role, v));
                            } else if self.engine.kind == "palert" {
                                valid_json = false;
                                self.engine.palert.last_error =
                                    Some(format!("{}: invalid JSON response", r.role));
                            }
                        }
                        if self.engine.kind == "palert" && r.status != 200 {
                            self.engine.palert.last_error =
                                Some(format!("{}: HTTP {}", r.role, r.status));
                        }
                        done.push((r.id, r.role, r.status == 200 && valid_json));
                        break;
                    }
                    4 => {
                        if self.engine.kind == "palert" {
                            self.engine.palert.last_error =
                                Some(format!("{}: WinHTTP error {}", r.role, code));
                        }
                        done.push((r.id, r.role, false));
                        break;
                    }
                    _ => {
                        let _ = code;
                    }
                }
            }
        }
        for (role, v) in payloads {
            match role {
                "login" | "refresh" => {
                    self.login_pending = false;
                    self.token = v["token"].as_str().unwrap_or("").into();
                    if let Some(s) = v["refresh_token"].as_str() {
                        self.refresh = s.into();
                    }
                    self.expires = timestamp(&v["expires_at"], false, 0)
                        .map(|e| t + (e - t) / 2)
                        .unwrap_or(i64::MAX);
                    self.metadata_at = t;
                    self.stream_retry = t;
                }
                _ => {
                    let accepted = self.engine.input(&v, t);
                    if self.engine.kind == "palert"
                        && role == "metadata"
                        && !self.engine.palert.has_stations()
                    {
                        self.metadata_at = t + 3000;
                    }
                    if accepted {
                        self.failures = 0;
                        if role == "stream" {
                            self.poll_at = i64::MAX;
                        }
                    }
                }
            }
        }
        let mut unauthorized = false;
        for (id, role, success) in done {
            unauthorized |= self
                .requests
                .iter()
                .any(|r| r.id == id && r.status == 401 && !matches!(role, "login" | "refresh"));
            crate::http_transport::rq_http_release(id);
            self.requests.retain(|r| r.id != id);
            if !success {
                self.http_failure(role, t);
            }
            if matches!(role, "login" | "refresh") {
                self.login_pending = false;
                self.metadata_at = t;
                self.stream_retry = t;
            }
            if role == "stream" {
                self.stream_retry = t + 3000;
                self.poll_at = t;
            }
        }
        if self.engine.kind != "cwa" && unauthorized
            && !self.login_pending
            && self.settings["email"]
                .as_str()
                .is_some_and(|s| !s.is_empty())
        {
            self.login_pending = true;
            self.request("login", t);
        }
    }
    fn tick(&mut self, t: i64) {
        self.engine.expire(t);
        if self.testing {
            return;
        }
        if self.engine.kind == "palert" {
            self.drain_http(t);
            let timed = self
                .requests
                .iter()
                .filter(|r| t - r.started > 12000)
                .map(|r| (r.id, r.role))
                .collect::<Vec<_>>();
            for (id, role) in timed {
                crate::http_transport::rq_http_release(id);
                self.requests.retain(|r| r.id != id);
                self.http_failure(role, t);
            }
            if !self.engine.palert.has_stations() {
                if t >= self.metadata_at {
                    self.request("metadata", t);
                    self.metadata_at = i64::MAX;
                }
            } else if t >= self.poll_at {
                self.request("poll", t);
                self.poll_at = t + self.settings["pollMillis"].as_i64().unwrap_or(1000).max(1);
            }
            return;
        }
        if self.engine.kind == "kma" || self.engine.kind == "seisjs" {
            if self.ws == 0 && t >= self.retry {
                self.ws_open(t);
            }
            if self.ws != 0 {
                self.drain_ws(t);
                if self.ws != 0
                    && t >= self.heartbeat
                    && (self.engine.kind != "seisjs" || self.alive)
                {
                    self.send(if self.engine.source == "whews" {
                        br#"{"type":"ping"}"#
                    } else {
                        b"ping"
                    });
                    self.heartbeat = t + if self.engine.kind == "seisjs" {
                        30000
                    } else {
                        25000
                    };
                }
                let timeout = if self.engine.source == "jian" {
                    90000
                } else if self.engine.source == "whews" {
                    90000
                } else {
                    70000
                };
                let observation_stale = self.engine.source == "jian"
                    && t - self.engine.received.unwrap_or(self.opened_at) > 90000;
                let liveness_failed =
                    self.engine.source == "whews" && !self.alive && t - self.opened_at > 20000;
                if self.ws != 0
                    && self.engine.kind != "seisjs"
                    && (t - self.last_message > timeout || observation_stale || liveness_failed)
                {
                    self.ws_failed(t, 0);
                }
                if self.ws != 0
                    && self.engine.kind == "seisjs"
                    && !self.alive
                    && t - self.opened_at > 20000
                {
                    self.ws_failed(t, 0);
                }
            }
        } else {
            self.drain_http(t);
            let stale = self.engine.received.is_some_and(|r| t - r > 3500) && self.engine.connected;
            if stale {
                self.engine.status("error");
                self.host += 1;
                let ids = self
                    .requests
                    .iter()
                    .filter(|r| r.role == "stream")
                    .map(|r| r.id)
                    .collect::<Vec<_>>();
                for id in ids {
                    crate::http_transport::rq_http_release(id);
                    self.requests.retain(|r| r.id != id);
                }
                self.stream_retry = t;
                self.poll_at = t;
            }
            let timed = self
                .requests
                .iter()
                .filter(|r| {
                    t - r.started
                        > if r.role == "stream" && r.sse {
                            90000
                        } else {
                            8000
                        }
                })
                .map(|r| (r.id, r.role))
                .collect::<Vec<_>>();
            for (id, role) in timed {
                crate::http_transport::rq_http_release(id);
                self.requests.retain(|r| r.id != id);
                self.http_failure(role, t);
                if matches!(role, "login" | "refresh") {
                    self.login_pending = false;
                    self.metadata_at = t;
                    self.stream_retry = t;
                }
            }
            if !self.login_pending {
                if t >= self.expires && !self.refresh.is_empty() {
                    self.request("refresh", t);
                    self.expires = i64::MAX;
                }
                if t >= self.metadata_at {
                    self.request("metadata", t);
                    self.metadata_at = t + 300000;
                }
                if t >= self.stream_retry && !self.requests.iter().any(|r| r.role == "stream") {
                    self.request("stream", t);
                    self.stream_retry = i64::MAX;
                }
            }
        }
    }
    fn run(mut self) {
        if self.engine.kind == "palert" && !self.testing {
            self.http = crate::http_transport::open_system_client("FlutterRhythmQuake/1.0");
        }
        if self.engine.kind == "cwa" && !self.testing {
            self.http = unsafe {
                crate::http_transport::rq_http_client_open(
                    c"FlutterRhythmQuake/1.0".as_ptr().cast(),
                )
            };
        }
        let mut testing_clock = now();
        loop {
            let mut clock = if self.testing { testing_clock } else { now() };
            // SeisJS has no fixed-rate business work. Network completions wake
            // immediately; otherwise sleep until expiry, heartbeat or retry.
            let mut wait = if self.s.source_display_only {
                Duration::from_secs(86400)
            } else if self.engine.kind == "seisjs" && !self.testing {
                let deadline = if self.ws == 0 {
                    self.retry
                } else if self.alive {
                    self.heartbeat
                } else {
                    self.opened_at + 20001
                };
                Duration::from_millis(
                    self.engine
                        .seisjs
                        .deadline(clock)
                        .min(deadline)
                        .saturating_sub(clock)
                        .max(0) as u64,
                )
            } else if self.engine.kind == "palert" && !self.testing {
                let mut deadline =
                    self.engine
                        .palert
                        .deadline()
                        .min(if self.engine.palert.has_stations() {
                            self.poll_at
                        } else {
                            self.metadata_at
                        });
                for request in &self.requests {
                    deadline = deadline.min(request.started + 12001);
                }
                Duration::from_millis(deadline.saturating_sub(clock).max(0) as u64)
            } else {
                Duration::from_millis(100)
            };
            if self.engine.kind == "seisjs" && self.engine.changed {
                wait = wait.min(
                    self.engine
                        .next_display
                        .saturating_duration_since(Instant::now()),
                );
            }
            match self.rx.recv_timeout(wait) {
                Ok(Command::Close) | Err(mpsc::RecvTimeoutError::Disconnected) => break,
                Ok(Command::Input(b, t)) => {
                    clock = t;
                    testing_clock = t;
                    self.engine.expire(t);
                    if let Ok(v) = serde_json::from_slice::<Value>(&b) {
                        self.engine.input(&v, t);
                    }
                }
                Ok(Command::PackedInput(bytes, root, t)) => {
                    clock = t;
                    testing_clock = t;
                    self.engine.expire(t);
                    if let Ok(value) = crate::station_json::unpack_value(&bytes, root) {
                        self.engine.input(&value, t);
                    }
                }
                Ok(Command::Settings(v)) => {
                    if let Some(enabled) = v["inference"].as_bool() {
                        self.engine.palert.set_inference(enabled);
                        self.engine.changed = true;
                    }
                    if let Some(x) = v["sensitivity"].as_i64() {
                        self.engine.sensitivity = x.clamp(1, 3) as i32;
                    }
                    if let Some(x) = v["hold"].as_u64() {
                        self.engine.hold = x.clamp(1, 60) as usize;
                    }
                }
                _ => {}
            }
            if !self.testing {
                self.tick(clock);
            }
            self.engine.publish(&self.s, clock);
        }
        let socket_closed =
            !self.shutdown_failed && (self.ws == 0 || crate::websocket::release_and_wait(self.ws));
        if socket_closed {
            release_socket_owner(&self.engine.kind, self.id);
        }
        for r in &self.requests {
            crate::http_transport::rq_http_release(r.id);
        }
        if self.http != 0 {
            crate::http_transport::rq_http_client_close(self.http);
        }
        if self.engine.kind == "cwa" {
            self.engine.clear_trem();
        }
        WORKERS.fetch_sub(1, Ordering::Relaxed);
    }
}
#[no_mangle]
pub unsafe extern "C" fn rq_station_runtime_open(
    bytes: *const u8,
    len: usize,
    port: i64,
    post: Post,
) -> u64 {
    if bytes.is_null() || len > 1024 * 1024 {
        return 0;
    }
    let Ok(settings) =
        serde_json::from_slice::<Value>(unsafe { std::slice::from_raw_parts(bytes, len) })
    else {
        return 0;
    };
    let testing = settings["testing"] == true;
    let engine = Engine::new(&settings);
    let id = NEXT.fetch_add(1, Ordering::Relaxed);
    let (tx, rx) = mpsc::channel();
    let s = Arc::new(Session {
        tx,
        out: Mutex::new(Output {
            prepared: None,
            delivered_prepared: Arc::new(vec![]),
            original_tree: Arc::new(vec![]),
            archive_tree: Arc::new(vec![]),
            pinned_original_tree: Arc::new(vec![]),
            pinned_archive_tree: Arc::new(vec![]),
            delivered_signals: vec![],
            palert: None,
            pinned_palert: None,
            deliveries: HashMap::new(),
            next_delivery: 0,
            snapshot: None,
            signals: vec![],
            delivered: vec![],
            original: Arc::new(vec![]),
            pinned_original: Arc::new(vec![]),
            archive: Arc::new(vec![]),
            pinned_archive: Arc::new(vec![]),
        }),
        port,
        post,
        testing,
        native_display: settings["nativeDisplay"] == true && settings["kind"] == "palert",
        prepared_tree: settings["preparedTree"] == true && settings["kind"] != "palert",
        source_display_only: settings["sourceDisplayOnly"] == true,
        packed_input: Mutex::new((0, Arc::new(vec![]))),
    });
    registry().lock().unwrap().insert(id, s.clone());
    WORKERS.fetch_add(1, Ordering::Relaxed);
    if thread::Builder::new()
        .name(format!("rq-{}-source", engine.kind))
        .stack_size(512 * 1024)
        .spawn(move || {
            Runtime {
                id,
                engine,
                s,
                rx,
                settings,
                ws: 0,
                http: 0,
                requests: vec![],
                retry: 0,
                heartbeat: 0,
                last_message: 0,
                opened_at: 0,
                alive: false,
                unauthorized: false,
                shutdown_failed: false,
                retry_seconds: 3,
                host: 0,
                failures: 0,
                stream_retry: 0,
                poll_at: 0,
                metadata_at: 0,
                token: String::new(),
                refresh: String::new(),
                expires: i64::MAX,
                login_pending: false,
                testing,
            }
            .run()
        })
        .is_err()
    {
        registry().lock().unwrap().remove(&id);
        WORKERS.fetch_sub(1, Ordering::Relaxed);
        return 0;
    }
    id
}
#[no_mangle]
pub unsafe extern "C" fn rq_station_runtime_input(
    id: u64,
    bytes: *const u8,
    len: usize,
    clock: i64,
) -> u32 {
    if bytes.is_null() || len > 8 * 1024 * 1024 {
        return 1;
    }
    let Some(s) = session(id) else {
        return 1;
    };
    if !s.testing {
        return 1;
    }
    let b = unsafe { std::slice::from_raw_parts(bytes, len) }.to_vec();
    u32::from(s.tx.send(Command::Input(b, clock)).is_err())
}
#[no_mangle]
pub unsafe extern "C" fn rq_station_runtime_settings(id: u64, bytes: *const u8, len: usize) -> u32 {
    if bytes.is_null() || len > 1024 * 1024 {
        return 1;
    }
    let Some(s) = session(id) else {
        return 1;
    };
    let Ok(v) = serde_json::from_slice(unsafe { std::slice::from_raw_parts(bytes, len) }) else {
        return 1;
    };
    u32::from(s.tx.send(Command::Settings(v)).is_err())
}
#[no_mangle]
pub unsafe extern "C" fn rq_station_runtime_input_packed(
    id: u64,
    bytes: *const u8,
    len: usize,
    root: u32,
    clock: i64,
    token: u64,
) -> u32 {
    let Some(s) = session(id) else {
        return 1;
    };
    if !s.testing || len > 128 * 1024 * 1024 {
        return 1;
    }
    let data = {
        let mut cached = s.packed_input.lock().unwrap();
        if !bytes.is_null() && len > 0 {
            *cached = (
                token,
                Arc::new(unsafe { std::slice::from_raw_parts(bytes, len) }.to_vec()),
            );
        }
        if cached.0 != token || cached.1.is_empty() {
            return 1;
        }
        cached.1.clone()
    };
    u32::from(s.tx.send(Command::PackedInput(data, root, clock)).is_err())
}
#[no_mangle]
pub unsafe extern "C" fn rq_station_runtime_take(
    id: u64,
    len: *mut usize,
    original: u32,
) -> *const u8 {
    if len.is_null() {
        return ptr::null();
    }
    let Some(s) = session(id) else {
        return ptr::null();
    };
    let mut out = s.out.lock().unwrap();
    if original >= 10 {
        if original == 10 {
            let Some(frame) = out.prepared.take() else {
                return ptr::null();
            };
            out.delivered_prepared = frame;
            out.pinned_original_tree = out.original_tree.clone();
            out.pinned_archive_tree = out.archive_tree.clone();
            out.delivered_signals = std::mem::take(&mut out.signals);
        }
        let bytes = match original {
            10 => &out.delivered_prepared,
            11 => &out.pinned_original_tree,
            12 => &out.pinned_archive_tree,
            _ => return ptr::null(),
        };
        if bytes.is_empty() {
            return ptr::null();
        }
        unsafe {
            *len = bytes.len();
        }
        return bytes.as_ptr();
    }
    if let Some(frame) = out.pinned_palert.clone() {
        if original == 1 && out.pinned_original.is_empty() {
            out.pinned_original = Arc::new(frame.original.encode());
        }
        if original == 2 && out.pinned_archive.is_empty() {
            out.pinned_archive = Arc::new(frame.archive());
        }
    }
    // Serialization and archive assembly happened on the producer thread.
    // Taking a display frame only swaps owned buffers and pins two Arcs.
    if original == 1 {
        if out.pinned_original.is_empty() {
            return ptr::null();
        }
        unsafe {
            *len = out.pinned_original.len();
        }
        return out.pinned_original.as_ptr();
    }
    if original == 2 {
        if out.pinned_archive.is_empty() {
            return ptr::null();
        }
        unsafe {
            *len = out.pinned_archive.len();
        }
        return out.pinned_archive.as_ptr();
    }
    let Some(bytes) = out.snapshot.take() else {
        return ptr::null();
    };
    out.pinned_original = out.original.clone();
    out.pinned_archive = out.archive.clone();
    out.signals.clear();
    out.delivered = bytes;
    unsafe {
        *len = out.delivered.len();
    }
    out.delivered.as_ptr()
}
/// Deliver an already prepared UI frame directly through Dart_PostCObject.
/// The primitive wake and the payload have separate tags; no live JSON decoder
/// or per-station source interpretation executes on the Dart side.
#[no_mangle]
pub extern "C" fn rq_station_runtime_post_palert(id: u64, catalogue_revision: i64) -> u32 {
    let Some(s) = session(id) else {
        return 1;
    };
    let (frame, signals, delivery) = {
        let mut out = s.out.lock().unwrap();
        let Some(frame) = out.palert.take() else {
            return 0;
        };
        let signals = std::mem::take(&mut out.signals);
        out.next_delivery += 1;
        let delivery = out.next_delivery;
        out.deliveries.insert(delivery, frame.clone());
        (frame, signals, delivery)
    };
    u32::from(!if s.source_display_only {
        frame.post_sources(s.port, s.post, delivery)
    } else {
        frame.post(
            s.port,
            s.post,
            &signals,
            catalogue_revision != frame.catalogue.revision as i64,
            delivery,
        )
    })
}
#[no_mangle]
pub extern "C" fn rq_station_runtime_ack_palert(id: u64, delivery: u64) -> u32 {
    let Some(s) = session(id) else {
        return 1;
    };
    let mut out = s.out.lock().unwrap();
    let Some(frame) = out.deliveries.remove(&delivery) else {
        return 1;
    };
    out.pinned_palert = Some(frame);
    out.pinned_original = Arc::new(vec![]);
    out.pinned_archive = Arc::new(vec![]);
    0
}
#[no_mangle]
pub unsafe extern "C" fn rq_station_runtime_delivered_signals(
    id: u64,
    len: *mut usize,
) -> *const i32 {
    if len.is_null() {
        return ptr::null();
    }
    let Some(s) = session(id) else {
        return ptr::null();
    };
    let out = s.out.lock().unwrap();
    unsafe {
        *len = out.delivered_signals.len();
    }
    out.delivered_signals.as_ptr()
}
/// Immutable native-produced archive trees, pinned to the delivered UI frame.
/// Taking/copying never serializes or parses data on the calling UI thread.
#[no_mangle]
pub unsafe extern "C" fn rq_station_runtime_take_palert_tree(
    id: u64,
    part: u32,
    len: *mut usize,
) -> *const u8 {
    if len.is_null() {
        return ptr::null();
    }
    let Some(s) = session(id) else {
        return ptr::null();
    };
    let out = s.out.lock().unwrap();
    let Some(frame) = &out.pinned_palert else {
        return ptr::null();
    };
    let bytes = match part {
        0 => Some(frame.archive_tree.as_slice()),
        1 => frame.original.metadata_tree.as_ref().map(|v| v.as_slice()),
        2 => frame.original.data_tree.as_ref().map(|v| v.as_slice()),
        _ => None,
    };
    match bytes {
        Some(bytes) if !bytes.is_empty() => {
            unsafe {
                *len = bytes.len();
            }
            bytes.as_ptr()
        }
        _ => ptr::null(),
    }
}
#[no_mangle]
pub extern "C" fn rq_station_runtime_release(id: u64) {
    if let Some(s) = registry().lock().unwrap().remove(&id) {
        let _ = s.tx.send(Command::Close);
    }
}
#[no_mangle]
pub extern "C" fn rq_station_runtime_finalizer(id: *mut c_void) {
    rq_station_runtime_release(id as u64);
}
#[no_mangle]
pub extern "C" fn rq_station_runtime_workers() -> usize {
    WORKERS.load(Ordering::Relaxed)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn native_socket_owner_changes_only_after_shutdown_confirmation() {
        let kind = "controlled-test-owner";
        assert!(claim_socket_owner(kind, u64::MAX - 1));
        assert!(!claim_socket_owner(kind, u64::MAX));
        release_socket_owner(kind, u64::MAX);
        assert!(!claim_socket_owner(kind, u64::MAX));
        release_socket_owner(kind, u64::MAX - 1);
        assert!(claim_socket_owner(kind, u64::MAX));
        release_socket_owner(kind, u64::MAX);
    }
    #[test]
    fn authentication_and_ban_failures_are_terminal() {
        for source in ["whews", "jian"] {
            for code in [
                401,
                403,
                429,
                1008,
                4008,
                4401,
                4403,
                0x10000 | 401,
                0x10000 | 403,
                0x10000 | 429,
            ] {
                assert!(
                    ws_rejection_status(source, code).is_some(),
                    "{source} {code}"
                );
            }
            for code in [0, 1000, 1006, 4503, 0x10000 | 503] {
                assert_eq!(ws_rejection_status(source, code), None);
            }
        }
        assert_eq!(ws_rejection_status("whews", 4401), Some("unauthorized"));
        assert_eq!(ws_rejection_status("whews", 4403), Some("error"));
        assert_eq!(ws_rejection_status("seisjs", 403), None);
    }
    #[test]
    fn original_kma_frames() {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../test/fixtures/source_ws_followup_20261016");
        let mut e = Engine::new(&json!({"kind":"kma"}));
        for i in 0..8 {
            let b = std::fs::read(root.join(format!("kma_{i:02}.original.bytes"))).unwrap();
            let v: Value = serde_json::from_slice(&b).unwrap();
            e.input(&v, 1792140660000);
        }
        assert!(!e.kma.is_empty());
        assert!(e.frames > 0);
        let t = e.last.unwrap();
        assert!(!e.kma_input(&e.original["data"].clone(), t));
        assert!(e.adj.iter().map(Vec::len).sum::<usize>() < e.kma.len() * e.kma.len());
    }
    #[test]
    fn time_offsets() {
        assert_eq!(
            timestamp(&json!("2026-10-17T11:00:00+09:00"), false, 0),
            timestamp(&json!("20261017020000"), true, 0)
        );
        assert_eq!(iso(0), "1970-01-01T00:00:00.000Z");
        assert_eq!(timestamp(&json!("20260230000000"), true, 0), None);
    }
}
