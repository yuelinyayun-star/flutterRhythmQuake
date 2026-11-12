"""Official island names/baselines and a documented 12-nm derived envelope."""
from pathlib import Path
import hashlib,json,re,math
from html import unescape
from build_japan_sea_assets import baseline_features,checked,BASELINE_SHA256,BASELINE_URL
from build_region_assets import _build_polygon_features

COORDINATES_SHA256='b19e38d9f78bde8975c72007b2e024ba85f05dbbba67570a060db29bd1ce6f1b'
NAMES_SHA256='b385225efafd24a82ac83d1880d303512e077bf0356fda1c2408d66f14fd31fd'
LAW_SHA256='dbc32adc7d9283059afb3592912560e33c0ccd69f2090fff1f7c2243e5fc05a4'
RADIUS_METRES=12*1852
COLLECTIVE_NAME='钓鱼岛及其附属岛屿'

def rows(html):
 result=[]
 for row in re.findall(r'<tr\b[^>]*>(.*?)</tr>',html,re.S|re.I):
  cells=[re.sub(r'\s+','',unescape(re.sub(r'<[^>]+>',' ',td))) for td in re.findall(r'<td\b[^>]*>(.*?)</td>',row,re.S|re.I)]
  if cells and cells[0].isdigit():result.append(cells)
 return result

def official_points(source):
 coords=rows(checked(source/'diaoyu_coordinates_20120915.original.html',COORDINATES_SHA256).decode('utf-8'))
 names=rows(checked(source/'diaoyu_names_20120302.original.html',NAMES_SHA256).decode('utf-8'))
 if len(coords)!=71 or len(names)!=71:raise ValueError('Official island table count differs')
 if [r[1] for r in coords]!=[r[1] for r in names]:raise ValueError('Official names and coordinate tables disagree')
 result=[]
 for row in coords:
  match=re.fullmatch(r'北纬(\d+)°([\d.]+)′东经(\d+)°([\d.]+)′',row[2])
  if not match:raise ValueError('Unknown official coordinate '+str(row))
  a,b,c,d=match.groups();result.append({'name':row[1],'lat':int(a)+float(b)/60,'lon':int(c)+float(d)/60,'publishedCoordinate':row[2]})
 return result

