//! Stateful Java object stream used by GlobalQuake. No normalization of values.
use std::{
    collections::HashMap,
    ffi::c_void,
    sync::atomic::{AtomicU64, Ordering},
};
const LIMIT: usize = 64 * 1024 * 1024;
const MAX_NODES: usize = 1_000_000;
static SESSIONS: AtomicU64 = AtomicU64::new(0);
static CALLS: AtomicU64 = AtomicU64::new(0);

#[derive(Clone)]
enum Value {
    Null,
    Bool(bool),
    Int(i64),
    Float(u64),
    Ref(usize),
}
#[derive(Clone)]
struct Field {
    ty: u8,
    name: Vec<u8>,
    type_name: Option<Vec<u8>>,
}
enum Node {
    String(Vec<u8>),
    Desc {
        name: Vec<u8>,
        flags: u8,
        fields: Vec<Field>,
        parent: Option<usize>,
    },
    Object {
        name: Vec<u8>,
        fields: Vec<(Vec<u8>, Value)>,
        custom: Vec<(Vec<u8>, Vec<Value>)>,
    },
    List(Vec<Value>),
    Block(Vec<u8>),
}
enum Error {
    More,
    Invalid,
    Limit,
}
type Result<T> = std::result::Result<T, Error>;
#[derive(Default)]
struct Stream {
    bytes: Vec<u8>,
    offset: usize,
    header: bool,
    handles: Vec<usize>,
    nodes: Vec<Node>,
    output: Vec<u8>,
    checkpoint_handles: usize,
    reset_handles: Option<Vec<usize>>,
    reset_at: Option<usize>,
}
impl Stream {
    fn take(&mut self, count: usize) -> Result<&[u8]> {
        let end = self.offset.checked_add(count).ok_or(Error::Limit)?;
        let value = self.bytes.get(self.offset..end).ok_or(Error::More)?;
        self.offset = end;
        Ok(value)
    }
    fn u8(&mut self) -> Result<u8> {
        Ok(self.take(1)?[0])
    }
    fn u16(&mut self) -> Result<u16> {
        Ok(u16::from_be_bytes(self.take(2)?.try_into().unwrap()))
    }
    fn u32(&mut self) -> Result<u32> {
        Ok(u32::from_be_bytes(self.take(4)?.try_into().unwrap()))
    }
    fn u64(&mut self) -> Result<u64> {
        Ok(u64::from_be_bytes(self.take(8)?.try_into().unwrap()))
    }
    fn utf(&mut self) -> Result<Vec<u8>> {
        let length = self.u16()? as usize;
        Ok(self.take(length)?.to_vec())
    }
    fn node(&mut self, value: Node, handle: bool) -> Result<usize> {
        if self.nodes.len() >= MAX_NODES {
            return Err(Error::Limit);
        }
        let index = self.nodes.len();
        self.nodes.push(value);
        if handle {
            self.handles.push(index);
        }
        Ok(index)
    }
    fn content(&mut self, depth: usize) -> Result<Value> {
        if depth > 256 {
            return Err(Error::Limit);
        }
        match self.u8()? {
            0x70 => Ok(Value::Null),
            0x71 => {
                let wire = self.u32()?;
                let index = wire.checked_sub(0x7e0000).ok_or(Error::Invalid)? as usize;
                Ok(Value::Ref(*self.handles.get(index).ok_or(Error::Invalid)?))
            }
            0x72 => self.desc(depth + 1).map(Value::Ref),
            0x73 => self.object(depth + 1).map(Value::Ref),
            0x74 => {
                let text = self.utf()?;
                self.node(Node::String(text), true).map(Value::Ref)
            }
            0x75 => {
                let descriptor = self.class_desc(depth + 1)?;
                let ty = match &self.nodes[descriptor] {
                    Node::Desc { name, .. } => *name.get(1).unwrap_or(&b'L'),
                    _ => return Err(Error::Invalid),
                };
                let index = self.node(Node::List(Vec::new()), true)?;
                let length = self.u32()? as usize;
                if length > MAX_NODES {
                    return Err(Error::Limit);
                }
                let mut values = Vec::new();
                for _ in 0..length {
                    values.push(self.field(ty, depth + 1)?);
                }
                self.nodes[index] = Node::List(values);
                Ok(Value::Ref(index))
            }
            0x77 => {
                let count = self.u8()? as usize;
                let bytes = self.take(count)?.to_vec();
                self.node(Node::Block(bytes), false).map(Value::Ref)
            }
            0x7a => {
                let count = self.u32()? as usize;
                if count > LIMIT {
                    return Err(Error::Limit);
                }
                let bytes = self.take(count)?.to_vec();
                self.node(Node::Block(bytes), false).map(Value::Ref)
            }
            0x79 => {
                if self.reset_handles.is_none() {
                    self.reset_handles = Some(self.handles[..self.checkpoint_handles].to_vec());
                }
                self.handles.clear();
                self.reset_at = Some(self.nodes.len());
                self.content(depth + 1)
            }
            _ => Err(Error::Invalid),
        }
    }
    fn class_desc(&mut self, depth: usize) -> Result<usize> {
        match self.content(depth)? {
            Value::Ref(index) if matches!(self.nodes[index], Node::Desc { .. }) => Ok(index),
            _ => Err(Error::Invalid),
        }
    }
    fn desc(&mut self, depth: usize) -> Result<usize> {
        let name = self.utf()?;
        self.u64()?;
        let index = self.node(
            Node::Desc {
                name,
                flags: 0,
                fields: Vec::new(),
                parent: None,
            },
            true,
        )?;
        let flags = self.u8()?;
        let count = self.u16()?;
        let mut fields = Vec::new();
        for _ in 0..count {
            let ty = self.u8()?;
            let name = self.utf()?;
            let type_name = if ty == b'L' || ty == b'[' {
                match self.content(depth + 1)? {
                    Value::Null => None,
                    Value::Ref(i) => match &self.nodes[i] {
                        Node::String(text) => Some(text.clone()),
                        _ => return Err(Error::Invalid),
                    },
                    _ => return Err(Error::Invalid),
                }
            } else {
                None
            };
            fields.push(Field {
                ty,
                name,
                type_name,
            });
        }
        while self.u8()? != 0x78 {
            self.offset -= 1;
            self.content(depth + 1)?;
        }
        let parent = match self.content(depth + 1)? {
            Value::Ref(i) if matches!(self.nodes[i], Node::Desc { .. }) => Some(i),
            _ => None,
        };
        if let Node::Desc {
            flags: f,
            fields: v,
            parent: p,
            ..
        } = &mut self.nodes[index]
        {
            *f = flags;
            *v = fields;
            *p = parent;
        }
        Ok(index)
    }
    fn object(&mut self, depth: usize) -> Result<usize> {
        let desc = self.class_desc(depth + 1)?;
        let name = match &self.nodes[desc] {
            Node::Desc { name, .. } => name.clone(),
            _ => return Err(Error::Invalid),
        };
        let index = self.node(
            Node::Object {
                name,
                fields: Vec::new(),
                custom: Vec::new(),
            },
            true,
        )?;
        let mut hierarchy = Vec::new();
        let mut current = Some(desc);
        while let Some(i) = current {
            if hierarchy.len() >= 256 || hierarchy.contains(&i) {
                return Err(Error::Invalid);
            }
            hierarchy.push(i);
            current = match &self.nodes[i] {
                Node::Desc { parent, .. } => *parent,
                _ => return Err(Error::Invalid),
            };
        }
        for i in hierarchy.into_iter().rev() {
            let (name, flags, fields) = match &self.nodes[i] {
                Node::Desc {
                    name,
                    flags,
                    fields,
                    ..
                } => (name.clone(), *flags, fields.clone()),
                _ => return Err(Error::Invalid),
            };
            for field in fields {
                let value = self.field(field.ty, depth + 1)?;
                if let Node::Object { fields, .. } = &mut self.nodes[index] {
                    if let Some((_, old)) = fields.iter_mut().find(|(key, _)| *key == field.name) {
                        *old = value;
                    } else {
                        fields.push((field.name, value));
                    }
                }
            }
            if flags & 1 != 0 {
                let mut values = Vec::new();
                while self.u8()? != 0x78 {
                    self.offset -= 1;
                    values.push(self.content(depth + 1)?);
                }
                if let Node::Object { custom, .. } = &mut self.nodes[index] {
                    custom.push((name, values));
                }
            }
        }
        Ok(index)
    }
    fn field(&mut self, ty: u8, depth: usize) -> Result<Value> {
        Ok(match ty {
            b'B' => Value::Int(self.u8()? as i64), // Preserve existing unsigned byte contract.
            b'C' => Value::Int(self.u16()? as i64),
            b'S' => Value::Int(self.u16()? as i16 as i64),
            b'I' => Value::Int(self.u32()? as i32 as i64),
            b'J' => Value::Int(self.u64()? as i64),
            b'D' => Value::Float(self.u64()?),
            b'F' => Value::Float((f32::from_bits(self.u32()?) as f64).to_bits()),
            b'Z' => Value::Bool(self.u8()? != 0),
            b'L' | b'[' => self.content(depth)?,
            _ => return Err(Error::Invalid),
        })
    }
    fn compact_reset(&mut self) -> Result<()> {
        let Some(start) = self.reset_at.take() else {
            return Ok(());
        };
        fn adjust(value: &mut Value, start: usize) -> Result<()> {
            if let Value::Ref(i) = value {
                *i = i.checked_sub(start).ok_or(Error::Invalid)?;
            }
            Ok(())
        }
        for node in &mut self.nodes[start..] {
            match node {
                Node::Desc {
                    parent: Some(i), ..
                } => *i = i.checked_sub(start).ok_or(Error::Invalid)?,
                Node::Object { fields, custom, .. } => {
                    for (_, value) in fields {
                        adjust(value, start)?;
                    }
                    for (_, values) in custom {
                        for value in values {
                            adjust(value, start)?;
                        }
                    }
                }
                Node::List(values) => {
                    for value in values {
                        adjust(value, start)?;
                    }
                }
                _ => (),
            }
        }
        for i in &mut self.handles {
            *i = i.checked_sub(start).ok_or(Error::Invalid)?;
        }
        self.nodes.drain(..start);
        Ok(())
    }
    fn add(&mut self, input: &[u8]) -> Result<()> {
        self.output.clear();
        if self
            .bytes
            .len()
            .checked_add(input.len())
            .ok_or(Error::Limit)?
            > LIMIT
        {
            return Err(Error::Limit);
        }
        self.bytes.extend_from_slice(input);
        if !self.header {
            if self.bytes.len() < 4 {
                return Ok(());
            }
            if self.take(4)? != [0xac, 0xed, 0, 5] {
                return Err(Error::Invalid);
            }
            self.header = true;
        }
        while self.offset < self.bytes.len() {
            let mark = self.offset;
            let node_mark = self.nodes.len();
            self.checkpoint_handles = self.handles.len();
            self.reset_handles = None;
            self.reset_at = None;
            match self.content(0) {
                Ok(value) => {
                    if matches!(&value, Value::Ref(i) if matches!(self.nodes[*i], Node::Object { .. }))
                    {
                        encode(
                            &self.nodes,
                            &value,
                            &mut HashMap::new(),
                            &mut self.output,
                            0,
                        )?;
                    }
                    self.compact_reset()?;
                    self.reset_handles = None;
                }
                Err(Error::More) => {
                    self.offset = mark;
                    self.nodes.truncate(node_mark);
                    if let Some(handles) = self.reset_handles.take() {
                        self.handles = handles;
                    } else {
                        self.handles.truncate(self.checkpoint_handles);
                    }
                    self.reset_at = None;
                    break;
                }
                Err(error) => return Err(error),
            }
        }
        if self.offset > 0 {
            self.bytes.drain(..self.offset);
            self.offset = 0;
        }
        if self.output.len() > LIMIT {
            return Err(Error::Limit);
        }
        Ok(())
    }
}

