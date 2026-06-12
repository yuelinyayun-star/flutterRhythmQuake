"""SB3 Detector - Extract detection logic procedures from Scratch .sb3 project.json"""
import json, os, sys

sb3_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.environ.get('TEMP', '.'), 'sb3_extract', 'project.json')

with open(sb3_path, 'r', encoding='utf-8') as f:
    data = json.load(f)

for t in data['targets']:
    if t.get('name') == '受信と検出':
        tgt = t; break

blocks = tgt['blocks']

def explain(v):
    if not isinstance(v, list) or len(v) < 2:
        return str(v)
    t, val = v[0], v[1]
    if t == 1:  # shadow
        return str(val[1]) if isinstance(val, list) and len(val) >= 2 else str(val)
    elif t == 3:  # block ref
        return '[SUB]'
    elif t == 4:  # number
        return str(val[1]) if isinstance(val, list) and len(val) >= 2 else str(val)
    elif t >= 11:  # var/list name
        return str(val[1]) if isinstance(val, list) and len(val) >= 2 else str(val)
    return str(t)

def block_sig(blk):
    """Extract readable signature from a block"""
    op = blk.get('opcode', '?')
    parts = []
    for ik, iv in sorted(blk.get('inputs', {}).items(), key=lambda x: x[0]):
        if isinstance(iv, list) and len(iv) >= 2:
            parts.append(explain(iv))
    for fv in blk.get('fields', {}).values():
        if isinstance(fv, list) and len(fv) >= 2:
            parts.append(str(fv[1]))
    return op + ' ' + ' '.join(parts)

def walk_proc(bid, max_steps=30):
    """Walk a procedure definition and print its block chain"""
    seen = set()
    stack = [(bid, 0)]
    while stack and max_steps > 0:
        b, indent = stack.pop(0)
        if b is None or b in seen:
            continue
        seen.add(b)
        blk = blocks.get(b)
        if not isinstance(blk, dict):
            continue
        sig = block_sig(blk)[:140]
        print('  ' * indent + sig)
        max_steps -= 1
        
        # Check for sub-blocks in inputs
        for ik, iv in sorted(blk.get('inputs', {}).items(), key=lambda x: x[0]):
            if isinstance(iv, list) and len(iv) >= 2 and iv[0] == 3 and isinstance(iv[1], str):
                stack.insert(0, (iv[1], indent + 1))
        
        # Next block
        nxt = blk.get('next')
        if nxt:
            stack.insert(0, (nxt, indent))

targets = ['揺れ検出許可','検出許可震度算出','点許可状態更新','単独トリガ',
           '複数トリガ','gridトリガ','加速追加','NG加速','周囲9grid','grid:上昇中割合']

for bid, block in blocks.items():
    if not isinstance(block, dict):
        continue
    if block.get('opcode') == 'procedures_definition':
        pbid = block.get('inputs', {}).get('custom_block', [None, None])
        proto_id = pbid[1] if isinstance(pbid, list) and len(pbid) >= 2 else None
        if not proto_id:
            continue
        proto = blocks.get(proto_id, {})
        proccode = proto.get('mutation', {}).get('proccode', '')
        if any(p in proccode for p in targets):
            print(f'\n=== {proccode} ===')
            next_id = block.get('next')
            if next_id:
                walk_proc(next_id, 20)
            print()
