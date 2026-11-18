//! Direct PEWS polling for the station actor. Both EEW and station consumers
//! share this actor through the Dart ownership bridge.
use super::*;
use base64::{engine::general_purpose::STANDARD, Engine as _};

fn html_content_type(headers: &str) -> bool {
    headers.lines().any(|line| {
        let Some((name, value)) = line.split_once(':') else {
            return false;
        };
        if !name.eq_ignore_ascii_case("Content-Type") {
            return false;
        }
        let media_type = value.split(';').next().unwrap_or_default().trim();
        media_type.eq_ignore_ascii_case("text/html")
            || media_type.eq_ignore_ascii_case("application/xhtml+xml")
    })
}

fn html_body(bytes: &[u8]) -> bool {
    let prefix = &bytes[..bytes.len().min(256)];
    let prefix = prefix
        .strip_prefix(b"\xef\xbb\xbf")
        .unwrap_or(prefix)
        .trim_ascii_start();
    [
        b"<!doctype html".as_slice(),
        b"<html",
        b"<br>",
        b"<br/>",
        b"<br />",
    ]
    .iter()
    .any(|signature| {
        prefix
            .get(..signature.len())
            .is_some_and(|head| head.eq_ignore_ascii_case(signature))
    })
}

#[derive(Default)]
pub(super) struct Pews {
    clock: Option<(i64, Instant)>,
    attempted: i64,
    candidate: i64,
    retries: u8,
    pending: Option<Vec<u8>>,
    last_table: Vec<u8>,
    detail_pending: Option<(Vec<u8>, i64)>,
    detail_key: Option<(String, u8)>,
    detail_attempts: u8,
}

impl Runtime {
    fn pews_request(&mut self, role: &'static str, t: i64) {
        if self
            .requests
            .iter()
            .any(|r| r.role == role || (role != "pews_detail" && r.role != "pews_detail"))
        {
            return;
        }
        let stamp = iso(self.pews.candidate * 1000)
            .chars()
            .filter(|c| c.is_ascii_digit())
            .take(14)
            .collect::<String>();
        let path = match role {
            "pews_clock" => "/pews/".to_string(),
            "pews_frame" => format!("/pews/data/{stamp}.b"),
            "pews_table" => format!("/pews/data/{stamp}.s"),
            "pews_detail" => {
                let Some((bytes, _)) = &self.pews.detail_pending else {
                    return;
                };
                let Some((phase, id, _)) = crate::kma_pews::header(bytes) else {
                    return;
                };
                format!("/pews/data/{id}.{}", if phase == 2 { "le" } else { "li" })
            }
            _ => return,
        };
        let endpoint = &self.settings["endpoint"];
        let host = CString::new(endpoint["host"].as_str().unwrap_or("www.weather.go.kr")).unwrap();
        let path = CString::new(path).unwrap();
        let headers = c"Accept: application/octet-stream,*/*;q=0.8\r\nReferer: https://www.weather.go.kr/pews/\r\nCache-Control: no-cache\r\n";
        let secure = endpoint["secure"] != false;
        let id = unsafe {
            crate::http_transport::rq_http_open(
                self.http,
                host.as_ptr().cast(),
                path.as_ptr().cast(),
                c"GET".as_ptr().cast(),
                headers.as_ptr().cast(),
                ptr::null(),
                0,
                endpoint["port"]
                    .as_u64()
                    .unwrap_or(if secure { 443 } else { 80 }) as u32,
                u32::from(secure) | 8,
                self.id as i64,
                std::mem::transmute::<
                    unsafe extern "C" fn(i64, *mut c_void) -> bool,
                    unsafe extern "C" fn(i64, *mut crate::http_transport::DartObject) -> bool,
                >(wake),
            )
        };
        self.requests.push(Request {
            id,
            role,
            bytes: vec![],
            started: t,
            status: 0,
            is_html: false,
            sse: false,
            trem_stream: trem_protocol::Stream::default(),
        });
    }

    fn pews_headers(&mut self, headers: &str, started: i64, t: i64) {
        let st = headers.lines().find_map(|line| {
            let (name, value) = line.split_once(':')?;
            name.eq_ignore_ascii_case("ST")
                .then(|| value.trim().parse::<f64>().ok())
                .flatten()
        });
        if let Some(seconds) = st.filter(|v| (1_500_000_000.0..4_000_000_000.0).contains(v)) {
            self.pews.clock = Some((
                (seconds * 1000.0) as i64 + (t - started).max(0) / 2,
                Instant::now(),
            ));
        }
    }

