# 中国海洋预报网海啸地图核验

2026-10-21，只调查官网和原始响应，未修改 APP。
页面：https://www.oceanguide.org.cn/TsunamiWarning

## 实际页面

实际启动隔离 Chromium 加载官网，得到 2 个 Leaflet TileLayer：
高德普通地图、天地图中文注记。当前 now 数组长度 0，页面显示“暂无数据”，
最初加载 10 条历史报文，没有 JavaScript 异常。
当前地图不含活动海啸岸段或预报/观测点图层；截图的行政区名、海上红线来自底图。

页面的公开组件在有活动报文时读取 `latlng`，移动至震中，并在该点画红色闪烁点和
扩散圆。圆圈每 750 ms 新建，5 秒内从 6 到 100 像素，属于示意动画，非海啸走时计算。
空报文状态会禁用拖拽、触摸缩放、双击及滚轮缩放。

海啸专用 chunk 只调用 nowAlarm/history 和上述震中动画；未发现其加载独立的
海啸岸段 GeoJSON/TopoJSON。共享代码另有海浪/风暴潮区域绘制，不能据此声称
海啸页也具备同样区域接口。

## 网站实际请求

均为表单 POST，复用公开页面请求头，不记录公开脚本的静态请求头值：

|接口|参数|用途|
|---|---|---|
|`/hyyj2/warning/nowAlarm`|`type=bore`|当前海啸警报/消息|
|`/hyyj2/warning/history`|`type=bore&time=YYYY-MM`|按月历史报文|
|`/hyyj2/warning/detail`|`id=报文ID`|单报完整详情|

本次 nowAlarm 原文为 `{"success":false,"msg":"海洋灾害无数据"}`。
history 返回 count 174（报文条数，不能称为地震事件数）；初始 2026-10 有 10 条，
实际另取到 2025-07 的 24 条，包括黄色警报与解除报。2024-04 的 data 为空，
不将其解释为该月没有实际发生警报。

## 实际黄色警报详情

https://www.oceanguide.org.cn/warningDetails?id=e1c162695f42444e90b2590e0b4167be&type=

2025-07-30 14:24:30 第5期，`level=Ⅲ级`。

|原字段|实际含义|
|---|---|
|`latlng`|震中 `[52.53,160.16]`，纬度在前|
|`magnitude` / `depth`|震级 / 深度|
|`tblCon`|JSON 字符串，内含带表头的表格；不是岸段坐标|
|`tblCon` 第1表|省份、预报区域、预报点、预计到达（BJT）、最大波幅（厘米）、原预警颜色|
|`tblCon` 第2表|站名、位置、坐标、时间（BJT）、最大实测波幅（厘米）|
|`bak5`|岸段预报 JPG|
|`jsonPath`|此实际报文为深海最大波幅 JPG，不能按字段名假设是 JSON|
|`image`|震中位置 JPG|
|`standard` / `defenseGuide`|该级别标准 / 防御指南|

此报预报表有 7 个区域，监测表有 8 行：浮标21416、21414、21415、46413，
以及钏路港、阿特卡岛、中途岛、大船渡。原始坐标的经纬度半球与单位均未修改。

## 证据

`tmp/oceanguide_tsunami_20261021/` 保存官网原 JS、nowAlarm、两个月历史和第5期
详情的原始响应；`browser-observation.json` 保存实际浏览器图层和网络请求，
`live-page.png` 为页面截图。未在这里把图像反推成官方岸段边界。
