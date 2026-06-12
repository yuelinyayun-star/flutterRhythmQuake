"""Dump specific procedures from sb3 project.json"""
import json, os

sb3_path = os.path.join(os.environ.get('TEMP', '.'), 'sb3_extract', 'project.json')
with open(sb3_path, 'r', encoding='utf-8') as f:
    data = json.load(f)

for t in data['targets']:
    if t.get('name') == '受信と検出':
        tgt = t; break

blocks = tgt['blocks']
comments = tgt.get('comments', {})

# Collect all variables and lists
var_names = {}
list_names = {}
for bid, block in blocks.items():
    if not isinstance(block, dict): continue
    for fk, fv in block.get('fields', {}).items():
        if isinstance(fv, list) and len(fv) >= 2:
            fid = fv[0] if isinstance(fv[0], str) else str(fv[0])
            if fk == 'VARIABLE':
                var_names[fid] = str(fv[1])
            elif fk == 'LIST':
                list_names[fid] = str(fv[1])

def resolve(expr, depth=0):
    if depth > 5: return '...'
    if not isinstance(expr, list) or len(expr) < 2:
        return str(expr)
    t, val = expr[0], expr[1]

    if t == 1:  # shadow
        if isinstance(val, list) and len(val) >= 2:
            inner_t, inner_v = val[0], val[1]
            if inner_t == 11:
                return var_names.get(inner_v[1] if isinstance(inner_v, list) and len(inner_v) >= 2 else inner_v, f'V:{inner_v}')
            if inner_t == 12:
                return list_names.get(inner_v[1] if isinstance(inner_v, list) and len(inner_v) >= 2 else inner_v, f'L:{inner_v}')
            return str(inner_v)
        return str(val)

    elif t == 2: return 'HIDDEN'
    elif t == 3 and isinstance(val, str):
        return resolve_block(val, depth + 1)

    elif t in (4,5,6,7):
        if isinstance(val, list) and len(val) >= 2: return str(val[1])
        return str(val)

    elif t >= 11:
        if isinstance(val, list) and len(val) >= 2:
            name = var_names.get(val[1], list_names.get(val[1], str(val[1])))
            return name
        return str(val)

    return f't{t}:{val}'

def resolve_block(bid, depth=0):
    if depth > 5: return '...'
    blk = blocks.get(bid)
    if not isinstance(blk, dict): return str(blk)
    op = blk.get('opcode', '?')
    inputs = blk.get('inputs', {})
    fields = blk.get('fields', {})

    # Collect args
    args = []
    for ik in sorted(inputs.keys()):
        iv = inputs[ik]
        if isinstance(iv, list) and len(iv) >= 2:
            args.append(resolve(iv, depth))

    fargs = []
    for fk, fv in sorted(fields.items()):
        if isinstance(fv, list) and len(fv) >= 2:
            fargs.append(str(fv[1]))

    # Operators
    if op == 'operator_add':
        return f'({args[0] if args else "?"} + {args[1] if len(args)>1 else "?"})'
    elif op == 'operator_subtract':
        return f'({args[0] if args else "?"} - {args[1] if len(args)>1 else "?"})'
    elif op == 'operator_multiply':
        return f'({args[0] if args else "?"} * {args[1] if len(args)>1 else "?"})'
    elif op == 'operator_divide':
        return f'({args[0] if args else "?"} / {args[1] if len(args)>1 else "?"})'
    elif op == 'data_itemoflist':
        return f'{args[1] if len(args)>1 else "?"}[{args[0] if args else "?"}]'
    elif op == 'argument_reporter_string_number':
        return fargs[0] if fargs else 'ARG'
    elif op == 'operator_gt':
        return f'({args[0] if args else "?"} > {args[1] if len(args)>1 else "?"})'
    elif op == 'operator_lt':
        return f'({args[0] if args else "?"} < {args[1] if len(args)>1 else "?"})'
    elif op == 'operator_equals':
        return f'({args[0] if args else "?"} == {args[1] if len(args)>1 else "?"})'
    elif op == 'operator_and':
        return f'({args[0] if args else "?"} AND {args[1] if len(args)>1 else "?"})'
    elif op == 'operator_or':
        return f'({args[0] if args else "?"} OR {args[1] if len(args)>1 else "?"})'
    elif op == 'operator_mathop':
        return f'MATH({",".join(args)})'
    elif op == 'operator_round':
        return f'ROUND({",".join(args)})'
    elif op == 'operator_length':
        return f'LEN({",".join(args)})'
    elif op == 'operator_contains':
        return f'CONTAINS({",".join(args)})'
    elif op == 'operator_mod':
        return f'({args[0] if args else "?"} MOD {args[1] if len(args)>1 else "?"})'
    elif op == 'operator_join':
        return f'JOIN({",".join(args)})'
    elif op == 'operator_random':
        return f'RANDOM({",".join(args)})'
    elif op == 'procedures_call':
        mut = blk.get('mutation', {})
        pc = mut.get('proccode', '???')
        call_args = [(k, resolve(v, depth)) for k, v in inputs.items() if k != 'custom_block' and isinstance(v, list) and len(v) >= 2]
        return f'{pc}({", ".join([v for _,v in call_args])})'
    elif op == 'sensing_of':
        return f'SENSING({",".join(args)})'

    return f'{op}[{",".join(args + fargs)}]'

