//! ExpTech's public rts.v1 transport. Observations remain in their original schema.
use base64::{engine::general_purpose::STANDARD, Engine};
use serde_json::Value;
use std::io::Read;

const MAX_BYTES: usize = 8 * 1024 * 1024;

pub struct Station {
    pub id: String,
    pub lat: f64,
    pub lon: f64,
    pub code: i64,
    pub net: String,
    pub work: bool,
}

pub fn catalogue(csv: &str) -> Vec<Station> {
    let mut lines = csv.trim_start_matches('\u{feff}').lines();
    let Some(header) = lines.next() else { return vec![] };
    let columns: Vec<_> = header.split(',').map(str::trim).collect();
    let col = |name| columns.iter().position(|&v| v == name);
    let (Some(id), Some(lat), Some(lon), Some(code)) =
        (col("id"), col("lat"), col("lon"), col("code")) else { return vec![] };
    let net = col("net");
    let work = col("work");
    lines.filter_map(|line| {
        let cells: Vec<_> = line.split(',').map(str::trim).collect();
        let id = cells.get(id)?;
        let lat: f64 = cells.get(lat)?.parse().ok()?;
        let lon: f64 = cells.get(lon)?.parse().ok()?;
        if id.is_empty() || !lat.is_finite() || !lon.is_finite()
            || lat.abs() > 90.0 || lon.abs() > 180.0 { return None; }
        Some(Station {
            id: (*id).into(), lat, lon,
            code: cells.get(code)?.parse().ok()?,
            net: net.and_then(|i| cells.get(i)).unwrap_or(&"").to_string(),
            work: work.and_then(|i| cells.get(i)) == Some(&"1"),
        })
    }).collect()
}

pub fn payload(data: &[u8]) -> Option<Value> {
    if let Ok(v) = serde_json::from_slice::<Value>(data) { return Some(v); }
    let compact: Vec<_> = data.iter().copied().filter(|b| !b.is_ascii_whitespace()).collect();
    let compressed = STANDARD.decode(compact).ok()?;
    if !compressed.starts_with(&[0x1f, 0x8b]) { return None; }
    let mut decoded = Vec::new();
    flate2::read::GzDecoder::new(compressed.as_slice())
        .take(MAX_BYTES as u64 + 1).read_to_end(&mut decoded).ok()?;
    if decoded.len() > MAX_BYTES { return None; }
    serde_json::from_slice(&decoded).ok()
}

#[derive(Default)]
pub struct Stream {
    line: Vec<u8>,
    event: Vec<u8>,
    data: Vec<u8>,
}
impl Stream {
    pub fn push(&mut self, bytes: &[u8]) -> Result<Vec<Value>, &'static str> {
        let mut frames = vec![];
        for &b in bytes {
            if b != b'\n' {
                self.line.push(b);
                if self.line.len() + self.data.len() > MAX_BYTES { return Err("TREM SSE block too large"); }
                continue;
            }
            if self.line.last() == Some(&b'\r') { self.line.pop(); }
            if self.line.is_empty() {
                if self.event.is_empty() || self.event == b"trem.rts.v1" {
                    if let Some(v) = payload(&self.data) {
                        if v["stations"].is_object() || v["station"].is_object() { frames.push(v); }
                    }
                }
                self.event.clear();
                self.data.clear();
            } else if let Some(value) = self.line.strip_prefix(b"event:") {
                self.event = value.strip_prefix(b" ").unwrap_or(value).to_vec();
            } else if let Some(value) = self.line.strip_prefix(b"data:") {
                if !self.data.is_empty() { self.data.push(b'\n'); }
                self.data.extend_from_slice(value.strip_prefix(b" ").unwrap_or(value));
            }
            self.line.clear();
        }
        Ok(frames)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    const CSV: &str = include_str!("../../../test/fixtures/trem_rts_v1_20261024/station.original.csv");
    const SSE: &[u8] = include_bytes!("../../../test/fixtures/trem_rts_v1_20261024/rts.original.sse");
    #[test]
    fn original_capture_survives_every_chunk_boundary() {
        let stations = catalogue(CSV);
        assert!(!stations.is_empty());
        let expected = Stream::default().push(SSE).unwrap();
        assert_eq!(expected.len(), 1);
        assert_eq!(expected[0]["stations"].as_object().unwrap().len(), 121);
        for split in 0..=SSE.len() {
            let mut decoder = Stream::default();
            let mut actual = decoder.push(&SSE[..split]).unwrap();
            actual.extend(decoder.push(&SSE[split..]).unwrap());
            assert_eq!(actual, expected);
        }
        let joined = expected[0]["stations"].as_object().unwrap().keys()
            .filter(|id| stations.iter().any(|s| s.work && &s.id == *id)).count();
        assert_eq!(joined, 121);
        assert!(catalogue("<html>not a catalogue</html>").is_empty());
    }
}
