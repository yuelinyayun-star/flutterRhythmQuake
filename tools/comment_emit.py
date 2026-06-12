# Clean up wolfx_service.dart: properly remove all old emit() blocks
path = r'd:\flutterApp\flutterrhythmquake\lib\services\sources\wolfx_service.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

lines = content.split('\n')
out = []
i = 0
while i < len(lines):
    s = lines[i].strip()
    # Detect start of emit block (active or already partially commented)
    if s.startswith('emit(') or s.startswith('// emit('):
        # Aggressively skip until first ");" line that closes QuakeMessage
        # Collect all lines to determine block end
        j = i
        found_end = False
        while j < len(lines):
            if lines[j].strip() in (');', '// );'):
                found_end = True
                break
            j += 1
        if found_end:
            out.append('      // 旧管道已关闭，统一走新管道 (emitUnified)')
            i = j + 1
            # Skip blank lines after
            while i < len(lines) and lines[i].strip() == '':
                i += 1
            continue
    out.append(lines[i])
    i += 1

with open(path, 'w', encoding='utf-8') as f:
    f.write('\n'.join(out))
print('Done - all old emit() blocks removed')
