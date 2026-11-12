# 2026-10-11 测站数据处理重构

保留 Flutter 3.41.1 / Dart 3.11.0。本轮从上一轮实际 CPU 样本继续定位，修改前源码和原始上游报文保存在 `D:/flutterApp/flutter-cpu-refactor/20261011-134315`。

## P-Alert 布局判断

原来的主线程检出器与后台震源估算器，都在每帧执行 `stations.map((s) => '${s.id}:${s.coordinate}').join('|')`。当前 latlong2 0.9.1 的 LatLng.toString 每次为经纬度分别构造 NumberFormat；787 站每次布局检查需要 1,574 次格式化器构造，两条路径各检查一次时合计 3,148 次。

现在两处共用 `PAlertStationLayout`，只保留站号与不可变原始坐标，逐项比较站号、经纬度及顺序；只有站点布局变化时才重新保存布局和建立邻接关系。PGA、PGV、报文时间、检出门槛及震源算法沿用原流程。坐标判断不再依赖显示字符串的舍入精度。

通过现有 APP 相同 GraphQL 查询、请求头、TWCA 根证书和代理，保存了 787 站原始目录与 12 份原始 PGA/PGV 响应。原始响应字节未修改，记录时间与 SHA-256 保存在 `original-manifest.json`。

使用同一 Windows Profile 二进制同时包含修改前冻结实现和修改后实现，重放这 12 份报文：检出阶段、计数、检测站、格点、确认烈度及震源输出均一致。这份实时采样中的震源输出为空，没有把安静数据改造成告警来测试；已有受控告警回归另外验证触发、过期及 worker 重置行为。

787 站不变布局的检查，先预热，再交替顺序执行四轮，每轮各 200 次：

| 轮次 | 原实现总耗时 ms | 新实现总耗时 ms |
| --- | ---: | ---: |
| 1 | 1217.479 | 1.661 |
| 2 | 1200.024 | 1.726 |
| 3 | 1193.713 | 1.958 |
| 4 | 1173.256 | 1.888 |

平均每次检查由 **5.98059 ms 降至 0.00904125 ms**。这是布局判断的组件耗时，不是整个 APP 或整个检出流程的加速倍数；测量不包含首次建立邻接关系。

## NIED 重复观测对象

图片处理先通过 updateGifObservation 写入不可变 NiedGifObservation，再通过 updateFromContinuousShindo 更新检测状态。后者原本将同一震度再次 copyWith，产生数值相同的观测对象。

现在 continuousShindo setter 遇到已存储的相同 double 值时保留现有观测对象。数值真正变化时仍执行原更新；检测级别、历史、异常站判断、ascend、triggerStamp、activity 及缺测处理继续执行。

修改前后在同一 Profile 程序中读取原始奈良 GIF 时间窗 `20260610180120` 至 `20260610180210`：

- 51 张原始 GIF、当前目录 1634 站，逐条比较 **83,334 条动态测站状态**，全部一致。
- 对照包含级别、历史、异常计数、ascend、triggerStamp、activity、检测状态/原因、观测各物理字段和质量标记。
- 原实现产生 **80,299 次重复观测对象复制**，新实现为 **0 次**。
- 原始 GIF 与 P-Alert 响应在测量后重新计算哈希，全部保持原样。

## 验证与边界

- 10 个相关测试文件共 **80 项测试通过**；另有冻结实现的原始数据对照程序检查通过。
- 原 NIED 快照测试写死 1630 站，与当前 `nied_scan_1634_20261004_v2` 目录不一致，现改为逐个比较原目录站号，继续检查所有站的快照字段，没有减少站数。
- 修改的四个生产文件及快照测试静态分析无问题，diff 空白检查通过。Windows Profile 编译与实际运行通过，stderr 为空。
- 对照采集程序最初把目录全部 71 帧当成 51 帧，以及动态调用枚举 name，分别导致采集失败；修正后先通过采集程序自身测试，再运行最终 Profile 测量。失败日志和二进制单独保留，没有将失败结果作为收益证据。
- **尚未测定这轮改动对完整 APP 常态 RSS 的降幅**。这些结果证明重复格式化与对象分配减少，不能换算成释放数百 MiB，也没有将其它未归属的原生内存判为已修复。
- 本轮仅编译了验证程序；此前 1.0.5+22 personal 安装包不包含这轮新增改动。

生产改动：`lib/services/sources/palert_station_layout.dart`、`palert_detection.dart`、`palert_source_estimation.dart`、`nied_monitor.dart`。验证证据：上述目录的 `profile-results.json`、`verified-summary.json`、`current-source-manifest.json`、`final-regression.log`、`diagnostic-check.log`、`diagnostic-source/`、`binary-manifest.json`、`backup/` 和原始报文。
