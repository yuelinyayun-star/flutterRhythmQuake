use std::sync::atomic::{AtomicUsize, Ordering};
const LIMIT: usize = 1_048_576;
static SESSIONS: AtomicUsize = AtomicUsize::new(0);
static CALLS: AtomicUsize = AtomicUsize::new(0);

#[repr(C)]
pub struct Input {
    pub(crate) station: u64,
    pub(crate) level: i64,
    pub(crate) expire: i64,
    pub(crate) time_ms: i64,
    pub(crate) flags: u64,
    pub(crate) abnormal: i64,
}
#[repr(C)]
#[derive(Default, Clone, Copy)]
pub struct Output {
    pub(crate) level: i64,
    pub(crate) ascend: i64,
    pub(crate) trigger_ms: i64,
    pub(crate) activity: f64,
    pub(crate) abnormal: i64,
    pub(crate) length: u64,
}
pub struct Session {
    histories: Vec<Vec<i64>>,
    shindo_time: Option<i64>,
    shindo_abnormal: Vec<Option<i64>>,
}

fn abnormal(history: &[i64]) -> bool {
    let (mut phase, mut has_previous, mut previous) = (0, false, 0i64);
    let (mut left, mut top, mut right, mut peaks) = (0i64, 0i64, 0i64, 0);
    for &current in history {
        if current == -1 {
            continue;
        }
        if !has_previous {
            previous = current;
            has_previous = true;
            continue;
        }
        if phase == 1 {
            if current >= previous {
                top = current;
            } else {
                right = current;
                phase = 2;
            }
        } else if current <= previous {
            if phase == 2 {
                right = current;
            }
        } else {
            if phase == 2 && top.wrapping_sub(left) >= 3 && top.wrapping_sub(right) >= 3 {
                peaks += 1;
                if peaks >= 3 {
                    return true;
                }
            }
            left = previous;
            top = current;
            phase = 1;
        }
        previous = current;
    }
    if phase == 2 && top.wrapping_sub(left) >= 3 && top.wrapping_sub(right) >= 3 {
        peaks += 1;
    }
    peaks >= 3
}
fn ascend(history: &[i64], expire: i64, level: i64, time: i64) -> (i64, i64) {
    let mut values = [0i64; 60];
    values[..history.len()].copy_from_slice(history);
    let mut length = history.len();
    let mut index = history.iter().position(|&x| x == -1).unwrap_or(length);
    while index < length {
        if values[index] != -1 {
            index += 1;
            continue;
        }
        let (mut missing, mut next) = (1i64, index + 1);
        while next < length && values[next] == -1 {
            missing += 1;
            if missing > expire {
                length = index;
                break;
            }
            next += 1;
        }
        if index >= length {
            break;
        }
        if next < length {
            values[index] = values[next];
            index += 1;
        } else {
            length = index;
            break;
        }
    }
    if length == 0 {
        return (0, 0);
    }
    let (mut min_value, mut min_index, mut identical) = (values[0], 0usize, 1i64);
    for i in 0..length - 1 {
        if values[i + 1] < values[i] {
            min_value = values[i + 1];
            min_index = i + 1;
            identical = 1;
        } else if values[i + 1] > values[i] {
            break;
        } else {
            identical += 1;
            if identical > expire {
                break;
            }
        }
    }
    let rise = level.wrapping_sub(min_value);
    let stamp = if rise > 0 && history[min_index] != -1 {
        time.wrapping_sub(min_index as i64 * 1000)
    } else {
        0
    };
    (rise, stamp)
}
fn activity(level: i64, rise: i64, active: bool) -> f64 {
    let a = if rise > 0 || active {
        if level <= 5 {
            0.0
        } else if level <= 7 {
            (if active { 0.5 } else { 0.25 }) * level.wrapping_sub(5) as f64
        } else if level <= 11 {
            2.0 * level.wrapping_sub(7) as f64
        } else {
            6.0 * level.wrapping_sub(10) as f64
        }
    } else {
        0.0
    };
    let b = if rise <= 0 {
        0.0
    } else if rise <= 1 {
        if active {
            0.5
        } else {
            0.25
        }
    } else if rise <= 6 {
        2.0 * rise.wrapping_sub(2) as f64 + 1.0
    } else {
        6.0 * rise.wrapping_sub(5) as f64
    };
    a + b
}
pub(crate) fn update(history: &mut Vec<i64>, row: &Input) -> Output {
    let origin = row.level.clamp(-1, 20);
    let level = if origin != -1 {
        origin
    } else {
        history
            .iter()
            .take(4)
            .copied()
            .find(|&x| x != -1)
            .unwrap_or(-1)
    };
    if history.capacity() < 60 {
        history.reserve_exact(60 - history.len());
    }
    history.truncate(59);
    history.insert(0, origin);
    let mut out = Output {
        level,
        abnormal: row.abnormal,
        length: history.len() as u64 | (if row.flags & 2 != 0 { 1 << 32 } else { 0 }),
        ..Output::default()
    };
    if abnormal(history) {
        out.abnormal = 0;
        out.length |= 1 << 32;
    } else if row.flags & 2 != 0 {
        let next = row.abnormal.wrapping_add(1);
        out.abnormal = next;
        if next >= 600 {
            out.length &= !(1 << 32);
        }
    } else {
        (out.ascend, out.trigger_ms) = ascend(history, row.expire, level, row.time_ms);
    }
    if out.ascend <= 0 {
        out.trigger_ms = 0;
    }
    out.activity = activity(level, out.ascend, row.flags & 1 != 0);
    out
}
#[no_mangle]
pub extern "C" fn rq_ka_abi_version() -> u32 {
    1
}
#[no_mangle]
pub extern "C" fn rq_ka_sessions() -> u64 {
    SESSIONS.load(Ordering::Relaxed) as u64
}
#[no_mangle]
pub extern "C" fn rq_ka_calls() -> u64 {
    CALLS.load(Ordering::Relaxed) as u64
}
#[no_mangle]
pub extern "C" fn rq_ka_create(count: usize) -> *mut Session {
    if count > LIMIT {
        return std::ptr::null_mut();
    }
    let ptr = std::panic::catch_unwind(|| {
        Box::into_raw(Box::new(Session {
            histories: (0..count).map(|_| Vec::new()).collect(),
            shindo_time: None,
            shindo_abnormal: vec![None; count],
        }))
    })
    .unwrap_or(std::ptr::null_mut());
    if !ptr.is_null() {
        SESSIONS.fetch_add(1, Ordering::Relaxed);
    }
    ptr
}
/// Raw array observations use the same input layout, with raw f64 bits in
/// `level`. Validation, missing-frame insertion, KA history and its derived
/// values execute in one native call. Input and source timestamps are read-only.
/// Flags output: bit 0 is valid raw shindo; bit 1 clears a stale active hold.
/// Safety: exclusive live session; nonoverlapping aligned arrays of count rows.
#[no_mangle]
pub unsafe extern "C" fn rq_ka_process_shindo(
    session: *mut Session,
    input: *const Input,
    count: usize,
    time_ms: i64,
    output: *mut Output,
    flags: *mut u8,
) -> i32 {
    if session.is_null()
        || count > LIMIT
        || (count > 0 && (input.is_null() || output.is_null() || flags.is_null()))
    {
        return 1;
    }
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let session = unsafe { &mut *session };
        if count != session.histories.len() {
            return 3;
        }
        if count == 0 {
            session.shindo_time = Some(time_ms);
            return 0;
        }
        let input = unsafe { std::slice::from_raw_parts(input, count) };
        // Check the entire frame before changing any rolling state.
        if input
            .iter()
            .enumerate()
            .any(|(i, r)| r.station != i as u64 || r.flags > 1)
        {
            return 3;
        }
        let diff = session
            .shindo_time
            .map_or(0, |t| time_ms as i128 - t as i128);
        let missing = if diff > 1000 {
            (((diff as f64 / 1000.0).round() as i128) - 1).clamp(0, 60) as usize
        } else {
            0
        };
        let stale = missing > 0 && diff > 10000;
        let output = unsafe { std::slice::from_raw_parts_mut(output, count) };
        let flags = unsafe { std::slice::from_raw_parts_mut(flags, count) };
        for (i, ((raw, out), flag)) in input.iter().zip(output).zip(flags).enumerate() {
            let history = &mut session.histories[i];
            if missing > 0 {
                history.truncate(60 - missing);
                let old = history.len();
                history.resize(old + missing, -1);
                history.copy_within(..old, missing);
                history[..missing].fill(-1);
            }
            let shindo = f64::from_bits(raw.level as u64);
            let valid = shindo.is_finite() && shindo > -3.0 && shindo <= 7.0;
            let level = if !valid {
                -1
            } else if shindo >= 6.5 {
                20
            } else {
                (shindo * 2.0 + 7.0).floor() as i64
            };
            let abnormal = session.shindo_abnormal[i];
            *out = update(
                history,
                &Input {
                    station: raw.station,
                    level,
                    expire: raw.expire,
                    time_ms,
                    flags: (if stale { raw.flags & !1 } else { raw.flags })
                        | if abnormal.is_some() { 2 } else { 0 },
                    abnormal: abnormal.unwrap_or(0),
                },
            );
            session.shindo_abnormal[i] = if out.length & (1 << 32) != 0 {
                Some(out.abnormal)
            } else {
                None
            };
            *flag = (valid as u8) | ((stale as u8) << 1);
        }
        session.shindo_time = Some(time_ms);
        CALLS.fetch_add(1, Ordering::Relaxed);
        0
    }))
    .unwrap_or(5)
}
/// Safety: exclusive live session. Does not discard observations or histories.
#[no_mangle]
pub unsafe extern "C" fn rq_ka_reset_shindo_clock(session: *mut Session) -> i32 {
    if session.is_null() {
        return 1;
    }
    unsafe { &mut *session }.shindo_time = None;
    0
}
/// Explicit state import/reset command; the previous native abnormal counter
/// no longer returns through a Dart view as the next frame's processing input.
/// Safety: exclusive live session. Index checked before mutation.
#[no_mangle]
pub unsafe extern "C" fn rq_ka_set_shindo_abnormal(
    session: *mut Session,
    station: usize,
    value: i64,
    present: u8,
) -> i32 {
    if session.is_null() || present > 1 {
        return 1;
    }
    let session = unsafe { &mut *session };
    let Some(state) = session.shindo_abnormal.get_mut(station) else {
        return 3;
    };
    *state = if present == 0 { None } else { Some(value) };
    0
}
/// Safety: exclusive live session, destroyed once; null is accepted.
#[no_mangle]
pub unsafe extern "C" fn rq_ka_destroy(session: *mut Session) {
    if !session.is_null() {
        drop(unsafe { Box::from_raw(session) });
        SESSIONS.fetch_sub(1, Ordering::Relaxed);
    }
}
/// Safety: exclusive session, aligned nonoverlapping count-element arrays.
#[no_mangle]
pub unsafe extern "C" fn rq_ka_process(
    session: *mut Session,
    input: *const Input,
    count: usize,
    output: *mut Output,
) -> i32 {
    if session.is_null() || (count > 0 && (input.is_null() || output.is_null())) {
        return 1;
    }
    if count > LIMIT {
        return 3;
    }
    if count == 0 {
        return 0;
    }
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let session = unsafe { &mut *session };
        let inputs = unsafe { std::slice::from_raw_parts(input, count) };
        if inputs
            .iter()
            .any(|row| row.station >= session.histories.len() as u64)
        {
            return 3;
        }
        let outputs = unsafe { std::slice::from_raw_parts_mut(output, count) };
        CALLS.fetch_add(1, Ordering::Relaxed);
        for (row, out) in inputs.iter().zip(outputs) {
            *out = update(&mut session.histories[row.station as usize], row);
        }
        0
    }))
    .unwrap_or(5)
}
/// Safety: live session; aligned output capacity. Copies original order.
#[no_mangle]
pub unsafe extern "C" fn rq_ka_copy_history(
    session: *const Session,
    station: usize,
    output: *mut i64,
    capacity: usize,
) -> i32 {
    if session.is_null() {
        return 1;
    }
    let session = unsafe { &*session };
    let Some(history) = session.histories.get(station) else {
        return 3;
    };
    if history.len() > capacity {
        return 3;
    }
    if history.is_empty() {
        return 0;
    }
    if output.is_null() {
        return 1;
    }
    unsafe {
        std::ptr::copy_nonoverlapping(history.as_ptr(), output, history.len());
    }
    0
}
/// Safety: live session and aligned count*60-element output, no aliasing.
/// Read-only frame copy; reject imported long histories before writing anything.
#[no_mangle]
pub unsafe extern "C" fn rq_ka_copy_histories(
    session: *const Session,
    output: *mut i64,
    count: usize,
) -> i32 {
    if session.is_null() {
        return 1;
    }
    let session = unsafe { &*session };
    if count != session.histories.len() || session.histories.iter().any(|h| h.len() > 60) {
        return 3;
    }
    if count == 0 {
        return 0;
    }
    if output.is_null() {
        return 1;
    }
    unsafe {
        std::ptr::write_bytes(output, 0, count * 60);
    }
    for (index, history) in session.histories.iter().enumerate() {
        if !history.is_empty() {
            unsafe {
                std::ptr::copy_nonoverlapping(
                    history.as_ptr(),
                    output.add(index * 60),
                    history.len(),
                );
            }
        }
    }
    0
}
/// Safety: exclusive session; aligned length-element original history input.
#[no_mangle]
pub unsafe extern "C" fn rq_ka_replace_history(
    session: *mut Session,
    station: usize,
    input: *const i64,
    length: usize,
) -> i32 {
    if session.is_null() || (length > 0 && input.is_null()) {
        return 1;
    }
    if length > LIMIT {
        return 3;
    }
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let session = unsafe { &mut *session };
        let Some(history) = session.histories.get_mut(station) else {
            return 3;
        };
        if length == 0 {
            *history = Vec::new();
        } else {
            *history = unsafe { std::slice::from_raw_parts(input, length) }.to_vec();
        }
        0
    }))
    .unwrap_or(5)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn raw_array_rejection_is_atomic_and_gaps_keep_original_order() {
        unsafe {
            let p = rq_ka_create(2);
            let mut input = [
                Input {
                    station: 0,
                    level: 1.5f64.to_bits() as i64,
                    expire: 10,
                    time_ms: 0,
                    flags: 1,
                    abnormal: 0,
                },
                Input {
                    station: 1,
                    level: 3.5f64.to_bits() as i64,
                    expire: 10,
                    time_ms: 0,
                    flags: 0,
                    abnormal: 0,
                },
            ];
            let mut output = [Output::default(); 2];
            let mut flags = [0; 2];
            assert_eq!(
                rq_ka_process_shindo(
                    p,
                    input.as_ptr(),
                    2,
                    1000,
                    output.as_mut_ptr(),
                    flags.as_mut_ptr()
                ),
                0
            );
            assert_eq!((*p).histories, [vec![10], vec![14]]);
            input[1].station = 99;
            assert_eq!(
                rq_ka_process_shindo(
                    p,
                    input.as_ptr(),
                    2,
                    100000,
                    output.as_mut_ptr(),
                    flags.as_mut_ptr()
                ),
                3
            );
            assert_eq!((*p).shindo_time, Some(1000));
            assert_eq!((*p).histories, [vec![10], vec![14]]);
            input[1].station = 1;
            assert_eq!(
                rq_ka_process_shindo(
                    p,
                    input.as_ptr(),
                    2,
                    3500,
                    output.as_mut_ptr(),
                    flags.as_mut_ptr()
                ),
                0
            );
            assert_eq!((*p).histories, [vec![10, -1, -1, 10], vec![14, -1, -1, 14]]);
            assert_eq!(flags, [1, 1]);
            assert_eq!(rq_ka_reset_shindo_clock(p), 0);
            assert_eq!(
                rq_ka_process_shindo(
                    p,
                    input.as_ptr(),
                    2,
                    100000,
                    output.as_mut_ptr(),
                    flags.as_mut_ptr()
                ),
                0
            );
            assert_eq!((&*p).histories[0], [10, 10, -1, -1, 10]);
            assert_eq!(
                rq_ka_process_shindo(
                    p,
                    input.as_ptr(),
                    2,
                    200000,
                    output.as_mut_ptr(),
                    flags.as_mut_ptr()
                ),
                0
            );
            assert_eq!(flags, [3, 3]);
            assert_eq!((&*p).histories[0].len(), 60);
            assert!((&*p).histories[0][1..].iter().all(|&v| v == -1));
            rq_ka_destroy(p);
        }
    }
    #[test]
    fn layout_and_errors() {
        assert_eq!(std::mem::size_of::<Input>(), 48);
        assert_eq!(std::mem::size_of::<Output>(), 48);
        assert!(rq_ka_create(LIMIT + 1).is_null());
        assert_eq!(
            unsafe {
                rq_ka_process(
                    std::ptr::null_mut(),
                    std::ptr::null(),
                    0,
                    std::ptr::null_mut(),
                )
            },
            1
        );
        let p = rq_ka_create(1);
        assert!(!p.is_null());
        assert_eq!(
            unsafe { rq_ka_copy_history(p, 1, std::ptr::null_mut(), 0) },
            3
        );
        unsafe {
            rq_ka_destroy(p);
        }
    }
}