fn count(out: &mut Vec<u8>, length: usize) {
    out.extend_from_slice(&(length as u32).to_le_bytes());
}
fn text(out: &mut Vec<u8>, bytes: &[u8]) {
    count(out, bytes.len());
    out.extend_from_slice(bytes);
}
fn encode(
    nodes: &[Node],
    value: &Value,
    seen: &mut HashMap<usize, u32>,
    out: &mut Vec<u8>,
    depth: usize,
) -> Result<()> {
    if depth > 256 || out.len() > LIMIT {
        return Err(Error::Limit);
    }
    match value {
        Value::Null => out.push(0),
        Value::Bool(value) => out.push(if *value { 2 } else { 1 }),
        Value::Int(value) => {
            out.push(3);
            out.extend_from_slice(&value.to_le_bytes());
        }
        Value::Float(value) => {
            out.push(4);
            out.extend_from_slice(&value.to_le_bytes());
        }
        Value::Ref(index) => {
            let node = &nodes[*index];
            if let Node::String(bytes) = node {
                out.push(5);
                text(out, bytes);
                return Ok(());
            }
            if let Some(id) = seen.get(index) {
                out.push(10);
                count(out, *id as usize);
                return Ok(());
            }
            let id = seen.len() as u32;
            seen.insert(*index, id);
            match node {
                Node::Object {
                    name,
                    fields,
                    custom,
                } => {
                    out.push(6);
                    count(out, id as usize);
                    text(out, name);
                    count(out, fields.len());
                    for (key, value) in fields {
                        text(out, key);
                        encode(nodes, value, seen, out, depth + 1)?;
                    }
                    count(out, custom.len());
                    for (key, values) in custom {
                        text(out, key);
                        count(out, values.len());
                        for value in values {
                            encode(nodes, value, seen, out, depth + 1)?;
                        }
                    }
                }
                Node::List(values) => {
                    out.push(7);
                    count(out, id as usize);
                    count(out, values.len());
                    for value in values {
                        encode(nodes, value, seen, out, depth + 1)?;
                    }
                }
                Node::Block(bytes) => {
                    out.push(8);
                    count(out, id as usize);
                    text(out, bytes);
                }
                Node::Desc {
                    name,
                    flags,
                    fields,
                    parent,
                } => {
                    out.push(9);
                    count(out, id as usize);
                    text(out, name);
                    out.push(*flags);
                    count(out, fields.len());
                    for field in fields {
                        out.push(field.ty);
                        text(out, &field.name);
                        match &field.type_name {
                            Some(bytes) => {
                                out.push(5);
                                text(out, bytes);
                            }
                            None => out.push(0),
                        }
                    }
                    encode(
                        nodes,
                        &parent.map_or(Value::Null, Value::Ref),
                        seen,
                        out,
                        depth + 1,
                    )?;
                }
                Node::String(_) => unreachable!(),
            }
        }
    }
    Ok(())
}

