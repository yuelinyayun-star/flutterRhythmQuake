use serde_json::Value;
use std::f64::consts::PI;

fn number(row: &Value, key: &str) -> Option<f64> {
    let value = &row[key];
    value
        .as_f64()
        .or_else(|| value.as_str()?.parse().ok())
        .filter(|v| v.is_finite())
}

// The provider passes these positions straight to BMap.Point (BD-09).
// Convert the station position for our geographic map. Rainfall stays as sent.
fn geographic(lon: f64, lat: f64) -> (f64, f64) {
    let x = lon - 0.0065;
    let y = lat - 0.006;
    let angle_scale = PI * 3000.0 / 180.0;
    let radius = x.hypot(y) - 0.00002 * (y * angle_scale).sin();
    let angle = y.atan2(x) - 0.000003 * (x * angle_scale).cos();
    let lon = radius * angle.cos();
    let lat = radius * angle.sin();

    let x = lon - 105.0;
    let y = lat - 35.0;
    let common = (20.0 * (6.0 * x * PI).sin() + 20.0 * (2.0 * x * PI).sin()) * 2.0 / 3.0;
    let dy = -100.0
        + 2.0 * x
        + 3.0 * y
        + 0.2 * y * y
        + 0.1 * x * y
        + 0.2 * x.abs().sqrt()
        + common
        + (20.0 * (y * PI).sin() + 40.0 * (y * PI / 3.0).sin()) * 2.0 / 3.0
        + (160.0 * (y * PI / 12.0).sin() + 320.0 * (y * PI / 30.0).sin()) * 2.0 / 3.0;
    let dx = 300.0
        + x
        + 2.0 * y
        + 0.1 * x * x
        + 0.1 * x * y
        + 0.1 * x.abs().sqrt()
        + common
        + (20.0 * (x * PI).sin() + 40.0 * (x * PI / 3.0).sin()) * 2.0 / 3.0
        + (150.0 * (x * PI / 12.0).sin() + 300.0 * (x * PI / 30.0).sin()) * 2.0 / 3.0;
    let radians = lat.to_radians();
    let eccentricity = 0.006693421622965943;
    let magic = 1.0 - eccentricity * radians.sin().powi(2);
    let axis = 6378245.0;
    let lat_delta = dy.to_degrees() * magic.powf(1.5) / (axis * (1.0 - eccentricity));
    let lon_delta = dx.to_degrees() * magic.sqrt() / (axis * radians.cos());
    (lat - lat_delta, lon - lon_delta)
}

fn stations(bytes: &[u8], stamp: u64) -> Option<Vec<f64>> {
    let text = std::str::from_utf8(bytes)
        .ok()?
        .trim_start_matches('\u{feff}')
        .trim();
    let body = text
        .strip_prefix("webgisDot")?
        .trim_start()
        .strip_prefix('(')?
        .trim_end_matches(';')
        .trim_end()
        .strip_suffix(')')?;
    let doc: Value = serde_json::from_str(body).ok()?;
    let time = doc["d3"].as_str()?.parse::<u64>().ok()?;
    let rows = doc["data"].as_array()?;
    if time != stamp || rows.len() > 4096 {
        return None;
    }
    let mut output = Vec::with_capacity(rows.len() * 3);
    for row in rows {
        let (Some(lon), Some(lat), Some(rain)) =
            (number(row, "x"), number(row, "y"), number(row, "v"))
        else {
            continue;
        };
        if !(73.0..=136.0).contains(&lon)
            || !(18.0..=55.0).contains(&lat)
            || !(0.0..9000.0).contains(&rain)
        {
            continue;
        }
        let (lat, lon) = geographic(lon, lat);
        output.extend([lat, lon, rain]);
    }
    Some(output)
}

#[no_mangle]
pub unsafe extern "C" fn rq_weather_precipitation_stations(
    input: *const u8,
    len: usize,
    stamp: u64,
    output: *mut f64,
    capacity: usize,
) -> i32 {
    if input.is_null() || output.is_null() || len > 512 * 1024 {
        return -1;
    }
    std::panic::catch_unwind(|| {
        let Some(values) = stations(unsafe { std::slice::from_raw_parts(input, len) }, stamp)
        else {
            return -1;
        };
        if values.len() > capacity {
            return -1;
        }
        unsafe { std::ptr::copy_nonoverlapping(values.as_ptr(), output, values.len()) };
        (values.len() / 3) as i32
    })
    .unwrap_or(-1)
}
