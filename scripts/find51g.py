import json

with open(r'd:\flutterApp\flutterrhythmquake\references\リアルタイム地震ビューアー\project_formatted.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

target = None
for t in data['targets']:
    if t['name'] == '受信と検出':
        target = t
        break
blocks = target['blocks']

# Find blocks that reference at] or aBB
for bid, b in blocks.items():
    if not isinstance(b, dict): continue
    for k, v in b.get('inputs', {}).items():
        if isinstance(v, list) and len(v) >= 2 and v[1] in ('at]', 'aBB'):
            print(f"REF: {bid} ({b.get('opcode')}) references '{v[1]}' in input '{k}'")
            # Print the full condition
            if b.get('opcode') == 'control_if':
                print(f"  IF condition block: {v[1]}")
                sub = b.get('inputs',{}).get('SUBSTACK',[None])
                if isinstance(sub, list) and len(sub)>=2:
                    # Show what happens
                    sb = blocks.get(sub[1])
                    if sb:
                        op = sb.get('opcode')
                        if op == 'procedures_call':
                            print(f"    THEN: CALL {sb.get('mutation',{}).get('proccode','?')}")
                        else:
                            print(f"    THEN: {op}")
            # Show parent chain to find WHERE this sits
            par = b.get('parent')
            for i in range(3):
                if par is None: break
                pb = blocks.get(par)
                if pb is None: break
                print(f"  parent[{i}]={par}: {pb.get('opcode')}")
                par = pb.get('parent')
            print()
