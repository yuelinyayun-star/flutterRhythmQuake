//! SeisJS domain owner. Receives untouched decoded ingress on the source actor;
//! only immutable display/archive projections cross the UI boundary.
use super::{iso, number, text, timestamp};
use serde_json::{json, Value};
use std::collections::HashMap;

#[derive(Default)]
pub(super) struct SeisJs {
    pub(super) revision: u64,
    rows: Vec<Value>,
    indices: HashMap<String, usize>,
    expire_at: Option<i64>,
}
impl SeisJs {
    pub(super) fn input(&mut self, v: &Value, clock: i64) -> Option<i64> {
        let id = v.get("type").map(text).unwrap_or_default();
        if id.is_empty() || matches!(id.as_str(), "heartbeat" | "pong") {
            return None;
        }
        let lat = number(&v["latitude"]).unwrap_or(0.0);
        let lon = number(&v["longitude"]).unwrap_or(0.0);
        if lat == 0.0 && lon == 0.0 {
            return None;
        }
        let time = timestamp(&v["update_at"], false, i64::MIN).unwrap_or(clock);
        let shindo = v
            .get("Shindo")
            .and_then(|n| text(n).parse::<i64>().ok())
            .unwrap_or(0);
        let mut row = json!({
            "id":id,"region":v.get("region").map(text).unwrap_or_default(),
            "coordinate":{"lat":lat,"lng":lon},"isDesktop":v["is_desktop"]==true,
            "shindo":shindo,"lastUpdate":iso(time)
        });
        for (key, original, default) in [
            ("calcShindo", "CalcShindo", -3.0),
            ("intensity", "Intensity", 0.0),
            ("pga", "PGA", 0.0),
            ("pgv", "PGV", 0.0),
            ("maxPga", "Max_PGA", 0.0),
            ("maxPgv", "Max_PGV", 0.0),
            ("maxIntensity", "Max_Intensity", 0.0),
        ] {
            row[key] = json!(number(&v[original]).unwrap_or(default));
        }
        // As in the existing service, metadata is fixed when an ID first arrives.
        if let Some(&i) = self.indices.get(&id) {
            for key in ["region", "coordinate", "isDesktop"] {
                row[key] = self.rows[i][key].clone();
            }
            self.rows[i] = row;
        } else {
            self.indices.insert(id, self.rows.len());
            self.rows.push(row);
        }
        self.revision += 1;
        Some(time)
    }
    pub(super) fn expire(&mut self, clock: i64) -> bool {
        let next = self.expire_at.get_or_insert(clock + 5000);
        if clock < *next {
            return false;
        }
        *next = clock + 5000;
        let before = self.rows.len();
        self.rows.retain(|row| {
            timestamp(&row["lastUpdate"], false, 0).is_none_or(|t| clock - t < 31000)
        });
        if before == self.rows.len() {
            return false;
        }
        self.indices.clear();
        self.revision += 1;
        for (i, row) in self.rows.iter().enumerate() {
            self.indices.insert(row["id"].as_str().unwrap().into(), i);
        }
        true
    }
    pub(super) fn deadline(&self, clock: i64) -> i64 {
        self.expire_at.unwrap_or(clock + 5000)
    }
    pub(super) fn snapshot(&self, clock: i64) -> Value {
        let mut signature = self.rows.len().to_string();
        let mut maximum: Option<&Value> = None;
        let mut special = None;
        let mut automation = Vec::with_capacity(self.rows.len());
        let mut rows = self.rows.clone();
        for row in &mut rows {
            let intensity = number(&row["intensity"]).unwrap();
            let region = row["region"].as_str().unwrap();
            if special.is_none() && (region.contains("六分街") || region.contains("新艾利都"))
            {
                special = Some(row.clone());
            }
            if maximum.is_none_or(|best| intensity > number(&best["intensity"]).unwrap()) {
                // Selection uses the domain rows, not the UI clone's temporary borrow.
                maximum = Some(&self.rows[self.indices[row["id"].as_str().unwrap()]]);
            }
            signature.push_str(&format!(
                "|{}:{:.3}",
                row["id"].as_str().unwrap(),
                intensity
            ));
            row["mapLevel"] = json!(intensity.round().clamp(0.0, 12.0) as i32);
            row["mapActive"] = json!(intensity >= 0.0);
            automation.push(
                json!({"id":row["id"],"name":row["region"],"level":row["shindo"],
                "intensity":intensity,"coordinate":row["coordinate"],"time":row["lastUpdate"],
                "strong":row["shindo"].as_i64().unwrap()>=4}),
            );
        }
        json!({"stations":rows,"signature":signature,"automation":automation,
            "summary":{"selected":special,"max":maximum},"receivedAt":iso(clock)})
    }
}