def build(source:Path,map_dir:Path,output:Path):
 from shapely import make_valid,union_all
 from shapely.geometry import shape,Polygon,Point,MultiPolygon,box
 from pyproj import Geod
 from align_vector_coast import load_vector_coast,polygon_parts
 from build_east_asia_names import decode_topology
 def clean(g):return MultiPolygon(polygon_parts(make_valid(g)))
 official=source/'official';points=official_points(official)
 law=checked(official/'territorial_sea_law.original.html',LAW_SHA256).decode('utf-8')
 text=re.sub(r'\s+','',unescape(re.sub(r'<[^>]+>',' ',law)))
 if '中华人民共和国领海的宽度从领海基线量起为十二海里' not in text:raise ValueError('Territorial width not found in pinned official law')
 baselines=baseline_features(official/'diaoyu_baselines_20120910.original.html')
 geod=Geod(ellps='WGS84');envelopes=[]
 for feature in baselines:
  ring=feature['geometry']['coordinates'][0];discs=[]
  for start,end in zip(ring,ring[1:]):
   _,_,length=geod.inv(*start,*end);steps=max(1,math.ceil(length/200))
   centres=[start]+geod.npts(*start,*end,steps-1) if steps>1 else [start]
   for lon,lat in centres:
    edge=[geod.fwd(lon,lat,azimuth,RADIUS_METRES)[:2] for azimuth in range(360)]
    discs.append(Polygon(edge))
  envelopes.append(clean(union_all([shape(feature['geometry'])]+discs)))
 vector=load_vector_coast(map_dir,decode_topology,clean)
 footprint=union_all(envelopes)
 land=[p for p in polygon_parts(vector['chinaLand']) if p.intersects(footprint)]
 land_union=union_all(land)
 main={'钓鱼岛','黄尾屿','赤尾屿','南小岛','北小岛','南屿','北屿','飞屿'}
 features=[];ambiguous=[]
 for polygon in land:
  matched=[p['name'] for p in points if p['name'] in main and polygon.covers(Point(p['lon'],p['lat']))]
  if not matched:
   for p in points:
    if p['name'] not in main:continue
    # Published tenths of an arcminute are reference coordinates, not exact
    # shoreline vertices. Assign only a unique existing island within that
    # stated coordinate resolution; never draw a land buffer around the point.
    mins=re.findall(r'°([\d.]+)′',p['publishedCoordinate'])
    eps=[10**(-len(m.split('.')[1]) if '.' in m else 0)/120 for m in mins]
    cell=box(p['lon']-eps[1],p['lat']-eps[0],p['lon']+eps[1],p['lat']+eps[0])
    candidates=[i for i in land if i.intersects(cell)]
    if len(candidates)==1 and candidates[0].equals(polygon):matched.append(p['name'])
  name=matched[0] if len(matched)==1 else COLLECTIVE_NAME
  if len(matched)!=1:ambiguous.append({'displayName':name,'reason':'No unique main-island coordinate inside this existing basemap polygon; no specific island name guessed','point':list(polygon.representative_point().coords)[0]})
  features.append({'type':'Feature','properties':{'displayName':name,'zoneKind':'islandLand'},'geometry':polygon.__geo_interface__})
 for base,envelope in zip(baselines,envelopes):
  inside=shape(base['geometry'])
  for kind,g in [('internalWaters',inside.difference(land_union)),('territorialSea',envelope.difference(inside).difference(land_union))]:
   features.append({'type':'Feature','properties':{'displayName':COLLECTIVE_NAME,'zoneKind':kind,'group':base['properties']['group']},'geometry':clean(g).__geo_interface__})
 output.mkdir(parents=True,exist_ok=True)
 _build_polygon_features(features,output/'diaoyu_official_regions.bin',lambda f:f['properties']['displayName'],double_precision=True)
 manifest={'name':COLLECTIVE_NAME,'officialBaselines':{'url':BASELINE_URL,'sha256':BASELINE_SHA256,'closedGroups':2,'uniqueBasepoints':17},
  'officialIslandCoordinates':{'url':'https://www.fmprc.gov.cn/diaoyudao/chn/zrhj/201510/t20151009_8520998.htm','sha256':COORDINATES_SHA256,'count':71},
  'officialIslandNames':{'url':'https://www.fmprc.gov.cn/diaoyudao/chn/zrhj/201510/t20151009_8520992.htm','sha256':NAMES_SHA256},
  'territorialRule':{'url':'https://www.mee.gov.cn/ywgz/fgbz/fl/202303/t20230314_1019569.shtml','sha256':LAW_SHA256,'nauticalMiles':12,'metres':RADIUS_METRES},
  'envelopeMeaning':'Computed WGS84 12-nautical-mile envelope from official baselines; NOT an officially published territorial-sea vector dataset',
  'approximation':{'baselineSampleMaximumMetres':200,'discAzimuthStepDegrees':1,'geodesicModel':'WGS84 ellipsoid, pyproj.Geod','expectedChordAndSamplingDeficitMetresUnder':2},
  'shorelineMeaning':'Existing unchanged app vector shoreline; official island reference coordinates are not used to fabricate island outlines',
  'originalSourcesUnchanged':True,'ambiguousBasemapIslandsUseOfficialCollectiveName':ambiguous,
  'points':points,'regions':[dict(f['properties'],labelPoint=list(shape(f['geometry']).representative_point().coords)[0]) for f in features],
  'baselineRings':[f['geometry']['coordinates'][0] for f in baselines],
  'outputSha256':hashlib.sha256((output/'diaoyu_official_regions.bin').read_bytes()).hexdigest()}
 (output/'diaoyu_official_regions.provenance.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print('Official Diaoyu regions:',len(features),'land names:',[f['properties']['displayName'] for f in features if f['properties']['displayName']!=COLLECTIVE_NAME],flush=True)
 return manifest

if __name__=='__main__':build(Path('references/region_data'),Path('assets/maps'),Path('assets/regions'))
