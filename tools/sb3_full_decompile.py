"""
SB3 full decompiler - produce readable pseudocode from kanameishi's Scratch project.
Usage: python sb3_full.py [path_to_project.json]
"""
import json, os, sys, re

if len(sys.argv) > 1:
    sb3_path = sys.argv[1]
else:
    sb3_path = os.path.join(os.environ.get('TEMP', '.'), 'sb3_extract', 'project.json')

with open(sb3_path, 'r', encoding='utf-8') as f:
    data = json.load(f)

# ── find targets ──
targets = {}
for t in data['targets']:
    targets[t.get('name', '?')] = t

tgt = targets.get('受信と検出')
if not tgt:
    print("Target '受信と検出' not found!")
    available = [k for k in targets if k != '?']
    print(f"Available: {available}")
    sys.exit(1)

blocks = tgt['blocks']
comments = tgt.get('comments', {})

# ── global name mapping ──
# collect all variables and list names
var_names = {}  # id -> name
list_names = {}  # id -> name
broadcast_names = {}  # id -> display name

for bid, block in blocks.items():
    if not isinstance(block, dict):
        continue
    op = block.get('opcode', '')
    fields = block.get('fields', {})
    # variables
    for fk, fv in fields.items():
        if isinstance(fv, list) and len(fv) >= 2:
            val = str(fv[1])
            fid = fv[0] if isinstance(fv[0], str) else str(fv[0])
            if fk == 'VARIABLE':
                var_names[fid] = val if val != fid else f'var_{fid[:4]}'
            elif fk == 'LIST':
                list_names[fid] = val if val != fid else f'list_{fid[:4]}'
            elif fk == 'BROADCAST_OPTION':
                broadcast_names[fid] = val

# ── expression resolver ──
def resolve(expr, depth=0):
    """Resolve a Scratch input/value to a string expression."""
    if depth > 8:
        return '(...)'
    if not isinstance(expr, list) or len(expr) < 2:
        return str(expr)
    
    t, val = expr[0], expr[1]
    
    # Type 1: shadow (literal from dropdown context)
    if t == 1:
        if isinstance(val, list) and len(val) >= 2:
            return str(val[1])
        return str(val)
    
    # Type 2: no shadow (hidden input - often a dropdown or menu value)
    if t == 2:
        return '?'
    
    # Type 3: block reference - recursively resolve
    if t == 3 and isinstance(val, str) and val in blocks:
        return resolve_block(val, depth + 1)
    
    # Type 4-7: number / positive number / positive integer / integer
    if t in (4, 5, 6, 7):
        if isinstance(val, list) and len(val) >= 2:
            return str(val[1])
        return str(val)
    
    # Type 8: angle
    if t == 8:
        if isinstance(val, list) and len(val) >= 2:
            return str(val[1]) + '°'
        return str(val) + '°'
    
    # Type 9: color
    if t == 9:
        return '#color'
    
    # Type 10: string
    if t == 10:
        if isinstance(val, list) and len(val) >= 2:
            return f'"{val[1]}"'
        return f'"{val}"'
    
    # Type 11-13: variable / list / broadcast names
    if t == 11:
        if isinstance(val, list) and len(val) >= 2:
            name = var_names.get(val[1], str(val[1]))
            return name
        return str(val)
    if t == 12:
        if isinstance(val, list) and len(val) >= 2:
            name = list_names.get(val[1], str(val[1]))
            return name
        return str(val)
    if t == 13:
        if isinstance(val, list) and len(val) >= 2:
            bid_name = broadcast_names.get(val[1], str(val[1]))
            return f'broadcast("{bid_name}")'
        return str(val)
    
    return str(t)

# ── block resolver ──
OPS = {
    'operator_add': ('+', 2, 'infix'),
    'operator_subtract': ('-', 2, 'infix'),
    'operator_multiply': ('*', 2, 'infix'),
    'operator_divide': ('/', 2, 'infix'),
    'operator_equals': ('==', 2, 'infix'),
    'operator_gt': ('>', 2, 'infix'),
    'operator_lt': ('<', 2, 'infix'),
    'operator_and': ('AND', 2, 'prefix'),
    'operator_or': ('OR', 2, 'prefix'),
    'operator_not': ('NOT', 1, 'prefix'),
    'operator_join': ('JOIN', 2, 'func'),
    'operator_round': ('ROUND', 1, 'func'),
    'operator_mathop': ('MATHOP', 1, 'func'),
    'operator_length': ('LEN', 1, 'func'),
    'operator_contains': ('CONTAINS', 2, 'func'),
    'operator_mod': ('MOD', 2, 'infix'),
    'operator_random': ('RANDOM', 2, 'func'),
    'operator_letter_of': ('LETTER', 2, 'func'),
}

