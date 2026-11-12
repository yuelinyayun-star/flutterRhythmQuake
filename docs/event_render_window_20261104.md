# 渲染事件窗口与本轮修复（2026-11-04）

## 本轮范围

修复审查列出的五项问题，并完成用户追加的上游区域分布、文字描边、底图切换、保存 PNG、CENC 烈度速报选择、统一 UI 标题修正。既有自动／手动主地图、EEW、测站样式、事件合并及轮播规则不在本轮改写范围。

## 入口与接口

- `lib/widgets/ui/eqlist_panel.dart` 的 `_EqCardState._renderEvent()`：捕获所点列表事件，打开应用内 `EventRenderPage`；主地图选中项保持不变。
- `QuakeProvider.informationMapEventFor()`：复用既有快照与匹配逻辑。
- 新增 `matchesInformationRenderEvent()`：调用既有 Rust `sameInfo`，不按名称猜测同一事件。
- 新增 `informationRenderCencIrBinding()`：调用 Rust `renderCencIrIndex`，保留既有 CENC-IR 匹配契约：明确 ID 或发震时间差不超过 1 秒且坐标差不超过 0.011°；即使 ID 相同，矛盾的时间／坐标仍拒绝；多份匹配时采用最新 `gmtCreate`。
- `retainedInformationRenderCencIr()`：只读复用当前已留存的匹配仪器烈度产品，不变更主界面的产品选择。
- `lib/services/render_information_loader.dart`：窗口独立 HTTP 客户端，只读加载所选事件的原始上游资料；关闭窗口时关闭客户端。
  - JMA／P2P 缺少实测区域时，读取 P2P `v2/history?codes=551&limit=100`，使用现有适配器与 Rust 身份匹配。
  - CWA 缺少实测区域时，读取既有 ExpTech `api/v2/eq/report/{id}` 详情入口并核对事件。
  - CENC 未留存仪器产品时，读取 NowQuake `/list?pageNo=0&pageSize=20`，匹配后读取 `/event/{id}`，再次核对详情身份。
  - 已留存的 FAN 产品可复用；本轮没有新增 FAN 网络订阅。
  - 没有匹配到上游区域时不编造区域分布。原有地图预估填色仍属于预估，不能进入实测地区列表。

## 窗口、底图与保存

- 画布固定 `1600×900`，预览由 `FittedBox` 等比适配；导出不含工具栏或应用窗口边框。
- `EventRenderLayoutMode.splitFloating`：左地图 `1012×834`，右侧栏宽 492，间隔 24。
- `EventRenderLayoutMode.fullMapFloating`：地图 `1528×834`，右侧栏内悬浮，左右无遮挡区域的震中锚点保持原规则。
- 两种模式外边距均为左 36、上 32、右 36、下 34；全幅的遮挡补偿仍为 258 像素。有效左侧区域震中为 `(506,417)`。
- 侧栏沿用当前设置材质：圆角 14、模糊 14、`SettingsControlStyle.panel` 和边线；没有为匹配旧文档改写已确认样式。
- 水印沿用 `RhythmQuake绘制`，字号 15、`Colors.white38`，右 36、下 7。
- 工具栏增加本窗口底图选择，复用 `MapConfig.baseTileOptions`。不写主地图设置、不改变事件视角。切换底图时用稳定 key 保留情报填色层，避免重建时暂退默认缩放。
- CENC 工具栏增加“地震情报／烈度速报”选择。速报存在才允许选择；复用 `CencIrLayer` 的原测站与实测填色。
- “保存图片”调用 `event_render_export.dart`：系统保存对话框、事件名称文件名、PNG。保存前等待矢量底图或当前栅格瓦片完成；失败明确提示，不导出加载失败的空白底图。编码后的 `ui.Image` 在 `finally` 释放。
- 窄窗口工具栏自动换行，保留桌面与 390 像素窄屏支持。

## 侧栏与分布

- 前四排复用 `UnifiedEventPresentation`：标题、震中、震级／深度、时间。
- CENC 普通情报统一完整标题“中国地震台网地震信息”；统一 UI 和成图不再把原始 `reviewed` 状态拼入非 EEW 标题。原始数据不修改，中文测定标签、其他报次、JMA 取消／订正和 EEW 标题规则保留。
- JMA 最大震度使用实际震度；生产 LPGM 的最大震度取 `bulletin.maxInt`，阶级取 `maxLgInt`，不再把阶级当作震度。
- 第五排及分布等级仍为下半部地图填色条。描边改成与前景共享字体、字重、缩放、locale、宽高基准的 `RichText`，消除不同布局方式导致的偏移。
- 分布严格要求 `fillSummary.isObserved && groups.isNotEmpty`。预估或没有实测分组时按钮置灰，不显示预估地区名单。
- 地图汇总真实接口名为 `PaintedRegionDetail`、`PaintedRegionGroup`、`InformationFillSummary`、`onInformationFillSummary`。此前文档的 `PaintedRegionItem`、`onInformationSummary`、`RenderPosterLayoutMode` 已纠正。
- 主地图没有汇总订阅者时，不构造地区文案、排序、分组和图例。原多边形、颜色、透明度及几何回调保持不变。
- 窗口销毁释放自己创建的外部 `MapController`；测试确认地图事件流随页面销毁关闭。

