//! Lossless station-table -> packed immutable DAG. Repeated catalogue/container
//! references remain references; replay does not expand every frame's graph.
use super::{Node, Tree};
use serde_json::{Map, Value};
const LIMIT: usize = 128 * 1024 * 1024;
fn finish(tree: Tree) -> Result<Vec<u8>, String> {
    let base = 24 + tree.nodes.len() * 16 + tree.children.len() * 4 + tree.strings8.len();
    if base > LIMIT {
        return Err("Station replay tree too large".into());
    }
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
    Ok(out)
}
pub(crate) fn pack_table(table: &Value) -> Result<Vec<u8>, String> {
    if table["format"] != "station-json-table-v1" {
        return Err("Invalid station JSON table".into());
    }
    let nodes = table["nodes"]
        .as_array()
        .ok_or("Invalid station JSON nodes")?;
    let roots = table["frames"]
        .as_array()
        .ok_or("Invalid station JSON frames")?;
    if nodes.len() > 2_000_000 || roots.len() > 1_000_000 {
        return Err("Station JSON table too large".into());
    }
    let mut tree = Tree::default();
    tree.nodes.push(Node::default());
    let mut costs = Vec::<usize>::new();
    for (i, value) in nodes.iter().enumerate() {
        let mut cost = 1usize;
        let node = match value {
            Value::Null => Node::default(),
            Value::Bool(b) => Node {
                tag: if *b { 2 } else { 1 },
                ..Default::default()
            },
            Value::Number(n) => {
                if let Some(v) = n.as_i64() {
                    Node {
                        tag: 3,
                        aux: 0,
                        bits: v as u64,
                    }
                } else {
                    Node {
                        tag: 4,
                        aux: 0,
                        bits: n.as_f64().unwrap().to_bits(),
                    }
                }
            }
            Value::String(s) => {
                let start = tree.strings8.len();
                tree.strings8.extend_from_slice(s.as_bytes());
                Node {
                    tag: 11,
                    aux: start as u32,
                    bits: s.len() as u64,
                }
            }
            Value::Array(items) => {
                let tag = match items.first().and_then(Value::as_str) {
                    Some("m") if items.len() % 2 == 1 => 7,
                    Some("l") => 6,
                    _ => return Err("Invalid station JSON node".into()),
                };
                let start = tree.children.len();
                for (j, item) in items.iter().skip(1).enumerate() {
                    let id = item
                        .as_u64()
                        .and_then(|n| usize::try_from(n).ok())
                        .filter(|&n| n < i)
                        .ok_or("Invalid station JSON reference")?;
                    if tag == 7 && j % 2 == 0 && !nodes[id].is_string() {
                        return Err("Invalid station JSON key".into());
                    }
                    cost = cost.saturating_add(costs[id]);
                    if cost > 2_000_000 {
                        return Err("Station JSON expansion too large".into());
                    }
                    tree.children.push(id as u32 + 1);
                }
                Node {
                    tag,
                    aux: start as u32,
                    bits: (items.len() - 1) as u64,
                }
            }
            _ => return Err("Invalid station JSON scalar".into()),
        };
        costs.push(cost);
        tree.nodes.push(node);
        if 24 + tree.nodes.len() * 16 + tree.children.len() * 4 + tree.strings8.len() > LIMIT {
            return Err("Station replay tree too large".into());
        }
    }
    let start = tree.children.len();
    for root in roots {
        let id = root
            .as_u64()
            .and_then(|n| usize::try_from(n).ok())
            .filter(|&n| n < nodes.len())
            .ok_or("Invalid station frame reference")?;
        tree.children.push(id as u32 + 1);
    }
    tree.nodes[0] = Node {
        tag: 6,
        aux: start as u32,
        bits: roots.len() as u64,
    };
    finish(tree)
}
pub(crate) fn unpack_value(bytes: &[u8], root: u32) -> Result<Value, String> {
    let u32_at = |p: usize| {
        bytes
            .get(p..p + 4)
            .map(|s| u32::from_le_bytes(s.try_into().unwrap()))
            .ok_or("Invalid native replay buffer")
    };
    let layout = u32_at(0)?;
    let count = (layout & 0x7fffffff) as usize;
    let header = if layout & 0x80000000 != 0 { 24 } else { 16 };
    let children = header + count * 16;
    let strings = children + u32_at(4)? as usize * 4;
    let strings8 = strings + u32_at(8)? as usize * 2;
    if bytes.len() > LIMIT || root as usize >= count || strings8 > bytes.len() {
        return Err("Invalid native replay tree".into());
    }
    struct Reader<'a> {
        bytes: &'a [u8],
        count: usize,
        header: usize,
        children: usize,
        strings: usize,
        strings8: usize,
        budget: usize,
    }
    impl Reader<'_> {
        fn word(&self, p: usize) -> Result<u32, String> {
            self.bytes
                .get(p..p + 4)
                .map(|v| u32::from_le_bytes(v.try_into().unwrap()))
                .ok_or_else(|| "Invalid replay tree offset".into())
        }
        fn read(&mut self, id: u32, depth: usize) -> Result<Value, String> {
            if id as usize >= self.count || depth > 512 || self.budget == 0 {
                return Err("Invalid replay tree reference".into());
            }
            self.budget -= 1;
            let p = self.header + id as usize * 16;
            let tag = self.word(p)?;
            let aux = self.word(p + 4)? as usize;
            let count = self.word(p + 8)? as usize;
            let bits = u64::from_le_bytes(
                self.bytes
                    .get(p + 8..p + 16)
                    .ok_or("Invalid replay number")?
                    .try_into()
                    .unwrap(),
            );
            match tag {
                0 => Ok(Value::Null),
                1 => Ok(Value::Bool(false)),
                2 => Ok(Value::Bool(true)),
                3 => Ok(Value::from(bits as i64)),
                4 => serde_json::Number::from_f64(f64::from_bits(bits))
                    .map(Value::Number)
                    .ok_or_else(|| "Invalid replay floating point".into()),
                5 => {
                    let start = self.strings + aux * 2;
                    let units = self
                        .bytes
                        .get(start..start + count * 2)
                        .ok_or("Invalid replay text")?
                        .chunks_exact(2)
                        .map(|c| u16::from_le_bytes(c.try_into().unwrap()))
                        .collect::<Vec<_>>();
                    String::from_utf16(&units)
                        .map(Value::String)
                        .map_err(|_| "Invalid replay Unicode".into())
                }
                11 => {
                    let start = self.strings8 + aux;
                    String::from_utf8(
                        self.bytes
                            .get(start..start + count)
                            .ok_or("Invalid replay text")?
                            .to_vec(),
                    )
                    .map(Value::String)
                    .map_err(|_| "Invalid replay UTF-8".into())
                }
                6 | 8 | 9 | 10 => {
                    let mut out = Vec::with_capacity(count.min(65536));
                    for i in 0..count {
                        let child = if tag == 9 || tag == 10 {
                            (aux + i) as u32
                        } else {
                            self.word(self.children + (aux + i) * 4)?
                        };
                        out.push(self.read(child, depth + 1)?);
                    }
                    Ok(Value::Array(out))
                }
                7 => {
                    if count % 2 != 0 {
                        return Err("Invalid replay map".into());
                    }
                    let mut out = Map::new();
                    for i in (0..count).step_by(2) {
                        let key = self.word(self.children + (aux + i) * 4)?;
                        let value = self.word(self.children + (aux + i + 1) * 4)?;
                        let key = self
                            .read(key, depth + 1)?
                            .as_str()
                            .ok_or("Invalid replay key")?
                            .to_owned();
                        out.insert(key, self.read(value, depth + 1)?);
                    }
                    Ok(Value::Object(out))
                }
                _ => Err("Invalid replay tree tag".into()),
            }
        }
    }
    Reader {
        bytes,
        count,
        header,
        children,
        strings,
        strings8,
        budget: 2_000_000,
    }
    .read(root, 0)
}