def resolve_block(bid, depth=0):
    """Resolve a single block to its expression string."""
    if depth > 8:
        return '(...)'
    block = blocks.get(bid)
    if not isinstance(block, dict):
        return str(block)
    
    opcode = block.get('opcode', '?')
    
    # Handle reporters / operators
    if opcode in OPS:
        name, arity, style = OPS[opcode]
        inputs = block.get('inputs', {})
        args = []
        for ik in sorted(inputs.keys()):
            iv = inputs[ik]
            if isinstance(iv, list) and len(iv) >= 2:
                args.append(resolve(iv, depth + 1))
        if style == 'infix' and len(args) == 2:
            return f'({args[0]} {name} {args[1]})'
        elif style == 'prefix' and len(args) == 2:
            return f'({name} {args[0]} {args[1]})'
        elif style == 'prefix' and len(args) == 1:
            return f'({name} {args[0]})'
        elif style == 'func':
            return f'{name}({", ".join(args)})'
        else:
            return f'{name}[{", ".join(args)}]'
    
    # sensing_of
    if opcode == 'sensing_of':
        inputs = block.get('inputs', {})
        parts = []
        for ik, iv in sorted(inputs.items()):
            if isinstance(iv, list) and len(iv) >= 2:
                parts.append(resolve(iv, depth + 1))
        return f'SENSING_OF({", ".join(parts)})'
    
    # data_itemoflist (list get at index)
    if opcode == 'data_itemoflist':
        inputs = block.get('inputs', {})
        parts = []
        for ik, iv in sorted(inputs.items()):
            if isinstance(iv, list) and len(iv) >= 2:
                parts.append(resolve(iv, depth + 1))
        if len(parts) >= 2:
            return f'{parts[0]}[{parts[1]}]'
        return f'LIST[{", ".join(parts)}]'
    
    # data_listcontainsitem
    if opcode == 'data_listcontainsitem':
        inputs = block.get('inputs', {})
        parts = []
        for ik, iv in sorted(inputs.items()):
            if isinstance(iv, list) and len(iv) >= 2:
                parts.append(resolve(iv, depth + 1))
        return f'({", ".join(parts)} IN_LIST)'
    
    # argument_reporter_string_number - procedure argument
    if opcode == 'argument_reporter_string_number':
        fields = block.get('fields', {})
        for fv in fields.values():
            if isinstance(fv, list) and len(fv) >= 2:
                return str(fv[1])
        return 'ARG'
    
    # procedures_call
    if opcode == 'procedures_call':
        proc_code = ''
        mutation = block.get('mutation', {})
        if mutation:
            proc_code = mutation.get('proccode', '')
        if not proc_code:
            inputs = block.get('inputs', {})
            for ik, iv in sorted(inputs.items()):
                if isinstance(iv, list) and len(iv) >= 2:
                    s = resolve(iv, depth + 1)
                    if s.startswith('"') or not s.startswith('?'):
                        proc_code += s + ' '
        
        # resolve inputs
        inputs = block.get('inputs', {})
        args = []
        for ik in sorted(inputs.keys()):
            iv = inputs[ik]
            if ik == 'custom_block':
                continue
            if isinstance(iv, list) and len(iv) >= 2:
                args.append(resolve(iv, depth + 1))
        
        return f'CALL({proc_code.strip()}, [{", ".join(args)}])'
    
    # Default: return block type with resolved inputs
    parts = []
    for ik, iv in sorted(block.get('inputs', {}).items()):
        if isinstance(iv, list) and len(iv) >= 2:
            parts.append(resolve(iv, depth + 1))
    for fv in block.get('fields', {}).values():
        if isinstance(fv, list) and len(fv) >= 2:
            parts.append(str(fv[1]))
    return f'{opcode}[{", ".join(parts)}]'

