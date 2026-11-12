# JMA / P2P 区域数值方格与云电脑更新

## 本轮授权与最终显示

仅给四类普通 JMA / P2P 情报的既有填色增加区域数值标签。用户随后确认：圆角方格、同色系略提亮、少量透明度、参考 SREV 的方格缩放；所有数字检查视觉对齐，`1` 按主竖笔画对齐，`5-/5+/6-/6+` 以主数字为中心，符号放在右上角且不参与中心计算。不显示“弱／强”。最后授权本地编译并更新云电脑，再给出完整地图。

最终底色 HSL 色相及饱和度沿用区域填色，亮度提高 0.035，86% 不透明；没有黑色压暗层、灰色混合、阴影或渐变。设计尺寸 28 的圆角半径为 4.2，描边沿用同色系较深颜色。字体使用 APP 的 MPLUSRounded1c，主数字 20、符号 11，随方格整体缩放。

## 精确修改位置及前后行为

| 文件 / 位置 | 改动 |
|---|---|
| `lib/widgets/map/jma_region_value_label.dart`，`showJmaInformationRegionValues` | 仅四类普通 JMA 情报选择显示标签；EEW、LPGM 和单独的国外情报不启用。|
| 同文件 `jmaRegionValueText` | 复用现有震度格式化，使用 `useSymbol: true` 显示 `5-/5+/6-/6+`；原填色的 dark-gray 零震度标记显示 0。没有修改震度阈值或输入报文。|
| 同文件 `JmaRegionValuePlacement` | 原来没有区域数值；现在每个区域主体标一个。位置使用主体轮廓面积中心，凹形中心在区域外时向中心附近的内部位置收回；不再使用最大内接圆中心作为所有区域的位置。|
| `lib/widgets/map/jma_region_value_badge_layer.dart` | 新增独立 Canvas 标签层。区域色、字体、圆角、透明度及缩放均在此完成。数字字形尺寸来自项目已捆绑字体；`1` 的主竖笔画 x=300..443 / 1000 em，不能用含左侧斜挑的整个字形框中心。|
| 同文件 `JmaRegionValueBadgeTextLayout` | 主数字及符号分别测量、缓存和绘制；正负号采用相同视觉高度。组合的中心固定在主数字，避免正负号把主数字挤向左边。自建 TextPainter 在换报文及卸载时释放。|
| `lib/widgets/map/intensity_fill_layer.dart`，`showRegionValues`、标签构建和 `_paintPolygons` | 增加默认关闭的显示开关；复用原有多边形及填色值，关闭原生裸文字重复绘制，启用独立方格层。没有改填色计算、区域颜色、原透明度、几何发布回调。|
| `lib/widgets/map/quake_map_view.dart:3216` | 普通 JMA 合并填色入口显式启用上述标签。其他图层及视角规则没有借此改写。|
| `test/jma_region_value_label_test.dart` | 原始报文准入、零值及 ± 格式、主体内部位置、原几何与颜色、相机跟随、40 帧缓存、字形定位、透明度绘制及符号排版检查。|

这里新增的是 Flutter 字形布局、地图投影及绘制；没有新增 Dart 后端策略，也没有修改原有 Rust 相机计算、情报合并、EEW 排序或各类型震中定位。

## SREV 参考范围与性能

读取了本地 `ZeroStar645-srev-chinese-translation-053786c/srev-s/assets/project.json` 中地図角色的 `地震情報スタンプ` 和 `h1` 等 SVG。只参考其方格比例、深色轮廓、符号处理及缩放思想，没有替换 APP 震度配色、底图、测站、填色业务或自动视角。

SREV 的 h 方格为 200 单位，缩放百分比为 `1.1 * screenScale * (4 + sqrt(mapScale))`；其墨卡托地图每周 3600 单位、参考舞台 480×360。本项目将这些绘制单位换算到 FlutterMap 的世界像素宽度。桌面 1584×850 的实际绘图检查在 zoom 5/7/9 分别得到边长 25.877/30.977/41.176，地图缩放时同步刷新；不使用定时节流。

