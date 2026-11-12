#!/usr/bin/env python3
"""Derive disjoint place-name regions; original source files are never rewritten."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import struct

from build_region_assets import _build_polygon_features

PREF_HASH = "234914ee3a13beea6ef25f148e5c3a1ba6d0d1f0d0d8eb2af6a1732792ecf3ed"
TOPO_HASH = "ff7295ceeac5996a4b7b0be1c6d0081e232e18a87ddd211ebf5d59383795acee"
PREF_NAMES = dict(zip(
    "北海道 青森県 岩手県 宮城県 秋田県 山形県 福島県 茨城県 栃木県 群馬県 埼玉県 千葉県 東京都 神奈川県 新潟県 富山県 石川県 福井県 山梨県 長野県 岐阜県 静岡県 愛知県 三重県 滋賀県 京都府 大阪府 兵庫県 奈良県 和歌山県 鳥取県 島根県 岡山県 広島県 山口県 徳島県 香川県 愛媛県 高知県 福岡県 佐賀県 長崎県 熊本県 大分県 宮崎県 鹿児島県 沖縄県".split(),
    "北海道 青森县 岩手县 宫城县 秋田县 山形县 福岛县 茨城县 栃木县 群马县 埼玉县 千叶县 东京都 神奈川县 新潟县 富山县 石川县 福井县 山梨县 长野县 岐阜县 静冈县 爱知县 三重县 滋贺县 京都府 大阪府 兵库县 奈良县 和歌山县 鸟取县 岛根县 冈山县 广岛县 山口县 德岛县 香川县 爱媛县 高知县 福冈县 佐贺县 长崎县 熊本县 大分县 宫崎县 鹿儿岛县 冲绳县".split()))


def binary_features(path):
    b=path.read_bytes();h=struct.unpack_from('<4s14I',b)
    magic,version,nf,np,nr,nt,nn,so,fo,po,ro,vo,fs,ps,rs=h
    assert magic in (b'CWR1',b'CWR2') and version==1
    double=magic==b'CWR2';point_size=16 if double else 8
    offsets=struct.unpack_from('<'+str(nn+1)+'I',b,so);base=so+4*(nn+1)
    names=[b[base+offsets[i]:base+offsets[i+1]].decode('utf-8') for i in range(nn)]
    result=[]
    for i in range(nf):
        ymin,ymax,xmin,xmax,ni,start,count,order=struct.unpack_from('<4d4I' if double else '<4f4I',b,fo+i*fs)
        polys=[]
        for p in range(start,start+count):
            first,n=struct.unpack_from('<2I',b,po+p*ps);rings=[]
            for r in range(first,first+n):
                pi,npt=struct.unpack_from('<2I',b,ro+r*rs)
                rings.append(list(struct.iter_unpack('<2d' if double else '<2f',b[vo+pi*point_size:vo+(pi+npt)*point_size])))
            polys.append(rings)
        result.append({'type':'Feature','properties':{'displayName':names[ni]},
                       'geometry':{'type':'MultiPolygon','coordinates':polys}})
    return result


def decode_topology(raw):
    scale=raw['transform']['scale'];shift=raw['transform']['translate'];arcs=[]
    for arc in raw['arcs']:
        x=y=0;points=[]
        for dx,dy in arc:
            x+=dx;y+=dy;points.append([x*scale[0]+shift[0],y*scale[1]+shift[1]])
        arcs.append(points)
    def stitch(refs):
        points=[]
        for ref in refs:
            part=arcs[ref] if ref>=0 else list(reversed(arcs[~ref]))
            if points:
                if points[-1]!=part[0]:raise ValueError('Disconnected original topology')
                points.extend(part[1:])
            else:points.extend(part)
        if points[0]!=points[-1]:raise ValueError('Unclosed original topology')
        return points
    result=[]
    for g in raw['objects']['region']['geometries']:
        refs=g['arcs'] if g['type']=='MultiPolygon' else [g['arcs']]
        result.append({'type':'Feature','properties':g['properties'],
                       'geometry':{'type':'MultiPolygon','coordinates':[[stitch(r) for r in p] for p in refs]}})
    return result


def build(map_dir, output):
    from opencc import OpenCC
    from shapely import make_valid, union_all, STRtree, set_precision
    from shapely.geometry import shape, mapping, Polygon, MultiPolygon, GeometryCollection
    from align_vector_coast import load_vector_coast, fill_gaps, fill_marine_to_coast, align_named_islands
    repair=Counter()
    def polygons(g):
        if g.is_empty:return []
        if g.geom_type=='Polygon':return [g]
        if g.geom_type in ('MultiPolygon','GeometryCollection'):
            return [p for part in g.geoms for p in polygons(part)]
        return []
    def clean(g):
        if not g.is_valid:
            repair['invalid_source_or_operation_geometries']+=1;g=make_valid(g)
        # A common sub-millimetre overlay grid keeps shared coast edges
        # identical through different intersection/difference paths.
        return set_precision(MultiPolygon(polygons(g)),1e-9)
    def geo(f):return clean(shape(f['geometry']))
    def checked(path,sha):
        b=path.read_bytes()
        if hashlib.sha256(b).hexdigest()!=sha:raise ValueError('Unreviewed source '+str(path))
        return json.loads(b)
    pref=checked(map_dir/'japan_prefectures.geojson',PREF_HASH)
    topo=decode_topology(checked(map_dir/'jp.eew.topo.json',TOPO_HASH))
    if len(pref['features'])!=47 or len(topo)!=191:raise ValueError('Unexpected Japanese source coverage')
    print('Reading original land blockers',flush=True)
    vector=load_vector_coast(map_dir,decode_topology,clean)
    cn=[vector['chinaLand']]
    bases=[geo(f) for f in binary_features(output/'diaoyu_official_regions.bin')]
    reserved=cn+bases
    def write_layer(items,path):
        _build_polygon_features([{'type':'Feature','properties':{'displayName':n},'geometry':mapping(g)} for n,g in items if not g.is_empty],output/path,lambda f:f['properties']['displayName'],double_precision=True)
    write_layer(vector['china'],'east_asia_china_coast.bin')
    write_layer([('APP矢量地图陆地',vector['land'])],'east_asia_land_mask.bin')
    def subtract(g,blockers):
        if g.is_empty or not blockers:return g
        candidates=STRtree(blockers).query(g,predicate='intersects')
        relevant=[blockers[i] for i in candidates if g.intersection(blockers[i]).area>0]
        return clean(g.difference(union_all(relevant))) if relevant else g
    pref_features=[];neutral=[]
    for f in pref['features']:
        name=f['properties']['N03_001'];coords=f['geometry']['coordinates']
        parts=coords if f['geometry']['type']=='MultiPolygon' else [coords]
        regular=[]
        for index,p in enumerate(parts):
            label=None
            if name=='北海道':
                if index in range(7,13):label='南千岛群岛'
                if index==13:label='择捉岛'
                if index in (20,21,22):label='色丹岛'
                if index==23:label='国后岛'
            if name=='沖縄県' and index in (4,5,6,7):label='钓鱼岛及其附属岛屿'
            if label:
                neutral.append((label,clean(Polygon(p[0],p[1:])),'neutralLand'))
            else:regular.append(p)
    # Match the land actually filled by VectorBasemapService, not the other
    # prefecture shoreline used in the preceding version of this index.
    def vector_pref_name(p):
        code=p['code']
        if code.startswith('901'):return '日本北海道'
        special={'9131':'日本东京都','9132':'日本东京都伊豆群岛','9133':'日本东京都小笠原群岛',
                 '9462':'日本鹿儿岛县奄美群岛','9471':'日本冲绳县本岛','9472':'日本冲绳县大东岛','9473':'日本冲绳县宫古岛','9474':'日本冲绳县八重山群岛'}
        if code in special:return special[code]
        ordinal=(int(code)-9000)//10
        return '日本'+list(PREF_NAMES.values())[ordinal-1]
    for p,g in vector['japan']:
        pref_features.append((vector_pref_name(p),set_precision(subtract(g,reserved),1e-9),'japanLand'))
    jp_land=union_all([g for _,g,_ in pref_features])
    neutral_land=union_all([g for _,g,_ in neutral])
    kr=[]
    for f in binary_features(output/'korea_land_regions.bin'):
        name=f['properties']['displayName'];g=geo(f)
        # Keep named tiny disputed islands when the coarse global basemap has
        # no polygon for them; no neighbouring country's sea owns these points.
        if name=='独岛（竹岛）':neutral.append((name,g,'neutralLand'));continue
        kr.append((name,subtract(clean(g.intersection(vector['koreaLand'])),reserved+[jp_land]),'koreaLand'))
    kr_filled,kr_coast=fill_gaps(vector['koreaLand'],[(n,g) for n,g,k in kr],clean,'korean land')
    kr=[(n,g,'koreaLand') for n,g in kr_filled]
    kr_land=union_all([g for _,g,_ in kr])
    neutral,retained_islands=align_named_islands(neutral,vector['land'],clean)
    neutral_land=union_all([g for _,g,_ in neutral])
    land_block=reserved+[vector['land'],neutral_land]
    cc=OpenCC('t2s')
    def land_name(p):
        value=p['name']
        for a,b in [('県','县'),('広','广'),('徳','德'),('児','儿'),('浜','滨'),('壱','壹'),('対','对'),('騨','驒'),('縄','绳'),('軽','轻'),('隠','隐'),('豊','丰'),('・','、'),('中通り','中通'),('通り','通'),('山沿い','山地')]:value=value.replace(a,b)
        value=cc.convert(value).translate(str.maketrans('０１２３４５６７８９','0123456789'))
        if int(p['code'])<200 and not value.startswith('北海道'):value='北海道'+value
        return '日本'+value
    detailed=[]
    for f in topo:
        if not f['properties'].get('code'):continue
        detailed.append((land_name(f['properties']),clean(set_precision(geo(f),1e-9).intersection(jp_land,grid_size=1e-9)),'japanLand'))
    # Partition only derived files. First explicit subdivision owns shared area;
    # prefecture names cover remaining real land, never unmasked offshore cells.
    rows=[];occupied=[]
    def take(name,g,kind,mask=None):
        source_area=g.area
        if mask is not None:g=subtract(g,mask)
        g=subtract(g,occupied)
        if g.is_empty:return
        rows.append((name,g,kind,source_area));occupied.append(g)
        if len(rows)%50==0:print('Partitioned',len(rows),'regions',flush=True)
    for name,g,kind in neutral:take(name,g,kind,reserved)
    for name,g,kind in detailed:take(name,g,kind)
    for name,g,kind in pref_features:take(name,g,kind)
    for name,g,kind in kr:take(name,g,kind)
    land_rows=len(rows)
    marine=[];marine_kinds=[]
    originals={path:[(f['properties']['displayName'],geo(f)) for f in binary_features(output/path)]
               for path in ('japan_sea_regions.bin','cwa_epicenter_regions.bin')}
    cwa_coverage=clean(union_all([g for _,g in originals['cwa_epicenter_regions.bin']]))
    from marine_dash_clip import taiwan_east_dash_partition
    west,dash_partition=taiwan_east_dash_partition(vector,cwa_coverage,clean)
    west_cwa=clean(cwa_coverage.intersection(west))
    for path,kind in [('japan_sea_regions.bin','japanSea'),('cwa_epicenter_regions.bin','taiwanSea')]:
        for name,g in originals[path]:
            if kind=='taiwanSea':g=clean(g.intersection(west))
            elif name!='东海':g=clean(g.difference(west_cwa))
            marine.append((name,g));marine_kinds.append(kind)
    marine,marine_coast=fill_marine_to_coast(marine,union_all(land_block),clean)
    for (name,g),kind in zip(marine,marine_kinds):take(name,g,kind,land_block)
    # Adjacent source cells with the same East China Sea name are one naming
    # region; remove their internal display seam without changing coverage.
    east=[r for r in rows if r[0]=='东海' and r[2]=='japanSea']
    if len(east)>1:
        merged=('东海',clean(union_all([r[1] for r in east])),'japanSea',sum(r[3] for r in east))
        position=next(i for i,r in enumerate(rows) if r[0]=='东海' and r[2]=='japanSea')
        rows=[r for r in rows if not (r[0]=='东海' and r[2]=='japanSea')]
        rows.insert(position,merged)
    # User requests the original base naming entry for this whole East China
    # Sea area, including Diaoyu. Store an explicit routing region in the same
    # hashed index; do not rename the base FE data or change other fine seas.
    def use_base(name,kind):
        return name=='东海' and kind=='japanSea'
    replaced_taiwan=[n for n,g,k,a in rows if k=='taiwanSea' and use_base(n,k)]
    base=clean(union_all([g for n,g,k,a in rows if use_base(n,k)]+bases))
    rows=[r for r in rows if not use_base(r[0],r[2])]
    rows.insert(0,('__BASE_FE__',base,'baseFE',base.area))
    rows=[('中国'+n if k=='taiwanSea' and not n.endswith('近岸海域') else n,g,k,a)
          for n,g,k,a in rows]
    fs=[{'type':'Feature','properties':{'displayName':n,'kind':k},'geometry':mapping(g)} for n,g,k,a in rows]
    _build_polygon_features(fs,output/'east_asia_names.bin',lambda f:f['properties']['displayName'],double_precision=True)
    # Audit the actual compiled output. CWR2 retains double-precision clipping
    # coordinates so Float32 rounding cannot reintroduce polygon slivers.
    compiled=binary_features(output/'east_asia_names.bin');geoms=[geo(f) for f in compiled]
    tree=STRtree(geoms);overlaps=[]
    for i,g in enumerate(geoms):
        for j in tree.query(g,predicate='intersects'):
            if j<=i:continue
            area=g.intersection(geoms[j]).area
            if area>1e-10:overlaps.append({'a':rows[i][0],'b':rows[j][0],'squareDegrees':area})
    if overlaps:raise ValueError('Compiled derived polygons overlap: '+str(overlaps[:5]))
    result={'purpose':'Disjoint derived lookup regions, not national or EEZ boundaries',
            'originalSourcesUnchanged':True,'prefectureSourceSha256':PREF_HASH,'subdivisionSourceSha256':TOPO_HASH,
            'japaneseSource':'Existing app assets, not claimed as a newly downloaded official GIS release',
            'coastlineAlignment':{'basemapSources':vector['sources'],'landMask':'east_asia_land_mask.bin',
                'chinaCoast':'east_asia_china_coast.bin','koreanLand':kr_coast,'marine':marine_coast,
                'protectedSmallIslandsAbsentFromBasemap':retained_islands,
                'addedAreasAreDerivedRepairsNotOfficialMarineBoundaryChanges':True},
            'japanSubdivisionCount':len(detailed),'japanPrefectureCount':47,'vectorJapanFeatureCount':len(vector['japan']),'landFeatureCount':land_rows,
            'features':len(rows),'groups':dict(Counter(r[2] for r in rows)),
            'priority':['base FE in East China Sea including Diaoyu','existing China land and official Diaoyu baseline-derived regions elsewhere','neutral island names','Japanese real-land subdivisions','Japanese real-land prefecture remainder','Korean real land','original Japanese marine polygons; existing fine names and East China Sea edges','original Taiwan marine polygons after clipping their overlap with the preceding marine regions','original base FE; South Korea display alias is 朝鲜半岛南部'],
            'marineOverlapRule':'Taiwan-east basemap dashed line partitions CWA/JMA overlap; original fine names retained. Original East China Sea connects above; equal East China Sea names are dissolved.',
            'marineDashPartition':dash_partition,
            'baseFERouting':'Effective East China Sea including Diaoyu uses unchanged base FE. Taiwan broad and nearshore marine regions remain detailed.',
            'taiwanBroadSeaNamePrefix':'中国',
            'baseFEReplacedTaiwanNames':replaced_taiwan,
            'geometryOperations':'Intersection/difference/union on derived data only; make_valid when required; no simplification or buffers',
            'derivedOverlayPrecisionDegrees':1e-9,
            'repairs':dict(repair),'compiledOverlaps':overlaps,
            'format':'CWR2, Float64 geometry and bounding boxes; originals remain CWR1',
            'outputSha256':hashlib.sha256((output/'east_asia_names.bin').read_bytes()).hexdigest(),
            'outputBytes':(output/'east_asia_names.bin').stat().st_size,
            'regions':[{'name':n,'kind':k,'sourceSquareDegrees':a,'effectiveSquareDegrees':g.area,
                        'labelPoint':[g.representative_point().x,g.representative_point().y]} for n,g,k,a in rows]}
    (output/'east_asia_names.provenance.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k not in ('regions','compiledOverlaps','coastlineAlignment')},ensure_ascii=False),flush=True)
    print('overlaps in compiled output:',len(overlaps),flush=True)
    return result


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--map-dir',type=Path,default=Path('assets/maps'))
    p.add_argument('--output-dir',type=Path,default=Path('assets/regions'));a=p.parse_args();build(a.map_dir,a.output_dir)
