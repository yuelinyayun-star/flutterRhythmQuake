import json

with open(r'd:\flutterApp\flutterrhythmquake\references\リアルタイム地震ビューアー\project_formatted.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

target = None
for t in data['targets']:
    if t['name'] == '受信と検出':
        target = t
        break
blocks = target['blocks']

def show_chain(bid, max_depth=10):
    nxt = bid
    for i in range(max_depth):
        if nxt is None: break
        b = blocks.get(nxt)
        if b is None: break
        op = b.get('opcode','')
        inp = b.get('inputs',{})
        fields = b.get('fields',{})
        
        if op == 'control_if':
            cond = lib(inp.get('CONDITION',[None])[1])
            sub = inp.get('SUBSTACK',[None])
            print(f"  IF {cond}")
            if isinstance(sub, list) and len(sub)>=2:
                show_chain(sub[1], max_depth=3)
        elif op == 'control_if_else':
            cond = lib(inp.get('CONDITION',[None])[1])
            sub1 = inp.get('SUBSTACK',[None])
            sub2 = inp.get('SUBSTACK2',[None])
            print(f"  IF {cond}")
            if isinstance(sub1, list) and len(sub1)>=2:
                print(f"    THEN:")
                show_chain(sub1[1], max_depth=3)
            if isinstance(sub2, list) and len(sub2)>=2:
                print(f"    ELSE:")
                show_chain(sub2[1], max_depth=3)
        elif op == 'procedures_call':
            pc = b.get('mutation',{}).get('proccode','?')
            print(f"    CALL {pc}")
        elif op == 'data_setvariableto':
            vn = fields.get('VARIABLE',['?'])[0]
            print(f"    SET {vn}")
        elif op == 'control_stop':
            print(f"    STOP")
        else:
            pass
        
        nxt = b.get('next')

def lib(bid, depth=0):
    if depth > 3 or bid is None: return '?'
    if isinstance(bid, (int, float)): return str(bid)
    if not isinstance(bid, str):
        if isinstance(bid, list) and len(bid) >= 2:
            t2, v2 = bid[0], bid[1]
            if t2 in (4,5,6,7,8): return str(v2)
            if t2 == 10: return '"' + str(v2)[:20] + '"'
        return '...'
    b = blocks.get(bid)
    if b is None: return '?'
    op = b.get('opcode','')
    inp = b.get('inputs',{})
    if op == 'operator_not': return 'NOT(' + lib(inp.get('OPERAND',[None])[1], depth+1) + ')'
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
    return '['+op[:8]+']'

# Shortened reachable output
# aL is a control_if_else
# gN -> gO -> gP -> at]
# Let me find the actual position of these in 単独トリガ

# Find the grandparent aL
print("=== aL context ===")
b_al = blocks.get('aL')
if b_al:
    op = b_al.get('opcode')
    cond = lib(b_al.get('inputs',{}).get('CONDITION',[None])[1])
    print(f"aL ({op}): IF {cond}")

# Now find gN (child of aL)
b_gn = blocks.get('gN')
if b_gn:
    cond = lib(b_gn.get('inputs',{}).get('CONDITION',[None])[1])
    print(f"  gN ({b_gn.get('opcode')}): IF {cond}")

b_go = blocks.get('gO')
if b_go:
    cond = lib(b_go.get('inputs',{}).get('CONDITION',[None])[1])
    print(f"    gO ({b_go.get('opcode')}): IF {cond}")

b_gp = blocks.get('gP')
if b_gp:
    cond = lib(b_gp.get('inputs',{}).get('CONDITION',[None])[1])
    print(f"      gP ({b_gp.get('opcode')}): IF {cond}")
    # What happens inside?
    sub = b_gp.get('inputs',{}).get('SUBSTACK',[None])
    print(f"        input: {lib(sub[1]) if isinstance(sub,list) and len(sub)>=2 else sub}")
    if isinstance(sub, list) and len(sub)>=2:
        sb = blocks.get(sub[1])
        if sb:
            print(f"        THEN: {sb.get('opcode')}")
            if sb.get('opcode') == 'procedures_call':
                print(f"          {sb.get('mutation',{}).get('proccode','?')}")

print("\n=== aBA context ===")
b_aba = blocks.get('aBA')  # procedures_definition
if b_aba:
    pc = b_aba.get('mutation',{}).get('proccode','?')
    print(f"Procedure: {pc}")

b_kk = blocks.get('Kk')
if b_kk:
    cond = lib(b_kk.get('inputs',{}).get('CONDITION',[None])[1])
    print(f"Kk: IF {cond}")
    sub = b_kk.get('inputs',{}).get('SUBSTACK',[None])
    if isinstance(sub, list) and len(sub)>=2:
        sb = blocks.get(sub[1])
        if sb:
            print(f"  THEN: {sb.get('opcode')}")
            if sb.get('opcode') == 'procedures_call':
                print(f"    {sb.get('mutation',{}).get('proccode','?')}")
