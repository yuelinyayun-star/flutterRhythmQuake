use crate::unified_event_policy::*;
use serde_json::{json, Value};
use std::collections::HashMap;

#[derive(Default)]
pub struct Engine {
    pub identity: Identity,
    pub active: Vec<Value>,
    pub history: Vec<Vec<Value>>,
    history_first: Vec<i64>,
    history_ids: Vec<String>,
    dismissed: Times,
    reviewed: Times,
    canceled: Times,
    ignored: HashMap<String, i64>,
    ignored_order: Vec<String>,
    accepted_eew: HashMap<String, i64>,
    accepted_eew_seen: Times,
    no_update_seen: Times,
    bodies: HashMap<String, Times>,
    deadlines: HashMap<String, i64>,
    effects: HashMap<String, (i64, Value)>,
    config: Value,
    clock: i64,
    now: i64,
    source_now: i64,
    eew_now: i64,
    offset: i64,
    next_view: i64,
    views: Vec<Value>,
    actions: Vec<Value>,
    persist_due: Option<i64>,
    catalog: crate::unified_catalog_history::CatalogHistory,
    bucket_policy: crate::unified_catalog_bucket::BucketPolicy,
    early_rows: Vec<Value>,
    lpgm_display: crate::jma_lpgm_display::LpgmDisplay,
}
impl Engine {
    fn remember_ignored(&mut self, key: String, number: i64) {
        if !self.ignored.contains_key(&key) {
            self.ignored_order.push(key.clone());
        }
        self.ignored.insert(key, number);
    }
    fn startup_history(&mut self, c: &Value) {
        let Some(input) = c["groups"].as_array() else {
            return;
        };
        let restored = i(c, "restoredCount") as usize;
        let mut groups = Vec::<(usize, String, i64, Vec<Value>)>::new();
        let mut index = HashMap::new();
        for (j, raw) in input.iter().enumerate() {
            let Some(rows) = raw.as_array() else {
                continue;
            };
            if rows.is_empty() {
                continue;
            }
            if rows.iter().any(|e| {
                self.config["blockedSources"]
                    .as_array()
                    .is_some_and(|v| v.iter().any(|source| source == s(e, "source")))
            }) {
                continue;
            }
            let id = c["eventIds"][j]
                .as_str()
                .unwrap_or(s(&rows[0], "eventId"))
                .to_owned();
            let key = (s(&rows[0], "source").to_owned(), id.clone());
            let first = c["firstArrivedUs"][j].as_i64().unwrap_or(self.now);
            if let Some(&old_index) = index.get(&key) {
                let old: &mut (usize, String, i64, Vec<Value>) = &mut groups[old_index];
                if j < restored {
                    *old = (j, id, first, rows.clone());
                } else {
                    for e in rows.iter().rev() {
                        let records = &mut old.3;
                        let duplicate = records.iter().position(|v| {
                            if s(v, "source") == "iclEew" && s(e, "source") == "iclEew" {
                                report_sort(v) == report_sort(e)
                            } else {
                                v["reportNumText"] == e["reportNumText"]
                                    && v["isCanceled"] == e["isCanceled"]
                            }
                        });
                        if let Some(k) = duplicate {
                            if s(e, "source") != "iclEew" {
                                records[k] = e.clone();
                            }
                        } else {
                            records.insert(0, e.clone());
                        }
                        records.sort_by(|a, bv| {
                            b(bv, "isCanceled")
                                .cmp(&b(a, "isCanceled"))
                                .then_with(|| report_sort(bv).cmp(&report_sort(a)))
                        });
                    }
                }
            } else {
                index.insert(key, groups.len());
                groups.push((j, id, first, rows.clone()));
            }
        }
        self.history = groups.iter().map(|v| v.3.clone()).collect();
        self.history_ids = groups.iter().map(|v| v.1.clone()).collect();
        self.history_first = groups.iter().map(|v| v.2).collect();
        for j in (0..self.history.len()).rev() {
            let first = self.history[j][0].clone();
            let mut anchor = first.clone();
            for k in 0..self.active.len() {
                let active = self.active[k].clone();
                if self.identity.same_eew(&active, &first) {
                    anchor = active;
                    break;
                }
            }
            for report in &self.history[j] {
                self.identity.remember_alias(&anchor, report, true);
            }
            if b(&first, "isCanceled") {
                self.canceled.put(
                    self.key(&first),
                    absolute(s(&first, "arrivedAt"), self.offset).unwrap_or(self.history_first[j]),
                );
            }
        }
        self.canceled.prune(self.now, 24 * 3600 * SECOND, 200);
        self.actions.push(json!([
            "startupHistory",
            groups
                .iter()
                .map(|v| json!([v.0, v.3.iter().map(|e| i(e, "$token")).collect::<Vec<_>>()]))
                .collect::<Vec<_>>()
        ]));
        self.retain_history();
        self.action("persistSeen", &Value::Null);
    }
    pub fn next_deadline(&self) -> Option<i64> {
        self.deadlines
            .values()
            .copied()
            .chain(self.effects.values().map(|v| v.0))
            .chain(self.persist_due)
            .chain(self.lpgm_display.next_deadline())
            .min()
    }
    fn cfg(&self, k: &str) -> bool {
        b(&self.config, k)
    }
    fn key(&self, e: &Value) -> String {
        self.identity.key(e)
    }
    fn first(&self, e: &Value) -> Option<&Value> {
        let key = self.key(e);
        self.active.iter().find(|v| self.key(v) == key)
    }
    fn remaining(&self, e: &Value) -> i64 {
        remaining(
            e,
            self.first(e),
            self.now,
            if b(e, "isEew") {
                self.eew_now
            } else {
                self.source_now
            },
            self.offset,
            self.cfg("showStale"),
        )
    }
    fn action(&mut self, kind: &str, e: &Value) {
        if kind.starts_with("persist") {
            self.persist_due.get_or_insert(self.clock + 250_000);
            return;
        }
        self.actions.push(json!([kind, i(e, "$token")]));
    }
    fn list(&mut self, e: &Value) {
        if b(e, "isEew") {
            return;
        }
        if s(e, "source") == "earlyEst" && !e["originTime"].is_null() {
            // Admission must see a history report immediately, even while its
            // immutable UI row is waiting for the asynchronous list binding.
            let mut row = e.clone();
            row["$quakeSource"] = json!("earlyEst");
            row["reviewType"] = message_fields(e)["reviewType"].clone();
            row["$historyRecord"] = json!(true);
            let result=self.bucket_policy.upsert(&json!({"bucket":"earlyEst","rows":self.early_rows,"incoming":row,"replayOnly":b(e,"isHistory")}));
            self.early_rows = result["indices"]
                .as_array()
                .unwrap()
                .iter()
                .map(|j| {
                    let j = j.as_i64().unwrap();
                    if j < 0 {
                        row.clone()
                    } else {
                        self.early_rows[j as usize].clone()
                    }
                })
                .collect();
        }
        self.actions
            .push(json!(["list", i(e, "$token"), message_fields(e)]));
    }
    fn view(&mut self, mut e: Value, base: i64, inherit: Value, arrival: Option<&Value>) -> Value {
        self.next_view -= 1;
        let token = self.next_view;
        e["$token"] = json!(token);
        if let Some(value) = arrival {
            e["arrivedAt"] = value.clone();
        }
        let arrival = absolute(s(&e, "arrivedAt"), self.offset);
        self.views.push(json!({"id":token,"base":base,"inherit":inherit,"arrivalUs":arrival,"arrivalUtc":s(&e,"arrivedAt").ends_with('Z')}));
        e
    }
    fn stamp(&self, e: &Value) -> Value {
        if e["arrivedAt"].is_null() {
            self.config["nowIso"].clone()
        } else {
            e["arrivedAt"].clone()
        }
    }
    fn remember(&mut self, e: &Value) {
        if !b(e, "isEew") {
            self.identity.remember(e, self.now);
        } else {
            let key = self.key(e);
            let old = self.accepted_eew.get(&key).copied().unwrap_or(report(e));
            self.accepted_eew.insert(key.clone(), old.max(report(e)));
            self.accepted_eew_seen.put(key, self.now);
            self.accepted_eew_seen
                .prune(self.now, 24 * 3600 * SECOND, 100);
            self.accepted_eew
                .retain(|k, _| self.accepted_eew_seen.values.contains_key(k));
        }
        self.action("persistSeen", e);
    }
    fn remember_no_update(&mut self, e: &Value) {
        if let Some(key) = no_update_key(&self.identity, e) {
            self.no_update_seen.put(key, self.now);
            self.no_update_seen.prune(self.now, 48 * 3600 * SECOND, 500);
            self.action("persistNoUpdate", e);
        }
    }
    fn same_eew_index(&mut self, e: &Value) -> Option<usize> {
        for j in 0..self.active.len() {
            let old = self.active[j].clone();
            if b(&old, "isEew") && self.identity.same_eew(&old, e) {
                return Some(j);
            }
        }
        None
    }
    fn add_history(&mut self, e: Value) {
        let mut index = None;
        for j in 0..self.history.len() {
            if self.history[j].is_empty() {
                continue;
            }
            let old = self.history[j][0].clone();
            if (s(&old, "source") == s(&e, "source") && self.history_ids[j] == s(&e, "eventId"))
                || self.identity.same_eew(&old, &e)
            {
                index = Some(j);
                break;
            }
        }
        let old_index = index;
        if let Some(j) = index {
            let records = &mut self.history[j];
            let duplicate = records.iter().position(|v| {
                if s(v, "source") == "iclEew" && s(&e, "source") == "iclEew" {
                    report_sort(v) == report_sort(&e)
                } else {
                    v["reportNumText"] == e["reportNumText"] && v["isCanceled"] == e["isCanceled"]
                }
            });
            if let Some(k) = duplicate {
                if s(&e, "source") != "iclEew" {
                    records[k] = e.clone();
                }
            } else {
                records.insert(0, e.clone());
            }
            records.sort_by(|a, bv| {
                b(bv, "isCanceled")
                    .cmp(&b(a, "isCanceled"))
                    .then_with(|| report_sort(bv).cmp(&report_sort(a)))
            });
        } else {
            self.history.insert(0, vec![e.clone()]);
            self.history_first.insert(
                0,
                absolute(s(&e, "arrivedAt"), self.offset).unwrap_or(self.now),
            );
            self.history_ids.insert(0, s(&e, "eventId").into());
            index = Some(0);
        }
        let index = index.unwrap();
        self.actions.push(json!([
            "history",
            old_index,
            index,
            self.history[index]
                .iter()
                .map(|v| i(v, "$token"))
                .collect::<Vec<_>>()
        ]));
        if self.cfg("historyLoaded") {
            self.retain_history();
        }
    }
    fn retain_history(&mut self) {
        let mut order = (0..self.history.len()).collect::<Vec<_>>();
        order.sort_by_key(|&j| std::cmp::Reverse(self.history_first[j]));
        if !self.cfg("historyKeepForever") {
            let max = i(&self.config, "historyMaxPerSource").max(1);
            let mut counts = HashMap::<String, i64>::new();
            order.retain(|&j| {
                let source = s(&self.history[j][0], "source").to_owned();
                let count = counts.entry(source).or_default();
                *count += 1;
                *count <= max
            });
        }
        let unchanged =
            order.len() == self.history.len() && order.iter().enumerate().all(|(i, &j)| i == j);
        if !unchanged {
            self.actions.push(json!(["historyOrder", order]));
            self.history = order.iter().map(|&j| self.history[j].clone()).collect();
            self.history_first = order.iter().map(|&j| self.history_first[j]).collect();
            self.history_ids = order.iter().map(|&j| self.history_ids[j].clone()).collect();
        }
    }
    fn schedule(&mut self, e: &Value) {
        let left = self.remaining(e).clamp(1, duration(e));
        self.deadlines
            .insert(self.key(e), self.clock.saturating_add(left * SECOND));
    }
    fn sort(&mut self) {
        let offset = self.offset;
        let now = self.now;
        self.active.sort_by(|a, bv| {
            let ar = !s(a, "$replaySessionId").is_empty();
            let br = !s(bv, "$replaySessionId").is_empty();
            if b(a, "isEew") && !ar && br {
                return std::cmp::Ordering::Less;
            }
            if b(bv, "isEew") && !br && ar {
                return std::cmp::Ordering::Greater;
            }
            b(bv, "isEew").cmp(&b(a, "isEew")).then_with(|| {
                absolute(s(bv, "arrivedAt"), offset)
                    .unwrap_or(now)
                    .cmp(&absolute(s(a, "arrivedAt"), offset).unwrap_or(now))
            })
        });
    }
    fn suppressed_body(&mut self, e: &Value) -> bool {
        let Some(key) = body_cache_key(e) else {
            return false;
        };
        let source = if s(e, "source") == "emscEqlist" {
            "emsc"
        } else {
            s(e, "source")
        };
        let cache = self.bodies.entry(source.into()).or_default();
        cache.prune(self.now, 24 * 3600 * SECOND, 1000);
        let found = cache.values.contains_key(&key);
        cache.put(key, self.now);
        if !found {
            self.action("persistBodies", e);
        }
        found
    }
    fn no_update_blocked(&mut self, e: &Value) -> bool {
        let Some(key) = no_update_key(&self.identity, e) else {
            return false;
        };
        self.no_update_seen.prune(self.now, 48 * 3600 * SECOND, 500);
        self.no_update_seen.values.contains_key(&key)
            && !self
                .active
                .iter()
                .any(|v| no_update_key(&self.identity, v).as_ref() == Some(&key))
    }
    fn freshness(&self, e: &Value, previous: Option<&Value>) -> bool {
        if !b(e, "isEew") || !b(e, "isCanceled") || b(e, "isHistory") {
            return false;
        }
        if previous.is_some_and(|v| !cancellation_transition(v, e)) {
            return false;
        }
        if let Some(t) = instant(
            e,
            if e["reportTime"].is_null() {
                "originTime"
            } else {
                "reportTime"
            },
        ) {
            let age = self.eew_now - i(e, "$replayOffsetUs") - t;
            if (-5 * SECOND..20 * SECOND).contains(&age) {
                return true;
            }
        }
        previous.is_some_and(|old| {
            absolute(s(old, "arrivedAt"), self.offset)
                .is_some_and(|t| self.now >= t && self.now - t < timeout(old) * SECOND)
        })
    }
    pub fn admit(&mut self, e: Value, accepted: bool, suppress: bool) {
        if self.config["blockedSources"]
            .as_array()
            .is_some_and(|v| v.iter().any(|v| v == s(&e, "source")))
        {
            return;
        }
        if !e["volcanoEvent"].is_null() && !self.cfg("volcanoEnabled") {
            return;
        }
        if !b(&e, "isEew") && s(&e, "source") == "earlyEst" {
            let canonical = self.identity.canonical(&e);
            for old in self.active.iter() {
                if !b(old, "isEew")
                    && s(old, "source") == "earlyEst"
                    && !canonical.is_empty()
                    && self.identity.canonical(old) == canonical
                {
                    if crate::unified_catalog_bucket::information_order(old, &e) == Some(-1) {
                        return;
                    }
                }
            }
            for old in self
                .catalog
                .events("earlyEst")
                .chain(self.early_rows.iter())
            {
                if !canonical.is_empty()
                    && (canonical == catalog_id("earlyEst", s(old, "eventId"))
                        || crate::unified_catalog_bucket::same_catalog("earlyEst", old, &e))
                    && crate::unified_catalog_bucket::information_order(old, &e) == Some(-1)
                {
                    return;
                }
            }
        }
        let mut cancel = false;
        if b(&e, "isEew") {
            let key = self.key(&e);
            let index = self.same_eew_index(&e);
            let restoring = accepted
                && b(&e, "isCanceled")
                && !e["arrivedAt"].is_null()
                && elapsed(&e, self.now, self.eew_now, self.offset, false) < 20
                && !self.dismissed.values.contains_key(&key)
                && index.is_none();
            if self.canceled.values.contains_key(&key) && !restoring {
                return;
            }
            if b(&e, "isCanceled") {
                let mut previous = index.map(|j| self.active[j].clone());
                if previous.is_none() {
                    for j in 0..self.history.len() {
                        let old = self.history[j][0].clone();
                        if self.identity.same_eew(&old, &e) {
                            previous = Some(old);
                            break;
                        }
                    }
                }
                cancel = restoring || self.freshness(&e, previous.as_ref());
                if !cancel
                    || (accepted && elapsed(&e, self.now, self.eew_now, self.offset, false) >= 20)
                {
                    return;
                }
            }
        }
        if b(&e, "isEew")
            && !cancel
            && elapsed(&e, self.now, self.eew_now, self.offset, false) >= timeout(&e)
        {
            return;
        }
        if suppress
            && !b(&e, "isEew")
            && (absolute(s(&e, "arrivedAt"), self.offset)
                .is_some_and(|t| self.now - t >= duration(&e) * SECOND)
                || (uses_window(&e) && self.remaining(&e) <= 0))
        {
            self.list(&e);
            self.action("notify", &e);
            return;
        }
        if !b(&e, "isEew") && !accepted {
            let threshold = self.config["filters"][s(&e, "source")].as_f64();
            if let Some(t) = threshold {
                if t < 0.0 {
                    return;
                }
                if t > 0.0
                    && !(n(&e, "magnitude") >= t
                        || s(&self.config, "whitelist")
                            .split('|')
                            .map(str::trim)
                            .filter(|v| !v.is_empty())
                            .any(|v| s(&e, "hypocenter").contains(v)))
                {
                    return;
                }
            }
            if b(&e, "isHistory") {
                if !e["originTime"].is_null() {
                    self.list(&e);
                }
                self.action("notify", &e);
                return;
            }
            let newer = s(&e, "source") == "earlyEst"
                && self.active.iter().any(|v| {
                    self.identity.same_info(v, &e)
                        && first_number(s(v, "reportNumText"))
                            .zip(first_number(s(&e, "reportNumText")))
                            .is_some_and(|(a, b)| b > a)
                });
            if !newer && self.identity.seen_report(&e) {
                self.list(&e);
                self.remember(&e);
                self.action("notify", &e);
                return;
            }
            if agency(s(&e, "source")).is_some()
                && !self.identity.unseen_review(&e)
                && self.identity.seen.values.contains_key(&self.key(&e))
                && !self.active.iter().any(|v| self.key(v) == self.key(&e))
            {
                self.list(&e);
                self.action("notify", &e);
                return;
            }
            if self.suppressed_body(&e) {
                return;
            }
        }
        if b(&e, "isHistory") {
            if !b(&e, "isEew") && !e["originTime"].is_null() {
                self.list(&e);
                self.action("notify", &e);
            }
            return;
        }
        if !b(&e, "isEew")
            && (!accepted || uses_catalog(&e))
            && uses_window(&e)
            && self.remaining(&e) <= 0
        {
            if s(&e, "source") != "cencEqlist" {
                self.list(&e);
            }
            self.action("notify", &e);
            return;
        }
        let index = if b(&e, "isEew") {
            self.same_eew_index(&e)
        } else {
            self.active.iter().position(|v| {
                !b(v, "isEew") && s(v, "$replaySessionId").is_empty() && slot(v) == slot(&e)
            })
        };
        let key = self.key(&e);
        let old = index.map(|j| self.active[j].clone());
        if s(&e, "source") != "cwaEqlist" && self.dismissed.values.contains_key(&key) && !cancel {
            if !b(&e, "isEew")
                && review(&e) == "reviewed"
                && !self.reviewed.values.contains_key(&key)
            {
                self.dismissed.values.remove(&key);
                self.reviewed.values.remove(&key);
            } else {
                return;
            }
        }
        if !accepted && self.no_update_blocked(&e) {
            self.list(&e);
            self.action("notify", &e);
            return;
        }
        if b(&e, "isEew") {
            let stored = self.stored(&e, old.as_ref());
            if !cancel
                && stored.is_some_and(|v| report(&e) <= v)
                && !old
                    .as_ref()
                    .is_some_and(|v| self.identity.same_revision(v, &e))
            {
                return;
            }
            let arrival = self.stamp(&e);
            let hist = self.view(e.clone(), i(&e, "$token"), json!({}), Some(&arrival));
            self.add_history(hist);
            if cancel {
                self.canceled.put(key.clone(), self.now);
                self.canceled.prune(self.now, i64::MAX, 200);
                self.dismissed.values.remove(&key);
            }
        }
        let mut quiet = false;
        let mut new_info = false;
        if let Some(ref old) = old {
            let old_key = self.key(old);
            if b(&e, "isEew") {
                let stored = self.stored(&e, Some(old));
                if stored.is_some_and(|v| report(&e) <= v) && !self.identity.same_revision(old, &e)
                {
                    return;
                }
                if old_key != key {
                    self.deadlines.remove(&old_key);
                    self.effects.remove(&old_key);
                    self.dismissed.values.remove(&old_key);
                    self.reviewed.values.remove(&old_key);
                    self.ignored.remove(&old_key);
                    self.ignored_order.retain(|v| v != &old_key);
                }
                self.remember_ignored(key.clone(), stored.unwrap_or(report(&e)).max(report(&e)));
            } else {
                let precision = cenc_order(old, &e);
                if precision == Some(-1)
                    || (self.identity.same_info(old, &e)
                        && review(old) == "reviewed"
                        && review(&e) == "automatic")
                {
                    self.list(&e);
                    return;
                }
                if slot(&e) == "emsc" && !self.identity.same_info(old, &e) && !self.later(old, &e) {
                    self.list(&e);
                    self.action("notify", &e);
                    return;
                }
                if (s(&e, "source") == "usgsEqlist"
                    && s(old, "source") == s(&e, "source")
                    && self.identity.same_body(old, &e))
                    || (i(&e, "origin") != 3
                        && no_update(s(&e, "source")).is_some()
                        && no_update(s(old, "source")) == no_update(s(&e, "source"))
                        && self.identity.same_body(old, &e))
                    || (self.identity.same_info(old, &e) && self.identity.same_body(old, &e))
                {
                    return;
                }
                let publication = |v: &Value| {
                    if slot(&e) == "emsc" {
                        instant(v, "reportTime")
                    } else {
                        time(v, "reportTime")
                    }
                };
                if let (Some(a), Some(t)) = (publication(old), publication(&e)) {
                    if precision != Some(1)
                        && s(&e, "source") == "cencEqlist"
                        && i(&e, "origin") != 3
                        && time(old, "originTime") != Some(a)
                        && time(&e, "originTime") != Some(t)
                        && t - a >= 0
                        && t - a < 30 * SECOND
                    {
                        return;
                    }
                    let numbered = s(&e, "source") == "earlyEst"
                        && self.identity.same_info(old, &e)
                        && first_number(s(old, "reportNumText"))
                            .zip(first_number(s(&e, "reportNumText")))
                            .is_some_and(|(a, b)| b > a);
                    let lpgm = b(old, "isJmaLpgm")
                        && b(&e, "isJmaLpgm")
                        && old["jmaLpgmBulletin"]["eventId"] == e["jmaLpgmBulletin"]["eventId"]
                        && i(&e["jmaLpgmBulletin"], "serial")
                            > i(&old["jmaLpgmBulletin"], "serial");
                    let corrected = observed_revision(old, &e)
                        || (i(&e, "origin") != 3
                            && no_update(s(&e, "source")).is_some()
                            && no_update(s(old, "source")) == no_update(s(&e, "source"))
                            && s(old, "eventId") == s(&e, "eventId")
                            && !s(&e, "eventId").trim().is_empty()
                            && !self.identity.same_body(old, &e));
                    let usgs = s(&e, "source") == "usgsEqlist"
                        && s(old, "source") == s(&e, "source")
                        && s(old, "eventId") == s(&e, "eventId")
                        && !self.identity.same_body(old, &e)
                        && t == a;
                    let whews = (agency(s(&e, "source")).is_some()
                        || i(old, "origin") == 3
                        || i(&e, "origin") == 3)
                        && slot(old) == slot(&e)
                        && self.identity.canonical(old) == self.identity.canonical(&e)
                        && !self.identity.same_body(old, &e)
                        && t == a;
                    quiet = usgs || whews || observed_revision(old, &e);
                    if precision != Some(1)
                        && t <= a
                        && !numbered
                        && !lpgm
                        && !(t == a
                            && time(old, "originTime")
                                .zip(time(&e, "originTime"))
                                .is_some_and(|(a, b)| b > a))
                        && !corrected
                        && !usgs
                        && !whews
                    {
                        return;
                    }
                } else if !self.identity.same_info(old, &e) && !self.later(old, &e) {
                    return;
                }
                if precision == Some(1) {
                    quiet = true;
                }
                if old_key != key {
                    self.dismissed.values.remove(&old_key);
                    self.reviewed.values.remove(&old_key);
                    self.deadlines.remove(&old_key);
                }
            }
            self.dismissed.values.remove(&key);
            self.reviewed.values.remove(&key);
            new_info =
                !b(&e, "isEew") && self.identity.canonical(old) != self.identity.canonical(&e);
            if !b(&e, "isEew")
                && !new_info
                && (agency(s(&e, "source")).is_some()
                    || (i(&e, "origin") != 3 && no_update(s(&e, "source")).is_some()))
            {
                quiet = true;
            }
            if new_info {
                self.actions
                    .push(json!(["discard", i(old, "$token"), old_key]));
            }
        }
        let next = if b(&e, "isEew") {
            e.clone()
        } else if let Some(ref old) = old {
            self.identity.merge(old, &e)
        } else {
            e.clone()
        };
        let arrival = if old.is_none() || new_info || cancel {
            self.stamp(&e)
        } else {
            old.as_ref().unwrap()["arrivedAt"].clone()
        };
        let mut inherit = json!({});
        if let Some(ref old) = old {
            for k in [
                "eventId",
                "titleText",
                "reportNumText",
                "hypocenter",
                "lat",
                "lng",
                "depth",
                "depthText",
                "maxIntensity",
                "className",
                "warnArea",
                "apiTypeLabel",
                "centroidDepth",
                "momentTensor",
                "cmtMetadata",
                "volcanoEvent",
                "magnitude",
            ] {
                if next[k] != e[k] {
                    inherit[k] = json!(i(old, "$token"));
                }
            }
        }
        let next = self.view(next, i(&e, "$token"), inherit, Some(&arrival));
        if let Some(j) = index {
            self.active[j] = next.clone();
        } else {
            self.active.insert(0, next.clone());
        }
        if b(&e, "isEew") && index.is_none() {
            let count = self.ignored.get(&key).copied().unwrap_or(0).max(report(&e));
            self.remember_ignored(key.clone(), count);
        }
        self.remember(&next);
        self.sort();
        if b(&e, "isEew")
            || matches!(s(&e, "source"), "jmaEqlist" | "p2pJmaEqlist")
            || new_info
            || !self.deadlines.contains_key(&key)
        {
            self.schedule(if b(&e, "isEew") || index.is_none() {
                &next
            } else {
                &e
            });
        }
        self.list(&next);
        self.remember_no_update(&next);
        let immediate = old.is_none()
            || b(&next, "isFinal")
            || b(&next, "isCanceled")
            || old
                .as_ref()
                .is_some_and(|v| !effective_warn(v) && effective_warn(&next));
        self.actions.push(json!([
            "accepted",
            i(&next, "$token"),
            old.as_ref().map(|v| i(v, "$token")),
            new_info,
            suppress,
            quiet,
            immediate
        ]));
        if !suppress {
            if old.is_some() && b(&next, "isEew") && !immediate {
                self.effects.insert(key, (self.clock + 300_000, next));
            } else if !quiet || b(&next, "isEew") || old.is_none() {
                self.effects.remove(&key);
                self.actions
                    .push(json!(["effects", i(&next, "$token"), old.is_some()]));
            }
        } else {
            self.effects.remove(&key);
        }
    }
    fn stored(&self, e: &Value, old: Option<&Value>) -> Option<i64> {
        if !b(e, "hasReportSequence") && old.is_none() {
            return None;
        }
        let mut stored = self.ignored.get(&self.key(e)).copied();
        if let Some(old) = old {
            stored = Some(
                stored
                    .unwrap_or(i64::MIN)
                    .max(
                        self.ignored
                            .get(&self.key(old))
                            .copied()
                            .unwrap_or(i64::MIN),
                    )
                    .max(report(old)),
            );
        }
        stored
    }
    fn later(&self, a: &Value, bv: &Value) -> bool {
        let value = |e: &Value| {
            if slot(bv) == "emsc" {
                instant(e, "originTime")
            } else {
                time(e, "originTime")
            }
        };
        if let (Some(a), Some(b)) = (value(a), value(bv)) {
            b > a
        } else {
            absolute(s(a, "arrivedAt"), self.offset)
                .zip(absolute(s(bv, "arrivedAt"), self.offset))
                .is_some_and(|(a, b)| b > a)
        }
    }
    pub fn remove(&mut self, key: &str) {
        let Some(index) = self.active.iter().position(|v| self.key(v) == key) else {
            return;
        };
        let e = self.active[index].clone();
        if !s(&e, "$replaySessionId").is_empty() {
            self.active.remove(index);
            self.deadlines.remove(key);
            self.effects.remove(key);
            self.action("stopReplay", &e);
            return;
        }
        self.remember_no_update(&e);
        if s(&e, "source") != "cwaEqlist" {
            self.dismissed.put(key.into(), self.now);
            if !b(&e, "isEew") && review(&e) == "reviewed" {
                self.reviewed.put(key.into(), self.now);
            } else {
                self.reviewed.values.remove(key);
            }
        }
        self.deadlines.remove(key);
        self.effects.remove(key);
        self.active.remove(index);
        if b(&e, "isEew") {
            let count = self.ignored.get(key).copied().unwrap_or(0).max(report(&e));
            self.remember_ignored(key.into(), count);
            if self.ignored.len() > 10 {
                let keep = self.active.iter().map(|v| self.key(v)).collect::<Vec<_>>();
                if let Some(remove) = self
                    .ignored_order
                    .iter()
                    .find(|v| !keep.contains(v) && *v != key)
                    .cloned()
                {
                    self.ignored.remove(&remove);
                    self.ignored_order.retain(|v| v != &remove);
                }
            }
        }
        self.dismissed.prune(self.now, i64::MAX, 200);
        let mut groups = vec![];
        if b(&e, "isEew") {
            for j in 0..self.history.len() {
                let latest = self.history[j][0].clone();
                if s(&latest, "source") == s(&e, "source")
                    && (self.history_ids[j] == s(&e, "eventId")
                        || self.identity.same_eew(&latest, &e))
                {
                    groups.push(j);
                }
            }
        }
        self.actions
            .push(json!(["removed", i(&e, "$token"), key, groups]));
    }
    pub fn advance(&mut self, clock: i64) {
        let delta = (clock - self.clock).max(0);
        self.now += delta;
        self.source_now += delta;
        self.eew_now += delta;
        self.clock = clock;
        if self.persist_due.is_some_and(|v| v <= clock) {
            self.persist_due = None;
            self.actions.push(json!(["persist"]));
        }
        let due = self
            .deadlines
            .iter()
            .filter(|(_, t)| **t <= clock)
            .map(|(k, _)| k.clone())
            .collect::<Vec<_>>();
        for key in due {
            self.remove(&key);
        }
        let due = self
            .effects
            .iter()
            .filter(|(_, v)| v.0 <= clock)
            .map(|(k, _)| k.clone())
            .collect::<Vec<_>>();
        for key in due {
            if let Some((_, e)) = self.effects.remove(&key) {
                if self.active.iter().any(|v| self.key(v) == key) {
                    self.actions.push(json!(["effects", i(&e, "$token"), true]));
                }
            }
        }
    }
    pub fn execute(&mut self, c: &Value, clock: i64) -> Value {
        if s(c, "op") == "tick" {
            self.advance(clock);
            return self.finish();
        }
        let elapsed = (clock - self.clock).max(0);
        self.clock = clock;
        if !c["context"].is_null() {
            self.config = c["context"].clone();
            self.now = i(&self.config, "nowUs");
            self.source_now = i(&self.config, "sourceNowUs");
            self.eew_now = i(&self.config, "eewNowUs");
            self.offset = i(&self.config, "localOffsetMinutes");
            self.lpgm_display.speech_busy = b(&self.config, "speechBusy");
        } else {
            self.now += elapsed;
            self.source_now += elapsed;
            self.eew_now += elapsed;
        }
        match s(c, "op") {
            "jmaLpgmSpeech" => {
                self.lpgm_display.speech_busy = b(c, "busy");
            }
            "clearJmaLpgm" => {
                let id = s(c, "eventId");
                for index in (0..self.active.len()).rev() {
                    let event = &self.active[index];
                    if b(event, "isJmaLpgm")
                        && (id.is_empty() || s(event, "eventId") == id)
                    {
                        let key = self.key(event);
                        self.remove(&key);
                    }
                }
            }
            "bucketUpsertAsync" => {
                let result = self.bucket_policy.upsert(c);
                self.actions
                    .push(json!(["bucketUpsert", i(c, "request"), result]));
            }
            "startupHistory" => self.startup_history(c),
            "catalog" => {
                if let Some(tokens) = self.catalog.snapshot(c) {
                    self.actions.push(json!(["flat", tokens]));
                }
            }
            "importRows" => {
                if let Some(caches) = c["rows"].as_object() {
                    for (name, rows) in caches {
                        if name == "background_accepted_eew_report_nums" {
                            if let Some(rows) = rows.as_array() {
                                for row in rows {
                                    if let Some((body, stamp)) =
                                        row.as_str().and_then(|v| v.rsplit_once('|'))
                                    {
                                        if let (Some((key, report)), Ok(stamp)) =
                                            (body.rsplit_once('|'), stamp.parse::<i64>())
                                        {
                                            if let Ok(report) = report.parse::<i64>() {
                                                self.accepted_eew.insert(
                                                    key.into(),
                                                    self.accepted_eew
                                                        .get(key)
                                                        .copied()
                                                        .unwrap_or(report)
                                                        .max(report),
                                                );
                                                self.accepted_eew_seen.put(
                                                    key.into(),
                                                    self.accepted_eew_seen
                                                        .values
                                                        .get(key)
                                                        .copied()
                                                        .unwrap_or(i64::MIN)
                                                        .max(stamp * 1000),
                                                );
                                            }
                                        }
                                    }
                                }
                            }
                            continue;
                        }
                        let cache = match name.as_str() {
                            "seen_no_update_info_events" => Some(&mut self.no_update_seen),
                            "seen_usgs_info_body_keys" => {
                                Some(self.bodies.entry("usgsEqlist".into()).or_default())
                            }
                            "seen_emsc_info_body_keys" => {
                                Some(self.bodies.entry("emsc".into()).or_default())
                            }
                            "seen_cwa_info_body_keys" => {
                                Some(self.bodies.entry("cwaEqlist".into()).or_default())
                            }
                            "background_seen_unified_info_events" => Some(&mut self.identity.seen),
                            "canceled_eew_events" => Some(&mut self.canceled),
                            _ => None,
                        };
                        if let Some(cache) = cache {
                            if let Some(rows) = rows.as_array() {
                                for row in rows {
                                    if let Some((key, stamp)) =
                                        row.as_str().and_then(|v| v.rsplit_once('|'))
                                    {
                                        if let Ok(stamp) = stamp.parse::<i64>() {
                                            cache.put(
                                                key.into(),
                                                cache
                                                    .values
                                                    .get(key)
                                                    .copied()
                                                    .unwrap_or(i64::MIN)
                                                    .max(stamp * 1000),
                                            );
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                self.identity.seen.prune(self.now, 48 * 3600 * SECOND, 1000);
                self.no_update_seen.prune(self.now, 48 * 3600 * SECOND, 500);
                self.canceled.prune(self.now, 24 * 3600 * SECOND, 200);
                self.accepted_eew_seen
                    .prune(self.now, 24 * 3600 * SECOND, 100);
                self.accepted_eew
                    .retain(|k, _| self.accepted_eew_seen.values.contains_key(k));
                for cache in self.bodies.values_mut() {
                    cache.prune(self.now, 24 * 3600 * SECOND, 1000);
                }
            }
            "admit" => self.admit(
                c["event"].clone(),
                b(c, "alreadyAccepted"),
                b(c, "suppressEffects"),
            ),
            "dismiss" => self.remove(s(c, "key")),
            "tick" => self.advance(clock),
            "seed" => {
                self.identity.seen.import(&c["seen"]);
                self.no_update_seen.import(&c["noUpdate"]);
                self.canceled.import(&c["canceled"]);
                for source in ["usgsEqlist", "emsc", "cwaEqlist"] {
                    self.bodies
                        .entry(source.into())
                        .or_default()
                        .import(&c["bodies"][source]);
                }
            }
            "seedHistory" => {
                if let Some(groups) = c["groups"].as_array() {
                    self.history = groups
                        .iter()
                        .filter_map(|v| v.as_array().cloned())
                        .collect();
                    self.history_first = self
                        .history
                        .iter()
                        .enumerate()
                        .map(|(j, group)| {
                            c["firstArrivedUs"][j]
                                .as_i64()
                                .or_else(|| {
                                    group
                                        .last()
                                        .and_then(|e| absolute(s(e, "arrivedAt"), self.offset))
                                })
                                .unwrap_or(self.now)
                        })
                        .collect();
                    self.history_ids = self
                        .history
                        .iter()
                        .enumerate()
                        .map(|(j, group)| {
                            c["eventIds"][j]
                                .as_str()
                                .unwrap_or(s(&group[0], "eventId"))
                                .to_owned()
                        })
                        .collect();
                    for group in &self.history {
                        if let Some(first) = group.first() {
                            for report in group {
                                self.identity.remember_alias(first, report, true);
                            }
                            if b(first, "isCanceled") {
                                self.canceled.put(
                                    self.key(first),
                                    absolute(s(first, "arrivedAt"), self.offset)
                                        .unwrap_or(self.now),
                                );
                            }
                        }
                    }
                }
            }
            "retainHistory" => self.retain_history(),
            "rebindHistory" => {
                if let Some(rows) = c["mappings"].as_array() {
                    for row in rows {
                        let from = row[0].as_i64().unwrap_or(0);
                        let to = row[1].as_i64().unwrap_or(0);
                        for report in self.history.iter_mut().flatten() {
                            if i(report, "$token") == from {
                                report["$token"] = json!(to);
                            }
                        }
                    }
                }
            }
            "product" => {
                let previous = &c["previous"];
                if !previous.is_null() {
                    self.active.retain(|v| {
                        !(s(v, "source") == s(previous, "source")
                            && s(v, "eventId") == s(previous, "eventId"))
                    });
                }
                if !c["event"].is_null() {
                    self.active.push(c["event"].clone());
                }
                self.sort();
            }
            "replay" => {
                let e = &c["event"];
                let index = self.same_eew_index(e);
                let old = index.map(|j| self.active[j].clone());
                if !old.as_ref().is_some_and(|v| {
                    b(v, "isCanceled")
                        || ((b(v, "hasReportSequence") || b(e, "hasReportSequence"))
                            && report(e) <= report(v)
                            && !self.identity.same_revision(v, e))
                }) {
                    if let Some(j) = index {
                        self.active.remove(j);
                    }
                    let next = self.view(e.clone(), i(e, "$token"), json!({}), None);
                    self.active.insert(0, next.clone());
                    self.sort();
                    self.actions
                        .push(json!(["replay", i(&next, "$token"), old.is_some()]));
                }
            }
            "clearReplay" => {
                let session = s(c, "session");
                let tokens = self
                    .active
                    .iter()
                    .filter(|v| s(v, "$replaySessionId") == session)
                    .map(|v| i(v, "$token"))
                    .collect::<Vec<_>>();
                self.active.retain(|v| s(v, "$replaySessionId") != session);
                self.identity
                    .aliases
                    .retain(|k, _| !k.starts_with(&format!("{session}|")));
                self.actions.push(json!(["replayCleared", tokens]));
            }
            "expireReplay" => {
                let e = &c["event"];
                let mut tokens = vec![];
                for j in (0..self.active.len()).rev() {
                    let old = self.active[j].clone();
                    if s(&old, "$replaySessionId") == s(e, "$replaySessionId")
                        && s(&old, "source") == s(e, "source")
                        && (old["eventId"] == e["eventId"] || self.identity.same_eew(&old, e))
                    {
                        tokens.push(i(&old, "$token"));
                        self.active.remove(j);
                    }
                }
                self.actions.push(json!(["replayCleared", tokens]));
            }
            _ => {}
        }
        let mut result = self.finish();
        result["consumed"] = json!(c
            .get("event")
            .filter(|v| !v.is_null())
            .map(|e| vec![i(e, "$token")])
            .unwrap_or_default());
        if s(c, "op") == "rebindHistory" {
            result["consumed"] = json!(c["mappings"]
                .as_array()
                .map(|v| v.iter().filter_map(|r| r[1].as_i64()).collect::<Vec<_>>())
                .unwrap_or_default());
        }
        if matches!(s(c, "op"), "seedHistory" | "startupHistory") {
            result["consumed"] = json!(c["groups"]
                .as_array()
                .map(|v| v
                    .iter()
                    .filter_map(Value::as_array)
                    .flatten()
                    .map(|e| i(e, "$token"))
                    .collect::<Vec<_>>())
                .unwrap_or_default());
        }
        result
    }
    pub fn finish(&mut self) -> Value {
        let lpgm_display = self.lpgm_display.project(&self.active, self.clock);
        let keys = self
            .active
            .iter()
            .map(|v| json!([i(v, "$token"), self.key(v)]))
            .collect::<Vec<_>>();
        let retained = self
            .active
            .iter()
            .chain(self.history.iter().flatten())
            .chain(self.effects.values().map(|v| &v.1))
            .map(|v| i(v, "$token"))
            .collect::<std::collections::HashSet<_>>();
        json!({"views":std::mem::take(&mut self.views),"actions":std::mem::take(&mut self.actions),"active":self.active.iter().map(|v|i(v,"$token")).collect::<Vec<_>>(),"jmaLpgmDisplay":lpgm_display,"keys":keys,"retained":retained,"nextDeadline":self.next_deadline(),"nowUs":self.now,"catalogRevision":self.catalog.revision(),"catalogRetained":self.catalog.retained()})
    }
    pub fn query(&mut self, c: &Value) -> Value {
        let e = &c["event"];
        let a = &c["previous"];
        match s(c, "op") {
            "bucketUpsert" => self.bucket_policy.upsert(c),
            "effectiveWarn" => json!(effective_warn(e)),
            "messageFields" => message_fields(e),
            "renderCencIrIndex" => render_cenc_ir_index(c),
            "formatNumbers" => json!([
                dart_double(n(c, "value")),
                fixed(n(c, "value"), i(c, "places") as u32)
            ]),
            "key" => json!(self.key(e)),
            "canonical" => json!(self.identity.canonical(e)),
            "slot" => json!(slot(e)),
            "sameEew" => json!(self.identity.same_eew(a, e)),
            "sameRevision" => json!(self.identity.same_revision(a, e)),
            "sameInfo" => json!(self.identity.same_info(a, e)),
            "jmaLpgmSameEvent" => json!(
                jma_lpgm_same_event(e, &c["bulletin"])
            ),
            "sameBody" => json!(self.identity.same_body(a, e)),
            "merge" => self.identity.merge(a, e),
            "duration" => json!(duration(e)),
            "remaining" => json!(self.remaining(e)),
            "mergeFields" => {
                let merged = self.identity.merge(a, e);
                json!([
                    "eventId",
                    "titleText",
                    "reportNumText",
                    "hypocenter",
                    "lat",
                    "lng",
                    "depth",
                    "depthText",
                    "maxIntensity",
                    "className",
                    "warnArea",
                    "apiTypeLabel",
                    "centroidDepth",
                    "momentTensor",
                    "cmtMetadata",
                    "volcanoEvent",
                    "magnitude"
                ]
                .into_iter()
                .filter(|k| merged[*k] != e[*k])
                .collect::<Vec<_>>())
            }
            "sort" => {
                let Some(events) = c["events"].as_array() else {
                    return json!([]);
                };
                let mut indices = (0..events.len()).collect::<Vec<_>>();
                let offset = self.offset;
                let now = self.now;
                indices.sort_by(|&ia, &ib| {
                    let a = &events[ia];
                    let bv = &events[ib];
                    let ar = !s(a, "$replaySessionId").is_empty();
                    let br = !s(bv, "$replaySessionId").is_empty();
                    if b(a, "isEew") && !ar && br {
                        return std::cmp::Ordering::Less;
                    }
                    if b(bv, "isEew") && !br && ar {
                        return std::cmp::Ordering::Greater;
                    }
                    b(bv, "isEew").cmp(&b(a, "isEew")).then_with(|| {
                        absolute(s(bv, "arrivedAt"), offset)
                            .unwrap_or(now)
                            .cmp(&absolute(s(a, "arrivedAt"), offset).unwrap_or(now))
                    })
                });
                json!(indices)
            }
            "export" => {
                let rows = |cache: &Times| {
                    cache
                        .order
                        .iter()
                        .filter_map(|k| cache.values.get(k).map(|v| format!("{k}|{}", v / 1000)))
                        .collect::<Vec<_>>()
                };
                json!({"preferenceRows":{
                    "background_seen_unified_info_events":rows(&self.identity.seen),
                    "seen_no_update_info_events":rows(&self.no_update_seen),
                    "canceled_eew_events":rows(&self.canceled),
                    "background_accepted_eew_report_nums":self.accepted_eew_seen.order.iter().filter_map(|key|self.accepted_eew_seen.values.get(key).map(|stamp|format!("{key}|{}|{}",self.accepted_eew.get(key).copied().unwrap_or(1),stamp/1000))).collect::<Vec<_>>(),
                    "seen_usgs_info_body_keys":self.bodies.get("usgsEqlist").map(&rows).unwrap_or_default(),
                    "seen_emsc_info_body_keys":self.bodies.get("emsc").map(&rows).unwrap_or_default(),
                    "seen_cwa_info_body_keys":self.bodies.get("cwaEqlist").map(&rows).unwrap_or_default(),
                }})
            }
            _ => Value::Null,
        }
    }
}
fn report_sort(e: &Value) -> i64 {
    s(e, "reportNumText")
        .find('第')
        .and_then(|j| {
            let rest = &s(e, "reportNumText")[j + '第'.len_utf8()..];
            let text = rest.split(|c: char| !c.is_ascii_digit()).next()?;
            text.parse().ok()
        })
        .unwrap_or(0)
}
