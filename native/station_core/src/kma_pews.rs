//! Decoder for the official KMA PEWS binary frames.
//!
//! The binary is kept intact at the transport boundary. This module only
//! projects the event tail and station table into bounded JSON values used by
//! the native runtime.

use serde_json::{json, Value};

fn bits(data: &[u8], offset: usize, width: usize) -> Option<u64> {
    if width == 0 || width > 63 || offset.checked_add(width)? > data.len() * 8 {
        return None;
    }
    let mut value = 0u64;
    for index in offset..offset + width {
        value = (value << 1) | u64::from((data[index / 8] >> (7 - index % 8)) & 1);
    }
    Some(value)
}

pub(crate) fn header(data: &[u8]) -> Option<(u8, String, bool)> {
    let word = u32::from_be_bytes(data.get(0..4)?.try_into().ok()?);
    let phase = match (word >> 29) & 3 {
        0 => 1,
        2 => 2,
        3 => 3,
        _ => 4,
    };
    Some((
        phase,
        format!("20{}", word & ((1 << 26) - 1)),
        word & (1 << 31) != 0,
    ))
}

pub(crate) fn event_tail(data: &[u8]) -> Option<&[u8]> {
    (data.len() >= 80).then(|| &data[data.len() - 75..])
}

pub(crate) fn stations(data: &[u8]) -> Option<Vec<Value>> {
    if data.len() * 8 < 20 {
        return None;
    }
    let count = data.len() * 8 / 20;
    let mut result = Vec::with_capacity(count);
    for index in 0..count {
        let lat_raw = bits(data, index * 20, 10)? as f64;
        let lon_raw = bits(data, index * 20 + 10, 10)? as f64;
        let longitude_base = if (lat_raw as i32, lon_raw as i32) == (748, 89)
            || (lat_raw as i32, lon_raw as i32) == (751, 81)
        {
            130.0
        } else {
            120.0
        };
        let latitude = (3000.0 + lat_raw) / 100.0;
        let longitude = (longitude_base * 100.0 + lon_raw) / 100.0;
        if !(30.0..=40.0).contains(&latitude) || !(120.0..=132.0).contains(&longitude) {
            return None;
        }
        result.push(json!({"latitude": latitude, "longitude": longitude}));
    }
    Some(result)
}

fn percent_decode(input: &[u8]) -> String {
    let mut out = Vec::with_capacity(input.len());
    let mut index = 0;
    while index < input.len() {
        if input[index] == b'%' && index + 2 < input.len() {
            let hi = (input[index + 1] as char).to_digit(16);
            let lo = (input[index + 2] as char).to_digit(16);
            if let (Some(hi), Some(lo)) = (hi, lo) {
                out.push((hi * 16 + lo) as u8);
                index += 3;
                continue;
            }
        }
        out.push(if input[index] == b'+' {
            b' '
        } else {
            input[index]
        });
        index += 1;
    }
    String::from_utf8_lossy(&out).trim().to_string()
}

pub(crate) fn event(data: &[u8], phase: u8, label: &str) -> Option<Value> {
    if !matches!(phase, 2 | 3) {
        return None;
    }
    let tail = event_tail(data)?;
    let latitude = (3000.0 + bits(tail, 0, 10)? as f64) / 100.0;
    let longitude = (12400.0 + bits(tail, 10, 10)? as f64) / 100.0;
    let magnitude = bits(tail, 20, 7)? as f64 / 10.0;
    let raw_depth = bits(tail, 27, 10)?;
    let depth = if raw_depth == 0 {
        -1.0
    } else {
        raw_depth as f64 / 10.0
    };
    let epoch = bits(tail, 37, 32)? as i64 + 9 * 3600;
    let event_id = format!("20{}", bits(tail, 69, 26)?);
    let max_intensity = bits(tail, 95, 4)? as i64;
    if max_intensity > 11 || header(data)?.1 != event_id {
        return None;
    }
    let area_mask = bits(tail, 99, 17)?;
    let location = percent_decode(&tail[15..]);
    // Unified events store source wall-clock components. Its policy subtracts
    // timeZone when comparing deadlines, regardless of the serialized Z.
    let origin_time = crate::unified_event_policy::iso_utc((epoch + 9 * 3600) * 1_000_000);
    let report = if phase == 2 { 1 } else { 2 };
    let class_name = match max_intensity {
        0..=1 => "dark-gray",
        2 => "gray",
        3 => "sky-blue",
        4 => "blue",
        5 => "green",
        6 => "yellow",
        7 => "orange",
        8 => "dark-orange",
        9 => "red",
        _ => "purple",
    };
    Some(json!({
        "source": "kmaEew",
        "origin": 8,
        "eventId": event_id,
        "isEew": true,
        "timeZone": 9,
        "titleText": "기상청 지진조기경보",
        "reportNumText": format!("第{}報", report),
        "useShindo": false,
        "maxIntensity": format!("{:.1}", max_intensity as f64),
        "className": class_name,
        "hypocenter": location,
        "originTime": origin_time,
        "reportTime": Value::Null,
        "magnitude": magnitude,
        "depth": depth,
        "depthText": if depth < 0.0 { "不明".to_string() } else { format!("{:.1} km", depth) },
        "lat": latitude,
        "lng": longitude,
        "isWarn": max_intensity as f64 >= 6.5,
        "isFinal": phase >= 3,
        "isCanceled": false,
        "isAssumption": false,
        "warnArea": "",
        "apiTypeLabel": label,
        "isSnapshot": false,
        "hasReportSequence": false,
        "useSourceTimeForExpiry": true,
        "sourcePayload": {"phase": phase, "areaMask": area_mask, "rawDepth": raw_depth, "rawBytes": data.len()},
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn decodes_reference_event_tail() {
        let bytes = include_bytes!(
            "../../../server/kma_pews_relay/test_fixtures/kma_20261117142557.original.b"
        );
        let value = event(bytes, 3, "KMA-PEWS").unwrap();
        assert_eq!(value["eventId"], "2026011364");
        assert_eq!(value["magnitude"], 3.6);
        assert_eq!(value["depth"], 20.0);
        assert_eq!(value["lat"], 36.52);
        assert_eq!(value["lng"], 127.96);
        assert_eq!(
            crate::unified_event_policy::instant(&value, "originTime"),
            Some(1_794_924_617_000_000),
        );
    }
}
