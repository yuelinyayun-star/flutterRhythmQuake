//! Explicit, temporary performance diagnostics. No remote shell or file reader.
use serde_json::{json, Value};
use std::{
    collections::VecDeque,
    fs::{self},
    io::{self, BufWriter, Read, Write},
    net::{SocketAddr, TcpListener, TcpStream},
    path::PathBuf,
    time::{Duration, Instant},
};

#[cfg(windows)]
mod win {
    use super::*;
    use std::{ffi::c_void, mem::size_of};
    type Handle = *mut c_void;
    #[repr(C)]
    #[derive(Default, Copy, Clone)]
    struct FileTime {
        low: u32,
        high: u32,
    }
    impl FileTime {
        fn ticks(self) -> u64 {
            (u64::from(self.high) << 32) | u64::from(self.low)
        }
    }
    #[repr(C)]
    #[derive(Default)]
    struct Memory {
        size: u32,
        faults: u32,
        peak_rss: usize,
        rss: usize,
        peak_paged: usize,
        paged: usize,
        peak_nonpaged: usize,
        nonpaged: usize,
        pagefile: usize,
        peak_pagefile: usize,
        private: usize,
    }
    #[repr(C)]
    #[derive(Default)]
    struct Io {
        reads: u64,
        writes: u64,
        other: u64,
        read_bytes: u64,
        write_bytes: u64,
        other_bytes: u64,
    }
    #[link(name = "kernel32")]
    extern "system" {
        fn OpenProcess(access: u32, inherit: i32, id: u32) -> Handle;
        fn CloseHandle(handle: Handle) -> i32;
        fn GetProcessTimes(
            h: Handle,
            created: *mut FileTime,
            exited: *mut FileTime,
            kernel: *mut FileTime,
            user: *mut FileTime,
        ) -> i32;
        fn K32GetProcessMemoryInfo(h: Handle, output: *mut Memory, size: u32) -> i32;
        fn GetProcessHandleCount(h: Handle, count: *mut u32) -> i32;
        fn GetProcessIoCounters(h: Handle, counters: *mut Io) -> i32;
        fn QueryFullProcessImageNameW(
            h: Handle,
            flags: u32,
            name: *mut u16,
            length: *mut u32,
        ) -> i32;
        fn GetSystemTimePreciseAsFileTime(time: *mut FileTime);
        fn WaitForSingleObject(handle: Handle, millis: u32) -> u32;
    }
    #[link(name = "bcrypt")]
    extern "system" {
        fn BCryptGenRandom(provider: Handle, output: *mut u8, length: u32, flags: u32) -> i32;
    }
    pub fn token() -> io::Result<String> {
        let mut bytes = [0u8; 32];
        if unsafe { BCryptGenRandom(std::ptr::null_mut(), bytes.as_mut_ptr(), 32, 2) } != 0 {
            return Err(io::Error::other("Windows secure random failed"));
        }
        Ok(bytes.iter().map(|b| format!("{b:02x}")).collect())
    }
    pub struct Process {
        handle: Handle,
        pub pid: u32,
        pub path: String,
    }
    impl Drop for Process {
        fn drop(&mut self) {
            unsafe {
                CloseHandle(self.handle);
            }
        }
    }
    impl Process {
        pub fn open(pid: u32) -> io::Result<Self> {
            let handle = unsafe { OpenProcess(0x1000 | 0x10 | 0x100000, 0, pid) };
            if handle.is_null() {
                return Err(io::Error::last_os_error());
            }
            let mut owner = Self {
                handle,
                pid,
                path: String::new(),
            };
            let mut buffer = vec![0u16; 32768];
            let mut length = buffer.len() as u32;
            if unsafe { QueryFullProcessImageNameW(handle, 0, buffer.as_mut_ptr(), &mut length) }
                == 0
            {
                return Err(io::Error::last_os_error());
            }
            owner.path = String::from_utf16_lossy(&buffer[..length as usize]);
            Ok(owner)
        }
        pub fn exited(&self) -> bool {
            unsafe { WaitForSingleObject(self.handle, 0) == 0 }
        }
        pub fn sample(&self) -> io::Result<Value> {
            let mut memory = Memory {
                size: size_of::<Memory>() as u32,
                ..Default::default()
            };
            let (mut created, mut exited, mut kernel, mut user, mut now) = (
                FileTime::default(),
                FileTime::default(),
                FileTime::default(),
                FileTime::default(),
                FileTime::default(),
            );
            let mut handles = 0;
            let mut counters = Io::default();
            if unsafe {
                K32GetProcessMemoryInfo(self.handle, &mut memory, size_of::<Memory>() as u32)
            } == 0
                || unsafe {
                    GetProcessTimes(
                        self.handle,
                        &mut created,
                        &mut exited,
                        &mut kernel,
                        &mut user,
                    )
                } == 0
            {
                return Err(io::Error::last_os_error());
            }
            unsafe {
                GetSystemTimePreciseAsFileTime(&mut now);
            }
            let handle_ok = unsafe { GetProcessHandleCount(self.handle, &mut handles) } != 0;
            let io_ok = unsafe { GetProcessIoCounters(self.handle, &mut counters) } != 0;
            Ok(
                json!({"pid":self.pid,"utcUnixMs":now.ticks().saturating_sub(116444736000000000)/10000,
                "processCreated100ns":created.ticks(),"kernel100ns":kernel.ticks(),"user100ns":user.ticks(),
                "rssBytes":memory.rss,"peakRssBytes":memory.peak_rss,"privateBytes":memory.private,
                "pageFaults":memory.faults,"handles":if handle_ok{Some(handles)}else{None},
                "io":if io_ok{Some(json!({"readOperations":counters.reads,"writeOperations":counters.writes,
                    "readBytes":counters.read_bytes,"writeBytes":counters.write_bytes}))}else{None}}),
            )
        }
    }
}

