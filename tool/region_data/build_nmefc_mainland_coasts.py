"""Assign the app's mainland marine outline to existing prefecture boundaries.

This is an offline administrative display layer, not an NMEFC warning polygon.
Original map files and boundary reference archives are never rewritten.
"""
from collections import defaultdict
from pathlib import Path
import hashlib
import io
import json
import zipfile

import shapefile
from opencc import OpenCC
from shapely import STRtree, line_merge, make_valid, set_precision, union_all
from shapely.geometry import LineString, MultiPolygon, Point, shape
from shapely.ops import substring

from align_vector_coast import VECTOR_HASHES, _lines, polygon_parts
from build_east_asia_names import decode_topology
from build_region_assets import _province_names

ADMIN_HASH = 'a268d74d3fba89bcc35f9febd8843a9cb77792a3690044dc8b26f21e8acf1bcd'
BORDER_HASH = '16ead035f539c8b6c23650c5845d86ad3556553e7456bdf9b4730210f26aacbe'
BORDER_URL = 'https://naturalearth.s3.amazonaws.com/10m_cultural/ne_10m_admin_0_boundary_lines_land.zip'
COASTAL_PROVINCES = {
    '辽宁省', '河北省', '天津市', '山东省', '江苏省', '上海市',
    '浙江省', '福建省', '广东省', '广西壮族自治区', '海南省',
    '香港特别行政区', '澳门特别行政区',
}


def checked(path, expected):
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != expected:
        raise ValueError('Unreviewed mainland coast source: ' + str(path))
    return data


def clean(geometry):
    return set_precision(MultiPolygon(polygon_parts(make_valid(geometry))), 1e-9)


def province_aliases(province):
    short = {'广西壮族自治区': '广西', '香港特别行政区': '香港',
             '澳门特别行政区': '澳门'}.get(province, province.removesuffix('省').removesuffix('市'))
    traditional = OpenCC('s2t')
    return sorted({name for value in (province, short)
                   for name in (value, '中国' + value, traditional.convert(value),
                                traditional.convert('中国' + value))})


def coast_features(province, city_lines):
    traditional = OpenCC('s2t')
    result = []
    for name, pieces in sorted(city_lines.items()):
        lines = _lines(line_merge(union_all(pieces)))
        if not lines:
            continue
        short = name.removesuffix('市').removesuffix('县')
        # Autonomous county abbreviations refer to their actual named county;
        # no directional sector or measurement-point alias is inferred.
        for ending in ('黎族自治', '黎族苗族自治'):
            short = short.removesuffix(ending)
        names = {name, short}
        if name == province:
            names.update(province_aliases(province))
        names |= {value + '沿海' for value in tuple(names)}
        aliases = set(names)
        if name != province:
            aliases |= {prefix + value for prefix in province_aliases(province) for value in names}
        aliases |= {traditional.convert(value) for value in tuple(aliases)}
        result.append({'type': 'Feature', 'properties': {
            'name': name if name == province else province + name,
            'province': province, 'provinceAliases': province_aliases(province),
            'aliases': sorted(aliases), 'kind': 'administrativeCoastline',
        }, 'geometry': {'type': 'MultiLineString', 'coordinates': [list(line.coords) for line in lines]}})
    return result


def mainland_marine_path(land, archive):
    # The two reference lines identify where to stop the national exterior.
    # They supply endpoints only: all drawn vertices stay on the app basemap.
    # No foreign administrative geometry or naming is imported into the asset.
    filename = 'ne_10m_admin_0_boundary_lines_land'
    anchors = {}
    with zipfile.ZipFile(io.BytesIO(checked(archive, BORDER_HASH))) as z:
        reader = shapefile.Reader(**{ext: io.BytesIO(z.read(filename + '.' + ext))
                                     for ext in ('shp', 'shx', 'dbf')}, encoding='utf-8')
        for record in reader.iterShapeRecords():
            props = record.record.as_dict()
            neighbours = {props['ADM0_LEFT'], props['ADM0_RIGHT']}
            if neighbours not in ({'China', 'North Korea'}, {'China', 'Vietnam'}):
                continue
            lines = _lines(line_merge(union_all(_lines(shape(record.shape.__geo_interface__)))))
            endpoints = [Point(line.coords[i]) for line in lines for i in (0, -1)]
            anchors[','.join(sorted(neighbours))] = min(endpoints, key=lambda p: p.y)
    if len(anchors) != 2:
        raise ValueError('Missing mainland marine endpoint references')
    mainland = max(polygon_parts(land), key=lambda p: p.area)
    ring = LineString(mainland.exterior.coords)
    first, last = sorted(ring.project(p) for p in anchors.values())
    direct = substring(ring, first, last)
    wrapped = union_all([substring(ring, 0, first), substring(ring, last, ring.length)])
    coast = min((direct, wrapped), key=lambda g: g.length)
    return mainland, coast, {
        name: {'referenceCoordinate': list(point.coords)[0],
               'basemapCoordinate': list(ring.interpolate(ring.project(point)).coords)[0],
               'snapDistanceDegrees': ring.distance(point)}
        for name, point in anchors.items()
    }


