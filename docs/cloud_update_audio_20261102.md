# 云电脑 APP 更新与音频设备修复（2026-11-02）

授权范围：编译最新 Windows 安装包，更新指定新云电脑 APP，排查并处理其无法播放音频。此次部署未新增或修改 APP 业务代码；安装独立的厂商签名虚拟声卡，不制作或加载无签名内核驱动。

## 构建与更新

- `package_windows.ps1 -Edition personal -SkipProcessCleanup` 构建成功。
- 安装包：`build/installer/RhythmQuake_Setup_1.0.5.22_personal_x64.exe`，41604858 字节。
- SHA256：`c89197dc2fe9faf209db8e914deef353f81df4e8c431d52a08845d4fb81efe13`。
- 本地 Release 清单 141 文件逐项哈希通过。包含本轮已验证的 NIED 透明缺测/灰色站、自动 DYFI/ShakeMap 复用普通情报震中层，以及此前系统语音可用性检测；各功能修改及测试详见各自文档。
- MCP 校验目标 `DESKTOP-VUEC9GQ`，生产目录 `E:\RhythmQuake`。只替换与已安装清单不同的 `data/app.so`、`rq_station_core.dll` 和更新后的 `release_manifest.json`。未改用户配置、未备份旧 APP，未使用 RDP。
- ZIP SHA256：`dc15e3c8f2ee116baed8eda15a3578d8537bfa7ec73354a15184b4a7116ab8fa`。传输后先校验 ZIP、成员路径和文件 SHA，再关闭并更新 APP。
- 云端安装后 141 文件哈希全部通过；清单 SHA256：`97fd2f5b1fbe4df81834a1e673f4406912b4147ce71bb74cc4f827fa4ae4e1f8`。
- 重新启动 PID 10288，SessionId 1，`Responding=true`，标题 RhythmQuake。此为与安装包相同发布内容的增量部署，不表示执行过安装向导。

## 音频故障证据与针对性修复

修复前：`Audiosrv`、`AudioEndpointBuilder` 均 Running/Auto，`Win32_SoundDevice` 为空。唯一“远程音频”端点 Code45，不在场。WinMM 播放设备数量 0；默认 `waveOutOpen` 返回 2（BADDEVICEID）。故障是缺少当前可用的播放设备，不是凭猜测重启服务或修改 APP 音量。

安装官方 VB-CABLE 基础版 Pack45：

- 来源：<https://download.vb-audio.com/Download_CABLE/VBCABLE_Driver_Pack45.zip>
- ZIP SHA256：`b950e39f01af1d04ea623c8f6d8eb9b6ea5c477c637295fabf20631c85116bfb`，1318877 字节。本地下载并校验后经 MCP 传云机；云机直接下载超时的文件未用于安装。
- 云机安装前实查 `VBCABLE_Setup_x64.exe` 签名 Valid（BUREL VINCENT），Win10 驱动 CAT 签名 Valid（Microsoft Windows Hardware Compatibility Publisher）。
- 使用厂商安装器安装；没有禁用驱动签名、导入信任证书、改安全策略或重启云机。独立安装，没有把驱动整合进我们的 APP 安装包。
- 修复后 `VB-Audio Virtual Cable` Status OK / ConfigManagerErrorCode 0；驱动 `3.3.1.7`，Provider VB-Audio Software，`IsSigned=true`，INF `oem22.inf`。
- 新播放端点 CABLE Input、CABLE In 16 Ch，录音端点 CABLE Output 均 OK。WinMM 播放设备数变为 2；默认 `waveOutOpen` 返回 0。

## 实际音频流验证与边界

使用已安装 APP 原始 `assets/sounds/general/countdown.wav`（PCM16、双声道、48000Hz），通过系统默认 WinMM 设备播放，同时录制 CABLE Output。不是仅判断播放函数没有报错。

- 实录 662400 字节；播放完成。
- 播放前 RMS 0.47967，播放段 RMS 5156.108，峰值 23984，测试通过。
- 设备、缓冲区在 finally 中停止、解除准备和关闭。
- 验证确认音效数据可以进入虚拟播放设备并从录音端点取出。未宣称已通过 APP 内部事件触发完整报警，也未宣称用户远程客户端已经听见；后者还取决于远程软件转发或 OBS 音源选择。
- 此驱动不安装 Windows TTS 语音包；缺少系统语音与缺少播放设备是两件事。
- 厂商建议安装后重启；本次不自行重启，当前实际设备与音频流已经可用。

云机证据在 `%LOCALAPPDATA%\RhythmQuakeCloudMCP\logs\audio-repair-20261102`（原始设备清单、WinMM 探针、roundtrip.json / roundtrip.wav）以及 `logs\latest-map-update-20261102\deployed.json`。本地辅助脚本位于 `tmp/cloud_vgpub_20261101`，不是常驻组件。

## 用户确认用途：OBS 采集/直播

通过 OBS 已启用的本机 WebSocket 只读核对实时状态，未改场景文件、启动直播或录制：

- 原有 `rhythmquake` 窗口源 `capture_audio=true`，目标精确匹配 `flutterrhythmquake.exe`。
- 音源未静音，增益 0dB / 100%，轨道 1–6 均开启，监听关闭。其画面 active/showing；实际 OBS 预览已看到 APP 地图和测站更新。
- OBS 日志确认 APP 重启后在 14:06:41 重新初始化该源的 48000Hz process loopback。
- 18 秒观察收到 354 个音量事件，RhythmQuake 每次均存在双声道，当前无播报、电平为 0。这不能冒充已有事件声或直播端收音测试。
- 现有按应用采集路由保留；不再新增全桌面采集，避免把其它源的声音再混入。没有修改其它应用音源、场景尺寸或位置。
- 虚拟设备音效回录成功、OBS 路由/会话有效与真正触发 APP 警报并验证直播端收音，属于不同验收层级；最后一项此次未执行。