struct Request {
    method: String,
    target: String,
    authorization: String,
    body: Vec<u8>,
}
fn read_request(stream: &mut TcpStream, token: &str) -> io::Result<Request> {
    stream.set_read_timeout(Some(Duration::from_millis(500)))?;
    stream.set_write_timeout(Some(Duration::from_secs(2)))?;
    let mut header = Vec::new();
    let mut byte = [0u8; 1];
    while !header.ends_with(b"\r\n\r\n") {
        if header.len() >= 8192 {
            return Err(io::Error::other("HTTP header too large"));
        }
        stream.read_exact(&mut byte)?;
        header.push(byte[0]);
    }
    let text = std::str::from_utf8(&header).map_err(io::Error::other)?;
    let mut lines = text.split("\r\n");
    let mut start = lines.next().unwrap_or("").split_whitespace();
    let method = start.next().unwrap_or("").to_owned();
    let target = start.next().unwrap_or("").to_owned();
    let mut authorization = String::new();
    let mut length = 0usize;
    for line in lines {
        if let Some((key, value)) = line.split_once(':') {
            match key.to_ascii_lowercase().as_str() {
                "authorization" => authorization = value.trim().into(),
                "content-length" => length = value.trim().parse().map_err(io::Error::other)?,
                "transfer-encoding" => {
                    return Err(io::Error::other("Chunked requests are unsupported"))
                }
                _ => {}
            }
        }
    }
    if length > 8 * 1024 * 1024 {
        return Err(io::Error::other("Request body too large"));
    }
    let mut body = if authorized(&authorization, token) {
        vec![0; length]
    } else {
        Vec::new()
    };
    stream.read_exact(&mut body)?;
    Ok(Request {
        method,
        target,
        authorization,
        body,
    })
}
fn authorized(actual: &str, token: &str) -> bool {
    let expected = format!("Bearer {token}");
    actual.len() == expected.len()
        && actual
            .bytes()
            .zip(expected.bytes())
            .fold(0u8, |n, (a, b)| n | (a ^ b))
            == 0
}
fn respond(stream: &mut TcpStream, status: u16, body: &Value) -> io::Result<()> {
    let bytes = serde_json::to_vec(body)?;
    write!(stream,"HTTP/1.1 {status} Result\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n",bytes.len())?;
    stream.write_all(&bytes)
}
fn decode_http(bytes: &[u8]) -> io::Result<Value> {
    let end = bytes
        .windows(4)
        .position(|w| w == b"\r\n\r\n")
        .ok_or_else(|| io::Error::other("Invalid APP HTTP response"))?;
    let header = String::from_utf8_lossy(&bytes[..end]);
    if !header.lines().next().unwrap_or("").contains(" 200 ") {
        return Err(io::Error::other(
            "APP endpoint unavailable (update APP and enable local debug API)",
        ));
    }
    let body = &bytes[end + 4..];
    if !header.to_lowercase().contains("transfer-encoding: chunked") {
        return serde_json::from_slice(body).map_err(io::Error::other);
    }
    let mut remaining = body;
    let mut decoded = Vec::new();
    loop {
        let e = remaining
            .windows(2)
            .position(|w| w == b"\r\n")
            .ok_or_else(|| io::Error::other("Invalid HTTP chunk"))?;
        let n = usize::from_str_radix(
            std::str::from_utf8(&remaining[..e])
                .map_err(io::Error::other)?
                .split(';')
                .next()
                .unwrap_or(""),
            16,
        )
        .map_err(io::Error::other)?;
        remaining = &remaining[e + 2..];
        if n == 0 {
            break;
        }
        if n > remaining.len().saturating_sub(2) {
            return Err(io::Error::other("Truncated HTTP chunk"));
        }
        decoded.extend_from_slice(&remaining[..n]);
        remaining = &remaining[n + 2..];
    }
    serde_json::from_slice(&decoded).map_err(io::Error::other)
}
fn app_request(port: u16, method: &str, path: &str, body: &[u8]) -> io::Result<Value> {
    let address = SocketAddr::from(([127, 0, 0, 1], port));
    let mut stream = TcpStream::connect_timeout(&address, Duration::from_millis(300))?;
    stream.set_read_timeout(Some(Duration::from_millis(500)))?;
    stream.set_write_timeout(Some(Duration::from_millis(500)))?;
    write!(stream,"{method} {path} HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",body.len())?;
    stream.write_all(body)?;
    let mut bytes = Vec::new();
    Read::take(&mut stream, 1024 * 1024).read_to_end(&mut bytes)?;
    decode_http(&bytes)
}
fn injection_path(target: &str) -> Option<String> {
    if target == "/app/inject" {
        return Some("/inject".into());
    }
    let format = target.strip_prefix("/app/inject?format=")?;
    if format.is_empty()
        || format.len() > 32
        || !format
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"_-".contains(&b))
    {
        return None;
    }
    Some(format!("/inject?format={format}"))
}
fn argument(args: &[String], name: &str) -> Option<String> {
    args.windows(2).find(|v| v[0] == name).map(|v| v[1].clone())
}
#[cfg(windows)]
fn run() -> io::Result<()> {
    let args = std::env::args().collect::<Vec<_>>();
    let pid = argument(&args, "--pid")
        .ok_or_else(|| io::Error::other("--pid is required"))?
        .parse::<u32>()
        .map_err(io::Error::other)?;
    let port = argument(&args, "--port")
        .unwrap_or_else(|| "18769".into())
        .parse::<u16>()
        .map_err(io::Error::other)?;
    let app_port = argument(&args, "--app-port")
        .unwrap_or_else(|| "8765".into())
        .parse::<u16>()
        .map_err(io::Error::other)?;
    let output = PathBuf::from(
        argument(&args, "--output").ok_or_else(|| io::Error::other("--output is required"))?,
    );
    let duration = argument(&args, "--duration-seconds")
        .unwrap_or_else(|| "3600".into())
        .parse::<u64>()
        .map_err(io::Error::other)?;
    if !(30..=86400).contains(&duration) {
        return Err(io::Error::other("Duration must be 30..86400 seconds"));
    }
    let target = win::Process::open(pid)?;
    if !target
        .path
        .to_lowercase()
        .ends_with("\\flutterrhythmquake.exe")
    {
        return Err(io::Error::other("Target must be flutterrhythmquake.exe"));
    }
    fs::create_dir_all(&output)?;
    let own = win::Process::open(std::process::id())?;
    let token = win::token()?;
    let listener = TcpListener::bind(SocketAddr::from(([127, 0, 0, 1], port)))?;
    listener.set_nonblocking(true)?;
    let port = listener.local_addr()?.port();
    let create_new = |path: PathBuf| {
        fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(path)
    };
    create_new(output.join("connection.json"))?.write_all(&serde_json::to_vec_pretty(&json!({"url":format!("http://127.0.0.1:{port}"),"token":token,"agentPid":std::process::id(),"targetPid":pid}))?)?;
    let cores = std::thread::available_parallelism()?.get();
    let metadata = json!({"version":env!("CARGO_PKG_VERSION"),"targetPid":pid,"targetPath":target.path,
        "logicalProcessors":cores,"sampleIntervalMs":1000,"sampleRingLimit":120,"appPort":app_port});
    create_new(output.join("metadata.json"))?.write_all(&serde_json::to_vec_pretty(&metadata)?)?;
    let mut writer = BufWriter::new(create_new(output.join("samples.jsonl"))?);
    let mut ring = VecDeque::<Value>::with_capacity(120);
    let started = Instant::now();
    let mut next_sample = Instant::now();
    let mut next_app = Instant::now();
    let mut seq = 0u64;
    let mut previous: Option<(u64, Instant)> = None;
    let mut app = Value::Null;
    let mut stop = false;
    let mut scenario = "initial".to_owned();
    let mut agent_cpu_start = None;
    println!(
        "Performance agent ready. Connection details: {}",
        output.join("connection.json").display()
    );
    while !stop && started.elapsed().as_secs() < duration {
        if Instant::now() >= next_app && !target.exited() {
            app = app_request(app_port, "GET", "/diagnostics/performance", &[])
                .unwrap_or_else(|e| json!({"unavailable":true,"error":e.to_string()}));
            next_app = Instant::now() + Duration::from_secs(5);
        }
        if Instant::now() >= next_sample {
            let now = Instant::now();
            next_sample = now + Duration::from_secs(1);
            if !target.exited() {
                let mut sample = target.sample()?;
                seq += 1;
                let total =
                    sample["kernel100ns"].as_u64().unwrap() + sample["user100ns"].as_u64().unwrap();
                sample["seq"] = json!(seq);
                sample["elapsedMs"] = json!(started.elapsed().as_millis());
                sample["scenario"] = json!(scenario);
                if let Some((before, time)) = previous {
                    let cpu = 100.0 * total.saturating_sub(before) as f64
                        / (now.duration_since(time).as_secs_f64() * 10_000_000.0);
                    sample["cpuPercentOneCore"] = json!(cpu);
                    sample["cpuPercentMachine"] = json!(cpu / cores as f64);
                }
                previous = Some((total, now));
                sample["appDiagnostics"] = app.clone();
                let own_stats = own.sample()?;
                let own_cpu = own_stats["kernel100ns"].as_u64().unwrap()
                    + own_stats["user100ns"].as_u64().unwrap();
                let first = *agent_cpu_start.get_or_insert(own_cpu);
                sample["agentOverhead"] = json!({"rssBytes":own_stats["rssBytes"],"privateBytes":own_stats["privateBytes"],
                    "cpu100nsSinceStart":own_cpu.saturating_sub(first)});
                serde_json::to_writer(&mut writer, &sample)?;
                writer.write_all(b"\n")?;
                writer.flush()?;
                if ring.len() == 120 {
                    ring.pop_front();
                }
                ring.push_back(sample);
            }
        }
        match listener.accept() {
            Ok((mut stream, _)) => {
                let request = match read_request(&mut stream, &token) {
                    Ok(v) => v,
                    Err(e) => {
                        let _ = respond(&mut stream, 400, &json!({"error":e.to_string()}));
                        continue;
                    }
                };
                if !authorized(&request.authorization, &token) {
                    let _ = respond(
                        &mut stream,
                        401,
                        &json!({"error":"Authentication required"}),
                    );
                    continue;
                }
                let (status, response) = match (request.method.as_str(), request.target.as_str()) {
                    ("GET", "/status") => (
                        200,
                        json!({"ok":true,"metadata":metadata,"targetExited":target.exited(),"samples":seq,"retainedSamples":ring.len(),"latest":ring.back()}),
                    ),
                    ("GET", "/samples") => (200, json!({"samples":ring})),
                    ("POST", "/scenario") => match serde_json::from_slice::<Value>(&request.body) {
                        Ok(v) if v["label"].as_str().is_some_and(|s| s.len() <= 80) => {
                            scenario = v["label"].as_str().unwrap().into();
                            (200, json!({"ok":true,"label":scenario}))
                        }
                        _ => (
                            400,
                            json!({"error":"Expected JSON label (maximum 80 UTF-8 bytes)"}),
                        ),
                    },
                    ("GET", "/app/diagnostics") => (200, app.clone()),
                    ("GET", "/app/health") => match app_request(app_port, "GET", "/health", &[]) {
                        Ok(v) => (200, v),
                        Err(e) => (502, json!({"error":e.to_string()})),
                    },
                    ("POST", "/shutdown") => {
                        stop = true;
                        (200, json!({"ok":true}))
                    }
                    ("POST", path) if injection_path(path).is_some() => match app_request(
                        app_port,
                        "POST",
                        &injection_path(path).unwrap(),
                        &request.body,
                    ) {
                        Ok(v) => (200, v),
                        Err(e) => (502, json!({"error":e.to_string()})),
                    },
                    _ => (404, json!({"error":"Unknown endpoint"})),
                };
                let _ = respond(&mut stream, status, &response);
            }
            Err(e) if e.kind() == io::ErrorKind::WouldBlock => {
                std::thread::sleep(Duration::from_millis(25))
            }
            Err(e) => return Err(e),
        }
    }
    writer.flush()?;
    fs::remove_file(output.join("connection.json"))?;
    Ok(())
}
fn main() {
    #[cfg(windows)]
    if let Err(e) = run() {
        eprintln!("Performance agent: {e}");
        std::process::exit(1);
    }
    #[cfg(not(windows))]
    {
        eprintln!("Windows is required");
        std::process::exit(1);
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn authentication_and_routes_are_narrow() {
        assert!(authorized("Bearer exact", "exact"));
        assert!(!authorized("Bearer exacT", "exact"));
        assert_eq!(
            injection_path("/app/inject?format=whews"),
            Some("/inject?format=whews".into())
        );
        for value in [
            "/app/inject?format=whews&fresh=1",
            "/app/inject?path=C:/x",
            "/app/inject?format=x%26fresh=1",
        ] {
            assert!(injection_path(value).is_none());
        }
    }
    #[test]
    fn chunked_app_response_and_json_response_are_decoded() {
        assert_eq!(
            decode_http(b"HTTP/1.1 200 OK\r\nContent-Length: 11\r\n\r\n{\"ok\":true}").unwrap(),
            json!({"ok":true})
        );
        assert_eq!(decode_http(b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nb\r\n{\"ok\":true}\r\n0\r\n\r\n").unwrap(),json!({"ok":true}));
        assert!(decode_http(b"HTTP/1.1 404 Not Found\r\n\r\n{}").is_err());
    }
    #[cfg(windows)]
    #[test]
    fn windows_reads_actual_process_counters_and_secure_tokens() {
        let process = win::Process::open(std::process::id()).unwrap();
        let sample = process.sample().unwrap();
        assert!(sample["rssBytes"].as_u64().unwrap() > 0);
        assert!(sample["privateBytes"].as_u64().unwrap() > 0);
        assert_eq!(win::token().unwrap().len(), 64);
        assert_ne!(win::token().unwrap(), win::token().unwrap());
    }
}
