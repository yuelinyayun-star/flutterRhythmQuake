//! Original byte ingress: UTF-8 policy, wrappers and incremental SSE lines.
use super::{Tree, CALLS, LIMIT};
use std::{borrow::Cow, ffi::c_void, sync::atomic::Ordering};

#[derive(Default)]
pub(super) struct SseLines {
    bytes: Vec<u8>,
    consumed: usize,
    scan: usize,
    skip_lf: bool,
    first: bool,
    finished: bool,
}
impl SseLines {
    fn feed(&mut self, bytes: &[u8], finish: bool) -> Result<(), i32> {
        if self.finished {
            return Err(1);
        }
        if self.consumed > 0 {
            self.bytes.drain(..self.consumed);
            self.scan -= self.consumed;
            self.consumed = 0;
        }
        if self.bytes.len().checked_add(bytes.len()).ok_or(3)? > LIMIT {
            return Err(3);
        }
        self.bytes.extend_from_slice(bytes);
        self.finished = finish;
        Ok(())
    }
    fn line(&mut self) -> Option<&[u8]> {
        if self.skip_lf && self.scan < self.bytes.len() {
            if self.bytes[self.scan] == b'\n' {
                self.scan += 1;
                self.consumed = self.scan;
            }
            self.skip_lf = false;
        }
        while self.scan < self.bytes.len() {
            let index = self.scan;
            let byte = self.bytes[index];
            self.scan += 1;
            if byte == b'\r' || byte == b'\n' {
                let start = self.consumed;
                self.consumed = self.scan;
                self.skip_lf = byte == b'\r';
                let line = &self.bytes[start..index];
                let first = !self.first;
                self.first = true;
                return Some(if first {
                    line.strip_prefix(&[0xef, 0xbb, 0xbf]).unwrap_or(line)
                } else {
                    line
                });
            }
        }
        if self.finished && self.consumed < self.bytes.len() {
            let start = self.consumed;
            self.consumed = self.bytes.len();
            let line = &self.bytes[start..];
            let first = !self.first;
            self.first = true;
            return Some(if first {
                line.strip_prefix(&[0xef, 0xbb, 0xbf]).unwrap_or(line)
            } else {
                line
            });
        }
        None
    }
}

#[no_mangle]
pub extern "C" fn rq_api_ingress_abi_version() -> u32 {
    1
}

/// Input is immutable and valid for the call; returned packed snapshot is
/// borrowed from owner until its next operation. Copy it before calling again.
#[no_mangle]
pub unsafe extern "C" fn rq_api_ingress_utf8(
    owner: *mut c_void,
    input: *const u8,
    length: usize,
    mode: u32,
    name: *const u8,
    name_length: usize,
    output: *mut *const u8,
    size: *mut usize,
) -> i32 {
    if owner.is_null()
        || output.is_null()
        || size.is_null()
        || (length > 0 && input.is_null())
        || (name_length > 0 && name.is_null())
    {
        return 1;
    }
    unsafe {
        *output = std::ptr::null();
        *size = 0;
    }
    if length > LIMIT || name_length > LIMIT {
        return 3;
    }
    std::panic::catch_unwind(|| unsafe {
        let bytes = if length == 0 {
            &[]
        } else {
            std::slice::from_raw_parts(input, length)
        };
        let text = if mode & 0x100 != 0 {
            String::from_utf8_lossy(bytes)
        } else {
            match std::str::from_utf8(bytes) {
                Ok(text) => Cow::Borrowed(text),
                Err(_) => return 2,
            }
        };
        let bytes = text
            .as_bytes()
            .strip_prefix(&[0xef, 0xbb, 0xbf])
            .unwrap_or(text.as_bytes());
        let name = if name_length == 0 {
            &[]
        } else {
            std::slice::from_raw_parts(name, name_length)
        };
        let kind = mode & 0xff;
        let selected = if kind == 0 {
            bytes
        } else {
            match crate::json_envelope::range(bytes, kind, name) {
                Ok((a, b)) => &bytes[a..b],
                Err(status) => return status,
            }
        };
        let tree = &mut *owner.cast::<Tree>();
        match tree.decode_input::<_, false>(selected) {
            Ok(()) => {
                *output = tree.output.as_ptr();
                *size = tree.output.len();
                CALLS.fetch_add(1, Ordering::Relaxed);
                0
            }
            Err(status) => status,
        }
    })
    .unwrap_or(5)
}

/// Feed original HTTP chunks in order. finish=1 is EOF, not a reconnect.
#[no_mangle]
pub unsafe extern "C" fn rq_api_sse_feed(
    owner: *mut c_void,
    input: *const u8,
    length: usize,
    finish: u32,
) -> i32 {
    if owner.is_null() || (length > 0 && input.is_null()) || finish > 1 {
        return 1;
    }
    if length > LIMIT {
        return 3;
    }
    std::panic::catch_unwind(|| unsafe {
        let bytes = if length == 0 {
            &[]
        } else {
            std::slice::from_raw_parts(input, length)
        };
        (&mut *owner.cast::<Tree>())
            .sse
            .feed(bytes, finish == 1)
            .err()
            .unwrap_or(0)
    })
    .unwrap_or(5)
}

/// 0=snapshot, 100=need bytes/EOF drained. Invalid JSON data lines are skipped
/// exactly as the previous client; malformed UTF-8 anywhere terminates stream.
#[no_mangle]
pub unsafe extern "C" fn rq_api_sse_next(
    owner: *mut c_void,
    output: *mut *const u8,
    size: *mut usize,
) -> i32 {
    if owner.is_null() || output.is_null() || size.is_null() {
        return 1;
    }
    unsafe {
        *output = std::ptr::null();
        *size = 0;
    }
    std::panic::catch_unwind(|| unsafe {
        let tree = &mut *owner.cast::<Tree>();
        // Move only the framer owner; input and JSON output remain independent.
        let mut lines = std::mem::take(&mut tree.sse);
        let status = loop {
            let Some(line) = lines.line() else {
                break 100;
            };
            if std::str::from_utf8(line).is_err() {
                break 2;
            }
            if !line.starts_with(b"data:") {
                continue;
            }
            let Ok((a, b)) = crate::json_envelope::range(line, 3, b"") else {
                continue;
            };
            if tree.decode_input::<_, false>(&line[a..b]).is_err() {
                continue;
            }
            *output = tree.output.as_ptr();
            *size = tree.output.len();
            CALLS.fetch_add(1, Ordering::Relaxed);
            break 0;
        };
        tree.sse = lines;
        status
    })
    .unwrap_or(5)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn every_chunk_boundary_crlf_bom_and_eof() {
        let bytes = "\u{feff}data: {\"日本\":1}\r\ndata: [2]\ndata: true".as_bytes();
        for width in 1..=bytes.len() {
            let mut lines = SseLines::default();
            let mut result = vec![];
            for chunk in bytes.chunks(width) {
                lines.feed(chunk, false).unwrap();
                while let Some(line) = lines.line() {
                    result.push(line.to_vec());
                }
            }
            lines.feed(&[], true).unwrap();
            while let Some(line) = lines.line() {
                result.push(line.to_vec());
            }
            assert_eq!(
                result,
                vec![
                    b"data: {\"\xe6\x97\xa5\xe6\x9c\xac\":1}".to_vec(),
                    b"data: [2]".to_vec(),
                    b"data: true".to_vec()
                ]
            );
            assert!(lines.feed(b"x", false).is_err());
        }
    }
}
