# NIED 检出原始帧核查（2026-11-02）

本次授权范围：按截图时间向前获取原始 GIF，测试检出。没有修改生产采样、检出、阈值、颜色、透明度或地图行为，也没有向运行中的 APP 发报。

## 时间与输入

- 截图主时钟 2026-11-02 10:18:27 UTC+8，对应 11:18:27 JST；截图 NIED 数据时间为 11:18:26 JST。
- 采集窗口 11:16:00—11:19:00 JST，每秒地表 jma_s、地中 jma_b 各一张。Lmoni 和 Kmoni 各 362 张，共 724 张，均成功下载、验证 GIF 签名并保存 SHA256。
- 两个端点同名同时间 GIF 并不完全相同，不能将 Kmoni 结果当成 Lmoni 结果。主数据源 Lmoni 使用 `https://www.lmoni.bosai.go.jp/img_svr`，对照 Kmoni 使用 `http://www.kmoni.bosai.go.jp`。
- 原始 GIF 没有改值、补帧、改时间。历史真实 receivedAt 不可得，在清单中保留 null；测试注入的 receivedAt 是本次测试实际接收时刻，绝不称为历史接收时间。所有事件时间从清单含 +09:00 的原始 observedAt 解析。
- jma_b 只留存核查，不混入当前地表采样路径。

## 已验证结果

1. 当前 Rust KA 历史和 Rust 检出 owner，用原始时间差推进显式生命周期时钟，三档灵敏度均复现 Lmoni 异常；截图 NIED 时刻分别为 29、48、64 个震度 0 检出站。
2. APP 的实际 `NiedRealtimePipeline` 后台 GIF 入口，按真实一秒一帧跑完 181 帧。默认灵敏度 2，11:18:26 JST 为 weak、48 站、13 个绿框，11:18:27 JST 为 47 站、13 个绿框。没有震度 1 以上的检出站。
3. 同步对照冻结的迁移前检出代码 `test/support/shake_detection_before_20261019.dart`，181 帧的 stage、weak、detected、strong 全部一致；CPU 原始像素采样和当前生产后台采样逐站没有数值差异。
4. 另将 KA 历史计算切到原 Dart 实现，仅在测试中运行，相同原始输入与显式时钟下，三档、每档 181 帧的完整诊断结果与 Rust KA 历史完全相同。不是新检出 owner 特有的结果。
5. 同时间 Kmoni 原帧走当前完整生产入口 181 帧，在默认灵敏度下全程 idle。该结果只能作为端点对照，不能用来否认 Lmoni 的异常。
6. 测试结束 Rust 检出 sessions/workers 和 KA sessions 均回到初始值。

## 已确认的错误处理链

Lmoni 部分原帧有大量测站像素缺失。例如 TYM002：

| JST | 原始 RGBA | 被解析震度 | KA 级别 | 上升量 | 活动值 |
| --- | --- | --- | --- | --- | --- |
| 11:16:00 | 0,85,238,255 | -1.9641315823862522 | 3 | 0 | 0 |
| 11:16:01 | 0,0,0,0 | -3.0 | 0 | 0 | 0 |
| 11:16:02 | 0,85,238,255 | -1.9641315823862522 | 3 | 3 | 3 |

恢复前后的有效像素完全相同，但中间透明缺测被记录为有效 -3.0，使恢复被算成真实上升。11:16:04 又出现广泛透明像素，次帧恢复后默认灵敏度出现 428 站检出；一秒一帧生产复测在 11:16:30 仍为 497 站、63 个框。

调用链：后台采样将 alpha 乘入 RGB，透明像素成为黑色；`ShindoColorUtil.rgbaToPosition(0,0,0)` 拒绝黑色，但 `rgbaToShindo` 随后查旧色表，色表包含黑色到 -3.0 的条目。`processSampledFrame` 接受这个 fallback，KA 将 -3.0 映射成有效级别 0，随后恢复形成虚假的上升量，再经邻站关联和 10.5 秒保持显示绿框。CPU 路径也走相同的旧色表回退，因此不是只有 Rust GIF 解码才出现。

本结论不把所有弱检出都认定为无效，也不推断缺测发生在 NIED 的哪个服务器内部环节。已确认的是这组原始输入中，透明缺测被本 APP 当成有效最低值，并产生可追踪的虚假上升。

## 文件与复现

- 原始主端点帧与清单：`tmp/captures/nied_false_detection_20261102_111827_jst_lmoni/`
- 对照端点：`tmp/captures/nied_false_detection_20261102_111827_jst/`
- `native-diagnostic.json`：三档灵敏度、原始像素探针、历史、上升量和逐帧检出。
- `dart-history-diagnostic.json`：原 Dart KA 历史对照。
- `production-ingress-diagnostic.json`：一秒一帧实际后台入口及迁移前检出对照。
- 新增测试：`test/nied_20261102_capture_diagnostic_test.dart`，运行需设置绝对路径 `RQ_STATION_CORE_LIBRARY`；`NIED_DIAGNOSTIC_CAPTURE` 指定原始采集目录，`NIED_DIAGNOSTIC_DART_HISTORY=true` 仅切换测试 KA 对照。

后续修复应只处理 GIF 缺测语义及其到 Rust KA 的生产调用，保留真实不透明深蓝最低值、正常颜色和透明度，不靠改检出阈值掩盖缺测问题。本轮尚未实施修复、重新打包该问题或在云端改算法。

