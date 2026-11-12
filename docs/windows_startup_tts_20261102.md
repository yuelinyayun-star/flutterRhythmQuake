# Windows云电脑启动退出：语音插件原生初始化异常

## 证据与根因

目标为本次用户指定的新Windows云电脑，Windows 10 19045，Administrator。
全程使用独立 `rq_vgpub_windows` MCP，没有重新连接RDP。

MCP安装成功且后台任务Running，APP 1.0.5+22已安装在 `E:\RhythmQuake`；
原安装器记录APP启动退出码 `-1073740791` / `0xC0000409`。
主程序、Flutter引擎、Rust DLL、Dart AOT文件均与原安装包哈希一致。

使用签名有效的微软ProcDump仅采集一次原始启动minidump。实际未处理异常是
`0xE06D7363`，类型 `winrt::hresult_error`；C++异常参数的throw-info和模块基址
均指向 `flutter_tts_plugin.dll`，异常对象中的HRESULT为 `0x800455A0`。
原始dump保留在云电脑MCP日志目录 `app-native-diagnostic`。
诊断脚本中的stackPointerCandidates只是内存候选值，并非已符号化的调用栈。

独立Windows WinRT探针得到AllVoices为0，构造SpeechSynthesizer重复报相同
`0x800455A0` / Internal Speech Error。System.Speech枚举也报告系统没有可用语音。
因此不能把此问题归因于地图、GPU、Rust迁移或安装文件损坏。

原 `flutter_tts` 4.2.5的WinRT成员默认构造会激活SpeechSynthesizer；插件注册时
没有处理该原生异常，插件注册阶段直接终止进程，Dart层的异常处理无法拦截。

## 精确修改范围

- `pubspec.yaml`、生成的`pubspec.lock`：选择项目内同版本4.2.5源码，其他原有依赖版本保持不变。
- `third_party/flutter_tts`：保存25个上游实现文件及原许可证；其中只有
  `windows/flutter_tts_plugin.cpp`与上游不同，另加本项目说明文件。
- WinRT句柄以null构造，把已有激活操作移进特定`winrt::hresult_error`捕获区域。
- 保存原HRESULT和错误消息，语音方法通道返回`tts_initialization_failed`，不伪报成功。
- 析构时仅在MediaPlayer非null时Close。

没有修改成功初始化后的语音参数、播放、回调或业务调度，没有修改Windows SAPI分支，
没有修改Dart语音服务、其他平台实现、地图、情报、EEW或Rust计算。
本修复属于Windows平台异常处理；没有借此迁移或重写无关语音队列。

## 实机验证

本地编译后仅通过MCP替换云电脑的 `flutter_tts_plugin.dll`，未备份APP或重写原始日志。
替换前哈希：`b83dec95fcfe020e49d9fb7617d5f3fcfa6928d1fd5d91a32a23a0958fde9057`。
实测修正版哈希：`90a02590f5aca6bdc43aaef17a71ea45d194e5f987f538f18175117d06696459`。
部署时同步精确更新`release_manifest.json`内该DLL的bytes/sha256，其余140项保持原值。
实际安装目录141项文件全部哈希校验通过，独立验证结果另存MCP日志目录
`tts-native-fix/verification.json`；原始失败日志没有覆盖。

修正后PID4232启动成功，多次查询保持Responding=True；通过MCP切到APP并截图，
实际显示地图、实时测站、情报列表和侧栏。其他四个核心文件保持原值：

| 文件 | SHA256 |
| --- | --- |
| flutterrhythmquake.exe | cb20fb6bec640f04ad334e77976b1e34d2cd2ba30671d70bcfd0e77d982dc927 |
| flutter_windows.dll | d3b43a11850159ac1e1f73bdf0caa8db728a958467ef49b72c5772eecd3e95f4 |
| rq_station_core.dll | ccca7155634862d804414f2bf610ef757bb8fe8dc5d10fc20f3285206f9ad01f |
| data/app.so | 9b9abe56f8fb9c5b6c37ef96bfb13f79ec33b853e65b09d632ad08c530fc273b |

独立系统探针仍显示无可用语音；启动修复不等于已经安装或修复了系统语音组件。
其他此前出现过的公共电脑没有同样的崩溃证据，不能直接宣称同一根因或已修复。

## 本地检查与后续包

原有语音偏好、Windows队列、EEW优先级和替报回归使用现有测试，不改变其断言；
在恢复原有锁定依赖后，四个测试文件共21项通过。
依赖解析中出现的三个非目标版本变化已恢复到修改前的锁定版本，并使用
`--enforce-lockfile`核查；169项原有hosted依赖版本对照证据保存在本次tmp目录。
修正版APP安装包与包含MCP的r3整合包已编译通过；r3内的语音插件哈希与云电脑
实测DLL一致。不能把云电脑单DLL验证等同于完整新安装包已经在该机安装。
云电脑当前可继续使用已验证的单DLL修复版，无需再次安装r3。

最终实机检查：PID4232连续运行13.5分钟，Responding=True，MCP后台任务Running。
新APP安装包SHA256：`2b3b8f2e1614d457fc0dbbdbe82e09b4d2eec719739d55a67b35e775428d6bf5`。
整合包位于 `build/cloud_vgpub/RhythmQuake-APP-MCP-Setup-r3.exe`。