    fn pews_stations(&mut self, bytes: &[u8], t: i64) -> bool {
        if bytes == self.pews.last_table {
            return !self.engine.kma.is_empty();
        }
        let Some(rows) = crate::kma_pews::stations(bytes) else {
            return false;
        };
        self.engine
            .kma_input(&json!({"type":"kma_stations_update","stations":rows}), t);
        self.pews.last_table = bytes.to_vec();
        self.engine.original["metadataOriginalBase64"] = json!(STANDARD.encode(bytes));
        true
    }

    fn pews_frame(&mut self, bytes: &[u8], t: i64) -> bool {
        let Some((phase, id, changed)) = crate::kma_pews::header(bytes) else {
            return false;
        };
        let tail_len = if matches!(phase, 2 | 3) { 75 } else { 0 };
        if bytes.len() <= 4 + tail_len {
            return false;
        }
        self.engine
            .pews_event(bytes, self.pews.candidate * 1000, t, false, None);
        if matches!(phase, 2 | 3)
            && self
                .engine
                .pews_latest
                .as_ref()
                .is_some_and(|(stamp, _, _, _)| *stamp == self.pews.candidate * 1000)
        {
            let key = (id.clone(), phase);
            if self.pews.detail_key.as_ref() != Some(&key) {
                self.pews.detail_key = Some(key);
                self.pews.detail_attempts = 0;
            }
            let has_detail = self
                .engine
                .pews_detail
                .as_ref()
                .is_some_and(|(event, p, _, _)| *event == id && *p == phase);
            if !has_detail
                && self.pews.detail_attempts < 3
                && !self.requests.iter().any(|r| r.role == "pews_detail")
            {
                self.pews.detail_attempts += 1;
                self.pews.detail_pending = Some((bytes.to_vec(), self.pews.candidate * 1000));
                self.pews_request("pews_detail", t);
            }
        }
        if self.settings["pewsStations"] == false {
            return true;
        }
        let capacity = (bytes.len() - 4 - tail_len) * 2;
        if self.engine.kma.is_empty() || changed || self.engine.kma.len() > capacity {
            self.pews.pending = Some(bytes.to_vec());
            self.pews_request("pews_table", t);
            return true;
        }
        self.pews_levels(bytes, t)
    }

    fn pews_levels(&mut self, bytes: &[u8], t: i64) -> bool {
        let Some((phase, _, _)) = crate::kma_pews::header(bytes) else {
            return false;
        };
        let capacity = (bytes
            .len()
            .saturating_sub(4)
            .saturating_sub(if matches!(phase, 2 | 3) { 75 } else { 0 }))
            * 2;
        if self.engine.kma.is_empty() || self.engine.kma.len() > capacity {
            return false;
        }
        let mmi = (0..self.engine.kma.len())
            .map(|i| {
                let byte = bytes[4 + i / 2];
                match if i % 2 == 0 { byte >> 4 } else { byte & 15 } {
                    0 => -3,
                    1 => -2,
                    value @ 12..=15 => value as i32 - 13,
                    value => value as i32,
                }
            })
            .collect::<Vec<_>>();
        let stamp = iso(self.pews.candidate * 1000);
        let accepted = self.engine.kma_input(
            &json!({"type":"update", "Data":{"timestamp":stamp,"mmi":mmi}}),
            t,
        );
        if accepted {
            self.engine.original["dataOriginalBase64"] = json!(STANDARD.encode(bytes));
        }
        accepted
    }

    pub(super) fn pews_station_settings(&mut self, enabled: bool) {
        if self.settings["pewsStations"].as_bool() == Some(enabled) {
            return;
        }
        self.settings["pewsStations"] = json!(enabled);
        self.pews.pending = None;
        self.pews.last_table.clear();
        if !enabled {
            self.engine.kma.clear();
            self.engine.adj.clear();
            self.engine.grids.clear();
            self.engine.grid_decimal = None;
            self.engine.last = None;
            self.engine.received = None;
            self.engine.previous = -1;
            self.engine.original = json!({});
            self.engine.changed = true;
        }
    }

