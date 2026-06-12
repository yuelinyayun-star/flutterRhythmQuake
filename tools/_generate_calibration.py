import json, os, re

with open(r'D:\flutterApp\flutterrhythmquake\lib\models\nied_station_db.dart', 'r', encoding='utf-8') as f:
    dart_content = f.read()
our_name_to_code = {}
for m in re.finditer(r'"code":\s*"([^"]+)"[^}]*"name":\s*"([^"]+)"', dart_content):
    our_name_to_code[m.group(2)] = m.group(1)

path = os.path.join(os.environ['TEMP'], 'sb3_extract', 'project.json')
data = json.load(open(path, 'r', encoding='utf-8'))

for t in data.get('targets', []):
    if t.get('name') != 'Stage':
        continue
    lists = t.get('lists', {})
    name_vals = lists.get('5F%|f/{h*d~4KS[%l+kq', [[], []])[1]
    code_vals = lists.get('aF6B2EN},t-!Y1TM2w6i', [[], []])[1]
    
    tc_map = {}
    for i in range(len(name_vals)):
        name = name_vals[i]
        tc = int(code_vals[i])
        if name in our_name_to_code:
            code = our_name_to_code[name]
            tc_map[code] = tc
    
    # Now update nied_calibration.dart to include thresholdCode
    # Re-read per values too
    per_vals = lists.get('L~`Jyu;rZchRgeb/+ifa', [[], []])[1]
    
    # Combine: per map for codes that have per
    combined = {}
    for i in range(len(name_vals)):
        name = name_vals[i]
        per = float(per_vals[i])
        tc = int(code_vals[i])
        if name in our_name_to_code:
            code = our_name_to_code[name]
            if code not in combined:
                combined[code] = (per, tc)
    
    lines = []
    lines.append('// Scratch sb3 per-station calibration factors + thresholdCodes')
    lines.append('// Extracted from kotoho7 リアルタイム地震ビューアー v1.6.3.sb3')
    lines.append(f'// Total entries: {len(combined)}')
    lines.append('')
    lines.append('class NiedCalibration {')
    lines.append('  static const Map<String, double> factors = {')
    for code in sorted(combined.keys()):
        per, tc = combined[code]
        lines.append(f'    "{code}": {round(per, 4)},')
    lines.append('  };')
    lines.append('')
    lines.append('  static const defaultFactor = 1.0;')
    lines.append('')
    lines.append('  static const Map<String, int> thresholdCodes = {')
    for code in sorted(combined.keys()):
        per, tc = combined[code]
        lines.append(f'    "{code}": {tc},')
    lines.append('  };')
    lines.append('')
    lines.append('  static const defaultThresholdCode = 320;')
    lines.append('}')
    
    out_path = r'D:\flutterApp\flutterrhythmquake\lib\models\nied_calibration.dart'
    with open(out_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines) + '\n')
    
    print(f"Written {len(combined)} entries with factors + thresholdCodes")
    print(f"Sample: {dict(list(combined.items())[:3])}")
    break
