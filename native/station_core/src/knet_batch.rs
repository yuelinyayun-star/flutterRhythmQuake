use std::cmp::Ordering;

/// Per-second output: PGA, horizontal PGA, PGV, RMS, energy/baseline, duration proxy.
/// Nullable fields are NaN. Missing channels use zero acceleration.
/// All three channel arrays, if present, are borrowed and never modified.
#[no_mangle]
pub unsafe extern "C" fn rq_knet_batch_features(
    channels: *const *const f64,
    lengths: *const usize,
    starts: *const usize,
    offsets: *const f64,
    sample_count: usize,
    samples_per_second: usize,
    sampling_hz: f64,
    duration_seconds: f64,
    baseline_seconds: isize,
    epsilon: f64,
    output: *mut f64,
) -> i32 {
    std::panic::catch_unwind(|| {
        if channels.is_null()
            || lengths.is_null()
            || starts.is_null()
            || offsets.is_null()
            || output.is_null()
            || sample_count == 0
            || sample_count > 4_000_000
            || samples_per_second == 0
            || samples_per_second > sample_count
            || !sampling_hz.is_finite()
            || sampling_hz <= 0.0
            || !duration_seconds.is_finite()
            || !epsilon.is_finite()
        {
            return 1;
        }

        let ptrs = unsafe { std::slice::from_raw_parts(channels, 3) };
        let lengths = unsafe { std::slice::from_raw_parts(lengths, 3) };
        let starts = unsafe { std::slice::from_raw_parts(starts, 3) };
        let offsets = unsafe { std::slice::from_raw_parts(offsets, 3) };
        let mut inputs: [Option<&[f64]>; 3] = [None, None, None];
        for axis in 0..3 {
            if !offsets[axis].is_finite() {
                return 1;
            }
            if ptrs[axis].is_null() {
                if lengths[axis] != 0 || starts[axis] != 0 {
                    return 1;
                }
                continue;
            }
            if starts[axis] > lengths[axis]
                || sample_count > lengths[axis] - starts[axis]
                || lengths[axis] > 4_000_000
            {
                return 1;
            }
            let slice = unsafe { std::slice::from_raw_parts(ptrs[axis], lengths[axis]) };
            inputs[axis] = Some(&slice[starts[axis]..starts[axis] + sample_count]);
        }
        let second_count = sample_count / samples_per_second;
        let out = unsafe { std::slice::from_raw_parts_mut(output, second_count * 6) };
        let mut velocity = [0.0_f64; 3];
        let dt = 1.0 / sampling_hz;
        let mut rms_history: Vec<f64> = Vec::with_capacity(second_count);
        let mut vectors: Vec<f64> = Vec::with_capacity(samples_per_second);

        for second in 0..second_count {
            vectors.clear();
            let (mut pga, mut horizontal_max, mut pgv, mut sum_square) =
                (0.0_f64, 0.0_f64, 0.0_f64, 0.0_f64);
            for i in second * samples_per_second..(second + 1) * samples_per_second {
                let mut acceleration = [0.0_f64; 3];
                for axis in 0..3 {
                    if let Some(input) = inputs[axis] {
                        acceleration[axis] = input[i] - offsets[axis];
                        if !acceleration[axis].is_finite() {
                            return 2;
                        }
                        velocity[axis] += acceleration[axis] * dt;
                    }
                }
                let horizontal =
                    (acceleration[0] * acceleration[0] + acceleration[1] * acceleration[1]).sqrt();
                let vector = (horizontal * horizontal + acceleration[2] * acceleration[2]).sqrt();
                vectors.push(vector);
                pga = pga.max(vector);
                horizontal_max = horizontal_max.max(horizontal);
                sum_square += vector * vector;
                pgv = pgv.max(
                    (velocity[0] * velocity[0]
                        + velocity[1] * velocity[1]
                        + velocity[2] * velocity[2])
                        .sqrt(),
                );
            }
            let rms = (sum_square / samples_per_second as f64).sqrt();
            let ratio = if rms_history.is_empty() || baseline_seconds <= 0 {
                f64::NAN
            } else {
                let window = baseline_seconds as usize;
                let start = rms_history.len().saturating_sub(window);
                let slice = &rms_history[start..];
                let mut sum = 0.0;
                for value in slice {
                    sum += value;
                }
                let baseline = sum / slice.len() as f64;
                if baseline <= epsilon {
                    f64::NAN
                } else {
                    rms / baseline
                }
            };
            rms_history.push(rms);
            let duration_samples = (duration_seconds * sampling_hz).ceil();
            let selected = if duration_samples.is_nan() {
                1
            } else {
                duration_samples.max(1.0).min(vectors.len() as f64) as usize
            };
            let index = vectors.len() - selected;
            vectors
                .select_nth_unstable_by(index, |a, b| a.partial_cmp(b).unwrap_or(Ordering::Equal));
            let threshold = vectors[index];
            let proxy = if threshold <= 0.0 {
                f64::NAN
            } else {
                2.0 * threshold.log10() + 0.94
            };
            let row = &mut out[second * 6..second * 6 + 6];
            row.copy_from_slice(&[pga, horizontal_max, pgv, rms, ratio, proxy]);
        }
        0
    })
    .unwrap_or(3)
}

