import json

with open(r'd:\flutterApp\flutterrhythmquake\references\リアルタイム地震ビューアー\project_formatted.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

target = None
for t in data['targets']:
    if t['name'] == '受信と検出':
        target = t
        break
blocks = target['blocks']

b = blocks.get('aO')
print("=== aO (control_if_else IF 設定[51]) ===")
print(json.dumps(b, indent=2, ensure_ascii=False)[:3000])
