# 海啸地图区域描边

本轮只接地图区域图层，左下信息列表和右侧文字侧栏的排版不变。

## 数据与渲染

- NOAA PTWC／NTWC：从当前报文的官方 `jsonUrl` 定位同一期
  `PHEBevent.kmz`／`PAAQevent.kmz`，读取官方实际警戒分区。
- CAT：按原始报文 ID 加载官网逐期 CAP，读取其实际使用的 WKT
  `POLYGON ((经度 纬度…))`；同时兼容标准 CAP 坐标串，保留原文。
- INCOIS：按官网 indexHome.js 的规则，从同一期 detailUrl 定位
  `level2/*_threatmap.geojson`；按每个要素的 THREAT_CAT 画实际多边形，
  NoThreat／Threatpa 不画活动警戒区域。
  历史公开公报另接其逐报 SHP/KMZ 路径；KML 的状态名称与样式 ID 分开读取，
  兼容 PolyStyle 数字 ID，保持原始线色。
- CWA：按当前报文点名的六区名称关联静态海岸线，颜色取原始 areaColor；
  绿色、解除分区和无法匹配的地名不绘制。底图来自 ExpTech 开源资源，
  原文件逐字节保留并附来源与完整许可证；它不是 CWA 发布的逐报预警多边形。
- Rust 负责 KMZ 解包、KML／CAP／显式 GeoJSON 几何解析、颜色选择、
  经纬度校验、跨日期变更线拆分；网络走现有 NativeHttpClient。
- Dart 只负责异步桥接、模型转绘图坐标和调用现有 TsunamiLayer。
- 复用 JMA 的线宽随缩放调整及共享时钟：每秒两帧，六帧中五帧可见。
  其他机构的颜色独立选择，JMA 原有颜色不变。
- 优先使用官方 KML LineStyle 的原始色值与透明度；KML ABGR 转成
  Flutter ARGB。没有指定色值时使用对应颜色名称的常规 RGB 值，
  不声称这是官网未提供的精确色号。
- 解除、明确过期、异步返回旧报文时不显示旧轮廓；同一期原文件只缓存
  一个请求，缓存最多六份。无边界文件时不以震中、测站、范围端点推造区域。

## 各机构核验范围

| 机构 | 官方样式依据 | 当前边界接入情况 |
|---|---|---|
| PTWC／NTWC | Warning 红、Advisory 橙、Watch 黄；优先实际 KML LineStyle | 已接同一期官方 KMZ；PTWC 夏威夷原始历史警报39区和NTWC原始历史文件验证通过 |
| NMEFC | 海啸警报黄、橙、红三级；保留原文 warningLevel | 已接显式几何解析；现有报文仅区域名称时无法产生区域线 |
| CWA | 区域 areaColor 的红、橙、黄；解除为绿 | 已接六个具名沿海分区的静态海岸线匹配；显式几何和CAP多边形仍优先。底图为ExpTech资源，不冒称官方逐报边界 |
| INCOIS | 官网 threat map 的分区颜色；有 KML 时优先其原色 | 已接新式逐期 GeoJSON 和历史逐期 KMZ；2012-04-11 第2报真实原始 KMZ 的 55 个区域全部通过解析及 Flutter 接入测试 |
| CAT | 官网 ALERTA #d71717、SEGUIMIENTO #ec8210 | 已接逐期 CAP 的 WKT；官网 2026-07-17 警报和后续报两份原始多边形验证通过 |

只有区域名的报文需要经核对的具名岸段底图才能绘制；目前仅 CWA 六区
接了这种静态匹配。不能用行政区整块填充或连接点位替代官方预警区。

## 官方参考

- NOAA 地图与图例：https://www.tsunami.gov/?page=help
- NOAA 地图加载代码：https://www.tsunami.gov/js/esri.js
- NMEFC 实际橙色警报及分区域等级：
  https://obs.nmefc.cn/Warning/TsunamiAdvice/202404030758_2_file/202404030758_2.html
