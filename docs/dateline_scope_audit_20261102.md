# B1 跨日期变更线范围遗漏复核（2026-11-02）

> 后续状态：用户已授权修复，B1 已完成本地源码修复与原始入口验证，见 [连续经度范围修复及 JMA/P2PQ 回归](dateline_geometry_fix_20261102.md)。下文保留修复前的只读审查和保护用途证据，不代表当前仍未修复。

授权目标：用户指定检查原问题列表 B1。本轮只调查、复现和核对影响入口，不修复生产代码，不修改原始报文/几何，不打包、安装、发报或操作云电脑。

## 当前结论

缺陷仍存在。原始 `aka2026tvzrwv` 产品保留连续经度东界 `181.883°`，震中经度 `178.854°`，西界 `176.083°`。这是原始跨线范围，不是震中字段越界或该数据被改写。

实际自动产品入口 `UsgsShakeMapService` 发布 → `QuakeProvider` 原生产产品槽 → `QuakeMapView` → `focusUsgsShakeMap` → `MapStateProvider.smartMoveToPoints`，在桌面和手机各复现一次：3 个关注点（震中、原始西南角、原始东北角）中的东北角未完整进入可用视野，震中仍准确居中。

| 真实地图入口尺寸 | 当前 zoom | 越出可用区域的原始点 | 震中中心误差 |
| --- | --- | --- | --- |
| 1584×850 | 7.151945634130147 | `(53.483, 181.883)`；y=104.87718，可用区域 top=106.22118，上方超出约 1.344px（原测试保留 1px 容差） | 约 1.05e-11px |
| 430×900 | 6.387768599756156 | 同一点；x=395.36268，可用区域 right=380，右侧超出约 15.363px | 约 1.82e-12px |

该条原始产品的等烈度线数组为空，范围点来自既有空轮廓 fallback。因此不能将它描述为已有 MMI 填色被删除，也不能造轮廓把空产品改成非空产品来测试。范围少算与震中偏移是两件事，本次中心检查通过。

## 明确调用链

1. `lib/widgets/map/usgs_shakemap_focus.dart:32` 的 `shakeMapFocusPoints()` 在空轮廓时取原始 south/west、north/east；保留 `181.883`，没有提前改原始经度。
2. `lib/providers/map_state_provider.dart:942` 的 `_calcWrappedPointView()` 先调用 `QuakeCalculator.isUsableMapCoordinate()`，过滤原值超过 ±180 的点。
3. 同文件 `:1060` 的 `_fitPointsAroundAnchor()` 又在 `:1078` 做同样过滤，之后才执行 `WorldWrap.longitudeClosestTo()`、地图投影并生成 offsets。
4. `lib/core/calculator.dart:68` 的校验同时用于真实震中和范围几何，要求 longitude.abs()≤180。范围采用连续经度时被误当成非法震中坐标。
5. Rust `native/station_core/src/camera_focus.rs:102` 的 `fitAnchor` 只收到过滤后的投影 offsets。原始东界没有传到它；当前证据不支持把问题归为 Rust 拟合丢点。

因此不是仅把一处 `longitudeClosestTo()` 调到前面就能证明已修复：另一个范围筛选入口仍存在；也不能将全局震中坐标校验改成允许任意经度，扩大对所有信源的接纳规则。

## 关联入口与边界

