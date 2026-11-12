# USGS 原始 DYFI 捕获

这些文件保留官方响应原始字节，未修改时间、震级、坐标、报告数或 CDI。SHA-256 见同目录 `SHA256SUMS.txt`。

- `ci41345415.dyfi_geo_10km.original.geojson`：191 份报告版本的原始 10 km 网格。来源：https://earthquake.usgs.gov/pdl/products/urn:usgs-product:us:dyfi:ci41345415:1791532575397/contents/dyfi_geo_10km.geojson 。对应详情保留在 `../usgs_shakemap/ci41345415.detail.original.geojson`。
- `ci41345415.versions.original.geojson`：包含历史产品的完整原始详情，2026-10-10 捕获。来源：https://earthquake.usgs.gov/fdsnws/event/1/query?eventid=ci41345415&format=geojson&includesuperseded=true 。回放只选择其中实际发布的对应产品对象，不修改产品字段。
- `ci41345415.210.dyfi_geo_10km.original.geojson`：210 份报告版本的原始网格。来源：https://earthquake.usgs.gov/product/dyfi/ci41345415/us/1791532884156/dyfi_geo_10km.geojson 。
- `us6000u0xi.dyfi_geo_10km.original.geojson`：另一实际地震的原始网格。来源：https://earthquake.usgs.gov/product/dyfi/us6000u0xi/us/1791453896368/dyfi_geo_10km.geojson 。详情位于 `../usgs_shakemap/us6000u0xi.detail.original.geojson`。

191 份报告版本有 15 个可绘制网格，网格内问卷合计 187 份。卡片总数读取产品 `numResp`，不能把差值补成虚构网格。
