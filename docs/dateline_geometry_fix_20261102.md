# B1 连续经度范围修复与 JMA/P2PQ 回归（2026-11-02）

## 授权和不变约束

用户授权修复 B1，并要求重点验证此前为 JMA/P2PQ 情报绘制处理而加入的逻辑，以及可能共用该入口的其它产品。范围限定为连续经度几何被误过滤、相应范围拟合与可见性判断；保留真实震中接纳、原始报文、绘制数据、配色、震中锚点、各类情报独立规则和共享视野稳定性。

用户随后明确 APP 不能旋转地图。已实查生产 `QuakeMapView`：initialRotation=0、手势 flags 排除 rotate、cursorKeyboardRotationOptions.disabled、enableQERotating=false；没有找到生产主动旋转调用。**本次不改旋转设置或旋转算法。**

## 精确生产改动

| 文件和入口 | 原行为 | 新行为及保留约束 |
| --- | --- | --- |
| `native/station_core/src/camera_focus.rs:21`，`prepare_geometry`；`:253`，`rq_camera_geometry_prepare` | 没有独立范围坐标策略；Dart 共用震中校验删点并自行计算圆周最小经度范围 | 新 Rust 接口借用原始 float64 经纬度对；筛掉非有限数和非法纬度，允许有限连续经度，返回原始有效索引和最小圆周范围。原输入不改写。原有所有 execute 操作（JMA 锚点选择、EEW、共享保留、固定锚点拟合等）逐字保持本轮修改前内容。 |
| `native/station_core/include/rq_station_core.h` | 无该接口 | 补充新接口、最大 2M 点、借用输入及沿用 rq_camera_focus_free 释放输出的契约。未改变旧函数签名。 |
| `lib/services/native_camera_focus_io.dart:15`，`prepareGeometry` | 无原始双精度批量入口 | 将原始 float64（包括测试里的 NaN/Inf 原值）复制进 FFI 输入，生产支持平台直接调用 Rust，finally 释放输出。没有先替换非法值、改原始经度或失败退回 Dart。 |
| `lib/services/native_camera_focus_portable.dart:11` | 无对应兼容入口 | 非原生平台保留现有兼容架构，并实现等价范围契约；支持原生平台失败时不走该实现。 |
| `lib/widgets/map/range_camera_geometry.dart:7`（新增 UI 适配） | 无范围类型区分 | 只打包原始坐标并按 Rust 返回索引保留原始 LatLng 对象；地图投影仍由 Flutter 执行，不改上游数据。 |
| `lib/providers/map_state_provider.dart`，`smartMoveToPoints()`、`_fitPointsAroundAnchor()` | `_calcWrappedPointView()` 与固定锚点拟合分别按震中 ±180 条件过滤；Dart 自算圆周范围 | 范围筛选和圆周范围计算改走 Rust；UI 使用有效原始点投影，不再重复用震中规则删点。固定锚点、padding、缩放上下限、动画、节流和手动暂停规则保留。原 `_calcWrappedPointView()` 的相关后端实现移除。 |
| 同文件，新增 `areGeometryPointsInEventViewport()` | 点可见性只有严格震中入口，连续经度点即使已在屏内也返回 false | 范围整体由 Rust 验证，再按原目标相机、世界副本和像素边界投影判断。任一非法点仍不宣称全部可见。**原 isPointInEventViewport() 与修改前逐字一致**，事件/卡片继续严格检查，且未增加单事件列表分配。 |
| `lib/widgets/map/information_camera_group.dart:137` | 共享组把范围顶点逐个送进震中可见性接口 | 改用一次范围批量可见性判断；原 1px 容差、共同成员、同 viewport、轮播不重拟合等规则不改。 |
| `lib/widgets/map/usgs_dyfi_focus.dart:94`，缩略图固定震中拟合 | 同类严格范围过滤，且仍在 Dart 重复计算固定锚点缩放 | 范围验证走同一 Rust 接口，固定锚点缩放走已有 Rust fitAnchor；Flutter 保留原投影。DYFI 的 10px 最小网格边长、zoom=12 上限、边距、缩略图不画震中规则不变。 |

共修改 7 个已有生产文件，新增 1 个 UI 适配文件。没有修改 `QuakeCalculator`、JMA 情报区域选取、informationFocusAnchor、QuakeMapView 的业务/绘制/交互代码；A3 已完成的回放修复也未再修改。

## 实际根因闭环

使用同一原始 Alaska `aka2026tvzrwv` 产品；震中 178.854°、西界176.083°、东界181.883°，等烈度线仍为空。没有补造轮廓、改经度或替换成另一事件。

| 实际 QuakeMapView | 修复前 | 修复后 |
| --- | --- | --- |
| 桌面 1584×850 | 3 个关注点中东北角越出可用范围，zoom=7.151945634130147 | 3/3 均在可用范围，zoom=7.145374208459333，震中误差约4.12e-12px |
| 手机 430×900 | 同一点越出可用范围，zoom=6.387768599756156 | 3/3 均在可用范围，zoom=6.259333732442196，震中误差0px |
| 宽诊断视口内的原始181.883°点 | 严格点接口返回false | 范围接口返回true；严格震中接口仍false，原保护没有被放宽 |

