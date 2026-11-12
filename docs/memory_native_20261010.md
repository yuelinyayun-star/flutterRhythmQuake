# 2026-10-10 原生内存及音频排查

沿用 Flutter 3.41.1 / Dart 3.11.0，在独立目录使用原安装数据副本运行 Profile APP。没有更换 SDK、修改上游报文或关闭警报音效。本轮源码备份及测量文件位于 `D:/flutterApp/flutter-memory-native/20261010-224600`。

## 当前完整 APP 的状态

先正常采样 240 秒，不连接 VM service 枚举对象；去掉启动前 30 秒后，RSS 为 387.81～520.38 MiB，平均 447.06 MiB。四个一分钟区间含启动阶段的均值依次为 361.51、430.05、479.93、457.82 MiB。存在启动加载与实时波动，这段记录不足以认定持续泄漏。

随后 GC 和只读查询得到：

- 业务 isolate group 的堆使用 98,287,136 字节，约 93.73 MiB；包括 NIED 和 AOT 代码对象。业务 isolate 共用此堆，不能重复相加。
- VM 报告包含 VM service 的自身诊断开销。连接及对象查询后的 RSS 不替代前面的正常采样。
- ImageCache 只有一张雷达图，24,912,008 字节，约 23.76 MiB。
- AssetBundle 原始资源字符串缓存为空，停用的自定义背景字节为 null。
- 地图投影层每个简化缓存只有当前整数 zoom 的一项，前一轮工作集限制已生效。
- 19 个 AudioPlayer、18 个音效池。数量由实际分配快照确认，不能仅凭 Dart 包装对象的浅大小判断原生开销。
- Windows 驻留 image 页约 98.70 MiB，包括 Flutter、显卡、输入法、Media Foundation、TTS 和系统 DLL；部分是共享页面。匿名 private 页尚未逐项归属。驻留页读取不是原子快照，不能直接与另一时刻 RSS 严格相加。

尝试只对诊断 PID 开启 xperf 原生堆栈采集，系统返回访问被拒绝（0x5），未开启记录，也没有改系统追踪配置。以下音频归属采用独立原文件对照，未把未知原生内存推断成某个组件的泄漏。

## 音效预热占用

同一个独立 Profile 程序分别运行空页面和现有 SoundEffectService.warmUp，预热使用现有 17 份音效路径，未播放音频。准备完成后等待稳定采样，再进行 GC 对象查询。

| 场景 | 稳定 RSS 均值 | GC 后 Dart 堆 | AudioPlayer 数量 |
| --- | ---: | ---: | ---: |
| 空页面 | 111.58 MiB | 5.29 MiB | 0 |
| 17 个原有音效预热 | 128.52 MiB | 5.39 MiB | 17 |

该组件实验约增加 16.94 MiB RSS，主要不在 Dart 包装对象中。此数包含首次初始化 Media Foundation 的开销，不能按每播放器等分，也不能直接当作完整 APP 可回收量。保留预热和并发警报行为，没有为了这部分占用延迟警报播放。

## 已修复的字节音频资源泄漏

`third_party/audioplayers_windows/windows/audio_player.cpp` 的 SetSourceBytes 原来取得 IStream 和 IMFByteStream 两个拥有引用的裸 COM 指针，却没有 Release。即使 Dart 播放器已 dispose，仍会保留流及音频缓冲。现改为 winrt::com_ptr 自动释放，并检查 MFCreateMFByteStreamOnStream 和 CreateObjectFromByteStream 的 HRESULT。原始音频内容及解码流程保持原样。

使用同一原始 `assets/sounds/general/countdown.wav`（170,866 字节）连续准备 200 次，完成后 dispose 播放器，再等待稳定采样。原始文件及独立副本 SHA-256 均为 `478cdfdab1318a09219bbcc9be87d9d929605ed6069e9b59b48210ec152182e1`。

| 版本 | 释放后 RSS 均值 | private commit 均值 | GC 后 Dart 堆 |
| --- | ---: | ---: | ---: |
| 原实现 | 234.46 MiB | 228.17 MiB | 5.32 MiB |
| COM 引用修复 | 170.04 MiB | 161.55 MiB | 5.32 MiB |

RSS 差约 64.41 MiB。原实现从第 78 次约 194.70 MiB 上涨到第 155 次约 220.28 MiB；修复后第 84 次约 170.20 MiB、第 172 次约 170.34 MiB，呈稳定平台。两次释放后 AudioPlayer 均为 0，支持问题发生在原生引用保留，而非 Dart 播放器集合。

**当前 APP 的音效和 Windows/GPT-SoVITS TTS 使用 AssetSource / DeviceFileSource，没有 BytesSource 调用。因此这是一处已验证的潜在泄漏修复，不能宣称当前完整 APP 常态占用因此减少 64 MiB。**

## 原生播放验证及证据

修复后的 Windows Profile 编译通过。使用原始 countdown.wav 的 BytesSource 与原始 issue.mp3 的 AssetSource 静音并发播放，避免诊断音效干扰使用者：

- 两者读取时长分别为 888 ms、1,567 ms。
- 同时 resume 后，查询位置均已推进到 85 ms。
- 两者均收到真实 native 完成事件并正常 dispose。
- Flutter 错误列表及 native stderr 为空。

证据目录保留：

- `baseline.jsonl` / `baseline-summary.json`：完整 APP 正常运行采样。
- `heap.json`、`cache.json`、`owners.json`、`pages.json`：GC、实际缓存、投影持有链及 Windows 驻留页。
- `backup/audio_player.cpp`：修改前原生源码。
- `audio-before-results.json` / `audio-after-results.json`：空页、预热及 200 次原始音频加载的测量。
- `audio-before-*` / `audio-after-*`：逐次加载、正常采样、GC 及日志；各版本 binary 分开保存。
- `audio-play-play/snapshots.jsonl`：真实并发播放的时长、位置和完成记录。
- `audio-play-binary`：含实际原生修复的播放验证程序；隔离项目 `tool/audio_memory_profile.dart` 为诊断入口。

此次改动位于原生插件，应用时需要完全退出并重新编译 Windows APP；Flutter 热重启不会重新加载原生 DLL。没有生成安装包或修改用户安装目录。
