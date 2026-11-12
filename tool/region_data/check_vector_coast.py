"""Audit compiled coastal repairs against the app's original vector assets."""
from pathlib import Path
import json,hashlib,argparse
from build_east_asia_names import binary_features,decode_topology
from align_vector_coast import load_vector_coast,polygon_parts
from shapely import make_valid,union_all,STRtree,set_precision
from shapely.geometry import shape,Polygon,Point,MultiPolygon

def clean(g):return set_precision(MultiPolygon(polygon_parts(make_valid(g))),1e-9)

def check(root=Path('.')):
 out=root/'assets/regions';m=json.loads((out/'east_asia_names.provenance.json').read_text(encoding='utf-8'))
 vector=load_vector_coast(root/'assets/maps',decode_topology,clean)
 fs=binary_features(out/'east_asia_names.bin')
 rows=[(r,clean(shape(f['geometry']))) for r,f in zip(m['regions'],fs)]
 assert len(rows)==m['features']
 jp=union_all([g for r,g in rows if r['kind']=='japanLand'])
 neutral=union_all([g for r,g in rows if r['kind']=='neutralLand'])
 bases=union_all([clean(shape(f['geometry'])) for f in binary_features(out/'diaoyu_official_regions.bin')])
 expected_jp=union_all([g for _,g in vector['japan']]).difference(union_all([vector['chinaLand'],bases,neutral]))
 difference=jp.symmetric_difference(expected_jp).area
 boundary=expected_jp.boundary
 max_offset=max((Point(p).distance(boundary) for g in polygon_parts(jp.symmetric_difference(expected_jp)) for p in g.exterior.coords),default=0)
 # Different overlay paths can introduce sub-millimetre shoreline slivers;
 # measure their width instead of hiding them in a large area tolerance.
 assert max_offset<5e-9,('Japanese shore displacement in degrees',max_offset)
 sea_kinds=('japanSea','taiwanSea','baseFE')
 sea=union_all([g for r,g in rows if r['kind'] in sea_kinds]).difference(bases)
 overlap=sea.intersection(vector['land']).area
 assert overlap<1e-9,('Marine regions invade vector-map land',overlap)
 public_seas=[(f['properties']['displayName'],clean(shape(f['geometry'])))
              for fn in ['japan_sea_regions.bin','cwa_epicenter_regions.bin']
              for f in binary_features(out/fn)]
 from marine_dash_clip import taiwan_east_dash_partition
 cwa=[(f['properties']['displayName'],clean(shape(f['geometry']))) for f in binary_features(out/'cwa_epicenter_regions.bin')]
 cwa_coverage=clean(union_all([g for _,g in cwa]))
 west,dash=taiwan_east_dash_partition(vector,cwa_coverage,clean)
 assert dash==m['marineDashPartition'], 'Compiled clipping guide differs from basemap strokes'
 west_cwa=clean(cwa_coverage.intersection(west))
 n_jp=len(public_seas)-len(cwa)
 public_seas=[(n,clean(g.difference(west_cwa)) if n!='东海' else g) for n,g in public_seas[:n_jp]]+[(n,clean(g.intersection(west))) for n,g in cwa]
 original_union=union_all([g for _,g in public_seas]);envelope=union_all([Polygon(p.exterior) for p in polygon_parts(original_union)])
 outside=sea.difference(envelope).area
 assert outside<1e-9,('Original outer marine extent expanded',outside)
 # Original names must keep their ownership after the user-selected dash cut.
 blocked=union_all([vector['land'],neutral,bases]);old_owned=[];changed=0.0
 base_names={'东海',*m.get('baseFEReplacedTaiwanNames',[])}
 for name,g in public_seas:
  if m.get('taiwanBroadSeaNamePrefix') and name.startswith('台湾') and not name.endswith('近岸海域'):
   name=m['taiwanBroadSeaNamePrefix']+name
  g=g.difference(blocked).difference(union_all(old_owned))
  different=union_all([shape(f['geometry']) for r,f in zip(m['regions'],fs) if r['kind'] in sea_kinds and not (r['kind']=='baseFE' and name in base_names) and r['name']!=name])
  changed+=g.intersection(different).area;old_owned.append(g)
 assert changed<1e-9,('Original named marine interiors were changed',changed)
 marine=m['coastlineAlignment']['marine']
 remaining_geometry=clean(envelope.difference(blocked).difference(sea))
 remaining=remaining_geometry.area
 # Locate the independently remaining enclosed water by the recorded point;
 # do not turn a whole missing coastal region into an area-error tolerance.
 isolated_points=[Point(r['point']) for r in marine['isolatedUnassigned']]
 residual=[p for p in polygon_parts(remaining_geometry)
           if not any(p.covers(point) for point in isolated_points)]
 # These strips may end on the land side of a sea/land intersection; measure
 # against both source edges, rather than only the sea edge at that endpoint.
 overlay_edges=union_all([sea.boundary,blocked.boundary])
 residual_offset=max((Point(c).distance(overlay_edges) for p in residual for c in p.exterior.coords),default=0)
 assert residual_offset<5e-9,('Connected shore gap width in degrees',residual_offset)
 assert all(p.buffer(-5e-9).is_empty for p in residual), 'Unfilled water interior remains'
 result={'japaneseLandSymmetricDifferenceSquareDegrees':difference,'japaneseShoreMaximumOverlayOffsetDegrees':max_offset,'marineOverlapWithBasemapLandSquareDegrees':overlap,
         'marineOutsideOriginalOuterExtentSquareDegrees':outside,'physicalSeaInteriorsAssignedToOtherNamesSquareDegrees':changed,
         'remainingCoastalOverlayMaximumOffsetDegrees':residual_offset,
         'filledMarineGapComponents':marine['filledComponents'],'remainingIsolatedComponents':marine['isolatedUnassignedComponents'],
         'remainingIsolatedSquareDegrees':remaining,'outputSha256':hashlib.sha256((out/'east_asia_names.bin').read_bytes()).hexdigest()}
 print(json.dumps(result,ensure_ascii=False,indent=2));return result

if __name__=='__main__':check()
