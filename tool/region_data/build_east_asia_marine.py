"""Read published geographic sea areas, never national or EEZ boundaries."""
from pathlib import Path
import hashlib
import io
import zipfile
import shapefile
from shapely.geometry import shape, box

SOURCE_URL = 'https://naturalearth.s3.amazonaws.com/10m_physical/ne_10m_geography_marine_polys.zip'
SOURCE_SHA256 = 'a2d3395904c41e718e02c3ec5bc988712164c524c236fad32d95d282ca303b2a'
SEA_NAMES = {
    # Detailed physical bays and straits own their water before the parent
    # sea. Earthquake forecast grids are deliberately not geographic borders.
    'Hangzhou Bay': '杭州湾',
    'East Korea Bay': '东朝鲜湾',
    'Taiwan Strait': '台湾海峡',
    'Korea Strait': '朝鲜海峡',
    'Inner Sea': '濑户内海',
    'Bo Hai': '渤海',
    'Yellow Sea': '黄海',
    'East China Sea': '东海',
    'Sea of Japan': '日本海',
    'Sea of Okhotsk': '鄂霍次克海',
    'Bering Sea': '白令海',
    'South China Sea': '南海',
    'Philippine Sea': '菲律宾海',
    'North Pacific Ocean': '太平洋',
}


def public_marine_regions(clean):
    source = Path('references/region_data/natural_earth/ne_10m_geography_marine_polys.original.zip')
    raw = source.read_bytes()
    if hashlib.sha256(raw).hexdigest() != SOURCE_SHA256:
        raise ValueError('Unreviewed public geographic sea dataset')
    found = {}
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        layer = 'ne_10m_geography_marine_polys'
        reader = shapefile.Reader(**{ext: io.BytesIO(archive.read(layer + '.' + ext))
                                     for ext in ('shp', 'shx', 'dbf')}, encoding='utf-8')
        for record in reader.iterShapeRecords():
            props = record.record.as_dict()
            if props['name'] not in SEA_NAMES:
                continue
            if props['name'] in found:
                raise ValueError('Duplicate geographic sea: ' + props['name'])
            found[props['name']] = clean(shape(record.shape.__geo_interface__).intersection(box(70, 0, 180, 65)))
    if found.keys() != SEA_NAMES.keys():
        raise ValueError('Missing reviewed geographic sea names')
    return [(SEA_NAMES[name], found[name]) for name in SEA_NAMES], {
        'source': SOURCE_URL, 'sourceSha256': SOURCE_SHA256, 'version': '5.1.0',
        'meaning': 'Published geographic sea naming polygons, NOT national, territorial-sea or EEZ delimitations. Original source unchanged; derived water polygons are clipped against the app land and official Diaoyu priority regions.',
        'names': SEA_NAMES,
    }
