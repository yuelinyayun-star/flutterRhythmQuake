# USGS 原始 ShakeMap 捕获

捕获日期：2026-10-09。文件为原响应字节，不修改源时间、震源或产品数据。

- `summary.original.geojson`: `https://earthquake.usgs.gov/fdsnws/event/1/query?format=geojson&producttype=shakemap&limit=3&orderby=time`
- `us6000u0xi.detail.original.geojson`: `https://earthquake.usgs.gov/fdsnws/event/1/query?eventid=us6000u0xi&format=geojson`
- `us6000u0xi.versions.original.geojson`: 同一详情 URL 加 `&includesuperseded=true`。
- 图片基址：`https://earthquake.usgs.gov/product/shakemap/us6000u0xi/us/{updateTime}/download/`。
- 第 1 版：`1791451302104`；第 2 版：`1791451511958`；第 3 版：`1791457492389`。
- `*.intensity.original.png` 对应 `intensity_overlay.png`，`*.legend.original.png` 对应 `mmi_legend.png`。不带 `.v1` / `.v2` 后缀的图片为第 3 版。

`SHA256.json` 记录各原文件散列。测试的 HTTP 客户端只回放这些实际数据，不向 APP 或服务器注入模拟地震。

镜头切换断言回归使用以下原始详情和 `intensity_overlay.png`：

- `ci41345415`：用户截图的加利福尼亚州南部 M3.2 事件，详情为 `https://earthquake.usgs.gov/earthquakes/feed/v1.0/detail/ci41345415.geojson`；图片链接取自该详情的首选 ShakeMap 产品。
- `aka2026tvzrwv`：详情为 `https://earthquake.usgs.gov/earthquakes/feed/v1.0/detail/aka2026tvzrwv.geojson`，原始范围为经度 176.083–181.883，覆盖日期变更线；图片同样取自原始产品链接。

这四个文件捕获于 2026-10-09，保留原响应字节。

等烈度线版本增加 `*.cont_mmi.original.json`：分别从上述原始产品的
`contents['download/cont_mmi.json'].url` 下载原响应。包含瓦努阿图第 1、2、3 版、
加利福尼亚州事件以及阿拉斯加产品。阿拉斯加的响应为合法的空 FeatureCollection，
测试保留该实际情况，不构造线条。瓦努阿图三个产品的线数据相同，产品更新时间
和版本各自保留，用于验证版本更新和去重。
