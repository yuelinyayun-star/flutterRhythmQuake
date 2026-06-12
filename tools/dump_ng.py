"""Dump NG加速 procedure from sb3 with full recursion"""
import json, os

sb3_path = os.path.join(os.environ.get('TEMP', '.'), 'sb3_extract', 'project.json')
with open(sb3_path, 'r', encoding='utf-8') as f:
    data = json.load(f)

for t in data['targets']:
    if t.get('name') == '受信と検出':
        tgt = t; break

blocks = tgt['blocks']

def resolve_full(expr, depth=0):
    """Resolve one input value to readable string, following block refs"""
    if depth > 6:
        return '...'
    if not isinstance(expr, list) or len(expr) < 2:
        return str(expr)
    t, val = expr[0], expr[1]
    
    if t == 1:  # shadow
        if isinstance(val, list) and len(val) >= 2:
            inner_t, inner_v = val[0], val[1]
            if inner_t == 11:  # variable
                if isinstance(inner_v, list) and len(inner_v) >= 2:
                    return f'VAR({inner_v[1]})'
                return f'VAR({inner_v})'
            if inner_t == 12:  # list
                if isinstance(inner_v, list) and len(inner_v) >= 2:
                    return f'LIST({inner_v[1]})'
                return f'LIST({inner_v})'
            return str(inner_v)
        return str(val)
    
    elif t == 2:  # no shadow - hidden input
        return 'HIDDEN'
    
    elif t == 3:  # block reference
        if isinstance(val, str) and val in blocks:
            sb = blocks[val]
            if isinstance(sb, dict):
                return resolve_block(val, depth + 1)
        return f'ref:{val}'
    
    elif t in (4, 5, 6, 7):  # numbers
        if isinstance(val, list) and len(val) >= 2:
            return str(val[1])
        return str(val)
    
    elif t == 10:  # string
        if isinstance(val, list) and len(val) >= 2:
            return f'"{val[1]}"'
        return f'"{val}"'
    
    elif t >= 11:  # var/list/broadcast name
        if isinstance(val, list) and len(val) >= 2:
            return str(val[1])
        return str(val)
    
    return f't{t}'

def resolve_block(bid, depth=0):
    """Resolve a single block to expression"""
    if depth > 6:
        return '(too deep)'
    blk = blocks.get(bid)
    if not isinstance(blk, dict):
        return str(blk)
    
    op = blk.get('opcode', '?')
    inputs = blk.get('inputs', {})
    fields = blk.get('fields', {})
    
    # Extract args
    args = []
    for ik in sorted(inputs.keys()):
        iv = inputs[ik]
        if isinstance(iv, list) and len(iv) >= 2:
            args.append((ik, resolve_full(iv, depth)))
    
    # Field values
    fargs = []
    for fk, fv in sorted(fields.items()):
        if isinstance(fv, list) and len(fv) >= 2:
            fargs.append(f'{fk}={fv[0]}/{fv[1]}')
    
    # Common operators
    if op == 'operator_add':
        a1 = args[0][1] if len(args) > 0 else '?'
        a2 = args[1][1] if len(args) > 1 else '?'
        return f'({a1} + {a2})'
    elif op == 'operator_subtract':
        a1 = args[0][1] if len(args) > 0 else '?'
        a2 = args[1][1] if len(args) > 1 else '?'
        return f'({a1} - {a2})'
    elif op == 'operator_multiply':
        a1 = args[0][1] if len(args) > 0 else '?'
        a2 = args[1][1] if len(args) > 1 else '?'
        return f'({a1} * {a2})'
    elif op == 'operator_divide':
        a1 = args[0][1] if len(args) > 0 else '?'
        a2 = args[1][1] if len(args) > 1 else '?'
        return f'({a1} / {a2})'
    elif op == 'data_itemoflist':
        a1 = args[0][1] if len(args) > 0 else '?'
        a2 = args[1][1] if len(args) > 1 else '?'
        return f'{a2}[{a1}]'
    elif op == 'argument_reporter_string_number':
        return fargs[0] if fargs else 'ARG'
    elif op == 'data_setvariableto':
        return f'SET({args})'
    elif op == 'procedures_call':
        mut = blk.get('mutation', {})
        pc = mut.get('proccode', '???')
        call_args = [(k, v) for k, v in args if k != 'custom_block']
        return f'CALL({pc}, {call_args})'
    
    return f'{op}({args} {fargs})'

# Find NG加速
for bid, block in blocks.items():
    if not isinstance(block, dict):
        continue
    if block.get('opcode') == 'procedures_definition':
        pbid = block.get('inputs', {}).get('custom_block', [None, None])
        proto_id = pbid[1] if isinstance(pbid, list) and len(pbid) >= 2 else None
        if not proto_id or proto_id not in blocks:
            continue
        proto = blocks[proto_id]
        proccode = proto.get('mutation', {}).get('proccode', '')
        if not proccode.startswith('NG加速'):
            continue
        
        print(f'=== {proccode} ===')
        
        # Walk body
        seen = set()
        next_id = block.get('next')
        while next_id and len(seen) < 20:
            if next_id in seen:
                break
            seen.add(next_id)
            blk = blocks.get(next_id)
            if not isinstance(blk, dict):
                break
            
            op = blk.get('opcode', '?')
            expr = resolve_block(next_id)
            print(f'  {op}: {expr}')
            
            next_id = blk.get('next')