## 具体改动位置和前后行为

| 文件 | 位置 | 原行为 → 本轮行为 |
| --- | --- | --- |
| `lib/models/unified_event_presentation.dart` | `_displayTitle` | 直接拼标题与 reviewed、可能采用“正式测定”作完整标题 → CENC 完整标题，非 EEW 去除多余 reviewed，保留原始元数据与其他显示规则 |
| `lib/widgets/ui/event_render_page.dart` | `_loadSources`、`_selectProduct`、`_buildModeSwitcher`、`_buildFlutterMap`、`_saveImage`、`dispose` | 只读目录快照、固定底图、无导出、控制器未释放 → 独立补充原始实测资料、速报选择、窗口底图、PNG 保存及资源释放 |
| 同上 | `_lpgmShindoValue`、`_buildHalfFillBadge` | 阶级优先、独立 Painter 文字布局 → 实际震度优先、同布局描边 |
| `lib/widgets/ui/event_render_export.dart`（新） | 两个导出函数 | 新增固定画布截图、保存与图像释放 |
| `lib/services/render_information_loader.dart`（新） | `observed`、`cencIr`、`close` | 新增仅供渲染窗口的上游读取，不接收进主事件流 |
| `lib/providers/quake_provider.dart` | 三个渲染查询方法 | 只增只读匹配／留存产品接口，不改接收、合并、选择或轮播 |
| `lib/widgets/ui/eqlist_panel.dart` | `_renderEvent` | 仅传快照 → 同时传只读查询与可复用产品 |
| `lib/widgets/map/cenc_ir_layer.dart` | 可选汇总／几何回调 | 原填色与测站不变，额外允许渲染窗口订阅 |
| `lib/widgets/map/intensity_fill_layer.dart` | 汇总构造与样式缓存键 | 无条件构造汇总 → 有订阅者才构造 |
| `lib/widgets/map/jma_lpgm_region_fill_layer.dart` | 汇总构造与发布键 | 无条件构造汇总 → 有订阅者才构造 |
| `lib/services/native_unified_event_owner_io.dart`、`_stub.dart` | `query(parameters:)` | 新增可选参数，保留调用者所有权与释放；op／事件参数不能被覆盖 |
| `native/station_core/src/unified_event_policy.rs` | `render_cenc_ir_index` | 新增窗口专用匹配，保留原绑定条件与墙钟语义 |
| `native/station_core/src/unified_event_state.rs` | 查询分派 | 只增 `renderCencIrIndex` 分支 |
| `test/event_render_fixes_test.dart`、`test/render_information_binding_test.dart` | 新测试 | 原报文、生产 Rust 调用、导出、描边、隔离、释放、底图切换不改视角 |
| `test/unified_event_presentation_test.dart` | 新标题测试 | 验证完整标题、状态不改、其他报次／EEW／JMA 取消订正保留 |
| `test/event_render_page_test.dart` | 既有日文震度标签期望 | `5弱` → 用户已确认的 `5-`，没有删除既有视角／布局断言 |

## 原始数据与实际验证

原始响应及 SHA256 在 `test/fixtures/event_render_20261104/`，正文按响应字节保存，未改报文、时间、震级、坐标或强度来通过测试。

- 熊本事件：2026-11-04 07:28:00 JST，M2.5。Wolfx 原目录缺少区域，匹配的 P2P 原报文只有一个震度 1 测站；渲染采用该上游观测区域，不再把模型的震度 2 当实测。
- 吉尔吉斯斯坦事件：2026-11-04 05:34:08 UTC+8，M5.0。NowQuake 原详情有 32 站，最大仪器烈度 4.2；可切换产品并显示实际测站、实测填色与分布。
- 46 项相关回归通过：成图旧测试、新原报文测试、Rust 绑定对照、历史手动选择、列表、CENC-IR、NIED 与 JMA 填色联动、LPGM、CWA 来源适配。
- 3 项标题测试通过：完整标题和 reviewed、JMA 报次／取消／订正、原中文测定标签。
- 原始主地图四组验证通过：JMA 95、CWA 12、CENC 7 个多边形自动／手动一致；KMA 原样例保持 0 个。无汇总订阅时 `_buildSummary` 覆盖命中为 0。
- 实际保存按钮已写出并解码核对 1600×900 PNG；描边与前景的尺寸、全局位置及字形选择框完全一致；移除页面后地图事件流关闭。
- 原始资料绑定遍历整个目录与速报列表，Rust 和既有 CENC-IR 绑定结果一致，包含匹配和拒绝样本；查询后保留视图数为 0。
- 静态分析没有 error／warning；仍有本仓库及新增代码的样式 info，不作为运行验收替代。
- 单独运行整个 `unified_event_presentation_test.dart` 另发现既有零烈度测试预期 `0`、当前 `unifiedRomanIntensityLabel(0)` 实际为 `I`。该函数未在本轮改动，标题输出不参与烈度计算；按精确范围约束记录，未顺带修改阈值或烈度逻辑。

