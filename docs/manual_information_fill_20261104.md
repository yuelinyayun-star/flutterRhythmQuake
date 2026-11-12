# 信息栏手动选择的地图填色

## 本次范围

让原本支持自动填色的普通地震情报在信息栏手动选择时也能填色，并预留同一图层的渲染入口。本次是展示路径和展示数据传递的修正，未修改震度计算公式、Rust 后端策略、视角计算、轮播、来报接收或告警规则。

原调用链的问题：普通填色层只读取 `unifiedEvents`；手动选择保存在 `_selectedHistoryInfo`，不在这个集合中。此外，统一情报转列表行时未保留 `warnArea` 等填色输入，单靠精简行无法恢复已有观测区域。

## 具体文件和行为

| 文件、位置 | 原行为 | 新行为 |
| --- | --- | --- |
| `lib/models/information_map_data.dart`（新增） | 无列表填色快照 | 保留原情报来源、标题、震度区域及长周期报文；CWA 保留原始参数，供既有修正系数和取消／训练判断使用。原始报文不改写。 |
| `lib/models/quake_message.dart`：`informationMap`、构造、复制、`toMap/fromMap` | 列表行只传递震源摘要 | 可附带填色快照并经过 JSON 往返；旧行没有新字段仍能读取。 |
| `lib/providers/quake_provider.dart`：`_unifiedToQuakeMessage` | 转列表行丢失区域填色输入 | 非 EEW 情报保留上述快照；EEW 不加入这个快照。 |
| 同文件：`selectedInformationMapEvent`（新增公开 getter） | 没有独立手动地图输入 | 复用已有信息卡匹配结果，优先使用仍保留的完整情报，否则读取选中行快照；弱缓存按地图数据版本复用展示对象，避免跟随刷新反复重建。 |
| `lib/services/sources/eqlist/jma_eqlist_service.dart`：`_parseP2PQuakeItem` | HTTP 列表丢弃原始测站／区域震度 | 复用现有适配器保留区域和原情报标题；原列表字段、过滤和排序保持。新增 `forTesting` 客户端注入只用于测试，生产仍使用原请求。 |
| `lib/services/sources/eqlist/cwa_eqlist_service.dart`：`_parseCwaItem` | HTTP 行未携带填色输入 | 复用既有 CWA 区域解析，携带原始参数；没有增加网络请求。 |
| `lib/widgets/map/information_event_fill_layer.dart`（新增） | 无独立入口 | 一个普通情报输入构建既有填色组件。JMA／P2P、CWA、CENC、KMA 分别使用原来的模式、透明度、门槛及数字样式；长周期使用原专用组件。 |
| `lib/widgets/map/quake_map_view.dart`：地图展示签名、`_buildUnifiedIntensityLayers` | 手动选择不影响普通填色层 | 支持的手动选择展示该情报的填色，取消选择后恢复原自动层；不支持的类型继续原路径。 |
| 同文件：`_hasPaintedJmaInformationForNiedDots`、手动几何回调 | 只知道自动 JMA 已绘制区域 | 手动 JMA／P2P 实际绘制出区域时延续既有 NIED 小点联动。未触碰其他测站、检出数据和绘制代码；该回调不参与相机拟合。 |

USGS ShakeMap、DYFI 和 CENC 仪器烈度速报继续使用已存在的专用产品层。没有修改这些产品的解析或绘制。没有原始观测区域的数据仍按原有模型路径处理，不将估算结果写回原始报文。

## 预留的渲染接口

调用方可从 `QuakeProvider.selectedInformationMapEvent` 取得只读展示输入，再在自有 FlutterMap 中构建：

```dart
InformationEventFillLayer(
  event: snapshot,
  onInformationGeometry: (regions) {
    // 可选：接收实际绘制的区域。
  },
)
```

图层不依赖 Provider，不接收报文、不启动轮播、不操作相机、不触发声音。后续离屏渲染可复用这个入口；本次未实现图片导出服务。

## 验证

- `test/manual_information_fill_test.dart`：使用未修改的原始报文，在完整 QuakeMapView 中经 `MapStateProvider.selectHistoryEvent` 选中；比较自动、手动、自动情报移除后手动保留、取消并恢复自动时的全部多边形顶点、填色、边线和宽度；检查无新增告警、原始数据未变及对象缓存复用。
- JMA／P2P：95 个多边形；CWA：12 个；CENC：7 个，自动与手动一致。原始 KMA M2.9 报文在自动模式没有达到填色门槛，手动也为 0，没有修改报文来制造填色。
- 同一地图测试检查只有 JMA／P2P 填色启用 NIED 小点；CWA、CENC、KMA 不启用此样式。
- `test/information_map_catalog_test.dart`：实际 JMA／CWA HTTP 服务入口使用原始响应字节，验证列表行和序列化后的原有填色数据。
- 回归覆盖既有信息卡、CWA 多源合并、NIED 自动填色联动及样式、USGS 产品震中图层。
- 最终执行结果：4 个独立完整地图场景通过，HTTP／相关回归 27 项通过，共 31 项。定向分析无 error／warning；既有文件仍有风格 info 提示，没有为此改写其他代码。
- 完整地图测试使用现有 Release Rust DLL；本次未修改 Rust 后端实现。测试截图在 `tmp/manual_information_fill_20261104/render/`，逐次日志在其上级目录。
- 与任务开始时的文件快照比较，仅上述 5 个既有源码文件发生任务改动；`quake_event_adapter.dart` 未修改。新建 2 个源码文件、2 个测试文件和本说明。任务差异在 `tmp/manual_information_fill_20261104/task-only.diff`。

本次完成源码和测试；未编译安装包、未安装运行新 APP、未更新云电脑。