原始两文件 SHA256 与之前只读审查相同：detail `a5f0100c555c236b5b1c1a04ff37a3297c32075104b92a762cbcbd2f4d60bf6b`；cont_mmi `af614350604dcbd852ebcdedab073053b173855669d2b81585279f149532a24d`。

## JMA/P2PQ 和共用入口验证

所有实际入口均运行在本地离屏 Flutter 引擎，使用当前真实 Release DLL；JMA/CWA 等报文经过回环 HTTP → 生产适配 → Rust Provider → 实际 QuakeMapView，USGS 产品使用原始归档在生产产品服务槽发布。没有向用户运行中的 APP 或云电脑注入警报，不占用桌面。

22 个独立实际入口场景全部通过，未选中的矩阵成员跳过，不计入通过数量：

| 类型 | 覆盖及结果 |
| --- | --- |
| JMA/P2PQ | 桌面/手机原始 ScalePrompt → Destination → DetailScale，6个阶段检查通过。前两种保留原区域规则；详细情报固定震中；区域点均在可用范围内。另有原始 Nemuro、日向滩、测站区域合并、当前事件、原生类型契约等回归。 |
| USGS ShakeMap | 原始非空等烈度线和本次空轮廓跨线产品，两尺寸实际入口通过；原等烈度线/原始边界不改。 |
| USGS DYFI | 普通原始网格和 Kenai 原始71格，桌面/手机自动与手动入口通过；已有三事件×三尺寸及缩略图检查通过，网格最小像素和中心约束保留。 |
| CENC/CWA | CENC、CWA 实际模型填色和 CWA 观测填色，两尺寸完整范围/中心检查通过；CENC 原始三事件多尺寸测站、填色与共享回归保留。 |
| 共享视野 | 实际多情报8次轮播、范围内新增原始报告不移动，地图事件为0，中心/缩放不变；真正范围外的新情报仍重新拟合。另用原始跨线几何检查共享组轮播与受控卡片身份新增，同样保持视野，未虚构上游报文。 |
| EEW | 原始 GQ Jan Mayen/Flores 两尺寸实际入口通过，原高纬度、波圈跟随、普通世界副本定位回归通过；EEW 未继承信息填色规则。 |
| 火山 | 原始降灰六个时间窗的范围/过期及绘制测试通过；未把火山改成固定地震震中规则。 |

实际入口同时核验生产地图初始角度为0、rotate手势禁用、Q/E旋转禁用；JMA 两个尺寸在最终源码上再次完成三个阶段验证。

## 测试、所有权和边界

- Rust 全库 **165 项通过**，包含9项camera_focus测试；不重复把子集加进总数。
- Flutter 首批5文件24项通过；相关18文件90项通过；独立实际入口22个全部通过。合计 **136 个受支持场景测试通过**；重跑和每个场景里的多阶段测量不重复累计。
- 原有正常经度范围数学与冻结旧实现完全一致。真实 Rust 调用计数增加、重复300次输出释放计数为0；原始 float64 字节不变，NaN/Inf没有先被Dart替换再传入。
- 原始震中坐标保护及零坐标/未初始化占位区分保留；JMA区域选取和锚点规则、全部既有Rust相机 execute 操作与修改前一致。原始数据、样式和现有断言未为过测而放宽。
- 新增 `test/native_camera_geometry_test.dart`、`test/dateline_shared_camera_test.dart`；`test/dateline_scope_audit_test.dart` 由缺陷审查转换为修复回归，仍断言原震中接口拒绝越界坐标。
- `test/filled_information_runtime_validation_test.dart` 保留所有范围/中心断言，新增实际禁旋转约束；自动产品震中定位器更新为此前已批准复用的 QuakeWaveLayer，仍要求恰好一个，手动入口继续检查 HistoryMarkerLayer。没有为本次更换生产震中样式或渲染层。
- 最初额外强制开启20°旋转的2个新测试未通过；冻结原算法和当前结果相同。用户澄清APP不能旋转，生产设置也证实如此，因此纠正了“额外APP问题”的判断：它不是当前可操作入口的回归。诊断源码、断言和失败日志单独保留于 `unsupported-rotation-audit.dart.txt`、`shared-rotation-baseline.log`，未修改旋转算法来扩大范围，也未把该诊断算为通过用例。
- 静态分析针对本次生产/测试文件无错误、警告；最新最终检查见 `analyze-final.log`。

证据目录 `tmp/dateline_fix_20261102/`：`runtime-progress.json`、`runtime/`的原始入口阶段JSON/PNG、`core-regressions.log`、`related-supported-final.log`、`rust-all.log`、`preserved-contracts.json`、`before-sha256.json`及精确增量diff。截图使用测试字体/隔离外部瓦片，检查地图几何与生产层，不当作安装版字体/联网验收。

新 DLL SHA256：`0ee43e58905528aef248c5ebf0d91ca59e4d7b7bec3605886565d9fc9fbc7832`。仅本地构建原生库用于实际 FFI 验证；**尚未编译新 APP 安装包、安装或更新云电脑。**
