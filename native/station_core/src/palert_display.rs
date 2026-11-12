//! Prepared P-Alert UI messages. Dart receives native numbers/strings directly;
//! live display never round-trips through UTF-8 JSON.
use super::{iso, DartObject, Post};
use serde::ser::{Serialize, SerializeMap, Serializer};
use serde_json::{json, Value};
use std::{ffi::CString, sync::Arc};

pub(super) fn post_replay_block(
    post: Post,
    port: i64,
    bytes: &[u8],
    expanded: i64,
    error: bool,
) -> bool {
    let mut arena = Arena::default();
    let tag = arena.string("station_replay_block_v1");
    let bytes = arena.object(7, [2, bytes.len() as i64, bytes.as_ptr() as i64, 0, 0]);
    let expanded = arena.int(expanded);
    let error = arena.boolean(error);
    let root = arena.array(vec![tag, bytes, expanded, error]);
    unsafe { post(port, root) }
}

#[derive(Clone, Default)]
pub(super) struct Original {
    pub metadata: Option<Arc<Value>>,
    pub data: Option<Arc<Value>>,
    pub metadata_tree: Option<Arc<Vec<u8>>>,
    pub data_tree: Option<Arc<Vec<u8>>>,
}
impl Serialize for Original {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        let mut map = serializer.serialize_map(None)?;
        if let Some(v) = &self.metadata {
            map.serialize_entry("metadata", v.as_ref())?;
        }
        if let Some(v) = &self.data {
            map.serialize_entry("data", v.as_ref())?;
        }
        map.end()
    }
}
impl Original {
    pub fn metadata(&mut self, value: &Value) {
        self.metadata = Some(Arc::new(value.clone()));
        self.metadata_tree = Some(Arc::new(crate::station_json::pack_value(value)));
    }
    pub fn data(&mut self, value: &Value) {
        self.data = Some(Arc::new(value.clone()));
        self.data_tree = Some(Arc::new(crate::station_json::pack_value(value)));
    }
    pub fn encode(&self) -> Vec<u8> {
        serde_json::to_vec(self).unwrap()
    }
}

