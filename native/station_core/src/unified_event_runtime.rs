//! Ordered native actor. The Dart port carries prepared display/effect batches.
use crate::{station_json::pack_value, unified_event_state::Engine};
use serde_json::Value;
use std::{
    collections::VecDeque,
    ffi::c_void,
    ptr,
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc, Condvar, Mutex,
    },
    thread,
    time::{Duration, Instant},
};
static SESSIONS: AtomicU64 = AtomicU64::new(0);
static WORKERS: AtomicU64 = AtomicU64::new(0);
#[repr(C)]
struct DartObject {
    kind: i32,
    value: [i64; 5],
}
type Post = unsafe extern "C" fn(i64, *mut DartObject) -> bool;
struct State {
    engine: Engine,
    jobs: VecDeque<(Vec<u8>, i64)>,
    output: VecDeque<Vec<u8>>,
    closed: bool,
    ready: bool,
    deferred: VecDeque<(Value, i64)>,
    commands: u64,
    processing_us: u64,
    max_command_us: u64,
    deadline_wakes: u64,
}
impl State {
    fn execute(&mut self, c: &Value, clock: i64) -> Value {
        let start = Instant::now();
        let result = self.engine.execute(c, clock);
        let elapsed = start.elapsed().as_micros() as u64;
        self.commands += 1;
        self.processing_us += elapsed;
        self.max_command_us = self.max_command_us.max(elapsed);
        result
    }
}
struct Shared {
    state: Mutex<State>,
    wake: Condvar,
    start: Instant,
    port: i64,
    post: Option<Post>,
    manual: bool,
}
struct Owner {
    shared: Arc<Shared>,
    thread: Option<thread::JoinHandle<()>>,
    delivered: Vec<u8>,
}
fn notify(s: &Shared) {
    if let Some(post) = s.post {
        let mut o = DartObject {
            kind: 3,
            value: [1, 0, 0, 0, 0],
        };
        unsafe {
            post(s.port, &mut o);
        }
    }
}
fn push(s: &Shared, state: &mut State, value: Value) {
    let empty = state.output.is_empty();
    state.output.push_back(pack_value(&value));
    if empty {
        notify(s);
    }
}
fn run(s: Arc<Shared>) {
    WORKERS.fetch_add(1, Ordering::Relaxed);
    let mut state = s.state.lock().unwrap();
    loop {
        if state.closed {
            break;
        }
        if state.output.len() >= 128 {
            state = s.wake.wait(state).unwrap();
            continue;
        }
        if let Some((bytes, clock)) = state.jobs.pop_front() {
            let response = match serde_json::from_slice::<Value>(&bytes) {
                Ok(c) => {
                    let op = crate::unified_event_policy::s(&c, "op");
                    if !state.ready && matches!(op, "admit" | "replay") {
                        state.deferred.push_back((c, clock));
                        continue;
                    }
                    let response = state.execute(&c, clock);
                    if op == "ready" {
                        state.ready = true;
                        push(&s, &mut state, response);
                        while let Some((command, stamp)) = state.deferred.pop_front() {
                            let response = state.execute(&command, stamp);
                            push(&s, &mut state, response);
                        }
                        continue;
                    }
                    response
                }
                Err(e) => serde_json::json!({"error":e.to_string()}),
            };
            push(&s, &mut state, response);
            continue;
        }
        let clock = s.start.elapsed().as_micros() as i64;
        if state.engine.next_deadline().is_some_and(|v| v <= clock) {
            state.deadline_wakes += 1;
            state.engine.advance(clock);
            let response = state.engine.finish();
            push(&s, &mut state, response);
            continue;
        }
        if let Some(due) = state.engine.next_deadline() {
            let duration = Duration::from_micros((due - clock).max(1) as u64);
            state = s.wake.wait_timeout(state, duration).unwrap().0;
        } else {
            state = s.wake.wait(state).unwrap();
        }
    }
    WORKERS.fetch_sub(1, Ordering::Relaxed);
}
#[no_mangle]
pub unsafe extern "C" fn rq_unified_event_create(
    port: i64,
    post: *const c_void,
    manual: u8,
) -> *mut c_void {
    std::panic::catch_unwind(|| {
        let shared = Arc::new(Shared {
            state: Mutex::new(State {
                engine: Engine::default(),
                jobs: VecDeque::new(),
                output: VecDeque::new(),
                closed: false,
                ready: manual != 0,
                deferred: VecDeque::new(),
                commands: 0,
                processing_us: 0,
                max_command_us: 0,
                deadline_wakes: 0,
            }),
            wake: Condvar::new(),
            start: Instant::now(),
            port,
            post: if post.is_null() {
                None
            } else {
                Some(unsafe { std::mem::transmute::<*const c_void, Post>(post) })
            },
            manual: manual != 0,
        });
        let worker = if manual != 0 {
            None
        } else {
            let s = shared.clone();
            match thread::Builder::new()
                .name("rq-unified-events".into())
                .stack_size(512 * 1024)
                .spawn(move || run(s))
            {
                Ok(v) => Some(v),
                Err(_) => return ptr::null_mut(),
            }
        };
        SESSIONS.fetch_add(1, Ordering::Relaxed);
        Box::into_raw(Box::new(Owner {
            shared,
            thread: worker,
            delivered: vec![],
        }))
        .cast()
    })
    .unwrap_or(ptr::null_mut())
}
#[no_mangle]
pub unsafe extern "C" fn rq_unified_event_send(
    owner: *mut c_void,
    bytes: *const u8,
    len: usize,
    clock: i64,
) -> i32 {
    if owner.is_null() || bytes.is_null() || len > 16 * 1024 * 1024 {
        return 1;
    }
    let owner = unsafe { &*owner.cast::<Owner>() };
    let shared = &owner.shared;
    let mut state = shared.state.lock().unwrap();
    if state.closed {
        return 2;
    }
    if state.jobs.len() + state.deferred.len() >= 256 {
        return 3;
    }
    let bytes = unsafe { std::slice::from_raw_parts(bytes, len) };
    if shared.manual {
        let Ok(c) = serde_json::from_slice::<Value>(bytes) else {
            return 4;
        };
        let response = state.execute(&c, clock);
        push(shared, &mut state, response);
    } else {
        state
            .jobs
            .push_back((bytes.to_vec(), shared.start.elapsed().as_micros() as i64));
        shared.wake.notify_one();
    }
    0
}
#[no_mangle]
pub unsafe extern "C" fn rq_unified_event_query(
    owner: *mut c_void,
    bytes: *const u8,
    len: usize,
    size: *mut usize,
) -> *const u8 {
    if owner.is_null() || bytes.is_null() || size.is_null() || len > 16 * 1024 * 1024 {
        return ptr::null();
    }
    let owner = unsafe { &mut *owner.cast::<Owner>() };
    let Ok(c) = serde_json::from_slice::<Value>(unsafe { std::slice::from_raw_parts(bytes, len) })
    else {
        return ptr::null();
    };
    let mut state = owner.shared.state.lock().unwrap();
    let response = if crate::unified_event_policy::s(&c, "op") == "runtimeStats" {
        serde_json::json!({"commands":state.commands,"processingUs":state.processing_us,"maxCommandUs":state.max_command_us,"deadlineWakes":state.deadline_wakes,"queued":state.jobs.len(),"deferred":state.deferred.len(),"outstanding":state.output.len()})
    } else {
        state.engine.query(&c)
    };
    owner.delivered = pack_value(&response);
    unsafe {
        *size = owner.delivered.len();
    }
    owner.delivered.as_ptr()
}
#[no_mangle]
pub unsafe extern "C" fn rq_unified_event_take(owner: *mut c_void, size: *mut usize) -> *const u8 {
    if owner.is_null() || size.is_null() {
        return ptr::null();
    }
    let owner = unsafe { &mut *owner.cast::<Owner>() };
    let Some(bytes) = owner.shared.state.lock().unwrap().output.pop_front() else {
        unsafe {
            *size = 0;
        }
        return ptr::null();
    };
    owner.delivered = bytes;
    unsafe {
        *size = owner.delivered.len();
    }
    owner.shared.wake.notify_one();
    owner.delivered.as_ptr()
}
#[no_mangle]
pub unsafe extern "C" fn rq_unified_event_destroy(owner: *mut c_void) {
    if owner.is_null() {
        return;
    }
    let mut owner = unsafe { Box::from_raw(owner.cast::<Owner>()) };
    owner.shared.state.lock().unwrap().closed = true;
    owner.shared.wake.notify_one();
    if let Some(thread) = owner.thread.take() {
        let _ = thread.join();
    }
    SESSIONS.fetch_sub(1, Ordering::Relaxed);
}
#[no_mangle]
pub extern "C" fn rq_unified_event_sessions() -> u64 {
    SESSIONS.load(Ordering::Relaxed)
}
#[no_mangle]
pub extern "C" fn rq_unified_event_workers() -> u64 {
    WORKERS.load(Ordering::Relaxed)
}
