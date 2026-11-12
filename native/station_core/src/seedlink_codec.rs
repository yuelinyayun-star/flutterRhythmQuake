//! Existing MiniSEED sample decode contract, including partial records and D0.
use std::sync::atomic::{AtomicU64, Ordering};
static CALLS: AtomicU64 = AtomicU64::new(0);

fn u32_at(input: &[u8], offset: usize, big: bool) -> u32 {
    let bytes: [u8; 4] = input[offset..offset + 4].try_into().unwrap();
    if big {
        u32::from_be_bytes(bytes)
    } else {
        u32::from_le_bytes(bytes)
    }
}
fn i16_at(input: &[u8], offset: usize, big: bool) -> i32 {
    let bytes: [u8; 2] = input[offset..offset + 2].try_into().unwrap();
    if big {
        i16::from_be_bytes(bytes) as i32
    } else {
        i16::from_le_bytes(bytes) as i32
    }
}
fn sign(value: u32, bits: u32) -> i32 {
    ((value << (32 - bits)) as i32) >> (32 - bits)
}

fn decode(input: &[u8], encoding: u32, big: bool, output: &mut [i32]) -> usize {
    if output.is_empty() || input.is_empty() {
        return 0;
    }
    if encoding == 1 || encoding == 3 {
        let width = if encoding == 1 { 2 } else { 4 };
        let count = output.len().min(input.len() / width);
        for (i, value) in output[..count].iter_mut().enumerate() {
            *value = if encoding == 1 {
                i16_at(input, i * 2, big)
            } else {
                u32_at(input, i * 4, big) as i32
            };
        }
        return count;
    }
    if encoding != 10 && encoding != 11 {
        return 0;
    }
    let mut written = 0;
    let mut previous: Option<i32> = None;
    let mut skip_first = true;
    for frame in (0..input.len() / 64).map(|i| i * 64) {
        let control = u32_at(input, frame, big);
        for word_index in 1..16 {
            let offset = frame + word_index * 4;
            let word = u32_at(input, offset, big);
            if frame == 0 && word_index == 1 {
                previous = Some(word as i32);
                output[written] = word as i32;
                written += 1;
                if written == output.len() {
                    return written;
                }
                continue;
            }
            if frame == 0 && word_index == 2 {
                continue;
            }
            let Some(mut current) = previous else {
                return written;
            };
            let code = (control >> (30 - 2 * word_index)) & 3;
            let (count, bits) = if encoding == 10 {
                match code {
                    1 => (4, 8),
                    2 => (2, 16),
                    3 => (1, 32),
                    _ => (0, 0),
                }
            } else {
                match (code, word >> 30) {
                    (1, _) => (4, 8),
                    (2, 1) => (1, 30),
                    (2, 2) => (2, 15),
                    (2, 3) => (3, 10),
                    (3, 0) => (5, 6),
                    (3, 1) => (6, 5),
                    (3, 2) => (7, 4),
                    _ => (0, 0),
                }
            };
            for j in 0..count {
                let difference = if code == 1 {
                    input[offset + j] as i8 as i32
                } else if encoding == 10 && code == 2 {
                    i16_at(input, offset + j * 2, big)
                } else {
                    sign(word >> ((count - 1 - j) * bits as usize), bits)
                };
                if skip_first {
                    skip_first = false;
                    continue;
                }
                current = current.wrapping_add(difference);
                previous = Some(current);
                output[written] = current;
                written += 1;
                if written == output.len() {
                    return written;
                }
            }
        }
    }
    written
}

#[no_mangle]
pub extern "C" fn rq_seedlink_codec_abi_version() -> u32 {
    1
}
#[no_mangle]
pub extern "C" fn rq_seedlink_codec_calls() -> u64 {
    CALLS.load(Ordering::Relaxed)
}

/// # Safety
/// Input borrows length bytes, output capacity int32 words, written one size_t.
/// All pointers are valid, aligned for their types, disjoint, and not retained.
#[no_mangle]
pub unsafe extern "C" fn rq_seedlink_decode(
    input: *const u8,
    length: usize,
    encoding: u32,
    big: u8,
    count: usize,
    output: *mut i32,
    capacity: usize,
    written: *mut usize,
) -> i32 {
    if written.is_null() || (length > 0 && input.is_null()) || (capacity > 0 && output.is_null()) {
        return 1;
    }
    unsafe {
        *written = 0;
    }
    if length > 1_048_576 || count > 65535 {
        return 3;
    }
    if big > 1 {
        return 2;
    }
    let limit = match encoding {
        1 => count.min(length / 2),
        3 => count.min(length / 4),
        10 | 11 => count.min(length * 2),
        _ => 0,
    };
    if capacity < limit {
        return 3;
    }
    std::panic::catch_unwind(|| unsafe {
        let data = if length == 0 {
            &[]
        } else {
            std::slice::from_raw_parts(input, length)
        };
        let out = if limit == 0 {
            &mut []
        } else {
            std::slice::from_raw_parts_mut(output, limit)
        };
        *written = decode(data, encoding, big == 1, out);
        CALLS.fetch_add(1, Ordering::Relaxed);
        0
    })
    .unwrap_or(5)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn endianness_partial_records_and_signed_extension() {
        assert_eq!(sign(0xfffffff0, 4), 0);
        assert_eq!(sign(15, 4), -1);
        assert_eq!(sign(0x80000000, 32), i32::MIN);
        let mut output = [0; 4];
        assert_eq!(decode(&[0x80, 0, 0x7f, 0xff, 1], 1, true, &mut output), 2);
        assert_eq!(&output[..2], &[-32768, 32767]);
        assert_eq!(decode(&[0; 63], 11, true, &mut output), 0);
        assert_eq!(decode(&[0; 64], 11, true, &mut output), 1);
    }
}