| 入口 | 证据与边界 |
| --- | --- |
| 自动 ShakeMap | 原始报文和真实 QuakeMapView 在两个尺寸复现。 |
| 手动历史产品聚焦 | `_focusHistoryProduct()`（quake_map_view.dart:5079）和自动 `_focusAutomaticInfoProduct()`（:5122）复用相同 `focusUsgsShakeMap()`。本轮额外直接运行该生产 helper，复现同一边界遗漏；未声称执行过安装版手动点击。 |
| 多情报共享范围 | `InformationCameraGroups.focus()` 将原始 fitPoints 送同一 smartMoveToPoints，因而有同样输入风险。其视野保留判断还调用下行可见性接口。 |
| 点可见性 | `MapStateProvider.isPointInEventViewport()`（:169）在投影前也按 ±180 拒绝点。在将诊断视口设为宽视野、三个原始点都确实位于可用屏幕内时，181.883° 的点仍返回 false。两种尺寸均实测。它会向共享范围保留判断传入错误的 allVisible=false；本轮没有把这个接口证据扩写成已观察到实际轮播抖动。 |
| 普通 CENC/CWA/JMA、DYFI、火山等范围拟合 | 同一范围接口也被多个类型调用，但只有实际传入连续范围经度时才有此风险；不能据共用函数断言所有信源都失效。 |
| EEW | 当前检查的 EEW 高纬度/波形拟合、普通世界副本定位、JMA 居中、共享组与信息填色几何测试均通过。未改其规则；不宣称覆盖全部 EEW 事件。 |

## 引入时间核对

`git log -S '_fitPointsAroundAnchor'` 定位该函数出现在 `656c343`（2026-09-21）。实际读取该提交、`4032b4e`（10月3日）、`ac247d8`（10月10日）的函数内容，三者均存在“严格坐标校验在世界副本换算之前”的顺序。故此问题在 Rust 相机迁移前已经存在，不能归因于最近的居中恢复、A3 销毁修复或 Rust 计算。提交账号不是实际操作人的独立证据，本轮不据此编造人员归因。

窄范围历史源码及顺序检查保存于 `tmp/dateline_audit_20261102/history-evidence.json`。早期提取脚本曾误将参数列表的 `})` 当函数结束，已纠正为完整独立闭括号边界；最终结论来自完整函数，不使用错误提取结果。

## 测试覆盖缺口

`test/usgs_shakemap_camera_fit_test.dart:107` 只遍历 `frame.contours` 验证轮廓入镜；空轮廓没有点参与循环，因此单靠它不能证明空产品的 fallback 范围完整。现有真实入口用例 `filled_information_runtime_validation_test.dart` 已验证 `shakeMapFocusPoints(frame)` 并明确失败，本轮未删除/放宽这条断言。

## 本轮验证结果与产物

- 原有真实入口：`empty-1584`、`empty-430` **各失败一次**，都为 1 个范围点越出可用视野。每次只运行选定场景，未选择场景跳过，不计为通过。
- 原有 6 文件共 **30 项回归通过**：世界副本定位、EEW 高纬度/波形、JMA 震中居中、信息共享组、填色几何。
- 新增 `test/dateline_scope_audit_test.dart` 两项审查特征测试通过，确认“真实可见但接口拒绝”及直接 helper 同样漏点；通过表示成功复现缺陷，不是缺陷修复。
- 新增测试静态分析无问题。原始 detail/cont_mmi 文件 SHA256 不变；没有转换原始经度再喂回生产流程。
- 本地离屏引擎的真实 APP 地图截图、范围/中心/原生输出计数位于 `tmp/dateline_audit_20261102/runtime/`。图中字体为测试引擎占位字形，不据此报告 APP 字体回归。未验证安装版窗口或云端。
- `visibility-1584.json` / `visibility-430.json` 记录原始点、投影坐标、可用区域、接口返回与直接 helper 拟合结果。
- `file-hashes.json` 记录相关源码和原始样本指纹，`related-regressions.log`、`visibility-audit.log`、`empty-*.log` 保存本次结果。

本次新增 1 个测试文件及本文，并在问题清单补充复核链接。生产文件保持不变；B1 仍标记为未修复。

## 继续核对：为什么原来这样写，是特殊规则还是 bug

用户进一步要求追查原校验的用途。本次补查提交差异、现有测试、USGS 解析和绘制代码后，结论分两层：**全局震中坐标校验本身有明确保护目的；把它直接用于连续经度范围是适配 bug。**

### 有依据、应保留的原处理

