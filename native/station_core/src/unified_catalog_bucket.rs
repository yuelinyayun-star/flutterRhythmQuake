//! Catalog row identities, proven aliases and revision ordering. Returned
//! indices bind the original QuakeMessage objects without rewriting reports.
use crate::unified_event_policy::*;
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};

#[derive(Default)]
struct Aliases {
    map: HashMap<String, String>,
    order: Vec<String>,
}
impl Aliases {
    fn put(&mut self, k: String, v: String) {
        if !self.map.contains_key(&k) {
            self.order.push(k.clone());
        }
        self.map.insert(k, v);
    }
}
#[derive(Default)]
pub struct BucketPolicy {
    aliases: HashMap<String, Aliases>,
}
fn default_zone(e: &Value) -> i64 {
    if matches!(
        s(e, "$quakeSource"),
        "wolfx" | "nied" | "p2p" | "jma_fan" | "jmaCmt" | "hinetAquaCmt" | "kma_eq" | "kma_eew_fan"
    ) {
        9
    } else {
        8
    }
}
fn comparable(e: &Value) -> i64 {
    time(e, "originTime").unwrap_or(0) - default_zone(e) * 3600 * SECOND
}
pub fn descriptor(e: &Value, bucket: &str) -> Value {
    let mut v = e.clone();
    v["source"] = json!(bucket);
    v["isEew"] = json!(false);
    v["$historyRecord"] = json!(true);
    if v["timeZone"].is_null() {
        v["timeZone"] = json!(default_zone(e));
    }
    v
}
fn jma(e: &Value) -> bool {
    matches!(s(e, "$quakeSource"), "wolfx" | "jma_fan" | "p2p")
}
fn jma_key(e: &Value) -> Option<String> {
    let place = s(e, "hypocenter")
        .chars()
        .filter(|c| !c.is_whitespace())
        .collect::<String>();
    if place.is_empty() || !jma(e) {
        return None;
    }
    Some(format!(
        "{}|{}|{}|{}",
        comparable(e) / (60 * SECOND),
        place,
        n(e, "magnitude").round() as i64,
        n(e, "depth").round() as i64
    ))
}
fn same_jma(a: &Value, b: &Value) -> bool {
    jma(a)
        && jma(b)
        && (comparable(a) / SECOND == comparable(b) / SECOND
            || jma_key(a).is_some_and(|v| Some(v) == jma_key(b)))
}
fn agency_source(bucket: &str) -> Option<&str> {
    match bucket {
        "usgsEqlist" => Some("usgs"),
        "cwaEqlist" => Some("cwa"),
        "emscEqlist" => Some("emsc"),
        "kmaEqlist" => Some("kma_eq"),
        _ => {
            if catalog(bucket) {
                Some(bucket.strip_prefix("whews_").unwrap_or(bucket))
            } else {
                None
            }
        }
    }
}
fn exact_observation(a: &Value, b: &Value) -> bool {
    observation(a).is_some_and(|v| Some(v) == observation(b))
        || (catalog(s(a, "source"))
            && instant(a, "originTime") == instant(b, "originTime")
            && cenc_obs(a).is_some()
            && ["lat", "lng", "magnitude", "depth"].iter().all(|k| {
                n(a, k).is_finite()
                    && n(a, k)
                        >= if *k == "lat" || *k == "lng" {
                            f64::NEG_INFINITY
                        } else {
                            0.0
                        }
                    && n(a, k) == n(b, k)
            }))
}
pub fn same_catalog(bucket: &str, a: &Value, b: &Value) -> bool {
    let id = catalog_id(bucket, s(a, "eventId"));
    if bucket == "cencEqlist" && s(a, "$quakeSource") == "cenc" && s(b, "$quakeSource") == "cenc" {
        return (!id.is_empty() && id == catalog_id(bucket, s(b, "eventId")))
            || cenc_order(a, b).is_some()
            || cenc_obs(a).is_some_and(|v| Some(v) == cenc_obs(b));
    }
    let Some(source) = agency_source(bucket) else {
        return false;
    };
    if s(a, "$quakeSource") != source || s(b, "$quakeSource") != source {
        return false;
    }
    if !id.is_empty() && id == catalog_id(bucket, s(b, "eventId")) {
        return true;
    }
    if exact_observation(a, b) {
        return true;
    }
    bucket == "whews_ga"
        && s(a, "apiTypeLabel") != s(b, "apiTypeLabel")
        && ga_report(a)
            .zip(ga_report(b))
            .is_some_and(|(a, b)| a["observation"] == b["observation"])
}
pub fn information_number(e: &Value) -> Option<i64> {
    let t = s(e, "reportNumText")
        .trim()
        .strip_prefix('第')?
        .trim_start();
    let digits = t.bytes().take_while(u8::is_ascii_digit).count();
    if digits == 0 {
        return None;
    }
    let value = t[..digits].parse::<i64>().ok()?;
    let rest = t[digits..].trim_start();
    if value > 0 && (rest.starts_with('報') || rest.starts_with('报')) {
        Some(value)
    } else {
        None
    }
}
pub fn information_order(a: &Value, b: &Value) -> Option<i32> {
    match (information_number(a), information_number(b)) {
        (Some(x), Some(y)) if x != y => return Some(if y > x { 1 } else { -1 }),
        (Some(_), None) => return Some(-1),
        _ => (),
    }
    match (instant(a, "reportTime"), instant(b, "reportTime")) {
        (Some(x), Some(y)) => Some(if y > x {
            1
        } else if y < x {
            -1
        } else {
            0
        }),
        (Some(_), None) => Some(-1),
        _ => None,
    }
}
impl BucketPolicy {
    pub fn upsert(&mut self, c: &Value) -> Value {
        let bucket = s(c, "bucket");
        let incoming = descriptor(&c["incoming"], bucket);
        let rows = c["rows"]
            .as_array()
            .map(|v| v.iter().map(|e| descriptor(e, bucket)).collect::<Vec<_>>())
            .unwrap_or_default();
        let aliases = if bucket == "cencEqlist" || agency(bucket).is_some() {
            Some(self.aliases.entry(bucket.into()).or_default())
        } else {
            None
        };
        let identity = |e: &Value, aliases: Option<&Aliases>| {
            let id = catalog_id(bucket, s(e, "eventId"));
            aliases.and_then(|a| a.map.get(&id)).cloned().unwrap_or(id)
        };
        let mut aliases = aliases;
        let ambiguous = bucket == "cencEqlist"
            && rows
                .iter()
                .filter(|e| {
                    catalog_id(bucket, s(e, "eventId"))
                        != catalog_id(bucket, s(&incoming, "eventId"))
                        && cenc_order(e, &incoming).is_some()
                })
                .map(|e| catalog_id(bucket, s(e, "eventId")))
                .collect::<HashSet<_>>()
                .len()
                > 1;
        let same = |e: &Value, aliases: Option<&Aliases>| {
            s(e, "eventId") == s(&incoming, "eventId")
                || (aliases.is_some()
                    && !identity(e, aliases).is_empty()
                    && identity(e, aliases) == identity(&incoming, aliases))
                || (same_catalog(bucket, e, &incoming)
                    && (!ambiguous || cenc_order(e, &incoming).is_none()))
                || (bucket == "jmaEqlist" && same_jma(e, &incoming))
        };
        let mut indices = (0..rows.len()).collect::<Vec<_>>();
        let mut old_index = indices
            .iter()
            .position(|&j| same(&rows[j], aliases.as_deref()));
        let mut notifications = 0;
        if matches!(bucket, "earlyEst" | "cencEqlist" | "cwaEqlist") {
            if let Some(mut old) = old_index {
                for j in old + 1..rows.len() {
                    if !same(&rows[j], aliases.as_deref()) {
                        continue;
                    }
                    let order = if bucket == "cencEqlist" {
                        cenc_order(&rows[old], &rows[j])
                    } else {
                        information_order(&rows[old], &rows[j])
                    };
                    if order == Some(1) {
                        old = j;
                    }
                }
                let before = indices.len();
                indices.retain(|&j| j == old || !same(&rows[j], aliases.as_deref()));
                old_index = indices.iter().position(|&j| j == old);
                if before != indices.len() {
                    notifications += 1;
                }
            }
        }
        let rejected = if let Some(index) = old_index {
            let old = &rows[indices[index]];
            let formal =
                |e: &Value| matches!(s(e, "reviewType"), "reviewed" | "formal" | "正式测定");
            let auto = |e: &Value| matches!(s(e, "reviewType"), "automatic" | "auto" | "自动测定");
            if formal(old) && auto(&incoming) {
                true
            } else {
                let upgrade = auto(old) && formal(&incoming);
                let precision = if bucket == "cencEqlist" {
                    cenc_order(old, &incoming)
                } else {
                    None
                };
                if let Some(ref mut aliases) = aliases {
                    let root = identity(old, Some(aliases));
                    let other = identity(&incoming, Some(aliases));
                    if !root.is_empty() && !other.is_empty() {
                        for value in aliases.map.values_mut() {
                            if *value == other {
                                *value = root.clone();
                            }
                        }
                        aliases.put(catalog_id(bucket, s(old, "eventId")), root.clone());
                        aliases.put(catalog_id(bucket, s(&incoming, "eventId")), root);
                        while aliases.order.len() > 1000 {
                            aliases.map.remove(&aliases.order.remove(0));
                        }
                    }
                }
                let numbered = if bucket == "earlyEst" {
                    information_order(old, &incoming)
                } else {
                    None
                };
                let old_time = instant(old, "reportTime");
                let new_time = instant(&incoming, "reportTime");
                precision == Some(-1)
                    || numbered == Some(-1)
                    || (numbered != Some(1)
                        && precision != Some(1)
                        && !upgrade
                        && ((b(c, "replayOnly")
                            && (new_time.is_none()
                                || old_time.zip(new_time).is_some_and(|(a, b)| b <= a)))
                            || old_time.is_some_and(|a| new_time.is_none_or(|b| b < a))))
            }
        } else {
            false
        };
        if rejected {
            return json!({"indices":indices,"notifications":notifications});
        }
        indices.retain(|&j| !same(&rows[j], aliases.as_deref()));
        let mut candidates = vec![-1_i64];
        candidates.extend(indices.into_iter().map(|v| v as i64));
        let event = |j: i64| if j < 0 { &incoming } else { &rows[j as usize] };
        let mut ordered = candidates
            .iter()
            .enumerate()
            .map(|(j, &index)| (j, -(comparable(event(index)) as i128)))
            .collect::<Vec<_>>();
        crate::unified_event_sort::sort(&mut ordered);
        let result = ordered
            .into_iter()
            .take(50)
            .map(|(j, _)| candidates[j])
            .collect::<Vec<_>>();
        if let Some(ref mut aliases) = aliases {
            let retained = result
                .iter()
                .map(|&j| identity(event(j), Some(aliases)))
                .collect::<HashSet<_>>();
            aliases.map.retain(|_, root| retained.contains(root));
            aliases.order.retain(|k| aliases.map.contains_key(k));
        }
        json!({"indices":result,"notifications":notifications+1})
    }
}
