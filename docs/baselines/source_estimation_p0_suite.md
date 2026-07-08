# 震源估算 P0 批量基线

> 基线日期：2026-06-20  
> 套件：`source_estimation_p0`  
> 状态：2个事件窗口 + 1个静稳窗口

## 运行方式

```powershell
flutter test test/source_estimation_batch_test.dart --reporter expanded
```

输出：

```text
.dart_tool/source_estimation_benchmark/source_estimation_p0.json
.dart_tool/source_estimation_benchmark/source_estimation_p0.md
.dart_tool/source_estimation_benchmark/cases/<case_id>.json
```

更新仓库内的自动结果表：

```powershell
.\tools\update_source_estimation_baseline.ps1
```

自动结果表：[`source_estimation_p0_suite.generated.md`](source_estimation_p0_suite.generated.md)

套件清单：

- [`test/fixtures/source_estimation/baseline_suite.json`](../../test/fixtures/source_estimation/baseline_suite.json)

## 数据集

| 案例 | 类型 | 窗口 | 帧数 | 真值/分类来源 |
|---|---|---|---:|---|
| 奈良 M3.6 | 事件 | 2026-06-10 18:01:20-18:02:10 JST | 51 | 项目既有回放标签 |
| 萨摩半岛西方冲 M2.6、179 km | 事件 | 2026-06-20 11:50:17-11:52:47 JST | 151 | 用户提供的 EQuake 截图 |
| 2026-06-14 静稳窗口 | 噪声 | 17:55:44-17:56:24 JST | 41 | 41帧在当前检测器下均为 `idle` |

静稳窗口只用于回归检测“是否错误输出震中”。它没有经过外部地震目录排除，因此不能表述为严格意义上的无地震真值。

## 批量结果

| 方法 | 有输出事件/事件总数 | 漏估事件 | 静稳误报帧/总帧 | 有输出事件的中位误差 | P90误差 |
|---|---:|---:|---:|---:|---:|
| `weighted_centroid_baseline` | 1/2 | 1 | 0/41 | 210 km | 236.8 km |
| `nied_gif_hybrid_v1` | 1/2 | 1 | 0/41 | 646 km | 737 km |
| `scratch_scan_v1` | 1/2 | 1 | 0/41 | 48 km | 65 km |

误差分位数只来自有输出的奈良事件。萨摩事件完全没有输出，不能把它计为零误差，也不能从误差集合中无说明地删除；因此批量报告单独记录：

```text
eventCasesWithEstimates = 1
missedEventCaseCount = 1
eventCaseDetectionRate = 0.5
```

## 萨摩深源事件

事件标签：

```text
2026-06-20 11:50:47 JST
31.11 N, 130.06 E
M2.6
深度 179 km
```

151帧全部成功解码，但三种算法均无输出。原因是当前震源估算依赖正式检测阶段或至少三个活动台站；这组深源小震的地表实时震度没有满足对应门槛。

这个结果说明后续必须把两个指标分开：

1. 检测器是否建立事件；
2. 已建立事件时，震源估算是否准确。

只优化第二项无法覆盖此类深源弱事件。

## 当前结论

- 批量入口已经能够读取多个案例清单并生成总体与逐案例 JSON。
- 当前三个方法在静稳窗口均未误报。
- 当前方法对2个事件只覆盖1个，事件覆盖率为50%。
- 当前混合算法在唯一有输出的奈良事件上显著劣于旧 Scratch。
- 样本量仍然太小，不能据此调整模型参数。

## 下一步

P0 剩余工作：

1. 再补至少一个能够触发的海域事件；
2. 固定事件级评测规则后进入 P1 扩充数据集。

已完成的测试基础清理：

- 所有回放测试不再包含开发机绝对路径；
- GIF 解码、时间键、压缩 JSON 读取和 Yahoo 台站映射统一到
  [`test/support/nied_replay_fixture.dart`](../../test/support/nied_replay_fixture.dart)；
- 当前基准器和旧诊断测试共享同一读取实现。
