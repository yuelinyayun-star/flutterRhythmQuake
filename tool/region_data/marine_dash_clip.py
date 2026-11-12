"""User-selected display partition along unchanged basemap maritime dashes."""
from shapely.geometry import Polygon
from align_vector_coast import polygon_parts


def taiwan_east_dash_partition(vector, taiwan_coverage, clean):
    # Select the two original eastern dashes, not earthquake region edges.
    dashes = [g for g in polygon_parts(vector['maritimeDashes'])
              if g.bounds[0] > 120 and g.bounds[1] > 20]
    if len(dashes) != 2:
        raise ValueError('Expected the two reviewed Taiwan-east basemap dashes')
    axes = []
    for g in dashes:
        coords = list(g.exterior.coords)
        edges = sorted(zip(coords, coords[1:]),
                       key=lambda e: (e[1][0]-e[0][0])**2+(e[1][1]-e[0][1])**2,
                       reverse=True)
        a, b = edges[0]
        c, d = edges[1]
        # Original strokes have two long opposite parallel sides and rounded
        # caps. Their midpoints give the source stroke's centreline.
        if a[1] > b[1]: a, b = b, a
        if c[1] > d[1]: c, d = d, c
        u, v = (b[0]-a[0], b[1]-a[1]), (d[0]-c[0], d[1]-c[1])
        if abs(u[0]*v[1]-u[1]*v[0]) > 1e-3:
            raise ValueError('Unreviewed stroke geometry')
        axes.append([[(a[0]+c[0])/2, (a[1]+c[1])/2],
                     [(b[0]+d[0])/2, (b[1]+d[1])/2]])
    axes.sort(key=lambda axis: axis[0][1])
    minimum, maximum = taiwan_coverage.bounds[1], taiwan_coverage.bounds[3]
    def extend(axis, latitude):
        a, b = axis
        return [a[0]+(latitude-a[1])*(b[0]-a[0])/(b[1]-a[1]), latitude]
    # The source is dashed, not a continuous polygon. These gap joins and end
    # extensions are explicit APP display derivations, never new source data.
    line = [extend(axes[0], minimum), *axes[0], *axes[1], extend(axes[1], maximum)]
    west = clean(Polygon([(70, minimum), *line, (70, maximum)]))
    return west, {
        'source': 'assets/maps/ka/cn.province.topo.json',
        'sourceSha256': vector['sources']['cn.province.topo.json'],
        'originalStrokeCount': 2,
        'originalStrokeAxes': axes,
        'derivedContinuousClipLine': line,
        'method': 'Original stroke centreline; straight joins between the two dashes; end tangents extended only to original CWA coverage bounds. APP naming partition, not a maritime legal delimitation.',
    }
