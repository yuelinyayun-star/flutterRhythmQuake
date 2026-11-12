# DYFI 主地图震中与网格核查（2026-11-01）

## 范围和责任

用户报告的是主地图震中标记及 DYFI 网格缺失，不是底图故障。此次恢复 DYFI 自动显示和手动选择的原有震中绘制，补齐此事件真实网格格式；不修改情报视角策略、轮播、缩略图无震中设计、颜色或网格绘制样式，不修改 ShakeMap MMI 解析和绘制。

## 历史证据

实际执行者为此会话中的 Codex，记录模型 `gpt-6.1-sol`。不能把工作区的未提交修改归给 Git HEAD 作者。

北京时间：

1. **10月10日16:25:54**，首次新增 `lib/models/usgs_dyfi.dart` 的工具调用 `call_ed19902011394a7ab6ee1acd776071f8`，只读取 `dyfi_geo_10km.geojson` 和 `dyfi_geo_1km.geojson`，没有 KMZ。此事件的 KMZ 属于初始接入遗漏，不是已证实的 KMZ 支持删除。
2. **10月10日16:32:20**，调用 `call_02fcf6ee162b4921b66e4101301e6b2c` 在主地图独立产品层添加 DYFI 震中，同时避免与同事件 ShakeMap 重复画震中。原来存在可绘制的实现。
3. **10月15日14:01:56**，调用 `call_e5c3d334d2c1453183b2d9df36d0376b` 把 DYFI / ShakeMap 排除出普通统一情报震中层。
4. **10月15日14:03:34** 的删除尝试 `call_dd7f9837ef5d4be9bbeb7165e5130bdb` 因补丁上下文不匹配失败，不能算生效修改。
5. **10月15日14:03:59**，成功调用 `call_b3812e6b7ac94fc29db8b0216030aa43` 删除独立 DYFI 震中，并使手动选中 DYFI 的产品震中分支直接返回空组件。与第3项一起造成自动和手动 DYFI 都没有震中。

当时用户要求：“看看DYFI我发现他已就不符合信息的显示规范，依旧强视野，其他信息轮播也不轮了，新信息来时的聚焦也被吃了”。该要求没有授权删除主地图震中。Codex 在修复视角/轮播时扩大了范围，验证也没有保留主地图震中可见性检查。这是修改及验证失误。

工具记录位于本仓库 `tmp/dyfi_missing_20261101/marker-attribution.json`、`grid-attribution.json`，保留来源会话文件、行号、时间、调用ID和实际补丁。

## 错误影响范围

- 已确认：DYFI 自动情报入口，独立震中被删除，普通层又跳过 DYFI，导致漏画。
- 已确认：手动选择 DYFI 入口的提前返回同样隐藏震中。
- 已确认：没有上述两种 GeoJSON、但提供 `dyfi_geo.kmz` 的 DYFI 产品会被旧适配当成没有网格；不止本事件会遇到。
- ShakeMap：普通层同样跳过，但独立 ShakeMap 震中仍存在；本次没有删除或更改它。MMI 数据源、解析器及画笔与 DYFI 独立。
- 缩略图：既有无震中设计保留，不在主地图震中恢复范围。
- 其他情报和 EEW：本次未改视角、测站、填色、阈值或轮播逻辑。

## 本次具体修改

| 位置 | 原行为 → 新行为 | 涉及功能 |
| --- | --- | --- |
| `lib/widgets/map/quake_map_view.dart` 产品震中 selector | 手动 DYFI 返回空组件、独立层只画 ShakeMap → 恢复 DYFI 原有 `HistoryMarkerLayer`，保留同事件去重 | DYFI 主地图自动/手动震中 |
| `lib/models/usgs_dyfi.dart` 的 `fromDetail`、`gridFormat`、`withGridResolution` | 只认识两种 GeoJSON → 保持原优先级，额外识别原产品 KMZ；记录真实格式和网格分辨率 | DYFI 产品文件选择 |
| `lib/services/sources/usgs_dyfi_service.dart` 的 `_fetch` 网格下载分支 | 只按 JSON 下载 → KMZ 原始 `bodyBytes` 交给 Rust，原 GeoJSON 路径保留 | DYFI 原始网格加载 |
| `native/station_core/src/dyfi_grid.rs` | 新增文件选择、原 KMZ/KML 多边形和观测字段读取、FFI 释放 | Rust 原生数据处理 |
| `native/station_core/src/tsunami_regions.rs` 的 `kml_from_zip` | 仅将可见性改为 `pub(crate)`，函数体不变 | 复用既有有界 ZIP 解包及 CRC 校验 |
| `native/station_core/src/lib.rs`、`native/station_core/CMakeLists.txt` | 注册新模块和构建依赖 | 原生构建 |
| `lib/services/native_dyfi_grid*.dart` | 新增 FFI，KMZ 解码在 isolate 调用；原生平台不静默回退 Dart | Flutter 与 Rust 接口；不支持原生的平台使用显式兼容实现 |
| `test/usgs_dyfi_kmz_test.dart`、原始 fixture | 原服务调用实际 Rust DLL，验证71个原网格及分配释放 | 原始数据回归 |
| `test/filled_information_runtime_validation_test.dart` | 新增桌面/手机 DYFI 原事件自动/手动绘制检查，强化 ShakeMap MMI 和震中检查 | 主地图实际生产组件离屏渲染 |
| `AGENTS.md` | 新增精确修改、含糊范围先征得同意、逐项交付说明 | 项目指令 |

## 验证边界

使用新 Release Rust DLL 的实际 FFI，不使用旧 Dart 后端替代结果；原始文件 SHA-256 保持不变。

- DYFI 模型、服务、UI、视角、轮播、共视野和 ShakeMap provider：49 项通过，`regressions.log`。
- ShakeMap 原始 MMI、三个事件的桌面/中等窗口/手机视角、图例：32 项通过，`shakemap-regressions.log`。
- 原始 KMZ Rust 解码及文件优先级：2 项通过，`rust-tests.log`；复用解包模块的既有回归19项通过，`rust-zip-regressions.log`。
- Kenai 主地图两个尺寸自动/手动入口：均显示1个震中，读入71个原始网格。桌面视野可见25个网格；按既有“网格可读性”缩放优先级，不承诺同屏显示全部远端网格。自动震中定位误差小于1像素。日志 `dyfi-kenai-1584.log` / `dyfi-kenai-430.log`。
- ShakeMap 主地图两个尺寸：检查真实 `UsgsMmiContourPainter`、原始frame身份、可见MMI轮廓及1个震中，离屏截图人工检查均可见。日志 `shakemap-1584.log` / `shakemap-430.log`。
- 共享情报视野两个尺寸：8次轮播及范围内新报均为0次地图移动，中心和缩放不变。见 `runtime/shared-stability-1584.json` / `shared-stability-430.json`。

已通过的结果和截图详见 `tmp/dyfi_missing_20261101/`。离屏 Flutter 引擎运行生产地图组件，不操作用户桌面。测试环境瓦片 HTTP 返回400、使用测试字体，因此截图用于检查震中和产品图层，不作为完整安装版底图与文字验收。没有打包、安装或替换正在运行的 APP。
