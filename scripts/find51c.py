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
            if t2 == 12: return '$' + str(v2)[:20]
        return str(bid)[:50]
    b = blocks.get(bid)
    if b is None: return 'BLK:'+bid[:8]
    op = b.get('opcode','')
    if op == 'data_itemoflist':
        lf = b.get('fields',{}).get('LIST',['?'])[0]
        idx = lit(b.get('inputs',{}).get('INDEX',[None])[1], depth+1)
        return f'@{lf}[{idx}]'
    return '['+op[:12]+']'

# Show surrounding blocks for each usage
for bid in ['b+[', 'b.v', 'b=x']:
    print(f"\n=== Context for {bid} ===")
    b = blocks.get(bid)
    if b is None: continue
    # Walk backwards
    print(f"Block {bid}: {b.get('opcode')}")
    # Walk forward a bit
    nxt = b.get('next')
    for i in range(5):
        if nxt is None: break
        nb = blocks.get(nxt)
        if nb is None: break
        print(f"  → {nxt}: {nb.get('opcode')}")
        for k, v in nb.get('inputs',{}).items():
            print(f"      {k}={lit(v[1]) if isinstance(v,list) and len(v)>=2 else str(v)[:60]}")
        nxt = nb.get('next')

    # Walk backwards (parent)
    par = b.get('parent')
    if par:
        pb = blocks.get(par)
        if pb:
            print(f"  parent {par}: {pb.get('opcode')}")
            # Show condition
            cond = pb.get('inputs',{}).get('CONDITION',[None])
            if cond and isinstance(cond, list) and len(cond)>=2:
                print(f"    condition={lit(cond[1])}")
