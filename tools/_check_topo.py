import json

d = json.load(open('d:/flutterApp/flutterrhythmquake/assets/maps/jp.tsunami.topo.json', encoding='utf-8'))
t = d['transform']
print(f"Scale: {t['scale']}")
print(f"Translate: {t['translate']}")

arcs = d['arcs']
print(f"Arcs count: {len(arcs)}")
print(f"First arc (first 5): {arcs[0][:5]}")

# Decode first arc
sx, sy = t['scale']
tx, ty = t['translate']
x, y = tx, ty
decoded = []
for pt in arcs[0][:5]:
    x += pt[0] * sx
    y += pt[1] * sy
    decoded.append((y, x))
print(f"Decoded first 5 points (lat, lng): {decoded}")

# Check region names
obj_key = list(d['objects'].keys())[0]
geoms = d['objects'][obj_key]['geometries']
print(f"Object: {obj_key}, geometries: {len(geoms)}")
print(f"First geometry keys: {list(geoms[0].keys())}")
