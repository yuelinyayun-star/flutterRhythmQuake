import json

with open(r'd:\flutterApp\flutterrhythmquake\references\リアルタイム地震ビューアー\project_formatted.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

target = None
for t in data['targets']:
    if t['name'] == '受信と検出':
        target = t
        break
blocks = target['blocks']

def lib(bid, depth=0):
    if depth > 4 or bid is None: return '?'
    if isinstance(bid, (int, float)): return str(bid)
    if not isinstance(bid, str):
        if isinstance(bid, list) and len(bid) >= 2:
            t2, v2 = bid[0], bid[1]
            if t2 in (4,5,6,7,8): return str(v2)
            if t2 == 10: return '"'+str(v2)[:15]+'"'
        return '...'
    b = blocks.get(bid)
    if b is None: return 'BLK'
    op = b.get('opcode','')
    inp = b.get('inputs',{})
    if op == 'operator_not': return '!' + lib(inp.get('OPERAND',[None])[1], depth+1)
    if op == 'data_itemoflist':
        lf = b.get('fields',{}).get('LIST',['?'])[0]
        idx = lib(inp.get('INDEX',[None])[1], depth+1)
        return f'@{lf}[{idx}]'
    if op == 'operator_gt':
        return '(' + lib(inp.get('OPERAND1',[None])[1], depth+1) + ' > ' + lib(inp.get('OPERAND2',[None])[1], depth+1) + ')'
    if op == 'operator_lt':
        return '(' + lib(inp.get('OPERAND1',[None])[1], depth+1) + ' < ' + lib(inp.get('OPERAND2',[None])[1], depth+1) + ')'
    if op == 'operator_equals':
        return '(' + lib(inp.get('OPERAND1',[None])[1], depth+1) + ' == ' + lib(inp.get('OPERAND2',[None])[1], depth+1) + ')'
    if op == 'operator_and':
        return '(' + lib(inp.get('OPERAND1',[None])[1], depth+1) + ' AND ' + lib(inp.get('OPERAND2',[None])[1], depth+1) + ')'
    if op == 'operator_or':
        return '(' + lib(inp.get('OPERAND1',[None])[1], depth+1) + ' OR ' + lib(inp.get('OPERAND2',[None])[1], depth+1) + ')'
    return '[op]'

# Extract complete subtree for gP
print("=== gP full subtree ===")
def subtree(bid, indent=0):
    b = blocks.get(bid)
    if b is None: return
    op = b.get('opcode','')
    pr = '  ' * indent
    if op == 'procedures_call':
        pc = b.get('mutation',{}).get('proccode','?')
        arg1 = lib(b.get('inputs',{}).get('first_arg', [None])[1])
        print(f'{pr}CALL {pc}({arg1},...)')
    elif op == 'data_setvariableto':
        vn = b.get('fields',{}).get('VARIABLE',['?'])[0]
        val = lib(b.get('inputs',{}).get('VALUE',[None])[1])
        print(f'{pr}SET {vn} = {val}')
    elif op == 'control_if':
        cond = lib(b.get('inputs',{}).get('CONDITION',[None])[1])
        sub = b.get('inputs',{}).get('SUBSTACK',[None])
        print(f'{pr}IF {cond}:')
        if isinstance(sub, list) and len(sub)>=2: subtree(sub[1], indent+1)
    elif op == 'control_if_else':
        cond = lib(b.get('inputs',{}).get('CONDITION',[None])[1])
        sub1 = b.get('inputs',{}).get('SUBSTACK',[None])
        sub2 = b.get('inputs',{}).get('SUBSTACK2',[None])
        print(f'{pr}IF {cond}:')
        if isinstance(sub1, list) and len(sub1)>=2:
            print(f'{pr}  THEN:')
            subtree(sub1[1], indent+2)
        if isinstance(sub2, list) and len(sub2)>=2:
            print(f'{pr}  ELSE:')
            subtree(sub2[1], indent+2)
    else:
        print(f'{pr}[{op}]')
    nxt = b.get('next')
    if nxt: subtree(nxt, indent)

# gP contains a control_if as its SUBSTACK
b_gp = blocks.get('gP')
sub = b_gp.get('inputs',{}).get('SUBSTACK',[None])
if isinstance(sub, list) and len(sub)>=2:
    subtree(sub[1])

print("\n=== Kk full subtree ===")
b_kk = blocks.get('Kk')
sub = b_kk.get('inputs',{}).get('SUBSTACK',[None])
if isinstance(sub, list) and len(sub)>=2:
    subtree(sub[1])

# Also look at what aL's branches do
print("\n=== aL full ===")
b_al = blocks.get('aL')
op = b_al.get('opcode')
cond = lib(b_al.get('inputs',{}).get('CONDITION',[None])[1])
sub1 = b_al.get('inputs',{}).get('SUBSTACK',[None])
sub2 = b_al.get('inputs',{}).get('SUBSTACK2',[None])
print(f'aL: IF {cond}:')
if isinstance(sub1, list) and len(sub1)>=2:
    print("  THEN:")
    subtree(sub1[1], 2)
if isinstance(sub2, list) and len(sub2)>=2:
    print("  ELSE:")
    subtree(sub2[1], 2)
