//! P-Alert episode picks and reference HYP session. Owned by the native source
//! actor; no calls to a Dart isolate, no held display peak as inference input.
use super::palert_display::Catalogue;
use crate::{hyp_geometry::travel_pair, hyp_score::Scorer, hyp_search::search_coordinates};
use serde_json::{json, Value};
use std::{
    collections::{HashMap, HashSet, VecDeque},
    sync::Arc,
};
#[path = "palert_polynomial.rs"]
mod polynomial;

#[derive(Clone, Copy)]
pub(super) struct Sample {
    pub stamp: Option<i64>,
    pub received: Option<i64>,
    pub pga: f64,
    pub level: i32,
    pub confirmed: bool,
}
#[derive(Clone)]
struct Pick {
    history: VecDeque<(i64, f64, i32)>,
    trigger: Option<i64>,
    boundary: Option<i64>,
    max: i32,
    second: i32,
    peak: Option<f64>,
    second_peak: Option<f64>,
    last_change: Option<i64>,
}
impl Default for Pick {
    fn default() -> Self {
        Self {
            history: VecDeque::new(),
            trigger: None,
            boundary: None,
            max: -1,
            second: -1,
            peak: None,
            second_peak: None,
            last_change: None,
        }
    }
}
impl Pick {
    fn clear_trigger(&mut self) {
        self.trigger = None;
        self.max = -1;
        self.second = -1;
        self.peak = None;
        self.second_peak = None;
        self.last_change = None;
    }
    fn update(&mut self, s: Sample) {
        let Some(time) = s.stamp else {
            return;
        };
        if self.history.back().is_some_and(|h| time <= h.0) {
            return;
        }
        if s.level < 0 {
            *self = Self::default();
            return;
        }
        if self.history.back().is_some_and(|h| time - h.0 > 6000) {
            *self = Self::default();
        }
        if s.level >= 6 || self.boundary.is_none() {
            self.boundary = Some(time);
        }
        if self.trigger.is_none() && self.history.len() >= 8 {
            let previous = *self.history.back().unwrap();
            let background = self
                .history
                .iter()
                .take(self.history.len() - 1)
                .map(|h| h.1)
                .fold(f64::NEG_INFINITY, f64::max);
            let at_least = |a: f64, b: f64| {
                format!("{a:.10}").parse::<f64>().unwrap()
                    >= format!("{b:.10}").parse::<f64>().unwrap()
            };
            if (s.level >= 6 || previous.2 >= 6)
                && previous.1 > 0.0
                && at_least(s.pga, background * 1.5)
                && at_least(previous.1, background * 1.5)
            {
                self.trigger = Some(previous.0);
                self.max = previous.2;
                self.peak = Some(previous.1);
            } else if s.level >= 6
                && s.pga > 0.0
                && at_least(s.pga, background.max(previous.1) * 2.0)
            {
                self.trigger = Some(time);
            }
        }
        if self.trigger.is_some() {
            let old = (self.peak, self.second_peak);
            if s.level >= self.max {
                self.second = self.max;
                self.max = s.level;
            } else if s.level > self.second {
                self.second = s.level;
            }
            if self.peak.is_none_or(|v| s.pga >= v) {
                self.second_peak = self.peak;
                self.peak = Some(s.pga);
            } else if self.second_peak.is_none_or(|v| s.pga > v) {
                self.second_peak = Some(s.pga);
            }
            if old != (self.peak, self.second_peak) {
                self.last_change = Some(time);
            }
            if self.last_change.is_some_and(|t| time - t >= 8000) {
                self.clear_trigger();
            }
        }
        self.history.push_back((time, s.pga, s.level));
        if self.history.len() > 8 {
            self.history.pop_front();
        }
    }
    fn quiet(&self) -> bool {
        self.history.len() == 8 && self.history.iter().all(|s| s.2 < 6)
    }
}
#[derive(Clone, Copy)]
struct Station {
    index: usize,
    trigger: i64,
    update: i64,
    level: i32,
    max: i32,
    second: i32,
    boundary: Option<i64>,
}
#[derive(Clone)]
struct ResultState {
    point: [f64; 3],
    origin: i64,
    origin_exact: f64,
    score: f64,
    quality: f64,
    effective: usize,
    p: i64,
    s: i64,
    prior: HashMap<usize, [i8; 2]>,
    wave_elapsed: f64,
    cap: f64,
    p_radius: f64,
    s_radius: f64,
}
#[derive(Clone)]
struct Cluster {
    id: u64,
    created: i64,
    first: usize,
    members: Vec<Station>,
    updates: u64,
    last_version: u64,
    report: u64,
    stable_count: u64,
    stable: bool,
    report_point: Option<[f64; 3]>,
    stable_point: Option<[f64; 3]>,
    inactive: u32,
    dirty: bool,
    evaluated: bool,
    result: Option<ResultState>,
    published: bool,
}
impl Cluster {
    fn new(id: u64, first: usize, clock: i64) -> Self {
        Self {
            id,
            created: clock,
            first,
            members: vec![],
            updates: 0,
            last_version: 0,
            report: 0,
            stable_count: 0,
            stable: false,
            report_point: None,
            stable_point: None,
            inactive: 0,
            dirty: true,
            evaluated: false,
            result: None,
            published: false,
        }
    }
    fn mark(&mut self, version: u64) {
        self.dirty = true;
        if self.last_version != version {
            self.updates += 1;
            self.last_version = version;
        }
    }
    fn insert(&mut self, s: Station) {
        if let Some(old) = self.members.iter_mut().find(|v| v.index == s.index) {
            *old = s;
            return;
        }
        let p = self.members.partition_point(|v| v.trigger <= s.trigger);
        self.members.insert(p, s);
    }
    fn refresh_publication(&mut self) {
        if !self.published {
            self.stable_point = None;
            self.stable_count = 0;
            self.stable = false;
            return;
        }
        let point = self.result.as_ref().unwrap().point;
        if !same_point(self.report_point, point) {
            self.report += 1;
            self.report_point = Some(point);
        }
        if same_point(self.stable_point, point) {
            self.stable_count += 1;
        } else {
            self.stable_point = Some(point);
            self.stable_count = 1;
            self.stable = false;
        }
        if self.stable_count >= 15 {
            self.stable = true;
        }
    }
}
struct Subcluster {
    id: u64,
    owner: u64,
    stations: Vec<Station>,
}
impl Subcluster {
    fn insert(&mut self, s: Station) {
        if let Some(old) = self.stations.iter_mut().find(|v| v.index == s.index) {
            *old = s;
            return;
        }
        let p = self.stations.partition_point(|v| v.trigger <= s.trigger);
        self.stations.insert(p, s);
    }
}
fn same_point(a: Option<[f64; 3]>, b: [f64; 3]) -> bool {
    a.is_some_and(|a| {
        let d = (a[1] - b[1]).abs();
        (a[0] - b[0]).abs() <= 1e-9 && d.min(360.0 - d) <= 1e-9 && (a[2] - b[2]).abs() <= 1e-9
    })
}
fn km(a: [f64; 2], b: [f64; 2]) -> f64 {
    let r = |n: f64| n * std::f64::consts::PI / 180.0;
    let x = libm::sin(r(b[0] - a[0]) / 2.0);
    let y = libm::sin(r(b[1] - a[1]) / 2.0);
    let q = x * x + libm::cos(r(a[0])) * libm::cos(r(b[0])) * (y * y);
    6371.0 * (2.0 * libm::atan2(libm::sqrt(q), libm::sqrt(1.0 - q)))
}
fn scratch_km(a: [f64; 2], b: [f64; 2]) -> f64 {
    let y = |lat: f64| {
        libm::log(libm::tan(
            std::f64::consts::PI / 4.0 + lat * std::f64::consts::PI / 180.0 / 2.0,
        )) * 180.0
            / std::f64::consts::PI
    };
    let dx = (b[1] - a[1]) * 10.0;
    let dy = (y(b[0]) - y(a[0])) * 10.0;
    libm::sqrt(dx * dx + dy * dy) * 11.0
}
fn intensity(l: i32) -> i32 {
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
fn quality_rank(q: f64, n: usize) -> (&'static str, f64) {
    let score = if q < 0.0 {
        0
    } else if q < 1.0 {
        10
    } else if q < 2.0 {
        30
    } else if q < 3.0 {
        100
    } else {
        200
    };
    for (rank, min, base) in [
        ("S", 200, 0.84),
        ("A", 100, 0.72),
        ("B", 30, 0.58),
        ("C", 10, 0.42),
        ("D", 0, 0.25),
    ] {
        if min <= n && min <= score {
            return (rank, (base + (n as f64 / 500.0).min(0.12)).clamp(0.0, 0.92));
        }
    }
    unreachable!()
}

pub(super) struct Inference {
    catalogue: Arc<Catalogue>,
    adjacency: Vec<Vec<usize>>,
    picks: Vec<Pick>,
    clusters: Vec<Cluster>,
    subclusters: Vec<Subcluster>,
    next_id: u64,
    next_sub: u64,
    version: u64,
    inactive_key: Vec<usize>,
    event_id: Option<i64>,
    last_observed: Option<i64>,
    selected: Option<u64>,
    pub events: Vec<Value>,
}
impl Default for Inference {
    fn default() -> Self {
        Self {
            catalogue: Arc::new(Catalogue {
                revision: 0,
                rows: vec![],
            }),
            adjacency: vec![],
            picks: vec![],
            clusters: vec![],
            subclusters: vec![],
            next_id: 1,
            next_sub: 1,
            version: 0,
            inactive_key: vec![],
            event_id: None,
            last_observed: None,
            selected: None,
            events: vec![],
        }
    }
}
impl Inference {
    pub fn configure(&mut self, catalogue: Arc<Catalogue>) {
        *self = Self::default();
        self.catalogue = catalogue;
        self.picks = vec![Pick::default(); self.catalogue.rows.len()];
        let xy = self
            .catalogue
            .rows
            .iter()
            .flat_map(|r| r.1)
            .collect::<Vec<_>>();
        let mut out = vec![u32::MAX; self.picks.len() * 12];
        let status = unsafe {
            crate::palert_topology::rq_palert_topology(
                xy.as_ptr(),
                self.picks.len(),
                out.as_mut_ptr(),
            )
        };
        assert_eq!(status, 0, "P-Alert inference topology");
        self.adjacency = out
            .chunks_exact(12)
            .map(|r| {
                r.iter()
                    .filter(|&&v| v != u32::MAX)
                    .map(|&v| v as usize)
                    .collect()
            })
            .collect();
    }
    pub fn clear_episode(&mut self) {
        self.clusters.clear();
        self.subclusters.clear();
        self.next_id = 1;
        self.next_sub = 1;
        self.inactive_key.clear();
        self.event_id = None;
        self.selected = None;
        self.events.clear();
    }
    fn create(&mut self, s: Station, clock: i64) -> u64 {
        let id = self.next_id;
        self.next_id += 1;
        self.clusters.push(Cluster::new(id, s.index, clock));
        id
    }
    fn create_sub(&mut self, owner: u64, stations: Vec<Station>) -> u64 {
        let id = self.next_sub;
        self.next_sub += 1;
        self.subclusters.push(Subcluster {
            id,
            owner,
            stations,
        });
        id
    }
    fn sync_subclusters(&mut self) {
        let ids = self.clusters.iter().map(|c| c.id).collect::<HashSet<_>>();
        self.subclusters.retain(|c| ids.contains(&c.owner));
        let missing = self
            .clusters
            .iter()
            .filter(|c| !self.subclusters.iter().any(|s| s.owner == c.id))
            .map(|c| (c.id, c.members.clone()))
            .collect::<Vec<_>>();
        for (id, stations) in missing {
            self.create_sub(id, stations);
        }
    }
    fn merge(&mut self, ids: &[u64], stations: Vec<Station>, clock: i64, mark: bool) -> u64 {
        let source = self
            .clusters
            .iter()
            .filter(|c| ids.contains(&c.id))
            .reduce(|a, b| {
                if a.members.len() > b.members.len()
                    || (a.members.len() == b.members.len() && a.updates >= b.updates)
                {
                    a
                } else {
                    b
                }
            })
            .unwrap()
            .clone();
        self.clusters.retain(|c| !ids.contains(&c.id));
        let id = self.create(stations[0], clock);
        let merged = self.clusters.last_mut().unwrap();
        merged.updates = source.updates;
        merged.last_version = source.last_version;
        merged.report = source.report;
        merged.report_point = source.report_point;
        merged.stable_point = source.stable_point;
        merged.stable_count = source.stable_count;
        merged.stable = source.stable;
        merged.result = source.result;
        for station in stations {
            merged.insert(station);
        }
        if mark {
            merged.mark(self.version);
        }
        id
    }
    pub fn update(&mut self, samples: &[Sample], clock: i64) {
        assert_eq!(samples.len(), self.picks.len());
        let mut active = vec![];
        let mut inactive = vec![];
        let mut observed = None;
        let mut max_index = -1;
        for (i, &sample) in samples.iter().enumerate() {
            let pick = &mut self.picks[i];
            if sample.stamp.is_none() || sample.received.is_none_or(|t| clock - t > 6000) {
                *pick = Pick::default();
                continue;
            }
            pick.update(sample);
            if pick.history.is_empty() {
                continue;
            }
            observed = Some(observed.unwrap_or(i64::MIN).max(sample.stamp.unwrap()));
            let s = Station {
                index: i,
                trigger: pick.trigger.unwrap_or(0),
                update: sample.stamp.unwrap(),
                level: sample.level,
                max: pick.max,
                second: pick.second,
                boundary: pick.boundary,
            };
            if sample.confirmed {
                max_index = max_index.max(intensity(sample.level));
            }
            let xy = self.catalogue.rows[i].1;
            let usable = xy[0].abs() <= 90.0
                && xy[1].abs() <= 180.0
                && !(xy[0].abs() < 1e-5 && xy[1].abs() < 1e-5);
            if sample.confirmed && pick.trigger.is_some() && usable {
                active.push(s);
            } else if pick.quiet() && !sample.confirmed && usable {
                inactive.push(s);
            }
        }
        if active.is_empty() || observed.is_none() {
            self.clear_episode();
            return;
        }
        let observed = observed.unwrap();
        if self.last_observed.is_some_and(|t| observed < t) {
            self.clear_episode();
        }
        self.last_observed = Some(observed);
        self.event_id.get_or_insert(observed);
        self.version += 1;
        self.sync_subclusters();
        let inactive_key = inactive.iter().map(|s| s.index).collect::<Vec<_>>();
        if inactive_key != self.inactive_key {
            self.inactive_key = inactive_key;
            for c in &mut self.clusters {
                c.mark(self.version);
            }
        }
        for station in &active {
            for cluster in &mut self.clusters {
                if let Some(old) = cluster
                    .members
                    .iter_mut()
                    .find(|s| s.index == station.index)
                {
                    let dirty = old.level != old.level.max(station.level)
                        || old.max != station.max
                        || old.second != station.second;
                    old.level = old.level.max(station.level);
                    old.update = station.update;
                    old.max = station.max;
                    old.second = station.second;
                    old.boundary = station.boundary;
                    if dirty {
                        cluster.mark(self.version);
                    }
                    break;
                }
            }
        }
        for &station in &active {
            if self
                .clusters
                .iter()
                .any(|c| c.members.iter().any(|s| s.index == station.index))
            {
                continue;
            }
            let mut neighbors = vec![];
            for neighbor in &self.adjacency[station.index] {
                if let Some(sub) = self
                    .subclusters
                    .iter()
                    .find(|s| s.stations.iter().any(|v| v.index == *neighbor))
                {
                    if !neighbors.contains(&sub.id) {
                        neighbors.push(sub.id);
                    }
                }
            }
            let mut best = None;
            let mut residual = f64::INFINITY;
            for sub in &self.subclusters {
                let cluster = self.clusters.iter().find(|c| c.id == sub.owner).unwrap();
                let Some(result) = &cluster.result else {
                    continue;
                };
                if !result.score.is_finite() {
                    continue;
                }
                let xy = self.catalogue.rows[station.index].1;
                let distance = km([result.point[0], result.point[1]], xy);
                let (p, s) = travel_pair(distance, result.point[2]);
                let observed = (station.trigger as f64 - result.origin_exact) / 1000.0;
                let r = (observed - p).abs().min((observed - s).abs());
                if r <= if sub.stations.len() >= 50 { 7.5 } else { 5.0 } && r < residual {
                    best = Some(sub.id);
                    residual = r;
                }
            }
            if let Some(best) = best {
                if !neighbors.contains(&best) {
                    neighbors.push(best);
                }
            }
            let owner = if neighbors.is_empty() {
                let id = self.create(station, observed);
                self.create_sub(id, vec![]);
                id
            } else if neighbors.len() == 1 {
                self.subclusters
                    .iter()
                    .find(|s| s.id == neighbors[0])
                    .unwrap()
                    .owner
            } else {
                let mut owners = vec![];
                for id in &neighbors {
                    let owner = self.subclusters.iter().find(|s| s.id == *id).unwrap().owner;
                    if !owners.contains(&owner) {
                        owners.push(owner);
                    }
                }
                let mut stations = vec![station];
                for owner in &owners {
                    stations.extend(
                        self.clusters
                            .iter()
                            .find(|c| c.id == *owner)
                            .unwrap()
                            .members
                            .iter()
                            .copied(),
                    );
                }
                let id = self.merge(&owners, stations, observed, true);
                let mut merged = Subcluster {
                    id: self.next_sub,
                    owner: id,
                    stations: vec![],
                };
                self.next_sub += 1;
                merged.insert(station);
                for old in &neighbors {
                    for &s in &self
                        .subclusters
                        .iter()
                        .find(|s| s.id == *old)
                        .unwrap()
                        .stations
                    {
                        merged.insert(s);
                    }
                }
                self.subclusters.retain(|s| !neighbors.contains(&s.id));
                self.subclusters.push(merged);
                id
            };
            let cluster = self.clusters.iter_mut().find(|c| c.id == owner).unwrap();
            cluster.insert(station);
            cluster.mark(self.version);
            if let Some(sub) = self.subclusters.iter_mut().find(|s| s.owner == owner) {
                sub.insert(station);
            } else {
                self.create_sub(owner, vec![station]);
            }
        }
        let ids = active.iter().map(|s| s.index).collect::<HashSet<_>>();
        for c in &mut self.clusters {
            if !c.members.is_empty() && c.members.iter().all(|s| !ids.contains(&s.index)) {
                c.mark(self.version);
                c.inactive += 1;
            } else {
                c.inactive = 0;
            }
        }
        self.clusters.retain(|c| c.inactive < 10);
        // The existing estimator publishes assignment metadata before its
        // result-based close-cluster merge. Magnitude consumes that exact
        // frame's assignment snapshot, including a newly merged ID's first
        // frame without assigned magnitude stations.
        let magnitude_assignments = self
            .clusters
            .iter()
            .flat_map(|c| c.members.iter().map(move |s| (s.index, c.id)))
            .collect::<HashMap<_, _>>();
        loop {
            for c in &mut self.clusters {
                if c.evaluated && !c.dirty {
                    c.published = c.result.is_some();
                    continue;
                }
                evaluate(c, &inactive, &self.adjacency, &self.catalogue, observed);
                c.refresh_publication();
                c.evaluated = true;
                c.dirty = false;
            }
            let mut pair = None;
            'pairs: for (i, a) in self.clusters.iter().enumerate() {
                for (j, b) in self.clusters.iter().enumerate().skip(i + 1) {
                    if let (Some(a), Some(b)) = (&a.result, &b.result) {
                        let longitude = (a.point[1] - b.point[1]).abs();
                        if a.score.is_finite()
                            && b.score.is_finite()
                            && (a.point[0] - b.point[0]).abs() <= 1.0
                            && longitude.min(360.0 - longitude) <= 1.0
                            && (a.point[2] - b.point[2]).abs() <= 100.0
                            && (a.origin - b.origin).abs() <= 10000
                        {
                            pair = Some((i, j));
                            break 'pairs;
                        }
                    }
                }
            }
            // Preserve insertion order when close clusters are reconstituted.
            let Some((left, right)) = pair else {
                break;
            };
            let owners = [self.clusters[left].id, self.clusters[right].id];
            let mut members = self.clusters[left].members.clone();
            members.extend(self.clusters[right].members.iter().copied());
            self.merge(&owners, members, observed, false);
        }
        let candidates = self
            .clusters
            .iter()
            .filter(|c| c.published)
            .collect::<Vec<_>>();
        let selected = candidates
            .iter()
            .copied()
            .reduce(|a, b| {
                let overlap =
                    |c: &Cluster| c.members.iter().filter(|s| ids.contains(&s.index)).count();
                let l = overlap(a);
                let r = overlap(b);
                if l > r
                    || (l == r
                        && (Some(a.id) == self.selected
                            || (Some(b.id) != self.selected && a.id > b.id)))
                {
                    a
                } else {
                    b
                }
            })
            .map(|c| c.id);
        if selected.is_some() {
            self.selected = selected;
        }
        self.events.clear();
        for c in &self.clusters {
            if !c.published {
                continue;
            }
            let result = c.result.as_ref().unwrap();
            if result.effective < 5
                || !result.quality.is_finite()
                || result.quality < -3.0
                || result.score >= 1e12
                || result.point.iter().any(|v| !v.is_finite())
                || result.point[0].abs() > 90.0
                || result.point[1].abs() > 180.0
                || result.point[2] < 0.0
            {
                continue;
            }
            let (rank, confidence) = quality_rank(result.quality, result.effective);
            let mut magnitudes = vec![];
            let mut magnitude_ids = vec![];
            for (i, pick) in self.picks.iter().enumerate() {
                if magnitude_assignments.get(&i) != Some(&c.id) {
                    continue;
                }
                let Some(pga) = pick.peak else {
                    continue;
                };
                if !pga.is_finite() || pga <= 0.0 {
                    continue;
                }
                let xy = self.catalogue.rows[i].1;
                let [lat, lng, depth] = result.point;
                let mean = (lat + xy[0]) / 2.0;
                let lat_scale = ((-0.000003885162 * mean + 0.0005279958) * mean - 0.004162794)
                    * mean
                    + 110.60424;
                let lng_scale =
                    ((0.0000614022 * mean - 0.0204) * mean + 0.091614) * mean + 110.44248;
                let dy = (lat - xy[0]) * lat_scale;
                let dx = (lng - xy[1]) * lng_scale;
                let surface = libm::sqrt(dx * dx + dy * dy);
                let distance = libm::sqrt(surface * surface + depth * depth);
                if !distance.is_finite() || distance <= 0.0 {
                    continue;
                }
                let m = (libm::log(pga / 1.657) + 1.607 * libm::log(distance)) / 1.533;
                if m.is_finite() {
                    magnitudes.push(m);
                    magnitude_ids.push(&self.catalogue.rows[i].0[0]);
                }
            }
            let magnitude = if magnitudes.len() < 5 {
                None
            } else {
                magnitudes.sort_by(f64::total_cmp);
                let n = magnitudes.len();
                let m = if n % 2 == 1 {
                    magnitudes[n / 2]
                } else {
                    (magnitudes[n / 2 - 1] + magnitudes[n / 2]) / 2.0
                };
                if m < 0.0 {
                    None
                } else {
                    Some(m)
                }
            };
            let mut diagnostics = json!({"error_level":result.score,"quality_score":result.quality,"quality_rank":rank,"wave_counts":{"P":result.p,"S":result.s,"O":c.members.len() as i64-result.effective as i64},"score":result.score,"wave_elapsed_s":result.wave_elapsed,"wave_radius_cap_km":result.cap,"best_source_p_radius_km":result.p_radius,"best_source_s_radius_km":result.s_radius,"nied_dart_hyp_report_num":c.report,"nied_dart_hyp_stable":c.stable,"nied_dart_hyp_stable_update_count":c.stable_count,"nied_dart_hyp_selected":Some(c.id)==selected,"selected_detection_id":c.id});
            if magnitude.is_some() {
                let m = diagnostics.as_object_mut().unwrap();
                m.insert(
                    "palert_magnitude_model".into(),
                    json!("taiwan_pga_attenuation_inverse_median_v1"),
                );
                m.insert("palert_magnitude_preliminary".into(), json!(true));
                m.insert(
                    "palert_magnitude_station_codes".into(),
                    json!(magnitude_ids),
                );
                m.insert(
                    "palert_magnitude_station_count".into(),
                    json!(magnitudes.len()),
                );
                m.insert(
                    "palert_magnitude_site_corrections".into(),
                    json!("unavailable_unit_factor"),
                );
            }
            self.events.push(json!([
                format!("palert-{}:{}", self.event_id.unwrap(), c.id),
                result.origin,
                clock,
                result.point,
                magnitude,
                confidence,
                result.effective,
                diagnostics,
                max_index
            ]));
        }
    }
}

