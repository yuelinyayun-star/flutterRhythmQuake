# 2026-10-13 中大西洋海岭 USGS 烈度回归

2026-10-14 捕获，官方文件保留原始响应字节，散列见 `SHA256.json`。

- `us6000u214.versions.original.geojson`：
  https://earthquake.usgs.gov/fdsnws/event/1/query?eventid=us6000u214&format=geojson&includesuperseded=true
- 第 1 版产品更新时间 `1791895456255`，下载基址：
  https://earthquake.usgs.gov/product/shakemap/us6000u214/us/1791895456255/download/
- `us6000u214.v1.info.original.json` 对应 `info.json`，
  `us6000u214.v1.cont_mmi.original.json` 对应 `cont_mmi.json`。

第 1 版原始震源为 M6.9、深度 10km、发震时刻
`2026-10-13T12:23:07.383000Z`。其 `maxmmi` 为 `nan`，
`maxmmi-grid` 为 `8.195`；info.json 的 `MMI.max` 为 null，
`MMI.max_grid` 为 `8.195`。这是 ShakeMap 模型栅格最大值，不能当作台站实测。
当前详情的事件概要已修订为 M6.8；测试从第 1 版 info.json 读取震源，
不把当前概要改成截图里的旧震级。

`saved-usgs-body-keys.capture.json` 是本机 APP 已保存的去重记录中，
只选取该事件的三条完整字符串。它不是 WHEWS 原始 WS 报文。
记录显示同一 `us6000u214` 更新从 `9.0` 变为 `0`。
测试将这些记录字段投影到适配器接口，验证显示规则；未声称恢复完整原报文。
异常数值边界测试是单独构造的契约场景，不改写上述官方原始数据。

回归使用真实 AlertModule 渲染，原发震时间不改写，不向运行中的 APP 注入事件。
