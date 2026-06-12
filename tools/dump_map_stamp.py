"""Dump map epicenter stamp procedures from sb3"""
import json, os

sb3 = os.path.join(os.environ.get('TEMP', '.'), 'sb3_extract', 'project.json')
with open(sb3, 'r', encoding='utf-8') as f:
    data = json.load(f)

for t in data['targets']:
    if t.get('name') == '地図':
        tgt = t; break

blocks = tgt['blocks']
comments = tgt.get('comments', {})

var_names = {}
list_names = {}
for bid, block in blocks.items():
    if not isinstance(block, dict): continue
    for fk, fv in block.get('fields', {}).items():
        if isinstance(fv, list) and len(fv) >= 2:
            fid = fv[0] if isinstance(fv[0], str) else str(fv[0])
            if fk == 'VARIABLE': var_names[fid] = str(fv[1])
            elif fk == 'LIST': list_names[fid] = str(fv[1])

def resolve(expr, depth=0):
    if depth > 5: return '...'
    if not isinstance(expr, list) or len(expr) < 2: return str(expr)
    t, val = expr[0], expr[1]
    if t == 1:
        if isinstance(val, list) and len(val) >= 2:
            inner_t, inner_v = val[0], val[1]
            if inner_t == 11: return var_names.get(inner_v[1] if isinstance(inner_v, list) and len(inner_v) >= 2 else inner_v, f'V({inner_v})')
            if inner_t == 12: return list_names.get(inner_v[1] if isinstance(inner_v, list) and len(inner_v) >= 2 else inner_v, f'L({inner_v})')
            return str(inner_v)
        return str(val)
    elif t == 3 and isinstance(val, str): return resolve_block(val, depth + 1)
    elif t in (4,5,6,7):
        if isinstance(val, list) and len(val) >= 2: return str(val[1])
        return str(val)
    elif t >= 11:
        if isinstance(val, list) and len(val) >= 2:
            return var_names.get(val[1], list_names.get(val[1], str(val[1])))
        return str(val)
    return f't{t}'

def resolve_block(bid, depth=0):
    if depth > 4: return '...'
    blk = blocks.get(bid)
    if not isinstance(blk, dict): return str(blk)
    op = blk.get('opcode', '?')
    ip = blk.get('inputs', {})
    fl = blk.get('fields', {})
    args = [resolve(iv, depth) for ik, iv in sorted(ip.items()) if isinstance(iv, list) and len(iv) >= 2]
    
    if op == 'operator_add': return f'({args[0]}+{args[1]})' if len(args)>=2 else '+'
    if op == 'operator_subtract': return f'({args[0]}-{args[1]})' if len(args)>=2 else '-'
    if op == 'operator_multiply': return f'({args[0]}*{args[1]})' if len(args)>=2 else '*'
    if op == 'operator_divide': return f'({args[0]}/{args[1]})' if len(args)>=2 else '/'
    if op == 'data_itemoflist': return f'{args[1]}[{args[0]}]' if len(args)>=2 else 'L[]'
    if op == 'argument_reporter_string_number':
        for fv in fl.values():
            if isinstance(fv, list) and len(fv) >= 2: return str(fv[1])
        return 'ARG'
    if op == 'procedures_call':
        mut = blk.get('mutation', {})
        pc = mut.get('proccode', '???')
        ca = [resolve(iv, depth) for ik, iv in sorted(ip.items()) if ik != 'custom_block' and isinstance(iv, list) and len(iv) >= 2]
        return f'{pc}({",".join(ca)})'
    if op == 'operator_gt': return f'({args[0]}>{args[1]})' if len(args)>=2 else '>'
    if op == 'operator_lt': return f'({args[0]}<{args[1]})' if len(args)>=2 else '<'
    if op == 'operator_equals': return f'({args[0]}=={args[1]})' if len(args)>=2 else '=='
    if op == 'operator_and': return f'({args[0]} AND {args[1]})' if len(args)>=2 else 'AND'
    if op == 'operator_or': return f'({args[0]} OR {args[1]})' if len(args)>=2 else 'OR'
    
    fargs = [str(fv[1]) for fv in fl.values() if isinstance(fv, list) and len(fv) >= 2]
    return f'{op}[{",".join(args+fargs)}]'

