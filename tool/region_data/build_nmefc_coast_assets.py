"""Derive named coastal lines; never treat an administrative ring as a warning polygon."""
from pathlib import Path
from collections import defaultdict
import hashlib
import json
from shapely import line_merge, make_valid, set_precision, union_all
from shapely.geometry import shape, MultiLineString
from opencc import OpenCC
from build_taiwan_official_assets import read_land, SOURCE_SHA256, SOURCE_URL


def parts(g, kind):
    if g.is_empty:
        return []
    if g.geom_type in kind:
        return [g]
    return [p for child in getattr(g, 'geoms', []) for p in parts(child, kind)]


def build():
    from build_nmefc_mainland_coasts import build_mainland, province_aliases
    source = Path('references/region_data/official/township_nlsc_1120317.original.zip')
    grouped = defaultdict(list)
    converter = OpenCC('t2s')
    for feature in read_land(source):
        county = feature['properties']['COUNTYNAME']
        # Keep the already-reviewed domestic naming/assignment of offshore
        # islands. No new Kinmen/Matsu/Qijin jurisdiction inference here.
        if not feature['displayName'].startswith('台湾省'):
            continue
        grouped[county].append(set_precision(make_valid(shape(feature['geometry'])), 1e-9))
    regions = {name: union_all(geometries) for name, geometries in grouped.items()}
    land = union_all(list(regions.values()))
    # Only outer shores: county/town boundaries and enclosed inland holes are
    # absent from this line set. Published source polygons remain unchanged.
    coast = union_all([p.exterior for p in parts(land, {'Polygon'})])
    features = []
    for original, region in sorted(regions.items()):
        lines = parts(line_merge(coast.intersection(region)), {'LineString', 'LinearRing'})
        if not lines:
            continue
        name = converter.convert(original)
        # User-selected display policy: resolve forecast-area names at the
        # county/city level. For example 花莲 selects 花莲县, not 花莲市.
        # Keep directional sectors distinct; never remove arbitrary suffixes.
        short_names = {original[:-1], name[:-1]} if name.endswith(('县', '市')) else set()
        aliases = sorted({original, name,
                          '台湾省' + name, '臺灣省' + original, '中国台湾省' + name,
                          *short_names,
                          *('台湾省' + short for short in short_names),
                          *('臺灣省' + short for short in short_names),
                          *('中国台湾省' + short for short in short_names)})
        features.append({'type': 'Feature', 'properties': {
            'name': '台湾省' + name, 'province': '台湾省', 'aliases': aliases,
            'provinceAliases': province_aliases('台湾省'),
            'kind': 'administrativeCoastline',
        }, 'geometry': MultiLineString([list(line.coords) for line in lines]).__geo_interface__})
    by_name = {f['properties']['name']: shape(f['geometry']) for f in features}
    for required in ['台湾省花莲县', '台湾省宜兰县']:
        if required not in by_name or by_name[required].is_empty:
            raise ValueError('Missing verified named coast ' + required)
    if any(not g.difference(coast).is_empty for g in by_name.values()):
        raise ValueError('An inland boundary was introduced')
    mainland_features, _, mainland_manifest = build_mainland()
    features.extend(mainland_features)
    by_name.update({f['properties']['name']: shape(f['geometry']) for f in mainland_features})
    output = Path('assets/maps/nmefc.named-coasts.geo.json')
    output.write_text(json.dumps({'type': 'FeatureCollection', 'features': features}, ensure_ascii=False, separators=(',', ':')) + '\n', encoding='utf-8')
    manifest = {'source': SOURCE_URL, 'sourceSha256': SOURCE_SHA256,
                'method': 'Taiwan township union exterior intersected by county; mainland basemap marine exterior partitioned by existing prefecture boundaries. Offline 1e-9 degree overlay grid; original sources unchanged. See mainland method and endpoint provenance.',
                'meaning': 'Named administrative coastal base lines, NOT NMEFC-issued warning boundaries or inundation limits.',
                'coverage': 'Mainland coastal prefectures/municipalities, Hainan coastal counties/cities, Hong Kong, Macao and 17 Taiwan Province coastal counties/cities. Not all NMEFC global forecast areas.',
                'mainland': mainland_manifest,
                'nameMatchingPolicy': 'User-selected county/city-level display. Unambiguous short names select the corresponding county/city shoreline, not a same-named township-level city. No directional suffix stripping.',
                'unmatchedNamesAreNotExpanded': ['台东北', '台东南', '屏东东', '屏东西', '台北东'],
                'ambiguousAliases': {alias: sorted(f['properties']['name'] for f in features if alias in f['properties']['aliases'])
                                     for alias in sorted({a for f in features for a in f['properties']['aliases']})
                                     if sum(alias in f['properties']['aliases'] for f in features) > 1},
                'featureNames': sorted(by_name), 'features': len(features),
                'inlandBoundariesIncluded': False,
                'outputSha256': hashlib.sha256(output.read_bytes()).hexdigest()}
    output.with_name('nmefc.named-coasts.provenance.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(manifest, ensure_ascii=False))


if __name__ == '__main__':
    build()
