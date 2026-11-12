//! Retained catalog rows and final history projection, without original bodies.
use crate::unified_event_policy::*;
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};

#[derive(Default)]
pub struct CatalogHistory {
    rows: HashMap<i64, Value>,
    buckets: Vec<(String, Vec<i64>)>,
    signature: Option<Value>,
    revision: i64,
}
fn jma(e: &Value) -> bool {
    matches!(s(e, "$quakeSource"), "wolfx" | "jma_fan" | "p2p")
}
fn origin(e: &Value) -> i64 {
    let zone = e["timeZone"].as_i64().unwrap_or(
        if matches!(
            s(e, "$quakeSource"),
            "wolfx"
                | "nied"
                | "p2p"
                | "jma_fan"
                | "jmaCmt"
                | "hinetAquaCmt"
                | "kma_eq"
                | "kma_eew_fan"
        ) {
            9
        } else {
            8
        },
    );
    time(e, "originTime").unwrap_or(0) - zone * 3600 * SECOND
}
fn key(e: &Value) -> Option<String> {
    if !jma(e) {
        return None;
    }
    let place = s(e, "hypocenter")
        .chars()
        .filter(|v| !v.is_whitespace())
        .collect::<String>();
    if place.is_empty() {
        return None;
    }
    Some(format!(
        "{}|{place}|{:.0}|{:.0}",
        origin(e) / (60 * SECOND),
        (n(e, "magnitude") * 10.0).round(),
        n(e, "depth").round()
    ))
}
fn reviewed(e: &Value) -> bool {
    let text = format!(
        "{} {} {} {}",
        s(e, "titleText"),
        s(e, "reviewType"),
        s(e, "reportNumText"),
        s(e, "tsunamiWarning")
    )
    .to_lowercase();
    ["reviewed", "confirmed", "正式", "確定", "已核实"]
        .iter()
        .any(|v| text.contains(v))
}
fn prefer(a: &Value, bv: &Value) -> bool {
    let x = reviewed(a);
    let y = reviewed(bv);
    if x != y {
        return y;
    }
    time(a, "reportTime")
        .zip(time(bv, "reportTime"))
        .is_some_and(|(a, b)| b > a)
}
impl CatalogHistory {
    pub fn events<'a>(&'a self, bucket: &'a str) -> impl Iterator<Item = &'a Value> {
        self.buckets
            .iter()
            .filter(move |(name, _)| name == bucket)
            .flat_map(|(_, ids)| ids.iter())
            .filter_map(|id| self.rows.get(id))
    }
    pub fn retained(&self) -> Vec<i64> {
        self.rows.keys().copied().collect()
    }
    pub fn snapshot(&mut self, c: &Value) -> Option<Vec<i64>> {
        self.revision = i(c, "catalogRevision");
        if let Some(rows) = c["rows"].as_array() {
            for row in rows {
                self.rows.insert(i(row, "$token"), row.clone());
            }
        }
        if let Some(buckets) = c["buckets"].as_array() {
            self.buckets = buckets
                .iter()
                .filter_map(|row| {
                    Some((
                        row[0].as_str()?.to_owned(),
                        row[1]
                            .as_array()?
                            .iter()
                            .filter_map(Value::as_i64)
                            .collect(),
                    ))
                })
                .collect();
        }
        for (bucket, ids) in &self.buckets {
            for id in ids {
                if let Some(row) = self.rows.get_mut(id) {
                    if row["source"].is_null() {
                        *row = crate::unified_catalog_bucket::descriptor(row, bucket);
                    }
                }
            }
        }
        let selected = c["sourceFilter"]
            .as_array()
            .map(|v| v.iter().filter_map(Value::as_str).collect::<HashSet<_>>())
            .unwrap_or_default();
        let mut merged = vec![];
        for (bucket, ids) in &self.buckets {
            if !selected.contains(bucket.as_str()) {
                continue;
            }
            let threshold = c["bucketFilters"][bucket].as_f64().unwrap_or(0.0);
            if threshold < 0.0 {
                continue;
            }
            for id in ids {
                let Some(e) = self.rows.get(id) else {
                    continue;
                };
                if threshold > 0.0 && n(e, "magnitude") < threshold {
                    continue;
                }
                if n(c, "magnitudeFilter") > 0.0 && n(e, "magnitude") < n(c, "magnitudeFilter") {
                    continue;
                }
                merged.push(*id);
            }
        }
        let mut seen = HashMap::new();
        let mut deduped: Vec<i64> = vec![];
        for token in merged {
            let e = &self.rows[&token];
            if let Some(k) = key(e) {
                if let Some(&old_index) = seen.get(&k) {
                    let old = &self.rows[&deduped[old_index]];
                    if prefer(old, e) {
                        deduped[old_index] = token;
                    }
                    continue;
                }
                seen.insert(k, deduped.len());
            }
            deduped.push(token);
        }
        let mut ordered = deduped
            .iter()
            .enumerate()
            .map(|(j, id)| (j, -(origin(&self.rows[id]) as i128)))
            .collect::<Vec<_>>();
        crate::unified_event_sort::sort(&mut ordered);
        let tokens = ordered
            .into_iter()
            .take(100)
            .map(|(j, _)| deduped[j])
            .collect::<Vec<_>>();
        let signature = json!(tokens
            .iter()
            .map(|id| {
                let e = &self.rows[id];
                json!([
                    s(e, "eventId"),
                    s(e, "$quakeSource"),
                    e["magnitude"],
                    e["$originEpochMs"],
                    s(e, "hypocenter"),
                    e["usgsUpdated"],
                    e["usgsProductTypes"],
                    e["reportTime"],
                    e["reportNumText"],
                    e["reviewType"],
                    e["nodalPlane1"],
                    e["nodalPlane2"],
                    e["centroidDepth"],
                    e["momentTensor"],
                    e["cmtMetadata"]
                ])
            })
            .collect::<Vec<_>>());
        let changed = self.signature.as_ref() != Some(&signature);
        self.signature = Some(signature);
        let retained = self
            .buckets
            .iter()
            .flat_map(|(_, ids)| ids.iter().copied())
            .collect::<HashSet<_>>();
        self.rows.retain(|id, _| retained.contains(id));
        if changed {
            Some(tokens)
        } else {
            None
        }
    }
    pub fn revision(&self) -> i64 {
        self.revision
    }
}
