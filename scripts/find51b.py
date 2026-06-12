import json

with open(r'd:\flutterApp\flutterrhythmquake\references\リアルタイム地震ビューアー\project_formatted.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

for t in data['targets']:
    blocks = t.get('blocks',{})
    for bid, b in blocks.items():
        if not isinstance(b, dict): continue
        fields = b.get('fields', {})
        inputs = b.get('inputs', {})
        s = json.dumps(b, ensure_ascii=False)
        if 'シス' in s and '51' in s:
            print(f"TARGET: {t['name']} / {bid} / {b.get('opcode')}")
            # Print all inputs and fields  
            for k, v in inputs.items():
                print(f"  input {k}: {v}")
            for k, v in fields.items():
                print(f"  field {k}: {v}")
            print()

print("\n=== looking for 設定 variable definition ===")
for t in data['targets']:
    for k, v in t.get('variables', {}).items():
        if '設定' in str(k):
            print(f"  {t['name']}: var {k} = {v}")
    for k,v in t.get('lists', {}).items():
        if '設定' in str(k):
            print(f"  {t['name']}: list {k} = {v}")
