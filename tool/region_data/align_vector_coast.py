"""Offline derived shoreline alignment using the app's unchanged KA basemap."""
from pathlib import Path
import hashlib,json,math
from collections import defaultdict

VECTOR_HASHES={
 'medium.global.modified.topo.json':'95d0495902b6ca977b0f5cbb5e733ee8cc55c15ef2182dcf5509dec1c3b0e955',
 'jp.pref.topo.json':'0a78934167d64f112a64393be3ed3a276c0584e3e56fc46ea3791049790bea0b',
 'cn.province.topo.json':'4b64a2d342c1017b1b571a4e02c92bafac0e114e9f3c31860b1b1bba4dc56965',
}

def polygon_parts(g):
 if g.is_empty:return []
 if g.geom_type=='Polygon':return [g]
 return [p for part in g.geoms for p in polygon_parts(part)] if hasattr(g,'geoms') else []

def load_vector_coast(map_dir,decode,clean):
 from shapely import union_all
 from shapely.geometry import shape,box
 datasets={}
 for name,expected in VECTOR_HASHES.items():
  b=(map_dir/'ka'/name).read_bytes()
  if hashlib.sha256(b).hexdigest()!=expected:raise ValueError('Unreviewed vector basemap '+name)
  datasets[name]=[(f['properties'],clean(shape(f['geometry']))) for f in decode(json.loads(b))]
 cn=[('中国|'+p['name'],g) for p,g in datasets['cn.province.topo.json'] if p.get('name') and not g.is_empty]
 jp=datasets['jp.pref.topo.json'];window=box(70,0,180,65)
 # This source's one unnamed Chinese feature consists of the ten cartographic
 # maritime dashes, not islands. Keep it for rendering, never as actual land.
 dashes=[g for p,g in datasets['cn.province.topo.json'] if not p.get('name')]
 if len(dashes)!=1 or len(polygon_parts(dashes[0]))!=10:
  raise ValueError('Unreviewed maritime-dash feature in fixed basemap')
 land=clean(union_all([g for name,fs in datasets.items() for p,g in fs
                      if name!='cn.province.topo.json' or p.get('name')]).intersection(window))
 cn_land=clean(union_all([g for p,g in datasets['cn.province.topo.json'] if p.get('name')]))
 kr_land=clean(union_all([g for p,g in datasets['medium.global.modified.topo.json'] if p.get('name')=='大韩民国']))
 return {'land':land,'chinaLand':cn_land,'china':cn,'japan':jp,'koreaLand':kr_land,
         'sources':VECTOR_HASHES,'maritimeDashes':dashes[0],
         'context':[(p.get('name',''),g.intersection(window)) for p,g in datasets['medium.global.modified.topo.json'] if g.intersects(window)]}

def _lines(g):
 if g.is_empty:return []
 if g.geom_type in ('LineString','LinearRing'):return [g]
 return [line for child in g.geoms for line in _lines(child)] if hasattr(g,'geoms') else []

def align_named_islands(regions,land,clean):
 """Use complete matching basemap islands; retain known tiny omitted islands."""
 from shapely import STRtree,union_all
 parts=polygon_parts(land);tree=STRtree(parts);result=[];retained=[]
 for name,g,kind in regions:
  chosen=[]
  for original in polygon_parts(g):
   matches=[parts[i] for i in tree.query(original,predicate='intersects')
            if original.intersection(parts[i]).area>parts[i].area*.5]
   if matches:chosen.extend(matches)
   else:
    chosen.append(original)
    retained.append({'name':name,'squareDegrees':original.area,
                     'point':[original.representative_point().x,original.representative_point().y]})
  result.append((name,clean(union_all(chosen)),kind))
 return result,retained

