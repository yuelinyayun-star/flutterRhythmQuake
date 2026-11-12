//! Locate original JSON without allocating wrapper substrings or executing JS.
pub(crate) trait Unit: Copy {
    const UTF8: bool;
    fn value(self) -> u16;
}
impl Unit for u8 {
    const UTF8: bool = true;
    fn value(self) -> u16 {
        self as u16
    }
}
impl Unit for u16 {
    const UTF8: bool = false;
    fn value(self) -> u16 {
        self
    }
}
fn at<T: Unit>(input: &[T], i: usize) -> u16 {
    input.get(i).map(|v| v.value()).unwrap_or(0xffff)
}
fn literal<T: Unit>(input: &[T], i: usize, value: &[u16]) -> bool {
    value.len() <= input.len().saturating_sub(i)
        && value
            .iter()
            .enumerate()
            .all(|(j, v)| at(input, i + j) == *v)
}
// ECMAScript RegExp \s, or Dart trimLeft's additional NEL for SSE.
fn white<T: Unit>(input: &[T], i: usize, trim: bool) -> usize {
    let first = at(input, i);
    if matches!(first, 9..=13 | 32) {
        return 1;
    }
    if !T::UTF8 {
        return usize::from(
            matches!(
                first,
                0xa0 | 0x1680 | 0x2000
                    ..=0x200a | 0x2028 | 0x2029 | 0x202f | 0x205f | 0x3000 | 0xfeff
            ) || (trim && first == 0x85),
        );
    }
    if first == 0xc2 && (at(input, i + 1) == 0xa0 || (trim && at(input, i + 1) == 0x85)) {
        return 2;
    }
    if first == 0xe1 && at(input, i + 1) == 0x9a && at(input, i + 2) == 0x80 {
        return 3;
    }
    if first == 0xe2
        && ((at(input, i + 1) == 0x80
            && matches!(at(input, i + 2), 0x80..=0x8a | 0xa8 | 0xa9 | 0xaf))
            || (at(input, i + 1) == 0x81 && at(input, i + 2) == 0x9f))
    {
        return 3;
    }
    if (first == 0xe3 && at(input, i + 1) == 0x80 && at(input, i + 2) == 0x80)
        || (first == 0xef && at(input, i + 1) == 0xbb && at(input, i + 2) == 0xbf)
    {
        return 3;
    }
    0
}
fn skip<T: Unit>(input: &[T], mut i: usize, trim: bool) -> usize {
    loop {
        let n = white(input, i, trim);
        if n == 0 {
            return i;
        }
        i += n;
    }
}
fn name_at<T: Unit>(input: &[T], i: usize, name: &[T]) -> bool {
    name.len() <= input.len().saturating_sub(i)
        && name
            .iter()
            .enumerate()
            .all(|(j, v)| at(input, i + j) == v.value())
}
pub(crate) fn range<T: Unit>(input: &[T], kind: u32, name: &[T]) -> Result<(usize, usize), i32> {
    match kind {
        5 => {
            let start = input.iter().position(|c| c.value() == 123).ok_or(2)?;
            let end = input.iter().rposition(|c| c.value() == 125).ok_or(2)?;
            if end <= start {
                return Err(2);
            }
            Ok((start, end + 1))
        }
        6 => {
            for start in 0..input.len() {
                if !literal(input, start, &[118, 97, 114]) {
                    continue;
                }
                let mut i = start + 3;
                if white(input, i, false) == 0 {
                    continue;
                }
                i = skip(input, i, false);
                if !literal(input, i, &[97, 108, 97, 114, 109, 105, 110, 102, 111]) {
                    continue;
                }
                i = skip(input, i + 9, false);
                if at(input, i) != 61 {
                    continue;
                }
                i = skip(input, i + 1, false);
                if at(input, i) != 123 {
                    continue;
                }
                if let Some(end) = (i + 1..input.len()).find(|&j| at(input, j) == 125) {
                    return Ok((i, end + 1));
                }
            }
            Err(2)
        }
        1 | 4 => {
            let mut start = skip(input, 0, false);
            if !name_at(input, start, name) {
                return Err(2);
            }
            start += name.len();
            if kind == 1 {
                start = skip(input, start, false);
            }
            if at(input, start) != 40 {
                return Err(2);
            }
            start += 1;
            // Remember the last non-space unit rather than allocate/reverse UTF8.
            let mut end = start;
            let mut i = start;
            while i < input.len() {
                let n = white(input, i, false);
                if n == 0 {
                    i += 1;
                    end = i;
                } else {
                    i += n;
                }
            }
            if end > start && at(input, end - 1) == 59 {
                let stop = end - 1;
                end = start;
                i = start;
                while i < stop {
                    let n = white(input, i, false);
                    if n == 0 {
                        i += 1;
                        end = i;
                    } else {
                        i += n;
                    }
                }
            }
            if end <= start || at(input, end - 1) != 41 {
                return Err(2);
            }
            Ok((start, end - 1))
        }
        2 => {
            let mut selected = None;
            for boundary in 0..=input.len() {
                let mut i = if boundary == 0 {
                    0
                } else {
                    let n = white(input, boundary - 1, false);
                    if n > 0 {
                        boundary - 1 + n
                    } else if at(input, boundary - 1) == 59 {
                        boundary
                    } else {
                        continue;
                    }
                };
                if !literal(input, i, &[118, 97, 114]) {
                    continue;
                }
                i += 3;
                if white(input, i, false) == 0 {
                    continue;
                }
                i = skip(input, i, false);
                if !name_at(input, i, name) {
                    continue;
                }
                i = skip(input, i + name.len(), false);
                if at(input, i) != 61 {
                    continue;
                }
                selected = Some(skip(input, i + 1, false));
                break;
            }
            let start = selected.ok_or(2)?;
            if !matches!(at(input, start), 123 | 91) {
                return Err(2);
            }
            let (mut depth, mut quoted, mut escaped) = (0i64, false, false);
            for i in start..input.len() {
                let c = at(input, i);
                if quoted {
                    if escaped {
                        escaped = false;
                    } else if c == 92 {
                        escaped = true;
                    } else if c == 34 {
                        quoted = false;
                    }
                    continue;
                }
                if c == 34 {
                    quoted = true;
                }
                if matches!(c, 123 | 91) {
                    depth += 1;
                }
                if matches!(c, 125 | 93) {
                    depth -= 1;
                    if depth == 0 {
                        return Ok((start, i + 1));
                    }
                }
            }
            Err(2)
        }
        3 => {
            if !literal(input, 0, &[100, 97, 116, 97, 58]) {
                return Err(2);
            }
            Ok((skip(input, 5, true), input.len()))
        }
        _ => Err(1),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn wrapper_ranges_and_boundaries() {
        let s = b" \ncb ( {\"x\":\")\"} ) ; \r";
        let (a, b) = range(s, 1, b"cb").unwrap();
        assert_eq!(&s[a..b], b" {\"x\":\")\"} ");
        assert!(range(s, 4, b"cb").is_err());
        assert!(range(b"cb({});;", 1, b"cb").is_err());
        let s = b"var ignore={};var data = {\"x\":\"}\\\"\"}; ignored()";
        let (a, b) = range(s, 2, b"data").unwrap();
        assert_eq!(&s[a..b], b"{\"x\":\"}\\\"\"}");
        assert!(range(b"var data=0;var data={}", 2, b"data").is_err());
        assert!(range(b"xvar data={}", 2, b"data").is_err());
        assert_eq!(range(b"data: {}", 3, b""), Ok((6, 8)));
        assert!(range(b" data: {}", 3, b"").is_err());
    }
}