    pub(super) fn pews_tick(&mut self, t: i64) {
        // The binary/table sequence shares one timestamp. Location enrichment
        // has a separate request so it cannot stall the next warning frame.
        let mut completed = vec![];
        let mut headers = vec![];
        for request in &mut self.requests {
            let mut done = None;
            loop {
                let (mut len, mut kind, mut code, mut owner) = (0, 0, 0, ptr::null_mut());
                let pointer = unsafe {
                    crate::http_transport::rq_http_take(
                        request.id, &mut len, &mut kind, &mut code, &mut owner,
                    )
                };
                if pointer.is_null() {
                    break;
                }
                let bytes = unsafe { std::slice::from_raw_parts(pointer, len) }.to_vec();
                unsafe {
                    crate::http_transport::rq_http_chunk_release(owner);
                }
                match kind {
                    1 => {
                        let text = String::from_utf8_lossy(&bytes).into_owned();
                        request.status = text
                            .split_whitespace()
                            .nth(1)
                            .and_then(|v| v.parse().ok())
                            .unwrap_or(0);
                        request.is_html = html_content_type(&text);
                        headers.push((text, request.started));
                    }
                    2 => {
                        if request.role == "pews_clock" || request.is_html {
                            continue;
                        }
                        request.bytes.extend(bytes);
                        if request.bytes.len() > 256 * 1024 {
                            done = Some(false);
                            break;
                        }
                    }
                    3 => {
                        done = Some(true);
                        break;
                    }
                    4 => {
                        done = Some(false);
                        break;
                    }
                    _ => {}
                }
            }
            if t - request.started > 8000 {
                done = Some(false);
            }
            if let Some(ok) = done {
                completed.push((request.id, ok));
            }
        }
        for (headers, started) in headers {
            self.pews_headers(&headers, started, t);
        }
        for (id, ok) in completed {
            let index = self.requests.iter().position(|r| r.id == id).unwrap();
            let request = self.requests.remove(index);
            crate::http_transport::rq_http_release(request.id);
            let html = request.is_html || html_body(&request.bytes);
            if request.role == "pews_detail" {
                if let Some((bytes, stamp)) = self.pews.detail_pending.take() {
                    if ok && request.status == 200 && !html {
                        // Enrich the newest identical phase, preserving its
                        // timestamp when newer station frames already arrived.
                        let current = self
                            .engine
                            .pews_latest
                            .as_ref()
                            .filter(|(_, phase, frame, _)| {
                                *phase == crate::kma_pews::header(&bytes).unwrap().0
                                    && crate::kma_pews::header(frame).unwrap().1
                                        == crate::kma_pews::header(&bytes).unwrap().1
                            })
                            .map(|v| (v.0, v.2.clone()))
                            .unwrap_or((stamp, bytes));
                        self.engine.pews_event(
                            &current.1,
                            current.0,
                            t,
                            false,
                            Some(&request.bytes),
                        );
                    }
                }
                continue;
            }
            let accepted = if ok && request.status == 200 && (request.role == "pews_clock" || !html)
            {
                match request.role {
                    "pews_clock" => self.pews.clock.is_some(),
                    "pews_frame" => self.pews_frame(&request.bytes, t),
                    "pews_table" => {
                        if self.settings["pewsStations"] == false {
                            true
                        } else if self.pews_stations(&request.bytes, t) {
                            self.pews
                                .pending
                                .take()
                                .is_some_and(|bytes| self.pews_levels(&bytes, t))
                        } else {
                            false
                        }
                    }
                    _ => false,
                }
            } else {
                false
            };
            if ok && request.status == 404 && request.role == "pews_frame" && self.pews.retries < 3
            {
                self.pews.retries += 1;
                self.pews.candidate -= 1;
                self.pews_request("pews_frame", t);
            } else if accepted {
                self.failures = 0;
                if request.role != "pews_clock" {
                    self.engine.status("connected");
                }
            } else {
                self.failures += 1;
                self.engine.status("error");
                self.poll_at = t + 2000;
                self.pews.pending = None;
                if self.failures >= 3 {
                    self.pews.clock = None;
                }
            }
        }
        if self.requests.iter().any(|r| r.role != "pews_detail") || t < self.poll_at {
            return;
        }
        let Some((epoch, anchor)) = self.pews.clock else {
            self.pews_request("pews_clock", t);
            return;
        };
        let candidate = (epoch + anchor.elapsed().as_millis() as i64) / 1000 - 1;
        if candidate <= self.pews.attempted {
            return;
        }
        self.pews.attempted = candidate;
        self.pews.candidate = candidate;
        self.pews.retries = 0;
        self.pews_request("pews_frame", t);
    }
}
