//! NIED GIF sampling only. Immutable original RGBA in; position, shindo and
//! current-pixel quality out. Transparent pixels are missing, never a low value.
use std::sync::atomic::{AtomicU64, Ordering};
static CALLS: AtomicU64 = AtomicU64::new(0);
const VALID: u64 = 1 << 32;
const MAX: usize = 1_048_576;
// Exact existing ShindoColorUtil palette; other providers retain their code.
const PALETTE: &[(u8, u8, u8, f64)] = &[
    (0, 0, 0, -3.0),
    (0, 0, 26, -3.0),
    (0, 0, 77, -3.0),
    (0, 0, 103, -3.0),
    (0, 0, 128, -3.0),
    (0, 0, 154, -3.0),
    (0, 0, 179, -3.0),
    (0, 0, 205, -3.0),
    (0, 7, 209, -2.9),
    (0, 18, 213, -2.8),
    (0, 36, 214, -2.7),
    (0, 55, 213, -2.6),
    (0, 73, 211, -2.5),
    (0, 91, 210, -2.4),
    (0, 110, 210, -2.3),
    (0, 128, 212, -2.2),
    (0, 146, 215, -2.1),
    (0, 165, 214, -2.0),
    (0, 183, 207, -1.9),
    (0, 201, 201, -1.8),
    (0, 220, 193, -1.7),
    (0, 238, 167, -1.6),
    (0, 255, 134, -1.5),
    (0, 255, 96, -1.4),
    (0, 255, 57, -1.3),
    (0, 255, 19, -1.2),
    (22, 255, 0, -1.1),
    (67, 255, 0, -1.0),
    (121, 255, 0, -0.9),
    (170, 255, 0, -0.8),
    (219, 255, 0, -0.7),
    (255, 244, 0, -0.6),
    (255, 225, 0, -0.5),
    (255, 206, 0, -0.4),
    (255, 187, 0, -0.3),
    (255, 168, 0, -0.2),
    (255, 149, 0, -0.1),
    (255, 130, 0, 0.0),
    (255, 111, 0, 0.1),
    (255, 92, 0, 0.2),
    (255, 73, 0, 0.3),
    (255, 54, 0, 0.4),
    (255, 35, 0, 0.5),
    (255, 16, 0, 0.6),
    (249, 0, 0, 0.7),
    (230, 0, 0, 0.8),
    (211, 0, 0, 0.9),
    (192, 0, 0, 1.0),
    (173, 0, 0, 1.1),
    (154, 0, 0, 1.2),
    (135, 0, 0, 1.3),
    (116, 0, 0, 1.4),
    (97, 0, 0, 1.5),
    (78, 0, 0, 1.6),
    (59, 0, 0, 1.7),
    (40, 0, 0, 1.8),
    (21, 0, 0, 1.9),
    (13, 0, 11, 2.0),
    (18, 0, 25, 2.1),
    (22, 0, 40, 2.2),
    (27, 0, 54, 2.3),
    (31, 0, 69, 2.4),
    (36, 0, 84, 2.5),
    (40, 0, 98, 2.6),
    (45, 0, 113, 2.7),
    (49, 0, 127, 2.8),
    (54, 0, 142, 2.9),
    (58, 0, 156, 3.0),
    (63, 0, 171, 3.1),
    (67, 0, 185, 3.2),
    (72, 0, 200, 3.3),
    (76, 0, 214, 3.4),
    (81, 0, 229, 3.5),
    (85, 0, 243, 3.6),
    (90, 0, 255, 3.7),
    (95, 0, 255, 3.8),
    (100, 0, 255, 3.9),
    (105, 0, 255, 4.0),
    (110, 0, 255, 4.1),
    (115, 0, 255, 4.2),
    (120, 0, 255, 4.3),
    (125, 0, 255, 4.4),
    (130, 0, 255, 4.5),
    (135, 0, 255, 4.6),
    (140, 0, 255, 4.7),
    (145, 0, 255, 4.8),
    (150, 0, 255, 4.9),
    (155, 0, 255, 5.0),
    (160, 0, 255, 5.1),
    (165, 0, 255, 5.2),
    (170, 0, 255, 5.3),
    (175, 0, 255, 5.4),
    (180, 0, 255, 5.5),
    (185, 0, 255, 5.6),
    (190, 0, 255, 5.7),
    (195, 0, 255, 5.8),
    (200, 0, 255, 5.9),
    (205, 0, 255, 6.0),
    (210, 0, 255, 6.1),
    (215, 0, 255, 6.2),
    (220, 0, 255, 6.3),
    (225, 0, 255, 6.4),
    (230, 0, 255, 6.5),
    (235, 0, 255, 6.6),
    (240, 0, 255, 6.7),
    (245, 0, 255, 6.8),
    (250, 0, 255, 6.9),
    (255, 0, 255, 7.0),
];

