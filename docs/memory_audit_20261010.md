# 2026-10-10 剩余内存占用排查

本次只调查内存保留链，没有修改业务代码或安装目录的数据。使用 Flutter 3.41.1 / Dart 3.11.0、先前 NIED 重构后的 Windows Profile 对照程序，运行目录及设置来自独立备份副本。正式 APP 的设置、源报文和时间没有被改写。

## 测量口径

- 先前约 369 MiB 是 NIED 原始回放的 **Flutter 测试进程峰值 RSS**，测试同时包含参考实现和后台实现。它不是“APP 去掉 NIED 后的剩余内存”。
- APP 的 RSS 包含 Dart 堆、图形/图片、原生分配、代码和 Windows DLL 等。不能从总 RSS 减去某个测试数字，就得到其他数据源的内存。
- 当前业务 isolate 共用一个 isolate group 的堆。不能把每个 isolate 查询到的同组 heap 相加。
- 对象统计采用 GC 后的浅大小；它不包含所引用对象。独立对象实验、图片缓存计数和 OS 驻留页属于不同口径，以下数值不能直接累加成总 RSS。
- 连接 VM service、枚举实例和查询引用链本身会增加诊断开销；诊断后的进程峰值不作为平常使用量。

## 已确认的主要持有者

| 项目 | 实测证据 | 原因与下一步 |
| --- | --- | --- |
| GlobalQuake 历史原文 | 15 组事件，163 份报文；原文内 97,823 个 Map、978 个 List。单独还原实验 GC 后增加 **32.92 MiB** | 启动恢复 `EewEventGroup` 时，每份 `UnifiedQuakeData.sourcePayload` 都展开为不可变嵌套容器。可将历史原文留在磁盘，列表保留必要字段，查看详情/回放时按需读取。 |
| 中国雷达解码图 | 图片缓存里两张 `MemoryImage`；每张 `sizeBytes = 24,912,008`，共 **47.52 MiB** | PNG 压缩数据只有约 0.12 MiB，但解码像素占用大。新图进入后旧图还在全局 ImageCache。应释放本图层已替换、已脱离显示的旧帧，而非清空其他图层缓存。 |
| 未启用的自定义背景 | `_useCustom == false`，但 `_customBytes.length == 6,820,462`，即 **6.50 MiB** | Provider 初始化仍读入保存的自定义图片；当前未启用也保留字节。应仅在启用或打开对应预览时读取。 |
| 地图源字符串 | rootBundle 保留 4 个 UTF-16 字符串，字符数分别 872,266 / 226,248 / 201,508 / 204,947，字符数据合计 **2.87 MiB** | 地图已解析并长期保留几何，原始加载字符串仍由 AssetBundle 的 `_stringCache` 持有。解析后可不长期缓存这份文本，不改变源文件或坐标。 |
| 地图投影与不同缩放级别缓存 | 11,918 个 `_ProjectedPolygon`、15,616 个 `_ProjectedPolyline`；确认底图数据及 `_cachedProjectedElements` 的引用链 | 本地 flutter_map 8.3.0 的 `_cachedSimplifiedElements` 按整数 zoom 保存不同结果，未设置条目上限。稳定的底图组件让这些缓存跨缩放保留。可限制工作集并按需重新计算，保持原几何。 |
| Windows 原生模块 | 驻留 image 页约 **99.0 MiB**，另有 mapped 页约 17.3 MiB | 包括 Flutter、显卡驱动、输入法、音频/TTS 和系统 DLL。这不是业务 JSON 的占用；部分页面为系统共享页。不能认为更换数据处理语言即可全部消除。 |

### 雷达的另一项开销

`FanRadarService._decodeFrame` 先调用 `ui.instantiateImageCodec` 完整解码一帧以校验，再 dispose；地图的 `MemoryImage` 显示时再解码同一份 PNG。这条路径已在代码中确认，会增加解码工作和瞬时分配。本次没有对它的 CPU 成本或瞬时 RSS 增量单独计时，不能将单帧缓存大小直接当成第二次解码的实际峰值增量。

缓存中的雷达图片通过 `_QuakeMapViewState._fanRadarLayerRevision` 的引用链确认，与未启用的自定义背景是两个独立来源。桌面 ImageCache 的配置上限为 80 MiB；这是上限，不是固定占用。

### 不应误算的部分

- `BasemapTileCache._byteCount == 0`、`_tiles.length == 0`。其 32 MiB 配置上限本次没有实际占用。
- GC 后主业务组堆约 142.33 MiB，external 约 5.16 MiB；**包含 NIED**，并非排除了 NIED 的总量。
- 全堆 `LatLng` 对象浅大小约 4.39 MiB、`Offset` 约 8.40 MiB。这里包括地图和 UI 坐标，不能把全部 Offset 都记作底图，也不能将这些数值视为地图完整占用。
- `_TimedSignal` 的抽样引用链指向 `NiedSourceEstimationDriver.stationTriggerDetector`，属于 NIED；不能重新归到“其他来源”。
- 当前没有证据将剩余原生 private 驻留页逐项归到 Skia、音频或某个订阅源。原生分配和系统驻留页统计尚不是完整的组件账本。

## 证据与可复现路径

主诊断目录：`D:/flutterApp/flutter-memory-audit/20261010-211202`。

- `owners.json`：GC 后对象统计、缓存字段、匿名化引用链。不记录源字符串内容。
- `cache-details.json`、`cache-details-final.json`：图片缓存实际条目、每帧字节数、背景开关和原文缓存长度。
- `history-payloads.json`：根据历史索引逐个读取原始磁盘记录，按来源统计报文及原文容器数量。
- `globalquake-payload-heap.json`：使用相同 Dart SDK，预热后对原始 GlobalQuake payload 做同一 `snapshotSourcePayload` 操作，分别 GC 测量。32.92 MiB 是独立还原实验的堆差，**不是对正在运行 APP 做移除前后的 RSS 差**。
- `resident-pages.json`：Windows QueryWorkingSet / VirtualQueryEx 的只读采样。采样非原子，有部分页面在查询期间失效；各分类不保证与另一时刻的 RSS 严格相等。
- `runtime/runtime-snapshots.jsonl`：独立运行过程的 RSS、帧耗时和布局错误记录。本次没有记录到布局错误。

诊断脚本在忽略的 `build/performance` 目录。对照程序使用的副本及本次诊断输出保留，诊断进程已关闭。

## 优化顺序

1. GlobalQuake 历史原文改为按需恢复，原报文逐字保留在磁盘；活动事件和回放仍使用完整原文。
2. 雷达复用解码结果，限制本图层旧帧的保留周期，保留当前帧及切换所需的短暂过渡。
3. 自定义背景按需读取；底图源文本不重复长期驻留。
4. 限制底图多 zoom 投影结果的缓存工作集，再测 CPU、帧耗时与 RSS 是否改善。

以上先解决对象生命周期及缓存。现有证据不足以认定需将所有数据处理迁移到 Rust/C++；语言迁移应由这些改动后的剩余热点决定。
