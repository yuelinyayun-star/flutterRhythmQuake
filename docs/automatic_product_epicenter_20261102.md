# 自动产品震中复用情报图层（2026-11-02）

## 本次范围

用户要求修复第二条 DYFI 漏画震中，并明确“除了手动外其他的都复用”。本次将 DYFI、ShakeMap 的自动震中放回既有普通情报的 QuakeWaveLayer；手动选中继续使用 HistoryMarkerLayer。没有修改事件接纳、产品有效期、原始字段、轮播、视角计算、DYFI 网格或 ShakeMap MMI 绘制。CMT beachball、火山与 SASMEX 原有特殊符号规则保留。

## 已确认的调用链与修复前复现

1. 原 QuakeMapView 的自动事件循环明确跳过 usgsDyfi 和 usgsShakeMap，所以它们没有走普通情报震中层。
2. 另一个专用 Selector 只从一个 ShakeMap frame 和一个 DYFI frame 补画 HistoryMarkerLayer；一旦 selectedHistoryEvent 非空，整个自动补画分支被跳过，只绘制手动历史事件。
3. Provider 同时允许手动第一条与自动第二条卡片存在；DYFI 网格 getter 可正确返回当前自动事件，但震中分支仍只画第一条手动选择。根因在渲染入口，不是原始震中坐标不存在。
4. 原样提取旧渲染循环后，使用两条官方原始详情与 KMZ，通过实际 QuakeProvider 的选择与发布入口复现：手动 California + 自动 Kenai，自动震中组件为 0；两个自动 DYFI 身份均被过滤。两个回归用例修复前均失败，日志 `tmp/cloud_vgpub_20261101/dyfi-epicenter-before.log`。

## 精确文件与行为

| 文件与位置 | 原行为 | 本次行为 |
| --- | --- | --- |
| `lib/widgets/map/unified_event_wave_layers.dart`（新增），UnifiedEventWaveLayers | 普通自动事件的循环内嵌在 QuakeMapView，过滤两个 USGS 产品 | 提取并直接复用同一循环；DYFI/ShakeMap 与其他情报用同一 QuakeWaveLayer。情报 showWaves=false、blinkOn=true；EEW 原参数和动画不变。 |
| 同文件，unifiedMapLayerKey | 原函数位于 QuakeMapView | 原函数行为不变地迁移，仍按 source/事件ID/EEW或info区分，同报次更新复用 State；QuakeMapView 保留 export，不破坏旧调用和测试。 |
| 同文件，ordinaryKeys/productKeys | 专用产品分支对同一事件的两个产品避免重复标记 | 自动产品与普通 USGS 情报共用同一地震的震中，避免重复 key 和重复十字；普通情报存在时保留其原 key/state。不同事件 ID 分别绘制。卡片不合并、产品数据不合并。 |
| `lib/widgets/map/quake_map_view.dart`，自动震中循环 | 跳过 DYFI/ShakeMap | 调用上述统一图层，保留所有既有 EEW/情报渲染参数。 |
| 同文件，手动历史 Selector | 手动事件与自动产品补画二选一 | 仅保留原手动 HistoryMarkerLayer；自动产品已由统一图层负责，不再另做补画。 |
| `test/usgs_product_epicenter_layers_test.dart`（新增） | 缺少多事件与手动/自动并存验证 | 验证原始 California + Kenai、两条自动身份、自动 ShakeMap 与 MMI 并存、同震去重、所有原文件 SHA256 不变。 |
| `test/fixtures/usgs_dyfi/two_events_20261102/*`（新增） | 无截图这两个事件的最新原始样本 | 保存官方两份原始详情、两份 KMZ、SHA256 和来源清单。California 官方已从截图的 79 份更新到 81 份，没有改写成 79；Kenai 原始值为 113/CDI3.9。 |

这是 Flutter 的渲染组合与图层复用，属于 UI 层；没有在 Dart 新增或回退后端计算，现有原生数据适配保持不变。

## 验证与边界

- 8 个相关测试文件共 45 项通过：上述多事件用例、原图层 key、DYFI 信息轮播、ShakeMap 线层与图例、DYFI/ShakeMap 的桌面与手机视角、JMA 既有震中居中回归。
- 原始样本通过实际产品服务加载，KMZ 沿用 Rust 解析；原始坐标、震级、CDI/MMI、报告数和时间未改写。
- 实际 Flutter 组件渲染图已检查，自动 Kenai 的红色震中与原网格同时存在；手动 California 不再抑制它。该组件截图使用测试引擎，默认 Canvas 字体仍受 Ahem 限制，不能用此截图声称已完成安装版字体验收。
- 本轮只完成本地源码与测试。没有重新打 APP 安装包、安装或更新云端；没有占用本地桌面。

同轮先完成的 NIED 透明缺测与灰色站修复，详见 `nied_detection_capture_20261102.md` 的“后续授权修复”部分，与本次产品震中修复分开记录。
