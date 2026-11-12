// WGS84 Vincenty and bearing follow latlong2 0.9.1 (Apache-2.0).
// Copyright (c) 2016 Michael Mitterer; see THIRD_PARTY_NOTICES.txt.
use std::f64::consts::PI;

fn distance(a: &[f64], b: &[f64]) -> Option<f64> {
    let r = PI / 180.0;
    let l = b[1] * r - a[1] * r;
    let f = 1.0 / 298.257223563;
    let u1 = ((1.0 - f) * (a[0] * r).tan()).atan();
    let u2 = ((1.0 - f) * (b[0] * r).tan()).atan();
    let (s1, c1) = (u1.sin(), u1.cos());
    let (s2, c2) = (u2.sin(), u2.cos());
    let mut lambda = l;
    for _ in 0..200 {
        let (sl, cl) = (lambda.sin(), lambda.cos());
        let q = c1 * s2 - s1 * c2 * cl;
        let ss = ((c2 * sl) * (c2 * sl) + q * q).sqrt();
        if ss == 0.0 {
            return Some(0.0);
        }
        let cs = s1 * s2 + c1 * c2 * cl;
        let sigma = ss.atan2(cs);
        let sa = c1 * c2 * sl / ss;
        let ca = 1.0 - sa * sa;
        let mut c2m = cs - 2.0 * s1 * s2 / ca;
        if c2m.is_nan() {
            c2m = 0.0;
        }
        let c = f / 16.0 * ca * (4.0 + f * (4.0 - 3.0 * ca));
        let next =
            l + (1.0 - c) * f * sa * (sigma + c * ss * (c2m + c * cs * (-1.0 + 2.0 * c2m * c2m)));
        if (next - lambda).abs() <= 1e-12 {
            let equator = 6378137.0_f64;
            let polar = 6356752.314245_f64;
            let usq = ca * (equator * equator - polar * polar) / (polar * polar);
            let aa = 1.0 + usq / 16384.0 * (4096.0 + usq * (-768.0 + usq * (320.0 - 175.0 * usq)));
            let bb = usq / 1024.0 * (256.0 + usq * (-128.0 + usq * (74.0 - 47.0 * usq)));
            let delta = bb
                * ss
                * (c2m
                    + bb / 4.0
                        * (cs * (-1.0 + 2.0 * c2m * c2m)
                            - bb / 6.0 * c2m * (-3.0 + 4.0 * ss * ss) * (-3.0 + 4.0 * c2m * c2m)));
            return Some((polar * aa * (sigma - delta)).round());
        }
        lambda = next;
    }
    None
}

fn direction(a: &[f64], b: &[f64]) -> usize {
    let r = PI / 180.0;
    let dl = b[1] * r - a[1] * r;
    let bearing = dl
        .sin()
        .atan2((a[0] * r).cos() * (b[0] * r).tan() - (a[0] * r).sin() * dl.cos())
        * 180.0
        / PI;
    let normalized = (bearing + 360.0).rem_euclid(360.0);
    (((normalized + 45.0) / 90.0).floor() as usize) % 4
}

#[no_mangle]
pub unsafe extern "C" fn rq_palert_topology(
    coordinates: *const f64,
    count: usize,
    output: *mut u32,
) -> i32 {
    if count == 0 {
        return 0;
    }
    if count > 4096 || coordinates.is_null() || output.is_null() {
        return 1;
    }
    std::panic::catch_unwind(|| {
        let coordinates = unsafe { std::slice::from_raw_parts(coordinates, count * 2) };
        if coordinates.chunks_exact(2).any(|p| {
            !p[0].is_finite() || p[0].abs() > 90.0 || !p[1].is_finite() || p[1].abs() > 180.0
        }) {
            return 2;
        }
        let output = unsafe { std::slice::from_raw_parts_mut(output, count * 12) };
        output.fill(u32::MAX);
        let mut candidates = Vec::with_capacity(count - 1);
        for first in 0..count {
            candidates.clear();
            let a = &coordinates[first * 2..first * 2 + 2];
            for second in 0..count {
                if first == second {
                    continue;
                }
                let b = &coordinates[second * 2..second * 2 + 2];
                let Some(km) = distance(a, b) else {
                    return 3;
                };
                candidates.push((second, km));
            }
            crate::palert_distance_sort::sort(&mut candidates);
            let mut counts = [0; 4];
            let mut used = 0;
            for &(second, _) in &candidates {
                let d = direction(a, &coordinates[second * 2..second * 2 + 2]);
                if counts[d] >= 3 {
                    continue;
                }
                counts[d] += 1;
                output[first * 12 + used] = second as u32;
                used += 1;
                if used == 12 {
                    break;
                }
            }
        }
        0
    })
    .unwrap_or(4)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn original_wgs84_units_and_invalid_inputs() {
        assert_eq!(distance(&[0.0, 0.0], &[0.0, 1.0]), Some(111319.0));
        assert_eq!(distance(&[24.0, 121.0], &[24.0, 121.0]), Some(0.0));
        assert_eq!(direction(&[0.0, 0.0], &[1.0, 0.0]), 0);
        assert_eq!(direction(&[0.0, 0.0], &[0.0, 1.0]), 1);
        assert_eq!(
            unsafe { rq_palert_topology(std::ptr::null(), 0, std::ptr::null_mut()) },
            0
        );
        assert_eq!(
            unsafe { rq_palert_topology(std::ptr::null(), 2, std::ptr::null_mut()) },
            1
        );
    }
}
