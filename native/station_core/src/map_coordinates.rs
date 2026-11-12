use std::sync::atomic::{AtomicUsize, Ordering};

static CALLS: AtomicUsize = AtomicUsize::new(0);
static SESSIONS: AtomicUsize = AtomicUsize::new(0);
struct Geometry {
    input: Vec<f64>,
    output: Vec<f64>,
}

#[no_mangle]
pub extern "C" fn rq_map_coordinates_abi_version() -> u32 {
    1
}
#[no_mangle]
pub extern "C" fn rq_map_coordinates_calls() -> u64 {
    CALLS.load(Ordering::Relaxed) as u64
}
#[no_mangle]
pub extern "C" fn rq_map_coordinates_sessions() -> u64 {
    SESSIONS.load(Ordering::Relaxed) as u64
}

/// Copies the original projected XY pairs; never retains the caller pointer.
#[no_mangle]
pub unsafe extern "C" fn rq_map_coordinates_create(
    input: *const f64,
    count: usize,
) -> *mut std::ffi::c_void {
    if input.is_null() || count > 2_000_000 {
        return std::ptr::null_mut();
    }
    let result = std::panic::catch_unwind(|| {
        let input = unsafe { std::slice::from_raw_parts(input, count * 2) };
        if input.iter().any(|v| !v.is_finite()) {
            return None;
        }
        Some(Geometry {
            input: input.to_vec(),
            output: vec![0.; count * 2],
        })
    });
    match result {
        Ok(Some(geometry)) => {
            SESSIONS.fetch_add(1, Ordering::Relaxed);
            Box::into_raw(Box::new(geometry)).cast()
        }
        _ => std::ptr::null_mut(),
    }
}

/// 9 parameters: a,b,c,d,scale,addedWorldWidth,negativeOriginX/Y,worldShift.
/// Keep each IEEE operation in the upstream Dart order; no fused multiply-add.
#[no_mangle]
pub unsafe extern "C" fn rq_map_coordinates_transform(
    handle: *mut std::ffi::c_void,
    params: *const f64,
) -> *const f64 {
    if handle.is_null() || params.is_null() {
        return std::ptr::null();
    }
    let geometry = unsafe { &mut *handle.cast::<Geometry>() };
    let p = unsafe { std::slice::from_raw_parts(params, 9) };
    if p.iter().any(|v| !v.is_finite()) {
        return std::ptr::null();
    }
    for (xy, out) in geometry
        .input
        .chunks_exact(2)
        .zip(geometry.output.chunks_exact_mut(2))
    {
        out[0] = p[4] * (p[0] * (xy[0] + p[5]) + p[1]) + p[6] + p[8];
        out[1] = p[4] * (p[2] * xy[1] + p[3]) + p[7];
    }
    CALLS.fetch_add(1, Ordering::Relaxed);
    geometry.output.as_ptr()
}
#[no_mangle]
pub unsafe extern "C" fn rq_map_coordinates_destroy(handle: *mut std::ffi::c_void) {
    if !handle.is_null() {
        unsafe {
            drop(Box::from_raw(handle.cast::<Geometry>()));
        }
        SESSIONS.fetch_sub(1, Ordering::Relaxed);
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn ownership_reuse_and_original_math() {
        let input = [-0., 0., 123.456, -987.654];
        let owner = unsafe { rq_map_coordinates_create(input.as_ptr(), 2) };
        assert!(!owner.is_null());
        let p = [
            0.001, 0.5, -0.001, 0.5, 32768., 40000., -137.3, -14.25, -200.,
        ];
        let out = unsafe {
            std::slice::from_raw_parts(rq_map_coordinates_transform(owner, p.as_ptr()), 4)
        };
        for i in 0..2 {
            assert_eq!(
                out[i * 2].to_bits(),
                (p[4] * (p[0] * (input[i * 2] + p[5]) + p[1]) + p[6] + p[8]).to_bits()
            );
            assert_eq!(
                out[i * 2 + 1].to_bits(),
                (p[4] * (p[2] * input[i * 2 + 1] + p[3]) + p[7]).to_bits()
            );
        }
        assert!(unsafe { rq_map_coordinates_transform(owner, std::ptr::null()) }.is_null());
        unsafe {
            rq_map_coordinates_destroy(owner);
        }
        assert_eq!(rq_map_coordinates_sessions(), 0);
        assert!(unsafe { rq_map_coordinates_create(std::ptr::null(), 2) }.is_null());
    }
}
