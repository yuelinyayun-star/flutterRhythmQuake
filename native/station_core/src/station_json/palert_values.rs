//! Derived P-Alert fields from the original JSON tree, without reparsing.
use super::{Node, Tree};
use std::{
    collections::HashMap,
    ffi::c_void,
    sync::atomic::{AtomicU64, Ordering},
};
static CALLS: AtomicU64 = AtomicU64::new(0);

#[derive(Default)]
pub(super) struct Fields {
    ids: HashMap<Vec<u16>, usize>,
    output: Vec<f64>,
    key: Vec<u16>,
    text: Vec<u16>,
    ascii: Vec<u8>,
    unknown: HashMap<Vec<u16>, bool>,
}

fn units(tree: &Tree, node: Node, out: &mut Vec<u16>) {
    out.clear();
    if node.tag == 11 {
        let start = node.aux as usize;
        // The whole transport was already validated by the JSON decoder.
        let text = std::str::from_utf8(&tree.strings8[start..start + node.bits as usize]).unwrap();
        out.extend(text.encode_utf16());
    } else if node.tag == 5 {
        let start = node.aux as usize;
        out.extend_from_slice(&tree.strings[start..start + node.bits as usize]);
    }
}

fn white(c: u16) -> bool {
    matches!(c, 9..=13 | 32 | 0x85 | 0xa0 | 0x1680 | 0x2000..=0x200a | 0x2028 | 0x2029 | 0x202f | 0x205f | 0x3000 | 0xfeff)
}

fn number(tree: &Tree, node: Node, text: &mut Vec<u16>, ascii: &mut Vec<u8>) -> Option<f64> {
    match node.tag {
        3 => return Some(node.bits as i64 as f64),
        4 => return Some(f64::from_bits(node.bits)),
        5 | 11 => units(tree, node, text),
        _ => return None,
    }
    let start = text.iter().position(|&c| !white(c))?;
    let end = text.iter().rposition(|&c| !white(c))? + 1;
    ascii.clear();
    for &c in &text[start..end] {
        if c > 127 {
            return None;
        }
        ascii.push(c as u8);
    }
    let mut i = usize::from(matches!(ascii.first(), Some(b'+' | b'-')));
    let body = &ascii[i..];
    if body == b"NaN" || body == b"Infinity" {
        return std::str::from_utf8(ascii).ok()?.parse().ok();
    }
    let mut digits = 0;
    while ascii.get(i).is_some_and(u8::is_ascii_digit) {
        i += 1;
        digits += 1;
    }
    if ascii.get(i) == Some(&b'.') {
        i += 1;
        while ascii.get(i).is_some_and(u8::is_ascii_digit) {
            i += 1;
            digits += 1;
        }
    }
    if digits == 0 {
        return None;
    }
    if matches!(ascii.get(i), Some(b'e' | b'E')) {
        i += 1;
        if matches!(ascii.get(i), Some(b'+' | b'-')) {
            i += 1;
        }
        let exponent = i;
        while ascii.get(i).is_some_and(u8::is_ascii_digit) {
            i += 1;
        }
        if i == exponent {
            return None;
        }
    }
    if i != ascii.len() {
        return None;
    }
    std::str::from_utf8(ascii).ok()?.parse().ok()
}

fn field(tree: &Tree, id: Option<u32>, name: &[u8]) -> Option<u32> {
    let node = tree.nodes[*id.as_ref()? as usize];
    if node.tag != 7 {
        return None;
    }
    // JSON object semantics: the last occurrence wins, including escaped keys.
    tree.children[node.aux as usize..node.aux as usize + node.bits as usize]
        .chunks_exact(2)
        .rev()
        .find_map(|pair| {
            let key = tree.nodes[pair[0] as usize];
            let equal = if key.tag == 11 {
                &tree.strings8[key.aux as usize..key.aux as usize + key.bits as usize] == name
            } else {
                key.tag == 5
                    && key.bits as usize == name.len()
                    && tree.strings[key.aux as usize..key.aux as usize + name.len()]
                        .iter()
                        .zip(name)
                        .all(|(&a, &b)| a == b as u16)
            };
            equal.then_some(pair[1])
        })
}

impl Fields {
    fn configure(&mut self, bytes: &[u8]) -> Result<(), i32> {
        let mut offset = 0;
        fn word(bytes: &[u8], offset: &mut usize) -> Result<usize, i32> {
            let end = offset.checked_add(4).ok_or(2)?;
            let value = u32::from_le_bytes(bytes.get(*offset..end).ok_or(2)?.try_into().unwrap());
            *offset = end;
            Ok(value as usize)
        }
        let count = word(bytes, &mut offset)?;
        if count > 1_000_000 {
            return Err(3);
        }
        let mut ids = HashMap::with_capacity(count);
        for index in 0..count {
            let length = word(bytes, &mut offset)?;
            let end = offset
                .checked_add(length.checked_mul(2).ok_or(2)?)
                .ok_or(2)?;
            let key = bytes
                .get(offset..end)
                .ok_or(2)?
                .chunks_exact(2)
                .map(|c| u16::from_le_bytes([c[0], c[1]]))
                .collect();
            if ids.insert(key, index).is_some() {
                return Err(2);
            }
            offset = end;
        }
        if offset != bytes.len() {
            return Err(2);
        }
        self.ids = ids;
        self.output = vec![0.0; count * 4];
        self.unknown.clear();
        Ok(())
    }

