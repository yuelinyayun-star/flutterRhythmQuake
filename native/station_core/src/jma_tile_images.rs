//! Viewport-driven JMA image requests. HTTP, retry, concurrency and cancellation
//! stay native; successful encoded images are handed to Flutter's image codec.
use crate::http_transport as http;
use std::{
    collections::BTreeMap,
    ffi::CString,
    ptr,
    time::{Duration, Instant},
};
type Wake = unsafe extern "C" fn(i64, *mut http::DartObject) -> bool;
struct Request {
    id: u64,
    status: u32,
    body: Vec<u8>,
}
struct Job {
    path: String,
    attempt: u32,
    request: Option<Request>,
    retry: Option<Instant>,
}
#[derive(Default)]
pub struct Images {
    jobs: BTreeMap<u64, Job>,
    pub requests: u64,
    pub cancelled: u64,
    pub completed: u64,
}
impl Images {
    pub fn add(
        &mut self,
        token: u64,
        path: String,
        satellite: bool,
    ) -> Option<(u64, u32, Vec<u8>)> {
        let prefix = if satellite {
            "/bosai/himawari/data/satimg/"
        } else {
            "/bosai/jmatile/data/nowc/"
        };
        if !path.starts_with(prefix) || path.contains(['\0', '\r', '\n']) {
            return Some((token, 2, b"Invalid JMA image path".to_vec()));
        }
        self.jobs.insert(
            token,
            Job {
                path,
                attempt: 0,
                request: None,
                retry: None,
            },
        );
        None
    }
    pub fn cancel(&mut self, token: u64) -> Option<(u64, u32, Vec<u8>)> {
        let job = self.jobs.remove(&token)?;
        if let Some(r) = job.request {
            http::rq_http_release(r.id);
        }
        self.cancelled += 1;
        Some((token, 1, vec![]))
    }
    pub fn clear(&mut self) -> Vec<(u64, u32, Vec<u8>)> {
        self.jobs
            .keys()
            .copied()
            .collect::<Vec<_>>()
            .into_iter()
            .filter_map(|id| self.cancel(id))
            .collect()
    }
    pub fn drain(&mut self) -> Vec<(u64, u32, Vec<u8>)> {
        let mut results = vec![];
        let mut done = vec![];
        for (&token, job) in &mut self.jobs {
            let Some(r) = job.request.as_mut() else {
                continue;
            };
            let mut finish = None;
            loop {
                let (mut len, mut kind, mut code, mut owner) = (0, 0, 0, ptr::null_mut());
                let p =
                    unsafe { http::rq_http_take(r.id, &mut len, &mut kind, &mut code, &mut owner) };
                if p.is_null() {
                    break;
                }
                let bytes = unsafe { std::slice::from_raw_parts(p, len) };
                match kind {
                    1 => {
                        r.status = std::str::from_utf8(bytes)
                            .ok()
                            .and_then(|s| s.split_whitespace().nth(1))
                            .and_then(|s| s.parse().ok())
                            .unwrap_or(0)
                    }
                    2 => {
                        r.body.extend_from_slice(bytes);
                        if r.body.len() > 16 * 1024 * 1024 {
                            finish = Some((false, false, "JMA image exceeds 16 MiB".to_owned()));
                        }
                    }
                    3 => {
                        finish = Some((
                            r.status == 200,
                            matches!(r.status, 408 | 429 | 500 | 502 | 503 | 504),
                            format!("JMA image HTTP {}", r.status),
                        ))
                    }
                    4 => finish = Some((false, true, format!("JMA image network error {code}"))),
                    _ => {}
                }
                unsafe {
                    http::rq_http_chunk_release(owner);
                }
                if finish.is_some() {
                    break;
                }
            }
            if let Some((ok, retry, error)) = finish {
                let r = job.request.take().unwrap();
                http::rq_http_release(r.id);
                if ok {
                    done.push(token);
                    results.push((token, 0, r.body));
                    self.completed += 1;
                } else if retry && job.attempt <= 3 {
                    job.retry =
                        Some(Instant::now() + Duration::from_millis(500 * job.attempt as u64));
                } else {
                    done.push(token);
                    results.push((token, 2, error.into_bytes()));
                }
            }
        }
        for id in done {
            self.jobs.remove(&id);
        }
        results
    }
    pub fn start_ready(
        &mut self,
        client: u64,
        host: &str,
        port: u32,
        secure: bool,
        source: u64,
        wake: Wake,
    ) {
        let mut active = self.jobs.values().filter(|j| j.request.is_some()).count();
        let now = Instant::now();
        for job in self.jobs.values_mut() {
            if active >= 8 {
                break;
            }
            if job.request.is_some() || job.retry.is_some_and(|at| now < at) {
                continue;
            }
            let host = CString::new(host).unwrap();
            let path = CString::new(job.path.clone()).unwrap();
            let id = unsafe {
                http::rq_http_open(
                    client,
                    host.as_ptr().cast(),
                    path.as_ptr().cast(),
                    c"GET".as_ptr().cast(),
                    c"User-Agent: FlutterRhythmQuake/1.0\r\nAccept-Encoding: gzip\r\n"
                        .as_ptr()
                        .cast(),
                    ptr::null(),
                    0,
                    port,
                    4 | 8 | u32::from(secure),
                    source as i64,
                    wake,
                )
            };
            job.attempt += 1;
            job.retry = None;
            job.request = Some(Request {
                id,
                status: 0,
                body: vec![],
            });
            active += 1;
            self.requests += 1;
        }
    }
    pub fn deadline(&self) -> Option<Instant> {
        if self.jobs.values().filter(|j| j.request.is_some()).count() >= 8 {
            return None;
        }
        self.jobs.values().filter_map(|j| j.retry).min()
    }
    pub fn count(&self) -> usize {
        self.jobs.len()
    }
    pub fn active_count(&self) -> usize {
        self.jobs.values().filter(|j| j.request.is_some()).count()
    }
    pub fn retained_bytes(&self) -> usize {
        self.jobs
            .values()
            .filter_map(|j| j.request.as_ref())
            .map(|r| r.body.len())
            .sum()
    }
}