# ── statement walker ──
def walk_stmt(bid, indent=0, max_lines=200):
    """Walk a statement chain and yield (indent, text) lines."""
    seen = set()
    stack = [(bid, indent, 'next')]
    lines = 0
    
    while stack and lines < max_lines:
        b, ind, mode = stack.pop(0)
        if b is None or b in seen:
            continue
        seen.add(b)
        block = blocks.get(b)
        if not isinstance(block, dict):
            continue
        
        opcode = block.get('opcode', '?')
        inputs = block.get('inputs', {})
        
        # ── control flow blocks ──
        if opcode == 'control_if':
            cond = resolve(inputs.get('CONDITION', [2, '?']))
            yield ind, f'if {cond}:'
            substack = inputs.get('SUBSTACK', [3, None])
            if isinstance(substack, list) and len(substack) >= 2 and substack[1]:
                stack.insert(0, (substack[1], ind + 1, 'substack'))
            nxt = block.get('next')
            if nxt:
                stack.insert(0, (nxt, ind, 'next'))
            lines += 1
        
        elif opcode == 'control_if_else':
            cond = resolve(inputs.get('CONDITION', [2, '?']))
            yield ind, f'if {cond}:'
            substack = inputs.get('SUBSTACK', [3, None])
            substack2 = inputs.get('SUBSTACK2', [3, None])
            if isinstance(substack, list) and len(substack) >= 2 and substack[1]:
                stack.insert(0, (substack[1], ind + 1, 'substack'))
            if isinstance(substack2, list) and len(substack2) >= 2 and substack2[1]:
                # insert else branch AFTER the if branch
                stack.insert(1, ('__else__', ind, 'else'))
                stack.insert(2, (substack2[1], ind + 1, 'substack'))
            nxt = block.get('next')
            if nxt:
                stack.insert(0, (nxt, ind, 'next'))
            lines += 1
        
        elif opcode == 'control_repeat':
            count = resolve(inputs.get('TIMES', [4, [10, '10']]))
            yield ind, f'repeat {count}:'
            substack = inputs.get('SUBSTACK', [3, None])
            if isinstance(substack, list) and len(substack) >= 2 and substack[1]:
                stack.insert(0, (substack[1], ind + 1, 'substack'))
            nxt = block.get('next')
            if nxt:
                stack.insert(0, (nxt, ind, 'next'))
            lines += 1
        
        elif opcode == 'control_repeat_until':
            cond = resolve(inputs.get('CONDITION', [2, '?']))
            yield ind, f'repeat until {cond}:'
            substack = inputs.get('SUBSTACK', [3, None])
            if isinstance(substack, list) and len(substack) >= 2 and substack[1]:
                stack.insert(0, (substack[1], ind + 1, 'substack'))
            nxt = block.get('next')
            if nxt:
                stack.insert(0, (nxt, ind, 'next'))
            lines += 1
        
        elif opcode == 'control_forever':
            yield ind, 'forever:'
            substack = inputs.get('SUBSTACK', [3, None])
            if isinstance(substack, list) and len(substack) >= 2 and substack[1]:
                stack.insert(0, (substack[1], ind + 1, 'substack'))
            lines += 1
        
        elif opcode == 'control_wait_until':
            cond = resolve(inputs.get('CONDITION', [2, '?']))
            yield ind, f'wait until {cond}'
            nxt = block.get('next')
            if nxt:
                stack.insert(0, (nxt, ind, 'next'))
            lines += 1
        
        elif opcode == 'control_wait':
            dur = resolve(inputs.get('DURATION', [4, [10, '1']]))
            yield ind, f'wait {dur} sec'
            nxt = block.get('next')
            if nxt:
                stack.insert(0, (nxt, ind, 'next'))
            lines += 1
        
        elif opcode == 'control_stop':
            stop_opt = block.get('fields', {}).get('STOP_OPTION', ['', 'this script'])
            yield ind, f'stop [{stop_opt[0] if isinstance(stop_opt, list) else stop_opt}]'
            lines += 1
        
        # ── data blocks ──
        elif opcode == 'data_setvariableto':
            var = resolve(inputs.get('VALUE', [1, ['0']]))
            fields = block.get('fields', {})
            vname = '?'
            for fv in fields.values():
                if isinstance(fv, list) and len(fv) >= 2:
                    vname = var_names.get(fv[1], str(fv[1]))
            yield ind, f'{vname} = {var}'
            nxt = block.get('next')
            if nxt:
                stack.insert(0, (nxt, ind, 'next'))
            lines += 1
        
        elif opcode == 'data_changevariableby':
            val = resolve(inputs.get('VALUE', [4, [10, '1']]))
            fields = block.get('fields', {})
            vname = '?'
            for fv in fields.values():
                if isinstance(fv, list) and len(fv) >= 2:
                    vname = var_names.get(fv[1], str(fv[1]))
            yield ind, f'{vname} += {val}'
            nxt = block.get('next')
            if nxt:
                stack.insert(0, (nxt, ind, 'next'))
            lines += 1
        
        elif opcode == 'data_replaceitemoflist':
            idx = resolve(inputs.get('INDEX', [4, [10, '1']]))
            item = resolve(inputs.get('ITEM', [1, ['0']]))
            fields = block.get('fields', {})
            lname = '?'
            for fv in fields.values():
                if isinstance(fv, list) and len(fv) >= 2:
                    lname = list_names.get(fv[1], str(fv[1]))
            yield ind, f'{lname}[{idx}] = {item}'
            nxt = block.get('next')
            if nxt:
                stack.insert(0, (nxt, ind, 'next'))
            lines += 1
        
        # ── procedures ──
        elif opcode == 'procedures_call':
            mutation = block.get('mutation', {})
            proc_code = mutation.get('proccode', '???') if mutation else '???'
            args = []
            for ik in sorted(inputs.keys()):
                iv = inputs[ik]
                if ik == 'custom_block':
                    continue
                if isinstance(iv, list) and len(iv) >= 2:
                    args.append(resolve(iv))
            yield ind, f'{proc_code}({", ".join(args)})'
            nxt = block.get('next')
            if nxt:
                stack.insert(0, (nxt, ind, 'next'))
            lines += 1
        
        # ── broadcast ──
        elif opcode == 'event_broadcast' or opcode == 'event_broadcastandwait':
            fv = block.get('fields', {}).get('BROADCAST_OPTION', ['', '?'])
            bname = fv[0] if isinstance(fv, list) and len(fv) >= 1 else str(fv)
            yield ind, f'broadcast("{bname}")'
            nxt = block.get('next')
            if nxt:
                stack.insert(0, (nxt, ind, 'next'))
            lines += 1
        
        # ── else marker ──
        elif opcode == '__else__':
            yield ind, 'else:'
            lines += 1
        
        else:
            # Generic block
            parts = []
            for ik, iv in sorted(inputs.items()):
                if isinstance(iv, list) and len(iv) >= 2:
                    parts.append(resolve(iv))
            for fv in block.get('fields', {}).values():
                if isinstance(fv, list) and len(fv) >= 2:
                    parts.append(str(fv[1]))
            text = opcode + ' ' + ' '.join(parts)
            yield ind, text
            nxt = block.get('next')
            if nxt:
                stack.insert(0, (nxt, ind, 'next'))
            lines += 1