- `1963af9`（2026-09-05）新增 `QuakeCalculator.isUsableMapCoordinate()`，注释明确接受真实 `(0,0)` 震中，拒绝非有限数、纬度超过 ±90、经度超过 ±180；同次将事件筛选原来“非 (0,0)”判断替换为该函数。现有 `test/calculator_test.dart` 也明确断言 NaN/Infinity、91°纬度和181°震中经度必须拒绝。因此不能为跨线几何直接删除或放宽全局校验。
- 同次新增的 `isLikelyUninitializedCoordinate()` 把 Kotoho7 暂未赋值的 `(0,0)` 占位判断单独隔开，注释限定用于未可信/未完整源字段；它与允许真实零经纬度并不冲突。B1 不涉及改变这一判断。
- `6d0e89f`（2026-09-17）新增 `isPointInEventViewport()`，会用尚未完成的动画目标相机判断点是否可见；当前普通事件选择/卡片仍使用该入口。这个“按目标相机判断，避免重复争抢/重启视角”的行为不应随 B1 改动。
- `656c343`（2026-09-21）新增 `_fitPointsAroundAnchor()`，提交说明明确包含“center CENC intensity reports”；代码明确保留震中居中，由较远一侧决定缩放，另有 viewportPadding、旋转和世界副本反投影。这些都是应保留的处理，不能以跨线修复为理由改成范围中点居中。
- `WorldWrap.longitudeClosestTo()` / `unprojectUnwrapped()` 是处理最近世界副本及跨线反投影的独立路径，并非要求抛弃原始连续经度。`longitudeClosestTo()` 的循环要求先排除非有限输入；不能单纯删掉前面的全部校验。

以上用途基于实际提交、注释、调用方和现有断言，不将提交标题推断成一条未找到原文的用户要求。

### 为什么当前范围入口可以判定为 bug

1. 同一 `1963af9` 还把 `isUsableMapCoordinate()` 加进 `_calcWrappedPointView()`，把“震中有效范围”和“已经展开的几何经度”混用；9月21日固定锚点拟合又沿用这一筛选。因此误用并非最近才由 Rust 新增。
2. `UsgsShakeMapProduct.fromDetail()`（`lib/models/usgs_shakemap.dart:54` 起）要求 south/north/west/east 有限、纬度合法、east>west、范围宽度不超过360；它没有要求 east≤180，当前原始 181.883° 产品正是合法进入这条路径。
3. 同文件 `UsgsMmiContour.parse()` 明确允许原始线坐标经度绝对值≤360；不会把所有超过180的坐标都当作坏数据。
4. `UsgsMmiContourPainter.projectLine()`（`lib/widgets/map/usgs_shakemap_layer.dart:164` 起）注释明确只在投影时选择世界副本、保持 USGS 原坐标不变；连续点逐点展开。`hasVisibleContour()` 也对原始产品四角整体选择世界副本，支持跨线范围。
5. `shakeMapFocusPoints()` 把解析器已接受的原始界限直接交给范围拟合，后续没有一条专门“超180产品边界不计入缩放”的分支。实际丢点发生于通用震中校验，比专门的跨线投影更早，导致产品适配/绘制允许的原始几何被相机排除。

因此应保留真实震中接纳规则、有限值检查、零坐标/占位区别、动画目标视野、原震中锚点、旋转、边距及世界副本规则；B1 的后续修复只能针对**范围几何的合法性及可见性入口与产品支持范围不一致**，不可全局放宽坐标接纳，也不可改写原始报文或先改经度再当原始数据处理。

### 本次补查验证

- 原有 `test/calculator_test.dart` 与 `test/usgs_shakemap_test.dart` 共 **22 项通过**，未修改测试或生产代码。涵盖全局坐标保护、真实零经纬度、原始产品/线样式与坐标、空轮廓状态、产品取消/版本和门限等既有行为。
- 提交原差异保存于 `tmp/dateline_audit_20261102/{1963af9,6d0e89f,656c343}-coordinate-history.diff`；补查日志 `guard-and-product-regressions.log`。
- 没有新的生产改动、打包或云端操作。上文两次真实入口范围失败仍是未修复状态。
