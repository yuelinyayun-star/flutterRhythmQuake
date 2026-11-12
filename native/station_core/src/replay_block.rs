//! Native replay archive ingress: checksum, decompression, table validation and
//! immutable graph preparation. One shared worker; Dart only binds frame views.
use super::{palert_display::post_replay_block, timestamp, Post};
use base64::{engine::general_purpose::STANDARD, Engine};
use flate2::read::GzDecoder;
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::{
    ffi::c_void,
    io::Read,
    sync::{mpsc, OnceLock},
    thread,
};
const LIMIT: usize = 128 * 1024 * 1024;
struct Decoded {
    bytes: Vec<u8>,
    expanded: i64,
    error: bool,
}
fn field(nodes: &[Value], id: usize, key: &str) -> Result<usize, String> {
    let map = nodes
        .get(id)
        .and_then(Value::as_array)
        .filter(|a| a.first().is_some_and(|v| v == "m") && a.len() % 2 == 1)
        .ok_or("Invalid station frame map")?;
    let mut found = None;
    for pair in map[1..].chunks_exact(2) {
        let k = pair[0]
            .as_u64()
            .and_then(|n| nodes.get(n as usize))
            .and_then(Value::as_str)
            .ok_or("Invalid station frame key")?;
        if k == key {
            if found.is_some() {
                return Err("Duplicate station frame field".into());
            }
            found = pair[1].as_u64().map(|n| n as usize);
        }
    }
    found.ok_or_else(|| "Missing station frame field".into())
}
fn decode(data: &[u8], hash: &[u8], index: &[u8]) -> Result<(Vec<u8>, i64), String> {
    let compressed = STANDARD
        .decode(data)
        .map_err(|_| "Invalid station block base64")?;
    if format!("{:x}", Sha256::digest(&compressed)).as_bytes() != hash {
        return Err("Station block checksum mismatch".into());
    }
    let mut expanded = Vec::new();
    GzDecoder::new(compressed.as_slice())
        .take((LIMIT + 1) as u64)
        .read_to_end(&mut expanded)
        .map_err(|_| "Invalid station block compression")?;
    if expanded.len() > LIMIT {
        return Err("Station block expansion too large".into());
    }
    let table: Value =
        serde_json::from_slice(&expanded).map_err(|_| "Invalid station JSON table")?;
    let index: Value = serde_json::from_slice(index).map_err(|_| "Invalid station block index")?;
    let index = index.as_array().ok_or("Invalid station block index")?;
    let roots = table["frames"]
        .as_array()
        .ok_or("Invalid station frame roots")?;
    if roots.len() != index.len() {
        return Err("Station block frame count mismatch".into());
    }
    let nodes = table["nodes"]
        .as_array()
        .ok_or("Invalid station table nodes")?;
    for (root, index) in roots.iter().zip(index) {
        let root = root.as_u64().ok_or("Invalid station frame root")? as usize;
        let receipt = nodes
            .get(field(nodes, root, "receivedAt")?)
            .and_then(Value::as_str)
            .ok_or("Invalid station receipt")?;
        let kind = nodes
            .get(field(nodes, field(nodes, root, "snapshot")?, "kind")?)
            .and_then(Value::as_str)
            .ok_or("Invalid station source")?;
        if !["nied", "snet", "kma", "cwa", "seisjs", "palert", "lpgm"].contains(&kind)
            || index[1] != kind
        {
            return Err("Station block index mismatch".into());
        }
        let expected = timestamp(&index[0], false, i64::MIN).ok_or("Invalid station index time")?;
        let actual = timestamp(&Value::String(receipt.to_owned()), false, i64::MIN)
            .ok_or("Invalid station receipt")?;
        if expected != actual {
            return Err("Station block index mismatch".into());
        }
    }
    Ok((
        crate::station_json::pack_table(&table)?,
        expanded.len() as i64,
    ))
}
fn result(data: &[u8], hash: &[u8], index: &[u8]) -> Decoded {
    match std::panic::catch_unwind(|| decode(data, hash, index)) {
        Ok(Ok((bytes, expanded))) => Decoded {
            bytes,
            expanded,
            error: false,
        },
        Ok(Err(error)) => Decoded {
            bytes: error.into_bytes(),
            expanded: 0,
            error: true,
        },
        Err(_) => Decoded {
            bytes: b"Native station replay decode failed".to_vec(),
            expanded: 0,
            error: true,
        },
    }
}
struct Request {
    data: Vec<u8>,
    hash: Vec<u8>,
    index: Vec<u8>,
    port: i64,
    post: Option<Post>,
}
static WORKER: OnceLock<mpsc::Sender<Request>> = OnceLock::new();
fn worker() -> &'static mpsc::Sender<Request> {
    WORKER.get_or_init(|| {
        let (tx, rx) = mpsc::channel::<Request>();
        thread::Builder::new()
            .name("rq-replay-archives".into())
            .stack_size(512 * 1024)
            .spawn(move || {
                for r in rx {
                    let decoded = result(&r.data, &r.hash, &r.index);
                    post_replay_block(
                        r.post.unwrap(),
                        r.port,
                        &decoded.bytes,
                        decoded.expanded,
                        decoded.error,
                    );
                }
            })
            .expect("Native replay reader");
        tx
    })
}
unsafe fn request(
    data: *const u8,
    len: usize,
    hash: *const u8,
    hash_len: usize,
    index: *const u8,
    index_len: usize,
) -> Option<Request> {
    if data.is_null()
        || hash.is_null()
        || index.is_null()
        || len > LIMIT * 2
        || hash_len != 64
        || index_len > 64 * 1024 * 1024
    {
        return None;
    }
    Some(Request {
        data: unsafe { std::slice::from_raw_parts(data, len) }.to_vec(),
        hash: unsafe { std::slice::from_raw_parts(hash, hash_len) }.to_vec(),
        index: unsafe { std::slice::from_raw_parts(index, index_len) }.to_vec(),
        port: 0,
        post: None,
    })
}
#[no_mangle]
pub unsafe extern "C" fn rq_replay_block_async(
    data: *const u8,
    len: usize,
    hash: *const u8,
    hash_len: usize,
    index: *const u8,
    index_len: usize,
    port: i64,
    post: Post,
) -> u32 {
    let Some(mut r) = (unsafe { request(data, len, hash, hash_len, index, index_len) }) else {
        return 1;
    };
    r.port = port;
    r.post = Some(post);
    u32::from(worker().send(r).is_err())
}
#[no_mangle]
pub unsafe extern "C" fn rq_replay_block_sync(
    data: *const u8,
    len: usize,
    hash: *const u8,
    hash_len: usize,
    index: *const u8,
    index_len: usize,
) -> *mut c_void {
    let Some(r) = (unsafe { request(data, len, hash, hash_len, index, index_len) }) else {
        return std::ptr::null_mut();
    };
    Box::into_raw(Box::new(result(&r.data, &r.hash, &r.index))).cast()
}
#[no_mangle]
pub unsafe extern "C" fn rq_replay_block_result(
    owner: *const c_void,
    size: *mut usize,
    expanded: *mut i64,
    error: *mut u32,
) -> *const u8 {
    if owner.is_null() || size.is_null() || expanded.is_null() || error.is_null() {
        return std::ptr::null();
    }
    let r = unsafe { &*owner.cast::<Decoded>() };
    unsafe {
        *size = r.bytes.len();
        *expanded = r.expanded;
        *error = u32::from(r.error);
    }
    r.bytes.as_ptr()
}
#[no_mangle]
pub unsafe extern "C" fn rq_replay_block_free(owner: *mut c_void) {
    if !owner.is_null() {
        drop(unsafe { Box::from_raw(owner.cast::<Decoded>()) });
    }
}