fn palette(r: u8, g: u8, b: u8) -> Option<f64> {
    PALETTE
        .iter()
        .find(|v| (v.0, v.1, v.2) == (r, g, b))
        .map(|v| v.3)
}
#[inline(never)]
fn dart_pow(x: f64, exponent: f64) -> f64 {
    // Dart's recognized constant powers 2/3 use ordered multiplication.
    // CRT pow(x, 3) differs by one ulp for ordinary GIF palette colors.
    if exponent == 2.0 {
        return x * x;
    }
    if exponent == 3.0 {
        return x * x * x;
    }
    x.powf(std::hint::black_box(exponent))
}
fn position(r: u8, g: u8, b: u8) -> Option<f64> {
    if (r, g, b) == (0, 0, 0) {
        return None;
    }
    let (rn, gn, bn) = (r as f64 / 255.0, g as f64 / 255.0, b as f64 / 255.0);
    let high = rn.max(gn.max(bn));
    let low = rn.min(gn.min(bn));
    let delta = high - low;
    let mut h = if delta == 0.0 {
        0.0
    } else if high == rn {
        60.0 * ((gn - bn) / delta).rem_euclid(6.0)
    } else if high == gn {
        60.0 * ((bn - rn) / delta + 2.0)
    } else {
        60.0 * ((rn - gn) / delta + 4.0)
    };
    if h < 0.0 {
        h += 360.0;
    }
    h /= 360.0;
    let saturation = if high == 0.0 { 0.0 } else { delta / high };
    let p = if high <= 0.1 || saturation <= 0.75 {
        0.0
    } else if h > 0.1476 {
        280.31 * dart_pow(h, 6.0) - 916.05 * dart_pow(h, 5.0) + 1142.6 * dart_pow(h, 4.0)
            - 709.95 * dart_pow(h, 3.0)
            + 234.65 * dart_pow(h, 2.0)
            - 40.27 * h
            + 3.2217
    } else if h > 0.001 {
        151.4 * dart_pow(h, 4.0) - 49.32 * dart_pow(h, 3.0) + 6.753 * dart_pow(h, 2.0) - 2.481 * h
            + 0.9033
    } else {
        -0.005171 * dart_pow(high, 2.0) - 0.3282 * high + 1.2236
    }
    .clamp(0.0, 1.0);
    if p > 0.0 {
        Some(p)
    } else {
        palette(r, g, b).map(|v| ((v + 3.0) / 10.0).clamp(0.0, 1.0))
    }
}
fn sample(pixel: u64, physical: bool) -> [f64; 3] {
    // Quality: 0 valid, 1 transparent, 2 undecodable, 3 outside image.
    if pixel & VALID == 0 {
        return [f64::NAN, f64::NAN, 3.0];
    }
    let alpha = ((pixel >> 24) & 255) as u32;
    if alpha == 0 {
        return [f64::NAN, f64::NAN, 1.0];
    }
    // Preserve the previous rawRgba premultiplication for nonzero alpha.
    let r = ((((pixel >> 16) & 255) as u32 * alpha + 127) / 255) as u8;
    let g = ((((pixel >> 8) & 255) as u32 * alpha + 127) / 255) as u8;
    let b = (((pixel & 255) as u32 * alpha + 127) / 255) as u8;
    let p = position(r, g, b);
    let shindo = p.map(|p| 10.0 * p - 3.0).or_else(|| palette(r, g, b));
    let valid = if physical {
        p.is_some()
    } else {
        shindo.is_some()
    };
    [
        p.unwrap_or(f64::NAN),
        shindo.unwrap_or(f64::NAN),
        if valid { 0.0 } else { 2.0 },
    ]
}
#[no_mangle]
pub extern "C" fn rq_nied_gif_sample_calls() -> u64 {
    CALLS.load(Ordering::Relaxed)
}
/// Safety: aligned disjoint input count u64 and output count*3 f64; borrowed only.
#[no_mangle]
pub unsafe extern "C" fn rq_nied_gif_sample_rgba(
    pixels: *const u64,
    count: usize,
    physical: u8,
    output: *mut f64,
) -> i32 {
    if count > MAX || physical > 1 {
        return 3;
    }
    if count > 0 && (pixels.is_null() || output.is_null()) {
        return 1;
    }
    if count == 0 {
        return 0;
    }
    std::panic::catch_unwind(|| {
        let input = unsafe { std::slice::from_raw_parts(pixels, count) };
        let out = unsafe { std::slice::from_raw_parts_mut(output, count * 3) };
        for (p, row) in input.iter().zip(out.chunks_exact_mut(3)) {
            row.copy_from_slice(&sample(*p, physical != 0));
        }
        CALLS.fetch_add(1, Ordering::Relaxed);
        0
    })
    .unwrap_or(5)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn original_dart_constant_power_results_are_preserved() {
        assert_eq!(position(0, 64, 245), Some(0.08179322851381832));
        assert_eq!(position(44, 237, 79), Some(0.271057432725351));
    }
    #[test]
    fn transparency_is_not_a_valid_minimum_or_an_in_place_input_rewrite() {
        let input = [VALID, VALID | 0xff0000cd, VALID | 0xff000000, 0];
        let original = input;
        let mut out = [0.0; 12];
        assert_eq!(
            unsafe { rq_nied_gif_sample_rgba(input.as_ptr(), 4, 0, out.as_mut_ptr()) },
            0
        );
        assert!(out[0].is_nan() && out[1].is_nan());
        assert_eq!(out[2], 1.0);
        assert_eq!(out[4], -3.0); // opaque genuine darkest blue is unchanged
        assert_eq!(out[5], 0.0);
        assert_eq!(out[7], -3.0); // opaque black keeps existing palette fallback
        assert_eq!(out[8], 0.0);
        assert_eq!(out[11], 3.0);
        assert_eq!(input, original);
    }
    #[test]
    fn partial_alpha_and_physical_layers_keep_original_conversion() {
        let p = VALID | 0x800000ff;
        assert_eq!(sample(p, false), sample(VALID | 0xff000080, false));
        assert_eq!(sample(VALID, true)[2], 1.0);
        assert_eq!(sample(VALID | 0xff000000, true)[2], 2.0);
    }
}
