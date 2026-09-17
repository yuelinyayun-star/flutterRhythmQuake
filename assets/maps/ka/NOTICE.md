# KA Basemap Data

Copied byte-for-byte on 2026-09-09 from the local kanameishi-dev reference
snapshot. No source coordinates, features, names, or topology were rewritten.
The local snapshot has no Git metadata; an upstream commit is not asserted.

Upstream: https://github.com/Lipomoea/kanameishi

KA credits these original data sources:

- Mainland China: Alibaba DataV.GeoAtlas, https://datav.aliyun.com/portal/school/atlas/area_selector
- Taiwan: GeoJSON.cn, https://geojson.cn/
- Japan: Japan Meteorological Agency, https://www.data.jma.go.jp/developer/gis.html
- Global: GeoJSON Maps of the globe, https://geojson-maps.kyd.au/

KA's repository license is retained verbatim as KA-LICENSE.txt (AGPL-3.0).
This notice does not replace original data-provider terms or establish that
those terms have been cleared for every redistribution use.

SHA-256:

```text
95d0495902b6ca977b0f5cbb5e733ee8cc55c15ef2182dcf5509dec1c3b0e955  medium.global.modified.topo.json
0a78934167d64f112a64393be3ed3a276c0584e3e56fc46ea3791049790bea0b  jp.pref.topo.json
4b64a2d342c1017b1b571a4e02c92bafac0e114e9f3c31860b1b1bba4dc56965  cn.province.topo.json
```

Render order: global, Japan, China. Unnamed features and all polygon holes are
retained. Original data preservation and selected geographic regression checks
are not a formal map-content approval or a map review number. See
docs/vector_basemap.md for the checked scope and remaining release review.