# ── main: dump all detection procedures ──
DETECT_PROCS = [
    '揺れ検出許可', '検出許可震度算出', '点許可状態更新',
    '単独トリガ', '複数トリガ', 'gridトリガ',
    '加速追加', 'NG加速',
    '周囲9grid最大震度or上昇', 'grid:上昇中割合計算',
    'カメラ用近傍点', '近い観測点TOP7',
]

# Find all procedure definitions
proc_map = {}  # proccode -> definition_block_id
for bid, block in blocks.items():
    if not isinstance(block, dict):
        continue
    if block.get('opcode') == 'procedures_definition':
        pbid = block.get('inputs', {}).get('custom_block', [None, None])
        proto_id = pbid[1] if isinstance(pbid, list) and len(pbid) >= 2 else None
        if proto_id and proto_id in blocks:
            proto = blocks[proto_id]
            proccode = proto.get('mutation', {}).get('proccode', '')
            proc_map[proccode] = (bid, block)

# Print procedures
for pattern in DETECT_PROCS:
    matches = [(p, proc_map[p]) for p in proc_map if pattern in p]
    if not matches:
        continue
    for proccode, (bid, block) in matches:
        print(f'\n{"="*70}')
        print(f'DEF {proccode}')
        print(f'{"="*70}')
        next_id = block.get('next')
        if next_id:
            for ind, line in walk_stmt(next_id, 0, 200):
                print('  ' + '  ' * ind + line)
        print()