    fn map(&mut self, tree: &Tree, id: Option<u32>, column: usize) -> usize {
        let Some(node) = id.map(|id| tree.nodes[id as usize]).filter(|n| n.tag == 7) else {
            return 0;
        };
        self.unknown.clear();
        let mut valid = 0usize;
        for pair in
            tree.children[node.aux as usize..node.aux as usize + node.bits as usize].chunks_exact(2)
        {
            units(tree, tree.nodes[pair[0] as usize], &mut self.key);
            let value = number(
                tree,
                tree.nodes[pair[1] as usize],
                &mut self.text,
                &mut self.ascii,
            );
            if let Some(&index) = self.ids.get(&self.key) {
                let offset = index * 4 + column;
                if self.output[offset] != 0.0 {
                    valid -= 1;
                }
                self.output[offset] = if value.is_some() { 1.0 } else { 0.0 };
                self.output[offset + 1] = value.unwrap_or(f64::NAN);
            } else if self.unknown.insert(self.key.clone(), value.is_some()) == Some(true) {
                valid -= 1;
            }
            if value.is_some() {
                valid += 1;
            }
        }
        self.unknown.clear();
        valid
    }

    fn extract(&mut self, tree: &Tree) -> usize {
        for row in self.output.chunks_exact_mut(4) {
            row.copy_from_slice(&[0.0, f64::NAN, 0.0, f64::NAN]);
        }
        let data = field(tree, Some(0), b"data");
        let pga = field(tree, data, b"pga");
        let pgv = field(tree, data, b"pgv");
        let count = self.map(tree, field(tree, pga, b"dataVals"), 0);
        self.map(tree, field(tree, pgv, b"dataVals"), 2);
        count
    }
}

#[no_mangle]
pub extern "C" fn rq_palert_values_abi_version() -> u32 {
    1
}
#[no_mangle]
pub extern "C" fn rq_palert_values_calls() -> u64 {
    CALLS.load(Ordering::Relaxed)
}
#[no_mangle]
pub unsafe extern "C" fn rq_palert_values_configure(
    owner: *mut c_void,
    input: *const u8,
    length: usize,
) -> i32 {
    if owner.is_null() || input.is_null() {
        return 1;
    }
    if length > super::LIMIT {
        return 3;
    }
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        unsafe { &mut *owner.cast::<Tree>() }
            .palert
            .configure(unsafe { std::slice::from_raw_parts(input, length) })
    }))
    .map_or(5, |r| r.err().unwrap_or(0))
}
#[no_mangle]
pub unsafe extern "C" fn rq_palert_values_extract(
    owner: *mut c_void,
    output: *mut *const f64,
    valid_pga: *mut usize,
) -> i32 {
    if owner.is_null() || output.is_null() || valid_pga.is_null() {
        return 1;
    }
    let tree = unsafe { &mut *owner.cast::<Tree>() };
    if tree.nodes.is_empty() {
        return 2;
    }
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let mut fields = std::mem::take(&mut tree.palert);
        let valid = fields.extract(tree);
        tree.palert = fields;
        unsafe {
            *output = tree.palert.output.as_ptr();
            *valid_pga = valid;
        }
        CALLS.fetch_add(1, Ordering::Relaxed);
    }))
    .map_or(5, |_| 0)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn duplicates_strings_unknown_and_original_tree() {
        let mut tree = Tree::default();
        tree.decode_input::<_, false>(br#"{"data":{"pga":{"dataVals":{"a":80,"\u0061":"-.0","x":1,"x":false}},"pgv":{"dataVals":{"a":" +.12e-9\u0085"}}}}"#).unwrap();
        let original = tree.output.clone();
        let mut fields = Fields::default();
        fields.configure(&[1, 0, 0, 0, 1, 0, 0, 0, 97, 0]).unwrap();
        assert_eq!(fields.extract(&tree), 1);
        assert_eq!(fields.output[1].to_bits(), (-0.0f64).to_bits());
        assert_eq!(fields.output[3], 1.2e-10);
        assert_eq!(tree.output, original);
        assert!(fields.configure(&[1, 0, 0, 0]).is_err());
        assert_eq!(fields.ids.len(), 1);
    }
}
