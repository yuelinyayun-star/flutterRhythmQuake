"""
解析 K-NET ASCII 波形数据，提取各站 PGA → 震度/level
新潟 M4.6 2026/06/01 05:54 JST
"""
import zipfile, re, math

eq_lat, eq_lng = 37.50, 138.10

stations = {}  # code -> {lat, lng, max_pga, components}
with zipfile.ZipFile(r"D:\Users\Rhythm\Downloads\20260601055432_ascii.zip") as z:
    for fname in z.namelist():
        if not fname.endswith('.NS') and not fname.endswith('.EW') and not fname.endswith('.UD'):
            continue
        comp = fname[-2:]
        code = fname.split('/')[-1].split('2606')[0]
        
        with z.open(fname) as f:
            content = f.read().decode('utf-8', errors='replace')
        
        # Extract max acc from header line
        m = re.search(r'Max\. Acc\. \(gal\)\s+([\d.]+)', content)
        if not m: continue
        pga = float(m.group(1))
        
        m_lat = re.search(r'Station Lat\.\s+([\d.]+)', content)
        m_lng = re.search(r'Station Long\.\s+([\d.]+)', content)
        if not m_lat or not m_lng: continue
        lat = float(m_lat.group(1))
        lng = float(m_lng.group(1))
        
        if code not in stations:
            stations[code] = {'lat': lat, 'lng': lng, 'max_pga': 0, 'comps': {}}
        stations[code]['comps'][comp] = pga
        if pga > stations[code]['max_pga']:
            stations[code]['max_pga'] = pga

# Filter: near epicenter, sort by PGA
results = []
for code, s in stations.items():
    dist = math.sqrt((s['lat'] - eq_lat)**2 + (s['lng'] - eq_lng)**2) * 111
    if dist < 150:  # within 150km
        results.append((dist, code, s['max_pga'], s['lat'], s['lng'], s['comps']))

results.sort(key=lambda x: -x[2])  # sort by PGA desc

scratchValues = [-3.0,-2.5,-2.0,-1.5,-1.17,-0.84,-0.5,-0.17,0.16,0.5,0.83,1.16,1.5,1.83,2.16,2.5,2.83,3.16,3.5,3.83,4.16,4.5,4.75,5.0,5.25,5.5,5.75,6.0,6.25,6.5]

print(f"=== 新潟 M4.6 (37.50N 138.10E 10km) K-NET PGA 结果 ===")
print(f"Total stations with data: {len(stations)}, within 150km: {len(results)}")
print()

for dist, code, pga, lat, lng, comps in results[:25]:
    shindo = 2.68 + 1.72 * math.log10(max(pga, 0.0001))
    level = -1
    if shindo >= scratchValues[0]:
        for i in range(len(scratchValues)-1, -1, -1):
            if shindo >= scratchValues[i]:
                level = i
                break
    comp_str = ' '.join(f'{c}={comps.get(c,0):.1f}' for c in ['NS','EW','UD'] if c in comps)
    print(f"  {code} {dist:5.0f}km PGA={pga:6.1f}gal shindo={shindo:.1f} level={level:2d}  [{comp_str}]")

print(f"\n=== 对比目录 ===")
print(f"Catalog: PGA=39.5gal, Intensity=2.7")
print(f"Predict: PGA→shindo → level → 检测")
