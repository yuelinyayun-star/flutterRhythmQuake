# 2026-10-10 剩余内存检查与底图投影修复

保留 Flutter 3.41.1 / Dart 3.11.0。用户确认当前 Debug APP 已做过热重启，因此本次没有把旧占用归因于未重启。未关闭用户的 Debug APP；诊断程序均使用独立目录及原应用数据副本。

源码备份及证据目录：`D:/flutterApp/flutter-memory-remaining/20261010-220642`。

## 修改

- 矢量底图原来先为全球全部图形建立投影和缩放缓存，再做可见性剔除。现在先按带缓冲的视野选择完整图形，再交给原 PolygonLayer / PolylineLayer 绘制。小范围平移复用缓存；离开缓冲区域或改变整数缩放级别时替换绘制列表，释放旧投影缓存。
- 原地图数据、全部坐标、洞、边界和绘制顺序均保留。日期变更线附近采用保守的经度选择，避免跨世界路径漏画。
- 中国、日本、韩国烈度地图和日本海啸地图，共享同地区正在进行的加载，避免多个图层同时请求时重复解析同一份完整几何。
- 上述烈度地图及走时表解析后不再由 AssetBundle 重复缓存原始文本。解析结果仍正常复用，计算公式和数据不变。

## 固定地图场景对照

同一个 Profile 二进制通过环境开关选择修改前的备份组件或新组件。使用同三份原始地图，视角固定于 29.36°N / 120.17°E，按相同顺序经过 7、8、5、7、8、9、7 级缩放，最后均停在 7 级。每次独立运行 45 秒；OS 内存先采样，之后才请求 VM GC 和分配统计。对照进程只显示底图，未接入实时事件或 NIED。

| 指标 | 修改前组件 | 修改后组件 |
| --- | ---: | ---: |
| 对照进程平均 RSS，最后五次采样 | 204.76 MiB | 192.31 MiB |
| 对照进程 GC 后 Dart 堆 | 29.65 MiB | 14.57 MiB |
| Offset 数量 | 266,113 | 30,114 |
| 投影 Polygon 数量 | 7,146 | 610 |
| 投影 Polyline 数量 | 9,134 | 760 |
| 原始 LatLng 数量 | 116,428 | 116,428 |
| Flutter 错误 | 0 | 0 |

这项固定场景的 RSS 差值约 12.45 MiB、Dart 堆差值约 15.07 MiB；两者口径不同，不能相加。这是专用底图对照进程的结果，不能写成完整 APP 的固定降幅。

## 当前 APP 的额外持有者

对用户当前 Debug 进程的只读检查发现：

- `assets/maps/cn.eew.topo.json` 的原始字符串长 3,148,552 字符，由 `PlatformAssetBundle._stringCache` 持有；其 UTF-16 内容约 6.01 MiB。现在已禁止这份重复文本缓存。
- 部分大字符串由 VM 的 `Script.source_` / `Library.loaded_scripts_` 持有，属于 Debug 调试源码。另有编译指令、调试元数据及 Profiler 样本；这些不能通过重写业务 JSON 解析全部消除。
- 已停用自定义背景的字节为 null，雷达缓存只有一张 24,912,008 字节的 RadarFrameImage，上一轮生命周期修复在该进程中已生效。

完整 APP 的两次正常采样平均 RSS 分别约 429.42 MiB 和 354.64 MiB，但自动缩放和实时事件不同，随后检查的视角也分别处于约 7 级和 4 级。这两次不是固定输入对照，不能宣称本次修复必然减少 74.78 MiB。

完整 APP 仍包含 Dart VM、原生图像与渲染分配及系统 DLL。原生匿名分配尚未全部归属到具体调用栈，本次没有把它们全部称为泄漏，也没有据此断言换语言可以释放多少。

## 验证及证据

- 23 项相关测试最终通过。手机及桌面共 22 组原始地图画面逐像素一致，覆盖东亚、日本、钓鱼岛、南海、正负 180°、阿拉斯加、欧洲、南非、极区、全世界及旋转视角。
- 四份原始 TopoJSON 分别验证 20 个并发调用共享同一加载及解析结果；全部地区名称、代码、中心、坐标和顺序与直接解析原文件一致，源文件字节未变。
- 静态检查没有 error / warning，保留 TopoJsonLoader 已有 print 用法的两条 info。
- 包含本轮全部三份生产源码修改的 Windows Profile 构建通过，最终独立 APP 完成 45 秒 OS 采样，启动检查没有 Flutter 错误；其 RSS 均值约 393.79 MiB，仍是实时事件场景，不与先前不同场景直接计算降幅。
- `map-comparison.json`、`map-reference`、`map-viewport`、`map-binary`：固定场景结果、运行记录及同一对照程序。
- `baseline.jsonl` / `baseline-summary.json`、`final/baseline.jsonl` / `final/baseline-summary.json`：完整 APP 正常采样；不含对象枚举阶段。
- `debug-largest-strings.json` / `debug-cache.json`：匿名化持有链及实际缓存状态，不记录上游报文或凭证内容。
- `tests-final.log`：23 项测试结果。
- `verified-binary`、`verified-hashes.json`、`verified-runtime-summary.json`：最终完整 APP、源码与 AOT 哈希及启动检查。所有本轮诊断 APP 进程均已关闭，用户的 Debug APP 保持运行。
- `after/INVALID.txt` 对应复制时构建尚未结束的旧程序运行，明确排除；不用于任何结果。

本轮源码修改需要再次热重启才能进入当前 Debug APP。未升级 SDK、改上游数据、降低地图精度或制作安装包。
