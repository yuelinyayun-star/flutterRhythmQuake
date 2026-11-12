use std::{
    collections::HashMap,
    sync::atomic::{AtomicUsize, Ordering},
};

const LIMIT: usize = 128 * 1024 * 1024;
const MAX_NODES: usize = 2_000_000;
static CALLS: AtomicUsize = AtomicUsize::new(0);
static SESSIONS: AtomicUsize = AtomicUsize::new(0);

#[derive(Clone, PartialEq, Eq, Hash)]
enum Node {
    Null,
    Bool(bool),
    Int(i64),
    Float(u64),
    String(Vec<u16>),
    List(Vec<usize>),
    Map(Vec<usize>),
}
struct Encoder<'a> {
    input: &'a [u8],
    offset: usize,
    nodes: Vec<Node>,
    index: HashMap<Node, usize>,
    strings: Vec<usize>,
    containers: Vec<usize>,
}
impl<'a> Encoder<'a> {
    fn take(&mut self, count: usize) -> Result<&'a [u8], i32> {
        let end = self.offset.checked_add(count).ok_or(3)?;
        let value = self.input.get(self.offset..end).ok_or(2)?;
        self.offset = end;
        Ok(value)
    }
    fn u32(&mut self) -> Result<usize, i32> {
        Ok(u32::from_le_bytes(self.take(4)?.try_into().unwrap()) as usize)
    }
    fn intern(&mut self, node: Node) -> Result<usize, i32> {
        if let Some(index) = self.index.get(&node) {
            return Ok(*index);
        }
        if self.nodes.len() >= MAX_NODES {
            return Err(3);
        }
        let index = self.nodes.len();
        self.nodes.push(node.clone());
        self.index.insert(node, index);
        Ok(index)
    }
    fn value(&mut self, depth: usize) -> Result<usize, i32> {
        if depth > 512 {
            return Err(3);
        }
        let tag = self.take(1)?[0];
        if tag == 8 {
            let index = self.u32()?;
            return self.strings.get(index).copied().ok_or(2);
        }
        if tag == 9 {
            let index = self.u32()?;
            return self.containers.get(index).copied().ok_or(2);
        }
        let node = match tag {
            0 => Node::Null,
            1 => Node::Bool(false),
            2 => Node::Bool(true),
            3 => Node::Int(i64::from_le_bytes(self.take(8)?.try_into().unwrap())),
            4 => {
                let bits = u64::from_le_bytes(self.take(8)?.try_into().unwrap());
                if !f64::from_bits(bits).is_finite() {
                    return Err(2);
                }
                Node::Float(bits)
            }
            5 => {
                let count = self.u32()?;
                let bytes = self.take(count.checked_mul(2).ok_or(3)?)?;
                Node::String(
                    bytes
                        .chunks_exact(2)
                        .map(|b| u16::from_le_bytes([b[0], b[1]]))
                        .collect(),
                )
            }
            6 | 7 => {
                let count = self.u32()?;
                let words = count.checked_mul(if tag == 7 { 2 } else { 1 }).ok_or(3)?;
                if words > self.input.len().saturating_sub(self.offset) || words > MAX_NODES {
                    return Err(3);
                }
                let mut children = Vec::with_capacity(words);
                for i in 0..words {
                    let child = self.value(depth + 1)?;
                    if tag == 7 && i % 2 == 0 && !matches!(self.nodes[child], Node::String(_)) {
                        return Err(2);
                    }
                    children.push(child);
                }
                if tag == 6 {
                    Node::List(children)
                } else {
                    Node::Map(children)
                }
            }
            _ => return Err(2),
        };
        let index = self.intern(node)?;
        if tag == 5 {
            self.strings.push(index);
        }
        if tag == 6 || tag == 7 {
            self.containers.push(index);
        }
        Ok(index)
    }
}
fn quoted(out: &mut String, units: &[u16]) {
    use std::fmt::Write;
    out.push('"');
    let mut i = 0;
    while i < units.len() {
        let u = units[i];
        i += 1;
        match u {
            34 => out.push_str("\\\""),
            92 => out.push_str("\\\\"),
            0..=31 => {
                write!(out, "\\u{u:04x}").unwrap();
            }
            0xd800..=0xdbff if i < units.len() && (0xdc00..=0xdfff).contains(&units[i]) => {
                let code = 0x10000 + (((u as u32 - 0xd800) << 10) | (units[i] as u32 - 0xdc00));
                i += 1;
                out.push(char::from_u32(code).unwrap());
            }
            0xd800..=0xdfff => {
                write!(out, "\\u{u:04x}").unwrap();
            }
            _ => out.push(char::from_u32(u as u32).unwrap()),
        }
    }
    out.push('"');
}
fn encode(input: &[u8]) -> Result<Vec<u8>, i32> {
    use std::fmt::Write;
    let mut encoder = Encoder {
        input,
        offset: 0,
        nodes: Vec::new(),
        index: HashMap::new(),
        strings: Vec::new(),
        containers: Vec::new(),
    };
    let count = encoder.u32()?;
    if count > 100_000 || count > input.len() {
        return Err(3);
    }
    let mut roots = Vec::with_capacity(count);
    for _ in 0..count {
        roots.push(encoder.value(0)?);
    }
    if encoder.offset != input.len() {
        return Err(2);
    }
    // Index data is no longer needed while constructing the owned output.
    drop(encoder.index);
    let mut out = String::from("{\"format\":\"station-json-table-v1\",\"nodes\":[");
    for (index, node) in encoder.nodes.iter().enumerate() {
        if index != 0 {
            out.push(',');
        }
        match node {
            Node::Null => out.push_str("null"),
            Node::Bool(v) => out.push_str(if *v { "true" } else { "false" }),
            Node::Int(v) => write!(out, "{v}").unwrap(),
            // Scientific syntax preserves the double type even for 1.0/-0.0.
            Node::Float(bits) => write!(out, "{:e}", f64::from_bits(*bits)).unwrap(),
            Node::String(v) => quoted(&mut out, v),
            Node::List(v) | Node::Map(v) => {
                out.push_str(if matches!(node, Node::List(_)) {
                    "[\"l\""
                } else {
                    "[\"m\""
                });
                for child in v {
                    write!(out, ",{child}").unwrap();
                }
                out.push(']');
            }
        }
        if out.len() > LIMIT {
            return Err(3);
        }
    }
    out.push_str("],\"frames\":[");
    for (i, root) in roots.iter().enumerate() {
        if i != 0 {
            out.push(',');
        }
        write!(out, "{root}").unwrap();
    }
    out.push_str("]}");
    if out.len() > LIMIT {
        return Err(3);
    }
    Ok(out.into_bytes())
}
struct Archive {
    bytes: Vec<u8>,
}
#[no_mangle]
pub extern "C" fn rq_station_archive_abi_version() -> u32 {
    1
}
#[no_mangle]
pub extern "C" fn rq_station_archive_calls() -> u64 {
    CALLS.load(Ordering::Relaxed) as u64
}
#[no_mangle]
pub extern "C" fn rq_station_archive_sessions() -> u64 {
    SESSIONS.load(Ordering::Relaxed) as u64
}
/// Caller provides valid input/status memory; input is borrowed only for this call.
#[no_mangle]
pub unsafe extern "C" fn rq_station_archive_create(
    input: *const u8,
    length: usize,
    status: *mut i32,
) -> *mut std::ffi::c_void {
    unsafe { create(input, length, status, false) }
}
/// Same table with a gzip level 3 storage envelope; no expanded graph crosses FFI.
#[no_mangle]
pub unsafe extern "C" fn rq_station_archive_create_gzip(
    input: *const u8,
    length: usize,
    status: *mut i32,
) -> *mut std::ffi::c_void {
    unsafe { create(input, length, status, true) }
}
unsafe fn create(
    input: *const u8,
    length: usize,
    status: *mut i32,
    gzip: bool,
) -> *mut std::ffi::c_void {
    if status.is_null() {
        return std::ptr::null_mut();
    }
    unsafe {
        *status = 1;
    }
    if input.is_null() || length < 4 {
        return std::ptr::null_mut();
    }
    if length > LIMIT {
        unsafe {
            *status = 3;
        }
        return std::ptr::null_mut();
    }
    CALLS.fetch_add(1, Ordering::Relaxed);
    let result = std::panic::catch_unwind(|| {
        let bytes = encode(unsafe { std::slice::from_raw_parts(input, length) })?;
        if !gzip {
            return Ok(bytes);
        }
        use std::io::Write;
        let mut encoder = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::new(3));
        encoder.write_all(&bytes).map_err(|_| 4)?;
        let compressed = encoder.finish().map_err(|_| 4)?;
        if compressed.len() > LIMIT {
            return Err(3);
        }
        Ok(compressed)
    })
    .unwrap_or(Err(5));
    match result {
        Ok(bytes) => {
            unsafe {
                *status = 0;
            }
            SESSIONS.fetch_add(1, Ordering::Relaxed);
            Box::into_raw(Box::new(Archive { bytes })).cast()
        }
        Err(code) => {
            unsafe {
                *status = code;
            }
            std::ptr::null_mut()
        }
    }
}
#[no_mangle]
pub unsafe extern "C" fn rq_station_archive_length(handle: *const std::ffi::c_void) -> usize {
    if handle.is_null() {
        0
    } else {
        unsafe { (&*handle.cast::<Archive>()).bytes.len() }
    }
}
#[no_mangle]
pub unsafe extern "C" fn rq_station_archive_copy(
    handle: *const std::ffi::c_void,
    output: *mut u8,
    length: usize,
) -> i32 {
    if handle.is_null() || output.is_null() {
        return 1;
    }
    let bytes = unsafe { &(&*handle.cast::<Archive>()).bytes };
    if length != bytes.len() {
        return 2;
    }
    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), output, length);
    }
    0
}
#[no_mangle]
pub unsafe extern "C" fn rq_station_archive_destroy(handle: *mut std::ffi::c_void) {
    if !handle.is_null() {
        unsafe {
            drop(Box::from_raw(handle.cast::<Archive>()));
        }
        SESSIONS.fetch_sub(1, Ordering::Relaxed);
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn compressed_owner_round_trip_and_malformed_references() {
        use std::io::Read;
        let input = [
            1, 0, 0, 0, 6, 2, 0, 0, 0, 5, 1, 0, 0, 0, 65, 0, 8, 0, 0, 0, 0,
        ];
        let mut status = -1;
        let owner =
            unsafe { rq_station_archive_create_gzip(input.as_ptr(), input.len(), &mut status) };
        assert_eq!(status, 0);
        assert!(!owner.is_null());
        let mut compressed = vec![0; unsafe { rq_station_archive_length(owner) }];
        assert_eq!(
            unsafe { rq_station_archive_copy(owner, compressed.as_mut_ptr(), compressed.len()) },
            0
        );
        unsafe {
            rq_station_archive_destroy(owner);
        }
        let mut decoded = Vec::new();
        flate2::read::GzDecoder::new(compressed.as_slice())
            .read_to_end(&mut decoded)
            .unwrap();
        assert_eq!(decoded, encode(&input).unwrap());
        let invalid = [1, 0, 0, 0, 9, 0, 0, 0, 0];
        assert!(
            unsafe { rq_station_archive_create(invalid.as_ptr(), invalid.len(), &mut status) }
                .is_null()
        );
        assert_eq!(status, 2);
        assert_eq!(rq_station_archive_sessions(), 0);
    }
    #[test]
    fn empty_archive_and_malformed_input() {
        assert_eq!(
            String::from_utf8(encode(&[0, 0, 0, 0]).unwrap()).unwrap(),
            "{\"format\":\"station-json-table-v1\",\"nodes\":[],\"frames\":[]}"
        );
        assert_eq!(encode(&[1, 0, 0, 0, 255]), Err(2));
        assert_eq!(encode(&[0, 0, 0, 0, 0]), Err(2));
    }
    #[test]
    fn scalar_identity_and_utf16() {
        let mut data = vec![5, 0, 0, 0, 3];
        data.extend_from_slice(&0_i64.to_le_bytes());
        data.push(4);
        data.extend_from_slice(&0_f64.to_bits().to_le_bytes());
        data.push(4);
        data.extend_from_slice(&(-0_f64).to_bits().to_le_bytes());
        data.push(5);
        data.extend_from_slice(&2_u32.to_le_bytes());
        data.extend_from_slice(&[0x2d, 0x4e, 0x00, 0xd8]);
        data.push(3);
        data.extend_from_slice(&0_i64.to_le_bytes());
        let text = String::from_utf8(encode(&data).unwrap()).unwrap();
        assert!(text.contains("0,0e0,-0e0,\"中\\ud800\""));
        assert!(text.ends_with("\"frames\":[0,1,2,3,0]}"));
    }
}
