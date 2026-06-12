import json, os

path = os.path.join(os.environ['TEMP'], 'sb3_old', 'project.json')
data = json.load(open(path, 'r', encoding='utf-8'))

for t in data.get('targets', []):
    if t.get('name') != 'P/S計算': continue
    blocks = t.get('blocks', {})
    
    # Show the flag clicked handler and FOREVER loop
    for bid in ['za', 'ox', 'oJ', 'oK']:
        b = blocks.get(bid)
        if b:
            print(f"\n{bid}: {json.dumps(b, indent=2, ensure_ascii=False)[:500]}")
    
    # Also check what oK looks like
    ok = blocks.get('oK')
    if ok:
        print(f"\noK full: {json.dumps(ok, indent=2, ensure_ascii=False)}")
    break
