use std::cmp::Ordering;

/// Returns NaN when input cannot produce an intensity proxy.
#[no_mangle]
pub unsafe extern "C" fn rq_knet_duration_proxy(
    samples: *const f64,
    count: usize,
    hz: f64,
    duration: f64,
) -> f64 {
    std::panic::catch_unwind(|| {
        if samples.is_null()
            || count == 0
            || count > 4_000_000
            || hz <= 0.0
            || !hz.is_finite()
            || !duration.is_finite()
        {
            return f64::NAN;
        }
        let input = unsafe { std::slice::from_raw_parts(samples, count) };
        if input.iter().any(|x| !x.is_finite()) {
            return f64::NAN;
        }
        let requested = (duration * hz).ceil();
        let target = if requested.is_nan() {
            1
        } else {
            requested.max(1.0).min(count as f64) as usize
        };
        let index = count - target;
        let mut values = input.to_vec();
        values.select_nth_unstable_by(index, |a, b| a.partial_cmp(b).unwrap_or(Ordering::Equal));
        let threshold = values[index];
        if threshold <= 0.0 {
            f64::NAN
        } else {
            2.0 * threshold.log10() + 0.94
        }
    })
    .unwrap_or(f64::NAN)
}

#[cfg(test)]
mod tests {
    #[test]
    fn proxy_threshold_and_invalid_input() {
        let values = [1.0, 4.0, 3.0, 2.0];
        let v = unsafe { super::rq_knet_duration_proxy(values.as_ptr(), 4, 4.0, 0.5) };
        assert!((v - (2.0 * 3.0_f64.log10() + 0.94)).abs() < 1e-12);
        assert!(unsafe { super::rq_knet_duration_proxy(std::ptr::null(), 4, 4.0, 0.5) }.is_nan());
    }
}

/// Samples are interleaved NS/EW/UD; metrics: PGA, PGV, sum squares,
/// horizontal PGA, final NS/EW/UD velocities. Velocity is continuous.
#[no_mangle]
pub unsafe extern "C" fn rq_knet_second_metrics(
    samples: *const f64,
    count: usize,
    dt: f64,
    initial_vel: *const f64,
    vectors: *mut f64,
    metrics: *mut f64,
) -> i32 {
    std::panic::catch_unwind(|| {
        if samples.is_null()
            || initial_vel.is_null()
            || vectors.is_null()
            || metrics.is_null()
            || count == 0
            || count > 4_000_000
            || !dt.is_finite()
            || dt <= 0.0
        {
            return 1;
        }
        let inputs = unsafe { std::slice::from_raw_parts(samples, count * 3) };
        let initial = unsafe { std::slice::from_raw_parts(initial_vel, 3) };
        if inputs.iter().any(|v| !v.is_finite()) || initial.iter().any(|v| !v.is_finite()) {
            return 2;
        }
        let out = unsafe { std::slice::from_raw_parts_mut(vectors, count) };
        let metrics = unsafe { std::slice::from_raw_parts_mut(metrics, 7) };
        let (mut ns_v, mut ew_v, mut ud_v) = (initial[0], initial[1], initial[2]);
        let (mut pga, mut pgv, mut sum, mut horizontal_max) = (0.0_f64, 0.0_f64, 0.0_f64, 0.0_f64);
        for (i, xyz) in inputs.chunks_exact(3).enumerate() {
            let (ns, ew, ud) = (xyz[0], xyz[1], xyz[2]);
            let horizontal = (ns * ns + ew * ew).sqrt();
            let vector = (horizontal * horizontal + ud * ud).sqrt();
            out[i] = vector;
            pga = pga.max(vector);
            horizontal_max = horizontal_max.max(horizontal);
            sum += vector * vector;
            ns_v += ns * dt;
            ew_v += ew * dt;
            ud_v += ud * dt;
            pgv = pgv.max((ns_v * ns_v + ew_v * ew_v + ud_v * ud_v).sqrt());
        }
        metrics.copy_from_slice(&[pga, pgv, sum, horizontal_max, ns_v, ew_v, ud_v]);
        0
    })
    .unwrap_or(3)
}

#[cfg(test)]
mod second_tests {
    #[test]
    fn carries_velocity_across_second() {
        let samples = [3.0, 4.0, 0.0, 0.0, 0.0, 12.0];
        let initial = [1.0, 0.0, 0.0];
        let mut vectors = [0.0; 2];
        let mut metrics = [0.0; 7];
        let result = unsafe {
            super::rq_knet_second_metrics(
                samples.as_ptr(),
                2,
                0.5,
                initial.as_ptr(),
                vectors.as_mut_ptr(),
                metrics.as_mut_ptr(),
            )
        };
        assert_eq!(result, 0);
        assert_eq!(vectors, [5.0, 12.0]);
        assert_eq!(metrics[0], 12.0);
        assert_eq!(metrics[2], 169.0);
        assert_eq!(metrics[3], 5.0);
        assert_eq!(metrics[4], 2.5);
        assert_eq!(metrics[5], 2.0);
        assert_eq!(metrics[6], 6.0);
    }
}

/// Copies an aligned time slice of a channel and removes its original offset.
/// Inputs remain borrowed. Returns 0 on success and never partially writes on bad ranges.
#[no_mangle]
pub unsafe extern "C" fn rq_knet_align_component(
    samples: *const f64,
    length: usize,
    start: usize,
    count: usize,
    offset_gal: f64,
    output: *mut f64,
) -> i32 {
    std::panic::catch_unwind(|| {
        if samples.is_null()
            || output.is_null()
            || count == 0
            || count > 4_000_000
            || start > length
            || count > length - start
            || !offset_gal.is_finite()
        {
            return 1;
        }
        let source = unsafe { std::slice::from_raw_parts(samples, length) };
        let destination = unsafe { std::slice::from_raw_parts_mut(output, count) };
        for (value, source_value) in destination.iter_mut().zip(&source[start..start + count]) {
            *value = source_value - offset_gal;
        }
        0
    })
    .unwrap_or(2)
}

#[cfg(test)]
mod alignment_tests {
    #[test]
    fn exact_range_and_offset() {
        let input = [9.0, 11.0, 12.5, -3.0];
        let mut output = [0.0; 2];
        assert_eq!(
            unsafe {
                super::rq_knet_align_component(input.as_ptr(), 4, 1, 2, 10.0, output.as_mut_ptr())
            },
            0
        );
        assert_eq!(output, [1.0, 2.5]);
        assert_ne!(
            unsafe {
                super::rq_knet_align_component(input.as_ptr(), 4, 3, 2, 0.0, output.as_mut_ptr())
            },
            0
        );
    }
}
