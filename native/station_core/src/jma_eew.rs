//! JMA EEW method metadata only. Does not change admission, waves or timing.
#[no_mangle]
pub extern "C" fn rq_jma_eew_is_plum(flags: u32) -> u32 {
    // 1 = JMA EEW source, 2 = EEW, 4 = existing assumption, 8 = wire isPLUM.
    u32::from(flags & 3 == 3 && flags & 12 != 0)
}

/// Maximum predicted long-period class. No allocations or retained buffers.
/// -1 denotes missing/invalid data, which is distinct from supplied class 0.
#[no_mangle]
pub unsafe extern "C" fn rq_jma_eew_lg_int_class(flags: u32, data: *const u8, len: usize) -> i32 {
    if flags & 3 != 3 || data.is_null() || len == 0 || len > 64 {
        return -1;
    }
    let bytes = unsafe { std::slice::from_raw_parts(data, len) };
    let Ok(text) = std::str::from_utf8(bytes) else {
        return -1;
    };
    let Ok(value) = text.trim().parse::<f64>() else {
        return -1;
    };
    if value.is_finite() && (0.0..=4.0).contains(&value) && value.fract() == 0.0 {
        value as i32
    } else {
        -1
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn method_metadata_never_changes_other_agencies_or_information() {
        assert_eq!(rq_jma_eew_is_plum(1 | 2 | 8), 1);
        assert_eq!(rq_jma_eew_is_plum(1 | 2 | 4), 1);
        assert_eq!(rq_jma_eew_is_plum(1 | 2), 0);
        assert_eq!(rq_jma_eew_is_plum(2 | 8), 0);
        assert_eq!(rq_jma_eew_is_plum(1 | 8), 0);
        assert_eq!(rq_jma_eew_is_plum(1 | 2 | 0x8000), 0);
    }
    #[test]
    fn long_period_class_preserves_zero_and_rejects_missing_or_other_products() {
        let parse = |flags, text: &str| unsafe {
            rq_jma_eew_lg_int_class(flags, text.as_ptr(), text.len())
        };
        for value in 0..=4 {
            assert_eq!(parse(3, &value.to_string()), value);
        }
        assert_eq!(parse(3, "2.0"), 2);
        for text in ["", " ", "NaN", "不明", "-1", "5", "2.5", "true"] {
            assert_eq!(parse(3, text), -1);
        }
        assert_eq!(parse(1, "3"), -1);
        assert_eq!(parse(2, "3"), -1);
    }
}
