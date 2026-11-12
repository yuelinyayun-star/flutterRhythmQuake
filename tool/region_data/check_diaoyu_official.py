"""Independent checks of names, published baselines and geodesic 12-nm width."""
from pathlib import Path
import json,hashlib,sys
from shapely import union_all,STRtree
from shapely.geometry import shape,Point
from pyproj import Geod
from build_east_asia_names import binary_features
from build_japan_sea_assets import baseline_features

def check():
 out=Path('assets/regions');m=json.loads((out/'diaoyu_official_regions.provenance.json').read_text(encoding='utf-8'))
 fs=binary_features(out/'diaoyu_official_regions.bin');gs=[shape(f['geometry']) for f in fs]
 assert len(fs)==len(m['regions'])
 source=baseline_features(Path('references/region_data/official/diaoyu_baselines_20120910.original.html'))
 compiled=binary_features(out/'diaoyu_baseline_regions.bin')
 for original,current in zip(source,compiled):
  assert list(shape(original['geometry']).exterior.coords)==list(shape(current['geometry']).geoms[0].exterior.coords),'Official baseline coordinates changed'
 assert (out/'diaoyu_baseline_regions.bin').read_bytes()[:4]==b'CWR2'
 assert len(m['points'])==71 and m['officialBaselines']['uniqueBasepoints']==17
 names={p['name'] for p in m['points']}|{m['name']}
 assert all(f['properties']['displayName'] in names for f in fs)
 tree=STRtree(gs);overlaps=[]
 for i,g in enumerate(gs):
  for j in tree.query(g,predicate='intersects'):
   if j>i and g.intersection(gs[j]).area>1e-10:overlaps.append([int(i),int(j)])
 assert not overlaps,overlaps
 envelope=union_all(gs);geod=Geod(ellps='WGS84')
 segments=[]
 for base in source:
  ring=base['geometry']['coordinates'][0]
  for a,b in zip(ring,ring[1:]):
   azimuth,_,length=geod.inv(*a,*b);segments.append((a,b,azimuth,length))
 def distance_to_baselines(point):
  best=float('inf')
  for a,b,azimuth,length in segments:
   def distance(t):
    x,y,_=geod.fwd(*a,azimuth,t)
    return geod.inv(point[0],point[1],x,y)[2]
   lo=0;hi=length
   for _ in range(36):
    left=lo+(hi-lo)/3;right=hi-(hi-lo)/3
    if distance(left)<distance(right):hi=right
    else:lo=left
   best=min(best,distance(0),distance(length),distance((lo+hi)/2))
  return best
 distances=[]
 for polygon in envelope.geoms:
  boundary=list(polygon.exterior.coords)
  distances.extend(distance_to_baselines(p) for p in boundary[::max(1,len(boundary)//40)])
 deviation=max(abs(d-22224) for d in distances)
 assert deviation<2,('Geodesic envelope exceeds documented approximation error',deviation)
 # Midpoint of the published easternmost Chiwei baseline edge. All other
 # baseline points lie west; test just inside and outside the statutory width.
 lon=124+33.7/60;lat=25+55.4/60
 probes=[]
 for distance,expected in [(22224-3,True),(22224+3,False),(23000,False)]:
  x,y,_=geod.fwd(lon,lat,90,distance)
  actual=envelope.covers(Point(x,y));assert actual==expected,(distance,x,y,actual)
  probes.append({'distanceMetres':distance,'point':[x,y],'inside':actual})
 record={'officialBaselineCoordinatesUnchanged':True,'standardNameCount':71,'regions':len(fs),'pairwiseAreaOverlaps':overlaps,
         'radiusMetres':22224,'boundarySamples':len(distances),'maximumSampledBoundaryErrorMetres':deviation,
         'geodesicBoundaryProbes':probes,'outputSha256':hashlib.sha256((out/'diaoyu_official_regions.bin').read_bytes()).hexdigest()}
 print(json.dumps(record,ensure_ascii=False,indent=2));return record

if __name__=='__main__':check()