证据：`tmp/event_render_fixes_20261104/` 的日志、成图、覆盖记录和任务前后差异。栅格选择组件测试核对 URL 与状态隔离，不把测试框架禁止外网时的 HTTP 400 视为在线瓦片验收。

## 打包与云电脑

用户已授权本地完成后编译并更新云电脑。此段最终结果以本轮 `package.log` 与部署、运行核验记录为准；源码、组件测试、打包、安装和真实桌面验证分别记录，不互相替代。现有云电脑配置和数据保留，不创建整套应用备份。


### 最终交付核验（2026-11-05 00:01 UTC+8）

- Windows Release 与安装包均已完成：`build/installer/RhythmQuake_Setup_1.0.5.22_personal_x64.exe`，41,659,104 字节（39.73 MiB）。安装包 SHA256：`e046bda7ab5ea8af4d67aa3e415ad04ecbe35d37157941acbbba59e1679e6911`。
- 经现有认证 MCP 更新 `DESKTOP-VUEC9GQ` 的 `E:\RhythmQuake`。只替换差异程序 `data/app.so`、`rq_station_core.dll`；完整清单 141 个文件全部核验，未创建应用备份。
- 已重新启动 APP，PID 13080，窗口 `RhythmQuake`，`Responding=true`。
- 云端实际从地震列表打开成图窗口，切换 Petal 浅色在线底图，地图正常加载、震中位置保持；无实测分布的普通 SSN 事件按钮为禁用状态。
- 云端实际点击保存，经 Windows 保存对话框写入 `E:\RhythmQuake\event-render-check-20261104-235955.png`。文件已取回解码，尺寸 1600×900，947,969 字节，SHA256 `ce504400cb205ec24392d41d4f026bf4d7328dc409a81dc69613f8aabb8a1e30`。
- 已退出成图返回主界面；本轮检查中短暂操作的列表 CENC 筛选已恢复，主底图与原配置保留。测试用底图选择只在成图窗口内生效。
- CENC 32 站原报文与 JMA 实测区域的完整成图在本地组件／原生 Rust 路径验证；云端本次界面验收使用其当前 SSN 列表事件，不混称为云端已经重测所有信源。


---

## 画布比例切换支持（16:9 与 4:3，2026-11-05）

- **比例枚举与画布规格（`EventRenderAspectRatio`）**：
  - `ratio16x9`（默认）：画布 `1600×900`；全幅地图面板 `1528×834`（无遮挡左侧可视区震中居中于 `(506, 417)`），分栏地图面板 `1012×834`（震中居中于 `(506, 417)`）。
  - `ratio4x3`：画布 `1600×1200`（保持画布宽度 `1600`、右侧信息栏宽度 `492` 及四周边距不变，纵向增高至 `1200`）；全幅地图面板 `1528×1134`（无遮挡左侧可视区震中居中于 `(506, 567)`），分栏地图面板 `1012×1134`（震中居中于 `(506, 567)`）。
- **工具栏切换入口**：
  - 在 `_buildModeSwitcher()` 新增 `16:9`（`ValueKey('render_aspect_16_9')`）与 `4:3`（`ValueKey('render_aspect_4_3')`）切换按钮。
  - 切换比例后下一帧自动调用 `_fitMapCamera()` 按新画布高度重算相机缩放与偏移，保持震中锚点在无遮挡地图可视区严格居中；右侧栏下半区分布列表通过 `Expanded` + `LayoutBuilder` 自动利用纵向新增的 `300px` 空间容纳更多实测地区。
- **验证结果**：
  - `test/event_render_page_test.dart` 与 `test/event_render_fixes_test.dart` 共 7 项测试全部通过，覆盖 `16:9`（`1600×900`）与 `4:3`（`1600×1200`）在全幅悬浮／分栏悬浮两种模式下的画布尺寸、震中居中坐标及实际导出 PNG 尺寸核验。
  - **Windows Release 与安装包编译**：已执行 `package_windows.ps1 -Edition personal -SkipProcessCleanup` 完成 Release 构建与 Inno Setup 安装包编译：
    - 产物路径：`build/installer/RhythmQuake_Setup_1.0.5.22_personal_x64.exe`
    - 大小：`41,663,263` 字节（`39.73 MB`）
    - SHA256：`5a6bb20a53d5d7511205365d65d3d22e55a85c2147dac1562a12100dca1e512d`
    - 清单：[`build/windows/x64/runner/Release/release_manifest.json`](../build/windows/x64/runner/Release/release_manifest.json)（141 个载荷文件）