# Walk statement chain
def walk_statements(bid, indent=0, max_lines=50):
    seen = set()
    stack = [(bid, indent, 'next')]
    lines = 0

    while stack and lines < max_lines:
        b, ind, mode = stack.pop(0)
        if b is None or b in seen: continue
        seen.add(b)
        blk = blocks.get(b)
        if not isinstance(blk, dict): continue

        op = blk.get('opcode', '?')
        inputs = blk.get('inputs', {})
        fields = blk.get('fields', {})

        if op == 'control_if':
            cond = resolve(inputs.get('CONDITION', [2, '?']))
            print(f'{"  "*ind}if {cond}:')
            substack = inputs.get('SUBSTACK', [3, None])
            if isinstance(substack, list) and len(substack) >= 2 and substack[1]:
                stack.insert(0, (substack[1], ind + 1, 'substack'))
            nxt = blk.get('next')
            if nxt: stack.insert(0, (nxt, ind, 'next'))
            lines += 1

        elif op == 'control_if_else':
            cond = resolve(inputs.get('CONDITION', [2, '?']))
            print(f'{"  "*ind}if {cond}:')
            s1 = inputs.get('SUBSTACK', [3, None])
            s2 = inputs.get('SUBSTACK2', [3, None])
            if isinstance(s1, list) and len(s1) >= 2 and s1[1]:
                stack.insert(0, (s1[1], ind + 1, 'substack'))
            if isinstance(s2, list) and len(s2) >= 2 and s2[1]:
                stack.insert(1, ('__else__', ind, 'else'))
                stack.insert(2, (s2[1], ind + 1, 'substack'))
            nxt = blk.get('next')
            if nxt: stack.insert(0, (nxt, ind, 'next'))
            lines += 1

        elif op == '__else__':
            print(f'{"  "*ind}else:')
            lines += 1

        elif op == 'control_repeat':
            cnt = resolve(inputs.get('TIMES', [4, [10, '1']]))
            print(f'{"  "*ind}repeat {cnt}:')
            substack = inputs.get('SUBSTACK', [3, None])
            if isinstance(substack, list) and len(substack) >= 2 and substack[1]:
                stack.insert(0, (substack[1], ind + 1, 'substack'))
            nxt = blk.get('next')
            if nxt: stack.insert(0, (nxt, ind, 'next'))
            lines += 1

        elif op == 'control_repeat_until':
            cond = resolve(inputs.get('CONDITION', [2, '?']))
            print(f'{"  "*ind}repeat until {cond}:')
            substack = inputs.get('SUBSTACK', [3, None])
            if isinstance(substack, list) and len(substack) >= 2 and substack[1]:
                stack.insert(0, (substack[1], ind + 1, 'substack'))
            nxt = blk.get('next')
            if nxt: stack.insert(0, (nxt, ind, 'next'))
            lines += 1

        elif op == 'control_forever':
            print(f'{"  "*ind}forever:')
            substack = inputs.get('SUBSTACK', [3, None])
            if isinstance(substack, list) and len(substack) >= 2 and substack[1]:
                stack.insert(0, (substack[1], ind + 1, 'substack'))
            lines += 1

        elif op == 'control_wait':
            dur = resolve(inputs.get('DURATION', [4, [10, '1']]))
            print(f'{"  "*ind}wait {dur} sec')
            nxt = blk.get('next')
            if nxt: stack.insert(0, (nxt, ind, 'next'))
            lines += 1

        elif op == 'control_wait_until':
            cond = resolve(inputs.get('CONDITION', [2, '?']))
            print(f'{"  "*ind}wait until {cond}')
            nxt = blk.get('next')
            if nxt: stack.insert(0, (nxt, ind, 'next'))
            lines += 1

        elif op == 'control_stop':
            fld = fields.get('STOP_OPTION', ['', 'this script'])
            print(f'{"  "*ind}stop [{fld[0] if isinstance(fld, list) else fld}]')
            lines += 1

        elif op == 'data_setvariableto':
            val = resolve(inputs.get('VALUE', [1, ['0']]))
            vname = '?'
            for fv in fields.values():
                if isinstance(fv, list) and len(fv) >= 2:
                    vname = var_names.get(fv[1], str(fv[1]))
            print(f'{"  "*ind}{vname} = {val}')
            nxt = blk.get('next')
            if nxt: stack.insert(0, (nxt, ind, 'next'))
            lines += 1

        elif op == 'data_changevariableby':
            val = resolve(inputs.get('VALUE', [4, [10, '1']]))
            vname = '?'
            for fv in fields.values():
                if isinstance(fv, list) and len(fv) >= 2:
                    vname = var_names.get(fv[1], str(fv[1]))
            print(f'{"  "*ind}{vname} += {val}')
            nxt = blk.get('next')
            if nxt: stack.insert(0, (nxt, ind, 'next'))
            lines += 1

        elif op == 'data_replaceitemoflist':
            idx = resolve(inputs.get('INDEX', [4, [10, '1']]))
            item = resolve(inputs.get('ITEM', [1, ['0']]))
            lname = '?'
            for fv in fields.values():
                if isinstance(fv, list) and len(fv) >= 2:
                    lname = list_names.get(fv[1], str(fv[1]))
            print(f'{"  "*ind}{lname}[{idx}] = {item}')
            nxt = blk.get('next')
            if nxt: stack.insert(0, (nxt, ind, 'next'))
            lines += 1

        elif op == 'data_deleteoflist':
            idx = resolve(inputs.get('INDEX', [4, [10, '1']]))
            lname = '?'
            for fv in fields.values():
                if isinstance(fv, list) and len(fv) >= 2:
                    lname = list_names.get(fv[1], str(fv[1]))
            print(f'{"  "*ind}delete {lname}[{idx}]')
            nxt = blk.get('next')
            if nxt: stack.insert(0, (nxt, ind, 'next'))
            lines += 1

        elif op == 'data_deletealloflist':
            lname = '?'
            for fv in fields.values():
                if isinstance(fv, list) and len(fv) >= 2:
                    lname = list_names.get(fv[1], str(fv[1]))
            print(f'{"  "*ind}delete all {lname}')
            nxt = blk.get('next')
            if nxt: stack.insert(0, (nxt, ind, 'next'))
            lines += 1

        elif op == 'data_inserttolist':
            idx = resolve(inputs.get('INDEX', [4, [10, '1']]))
            item = resolve(inputs.get('ITEM', [1, ['0']]))
            lname = '?'
            for fv in fields.values():
                if isinstance(fv, list) and len(fv) >= 2:
                    lname = list_names.get(fv[1], str(fv[1]))
            print(f'{"  "*ind}{lname}.insert({idx}, {item})')
            nxt = blk.get('next')
            if nxt: stack.insert(0, (nxt, ind, 'next'))
            lines += 1

        elif op == 'data_listcontainsitem':
            item = resolve(inputs.get('ITEM', [1, ['0']]))
            lname = '?'
            for fv in fields.values():
                if isinstance(fv, list) and len(fv) >= 2:
                    lname = list_names.get(fv[1], str(fv[1]))
            print(f'{"  "*ind}{lname}.contains({item})')
            nxt = blk.get('next')
            if nxt: stack.insert(0, (nxt, ind, 'next'))
            lines += 1

        elif op == 'data_lengthoflist':
            lname = '?'
            for fv in fields.values():
                if isinstance(fv, list) and len(fv) >= 2:
                    lname = list_names.get(fv[1], str(fv[1]))
            print(f'{"  "*ind}len({lname})')
            nxt = blk.get('next')
            if nxt: stack.insert(0, (nxt, ind, 'next'))
            lines += 1

        elif op == 'procedures_call':
            mut = blk.get('mutation', {})
            pc = mut.get('proccode', '???')
            call_args = []
            for ik, iv in sorted(inputs.items()):
                if ik == 'custom_block': continue
                if isinstance(iv, list) and len(iv) >= 2:
                    call_args.append(resolve(iv))
            print(f'{"  "*ind}{pc}({", ".join(call_args)})')
            nxt = blk.get('next')
            if nxt: stack.insert(0, (nxt, ind, 'next'))
            lines += 1

        elif op == 'event_broadcast' or op == 'event_broadcastandwait':
            fv = fields.get('BROADCAST_OPTION', ['', '?'])
            bname = fv[0] if isinstance(fv, list) and len(fv) >= 1 else str(fv)
            print(f'{"  "*ind}broadcast("{bname}")')
            nxt = blk.get('next')
            if nxt: stack.insert(0, (nxt, ind, 'next'))
            lines += 1

        else:
            line = op
            for ik, iv in sorted(inputs.items()):
                if isinstance(iv, list) and len(iv) >= 2:
                    line += ' ' + resolve(iv)
            for fv in fields.values():
                if isinstance(fv, list) and len(fv) >= 2:
                    line += ' ' + str(fv[1])
            print(f'{"  "*ind}{line}')
            nxt = blk.get('next')
            if nxt: stack.insert(0, (nxt, ind, 'next'))
            lines += 1

# Find and dump target procedures
targets = ['点-震源 距離計算', 'JMA2001距離近似', '緯度経度で距離km', '円の中か判定']

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

    next_id = block.get('next')
    if next_id:
        walk_statements(next_id, 0, 60)
    print()
