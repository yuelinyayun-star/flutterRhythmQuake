"""Export actual compiled lookup polygons for rendering only.

Point queries are never done in this export or in browser JavaScript. The
inspection server calls the application's getFEName entry directly.
"""
from pathlib import Path
import hashlib
import json
import ast
import re
import math

from shapely import make_valid, set_precision
from shapely.geometry import MultiPolygon, shape, mapping, box
from align_vector_coast import load_vector_coast, polygon_parts
from build_east_asia_names import binary_features, decode_topology


def build():
    def clean(g):
        return set_precision(MultiPolygon(polygon_parts(make_valid(g))), 1e-9)
    assets = Path('assets/regions')
    vector = load_vector_coast(Path('assets/maps'), decode_topology, clean)
    metadata = json.loads((assets/'east_asia_names.provenance.json').read_bytes())
    diaoyu = json.loads((assets/'diaoyu_official_regions.provenance.json').read_bytes())
    compiled = binary_features(assets/'east_asia_names.bin')
    from shapely import union_all
    base = union_all([shape(f['geometry']) for r,f in zip(metadata['regions'],compiled) if r['kind']=='baseFE'])
    regions = []
    for name, g in vector['china']:
        g = clean(g.difference(base))
        if g.is_empty: continue
        regions.append({'type': 'Feature', 'properties': {
            'name': name.removeprefix('中国|'), 'kind': 'chinaLand',
            'point': list(g.representative_point().coords)[0], 'area': g.area,
        }, 'geometry': mapping(g)})
    for meta, feature in zip(metadata['regions'], compiled):
        if meta['kind']=='baseFE': continue
        regions.append({'type': 'Feature', 'properties': {
            'name': '基础地名映射' if meta['kind']=='baseFE' else meta['name'], 'kind': meta['kind'], 'point': meta['labelPoint'],
            'area': meta['effectiveSquareDegrees'],
        }, 'geometry': feature['geometry']})
    # Render the actual unchanged base table, clipped to the native base route.
    # These polygons only explain its coverage; live queries still call APP.
    text = Path('lib/utils/fe_regions.dart').read_text(encoding='utf-8')
    table = [int(v) for v in re.findall(r'\d+',re.search(r'Uint16List\.fromList\(\[(.*?)\]\);',text,re.S).group(1))]
    names = ast.literal_eval('['+re.search(r'final List<String> _feNames = \[(.*?)\];',text,re.S).group(1)+']')
    reference = json.loads(Path('references/region_data/fe_fix_region_data.json').read_bytes())
    if table != [v for row in reference['grid']['table'] for v in row]:
        raise ValueError('Embedded APP base table differs from its source')
    pieces = {}
    if not base.is_empty:
        xmin,ymin,xmax,ymax = base.bounds
        for lat in range(math.floor(ymin),math.ceil(ymax)):
            for lon in range(math.floor(xmin),math.ceil(xmax)):
                piece = clean(box(lon,lat,lon+1,lat+1).intersection(base))
                if piece.is_empty: continue
                index = table[(lat+90)*360+lon+180]
                pieces.setdefault(index,[]).append(piece)
    for index, parts in pieces.items():
        geometry = clean(union_all(parts))
        name = names[index-1]
        if name=='韩国': name='朝鲜半岛南部'
        regions.append({'type':'Feature','properties':{
            'name':name,'kind':'baseFE','baseRegionId':index,
            'point':list(geometry.representative_point().coords)[0],
            'area':geometry.area},'geometry':mapping(geometry)})
    for meta, feature in zip(diaoyu['regions'], binary_features(assets/'diaoyu_official_regions.bin')):
        geometry = clean(shape(feature['geometry']).difference(base))
        if geometry.is_empty: continue
        regions.append({'type': 'Feature', 'properties': {
            'name': meta['displayName'], 'kind': 'diaoyu', 'zoneKind': meta['zoneKind'],
            'point': meta['labelPoint'], 'area': shape(feature['geometry']).area,
        }, 'geometry': mapping(geometry)})
    output = Path('.dart_tool/place_name_inspector/regions.json')
    output.parent.mkdir(parents=True, exist_ok=True)
    views = {
        'east': [[115, 18], [145, 44]],
        'taiwan': [[118, 21], [132, 34]],
        'japan': [[126, 29], [146, 46]],
        'coast': [[120, 26], [127, 34]],
        'diaoyu': [[123.1, 25.5], [124.9, 26.3]],
    }
    # Rendering anchors only: a large sea's global label point may be outside
    # a regional view. Label its visible water interior, without moving any
    # lookup geometry or using these anchors for point queries.
    for feature in regions:
        if feature['properties']['kind'] != 'geographicSea':
            continue
        geometry = shape(feature['geometry'])
        anchors = {}
        for view, (lower, upper) in views.items():
            parts = polygon_parts(geometry.intersection(box(*lower, *upper)))
            if parts:
                anchors[view] = list(max(parts, key=lambda p: p.area).representative_point().coords)[0]
        feature['properties']['viewPoints'] = anchors
    output.write_text(json.dumps({
        'datasetSha256': hashlib.sha256((assets/'east_asia_names.bin').read_bytes()).hexdigest(),
        'regions': regions,
        'context': [{'type': 'Feature', 'properties': {'name': name}, 'geometry': mapping(g)}
                    for name, g in vector['context'] if not g.is_empty],
        'baselines': diaoyu['baselineRings'], 'diaoyuPoints': diaoyu['points'],
        'maritimeDashes': {'type':'Feature','geometry':mapping(vector['maritimeDashes'])},
        'views': views,
    }, ensure_ascii=False, separators=(',', ':')) + '\n', encoding='utf-8')
    print(str(output), 'features', len(regions), 'bytes', output.stat().st_size)


if __name__ == '__main__':
    build()
