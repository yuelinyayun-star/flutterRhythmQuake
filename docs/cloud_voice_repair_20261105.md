# 云电脑语音修复记录（2026-11-05）

适用设备：DESKTOP-VUEC9GQ，Windows 10 19045.1889。本次目标为恢复已开启的 APP 系统语音，不修改地震、海啸、地图、OBS 自动录制规则或 APP 源码。

## 实际故障及证据

- APP 语音、事件、更新报开关已开启，选中 `Microsoft Huihui Desktop|zh-CN`，音量 1.0、语速 0.58、音调 1.0。问题并非没有打开设置。
- 系统能够枚举慧慧音色，但 `System.Speech.SelectVoice` / 实际合成失败。此前仅凭音色枚举判断安装可用，验证不完整。
- 慧慧使用的 OneCore 引擎 CLSID `{179F3D56-1B0B-42B2-A962-59B7EF59FE1B}` 最初激活返回 `0x80040154`，对应引擎文件及注册缺失。
- 补齐引擎后，`ISpObjectWithToken.SetObjectToken` 返回 `0x80045040`。对相同有效路径调用 OneCore `ISpObjectTokenCategory.SetId` 也失败。公共 SAPI DLL 的 SHA256 与微软原文件一致，相关 COM 类存在，不能将此错误归因于所有公共 COM 注册丢失。
- 实际文件跟踪发现 `Speech_OneCore\Common\Tokens.xml` 不存在。初始化内部结果为 `0x8004502D`，注册根目录映射未建立。
- 重建目录配置后，错误推进到 `0x80070002`；跟踪确认中文慧慧混读依赖的 `Speech_OneCore\Engines\TTS\en-US\MSTTSLocEnUS.dat` 缺失。
- 补回英文数据后返回 `0x8004503A`；跟踪显示初始化需要的 `TextNormalizers` 类别不存在。补齐空类别后实际合成成功。

## 本次保留的系统修改

1. 补入微软 Windows 10 对应组件文件，未覆盖已有同名文件：
   - `%SystemRoot%\System32\Speech\Engines\TTS\MSTTSEngine.dll`：10.0.19041.1052 组件，SHA256 `23895fcfd75613e6cbf1b47f3886845d557aef9e9067f873cf9733702183a6d1`。
   - `%SystemRoot%\System32\Speech_OneCore\Engines\TTS\msttsengine_onecore.dll`：10.0.19041.746 组件，SHA256 `ad526d6499f907a87ae549c305862762447010e69b2d5a26b079d00983e16be0`。
   - 同目录 `msttsloc_onecore.dll`：10.0.19041.746 组件，SHA256 `a25e771a3a44f24451145ed278f373b3dfc37c1f795edba346e55a9c0a978a35`。
   - 文件下载自微软符号服务器，上传后核对哈希及云端数字签名。
2. 恢复 OneCore `{179F…}` 与桌面 `{C64501F6-E6E6-451F-A150-25D0839BC510}` 的引擎 COM 绑定及 `ThreadingModel=Both`。曾临时将慧慧绑定到桌面引擎进行诊断，未成功；已恢复原始 `{179F…}` 绑定。
3. 桌面慧慧 token 的 `Attributes` 补入原始 OneCore token 已有的 `DataVersion` 和 `SayAsSupport`；未改动其语言、音色、音频数据或 APP 选项。用户级 OneCore 默认音色设为现有慧慧 token。
4. 新建 `%SystemRoot%\System32\Speech_OneCore\Common\Tokens.xml`：
   - 这不是下载的原始微软 XML，也不是复制其他 Windows 版本的文件。
   - `PhoneConverters` 的 8 个 token、36 个值由这台机器现存的 10.0.19041.1620 组件清单逐值生成；保留原始内容。
   - 按系统 XML 结构加入 `AppLexicons` 空类别及初始化实际要求的 `TextNormalizers` 空类别；未添加虚构音色或转换器。
5. 使用 `Add-WindowsCapability` 安装微软 `Language.TextToSpeech~~~en-US~0.0.1.0`，报告不需要重启。组件库有英文 DAT，但目标目录缺少链接，因此从这台机器安装后的 `WinSxS\amd64_microsoft-windows-texttospeech-en-us_…10.0.19041.1…\MSTTSLocEnUS.dat` 原样复制至语音数据目录，大小 9,258,072 字节。

修复过程中使用一次性 SYSTEM 任务及 TrustedInstaller 身份写入受保护的语音组件，未更改这些目录或注册项的 ACL。公共 `sapi.dll` 执行过自注册；对 `sapi_onecore.dll` / `sapi_extensions.dll` 的自注册返回 `0x80070715`（找不到资源类型），该返回值不能解释为已经证实的权限拒绝。

最初单独补桌面引擎不能修复慧慧，属于诊断中的错误方向；最终由 OneCore 调用及实际合成验证确定结果。

## 实际验证

- 原始 OneCore 慧慧和 APP 使用的桌面慧慧 token 均成功生成 101,652 字节测试 WAV。
- `System.Speech.SelectVoice('Microsoft Huihui Desktop')` 成功，中文“RhythmQuake 语音播报测试。”生成 128,756 字节 WAV。
- 在 APP 设置中点击“播放测试”，虚拟声卡捕获 2,807,040 字节音频，峰值 20,237。由于声卡也有其他程序输出，这次采集本身不能单独证明声音归属；随后补做 APP 进程与 OBS 独立声道的同步测试。
- 删除诊断时额外复制的 18.5 MB 中文 DAT 副本后，再次中文合成仍成功，保留原有语音数据路径。
- 为重新加载系统语音并保留播放日志，将 APP 从 PID 13080 重启为 PID 15800。未更改 APP 源码、安装包、现有语音开关、语速、音调或音量。
- 已删除本次 3 轮 Procmon 大体积抓取及传输临时文件，共 595,452,846 字节，并删除本次精确命名的一次性修复计划任务。

OBS 只读检查：当前运行的是便携版 30.2.3，WebSocket 在 4456；原先检查 4455 的连接拒绝不能当成 OBS 未运行。`rhythmquake` 窗口采集开启音频、未静音、音量 0 dB、音轨 1–6 开启。

最终同步测试使用独立的一次性交互任务启动监听，确认监听已经就绪后才点击 APP 的“播放测试”，避免旧的后台命令输出管道等待导致点击发生在监听结束之后。20 秒内收到 391 帧 OBS 音量事件，APP PID 15800 的 CoreAudio 峰值为 **0.61688256**，OBS `rhythmquake` 独立声道峰值为 **0.55523789**。两者都实际收到本次 APP 试听音频。此测试未修改 OBS 设置，也没有开始或停止录制；没有额外录制成片验收。同步测试计划任务已删除。

APP 重启命令完成后，MCP 出现工具调用排队，已通过取消本地未结束的请求释放调用锁，恢复 `ControlStatus=ready` 后继续测试；没有切换远程桌面或绕过用户手动控制保护。

详细本地诊断文件位于 `tmp/cloud_voice_20261105/`；该目录含组件来源、脚本、原始返回结果和截图，不含对用户报文的加工替换。
