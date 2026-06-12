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
    if op == 'operator_and':
        return '(' + lit(inp.get('OPERAND1',[None])[1], depth+1) + ' AND ' + lit(inp.get('OPERAND2',[None])[1], depth+1) + ')'
    if op == 'operator_or':
        return '(' + lit(inp.get('OPERAND1',[None])[1], depth+1) + ' OR ' + lit(inp.get('OPERAND2',[None])[1], depth+1) + ')'
    if op == 'operator_subtract':
        return '(' + lit(inp.get('NUM1',[None])[1], depth+1) + ' - ' + lit(inp.get('NUM2',[None])[1], depth+1) + ')'
    return '['+op[:10]+']'

def walk_siblings(bid, prefix='', max_depth=10):
    """Walk the chain showing block content"""
    nxt = bid
    for i in range(max_depth):
        if nxt is None: break
        b = blocks.get(nxt)
        if b is None: break
        op = b.get('opcode','')
        inp = b.get('inputs',{})
        fields = b.get('fields',{})
        
        if op == 'procedures_call':
            pc = b.get('mutation',{}).get('proccode','?')
            print(f'{prefix}{nxt}: CALL {pc}')
        elif op == 'data_setvariableto':
            vn = fields.get('VARIABLE',['?'])[0]
            val = lit(inp.get('VALUE',[None])[1])
            print(f'{prefix}{nxt}: SET {vn} = {val}')
        elif op == 'control_if':
            cond = lit(inp.get('CONDITION',[None])[1])
            sub = inp.get('SUBSTACK',[None])
            print(f'{prefix}{nxt}: IF {cond}')
            if isinstance(sub, list) and len(sub)>=2:
                walk_siblings(sub[1], prefix+'  SUB: ')
        elif op == 'control_if_else':
            cond = lit(inp.get('CONDITION',[None])[1])
            sub = inp.get('SUBSTACK',[None])
            sub2 = inp.get('SUBSTACK2',[None])
            print(f'{prefix}{nxt}: IF {cond}')
            if isinstance(sub, list) and len(sub)>=2:
                print(f'{prefix}  THEN:')
                walk_siblings(sub[1], prefix+'    ')
            if isinstance(sub2, list) and len(sub2)>=2:
                print(f'{prefix}  ELSE:')
                walk_siblings(sub2[1], prefix+'    ')
        elif op == 'control_stop':
            print(f'{prefix}{nxt}: STOP')
        elif op == 'operator_not':
            print(f'{prefix}{nxt}: NOT(...)')
        else:
            print(f'{prefix}{nxt}: {op}')
        
        # Skip past control structures to next sibling
        nxt = b.get('next')

# Parent aO uses v or b.v  
print("=== Parent aO (IF 設定[51]) ===")
walk_siblings('aO', max_depth=15)

# Parent at] uses b+[
print("\n=== Parent at] (NOT(設定[51])) ===")
walk_siblings('at]', max_depth=15)

# aBB uses b=x
print("\n=== Parent aBB (NOT(設定[51])) ===")
walk_siblings('aBB', max_depth=15)