fn evaluate(
    c: &mut Cluster,
    inactive: &[Station],
    adjacency: &[Vec<usize>],
    catalogue: &Catalogue,
    observed: i64,
) {
    let active = &c.members;
    if active.len() < 5 {
        c.published = false;
        return;
    }
    let earliest = active[0].trigger;
    let first = active.iter().find(|s| s.index == c.first).unwrap();
    let max_distance = active
        .iter()
        .map(|s| scratch_km(catalogue.rows[first.index].1, catalogue.rows[s.index].1))
        .fold(0.0, f64::max);
    let age = (observed - c.created) as f64 / 1000.0;
    if age < 120.0 {
        let mut coordinates = vec![];
        let mut info = vec![];
        let mut seconds = vec![];
        let prior = c.result.as_ref().map(|r| &r.prior);
        for s in active {
            coordinates.extend(catalogue.rows[s.index].1);
            seconds.push((s.trigger - earliest) as f64 / 1000.0);
            let old = prior
                .and_then(|p| p.get(&s.index))
                .copied()
                .unwrap_or([-1, -1]);
            info.extend([
                adjacency[s.index].len() as i64,
                0,
                s.level as i64,
                1,
                s.max as i64,
                s.second as i64,
                old[0] as i64,
                old[1] as i64,
            ]);
        }
        let neighbors = active
            .iter()
            .flat_map(|s| adjacency[s.index].iter().copied())
            .collect::<HashSet<_>>();
        let mut inactive_count = 0;
        if active.iter().any(|s| s.second >= 9) {
            for s in inactive {
                if active.iter().any(|a| a.index == s.index)
                    || !neighbors.contains(&s.index)
                    || s.boundary.is_none_or(|t| t >= earliest)
                {
                    continue;
                }
                coordinates.extend(catalogue.rows[s.index].1);
                inactive_count += 1;
            }
        }
        let start = if let Some(r) = &c.result {
            r.point
        } else {
            let seeds = active
                .iter()
                .take_while(|s| s.trigger == earliest)
                .collect::<Vec<_>>();
            let lat = seeds
                .iter()
                .map(|s| catalogue.rows[s.index].1[0])
                .sum::<f64>()
                / seeds.len() as f64;
            let lng = seeds
                .iter()
                .map(|s| catalogue.rows[s.index].1[1])
                .sum::<f64>()
                / seeds.len() as f64;
            [(lat / 0.1).round() * 0.1, (lng / 0.1).round() * 0.1, 10.0]
        };
        let mut scorer = Scorer::new(&info, &seconds, inactive_count);
        let (point, output, waves) =
            search_coordinates(&mut scorer, start, &coordinates).expect("native HYP source search");
        let selected = output[0] as i32;
        if selected < 0 {
            c.published = false;
            return;
        }
        let value = &output[3 + selected as usize * 16..];
        if value[9] <= 0.0 || value[4] <= 0.0 || !value[2].is_finite() {
            c.published = false;
            return;
        }
        let mut prior = HashMap::new();
        for (i, s) in active.iter().enumerate() {
            let p = if output[1] >= 0.0 { waves[i] } else { -1 };
            let q = if output[2] >= 0.0 {
                waves[active.len() + i]
            } else {
                -1
            };
            prior.insert(s.index, [p, q]);
        }
        let origin_exact = earliest as f64 + value[1] * 1000.0;
        c.result = Some(ResultState {
            point: [point[0], point[1], point[2]],
            origin: earliest + (value[1] * 1000.0).round() as i64,
            origin_exact,
            score: value[2],
            quality: value[10],
            effective: value[9] as usize,
            p: value[11] as i64,
            s: value[12] as i64,
            prior,
            wave_elapsed: 0.0,
            cap: 0.0,
            p_radius: 0.0,
            s_radius: 0.0,
        });
    }
    if let Some(r) = &mut c.result {
        r.wave_elapsed = ((observed - r.origin) as f64 / 1000.0).max(0.0);
        r.cap = 100.0 + max_distance * 3.0;
        if r.wave_elapsed >= 300.0 {
            r.p_radius = 999999.0;
            r.s_radius = 999999.0;
        } else {
            r.p_radius = polynomial::evaluate(r.wave_elapsed, r.point[2], true, false)
                .1
                .min(r.cap);
            r.s_radius = polynomial::evaluate(r.wave_elapsed, r.point[2], false, false)
                .1
                .min(r.cap);
        }
        c.published = true;
    } else {
        c.published = false;
    }
}
