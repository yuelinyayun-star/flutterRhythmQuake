# 2026-10-11 安装包与图形内存核验

保留 Flutter 3.41.1 / Dart 3.11.0。安装包使用现有 personal 配置、版本 1.0.5+22。构建与测量均在隔离项目进行，使用原安装数据副本和真实实时来源。本轮没有新增生产缓存限制或改动原始观测数据。

## 安装包

| 平台 | 文件 | 大小 | SHA-256 |
| --- | --- | ---: | --- |
| Windows x64 | `build/installer/RhythmQuake_Setup_1.0.5.22_personal_x64.exe` | 34,356,870 字节，32.77 MiB | `366090559a1724085e23a95891f04105874f131c8eff5b46ef6e481dd999b328` |
| Android | `build/installer/RhythmQuake_1.0.5.22_personal.apk` | 114,516,250 字节，109.21 MiB | `4e1f40caee26c682ade1eeae355c7264e3530414fb4a30e24a6dcc87f84dcbd4` |

- Windows 经项目 Inno Setup 安装器流程产出，120 个运行文件的长度及 SHA-256 核验通过，包含上一轮 COM 音频引用修复。
- APK 的包名为 `com.example.flutterrhythmquake`，versionName 1.0.5、versionCode 22、minSdk 24、targetSdk 36；apksigner 验证通过，使用现有 v2 签名配置。
- Android 首次构建未产出完整 APK，日志显示 C: Pub Cache 与 D: 构建目录之间的 Kotlin 增量缓存错误。仅在隔离项目关闭 Kotlin 增量缓存、使用 in-process 编译后重试成功；原仓库 gradle.properties 没有修改。
- 旧包保存在 `D:/flutterApp/flutter-packaging/20261010-225437/previous-packages`。同目录的 `verified-packages.json` 保存最终核验结果；686 个构建源码文件与当前仓库逐个比较，哈希一致。
- 没有运行安装器、替换用户安装目录、升级 SDK 或发布 GitHub。

## 正常运行与采集边界

诊断程序及证据位于 `D:/flutterApp/flutter-memory-graphics/20261011-132310`。先运行 90 秒，未连接 VM service 查询对象；去掉启动前 30 秒后，RSS 为 **340.10～378.04 MiB，平均 360.49 MiB**，private commit 平均 444.08 MiB。private commit 是提交量，RSS 是驻留量，二者不能混用。

该次实时来源、窗口和时段与上一轮不同，不能将本轮均值与上一轮均值的差当成优化收益。随后启用 VM service、堆枚举及 CPU profiler 的诊断开销也不属于这段正常采样。

## 图形对象与引擎计数

在创建入口安装弱引用记录，不延长 Image / Picture 的生命周期；Image 用 isCloneOf 去重。记录期间：

- 始终只有 **1 张独立图片**，3 个句柄指向同一张 2882×2161 雷达图，RGBA32 像素量为 24,912,008 字节，约 **23.76 MiB**。这是像素量估计，不代表包含 GPU 副本的完整成本。
- 存活 Picture 为 **37～42 个**，approximateBytesUsed 峰值约 **0.40 MiB**；这项只表示绘图指令估计，不包含所引用图片或 GPU 缓存。
- Profile 引擎真实 RasterCache 计数为 **0.41～11.72 MiB**，随画面变化；没有观察到这些存活对象数量持续累积。

对应固定引擎 `3452d735bd38224ef2db85ca763d862d6326b17f` 的 [RasterCache 源码](https://raw.githubusercontent.com/flutter/flutter/3452d735bd38224ef2db85ca763d862d6326b17f/engine/src/flutter/flow/raster_cache.cc)提供 Layer/Picture 计数；[Shell 源码](https://raw.githubusercontent.com/flutter/flutter/3452d735bd38224ef2db85ca763d862d6326b17f/engine/src/flutter/shell/common/shell.cc)提供资源缓存上限消息及视口预算公式。资源缓存预算与 RasterCache 实际计数不是同一项。

## 缓存上限对照

同一诊断进程依次测试默认、32 MiB、16 MiB、恢复视口预算。窗口物理尺寸 1582×853、DPR 1.25；视口预算为 64,773,408 字节，约 61.77 MiB。各阶段均在采集完成后等待并记录正常帧时间。

| 阶段 | RSS 均值 MiB | private commit 均值 MiB | Raster P95 ms | 专用显存均值 MiB |
| --- | ---: | ---: | ---: | ---: |
| 默认，已连接 VM | 377.07 | 432.41 | 9.78 | 91.11 |
| 上限 32 MiB | 384.86 | 450.02 | 17.58 | 100.38 |
| 上限 16 MiB | 394.23 | 475.31 | 19.03 | 113.86 |
| 恢复视口预算 | 379.18 | 454.86 | 14.69 | 104.82 |

这是真实实时运行的顺序对照，画面与来源会变化，不能由这张表断言降低上限造成内存或耗时增加。但它**没有证明限制缓存有稳定收益**，因此没有写入生产 APP。专用显存由 Windows GPU Process Memory 按诊断 PID 读取，不属于进程 RSS，不能相加解释系统内存。

## 剩余占用与 CPU 线索

- 上述对照结束后，GC 得到业务 isolate group 堆使用 **92,521,904 字节，约 88.24 MiB**，externalUsage 5,786,432 字节，约 5.52 MiB。多个业务 isolate 共享堆，不能重复相加。
- Windows 驻留页分类读到 image 页约 **86.95 MiB**、mapped 页约 **12.61 MiB**，包括 Flutter、NVIDIA 驱动、Media Foundation、TTS 等。部分页面共享；驻留页枚举非原子，不能和另一时刻 RSS 严格相加。
- 匿名 private 页没有获得逐分配调用栈，尚不能全部归属给某个插件或数据源。没有将它们直接判为泄漏。
- CPU profiler 原先关闭，单独为 10 秒 CPU 采样启用，结束恢复原值。主 isolate 有 924 个样本，NIED 图像 worker 38、NIED 估算 worker 50、P-Alert 估算 worker 37；数量只是该采样窗口的样本量，不是组件内存大小。
- 主线程样本包含测站更新、processSampledFrame、updateFromContinuousShindo、异常站及 ascend 判断；P-Alert worker 样本包含 NumberFormat 构造与格式化。它们提供下一轮定位入口，尚无独立前后对照证明具体优化收益。
- 最后 Flutter 错误记录为空。只关闭了本轮创建、路径核验相符的诊断 APP。

证据文件：`os-snapshots.jsonl`、`stage-summary.json`、`combined-summary.json`、`gpu-snapshots.jsonl`、`*-engine.json`、`heap.json`、`pages-before-heap.json`、`cpu-enabled.json`、`binary-manifest.json`、`diagnostic-source/`、`cleanup.json`。CPU profiler 在缓存对照及堆采样之后启用，其后增加的诊断内存没有用于宣称 APP 占用或缓存收益。
