# 地震信息栏手动地图显示审查（2026-11-10）

## 范围

本次只恢复地震信息栏点击“地图显示”及渲染窗口读取时的既有标题和同事件完整报文复用规则。

- 不改任何上游原始报文、解析字段、目录去重、告警接收、自动轮播、相机规则或填色算法。
- 不把海啸、火山、JMA 长周期、ShakeMap、DYFI 等独立产品塞入普通历史地震的手动选择入口；它们保留各自已有的展示和地图入口。
- 该处属于 Flutter 的列表选择、展示快照和渲染输入，不是后端数据计算；Rust 的同事件渲染匹配调用保持不变。

## 已确认的问题与修复

手动选择历史行后，`InformationMapData.titleText` 曾被用于覆盖所选地震信息卡的标题。这个字段是地图填色/产品快照的标签，不能取代信息栏原有的机构、类别和正式/自动状态标题，因此会把不同来源和类型显示成不正确的统一文案。

修复后：

1. `lib/models/catalog_information_title.dart` 作为唯一的既有标题规则。
2. `QuakeEventAdapter.catalogInfo`、信息栏历史卡和渲染入口共同调用该规则。
3. `QuakeProvider._informationMapView` 只带入填色所需的 `warnArea`、JMA 长周期及 CWA 原始参数，不再写入地图快照的 `titleText` 覆盖已选行。
4. 同事件若已有完整实时/保留情报，手动选择仍复用该完整情报；另一事件不得替换点击行。

## 原始报文矩阵

`test/catalog_manual_display_regression_test.dart` 对每行确认：

1. 信息栏标题等于恢复前的既有标题规则；
2. 手动地图选择和渲染输入标题与卡片一致；
3. 原始 `QuakeMessage` 和输入原始报文不被改写；
4. 同事件复用完整保留报文，不同事件保持独立。

2026-11-10 的目录行矩阵共使用 **270 条原始报文、56 个来源类型**，覆盖：

- JIAN/WHEWS/FAN 的 JMA 目录行，以及 100 条 P2P 原始情报（`DetailScale`、`Destination`、`ScalePrompt`、`Foreign` 四类）;
- CWA 的 TREM HTTP、JIAN、WHEWS/FAN；
- CENC 的 Wolfx、JIAN、烈度速报；
- USGS、FSSN、KMA、HKO、EMSC 及 32 个国际目录来源；
- FUNVISIS 的 WHEWS 原始情报；
- FSSN、CENC、USGS、JMA、F-net、Hi-net AQUA 六类 CMT；其中 JMA CMT 由保存的官方 HTML 直接经过生产解析器进入矩阵；
- 420×850 手机和 1280×850 桌面信息卡实际渲染。

没有保存广西地震局的原始 JIAN 目录报文，因此它不能被标为“原始报文已验证”；映射和标题规则仍存在，但需要获得该源实际报文后再补入矩阵。

不进入本次“手动历史地图”矩阵的来源也逐一归类：JMA、四川、福建、重庆、CWA、CEA/CEA-pr、ShakeAlert、KMA、ICL 是 EEW 管线；NIED 是测站观测流；SASMEX 是检出/预警管线。它们不应被接入普通历史手动地图。它们的原始报文验证分别由 `eew_api_identity_test.dart`、`eew_voice_intensity_alignment_test.dart`、`chinaeew_icl_service_test.dart`、`sasmex_service_test.dart`、`nied_jma_information_display_test.dart` 覆盖。测试同时断言 69 个 `QuakeSourceType` 均已归入原始目录矩阵或上述专用管线；广西是唯一缺少保留原报的普通目录来源。

## 地图与独立产品验证

- 手动地图原始填色：JMA 95 个多边形、CWA 12 个、CENC 7 个均与自动展示一致；KMA 使用的原始 M2.9 报文没有达到现有可画区域的级别，自动和手动均为 0 个多边形。
- JMA 长周期与普通 JMA 震度绑定、USGS ShakeMap、USGS DYFI 的独立入口通过既有产品测试。
- JMA/国际海啸及火山降灰保留独立列表和地图管线，通过相关原始报文回归；它们没有接入普通地震历史的手动地图选择。

## 实际验证

```powershell
$env:RQ_STATION_CORE_LIBRARY=(Resolve-Path native\station_core\target\release\rq_station_core.dll).Path
flutter test --no-pub test\catalog_manual_display_regression_test.dart
flutter test --no-pub --dart-define=MANUAL_FILL_CASE=jma test\manual_information_fill_test.dart
flutter test --no-pub --dart-define=MANUAL_FILL_CASE=cwa test\manual_information_fill_test.dart
flutter test --no-pub --dart-define=MANUAL_FILL_CASE=cenc test\manual_information_fill_test.dart
flutter test --no-pub --dart-define=MANUAL_FILL_CASE=kma test\manual_information_fill_test.dart
```

以上均通过。随后运行目录合并、CMT、ShakeMap/DYFI、JMA/国际海啸、火山降灰的相关回归组，共 **169 项通过**。`flutter analyze` 对本次 3 个新增/修改测试相关文件没有 error；JMA CMT 服务原有 5 条 info 级提示仍存在。

本次没有打包、安装或更新云电脑。
