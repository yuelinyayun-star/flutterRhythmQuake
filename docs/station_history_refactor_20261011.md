# 2026-10-11 测站历史扫描优化

保留 Flutter 3.41.1。修改前源码保存在 `D:/flutterApp/flutter-history-refactor/20261011-141319/backup`，其中 nied_monitor.dart 的 SHA-256 为 `76c6f17cb6948ca692cbfd9f291bd3dc62277a347665b0771a3de8c1ac797fec`。本轮基线已包含上一轮 P-Alert 布局与 NIED 重复观测对象优化。

## 修改

- `_calcAscend` 原本先 contains 检查缺测，再从头遍历一次处理缺测。现在使用首个缺测位置，从该位置开始原有补缺测运算；无缺测时直接进入原有上升量计算。
- `_isAbnormalStation` 原本在缺测时分配过滤后的列表。现在按原顺序直接读取有效级别，用寻找谷底、上升、下降三个阶段保留原峰值判断；确认三个完整峰后即可返回。
- 原始测站历史、缺测值、显示保持窗口、触发时间、异常隔离 600 次更新、活动值及阈值均沿用原流程。历史列表的存储方式和对外接口没有修改。

## 验证

同一 Windows Profile 二进制同时包含修改前冻结实现与当前实现。读取奈良原始 GIF `20260610180120.lmoni.jma_s.gif` 至 `20260610180210.lmoni.jma_s.gif`，共 51 帧、1634 站；83,334 条测站动态状态逐条一致，包含历史、级别、ascend、triggerStamp、activity、异常计数、检测状态、观测物理字段与质量标记。原 GIF 文件逐个保存 SHA-256，测量后重新核验未修改。

这段原始数据的异常站检查原本创建 3,359 个缺测过滤列表，现在为零。仍需执行原来的短缺测补齐副本，没有将全部历史分配归零。

预热后交替顺序执行八轮，计时覆盖 51 帧的测站观测写入与 updateFromContinuousShindo，不包含 GIF 解码、数据下载、绘制或首次创建测站：

| 轮次 | 原实现 ms | 当前实现 ms |
| --- | ---: | ---: |
| 1 | 75.272 | 55.440 |
| 2 | 81.198 | 50.130 |
| 3 | 79.972 | 51.694 |
| 4 | 82.057 | 53.109 |
| 5 | 79.470 | 51.810 |
| 6 | 98.678 | 54.143 |
| 7 | 90.161 | 57.433 |
| 8 | 73.636 | 49.610 |

平均 **82.5555 ms → 52.921125 ms，减少 35.90%**。这是测站更新组件耗时，不是完整 APP 的加速或内存降幅。

另外从修改前后源码提取原方法进行受控算法边界对照：枚举长度 0–8、值域 [-1, 0, 2, 3, 6]，488,281 种历史的异常判断相同；结合过期窗口 0/1/2/10 和当前级别 0/20，3,906,248 次上升量及时间戳比较相同，输入列表保持原样。此项为受控边界测试，不作为真实上游采样。

9 个相关测试文件共 65 项通过，覆盖缺测、平台值、历史末端第三峰、异常隔离、快照、恢复、物理层、冷启动、后台 worker 和 P-Alert；两个修改文件静态分析无问题，diff 空白检查通过。Windows Profile 编译及原始数据对照实际运行成功，stderr 为空。

证据包含本目录外上述备份根目录的 `profile-results.json`、`boundary_check.dart`、`boundary-check.log`、`diagnostic-source/`、`binary-manifest.json`、`history-tests.log`、`history-integration-tests.log` 和 `history-analyze.log`。

## 完整 APP 后续检查

使用当前全部 lib 源码另行编译完整 APP Profile 程序，与个人安装配置的隔离副本运行；编译前逐个确认隔离项目 lib 与工作区源码字节一致。正常运行每 5 秒记录一次，共 24 次，排除前 30 秒启动期后 RSS **346.91–371.09 MiB，平均 359.88 MiB**，CPU 为全机逻辑核口径约 4.94%。采样完成后才连接 VM 请求 GC、枚举对象和 CPU 诊断，因此基线没有包含这些诊断引起的额外内存。

上一轮正常采样 RSS 平均约 360.49 MiB；两轮使用实时数据、观察时长和视角不同，不能把差值当作优化收益。本轮没有测得完整 APP RSS 显著下降。

GC 后 Dart 堆 100.23 MiB、外部内存 5.21 MiB。其中 Offset 237,119 个、7,587,808 字节（7.24 MiB）；随后抽样多数持有链指向 `_ProjectedPolyline.points` 和 `_ProjectedPolygon.points`。读到当前底图 `_windowZoom` 为 3，图层各自 `_cachedSimplifiedElements` 的长度均为 1。确认有地图投影占用，但未获得简化缓存无界增长的证据，没有据此修改地图精度或缓存策略。

完整 APP 采样没有记录到 Flutter 布局异常。10 秒 CPU 采样中主 isolate 有 140 个样本，NIED 图片 worker 4 个、震源 worker 8 个；这些是当时的实时工作量，不与上一轮不同窗口直接计算加速倍数。P-Alert 震源 worker 当时样本为零，不能据此断言其后续所有开销已消失。

完整 APP 证据：`full-app-binary/`、`full-app-binary-manifest.json`、`full-app-build.log`、`full-app-measurement/baseline.jsonl`、`baseline-summary.json`、`heap.json`、`cpu.json`、`offset-owners-spaced.json`、`map-state.json` 及运行快照。最初较大对象抽样使默认 VM 对象 ID 过期；改用容量 32,768 的专用 ID zone 后成功取得持有链并删除该 zone。失败日志单独保留，没有将失败抽样作为证据。

此前 1.0.5+22 personal 安装包不包含本轮或上一轮新增 CPU 优化。本轮没有更新安装包、SDK 或云端代码。