pub(super) struct Catalogue {
    pub revision: u64,
    pub rows: Vec<([String; 4], [f64; 2])>,
}
pub(super) struct Frame {
    pub catalogue: Arc<Catalogue>,
    // PGA, PGV, current index, held index, held level, sampled level,
    // observation ms, receive ms, map freshness, measurement presence bits.
    pub stations: Vec<f64>,
    pub status: String,
    pub error: Option<String>,
    pub frames: u64,
    pub revision: u64,
    pub data_time: Option<i64>,
    pub received: Option<i64>,
    pub clock: i64,
    pub signature: String,
    pub summary: i64,
    pub stage: &'static str,
    pub counts: [i64; 4],
    pub entries: Vec<[i64; 4]>,
    pub grids: Vec<f64>,
    pub detection_signature: String,
    // Ready OBS station index, intensity and strong flag; no UI selection.
    pub automation: Vec<i32>,
    pub data_changed: bool,
    pub original: Original,
    pub events: Vec<Value>,
    pub archive_tree: Vec<u8>,
}
impl Frame {
    /// Write the compatible history view directly from the prepared columns.
    /// No per-station JSON maps or second measurement interpretation are needed.
    pub fn pack_archive(&self) -> Vec<u8> {
        use crate::station_json::ViewPacker;
        fn optional_time(p: &mut ViewPacker, value: Option<i64>) -> u32 {
            match value {
                Some(t) => p.text(&iso(t)),
                None => p.reserve(),
            }
        }
        fn optional_int(p: &mut ViewPacker, value: f64) -> u32 {
            if value.is_nan() {
                p.reserve()
            } else {
                p.int(value as i64)
            }
        }
        fn physical(p: &mut ViewPacker, value: f64, present: bool) -> u32 {
            if !present {
                p.reserve()
            } else if value.is_finite() {
                p.double(value)
            } else {
                p.text(if value.is_nan() {
                    "NaN"
                } else if value.is_sign_positive() {
                    "Infinity"
                } else {
                    "-Infinity"
                })
            }
        }
        let mut p = ViewPacker::new();
        let root = p.reserve();
        let list = p.reserve();
        let mut rows = Vec::with_capacity(self.catalogue.rows.len());
        for (i, (names, xy)) in self.catalogue.rows.iter().enumerate() {
            let row = p.reserve();
            let v = &self.stations[i * 10..i * 10 + 10];
            let coordinate = p.reserve();
            let lat = p.double(xy[0]);
            let lng = p.double(xy[1]);
            p.object(coordinate, vec![("lat", lat), ("lng", lng)]);
            let entries = vec![
                ("id", p.text(&names[0])),
                ("network", p.text(&names[1])),
                ("name", p.text(&names[2])),
                ("area", p.text(&names[3])),
                ("coordinate", coordinate),
                ("pgaGal", physical(&mut p, v[0], v[9] as i32 & 1 != 0)),
                ("pgvCms", physical(&mut p, v[1], v[9] as i32 & 2 != 0)),
                ("cwaIntensityIndex", optional_int(&mut p, v[2])),
                ("heldCwaIntensityIndex", optional_int(&mut p, v[3])),
                ("heldLevel", optional_int(&mut p, v[4])),
                ("sampledLevel", optional_int(&mut p, v[5])),
                (
                    "dataTime",
                    optional_time(&mut p, (!v[6].is_nan()).then_some(v[6] as i64)),
                ),
                (
                    "receivedAt",
                    optional_time(&mut p, (!v[7].is_nan()).then_some(v[7] as i64)),
                ),
                ("mapRecent", p.boolean(v[8] != 0.0)),
            ];
            p.object(row, entries);
            rows.push(row);
        }
        p.array(list, rows);
        let ids = p.reserve();
        let children = self
            .entries
            .iter()
            .map(|e| p.text(&self.catalogue.rows[e[0] as usize].0[0]))
            .collect();
        p.array(ids, children);
        let grids = p.reserve();
        let mut cells = Vec::with_capacity(self.grids.len() / 12);
        for g in self.grids.chunks_exact(12) {
            let cell = p.reserve();
            let values = vec![p.double(g[0]), p.double(g[1]), p.int(g[2] as i32 as i64)];
            p.array(cell, values);
            cells.push(cell);
        }
        p.array(grids, cells);
        let entries = vec![
            ("kind", p.text("palert")),
            ("stations", list),
            ("dataTime", optional_time(&mut p, self.data_time)),
            ("receivedTime", optional_time(&mut p, self.received)),
            ("receivedAt", p.text(&iso(self.clock))),
            ("detectedStationIds", ids),
            ("detectionGrid", grids),
        ];
        p.object(root, entries);
        p.finish()
    }
    pub fn post_sources(&self, port: i64, post: Post, delivery: u64) -> bool {
        let mut arena = Arena::default();
        let tag = arena.string("palert_source_ui_v1");
        let count = arena.int(self.frames as i64);
        let events = self.events.iter().map(|v| arena.value(v)).collect();
        let events = arena.array(events);
        let delivery = arena.int(delivery as i64);
        let root = arena.array(vec![tag, count, events, delivery]);
        unsafe { post(port, root) }
    }
    fn row(&self, i: usize) -> Value {
        let (names, xy) = &self.catalogue.rows[i];
        let v = &self.stations[i * 10..i * 10 + 10];
        let opt = |n: f64| {
            if n.is_nan() {
                Value::Null
            } else {
                json!(n as i64)
            }
        };
        let physical = |n: f64, present: bool| {
            if !present {
                Value::Null
            } else if n.is_finite() {
                json!(n)
            } else if n.is_nan() {
                json!("NaN")
            } else if n.is_sign_positive() {
                json!("Infinity")
            } else {
                json!("-Infinity")
            }
        };
        json!({"id":names[0],"network":names[1],"name":names[2],"area":names[3],"coordinate":{"lat":xy[0],"lng":xy[1]},"pgaGal":physical(v[0],v[9] as i32&1!=0),"pgvCms":physical(v[1],v[9] as i32&2!=0),"cwaIntensityIndex":opt(v[2]),"heldCwaIntensityIndex":opt(v[3]),"heldLevel":opt(v[4]),"sampledLevel":opt(v[5]),"dataTime":if v[6].is_nan(){None}else{Some(iso(v[6] as i64))},"receivedAt":if v[7].is_nan(){None}else{Some(iso(v[7] as i64))},"mapRecent":v[8]!=0.0})
    }
    pub fn archive(&self) -> Vec<u8> {
        serde_json::to_vec(&self.archive_value()).unwrap()
    }
    pub fn archive_value(&self) -> Value {
        let rows = (0..self.catalogue.rows.len())
            .map(|i| self.row(i))
            .collect::<Vec<_>>();
        let grid_cells = self
            .grids
            .chunks_exact(12)
            .map(|g| json!([g[0], g[1], g[2] as i32]))
            .collect::<Vec<_>>();
        json!({"kind":"palert","stations":rows,"dataTime":self.data_time.map(iso),"receivedTime":self.received.map(iso),"receivedAt":iso(self.clock),"detectedStationIds":self.entries.iter().map(|e|&self.catalogue.rows[e[0] as usize].0[0]).collect::<Vec<_>>(),"detectionGrid":grid_cells})
    }
    pub fn post(
        &self,
        port: i64,
        post: Post,
        signals: &[i32],
        catalogue: bool,
        delivery: u64,
    ) -> bool {
        let mut arena = Arena::default();
        let catalog = if catalogue {
            let mut rows = Vec::with_capacity(self.catalogue.rows.len());
            for (names, xy) in &self.catalogue.rows {
                let mut row = names.iter().map(|s| arena.string(s)).collect::<Vec<_>>();
                row.push(arena.double(xy[0]));
                row.push(arena.double(xy[1]));
                rows.push(arena.array(row));
            }
            arena.array(rows)
        } else {
            arena.null()
        };
        let status = arena.string(&self.status);
        let error = self
            .error
            .as_ref()
            .map(|s| arena.string(s))
            .unwrap_or_else(|| arena.null());
        let frames = arena.int(self.frames as i64);
        let revision = arena.int(self.revision as i64);
        let data_time = arena.optional_int(self.data_time);
        let received = arena.optional_int(self.received);
        let clock = arena.int(self.clock);
        let signature = arena.string(&self.signature);
        let stations = arena.doubles(&self.stations);
        let summary = arena.int(self.summary);
        let mut entry_rows = vec![];
        for e in &self.entries {
            let fields = e.iter().map(|&n| arena.int(n)).collect();
            entry_rows.push(arena.array(fields));
        }
        let entry_rows = arena.array(entry_rows);
        let stage = arena.string(self.stage);
        let mut detection = vec![stage];
        detection.extend(self.counts.iter().map(|&n| arena.int(n)));
        detection.push(entry_rows);
        detection.push(arena.string(&self.detection_signature));
        detection.push(arena.doubles(&self.grids));
        let detection = arena.array(detection);
        let signals = arena.ints(signals);
        let changed = arena.boolean(self.data_changed);
        let catalog_revision = arena.int(self.catalogue.revision as i64);
        let automation = arena.ints(&self.automation);
        let tag = arena.string("palert_ui_v1");
        let events = self.events.iter().map(|v| arena.value(v)).collect();
        let events = arena.array(events);
        let delivery = arena.int(delivery as i64);
        let root = arena.array(vec![
            tag,
            status,
            error,
            frames,
            revision,
            data_time,
            received,
            clock,
            signature,
            catalog,
            stations,
            summary,
            detection,
            signals,
            changed,
            catalog_revision,
            automation,
            events,
            delivery,
        ]);
        unsafe { post(port, root) }
    }
}