#[no_mangle]
pub extern "C" fn rq_gq_stream_abi_version() -> u32 {
    1
}
#[no_mangle]
pub extern "C" fn rq_gq_stream_sessions() -> u64 {
    SESSIONS.load(Ordering::Relaxed)
}
#[no_mangle]
pub extern "C" fn rq_gq_stream_calls() -> u64 {
    CALLS.load(Ordering::Relaxed)
}
#[no_mangle]
pub extern "C" fn rq_gq_stream_create() -> *mut c_void {
    let result = Box::into_raw(Box::<Stream>::default()).cast();
    SESSIONS.fetch_add(1, Ordering::Relaxed);
    result
}
/// # Safety
/// Owner is live and idle; input borrows count bytes. Output[1] and length[1]
/// receive a borrowed buffer valid until the owner's next add/destroy.
#[no_mangle]
pub unsafe extern "C" fn rq_gq_stream_add(
    owner: *mut c_void,
    input: *const u8,
    length: usize,
    output: *mut *const u8,
    output_length: *mut usize,
) -> i32 {
    if owner.is_null()
        || output.is_null()
        || output_length.is_null()
        || (length > 0 && input.is_null())
    {
        return 1;
    }
    unsafe {
        *output = std::ptr::null();
        *output_length = 0;
    }
    if length > LIMIT {
        return 3;
    }
    std::panic::catch_unwind(|| unsafe {
        let state = &mut *owner.cast::<Stream>();
        let input = if length == 0 {
            &[]
        } else {
            std::slice::from_raw_parts(input, length)
        };
        match state.add(input) {
            Ok(()) => {
                *output = state.output.as_ptr();
                *output_length = state.output.len();
                CALLS.fetch_add(1, Ordering::Relaxed);
                0
            }
            Err(Error::Limit) => 3,
            Err(_) => 2,
        }
    })
    .unwrap_or(5)
}
/// # Safety
/// Destroy an idle owner created here exactly once.
#[no_mangle]
pub unsafe extern "C" fn rq_gq_stream_destroy(owner: *mut c_void) {
    if !owner.is_null() {
        unsafe {
            drop(Box::from_raw(owner.cast::<Stream>()));
        }
        SESSIONS.fetch_sub(1, Ordering::Relaxed);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn raw_capture_reset_compacts_handles_and_nodes() {
        let raw = include_bytes!("../../../test/fixtures/global_quake/stream_20260921.bin");
        let mut captured = Stream::default();
        captured
            .add(raw)
            .unwrap_or_else(|_| panic!("original capture"));
        let complete = &raw[..raw.len() - captured.bytes.len()];
        assert_eq!(complete.len(), 966);
        let mut state = Stream::default();
        state
            .add(complete)
            .unwrap_or_else(|_| panic!("complete objects"));
        let expected = state.output.clone();
        let node_count = state.nodes.len();
        let handle_count = state.handles.len();
        let mut reset = vec![0x79];
        reset.extend_from_slice(&complete[4..]);
        for _ in 0..1000 {
            let mut output = Vec::new();
            for chunk in reset.chunks(64) {
                state
                    .add(chunk)
                    .unwrap_or_else(|_| panic!("fragmented reset"));
                output.extend_from_slice(&state.output);
            }
            assert_eq!(output, expected);
            assert_eq!(state.nodes.len(), node_count);
            assert_eq!(state.handles.len(), handle_count);
            assert!(state.bytes.is_empty());
        }
    }
    #[test]
    fn partial_header_and_bad_reference() {
        let mut state = Stream::default();
        state
            .add(&[0xac, 0xed])
            .unwrap_or_else(|_| panic!("header"));
        state
            .add(&[0, 5, 0x73])
            .unwrap_or_else(|_| panic!("partial root"));
        assert!(state.header);
        assert_eq!(state.bytes, [0x73]);
        assert_eq!(state.nodes.len(), 0);
        assert!(matches!(
            state.add(&[0x71, 0, 0x7e, 0, 9]),
            Err(Error::Invalid)
        ));
    }
}
