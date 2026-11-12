//! Original UTF-8/UTF-16 JSON to an owned tree, without field selection.
mod ingress;
#[path = "packed_replay.rs"]
mod packed_replay;
mod palert_values;
pub(crate) use packed_replay::{pack_table, unpack_value};
use std::{
    collections::{hash_map::RandomState, HashMap},
    ffi::c_void,
    hash::{BuildHasher, Hasher},
    sync::atomic::{AtomicU64, Ordering},
};
const LIMIT: usize = 64 * 1024 * 1024;
const NODES: usize = 2_000_000;
/// Direct writer for native-prepared views. Containers reserve their node before
/// writing children, so the root stays node zero without an intermediate DOM.
pub(crate) struct ViewPacker(Tree);
impl ViewPacker {
    pub fn new() -> Self {
        Self(Tree::default())
    }
    pub fn reserve(&mut self) -> u32 {
        let id = self.0.nodes.len() as u32;
        self.0.nodes.push(Node::default());
        id
    }
    pub fn text(&mut self, value: &str) -> u32 {
        if let Some(&id) = self.0.api_keys.get(value.as_bytes()) {
            return id;
        }
        let id = self.reserve();
        let offset = self.0.strings8.len();
        self.0.strings8.extend_from_slice(value.as_bytes());
        self.0.nodes[id as usize] = Node {
            tag: 11,
            aux: offset as u32,
            bits: value.len() as u64,
        };
        self.0.api_keys.insert(value.as_bytes().to_vec(), id);
        id
    }
    pub fn int(&mut self, value: i64) -> u32 {
        let id = self.reserve();
        self.0.nodes[id as usize] = Node {
            tag: 3,
            aux: 0,
            bits: value as u64,
        };
        id
    }
    pub fn double(&mut self, value: f64) -> u32 {
        let id = self.reserve();
        self.0.nodes[id as usize] = Node {
            tag: 4,
            aux: 0,
            bits: value.to_bits(),
        };
        id
    }
    pub fn boolean(&mut self, value: bool) -> u32 {
        let id = self.reserve();
        self.0.nodes[id as usize].tag = if value { 2 } else { 1 };
        id
    }
    pub fn array(&mut self, id: u32, children: Vec<u32>) {
        let start = self.0.children.len();
        let len = children.len();
        self.0.children.extend(children);
        self.0.nodes[id as usize] = Node {
            tag: 6,
            aux: start as u32,
            bits: len as u64,
        };
    }
    pub fn object(&mut self, id: u32, mut entries: Vec<(&str, u32)>) {
        // Match the canonical serde_json map order used by existing archives.
        entries.sort_unstable_by(|a, b| a.0.cmp(b.0));
        let mut children = Vec::with_capacity(entries.len() * 2);
        for (key, value) in entries {
            children.push(self.text(key));
            children.push(value);
        }
        let start = self.0.children.len();
        let len = children.len();
        self.0.children.extend(children);
        self.0.nodes[id as usize] = Node {
            tag: 7,
            aux: start as u32,
            bits: len as u64,
        };
    }
    pub fn finish(self) -> Vec<u8> {
        let tree = self.0;
        let base = 24 + tree.nodes.len() * 16 + tree.children.len() * 4 + tree.strings8.len();
        let mut out = Vec::with_capacity((base + 7) & !7);
        for n in [
            tree.nodes.len() as u32 | 0x80000000,
            tree.children.len() as u32,
            0,
            0,
            tree.strings8.len() as u32,
            0,
        ] {
            out.extend_from_slice(&n.to_le_bytes());
        }
        for n in tree.nodes {
            out.extend_from_slice(&n.tag.to_le_bytes());
            out.extend_from_slice(&n.aux.to_le_bytes());
            out.extend_from_slice(&n.bits.to_le_bytes());
        }
        for n in tree.children {
            out.extend_from_slice(&n.to_le_bytes());
        }
        out.extend(tree.strings8);
        out.resize((base + 7) & !7, 0);
        out
    }
}
static SESSIONS: AtomicU64 = AtomicU64::new(0);
static CALLS: AtomicU64 = AtomicU64::new(0);
/// Pack an already-owned native JSON value. This does not serialize/reparse
/// UTF-8, and the caller can pass the immutable tree straight to a UI view.
pub(crate) fn pack_value(value: &serde_json::Value) -> Vec<u8> {
    fn text(tree: &mut Tree, value: &str) -> u32 {
        if let Some(&id) = tree.api_keys.get(value.as_bytes()) {
            return id;
        }
        let id = tree.nodes.len() as u32;
        let offset = tree.strings8.len();
        tree.strings8.extend_from_slice(value.as_bytes());
        tree.nodes.push(Node {
            tag: 11,
            aux: offset as u32,
            bits: value.len() as u64,
        });
        tree.api_keys.insert(value.as_bytes().to_vec(), id);
        id
    }
    fn write(tree: &mut Tree, value: &serde_json::Value) -> u32 {
        use serde_json::Value;
        if let Value::String(s) = value {
            return text(tree, s);
        }
        let id = tree.nodes.len() as u32;
        tree.nodes.push(Node::default());
        let node = match value {
            Value::Null => Node::default(),
            Value::Bool(b) => Node {
                tag: if *b { 2 } else { 1 },
                ..Default::default()
            },
            Value::Number(n) => {
                if let Some(i) = n.as_i64() {
                    Node {
                        tag: 3,
                        aux: 0,
                        bits: i as u64,
                    }
                } else {
                    Node {
                        tag: 4,
                        aux: 0,
                        bits: n.as_f64().unwrap().to_bits(),
                    }
                }
            }
            Value::Array(rows) => {
                let children = rows.iter().map(|v| write(tree, v)).collect::<Vec<_>>();
                let start = tree.children.len();
                tree.children.extend(children);
                Node {
                    tag: 6,
                    aux: start as u32,
                    bits: rows.len() as u64,
                }
            }
            Value::Object(map) => {
                let mut children = Vec::with_capacity(map.len() * 2);
                for (k, v) in map {
                    children.push(text(tree, k));
                    children.push(write(tree, v));
                }
                let start = tree.children.len();
                tree.children.extend(children);
                Node {
                    tag: 7,
                    aux: start as u32,
                    bits: map.len() as u64 * 2,
                }
            }
            Value::String(_) => unreachable!(),
        };
        tree.nodes[id as usize] = node;
        id
    }
    let mut tree = Tree::default();
    write(&mut tree, value);
    let base = 24 + tree.nodes.len() * 16 + tree.children.len() * 4 + tree.strings8.len();
    let mut out = Vec::with_capacity((base + 7) & !7);
    for value in [
        tree.nodes.len() as u32 | 0x80000000,
        tree.children.len() as u32,
        0,
        0,
        tree.strings8.len() as u32,
        0,
    ] {
        out.extend_from_slice(&value.to_le_bytes());
    }
    for n in tree.nodes {
        out.extend_from_slice(&n.tag.to_le_bytes());
        out.extend_from_slice(&n.aux.to_le_bytes());
        out.extend_from_slice(&n.bits.to_le_bytes());
    }
    for n in tree.children {
        out.extend_from_slice(&n.to_le_bytes());
    }
    out.extend(tree.strings8);
    out.resize((base + 7) & !7, 0);
    out
}
#[repr(C)]
#[derive(Default, Clone, Copy)]
struct Node {
    tag: u32,
    aux: u32,
    bits: u64,
}
#[derive(Default)]
struct Tree {
    sse: ingress::SseLines,
    palert: palert_values::Fields,
    nodes: Vec<Node>,
    children: Vec<u32>,
    child_scratch: Vec<Vec<u32>>,
    strings: Vec<u16>,
    strings8: Vec<u8>,
    api_keys: HashMap<Vec<u8>, u32>,
    numbers: Vec<f64>,
    output: Vec<u8>,
    numeric_index: HashMap<(u32, u64), u32, NumericHash>,
    literal_cache: HashMap<(u32, u64), (Node, u32), NumericHash>,
    pending_literal: Option<(u32, u64)>,
    cached_index: Option<u32>,
    numeric_enabled: bool,
    literal_enabled: bool,
    numeric_seen: usize,
    literal_seen: usize,
    literal_misses: usize,
    last_index: Option<(u32, u64, u32)>,
    tokens: usize,
}
trait CodeUnit: Copy {
    const UTF8: bool;
    fn unit(self) -> u16;
}
impl CodeUnit for u8 {
    const UTF8: bool = true;
    fn unit(self) -> u16 {
        self as u16
    }
}
impl CodeUnit for u16 {
    const UTF8: bool = false;
    fn unit(self) -> u16 {
        self
    }
}
struct NumericHash(u64);
impl Default for NumericHash {
    fn default() -> Self {
        Self(RandomState::new().hash_one(0u64))
    }
}
struct NumericHasher(u64);
impl BuildHasher for NumericHash {
    type Hasher = NumericHasher;
    fn build_hasher(&self) -> NumericHasher {
        NumericHasher(self.0)
    }
}
impl Hasher for NumericHasher {
    fn finish(&self) -> u64 {
        let mut x = self.0;
        x = (x ^ (x >> 30)).wrapping_mul(0xbf58476d1ce4e5b9);
        x = (x ^ (x >> 27)).wrapping_mul(0x94d049bb133111eb);
        x ^ (x >> 31)
    }
    fn write(&mut self, bytes: &[u8]) {
        for b in bytes {
            self.0 = self.0.rotate_left(7) ^ *b as u64;
        }
    }
    fn write_u32(&mut self, n: u32) {
        self.0 = self.0.rotate_left(17) ^ n as u64;
    }
    fn write_u64(&mut self, n: u64) {
        self.0 = self.0.rotate_left(23) ^ n;
    }
}
struct Parser<'a, T: CodeUnit, const STATION: bool> {
    input: &'a [T],
    offset: usize,
    tree: &'a mut Tree,
}
type Result<T> = std::result::Result<T, i32>;
impl<T: CodeUnit, const STATION: bool> Parser<'_, T, STATION> {
    fn peek(&self) -> u16 {
        self.input
            .get(self.offset)
            .map(|v| v.unit())
            .unwrap_or(0xffff)
    }
    fn white(&mut self) {
        while matches!(self.peek(), 9 | 10 | 13 | 32) {
            self.offset += 1;
        }
    }
    fn eat(&mut self, byte: u16) -> Result<()> {
        if self.peek() != byte {
            return Err(2);
        }
        self.offset += 1;
        Ok(())
    }
    fn literal(&mut self, text: &[u16]) -> Result<()> {
        if !text
            .iter()
            .enumerate()
            .all(|(i, c)| self.input.get(self.offset + i).map(|v| v.unit()) == Some(*c))
        {
            return Err(2);
        }
        self.offset += text.len();
        Ok(())
    }
    fn string(&mut self) -> Result<Node> {
        self.eat(34)?;
        if !STATION && T::UTF8 {
            let start = self.offset;
            // Input UTF-8 has already been validated. Unescaped content is
            // copied once as original bytes; unused API strings stay encoded.
            let bytes = unsafe {
                std::slice::from_raw_parts(self.input.as_ptr().cast::<u8>(), self.input.len())
            };
            let end = bytes[start..]
                .iter()
                .position(|c| *c == 34 || *c == 92 || *c < 32)
                .map(|length| start + length)
                .ok_or(2)?;
            if bytes[end] == 34 {
                let offset = self.tree.strings8.len();
                self.tree.strings8.extend_from_slice(&bytes[start..end]);
                self.offset = end + 1;
                return Ok(Node {
                    tag: 11,
                    aux: offset as u32,
                    bits: (end - start) as u64,
                });
            }
        }
        let start = self.tree.strings.len();
        loop {
            let c = self.peek();
            self.offset += 1;
            match c {
                34 => break,
                0..=31 => return Err(2),
                92 => {
                    let escape = self.peek();
                    self.offset += 1;
                    let decoded = match escape {
                        34 | 47 | 92 => escape,
                        98 => 8,
                        102 => 12,
                        110 => 10,
                        114 => 13,
                        116 => 9,
                        117 => {
                            let mut value = 0u16;
                            for _ in 0..4 {
                                let digit = match self.peek() {
                                    n @ 48..=57 => n - 48,
                                    n @ 65..=70 => n - 65 + 10,
                                    n @ 97..=102 => n - 97 + 10,
                                    _ => return Err(2),
                                };
                                value = (value << 4) | digit;
                                self.offset += 1;
                            }
                            value
                        }
                        _ => return Err(2),
                    };
                    self.tree.strings.push(decoded);
                }
                _ if self.offset > self.input.len() => return Err(2),
                _ => {
                    if T::UTF8 {
                        if c >= 128 {
                            // decode_utf8 validated the complete source first.
                            let width = if c >= 0xf0 {
                                4
                            } else if c >= 0xe0 {
                                3
                            } else {
                                2
                            };
                            let mut scalar = (c & (0x7f >> width)) as u32;
                            for b in &self.input[self.offset..self.offset + width - 1] {
                                scalar = (scalar << 6) | (b.unit() & 0x3f) as u32;
                            }
                            self.offset += width - 1;
                            if scalar > 0xffff {
                                let value = scalar - 0x10000;
                                self.tree.strings.push(0xd800 | (value >> 10) as u16);
                                self.tree.strings.push(0xdc00 | (value & 0x3ff) as u16);
                            } else {
                                self.tree.strings.push(scalar as u16);
                            }
                            continue;
                        }
                    }
                    self.tree.strings.push(c);
                }
            }
        }
        Ok(Node {
            tag: 5,
            aux: start as u32,
            bits: (self.tree.strings.len() - start) as u64,
        })
    }
    fn number(&mut self) -> Result<Node> {
        self.tree.pending_literal = None;
        self.tree.cached_index = None;
        let start = self.offset;
        if self.peek() == 45 {
            self.offset += 1;
        }
        match self.peek() {
            48 => self.offset += 1,
            49..=57 => {
                while matches!(self.peek(), 48..=57) {
                    self.offset += 1;
                }
            }
            _ => return Err(2),
        }
        let mut integral = true;
        if self.peek() == 46 {
            integral = false;
            self.offset += 1;
            if !matches!(self.peek(), 48..=57) {
                return Err(2);
            }
            while matches!(self.peek(), 48..=57) {
                self.offset += 1;
            }
        }
        if matches!(self.peek(), 69 | 101) {
            integral = false;
            self.offset += 1;
            if matches!(self.peek(), 43 | 45) {
                self.offset += 1;
            }
            if !matches!(self.peek(), 48..=57) {
                return Err(2);
            }
            while matches!(self.peek(), 48..=57) {
                self.offset += 1;
            }
        }
        if integral {
            if T::UTF8 {
                let bytes = unsafe {
                    std::slice::from_raw_parts(
                        self.input.as_ptr().add(start).cast::<u8>(),
                        self.offset - start,
                    )
                };
                // The token scanner accepted ASCII digits/sign only.
                if let Ok(value) = unsafe { std::str::from_utf8_unchecked(bytes) }.parse::<i64>() {
                    return Ok(Node {
                        tag: 3,
                        aux: 0,
                        bits: value as u64,
                    });
                }
            }
            let negative = self.input[start].unit() == 45;
            let mut value = Some(0i64);
            for i in start + usize::from(negative)..self.offset {
                let c = self.input[i].unit();
                value = value.and_then(|v| v.checked_mul(10)).and_then(|v| {
                    if negative {
                        v.checked_sub((c - 48) as i64)
                    } else {
                        v.checked_add((c - 48) as i64)
                    }
                });
            }
            if let Some(value) = value {
                let node = Node {
                    tag: 3,
                    aux: 0,
                    bits: value as u64,
                };
                return Ok(node);
            }
        }
        // Cache only exact short floating literals, never rounded values.
        let length = self.offset - start;
        if self.tree.literal_enabled && length <= 8 {
            let mut word = 0u64;
            for i in 0..length {
                word |= (self.input[start + i].unit() as u64) << (i * 8);
            }
            let key = (length as u32, word);
            self.tree.literal_seen += 1;
            if let Some((node, id)) = self.tree.literal_cache.get(&key) {
                self.tree.cached_index = Some(*id);
                return Ok(*node);
            }
            self.tree.literal_misses += 1;
            if self.tree.literal_seen >= 128
                && self.tree.literal_misses * 10 >= self.tree.literal_seen * 9
            {
                self.tree.literal_enabled = false;
                self.tree.literal_cache.clear();
            } else {
                self.tree.pending_literal = Some(key);
            }
        }
        // Numeric tokens are ASCII. Ordinary floats do not allocate per token.
        let mut stack = [0u8; 128];
        let heap;
        let length = self.offset - start;
        let bytes = if T::UTF8 {
            // This monomorphized branch exists only for u8 (one byte/unit).
            unsafe {
                std::slice::from_raw_parts(self.input.as_ptr().add(start).cast::<u8>(), length)
            }
        } else if length <= stack.len() {
            for (i, byte) in stack[..length].iter_mut().enumerate() {
                *byte = self.input[start + i].unit() as u8;
            }
            &stack[..length]
        } else {
            heap = (start..self.offset)
                .map(|i| self.input[i].unit() as u8)
                .collect::<Vec<_>>();
            &heap
        };
        let text = std::str::from_utf8(&bytes).map_err(|_| 2)?;
        let value = text.parse::<f64>().map_err(|_| 2)?;
        let node = Node {
            tag: 4,
            aux: 0,
            bits: value.to_bits(),
        };
        Ok(node)
    }
    fn value(&mut self, depth: usize, is_key: bool) -> Result<u32> {
        self.white();
        if depth > 512 || self.tree.tokens >= NODES {
            return Err(3);
        }
        self.tree.tokens += 1;
        if matches!(self.peek(), 45 | 48..=57) {
            let node = self.number()?;
            if !STATION {
                let id = self.tree.nodes.len() as u32;
                self.tree.nodes.push(node);
                return Ok(id);
            }
            self.tree.numeric_seen += 1;
            let key = (node.tag, node.bits);
            let previous = self
                .tree
                .last_index
                .filter(|(tag, bits, _)| *tag == node.tag && *bits == node.bits)
                .map(|(_, _, id)| id);
            let id = if let Some(id) = self.tree.cached_index.or(previous) {
                id
            } else if !self.tree.numeric_enabled {
                let id = self.tree.nodes.len() as u32;
                self.tree.nodes.push(node);
                id
            } else if let Some(id) = self.tree.numeric_index.get(&key) {
                *id
            } else {
                let id = self.tree.nodes.len() as u32;
                self.tree.nodes.push(node);
                self.tree.numeric_index.insert(key, id);
                id
            };
            if self.tree.numeric_seen == 128 && self.tree.numeric_index.len() * 10 >= 128 * 9 {
                self.tree.numeric_enabled = false;
                self.tree.numeric_index.clear();
            }
            if let Some(key) = self.tree.pending_literal.take() {
                self.tree.literal_cache.insert(key, (node, id));
            }
            self.tree.last_index = Some((node.tag, node.bits, id));
            return Ok(id);
        }
        let id = self.tree.nodes.len() as u32;
        self.tree.nodes.push(Node::default());
        let node = match self.peek() {
            110 => {
                self.literal(&[110, 117, 108, 108])?;
                Node::default()
            }
            102 => {
                self.literal(&[102, 97, 108, 115, 101])?;
                Node {
                    tag: 1,
                    ..Node::default()
                }
            }
            116 => {
                self.literal(&[116, 114, 117, 101])?;
                Node {
                    tag: 2,
                    ..Node::default()
                }
            }
            34 => self.string()?,
            open @ (91 | 123) => {
                self.offset += 1;
                let map = open == 123;
                let close = if map { 125 } else { 93 };
                if self.tree.child_scratch.len() <= depth {
                    self.tree.child_scratch.resize_with(depth + 1, Vec::new);
                }
                let mut children = std::mem::take(&mut self.tree.child_scratch[depth]);
                children.clear();
                self.white();
                if self.peek() != close {
                    loop {
                        if map {
                            self.white();
                            if self.peek() != 34 {
                                return Err(2);
                            }
                            children.push(self.value(depth + 1, true)?);
                            self.white();
                            self.eat(58)?;
                        }
                        children.push(self.value(depth + 1, false)?);
                        self.white();
                        if self.peek() != 44 {
                            break;
                        }
                        self.offset += 1;
                    }
                }
                self.eat(close)?;
                let start = self.tree.children.len();
                if !map
                    && !children.is_empty()
                    && children
                        .iter()
                        .all(|i| matches!(self.tree.nodes[*i as usize].tag, 3 | 4))
                {
                    if !STATION {
                        // Generic API arrays retain original numeric nodes,
                        // without a second, station-specific Float64 pool.
                        self.tree.nodes[id as usize] = Node {
                            tag: 10,
                            aux: children[0],
                            bits: children.len() as u64,
                        };
                        self.tree.child_scratch[depth] = children;
                        return Ok(id);
                    }
                    let number_start = self.tree.numbers.len();
                    self.tree
                        .numbers
                        .extend_from_slice(&[f64::INFINITY, f64::NEG_INFINITY, 1.0]);
                    let mut contiguous = true;
                    for (offset, i) in children.iter().enumerate() {
                        contiguous &= *i == children[0] + offset as u32;
                        let node = self.tree.nodes[*i as usize];
                        let value = if node.tag == 3 {
                            node.bits as i64 as f64
                        } else {
                            f64::from_bits(node.bits)
                        };
                        self.tree.numbers[number_start] =
                            self.tree.numbers[number_start].min(value);
                        self.tree.numbers[number_start + 1] =
                            self.tree.numbers[number_start + 1].max(value);
                        if !value.is_finite() {
                            self.tree.numbers[number_start + 2] = 0.0;
                        }
                        self.tree.numbers.push(value);
                    }
                    if !contiguous {
                        self.tree.children.extend_from_slice(&children);
                    }
                    return {
                        self.tree.nodes[id as usize] = Node {
                            tag: if contiguous { 9 } else { 8 },
                            aux: if contiguous {
                                children[0]
                            } else {
                                start as u32
                            },
                            bits: children.len() as u64 | ((number_start as u64) << 32),
                        };
                        self.tree.child_scratch[depth] = children;
                        Ok(id)
                    };
                }
                self.tree.children.extend_from_slice(&children);
                let node = Node {
                    tag: if map { 7 } else { 6 },
                    aux: start as u32,
                    bits: children.len() as u64,
                };
                self.tree.child_scratch[depth] = children;
                node
            }
            _ => return Err(2),
        };
        if !STATION && is_key && node.tag == 11 {
            let start = node.aux as usize;
            let end = start + node.bits as usize;
            let key = &self.tree.strings8[start..end];
            if let Some(existing) = self.tree.api_keys.get(key).copied() {
                self.tree.nodes.pop();
                self.tree.strings8.truncate(start);
                return Ok(existing);
            }
            if self.tree.api_keys.len() < 4096 {
                self.tree.api_keys.insert(key.to_vec(), id);
            }
        }
        self.tree.nodes[id as usize] = node;
        Ok(id)
    }
}
impl Tree {
    fn decode_utf8(&mut self, bytes: &[u8]) -> Result<()> {
        std::str::from_utf8(bytes).map_err(|_| 2)?;
        self.decode_input::<_, true>(bytes)
    }
    fn decode(&mut self, input: &[u16]) -> Result<()> {
        self.decode_input::<_, true>(input)
    }
    fn decode_input<T: CodeUnit, const STATION: bool>(&mut self, input: &[T]) -> Result<()> {
        self.numeric_index.clear();
        self.literal_cache.clear();
        self.pending_literal = None;
        self.cached_index = None;
        self.numeric_enabled = STATION;
        self.literal_enabled = STATION;
        self.numeric_seen = 0;
        self.literal_seen = 0;
        self.literal_misses = 0;
        self.last_index = None;
        self.tokens = 0;
        self.nodes.clear();
        self.children.clear();
        self.strings.clear();
        self.strings8.clear();
        self.api_keys.clear();
        self.numbers.clear();
        self.output.clear();
        let mut parser = Parser::<_, STATION> {
            input,
            offset: 0,
            tree: self,
        };
        parser.value(0, false)?;
        parser.white();
        if parser.offset != input.len() {
            return Err(2);
        }
        let header = if STATION { 16 } else { 24 };
        let base = header
            + self.nodes.len() * 16
            + self.children.len() * 4
            + self.strings.len() * 2
            + self.strings8.len();
        let length = ((base + 7) & !7) + self.numbers.len() * 8;
        if length > LIMIT {
            return Err(3);
        }
        self.output.reserve(length);
        for n in [
            self.nodes.len() | if STATION { 0 } else { 0x80000000 },
            self.children.len(),
            self.strings.len(),
            self.numbers.len(),
        ] {
            self.output.extend_from_slice(&(n as u32).to_le_bytes());
        }
        if !STATION {
            self.output
                .extend_from_slice(&(self.strings8.len() as u32).to_le_bytes());
            self.output.extend_from_slice(&0u32.to_le_bytes());
        }
        #[cfg(target_endian = "little")]
        // Node is repr(C), exactly 16 initialized bytes (4+4+8, no padding).
        unsafe {
            self.output.extend_from_slice(std::slice::from_raw_parts(
                self.nodes.as_ptr().cast::<u8>(),
                self.nodes.len() * 16,
            ));
        }
        #[cfg(not(target_endian = "little"))]
        for n in &self.nodes {
            self.output.extend_from_slice(&n.tag.to_le_bytes());
            self.output.extend_from_slice(&n.aux.to_le_bytes());
            self.output.extend_from_slice(&n.bits.to_le_bytes());
        }
        #[cfg(target_endian = "little")]
        unsafe {
            self.output.extend_from_slice(std::slice::from_raw_parts(
                self.children.as_ptr().cast::<u8>(),
                self.children.len() * 4,
            ));
            self.output.extend_from_slice(std::slice::from_raw_parts(
                self.strings.as_ptr().cast::<u8>(),
                self.strings.len() * 2,
            ));
        }
        #[cfg(not(target_endian = "little"))]
        {
            for n in &self.children {
                self.output.extend_from_slice(&n.to_le_bytes());
            }
            for n in &self.strings {
                self.output.extend_from_slice(&n.to_le_bytes());
            }
        }
        self.output.extend_from_slice(&self.strings8);
        self.output.resize((base + 7) & !7, 0);
        for n in &self.numbers {
            self.output.extend_from_slice(&n.to_bits().to_le_bytes());
        }
        Ok(())
    }
}
#[no_mangle]
pub extern "C" fn rq_station_json_abi_version() -> u32 {
    2
}
#[no_mangle]
pub extern "C" fn rq_station_json_sessions() -> u64 {
    SESSIONS.load(Ordering::Relaxed)
}
#[no_mangle]
pub extern "C" fn rq_station_json_calls() -> u64 {
    CALLS.load(Ordering::Relaxed)
}
#[no_mangle]
pub extern "C" fn rq_station_json_create() -> *mut c_void {
    SESSIONS.fetch_add(1, Ordering::Relaxed);
    Box::into_raw(Box::<Tree>::default()).cast()
}
/// # Safety
/// Live exclusive owner, immutable input[length], disjoint output[1]/size[1].
/// Output is borrowed until next decode/destroy, and must be copied before then.
#[no_mangle]
pub unsafe extern "C" fn rq_station_json_decode(
    owner: *mut c_void,
    input: *const u16,
    length: usize,
    output: *mut *const u8,
    size: *mut usize,
) -> i32 {
    if owner.is_null() || output.is_null() || size.is_null() || (length > 0 && input.is_null()) {
        return 1;
    }
    unsafe {
        *output = std::ptr::null();
        *size = 0;
    }
    if length > LIMIT / 2 {
        return 3;
    }
    std::panic::catch_unwind(|| unsafe {
        let tree = &mut *owner.cast::<Tree>();
        let text = if length == 0 {
            &[]
        } else {
            std::slice::from_raw_parts(input, length)
        };
        match tree.decode(text) {
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
/// # Safety
/// Same ownership as UTF-16 decode; input is length immutable UTF-8 bytes.
#[no_mangle]
pub unsafe extern "C" fn rq_station_json_decode_utf8(
    owner: *mut c_void,
    input: *const u8,
    length: usize,
    output: *mut *const u8,
    size: *mut usize,
) -> i32 {
    if owner.is_null() || output.is_null() || size.is_null() || (length > 0 && input.is_null()) {
        return 1;
    }
    unsafe {
        *output = std::ptr::null();
        *size = 0;
    }
    if length > LIMIT {
        return 3;
    }
    std::panic::catch_unwind(|| unsafe {
        let tree = &mut *owner.cast::<Tree>();
        let bytes = if length == 0 {
            &[]
        } else {
            std::slice::from_raw_parts(input, length)
        };
        match tree.decode_utf8(bytes) {
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
unsafe fn decode_api<const UTF8: bool>(
    owner: *mut c_void,
    input: *const c_void,
    length: usize,
    output: *mut *const u8,
    size: *mut usize,
) -> i32 {
    if owner.is_null() || output.is_null() || size.is_null() || (length > 0 && input.is_null()) {
        return 1;
    }
    unsafe {
        *output = std::ptr::null();
        *size = 0;
    }
    if length > LIMIT / if UTF8 { 1 } else { 2 } {
        return 3;
    }
    std::panic::catch_unwind(|| unsafe {
        let tree = &mut *owner.cast::<Tree>();
        let result = if UTF8 {
            let bytes = if length == 0 {
                &[]
            } else {
                std::slice::from_raw_parts(input.cast::<u8>(), length)
            };
            std::str::from_utf8(bytes)
                .map_err(|_| 2)
                .and_then(|_| tree.decode_input::<_, false>(bytes))
        } else {
            let units = if length == 0 {
                &[]
            } else {
                std::slice::from_raw_parts(input.cast::<u16>(), length)
            };
            tree.decode_input::<_, false>(units)
        };
        match result {
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

/// # Safety
/// Same immutable input/borrowed output ownership as station decode.
#[no_mangle]
pub unsafe extern "C" fn rq_api_json_decode(
    owner: *mut c_void,
    input: *const u16,
    length: usize,
    output: *mut *const u8,
    size: *mut usize,
) -> i32 {
    unsafe { decode_api::<false>(owner, input.cast(), length, output, size) }
}

/// # Safety
/// Same ownership; input is length immutable UTF-8 bytes.
#[no_mangle]
pub unsafe extern "C" fn rq_api_json_decode_utf8(
    owner: *mut c_void,
    input: *const u8,
    length: usize,
    output: *mut *const u8,
    size: *mut usize,
) -> i32 {
    unsafe { decode_api::<true>(owner, input.cast(), length, output, size) }
}

#[no_mangle]
pub extern "C" fn rq_json_envelope_abi_version() -> u32 {
    1
}

unsafe fn decode_wrapped<const UTF8: bool>(
    owner: *mut c_void,
    input: *const c_void,
    length: usize,
    kind: u32,
    name: *const c_void,
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
    if length > isize::MAX as usize / if UTF8 { 1 } else { 2 }
        || name_length > isize::MAX as usize / if UTF8 { 1 } else { 2 }
    {
        return 3;
    }
    std::panic::catch_unwind(|| unsafe {
        if UTF8 {
            let bytes = if length == 0 {
                &[]
            } else {
                std::slice::from_raw_parts(input.cast::<u8>(), length)
            };
            if std::str::from_utf8(bytes).is_err() {
                return 2;
            }
            let bytes = bytes.strip_prefix(&[0xef, 0xbb, 0xbf]).unwrap_or(bytes);
            let name = if name_length == 0 {
                &[]
            } else {
                std::slice::from_raw_parts(name.cast::<u8>(), name_length)
            };
            match crate::json_envelope::range(bytes, kind, name) {
                Ok((a, b)) => {
                    decode_api::<true>(owner, bytes.as_ptr().add(a).cast(), b - a, output, size)
                }
                Err(status) => status,
            }
        } else {
            let units = if length == 0 {
                &[]
            } else {
                std::slice::from_raw_parts(input.cast::<u16>(), length)
            };
            let name = if name_length == 0 {
                &[]
            } else {
                std::slice::from_raw_parts(name.cast::<u16>(), name_length)
            };
            match crate::json_envelope::range(units, kind, name) {
                Ok((a, b)) => {
                    decode_api::<false>(owner, units.as_ptr().add(a).cast(), b - a, output, size)
                }
                Err(status) => status,
            }
        }
    })
    .unwrap_or(5)
}

/// # Safety
/// Same owner/output as API JSON. Input and selector are immutable UTF-8 byte
/// buffers valid for the synchronous call. No reference to either is retained.
#[no_mangle]
pub unsafe extern "C" fn rq_api_json_wrapped_utf8(
    owner: *mut c_void,
    input: *const u8,
    length: usize,
    kind: u32,
    name: *const u8,
    name_length: usize,
    output: *mut *const u8,
    size: *mut usize,
) -> i32 {
    unsafe {
        decode_wrapped::<true>(
            owner,
            input.cast(),
            length,
            kind,
            name.cast(),
            name_length,
            output,
            size,
        )
    }
}

/// # Safety
/// Same contract, with aligned immutable UTF-16 code units. Lone surrogates
/// remain literal code units, matching Dart String and the existing JSON ABI.
#[no_mangle]
pub unsafe extern "C" fn rq_api_json_wrapped_utf16(
    owner: *mut c_void,
    input: *const u16,
    length: usize,
    kind: u32,
    name: *const u16,
    name_length: usize,
    output: *mut *const u8,
    size: *mut usize,
) -> i32 {
    unsafe {
        decode_wrapped::<false>(
            owner,
            input.cast(),
            length,
            kind,
            name.cast(),
            name_length,
            output,
            size,
        )
    }
}

/// # Safety
/// Destroy an idle owner created here exactly once.
#[no_mangle]
pub unsafe extern "C" fn rq_station_json_destroy(owner: *mut c_void) {
    if !owner.is_null() {
        unsafe {
            drop(Box::from_raw(owner.cast::<Tree>()));
        }
        SESSIONS.fetch_sub(1, Ordering::Relaxed);
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn generic_api_mode_has_no_station_number_pool_and_preserves_units() {
        let text = "{\"日本🌏\":[1,1.0,-0.0],\"nested\":[[1,2],{\"x\":3}]}";
        let mut utf8 = Tree::default();
        let mut utf16 = Tree::default();
        utf8.decode_input::<_, false>(text.as_bytes()).unwrap();
        utf16
            .decode_input::<_, false>(&text.encode_utf16().collect::<Vec<_>>())
            .unwrap();
        assert!(utf8.numbers.is_empty());
        assert!(!utf8.strings8.is_empty());
        assert!(utf16.strings8.is_empty());
        assert!(utf8.nodes.iter().any(|node| node.tag == 10));
        assert!(utf8.nodes.iter().all(|node| node.tag != 8 && node.tag != 9));
        assert!(utf8
            .nodes
            .iter()
            .any(|node| node.tag == 4 && node.bits == (-0.0f64).to_bits()));
    }
    fn parse(text: &str) -> Result<Tree> {
        let mut t = Tree::default();
        t.decode(&text.encode_utf16().collect::<Vec<_>>())?;
        Ok(t)
    }
    #[test]
    fn utf8_matches_utf16_and_reuses_input() {
        let text = "{\"日本語🌏\":[-0.0,1.25,-3],\"x\":\"\\ud800\"}";
        let expected = parse(text).unwrap_or_else(|_| panic!("valid UTF16"));
        let mut t = Tree::default();
        for _ in 0..100 {
            t.decode_utf8(text.as_bytes())
                .unwrap_or_else(|_| panic!("valid UTF8"));
            assert_eq!(t.output, expected.output);
        }
        assert!(t.decode_utf8(&[0xed, 0xa0, 0x80]).is_err());
        t.decode_utf8(text.as_bytes())
            .unwrap_or_else(|_| panic!("after invalid"));
        assert_eq!(t.output, expected.output);
    }
    #[test]
    fn exact_numeric_interning_keeps_types_zeros_and_original_order() {
        let text = "[1,1,1.0,0,-0,0.0,-0.0,1.000,1e0,2,1]";
        let t = parse(text).unwrap_or_else(|_| panic!("valid"));
        assert_eq!(t.children.len(), 11);
        assert_eq!(t.nodes.len(), 7); // root plus six distinct (type, bits)
        assert_eq!(t.children[0], t.children[1]);
        assert_ne!(t.children[0], t.children[2]);
        assert_eq!(t.children[3], t.children[4]);
        assert_ne!(t.children[5], t.children[6]);
        assert_eq!(t.children[2], t.children[7]);
        assert_eq!(t.children[2], t.children[8]);
        assert_eq!(t.children[0], t.children[10]);
    }
    #[test]
    fn syntax_and_utf16() {
        for text in [
            "",
            "[1,]",
            "{\"a\":}",
            "01",
            "1.",
            "1e",
            "true false",
            "\u{feff}{}",
            "\"\\u00xz\"",
        ] {
            assert!(parse(text).is_err(), "{text}");
        }
        let t = parse("{\"x\":[-0,-0.0,9223372036854775808,1e999,\"\\ud800\"]}")
            .unwrap_or_else(|_| panic!("valid"));
        assert_eq!(t.nodes[3].bits, 0);
        assert_eq!(t.nodes[4].bits, (-0.0f64).to_bits());
        assert_eq!(t.strings.last(), Some(&0xd800));
    }
}