#[cfg(test)]
mod tests {
    use super::rq_knet_batch_features;

    fn run(
        ns: Option<&[f64]>,
        ew: Option<&[f64]>,
        ud: Option<&[f64]>,
        offsets: [f64; 3],
        samples_per_second: usize,
        baseline: isize,
    ) -> (i32, Vec<f64>) {
        let arrays = [ns, ew, ud];
        let ptrs = arrays.map(|value| value.map_or(std::ptr::null(), |slice| slice.as_ptr()));
        let lens = arrays.map(|value| value.map_or(0, |slice| slice.len()));
        let starts = [0_usize; 3];
        let mut out = vec![0.0; (ns.or(ew).or(ud).unwrap().len() / samples_per_second) * 6];
        let code = unsafe {
            rq_knet_batch_features(
                ptrs.as_ptr(),
                lens.as_ptr(),
                starts.as_ptr(),
                offsets.as_ptr(),
                ns.or(ew).or(ud).unwrap().len(),
                samples_per_second,
                samples_per_second as f64,
                0.3,
                baseline,
                1e-9,
                out.as_mut_ptr(),
            )
        };
        (code, out)
    }

    #[test]
    fn continuous_velocity_energy_and_proxy() {
        let ns: Vec<f64> = [vec![2.0; 10], vec![3.0; 10]].concat();
        let ew = vec![0.0; 20];
        let (code, out) = run(Some(&ns), Some(&ew), None, [1.0, 0.0, 0.0], 10, 3);
        assert_eq!(code, 0);
        assert!((out[0] - 1.0).abs() < 1e-12);
        assert!((out[2] - 1.0).abs() < 1e-12);
        assert!(out[4].is_nan());
        assert!((out[5] - 0.94).abs() < 1e-12);
        assert!((out[6] - 2.0).abs() < 1e-12);
        assert!((out[8] - 3.0).abs() < 1e-12);
        assert!((out[10] - 2.0).abs() < 1e-12);
    }

    #[test]
    fn validates_channel_bounds() {
        let ns = [1.0_f64, 2.0, 3.0, 4.0];
        let ptrs = [ns.as_ptr(), std::ptr::null(), std::ptr::null()];
        let lens = [ns.len(), 0, 0];
        let starts = [2, 0, 0];
        let offsets = [0.0; 3];
        let mut out = [0.0; 6];
        assert_eq!(
            unsafe {
                rq_knet_batch_features(
                    ptrs.as_ptr(),
                    lens.as_ptr(),
                    starts.as_ptr(),
                    offsets.as_ptr(),
                    4,
                    4,
                    4.0,
                    0.3,
                    3,
                    1e-9,
                    out.as_mut_ptr(),
                )
            },
            1
        );
    }
}