- CWA 灯号：https://scweb.cwa.gov.tw/en-us/tsunami/data?page=2
- CWA CAP 规范：https://alerts.ncdr.nat.gov.tw/web/StaticFile/Document/CapDocument_TS.pdf
- INCOIS Alert 橙色的官方演练公报（不能当作真实历史事件）：
  https://incois.gov.in/DSSProducts/Product_NTWC/Web/dss111005100000_Bulletin2_box_pub_A.html
- INCOIS 作业说明：https://tsunami.incois.gov.in/TEWS/dsssop.jsp
- CAT 官方颜色释义：https://diredimoat.semar.gob.mx/cat/Heraldica.html
- CAT 实际前端和 CAP 列表：
  https://diredimoat.semar.gob.mx/cat/js/app.js
  https://diredimoat.semar.gob.mx/cat/rss/listado_xml.json
- INCOIS 实际地图加载代码：https://tsunami.incois.gov.in/TEWS/js/indexHome.js
- INCOIS 实际历史警报第2报：
  https://tsunami.incois.gov.in/DSSProducts/Product_NTWC/Web/dss120411083800_Bulletin2_box_pub_A.html

## 本轮验证

- Rust 区域解析 13 项通过：原始 NOAA KMZ、原色 ABGR 转换、各源颜色区分、
  区域解除、跨日期变更线、错误坐标、损坏压缩包和 CAP 标识绑定。
  新增 CAT 两份原始 WKT 报文与逐期加载，以及 INCOIS 官方路径和分区状态测试。
  INCOIS 真实历史 KMZ 验证 38 Watch／14 Alert／3 Warning 及每组原始线色。
  CWA 验证六区原始坐标不变、颜色与解除、简繁区域名匹配、未知地名不造边界。
  PTWC 真实夏威夷警报验证35 Warning／4 Advisory，保留线色和透明度。
- Flutter 地图接入 13 项通过：官方同一期 URL、原报文不变、取消不请求、
  请求失败不造区域、原色与共享闪烁时钟、迟到结果及过期不恢复轮廓。
  包含 CAT 原始警报、后续报从逐期 URL 到 Rust WKT 解析的两项接入测试。
  包含 INCOIS 原始 KMZ 从公报链接到 Rust 编解码的接入测试。
  包含 CWA 本地底图无需HTTP与原色接入、PTWC夏威夷逐期KMZ接入。
  CWA逐报CAP优先于静态底图；CAP取消或无活动区域时不恢复静态岸段。
- 原有海啸模型、生命周期、左侧列表、右侧侧栏和 NMEFC 点层回归 44 项通过。
- 新增桥接、服务、区域层、公共描边层和测试的 scoped analyze 无问题。
  地图主文件原有 23 条 info 级提示，无 error／warning。
- 已构建 Rust 开发库；尚未重新构建或重启用户当前运行的 Windows APP，
  本轮代码未加载到该实例。没有触发实时预警或向 APP 注入测试报文。
- D 盘空间耗尽后，验证迁至 C 盘独立临时构建目录，没有清理用户数据。

## 历史原始数据复核

- INCOIS 2012-04-11 第2报：官网提供可下载的 KMZ，文件未改写地震时刻、
  波高、分区或坐标。当前代码同时支持历史 KMZ 与现代逐期 GeoJSON。
- CWA 11400503（2025-07-30 第3报，海嘯警訊）：
  https://scweb.cwa.gov.tw/zh-tw/tsunami/details?fileString=11400503
  原页面包含六区预估表与 `Tsu11400503.gif`、震源图 JPG，没有引用矢量分区文件。
- NMEFC 2024-04-03 第2报：原页面引用 `Tsunami_Maximum_Amplitude.jpg` 与
  `Coastal_Forecast_Point.jpg`；没有从该公报取得矢量岸段文件。
  这不等于断言机构不存在矢量数据，只记录当前入口尚未接通的部分。