def partition_gap(gap,adjacent,clean):
 """Continue adjacent names to the shore, splitting shared gaps by edge distance.

 Only the gap is partitioned. Existing region interiors are never reassigned.
 Sites are sampled from the actual shared water/gap edges in Web Mercator.
 """
 from shapely import voronoi_polygons,union_all
 from shapely.geometry import MultiPoint
 from shapely.ops import transform
 from pyproj import Transformer
 if len(adjacent)==1:return {adjacent[0][0]:gap}
 forward=Transformer.from_crs(4326,3857,always_xy=True).transform
 reverse=Transformer.from_crs(3857,4326,always_xy=True).transform
 projected=transform(forward,gap);sites={}
 for index,g in adjacent:
  shared=g.boundary.intersection(gap.boundary)
  for line in _lines(transform(forward,shared)):
   count=max(1,math.ceil(line.length/500))
   for step in range(count+1):
    p=line.interpolate(step/count,normalized=True);key=(p.x,p.y)
    sites.setdefault(key,index)
 if not sites:raise ValueError('Gap lacks an adjacent boundary: '+str(gap.bounds))
 points=list(sites);cells=voronoi_polygons(MultiPoint(points),extend_to=projected.envelope,ordered=True)
 pieces=defaultdict(list)
 for point,cell in zip(points,cells.geoms):
  # Transform the partition cell first, then cut the original gap. Transforming
  # a clipped shoreline would replace straight source edges with inverse-
  # projection chords and leave strips along long coast segments.
  piece=clean(transform(reverse,cell).intersection(gap))
  if piece.area>0:pieces[sites[point]].append(piece)
 result={i:clean(union_all(gs)) for i,gs in pieces.items()}
 return result

def fill_gaps(target,regions,clean,phase):
 from shapely import STRtree,union_all
 occupied=union_all([g for _,g in regions]);missing=clean(target.difference(occupied))
 patches=defaultdict(list);records=[];unassigned=[]
 tree=STRtree([g for _,g in regions])
 for gap in polygon_parts(missing):
  adjacent=[(int(i),regions[i][1]) for i in tree.query(gap,predicate='intersects')
            if regions[i][1].boundary.intersection(gap.boundary).length>1e-10]
  # Isolated inland lakes with no marine edge do not become sea regions.
  if not adjacent:
   unassigned.append(gap);continue
  pieces=partition_gap(gap,adjacent,clean)
  owned=[]
  for index,g in sorted(pieces.items()):
   g=clean(g.difference(union_all(owned))) if owned else g
   if g.is_empty:continue
   patches[index].append(g);owned.append(g)
  remainder=clean(gap.difference(union_all(owned)))
  # Projection inversion can leave roundoff strips at the edge. Keep all true
  # gap area and use the same adjacent-owner rule for these tiny residuals.
  for part in polygon_parts(remainder):
   if part.area>1e-9:raise ValueError('Unpartitioned '+phase+' gap '+str(part.area))
   point=part.representative_point();index=min(adjacent,key=lambda pair:pair[1].distance(point))[0]
   patches[index].append(part)
  point=gap.representative_point()
  records.append({'squareDegrees':gap.area,'point':[point.x,point.y],
                  'owners':[regions[i][0] for i in sorted(pieces)]})
 result=[(name,clean(union_all([g]+patches[i]))) for i,(name,g) in enumerate(regions)]
 return result,{'phase':phase,'filledComponents':len(records),'filledSquareDegrees':sum(r['squareDegrees'] for r in records),
                'components':records,'isolatedUnassignedComponents':len(unassigned),
                'isolatedUnassignedSquareDegrees':sum(g.area for g in unassigned),
                'isolatedUnassigned':[{'point':[g.representative_point().x,g.representative_point().y],'squareDegrees':g.area,'bounds':list(g.bounds)} for g in unassigned],
                'method':'Adjacent-boundary continuation; shared gaps use 500m boundary-site Voronoi in EPSG:3857; original interiors unchanged'}

def fill_marine_to_coast(regions,land,clean):
 from shapely import union_all
 from shapely.geometry import Polygon
 sea=union_all([g for _,g in regions])
 envelope=union_all([Polygon(p.exterior) for p in polygon_parts(sea)])
 target=clean(envelope.difference(land))
 clipped=[(name,clean(g.difference(land))) for name,g in regions]
 return fill_gaps(target,clipped,clean,'marine')
