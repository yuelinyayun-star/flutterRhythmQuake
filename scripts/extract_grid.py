import json

with open(r'd:\flutterApp\flutterrhythmquake\references\リアルタイム地震ビューアー\project_formatted.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

stage = data['targets'][0]  # Stage
lists = stage.get('lists', {})

def get_list(name):
    for k, v in lists.items():
        if isinstance(v, list) and len(v) >= 2 and v[0] == name:
            return v[1]
    return None

area_codes = get_list('d ten:\u89b3\u6e2c\u70b9\u6240\u5c5e\u533a\u57df')
henkan = get_list('\u7d30\u5206\u533a\u57df\u9023\u756a-\u5909\u63db')

# Build area_code -> sub_index (1-based)
area_to_idx = {}
if henkan:
    for i, code in enumerate(henkan):
        if isinstance(code, str) and code != '':
            code_i = int(float(code))
            if code_i not in area_to_idx:
                area_to_idx[code_i] = i + 1
        elif isinstance(code, (int, float)):
            code_i = int(code)
            if code_i not in area_to_idx:
                area_to_idx[code_i] = i + 1

print(f"area codes: {len(area_codes)}")
print(f"henkan: {len(henkan)}, unique areas: {len(area_to_idx)}")

# Build station_to_sub: 0-based station index -> 1-based sub-area
station_to_sub = []
for code in area_codes:
    if isinstance(code, str) and code != '':
        code_i = int(float(code))
    elif isinstance(code, (int, float)):
        code_i = int(code)
    else:
        code_i = -1
    sub = area_to_idx.get(code_i, -1)
    station_to_sub.append(sub)

used = set(station_to_sub)
print(f"Station->sub mapping: {len(station_to_sub)} entries, {len(used)} unique sub-areas")
print(f"Sub indices used: {sorted(used)}")

# Write Dart
if station_to_sub:
    with open(r'd:\flutterApp\flutterrhythmquake\lib\core\jma_grid_data.dart', 'w', encoding='utf-8') as out:
        out.write('/// Station->JMA sub-area mapping (auto-generated from reference)\n')
        out.write('class JmaGridData {\n')
        out.write(f'  static const int stationCount = {len(station_to_sub)};\n')
        out.write(f'  static const int subAreaCount = {len(used)};\n\n')
        
        out.write('  /// Maps 0-based NIED station index to 1-based JMA sub-area index (1..194)\n')
        out.write('  /// -1 means no mapping\n')
        out.write('  static const List<int> stationToSubArea = [\n')
        for i in range(0, len(station_to_sub), 15):
            chunk = station_to_sub[i:i+15]
            vals = ', '.join(str(v) for v in chunk)
            out.write(f'    {vals},\n')
        out.write('  ];\n')
        out.write('}\n')
    print("Generated jma_grid_data.dart")

# Now get the 188 area definitions from 地図 sprite
for t in data['targets']:
    if t.get('name') == '\u5730\u56f3':  # 地図
        map_lists = t.get('lists', {})
        for k, v in map_lists.items():
            if isinstance(v, list) and len(v) >= 2:
                name = v[0]
                if '\u9707\u5ea6\u901f\u5831\u533a\u5206' in name:  # 震度速報区分
                    areas = v[1]
                    print(f"\nArea list found: {len(areas)} items ({len(areas)//4} areas)")
                    # Print first 5 areas
                    for i in range(0, min(20, len(areas)), 4):
                        print(f"  {areas[i]}: {areas[i+1]} ({areas[i+2]}, {areas[i+3]})")
                    break
        break
