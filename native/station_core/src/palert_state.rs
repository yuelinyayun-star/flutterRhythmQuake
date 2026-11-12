//! P-Alert observation/detection owner. All source values remain in their
//! original domain; UI projections are separate from retained source JSON.
use super::palert_display::{Catalogue, Frame, Original};
use super::palert_inference::{Inference, Sample};
use super::{iso, number, text, timestamp};
use crate::{ka_detector::Detector, ka_history, palert_levels::Levels};
use serde::{ser::SerializeMap, Serialize, Serializer};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::Arc;

// Borrow immutable station fields while writing the display projection. The
// catalogue and measurement maps must not be deep-cloned for every UI frame.
struct DisplayRow<'a> {
    row: &'a Value,
    recent: bool,
}
impl Serialize for DisplayRow<'_> {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        let row = self.row.as_object().unwrap();
        let mut map = serializer.serialize_map(Some(
            row.len() + usize::from(!row.contains_key("mapRecent")),
        ))?;
        for (key, value) in row {
            if key != "mapRecent" {
                map.serialize_entry(key, value)?;
            }
        }
        map.serialize_entry("mapRecent", &self.recent)?;
        map.end()
    }
}
struct DisplaySnapshot<'a> {
    header: Value,
    stations: Vec<DisplayRow<'a>>,
    summary: Option<DisplayRow<'a>>,
}
impl Serialize for DisplaySnapshot<'_> {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        let header = self.header.as_object().unwrap();
        let mut map = serializer.serialize_map(Some(header.len() + 2))?;
        for (key, value) in header {
            map.serialize_entry(key, value)?;
        }
        map.serialize_entry("stations", &self.stations)?;
        map.serialize_entry("summary", &self.summary)?;
        map.end()
    }
}

