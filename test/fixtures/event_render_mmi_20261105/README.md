# 渲染窗口 MMI 原始报文

2026-11-05 捕获，未修改响应字节。

- 用户截图事件：`nc75462637`，2026-11-05 04:56:02.670 UTC，Petrolia 以西海域，M4.96。
- 详情：`https://earthquake.usgs.gov/fdsnws/event/1/query?eventid=nc75462637&format=geojson`
- 等值线：从原详情首选 ShakeMap 第 8 版 `contents['download/cont_mmi.json'].url` 直接下载：`https://earthquake.usgs.gov/product/shakemap/75462637/nc/1793879580177/download/cont_mmi.json`
- 9 个 Feature；`maxmmi=2.816`、`maxmmi-grid=5.19` 均保留。成图复用主地图已有的 `UsgsShakeMapProduct.maxMmi` 规则，优先使用有效 `maxmmi`，不修改源值，不用本地 CSIS 估计替换 MMI。
- `SHA256.json` 为两份原始响应散列。测试仅通过隔离 HTTP 客户端回放原响应，不向实时事件流注入事件。