def walk(bid, indent=0, max_lines=50):
    seen = set()
    stack = [(bid, indent)]
    lines = 0
    while stack and lines < max_lines:
        b, ind = stack.pop(0)
        if b is None or b in seen: continue
        seen.add(b)
        blk = blocks.get(b)
        if not isinstance(blk, dict): continue
        op = blk.get('opcode', '?')
        ip = blk.get('inputs', {})
        fl = blk.get('fields', {})

        if op == 'control_if':
            cond = resolve(ip.get('CONDITION', [2, '?']))
            print(f'{"  "*ind}if {cond}:')
            s = ip.get('SUBSTACK', [3, None])
            if isinstance(s, list) and len(s) >= 2 and s[1]:
                stack.insert(0, (s[1], ind + 1))
            nxt = blk.get('next')
            if nxt: stack.insert(0, (nxt, ind))
            lines += 1
        elif op == 'control_if_else':
            cond = resolve(ip.get('CONDITION', [2, '?']))
            print(f'{"  "*ind}if {cond}:')
            s1, s2 = ip.get('SUBSTACK', [3, None]), ip.get('SUBSTACK2', [3, None])
            if isinstance(s1, list) and len(s1) >= 2 and s1[1]:
                stack.insert(0, (s1[1], ind + 1))
            if isinstance(s2, list) and len(s2) >= 2 and s2[1]:
                stack.insert(0, (f'__else__', ind))
                stack.insert(1, (s2[1], ind + 1))
            nxt = blk.get('next')
            if nxt: stack.insert(0, (nxt, ind))
            lines += 1
        elif op == 'control_repeat':
            cnt = resolve(ip.get('TIMES', [4, [10, '1']]))
            print(f'{"  "*ind}repeat {cnt}:')
            s = ip.get('SUBSTACK', [3, None])
            if isinstance(s, list) and len(s) >= 2 and s[1]:
                stack.insert(0, (s[1], ind + 1))
            nxt = blk.get('next')
            if nxt: stack.insert(0, (nxt, ind))
            lines += 1
        elif op == 'control_wait':
            dur = resolve(ip.get('DURATION', [4, [10, '1']]))
            print(f'{"  "*ind}wait {dur}s')
            nxt = blk.get('next')
            if nxt: stack.insert(0, (nxt, ind))
            lines += 1
        elif op == 'control_stop':
            f = fl.get('STOP_OPTION', ['', 'this script'])
            print(f'{"  "*ind}stop [{f[0] if isinstance(f, list) else f}]')
            lines += 1
        elif op == 'data_setvariableto':
            val = resolve(ip.get('VALUE', [1, ['0']]))
            vn = '?'
            for fv in fl.values():
                if isinstance(fv, list) and len(fv) >= 2:
                    vn = var_names.get(fv[1], str(fv[1]))
            print(f'{"  "*ind}{vn} = {val}')
            nxt = blk.get('next')
            if nxt: stack.insert(0, (nxt, ind))
            lines += 1
        elif op == 'data_replaceitemoflist':
            idx = resolve(ip.get('INDEX', [4, [10, '1']]))
            item = resolve(ip.get('ITEM', [1, ['0']]))
            ln = '?'
            for fv in fl.values():
                if isinstance(fv, list) and len(fv) >= 2:
                    ln = list_names.get(fv[1], str(fv[1]))
            print(f'{"  "*ind}{ln}[{idx}] = {item}')
            nxt = blk.get('next')
            if nxt: stack.insert(0, (nxt, ind))
            lines += 1
        elif op == 'data_changevariableby':
            val = resolve(ip.get('VALUE', [4, [10, '1']]))
            vn = '?'
            for fv in fl.values():
                if isinstance(fv, list) and len(fv) >= 2:
                    vn = var_names.get(fv[1], str(fv[1]))
            print(f'{"  "*ind}{vn} += {val}')
            nxt = blk.get('next')
            if nxt: stack.insert(0, (nxt, ind))
            lines += 1
        elif op == 'procedures_call':
            mut = blk.get('mutation', {})
            pc = mut.get('proccode', '???')
            ca = [resolve(iv) for ik, iv in sorted(ip.items()) if ik != 'custom_block' and isinstance(iv, list) and len(iv) >= 2]
            print(f'{"  "*ind}{pc}({",".join(ca)})')
            nxt = blk.get('next')
            if nxt: stack.insert(0, (nxt, ind))
            lines += 1
        elif isinstance(op, str) and op == '__else__':
            print(f'{"  "*ind}else:')
            lines += 1
        else:
            line = op
            for ik, iv in sorted(ip.items()):
                if isinstance(iv, list) and len(iv) >= 2: line += ' ' + resolve(iv)
            for fv in fl.values():
                if isinstance(fv, list) and len(fv) >= 2: line += ' ' + str(fv[1])
            print(f'{"  "*ind}{line}')
            nxt = blk.get('next')
            if nxt: stack.insert(0, (nxt, ind))
            lines += 1

# Find and dump
targets = ['震源スタンプ', '震源スタンんプEEW', '最短点表示', '検出エフェクトなど']

for bid, block in blocks.items():
    if not isinstance(block, dict): continue
    if block.get('opcode') != 'procedures_definition': continue
    pbid = block.get('inputs', {}).get('custom_block', [None, None])
    proto_id = pbid[1] if isinstance(pbid, list) and len(pbid) >= 2 else None
    if not proto_id or proto_id not in blocks: continue
    proto = blocks[proto_id]
    proccode = proto.get('mutation', {}).get('proccode', '')
    if not any(t in proccode for t in targets): continue

    print(f'\n{"="*60}')
    print(f'DEF {proccode}')
    print(f'{"="*60}')
    nxt = block.get('next')
    if nxt:
        walk(nxt, 0, 40)
    print()