fn label(v: &Value) -> String {
    if v.is_null() {
        String::new()
    } else {
        text(v).trim().into()
    }
}
fn measurement(v: &Value) -> Option<f64> {
    v.as_f64().or_else(|| v.as_str()?.trim().parse().ok())
}
fn wire_number(v: f64) -> Value {
    if v.is_finite() {
        json!(v)
    } else if v.is_nan() {
        json!("NaN")
    } else if v.is_sign_positive() {
        json!("Infinity")
    } else {
        json!("-Infinity")
    }
}
fn index(l: i32) -> i32 {
    if l < 0 {
        -1
    } else if l <= 7 {
        0
    } else if l <= 15 {
        (l - 6) / 2
    } else {
        (l - 11).clamp(5, 9)
    }
}
fn shindo(l: i32) -> i32 {
    let i = index(l);
    if i <= 4 {
        i
    } else if i <= 6 {
        5
    } else if i <= 8 {
        6
    } else {
        7
    }
}
fn jma(l: i32) -> i32 {
    if l < 0 {
        -1
    } else if l <= 7 {
        0
    } else {
        ((l - 6) / 2).min(7)
    }
}
fn time(v: &Value) -> Option<i64> {
    let s = v.as_str()?.trim();
    if let Some(t) = timestamp(&json!(s), false, i64::MIN) {
        return Some(t);
    }
    let p = s
        .split(['/', ' ', ':'])
        .map(str::parse::<i64>)
        .collect::<Result<Vec<_>, _>>()
        .ok()?;
    if p.len() != 6 {
        return None;
    }
    timestamp(
        &json!(format!(
            "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z",
            p[2], p[0], p[1], p[3], p[4], p[5]
        )),
        false,
        0,
    )
}
fn km(a: (f64, f64), b: (f64, f64)) -> f64 {
    let rad = 0.017453292519943295;
    let x = ((b.0 - a.0) * rad / 2.0).sin();
    let y = ((b.1 - a.1) * rad / 2.0).sin();
    2.0 * 6371.0
        * (x * x + y * y * (a.0 * rad).cos() * (b.0 * rad).cos())
            .sqrt()
            .asin()
}
#[derive(Clone)]
struct Station {
    row: Value,
    history: Vec<i64>,
    result: ka_history::Output,
    previous: Option<i64>,
    until: i64,
    state: i32,
}
impl Station {
    fn invalidate(&mut self) -> bool {
        let changed = self.result.level >= 0 || self.until > 0;
        self.history.clear();
        self.result = ka_history::Output {
            level: -1,
            ..Default::default()
        };
        self.previous = None;
        self.until = 0;
        self.state = 0;
        changed
    }
    fn update(&mut self, level: i64, time: i64) {
        let abnormal = self.result.length & (1 << 32) != 0;
        self.result = ka_history::update(
            &mut self.history,
            &ka_history::Input {
                station: 0,
                level,
                expire: 10,
                time_ms: time,
                flags: u64::from(self.until > 0) | (u64::from(abnormal) << 1),
                abnormal: self.result.abnormal,
            },
        );
    }
}
pub(super) struct PAlert {
    stations: Vec<Station>,
    levels: Levels,
    detector: Option<Detector>,
    pub(super) last: Option<i64>,
    pub(super) received: Option<i64>,
    pub(super) status: String,
    pub(super) revision: u64,
    pub(super) frames: u64,
    pub(super) original: Original,
    catalogue: Arc<Catalogue>,
    inference: Inference,
    inference_enabled: bool,
    pub(super) replay_mode: bool,
    pub(super) signals: Vec<i32>,
    pub(super) last_error: Option<String>,
    grids: Vec<(f64, f64, i32)>,
    decimal: (f64, f64),
    previous_shindo: i32,
    low: bool,
    strong: bool,
    failures: i32,
    next_expire: i64,
}
impl Default for PAlert {
    fn default() -> Self {
        Self {
            stations: vec![],
            levels: Levels::default(),
            detector: None,
            last: None,
            received: None,
            status: "connecting".into(),
            revision: 0,
            frames: 0,
            original: Original::default(),
            catalogue: Arc::new(Catalogue {
                revision: 0,
                rows: vec![],
            }),
            inference: Inference::default(),
            inference_enabled: false,
            replay_mode: false,
            signals: vec![],
            last_error: None,
            grids: vec![],
            decimal: (0.0, 0.0),
            previous_shindo: -1,
            low: false,
            strong: false,
            failures: 0,
            next_expire: 0,
        }
    }
}
impl PAlert {
    pub(super) fn set_inference(&mut self, enabled: bool) {
        if self.inference_enabled == enabled {
            return;
        }
        self.inference_enabled = enabled;
        if enabled && !self.stations.is_empty() {
            self.inference.configure(self.catalogue.clone());
        } else {
            self.inference = Inference::default();
        }
    }
    pub(super) fn deadline(&self) -> i64 {
        self.next_expire
    }
    pub(super) fn has_stations(&self) -> bool {
        !self.stations.is_empty()
    }
    pub(super) fn fail(&mut self) {
        self.failures += 1;
        if self.failures == 3 {
            self.status = "error".into();
            self.reset_detection();
        }
    }
    pub(super) fn reset_detection(&mut self) {
        self.inference.clear_episode();
        for s in &mut self.stations {
            s.invalidate();
        }
        self.grids.clear();
        self.decimal = (0.0, 0.0);
        self.sound(-1);
        self.revision += 1;
    }
    fn sound(&mut self, max: i32) {
        if max < 0 {
            if self.previous_shindo >= 0 {
                self.signals.push(-1);
            }
            self.previous_shindo = -1;
            self.low = false;
            self.strong = false;
            return;
        }
        let rising = max > self.previous_shindo;
        self.previous_shindo = max;
        if rising && max >= 4 && !self.strong {
            self.low = true;
            self.strong = true;
            self.signals.push(max);
        } else if rising && max >= 1 && !self.low {
            self.low = true;
            self.signals.push(max);
        }
    }
    fn configure(&mut self) {
        let points = self
            .stations
            .iter()
            .map(|s| {
                (
                    number(&s.row["coordinate"]["lat"]).unwrap(),
                    number(&s.row["coordinate"]["lng"]).unwrap(),
                )
            })
            .collect::<Vec<_>>();
        let mut adj = Vec::with_capacity(points.len());
        for &a in &points {
            let mut near = vec![];
            let mut candidate: Option<(usize, f64)> = None;
            for (j, &b) in points.iter().enumerate() {
                let d = km(a, b);
                if d <= 30.0 {
                    near.push((j, d));
                } else if d <= 40.0 && candidate.is_none_or(|(_, old)| d <= old) {
                    candidate = Some((j, d));
                }
            }
            if near.len() <= 1 {
                if let Some(v) = candidate {
                    near.push(v);
                }
            }
            near.sort_by(|a, b| a.1.total_cmp(&b.1));
            near.truncate(6);
            adj.push(near.into_iter().map(|a| a.0).collect::<Vec<_>>());
        }
        let mut distances = HashMap::new();
        for neighbors in &adj {
            for &a in neighbors {
                for &b in neighbors {
                    distances
                        .entry((a as u32, b as u32))
                        .or_insert_with(|| km(points[a], points[b]));
                }
            }
        }
        self.detector = Some(Detector::from_topology(&adj, distances));
    }
    pub(super) fn input(&mut self, v: &Value, clock: i64, sensitivity: i32) -> bool {
        if self.replay_mode {
            return self.recorded_snapshot(v, clock, sensitivity);
        }
        if !v["errors"].is_null() {
            self.fail();
            return false;
        }
        if let Some(infos) = v["data"]["stationList"]["staInfos"].as_array() {
            self.original.metadata(v);
            let mut rows = vec![];
            for info in infos {
                let id = label(&info["station"]);
                let (Some(lat), Some(lon)) = (number(&info["lat"]), number(&info["lon"])) else {
                    continue;
                };
                if id.is_empty() {
                    continue;
                }
                let name = label(&info["locname"]);
                let row = json!({"id":id,"network":label(&info["network"]),"name":if name.is_empty(){id.clone()}else{name},"area":label(&info["area"]),"coordinate":{"lat":lat,"lng":lon},"pgaGal":null,"pgvCms":null,"cwaIntensityIndex":null,"heldCwaIntensityIndex":null,"heldLevel":null,"dataTime":null,"receivedAt":null,"sampledLevel":null});
                if let Some(index) = rows.iter().position(|s: &Station| s.row["id"] == id) {
                    rows.remove(index);
                }
                rows.push(Station {
                    row,
                    history: vec![],
                    result: ka_history::Output {
                        level: -1,
                        ..Default::default()
                    },
                    previous: None,
                    until: 0,
                    state: 0,
                });
            }
            if rows.is_empty() {
                self.fail();
                return false;
            }
            rows.sort_by(|a, b| {
                a.row["id"]
                    .as_str()
                    .unwrap()
                    .cmp(b.row["id"].as_str().unwrap())
            });
            self.stations = rows;
            self.catalogue = Arc::new(Catalogue {
                revision: self.catalogue.revision + 1,
                rows: self
                    .stations
                    .iter()
                    .map(|s| {
                        (
                            ["id", "network", "name", "area"]
                                .map(|key| s.row[key].as_str().unwrap().to_owned()),
                            [
                                s.row["coordinate"]["lat"].as_f64().unwrap(),
                                s.row["coordinate"]["lng"].as_f64().unwrap(),
                            ],
                        )
                    })
                    .collect(),
            });
            if self.inference_enabled {
                self.inference.configure(self.catalogue.clone());
            }
            self.levels = Levels::default();
            self.levels
                .configure(&vec![-1; self.stations.len()])
                .unwrap();
            self.configure();
            self.revision += 1;
            return true;
        }
        self.original.data(v);
        let Some(stamp) = time(&v["data"]["pga"]["timestamp"]) else {
            self.fail();
            return false;
        };
        if self.last.is_some_and(|old| stamp <= old) {
            return false;
        }
        let same = time(&v["data"]["pgv"]["timestamp"]) == Some(stamp);
        let (a, b) = (&v["data"]["pga"]["dataVals"], &v["data"]["pgv"]["dataVals"]);
        if !a
            .as_object()
            .is_some_and(|values| values.values().any(|v| measurement(v).is_some()))
        {
            self.fail();
            return false;
        }
        let mut input = vec![0.0; self.stations.len() * 3];
        let mut velocities = Vec::with_capacity(self.stations.len());
        for (i, s) in self.stations.iter().enumerate() {
            let id = s.row["id"].as_str().unwrap();
            let pga = measurement(&a[id]);
            let pgv = if same { measurement(&b[id]) } else { None };
            velocities.push(pgv);
            input[i * 3] = if pga.is_some() { 1.0 } else { 0.0 };
            input[i * 3 + 1] = pga.unwrap_or(f64::NAN);
            input[i * 3 + 2] = pgv.unwrap_or(f64::NAN);
        }
        if !input
            .chunks_exact(3)
            .enumerate()
            .any(|(i, r)| r[0] > 0.0 || velocities[i].is_some())
        {
            self.fail();
            return false;
        }
        let mut out = vec![-1; self.stations.len() * 2];
        self.levels.process(stamp * 1000, &input, &mut out);
        for (i, s) in self.stations.iter_mut().enumerate() {
            let row = &input[i * 3..i * 3 + 3];
            if row[0] == 0.0 && velocities[i].is_none() {
                continue;
            }
            let current = out[i * 2];
            let held = out[i * 2 + 1];
            if row[0] > 0.0 {
                s.row["pgaGal"] = wire_number(row[1]);
                s.row["pgvCms"] = velocities[i].map(wire_number).unwrap_or(Value::Null);
                s.row["heldLevel"] = json!(held);
                s.row["heldCwaIntensityIndex"] = if held < 0 {
                    Value::Null
                } else {
                    json!(index(held))
                };
                s.row["dataTime"] = json!(iso(stamp));
                s.row["receivedAt"] = json!(iso(clock));
                s.row["sampledLevel"] = json!(current);
            }
            s.row["cwaIntensityIndex"] = if current < 0 {
                Value::Null
            } else {
                json!(index(current))
            };
        }
        self.last = Some(stamp);
        self.received = Some(clock);
        self.frames += 1;
        self.revision += 1;
        self.status = "connected".into();
        self.failures = 0;
        self.last_error = None;
        self.detect(clock, sensitivity);
        if self.inference_enabled {
            let samples = self
                .stations
                .iter()
                .map(|s| Sample {
                    stamp: time(&s.row["dataTime"]),
                    received: time(&s.row["receivedAt"]),
                    pga: measurement(&s.row["pgaGal"]).unwrap_or(f64::NAN),
                    level: s.row["sampledLevel"].as_i64().unwrap_or(-1) as i32,
                    confirmed: s.until > clock,
                })
                .collect::<Vec<_>>();
            self.inference.update(&samples, clock);
        }
        true
    }
    fn detect(&mut self, clock: i64, sensitivity: i32) {
        let mut changed = false;
        for s in &mut self.stations {
            s.result.activity = 0.0;
            let (Some(stamp), Some(received)) =
                (time(&s.row["dataTime"]), time(&s.row["receivedAt"]))
            else {
                changed |= s.invalidate();
                continue;
            };
            let level = s.row["sampledLevel"].as_i64().unwrap_or(-1);
            if clock - received > 6000 || level < 0 {
                changed |= s.invalidate();
                continue;
            }
            if let Some(old) = s.previous {
                if stamp <= old {
                    continue;
                }
                let gap = (stamp - old) / 1000;
                if gap > 6 {
                    s.invalidate();
                } else {
                    for second in 1..gap.min(60) {
                        s.update(-1, old + second * 1000);
                    }
                }
            }
            s.previous = Some(stamp);
            s.update(level, stamp);
            if measurement(&s.row["pgaGal"]).unwrap_or(f64::NAN) < 0.8 {
                s.result.activity = 0.0;
            }
            changed = true;
        }
        if changed {
            let mut info = vec![];
            for s in &mut self.stations {
                if s.until <= clock {
                    s.until = 0;
                    s.state = 0;
                }
                info.extend_from_slice(&[
                    s.result.level,
                    s.result.activity.to_bits() as i64,
                    s.result.ascend,
                    i64::from(s.until > clock),
                    0,
                    s.result.trigger_ms,
                ]);
            }
            if let Some(detector) = self.detector.as_mut() {
                let strongest = detector
                    .detect_policy(&info, sensitivity as i64, !self.grids.is_empty(), false, 3)
                    .expect("P-Alert topology pair");
                if strongest >= 0 {
                    let s = &self.stations[strongest as usize];
                    let decimal = |v: f64| ((v + 180.0).rem_euclid(1.0) * 10.0).round() / 10.0;
                    self.decimal = (
                        decimal(number(&s.row["coordinate"]["lat"]).unwrap()),
                        decimal(number(&s.row["coordinate"]["lng"]).unwrap()),
                    );
                }
                for &i in &detector.active {
                    let s = &mut self.stations[i as usize];
                    s.until = clock + 10500;
                    s.state = match jma(s.result.level as i32) {
                        4.. => 6,
                        1..=3 => 5,
                        0 => 1,
                        _ => 0,
                    };
                }
            }
        }
        self.refresh(clock);
    }
    fn refresh(&mut self, clock: i64) {
        self.grids.clear();
        let mut max = -1;
        for s in &self.stations {
            if s.until <= clock {
                continue;
            }
            max = max
                .max(0)
                .max(shindo(s.row["sampledLevel"].as_i64().unwrap_or(-1) as i32));
            let level = s.result.level as i32;
            if level < 0 {
                continue;
            }
            let lat = (number(&s.row["coordinate"]["lat"]).unwrap() - self.decimal.0).round()
                + self.decimal.0;
            let lon = (number(&s.row["coordinate"]["lng"]).unwrap() - self.decimal.1).round()
                + self.decimal.1;
            if let Some(g) = self.grids.iter_mut().find(|g| g.0 == lat && g.1 == lon) {
                g.2 = g.2.max(level);
            } else {
                self.grids.push((lat, lon, level));
            }
        }
        if self.grids.is_empty() {
            self.decimal = (0.0, 0.0);
        }
        self.sound(max);
    }
    pub(super) fn expire(&mut self, clock: i64, sensitivity: i32) -> bool {
        if clock < self.next_expire {
            return false;
        }
        self.next_expire = clock + 1000;
        let mut changed = false;
        for s in &mut self.stations {
            let recent = time(&s.row["receivedAt"]).is_some_and(|t| clock - t <= 12000);
            if s.row["mapRecent"].as_bool() != Some(recent) {
                s.row["mapRecent"] = json!(recent);
                changed = true;
            }
            s.result.activity = 0.0;
            if time(&s.row["receivedAt"]).is_some_and(|t| clock - t > 6000) {
                changed |= s.invalidate();
            } else if s.until > 0 && s.until <= clock {
                s.until = 0;
                s.state = 0;
                changed = true;
            }
        }
        if changed {
            self.revision += 1;
            self.detect(clock, sensitivity);
        }
        if self.received.is_some_and(|t| clock - t > 6000) && self.status != "error" {
            self.status = "error".into();
            self.reset_detection();
            changed = true;
        }
        changed
    }
    pub(super) fn prepared(&self, clock: i64, data_changed: bool) -> Frame {
        let mut stations = Vec::with_capacity(self.stations.len() * 10);
        let mut signature = self.stations.len().to_string();
        let mut automation = vec![];
        let mut summary = -1i64;
        let mut best_level = -1;
        for (i, s) in self.stations.iter().enumerate() {
            let row = &s.row;
            let pga = measurement(&row["pgaGal"]);
            let pgv = measurement(&row["pgvCms"]);
            let data_time = time(&row["dataTime"]);
            let received = time(&row["receivedAt"]);
            let recent = received.is_some_and(|t| clock - t <= 12000);
            let level = row["heldLevel"].as_i64().unwrap_or(-1) as i32;
            stations.extend([
                pga.unwrap_or(f64::NAN),
                pgv.unwrap_or(f64::NAN),
                row["cwaIntensityIndex"].as_f64().unwrap_or(f64::NAN),
                row["heldCwaIntensityIndex"].as_f64().unwrap_or(f64::NAN),
                row["heldLevel"].as_f64().unwrap_or(f64::NAN),
                row["sampledLevel"].as_f64().unwrap_or(f64::NAN),
                data_time.map_or(f64::NAN, |v| v as f64),
                received.map_or(f64::NAN, |v| v as f64),
                if recent { 1.0 } else { 0.0 },
                (i32::from(pga.is_some()) | i32::from(pgv.is_some()) << 1) as f64,
            ]);
            signature.push_str(&format!(
                "|{}:{}:{}:{}:{}:{}",
                row["id"].as_str().unwrap(),
                level,
                number(&row["pgaGal"]).map_or("-".into(), |v| format!("{v:.3}")),
                number(&row["pgvCms"]).map_or("-".into(), |v| format!("{v:.3}")),
                data_time.unwrap_or(0),
                recent
            ));
            if level >= 0 && level > best_level {
                summary = i as i64;
                best_level = level;
            }
            if level >= 0 && data_time.is_some() {
                automation.extend([i as i32, index(level), i32::from(index(level) >= 4)]);
            }
        }
        let mut active = self
            .stations
            .iter()
            .enumerate()
            .filter(|(_, s)| s.until > clock)
            .collect::<Vec<_>>();
        active.sort_by(|(_, a), (_, b)| {
            b.result
                .level
                .cmp(&a.result.level)
                .then_with(|| a.row["id"].as_str().cmp(&b.row["id"].as_str()))
        });
        let mut counts = [0, 0, 0, -1];
        let mut entries = vec![];
        let mut json_entries = vec![];
        for (i, s) in active {
            let shindo = jma(s.result.level as i32);
            counts[3] = counts[3].max(shindo as i64);
            if shindo == 0 {
                counts[0] += 1;
            } else if shindo >= 4 {
                counts[2] += 1;
            } else if shindo >= 1 {
                counts[1] += 1;
            }
            entries.push([i as i64, s.result.level, shindo as i64, s.state as i64]);
            json_entries.push(json!({"code":s.row["id"],"prefecture":s.row["area"],"level":s.result.level,"jmaShindo":shindo,"detectState":s.state,"detectReason":"kanameishi-chain"}));
        }
        let stage = if entries.is_empty() {
            "idle"
        } else if counts[2] > 0 {
            "strong"
        } else if counts[1] > 0 {
            "detected"
        } else {
            "weak"
        };
        let detection = json!({"stage":stage,"weakCount":counts[0],"detectedCount":counts[1],"strongCount":counts[2],"maxShindo":counts[3],"entries":json_entries});
        let grid_cells = self
            .grids
            .iter()
            .map(|&(lat, lon, l)| json!([lat, lon, l]))
            .collect::<Vec<_>>();
        let detection_signature = serde_json::to_string(&json!([detection, grid_cells])).unwrap();
        let mut grids = vec![];
        for &(lat, lon, l) in &self.grids {
            let shindo = if l <= 0 {
                -3.0
            } else if l >= 20 {
                6.5
            } else {
                (l as f64 + 0.5 - 7.0) / 2.0
            };
            grids.extend([
                lat,
                lon,
                l as f64,
                shindo,
                lat - 0.495,
                lon - 0.495,
                lat + 0.495,
                lon - 0.495,
                lat + 0.495,
                lon + 0.495,
                lat - 0.495,
                lon + 0.495,
            ]);
        }
        let mut frame = Frame {
            catalogue: self.catalogue.clone(),
            stations,
            status: self.status.clone(),
            error: self.last_error.clone(),
            frames: self.frames,
            revision: self.revision,
            data_time: self.last,
            received: self.received,
            clock,
            signature,
            summary,
            stage,
            counts,
            entries,
            grids,
            detection_signature,
            automation,
            data_changed,
            original: self.original.clone(),
            events: self.inference.events.clone(),
            archive_tree: vec![],
        };
        frame.archive_tree = frame.pack_archive();
        frame
    }
    pub(super) fn source_frame(&self, clock: i64) -> Frame {
        Frame {
            catalogue: self.catalogue.clone(),
            stations: vec![],
            status: self.status.clone(),
            error: self.last_error.clone(),
            frames: self.frames,
            revision: self.revision,
            data_time: self.last,
            received: self.received,
            clock,
            signature: String::new(),
            summary: -1,
            stage: "idle",
            counts: [0, 0, 0, -1],
            entries: vec![],
            grids: vec![],
            detection_signature: String::new(),
            automation: vec![],
            data_changed: true,
            original: Original::default(),
            events: self.inference.events.clone(),
            archive_tree: vec![],
        }
    }
    fn recorded_snapshot(&mut self, v: &Value, clock: i64, sensitivity: i32) -> bool {
        let rows = v["stations"].as_array().map(Vec::as_slice).unwrap_or(&[]);
        let mut values = vec![];
        for row in rows {
            let Some(_) = row["id"].as_str() else {
                continue;
            };
            let (Some(lat), Some(lng)) = (
                number(&row["coordinate"]["lat"]),
                number(&row["coordinate"]["lng"]),
            ) else {
                continue;
            };
            if lat.abs() > 90.0 || lng.abs() > 180.0 {
                continue;
            }
            values.push(row);
        }
        let same = values.len() == self.catalogue.rows.len()
            && values.iter().zip(&self.catalogue.rows).all(|(a, b)| {
                a["id"].as_str() == Some(b.0[0].as_str())
                    && number(&a["coordinate"]["lat"]) == Some(b.1[0])
                    && number(&a["coordinate"]["lng"]) == Some(b.1[1])
            });
        if !same {
            self.catalogue = Arc::new(Catalogue {
                revision: self.catalogue.revision + 1,
                rows: values
                    .iter()
                    .map(|row| {
                        (
                            [
                                row["id"].as_str().unwrap().to_owned(),
                                label(&row["network"]),
                                label(&row["name"]),
                                label(&row["area"]),
                            ],
                            [
                                number(&row["coordinate"]["lat"]).unwrap(),
                                number(&row["coordinate"]["lng"]).unwrap(),
                            ],
                        )
                    })
                    .collect(),
            });
            self.stations = values
                .iter()
                .map(|row| Station {
                    row: (*row).clone(),
                    history: vec![],
                    result: ka_history::Output {
                        level: -1,
                        ..Default::default()
                    },
                    previous: None,
                    until: 0,
                    state: 0,
                })
                .collect();
            self.configure();
            self.inference.configure(self.catalogue.clone());
        }
        let level = |row: &Value| {
            row["sampledLevel"].as_i64().unwrap_or_else(|| {
                crate::palert_levels::level(
                    measurement(&row["pgaGal"]).unwrap_or(f64::NAN),
                    measurement(&row["pgvCms"]).unwrap_or(f64::NAN),
                ) as i64
            })
        };
        let explicit = v.get("detectedStationIds");
        if explicit.is_none() {
            // Only the detector needs owned mutable rows. Canonical archives
            // already carry confirmed IDs: inference borrows their originals.
            for (station, row) in self.stations.iter_mut().zip(&values) {
                station.row = (*row).clone();
                station.row["sampledLevel"] = json!(level(row));
            }
            self.detect(clock, sensitivity);
        }
        let ids = explicit
            .and_then(Value::as_array)
            .map(|a| {
                a.iter()
                    .filter_map(Value::as_str)
                    .collect::<std::collections::HashSet<_>>()
            })
            .unwrap_or_default();
        let fresh = time(&v["receivedTime"]).is_some_and(|t| clock - t <= 6000);
        let samples = values
            .iter()
            .zip(&self.stations)
            .map(|(row, s)| Sample {
                stamp: time(&row["dataTime"]),
                received: time(&row["receivedAt"]),
                pga: measurement(&row["pgaGal"]).unwrap_or(f64::NAN),
                level: level(row) as i32,
                confirmed: if explicit.is_some() {
                    fresh && ids.contains(row["id"].as_str().unwrap())
                } else {
                    s.until > clock
                },
            })
            .collect::<Vec<_>>();
        self.inference.update(&samples, clock);
        self.frames += 1;
        self.revision += 1;
        self.status = "connected".into();
        self.received = Some(clock);
        self.last = time(&v["dataTime"]);
        true
    }
    pub(super) fn encoded_snapshot(&self, clock: i64, data_changed: bool) -> Vec<u8> {
        let rows = self.stations.iter().map(|s| &s.row).collect::<Vec<_>>();
        let mut active = self
            .stations
            .iter()
            .filter(|s| s.until > clock)
            .collect::<Vec<_>>();
        active.sort_by(|a, b| {
            b.result
                .level
                .cmp(&a.result.level)
                .then_with(|| a.row["id"].as_str().cmp(&b.row["id"].as_str()))
        });
        let weak = active
            .iter()
            .filter(|s| jma(s.result.level as i32) == 0)
            .count();
        let detected = active
            .iter()
            .filter(|s| (1..=3).contains(&jma(s.result.level as i32)))
            .count();
        let strong = active
            .iter()
            .filter(|s| jma(s.result.level as i32) >= 4)
            .count();
        let max = active
            .iter()
            .map(|s| jma(s.result.level as i32))
            .max()
            .unwrap_or(-1);
        let stage = if active.is_empty() {
            "idle"
        } else if strong > 0 {
            "strong"
        } else if detected > 0 {
            "detected"
        } else {
            "weak"
        };
        let entries=active.iter().map(|s|json!({"code":s.row["id"],"prefecture":s.row["area"],"level":s.result.level,"jmaShindo":jma(s.result.level as i32),"detectState":s.state,"detectReason":"kanameishi-chain"})).collect::<Vec<_>>();
        let grids = self
            .grids
            .iter()
            .map(|&(lat, lon, level)| json!([lat, lon, level]))
            .collect::<Vec<_>>();
        let mut signature = rows.len().to_string();
        let mut automation = vec![];
        let mut best: Option<&Value> = None;
        for &row in &rows {
            let level = row["heldLevel"].as_i64().unwrap_or(-1) as i32;
            signature.push_str(&format!(
                "|{}:{}:{}:{}:{}:{}",
                row["id"].as_str().unwrap(),
                level,
                number(&row["pgaGal"]).map_or("-".into(), |v| format!("{v:.3}")),
                number(&row["pgvCms"]).map_or("-".into(), |v| format!("{v:.3}")),
                time(&row["dataTime"]).unwrap_or(0),
                time(&row["receivedAt"]).is_some_and(|t| clock - t <= 12000)
            ));
            if level >= 0
                && best.is_none_or(|b| level > b["heldLevel"].as_i64().unwrap_or(-1) as i32)
            {
                best = Some(row);
            }
            if level >= 0 && !row["dataTime"].is_null() {
                automation.push(json!({"id":row["id"],"name":row["name"],"level":index(level),"intensity":index(level),"coordinate":row["coordinate"],"time":row["dataTime"],"strong":index(level)>=4}));
            }
        }
        let detection = json!({"stage":stage,"weakCount":weak,"detectedCount":detected,"strongCount":strong,"maxShindo":max,"entries":entries});
        let detection_signature = serde_json::to_string(&json!([&detection, &grids])).unwrap();
        let header = json!({"kind":"palert","source":"palert","status":self.status,"dataTime":self.last.map(iso),"receivedTime":self.received.map(iso),"receivedAt":iso(clock),"signature":signature,"automation":automation,"frames":self.frames,"lastError":self.last_error,"dataChanged":data_changed,"detectedStationIds":active.iter().map(|s|s.row["id"].clone()).collect::<Vec<_>>(),"detectionGrid":grids,"detection":detection,"detectionSignature":detection_signature,"grids":self.grids.iter().map(|&(lat,lon,level)|json!({"center":[lat,lon],"level":level,"shindo":if level<0{-3.0}else if level==0{-3.0}else if level>=20{6.5}else{(level as f64+0.5-7.0)/2.0},"points":[[lat-0.495,lon-0.495],[lat+0.495,lon-0.495],[lat+0.495,lon+0.495],[lat-0.495,lon+0.495]]})).collect::<Vec<_>>()});
        let display_row = |row| DisplayRow {
            row,
            recent: time(&row["receivedAt"]).is_some_and(|t| clock - t <= 12000),
        };
        serde_json::to_vec(&DisplaySnapshot {
            header,
            stations: rows.into_iter().map(display_row).collect(),
            summary: best.map(display_row),
        })
        .unwrap()
    }
}
