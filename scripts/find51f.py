import json

with open(r'd:\flutterApp\flutterrhythmquake\references\リアルタイム地震ビューアー\project_formatted.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

target = None
for t in data['targets']:
    if t['name'] == '受信と検出':
        target = t
        break
blocks = target['blocks']

def lit(bid, depth=0):
    if depth > 4 or bid is None: return '?'
    if isinstance(bid, (int, float)): return str(bid)
    if not isinstance(bid, str):
        if isinstance(bid, list) and len(bid) >= 2:
            t2, v2 = bid[0], bid[1]
            if t2 in (4,5,6,7,8): return str(v2)
            if t2 == 10: return '"' + str(v2)[:30] + '"'
        return str(bid)[:50]
    b = blocks.get(bid)
    if b is None: return '?'
    op = b.get('opcode','')
    inp = b.get('inputs',{})
    if op == 'operator_not':
        return 'NOT(' + lit(inp.get('OPERAND',[None])[1], depth+1) + ')'
    if op == 'data_itemoflist':
        lf = b.get('fields',{}).get('LIST',['?'])[0]
        idx = lit(inp.get('INDEX',[None])[1], depth+1)
        return f'@{lf}[{idx}]'
    if op == 'operator_gt':
        return '(' + lit(inp.get('OPERAND1',[None])[1], depth+1) + ' > ' + lit(inp.get('OPERAND2',[None])[1], depth+1) + ')'
    if op == 'operator_lt':
        return '(' + lit(inp.get('OPERAND1',[None])[1], depth+1) + ' < ' + lit(inp.get('OPERAND2',[None])[1], depth+1) + ')'
    if op == 'operator_equals':
        return '(' + lit(inp.get('OPERAND1',[None])[1], depth+1) + ' == ' + lit(inp.get('OPERAND2',[None])[1], depth+1) + ')'
    if op == 'operator_and':
        return '(' + lit(inp.get('OPERAND1',[None])[1], depth+1) + ' AND ' + lit(inp.get('OPERAND2',[None])[1], depth+1) + ')'
    if op == 'operator_or':
        return '(' + lit(inp.get('OPERAND1',[None])[1], depth+1) + ' OR ' + lit(inp.get('OPERAND2',[None])[1], depth+1) + ')'
    if op == 'operator_subtract':
        return '(' + lit(inp.get('NUM1',[None])[1], depth+1) + ' - ' + lit(inp.get('NUM2',[None])[1], depth+1) + ')'
    if op == 'operator_mathop':
        fop = b.get('fields',{}).get('OPERATOR',['?'])[0]
        return fop + '(' + lit(inp.get('NUM',[None])[1], depth+1) + ')'
    if op == 'argument_reporter_string_number':
        return str(b.get('fields',{}).get('VALUE',['?'])[0])
    vv = b.get('fields', {}).get('VARIABLE', ['?'])
    if vv and vv[0] != '?':
        return '$' + str(vv[0])[:20]
    return '['+op[:10]+']'

# Look at awE and awF - they call 点許可状態更新
def show_call(bid, name, depth=0):
    b = blocks.get(bid)
    if b is None: return
    pc = b.get('mutation',{}).get('proccode','?')
    args = b.get('inputs',{})
    arg_strs = {}
    for k, v in args.items():
        if isinstance(v, list) and len(v) >= 2:
            arg_strs[k] = lit(v[1], depth+1)
    print(f"{name}: {pc}")
    for k, v in arg_strs.items():
        print(f"  {k}: {v}")

show_call('awE', 'awE (THEN)')
print()
show_call('awF', 'awF (ELSE)')

# Now look at parent of aO which is 'If'
# Walk the full chain that contains aO
print("\n=== Full chain containing aO ===")
# Find blocks whose next == 'aO' directly or after a few hops
# Or find the outer control block whose SUBSTACK contains aO
# aO's parent is 'If'
# First find what 'If' is
b_if = blocks.get('If')
if b_if:
    print(f"'If' block: {b_if.get('opcode')}")
    print(json.dumps(b_if, indent=2, ensure_ascii=False)[:2000])

# The parent chain: aO → If → ... → eventually the main flow
# Let me also check the 'If' parent
if b_if and 'parent' in b_if:
    par2 = blocks.get(b_if['parent'])
    if par2:
        print(f"\n'If' parent ({b_if['parent']}): {par2.get('opcode')}")
        pc = par2.get('next')
        if pc:
            pb = blocks.get(pc)
            print(f"  next: {pc}: {pb.get('opcode') if pb else '?'}")