def split_at_city_edges(line, edges):
    # substring also handles edges collinear with a city boundary. Unlike
    # buffering/smoothing it preserves the original basemap outline exactly.
    intersection = line.intersection(edges)
    points = []
    def collect(g):
        if g.is_empty:
            return
        if g.geom_type == 'Point':
            points.append(g)
        elif g.geom_type in ('LineString', 'LinearRing'):
            points.extend((Point(g.coords[0]), Point(g.coords[-1])))
        else:
            for child in g.geoms:
                collect(child)
    collect(intersection)
    cuts = sorted({0.0, line.length, *(line.project(p) for p in points)})
    return [substring(line, a, b) for a, b in zip(cuts, cuts[1:]) if b - a > 1e-12]


def build_mainland():
    topo_path = Path('assets/maps/ka/cn.province.topo.json')
    topology = json.loads(checked(topo_path, VECTOR_HASHES[topo_path.name]))
    provinces = {f['properties']['name']: clean(shape(f['geometry']))
                 for f in decode_topology(topology) if f['properties'].get('name')}
    land = clean(union_all(list(provinces.values())))
    mainland, coast, endpoints = mainland_marine_path(
        land, Path('references/region_data/natural_earth/ne_10m_admin_0_boundary_lines_land.original.zip'))
    source = json.loads(checked(Path('assets/maps/中华人民共和国.geojson'), ADMIN_HASH))
    province_names = _province_names(Path('references/region_data/china_place_index.json'))
    cities = defaultdict(list)
    for feature in source['features']:
        p = feature['properties']
        code = str(p.get('adcode', ''))
        if not code.isdigit() or int(code) // 10000 == 71 or p.get('level') != 'city':
            continue
        province = province_names[int(code) // 10000]
        # This request covers mainland shores, Hainan and nearshore islands.
        # Do not reinterpret offshore sea/dash decorations as island coasts.
        if province in COASTAL_PROVINCES and p['name'] != '三沙市':
            cities[province].append((p['name'], clean(shape(feature['geometry']))))
    for province in ('天津市', '上海市', '香港特别行政区', '澳门特别行政区'):
        cities[province] = [(province, provinces[province])]
    result, counts, errors, max_alignment = [], {}, {}, 0.0
    shoreline_parts = []
    for province in sorted(COASTAL_PROVINCES):
        items = cities[province]
        admin = [g for _, g in items]
        islands = [p for p in polygon_parts(provinces[province])
                   if p.intersection(mainland).area < 1e-8 and any(p.intersects(g) for g in admin)]
        shore = line_merge(union_all([coast.intersection(provinces[province], grid_size=1e-9)] + [p.exterior for p in islands]))
        if shore.is_empty:
            raise ValueError('Missing coastal province: ' + province)
        shoreline_parts.append(shore)
        edges, tree = union_all([g.boundary for g in admin]), STRtree(admin)
        owned, distances = defaultdict(list), []
        for line in _lines(shore):
            for piece in ([line] if len(items) == 1 else split_at_city_edges(line, edges)):
                point = piece.interpolate(.5, normalized=True)
                index = int(tree.nearest(point))
                distance = point.distance(admin[index])
                if distance > .02:
                    raise ValueError(f'Unreviewed city/basemap gap: {province} {items[index][0]} {distance}')
                distances.append(distance)
                owned[items[index][0]].append(piece)
        features = coast_features(province, owned)
        result.extend(features)
        counts[province] = len(features)
        errors[province] = max(distances, default=0)
        max_alignment = max(max_alignment, errors[province])
    coverage = union_all(shoreline_parts)
    if not coast.difference(coverage.buffer(2e-9)).is_empty:
        raise ValueError('A gap remains in the continuous mainland coast')
    # This buffer is only a numerical validation tolerance, never output data.
    envelope = coverage.buffer(2e-9)
    for feature in result:
        if not shape(feature['geometry']).difference(envelope).is_empty:
            raise ValueError('Coast departed from original basemap')
    drawn = union_all([shape(feature['geometry']) for feature in result])
    if not coverage.difference(drawn.buffer(2e-9)).is_empty:
        raise ValueError('An unassigned coastal gap remains')
    return result, coverage, {
        'basemap': str(topo_path), 'basemapSha256': VECTOR_HASHES[topo_path.name],
        'administrativeSource': 'assets/maps/中华人民共和国.geojson', 'administrativeSha256': ADMIN_HASH,
        'endpointReference': BORDER_URL, 'endpointReferenceSha256': BORDER_HASH,
        'endpointAlignment': endpoints, 'featuresByProvince': counts,
        'maxCityAlignmentDistanceDegrees': max_alignment, 'cityAlignmentDistanceDegreesByProvince': errors,
        'coordinateValidationToleranceDegrees': 2e-9,
        'method': 'Original basemap mainland marine exterior between referenced estuary endpoints, plus nearshore island exterior rings. Split by existing city edges; assign unmatched shoreline slivers to the nearest city in the same province. No buffered coast, inland provincial/city boundaries, or new warning extents.',
        'coverage': '11 mainland coastal provinces/municipalities plus Hong Kong and Macao; Hainan directly administered coastal counties/cities included. Distant South China Sea features excluded from this mainland display layer.',
    }
