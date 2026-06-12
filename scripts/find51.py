import json, sys

with open(r'd:\flutterApp\flutterrhythmquake\references\リアルタイム地震ビューアー\project_formatted.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

for t in data['targets']:
    blocks = t.get('blocks',{})
    for bid, b in blocks.items():
        if not isinstance(b, dict): continue
        fields = b.get('fields', {})
        inputs = b.get('inputs', {})
        # Check fields
        for k, v in fields.items():
            s = str(v)
            if '51' in s and ('設定' in s or 'システム' in s):
                print(f"FOUND field: {t['name']} / {bid} / {b.get('opcode')}")
                print(f"  field {k}: {v}")
                print(f"  full block fields: { {k2: str(v2)[:80] for k2,v2 in fields.items()} }")
                print()
        for k, v in inputs.items():
            s = str(v)
            if '51' in s and ('設定' in s or 'システム' in s):
                print(f"FOUND input: {t['name']} / {bid} / {b.get('opcode')}")
                print(f"  input {k}: {v}")
                print()
