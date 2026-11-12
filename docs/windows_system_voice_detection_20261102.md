# Windows 系统语音启用检测（2026-11-02）

授权目标：设置中开启系统语音时检测是否有可用语音，没有则提示安装，UI 延续既有设计。只处理此设置流程、相关枚举及 Rust 后端，不改播报内容、语音队列、优先级或其它业务。

## 精确修改位置与行为

| 文件与入口 | 原行为 | 新行为 |
| --- | --- | --- |
| `native/station_core/src/windows_tts.rs`（新增），`lib.rs` 注册模块 | 没有原生能力检测接口 | Rust 在后台调用与实际 Windows 播放一致的 System.Speech 枚举；保留原始名称、语言、Enabled、错误信息。提供 available / unavailable / check_failed 三态和 FFI 释放接口。6 秒超时终止并回收子进程；不播放声音、不安装组件。 |
| `lib/services/native_windows_tts.dart`、`native_windows_tts_io.dart`、`native_windows_tts_stub.dart`（新增） | 无接口 | Windows 生产调用 Release Rust DLL，Isolate.run 执行，finally 释放结果；不静默退回 Dart 后端。 |
| `lib/models/system_voice_availability.dart`（新增） | 无类型 | 区分缺少可用系统语音和检测操作失败。 |
| `lib/services/tts_service.dart`，`_loadWindowsVoices`、`checkWindowsSystemVoice` | Dart 启动 PowerShell 并解析语音枚举；合成的“系统默认”也存在于菜单 | 相关枚举与检测切换 Rust；保留原语音选项 ID、名称、语言、排序。只有真实启用的系统语音证明可用，“系统默认”不算。 |
| `lib/widgets/ui/system_voice_prompt.dart`（新增） | 无检测提示 | 异步检测开关防重入；缺少语音时保持关闭、不保存开启。使用既有 settings_controls 的磨砂背景、圆角、细边、蓝色强调按钮。提供安装路径、“暂不开启”、“前往安装”；检测失败只显示检测失败，不谎称一定没安装。组件移除后释放父级忙碌状态，不继续保存或弹窗。 |
| `lib/widgets/ui/settings_page.dart`，`_buildTtsSettings`、`_changeGptSovitsEnabled`、`_openWindowsSpeechSettings` | 开启主语音开关直接保存；切换系统后端直接保存 | Windows 系统语音开启前检测；GPT-SoVITS 主开关开启不查系统语音；已开启播报时从 GPT 切回系统也检测，失败保留原后端。安装按钮打开 `ms-settings:speech`，不代用户安装组件。原设置行位置及对齐结构保留。 |
| `test/system_voice_prompt_test.dart`、`test/native_windows_tts_test.dart`（新增） | 无此能力验收 | 检查三态、开启/关闭/GPT、重复点击、设置关闭、设置链接失败、重新检测、窄屏/大字体、实际 Release FFI 与内存释放。 |
| `test/fixtures/windows_tts/*`（新增） | 无原始枚举样本 | 保存本地有语音和云机无语音的原始 JSON 输出及 SHA256；未改写原值。 |

此前已完成的 `third_party/flutter_tts/windows/flutter_tts_plugin.cpp` 启动崩溃防护不属于本次设置新功能；参见 `windows_startup_tts_20261102.md`。本次没有继续改插件、依赖版本、地图或 EEW 业务。

## 实际验证

- Rust 4 项通过：原始有/无语音数据、异常结果分类、超时回收、FFI 所有权释放。
- 最新 Flutter 6 文件共 36 项通过：新 UI、实际 Release DLL 检测，以及原有偏好、Windows 队列、EEW 优先级和替报测试。未删除原有业务断言。
- 10 个相关 Dart 文件静态检查无问题。
- 本地检测真实返回 Microsoft Huihui Desktop / Microsoft Zira Desktop，重复检测结果分配归零。
- 新云机真实调用新 Rust DLL 返回 unavailable，outputs=0，保留原始错误。没有安装任何 Windows 语音组件。
- 新窗口视觉测试渲染已检查；不把该渲染当作实际云机设置交互验收。

## 打包、部署与运行边界

- 已打包：`build/installer/RhythmQuake_Setup_1.0.5.22_personal_x64.exe`。
- 安装包 SHA256：`c36bece063604d59b5bfe39fce0381d545d23b7cab8de0506d6cf8a4f09c9188`。
- 本地 Release 清单 141 个文件全部匹配。
- 云机通过独立 MCP 更新 E:\RhythmQuake，仅替换 `data/app.so`、`rq_station_core.dll`、`release_manifest.json`；云机 141 个发布文件哈希全部匹配。没有创建旧版本备份，没有使用 RDP。此为增量部署，不声称在云机执行过完整安装向导。
- APP 已重新启动，PID 11692；实际截图显示地图、测站、情报与侧栏运行。
- 真实“开启语音→弹窗→前往安装”的云机点击验收未完成：点击设置时 MCP 返回 USER_CONTROL，随后截图也被用户控制保护拦截，已停止界面输入。不能宣称实际云机弹窗和 Windows 设置跳转已验收；后续应在云机空闲时只继续这一步。
- 临时传输曾遇到 USER_CONTROL / CONTROL_UNAVAILABLE，按已验证的字节数和 SHA256 续传完成；错误没有导致半包覆盖安装目录。

## 本轮并行核查

用户随后要求按截图时间检查 NIED 检出，另见 `nied_detection_capture_20261102.md`。该核查仅新增原始采集、诊断测试和文档，没有修改正式检出算法；本安装包不包含 NIED 缺测解析修复。
