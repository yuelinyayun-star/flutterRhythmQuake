# 图片复制及 OBS 录制时长调整（2026-11-05）

## 授权范围

1. 渲染事件页面在保存图片之外增加直接复制图片。
2. GQ 固定录制时长、未匹配情报的等待上限从 3600 秒改为 1800 秒；新建默认配置及缺省值同步修改。
3. 按用户明确确认结束云电脑当前录制，保留文件，并应用现有配置。

未修改情报接入、地图填色、震中、视角、阈值、结束类型、事件匹配规则、附加时间或多事件共享录制所有权。

## 具体源码位置与行为

| 文件及位置 | 原行为 | 本次行为 |
| --- | --- | --- |
| `lib/models/obs_automation_builtin_presets.dart`：默认常量、`_buildRecordingPreset`、`_agencyRecordingBlocks`、`_globalQuakeRecordingStack` | 新建内置规则固定录制及匹配等待使用 3600 秒 | 统一默认常量 `obsRecordingDefaultLimitSeconds = '1800'`，向各规则传入该值 |
| 同文件 `upgradeBuiltInEewRecordingPresets` | 识别历史内置模板并执行既有迁移 | 显式保留历史 3600 秒模板指纹及旧迁移时长，避免新默认值破坏历史模板识别或静默重写已保存程序；本次云电脑现有配置单独明确更新 |
| `lib/widgets/ui/obs_recording_form.dart`：`obsRecordingChooseEnd` | 缺少已有时长时使用 3600 秒 | 缺省使用 1800 秒；已有用户时长继续保留 |
| `lib/widgets/ui/obs_automation_presets_page.dart`：`_loadPresets` | 通用匹配等待及新增 CENC 情报规则缺省使用 3600 秒 | 缺省使用统一 1800 秒常量 |
| `lib/widgets/ui/event_render_page.dart`：工具栏、`_exportImage` | 只提供保存图片 | 增加同风格“复制图片”；保存与复制共用原底图就绪检查和截图边界，互斥操作并显示成功或错误提示 |
| `lib/widgets/ui/event_render_export.dart`：`copyEventRenderPng` | 已有 PNG 截取及保存 | 复用同一 PNG 截取函数，把完整图片交给剪贴板服务 |
| `lib/services/event_render_clipboard{,_io,_stub}.dart` | 无图片剪贴板入口 | Windows 在工作 isolate 调用 Rust FFI；不支持的平台禁用按钮，不静默退回其他后端 |
| `native/station_core/src/event_render_clipboard.rs` | 无图片剪贴板原生接口 | 校验并解码 PNG，写入 Windows PNG 与 DIBV5 图片格式，显式管理句柄、内存及所有权 |
| `native/station_core/src/lib.rs`、`native/station_core/include/rq_station_core.h` | 未导出图片复制接口 | 注册独立模块并声明 `rq_event_render_copy_png` |

OBS 改动仅涉及配置构建及表单缺省值，没有改动 `obs_automation_runner.dart` 的计时、匹配或共享录制执行逻辑。图片复制属于平台适配，图片转换及剪贴板写入走实际 Rust DLL。

## 云电脑实际操作和验证

- OBS 便携版 30.2.3 收到 `StopRecord`；随后 `GetRecordStatus.outputActive = false`。
- 保留文件：`E:\OBS-30.2.3-portable\test-recordings\2026-11-05 12-56-45.mp4`；停止并完成封装后文件大小为 **960,139,024 字节**。
- APP 停止期间更新 `%APPDATA%\com.example\flutterrhythmquake\shared_preferences.json` 中两项配置：`flutter.obs_automation_presets_v1`、`flutter.obs_recording_wait_seconds`。
- 内置规则共 11 个时长参数：10 个情报等待上限和 1 个 GQ 固定时长，均为 `1800`；其他配置键深比较相等。GQ 用户原有 M5.5 阈值保留。
- 重启现有 APP 以释放旧录制任务；13:59:21（UTC+8）回读确认所有 11 项及通用等待均为 `1800`，运行进程 PID 15732，路径 `E:\RhythmQuake\flutterrhythmquake.exe`。
- 13:59:24 再查 OBS，确认未录制。OBS 场景及编码配置没有调整。

## 验证结果与交付边界

- OBS 三个测试文件共 **36 项通过**：新默认时长、历史模板识别、用户修改保留、CENC 情报触发、GQ 30 分钟、多个 GQ 事件和 GQ／其他机构重叠录制、表单自动保存。
- 原生图片格式测试 **1 项通过**：通道、透明度、上下行顺序、无效输入。
- 实际 Windows 剪贴板测试 **2 项通过**：1600×900 和 1600×1200；从系统剪贴板回读 PNG 与截图逐字节一致，并核查 DIBV5 尺寸；无效输入不会覆盖已有剪贴板。
- 原有渲染测试中的 JMA、CENC 原始报文、区域分布、描边、图片保存及 LPGM 类别检查通过；首轮组合运行的失败均来自 OBS 旧一小时预期及历史配置构造，修正后 OBS 36 项全通过。
- 12 个相关 Dart 文件静态检查无 error／warning；渲染页面存在 7 条花括号风格 info。
- 已编译本地 Rust release DLL 并通过真实 FFI 测试。**尚未重新打包 APP 安装包，尚未把图片复制功能安装到云电脑。** 云电脑本次应用的是现有 APP 的录制配置，不能等同于部署了新版本。

测试文件：`test/obs_automation_builtin_presets_test.dart`、`test/obs_recording_form_test.dart`、`test/obs_automation_presets_page_test.dart`、`test/event_render_clipboard_test.dart`、`test/event_render_fixes_test.dart`。

本地实测记录：`tmp/obs_recording_check_20261105/obs-final-tests.log`、`applied.txt`、`verified.txt`、`live-status.txt`。
