# 基奈半岛 DYFI 原始产品

2026-11-01 获取的 USGS 原始响应字节，不改坐标、时间、CDI、报告数或网格。

- `detail.original.geojson`：https://earthquake.usgs.gov/fdsnws/event/1/query?eventid=aka2026vqjriv&format=geojson
- `dyfi_geo.original.kmz`：https://earthquake.usgs.gov/product/dyfi/aka2026vqjriv/us/1793540971803/dyfi_geo.kmz
- 产品更新时间：1793540971803（北京时间 2026-11-01 21:49:31.803）。
- 总问卷 90，最大 CDI 3.9；原 KMZ 含 71 个多边形，网格问卷合计 87。差值不得补成虚构网格。
- 产品没有 `dyfi_geo_10km.geojson` / `dyfi_geo_1km.geojson`。KMZ 中原始 UTM 单元名记录 1000 米网格。

SHA-256：

```text
1cd8f3f61ab8bce7cd45d2aa5061510386b14671dd8d1a6ea60a6e64c3fb1c21  detail.original.geojson
fe5a5ada03de74b2a456065ec4ea29088b9306ae4140e043996f6044f17d7ed5  dyfi_geo.original.kmz
```
