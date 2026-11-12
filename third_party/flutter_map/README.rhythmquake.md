# Local flutter_map 8.3.0 patch

Upstream library and license retained. Changes are limited to offsets.dart,
crs.dart, flutter_map.dart and new projected_points_transform.dart.

Hole rings are flattened once rather than repeatedly scanning a concatenated
iterable by elementAt. An optional batch callback exposes original static CRS
coefficients and immutable projected rings. Default behavior remains Dart;
RhythmQuake registers its Windows native batch backend. Projection, vertex
order, hole selection, world wrap, culling and painting stay upstream.