## 后续授权修复：透明缺测与灰色站

用户随后明确授权处理，并要求地图灰色区分缺测站。以下为该次本地修复，前面的原始诊断数据保持原样。

### 具体修改与范围

| 位置 | 原行为 | 新行为 |
| --- | --- | --- |
| `native/station_core/src/nied_gif_sample.rs`（新增） | NIED 图片解码已在 Rust，颜色换算与缺测处理仍在 Dart | 原始 RGBA 不修改，NIED 采样与缺测判断迁入 Rust。alpha=0 输出缺测，不输出有效 -3.0。有效颜色沿用原 HSV 公式与完整原色表；对齐 Dart 常量幂 2/3 的运算顺序，不放宽数值一致断言。 |
| `native/station_core/src/lib.rs`、`CMakeLists.txt`、`include/rq_station_core.h` | 无此采样 ABI | 注册模块、编译依赖和只借用输入/输出缓冲的 C ABI。 |
| `lib/services/sources/native_station_image_decoder_io.dart` 与 stub | 只返回原始采样 RGBA | 增加 Rust NIED 采样接口、独立结果副本与复用缓冲，销毁时释放新缓冲；Windows 不回退旧 Dart 颜色算法。 |
| `lib/services/sources/nied_background_worker.dart`，`_scanFrame` | 透明像素乘 alpha 后黑色回退为 -3.0 | Windows 生产直接接 Rust 采样结果；传递 pixel_transparent 等质量标识。非原生平台既有分支保留有效值算法，增加相同透明缺测识别。 |
| `lib/services/sources/lmoni_image_service.dart`，`processPixels`、`processSampledFrame`、stop/broadcastStations | 透明缺测可能进入有效 KA 级别 0；只有保留值，显示不能区分当前缺测 | 原 GIF 兼容入口也调用 Rust；清除当前缺测观测、传递质量标识，KA 按原有短缺测历史规则处理 -1。不是强行改写历史级别或更改检出阈值。新增采样器在停止或目录替换时销毁。物理层现有质量标识保持原样。 |
| `lib/services/sources/nied_monitor.dart`，NiedStation 与 `_DecodedGifFrame` | CPU 兼容帧丢失 alpha；UI 无缺测便捷访问 | 兼容解码保留原 RGBA 供非原生入口辨别透明；模型读取已有质量标识，未增加假观测。 |
| `lib/services/sources/native_nied_detection_owner_io.dart`、`native/station_core/src/nied_detection_state.rs` | 图层签名只含级别和检出状态，历史级别不变时缺测不会触发重绘 | 原始输入第 8 列位 0 仍表示活动状态，位 1 传当前缺测；仅将缺测加入图层签名，不改变检出门槛、关联或 10.5 秒保持。 |
| `lib/widgets/map/nied_intensity_layer.dart` | 缺测短暂保留的级别仍画蓝/绿点或数字 | 当前缺测画灰点 `0x4D888888`，不画震度数字；恢复即恢复原配色。原点大小、透明度、边线和正常站图标保持原值，缓存纳入缺测位。 |
| `lib/widgets/map/quake_map_view.dart`，`_niedLayerSignature` | 兼容显示入口只按级别、检出状态刷新 | 同步纳入缺测标识；未改地图视角或任何情报/EEW聚焦逻辑。 |

### 实际验证结果

- 同一组未修改的原始帧重新验证：255484 个有效采样值与原 Dart 公式严格相等，40270 个透明采样确认为缺测；原文件 SHA256 全部匹配。
- TYM002 的历史从原来的 `3,0,3` 修为原缺测语义 `3,-1,3`，当前帧级别按既有短缺测规则保留 3；数据恢复时上升量为 0。地图即使保留级别也使用灰点。
- 三档灵敏度各跑完 181 帧均为 0 个检出、0 个框；截图对应时刻 71 个站缺测。
- 实际 NiedRealtimePipeline 后台 GIF 入口按真实一秒一帧跑完 181 帧，全程无这组缺测造成的检出；缺测、恢复时生产图层签名正常变化。测试实际接收时间与不可得的历史 receivedAt 明确分开。
- Release DLL 的相关回归 26 项通过：原始 51 帧奈良真实地震仍有检出、40 次推算输出；物理层数值与原质量标识、测站数据传输、生命周期释放均通过。另一个原速生产测试和实际地图组件渲染测试各通过。
- Rust 3 项通过，覆盖透明与真实不透明深蓝区分、原输入不修改、partial alpha 与原数值运算。
- UI 渲染证据：`tmp/cloud_vgpub_20261101/nied-missing-map-preview.png`，使用 TYM002 原始三帧与正式地图组件；已经目视检查。
- 结果文件分别保存 `missing-fixed-native-diagnostic.json` 与 `missing-fixed-production-ingress.json`，没有覆盖修复前证据。
- 额外发现的既有公共单测 `shindo_color_util_test.dart` 黑色期望 null、实际 -3.0 仍失败。该共有类本轮未修改，Windows NIED 生产已切到新的 Rust 专属采样。未把这个公共函数的行为扩改到其他产品；不宣称整个仓库全测通过。

本次完成本地源码、Release Rust 构建及上述测试；尚未生成包含本次修复的新 APP 安装包，也未更新云机。