// Dart_PostCObject copies these ordinary typed arrays synchronously. All
// backing storage remains owned until the call returns; no borrowed Dart heap
// pointers, native callbacks into a Dart isolate, or external-data finalizers.
#[derive(Default)]
struct Arena {
    objects: Vec<Box<DartObject>>,
    strings: Vec<CString>,
    arrays: Vec<Vec<*mut DartObject>>,
}
impl Arena {
    fn value(&mut self, v: &Value) -> *mut DartObject {
        match v {
            Value::Null => self.null(),
            Value::Bool(b) => self.boolean(*b),
            Value::Number(n) => {
                if let Some(i) = n.as_i64() {
                    self.int(i)
                } else {
                    self.double(n.as_f64().unwrap())
                }
            }
            Value::String(s) => self.string(s),
            Value::Array(a) => {
                let values = a.iter().map(|v| self.value(v)).collect();
                self.array(values)
            }
            Value::Object(map) => {
                let tag = self.string("palert_display_map_v1");
                let mut pairs = vec![];
                for (k, v) in map {
                    pairs.push(self.string(k));
                    pairs.push(self.value(v));
                }
                let pairs = self.array(pairs);
                self.array(vec![tag, pairs])
            }
        }
    }
    fn object(&mut self, kind: i32, value: [i64; 5]) -> *mut DartObject {
        let mut o = Box::new(DartObject::prepared(kind, value));
        let p = o.as_mut() as *mut _;
        self.objects.push(o);
        p
    }
    fn null(&mut self) -> *mut DartObject {
        self.object(0, [0; 5])
    }
    fn int(&mut self, n: i64) -> *mut DartObject {
        self.object(3, [n, 0, 0, 0, 0])
    }
    fn optional_int(&mut self, n: Option<i64>) -> *mut DartObject {
        n.map(|v| self.int(v)).unwrap_or_else(|| self.null())
    }
    fn double(&mut self, n: f64) -> *mut DartObject {
        self.object(4, [n.to_bits() as i64, 0, 0, 0, 0])
    }
    fn boolean(&mut self, n: bool) -> *mut DartObject {
        self.object(1, [i64::from(n), 0, 0, 0, 0])
    }
    fn string(&mut self, s: &str) -> *mut DartObject {
        let value = CString::new(s.replace('\0', "\u{fffd}")).unwrap();
        let p = value.as_ptr() as i64;
        self.strings.push(value);
        self.object(5, [p, 0, 0, 0, 0])
    }
    fn array(&mut self, v: Vec<*mut DartObject>) -> *mut DartObject {
        let len = v.len() as i64;
        let p = v.as_ptr() as i64;
        self.arrays.push(v);
        self.object(6, [len, p, 0, 0, 0])
    }
    fn doubles(&mut self, v: &[f64]) -> *mut DartObject {
        self.object(7, [11, v.len() as i64, v.as_ptr() as i64, 0, 0])
    }
    fn ints(&mut self, v: &[i32]) -> *mut DartObject {
        self.object(7, [6, v.len() as i64, v.as_ptr() as i64, 0, 0])
    }
}