主体锚点使用弱引用拓扑缓存；同一报文复用多边形、文字和画笔；平移复用投影，缩放时更新投影。只对可见区域解析内部锚点；用帧内空间桶避免标签重叠，不累计历史占位。40 帧检查未新建多边形列表、锚点或 Polygon 文字画笔。该结果是缓存检查，不代表已经测得云电脑 CPU 降幅。

## 实际渲染及数据边界

证据目录：`tmp/jma_region_values_20261102`。

- `badge-styles.png`：真正的方格图层绘制字符样式表；大矩形仅模拟区域填色，不是地震观测。最终数字居中调整直接重渲染、查看该图，没有反复运行无关测试。
- `detail-active.png` / `detail-idle.png`：生产 QuakeMapView、生产 Provider / 本地注入入口、Rust 相机及原始 P2P 情报的完整地图。测站坐标为原始 NIED 数据库；震动和平静数值是独立的样式模拟，不是实测，未送进原生检出或推算。震中标题白块是离屏引擎默认字体的限制，不代表云电脑实机故障。
- `prompt/destination/combined/detail.json`：四类原始报文入口已检查相机中心和 zoom 与添加标签前一致。后续共同样式调整重点重渲染样式表及完整 DetailScale 地图。
- `cloud-full-map.png`：更新后的云电脑 APP 实际窗口画面，从其现有 OBS 窗口源只读取得，1264×681。没有切换 OBS 场景、启动推流或注入假报文；当时没有有效预警，因此该实机图不冒充区域填色触发验证。

原始数据未修改，SHA256：

- `test/fixtures/jma_camera_20261030/p2p_history.original.json`：`a2a69f5c5b709d635eef95041199d28717a2626f5363a3d5aba9b2bab96fd9df`。
- `test/fixtures/catalog_20260917/whews_all.json`：`f69c83e0ed636684264840061ffa6873aecf769db5bd2a2146ba3c4799cda5db`。

功能实现阶段的 26 项相关回归通过；最终字符改版的 8 项针对性检查和样式绘图通过，最后“主数字而非整个组合居中”的调整又实际重绘检查。源码检查、离屏渲染、发布构建与实机启动分别记录，不将其中一项当成其他项。

## 构建、部署和运行

使用 `package_windows.ps1 -Edition personal -SkipProcessCleanup` 完成本地 Release 和 Inno 安装包，未关闭其他 Dart 工作进程。

- 安装包：`build/installer/RhythmQuake_Setup_1.0.5.22_personal_x64.exe`，41635101 字节。
- SHA256：`e37772dbe6d643a6e5838d17c8607621133b9b5b0d4b47622621690a4ff714ca`。
- MCP 目标实查：`DESKTOP-VUEC9GQ`，生产目录 `E:\RhythmQuake`。连接器不可用后恢复本机既有认证 SSH / MCP 隧道，未使用 RDP 或本地桌面。
- 与云端实际文件哈希比较后，仅部署 `data/app.so`、`rq_station_core.dll` 及发布清单。包含此前已完成但未打包的原生修复，见回放与跨线修复对应文档；本轮没有继续修改这些后端。
- ZIP 传输后校验归档、成员路径和每个文件；替换后 141 个发布文件哈希全部通过。清单 SHA256：`d78ad8615e4d3e2305fe98e10d39d1452072ad0f98687c05e7289f54b3834473`。
- 新 APP PID 5552，SessionId 1，路径 `E:\RhythmQuake\flutterrhythmquake.exe`，`Responding=true`，标题 RhythmQuake；实际图中数据和时间继续更新。
- 没有创建旧版本备份、修改用户设置、停止 MCP 或改 OBS 配置；部署暂存 ZIP、Base64 和展开目录已删除。此次为与安装包相同内容的增量更新，不冒充执行过安装向导。
