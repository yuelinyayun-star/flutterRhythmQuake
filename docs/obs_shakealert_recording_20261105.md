# SA（ShakeAlert）自动录制补充

## 本次行为

增加独立的 `ShakeAlert-EEW` 表格行，沿用已有设置样式和自动保存。默认震级门槛为 0，可切换震级／烈度及修改数值，独立开启或关闭。

默认结束条件是同一事件的 USGS 地震情报，匹配后附加录制 30 秒；未匹配等待上限为 1800 秒。沿用既有同震判定（300 秒／300 km）和多事件共用录制所有权规则。

新建默认配置包含 SA。已有内置配置只在缺失 SA 行时追加一次，原有各行的参数、ID、坐标及开关不变；已有 SA 行即使关闭也不会被重复添加。自定义名称的预设不追加。

## 具体位置、原行为与新行为

| 文件、位置 | 原行为 | 新行为 |
| --- | --- | --- |
| `lib/models/obs_automation_builtin_presets.dart`，`_buildRecordingPreset`、SA规则构造、`upgradeBuiltInEewRecordingPresets` 尾部 | 新配置和已有配置均缺少 SA 默认行 | 新建包含 SA；旧配置经 Rust 判断后只追加缺失行。历史模板指纹仍排除新行，保留原来的旧配置迁移行为 |
| `lib/widgets/ui/obs_recording_form.dart`，`obsRecordingAvailableEnds` | SA 没有对应的本机构结束选项族 | SA 对应 USGS，默认模式可选 USGS 情报／ShakeMap／DYFI／CMT，仍为单选 |
| `native/station_core/src/obs_automation_policy.rs`，`missingShakeAlertRules` | 没有检查遗漏 SA 行的策略 | Rust 返回应补行的内置预设下标；不重写输入配置 |
| `lib/services/native_obs_automation_policy_io.dart` | 无上述原生策略入口 | 通过现有 JSON FFI 请求 Rust，读取下标并释放返回内存；支持的原生平台不回退 Dart |
| `lib/services/native_obs_automation_policy_portable.dart` | 无上述入口 | 仅不支持 station-core 的平台提供对应实现 |

没有修改 EEW／情报源适配、原报文、地图、语音、录制执行器、超时执行、同震算法或其他机构默认条件。机构识别原先已经支持 `sa → shakeAlert`，本次没有改它。

## 实际验证

- Rust OBS 策略测试 **5 项通过**，包含限定内置预设、已有关闭行不重复追加、原输入不变、FFI 内存释放。
- 使用新编译的真实 Rust release DLL，Flutter 相关 **53 项测试通过**。
- 使用已有采集文件 `test/fixtures/eew_identity_20261013/reports.original.json` 中的原始 JIAN `sa` 和 WHEWS `sa_eew` 报文，经各自原适配入口触发录制，原始 JSON 保持不变。
- 使用明确标注的匹配边界单元输入检查：非同一事件 USGS 不结束；同一事件 USGS 才进入 30 秒附加录制；SA 完成时另一机构还在录制，不提前停止共享录制。
- 历史模板、旧配置用户自定义值、关闭的 SA 行、自定义预设、其他机构规则及表单自动保存测试通过。
- 已渲染并检查完整 OBS 设置表格，`ShakeAlert-EEW` 行、默认值、USGS 下拉项和开关正常。
- 相关 Dart 文件静态检查通过。

测试文件：`test/obs_automation_builtin_presets_test.dart`、`test/obs_recording_form_test.dart`、`test/obs_automation_presets_page_test.dart`、`test/native_obs_automation_policy_test.dart`、`test/obs_automation_runner_test.dart`。

记录：`tmp/obs_recording_check_20261105/sa-tests.log`；页面截图：`tmp/obs_settings_table_20261103/obs-settings-desktop.png`。

## 交付边界

本次完成本地源码、Rust DLL 编译和上述测试，**未重新打包 APP、未安装新版本、未改云电脑配置、未对真实 OBS 注入录制事件**。测试使用真实适配和运行器，录制动作使用测试执行器。
