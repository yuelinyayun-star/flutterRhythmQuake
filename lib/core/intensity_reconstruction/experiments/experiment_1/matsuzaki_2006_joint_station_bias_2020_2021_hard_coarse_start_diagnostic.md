# 松崎式联合定位硬域粗起点诊断：2020/2021

## 状态和边界

这是 `EXP1-DEC-056` 之后的策略交叉验证，不是生产算法评估，也不是新的参数选择。
2020 和 2021 使用现有年度输入与同一冻结协议重放；目录真值只在搜索完成后用于误差
比较，不参与输入构建、测站选择、候选评分或搜索过程。

本次只改变第一阶段的初始水平窗口：从原来的局部锚点窗口改为原始硬矩形域的
`0.5°/0.5°/20 km` 粗网格。后续两阶段、候选排序、震级搜索、250 km 径向约束和候选
预算保持不变。无站项和冻结站项路径分别比较，站项仍为冻结的 `k=2`。

## 输入和机器报告

年度输入：

```text
tmp/jma_intensity_pretraining/jma_final_intensity_2020.json
tmp/jma_intensity_pretraining/jma_final_intensity_2021.json
```

每年先生成同协议的无站项与冻结站项基线，再由诊断工具重放硬域粗起点：

```text
.dart_tool/matsuzaki_2006_archive_joint_evaluation_2020_strategy_crosscheck_no_bias/report.json
.dart_tool/matsuzaki_2006_archive_joint_evaluation_2020_strategy_crosscheck_station_bias_k2/report.json
.dart_tool/matsuzaki_2006_joint_station_bias_effect_diagnostic_2020_k2_hard_coarse_start/report.json

.dart_tool/matsuzaki_2006_archive_joint_evaluation_2021_strategy_crosscheck_no_bias/report.json
.dart_tool/matsuzaki_2006_archive_joint_evaluation_2021_strategy_crosscheck_station_bias_k2/report.json
.dart_tool/matsuzaki_2006_joint_station_bias_effect_diagnostic_2021_k2_hard_coarse_start/report.json
```

评估事件数为 2020 年 44 个、2021 年 51 个。两年都没有修改原始 JMA 输入，也没有把
硬域粗起点写入生产搜索器。

## 硬域粗起点相对同路径基线

表中“改善”是硬域粗起点结果的震中误差低于同一年度、同一模型、同一路径的原始起点
结果；中位变化为 `硬域粗起点 - 原始起点`，负值表示改善。

| 年度 | 模型 | 路径 | 震中误差改善 | 中位变化 | P90 变化 | 基线硬边界数 -> 新硬边界数 |
|---|---|---|---:|---:|---:|---:|
| 2020 | `published` | 无站项 | 18/44 | +0.144 km | +1.154 km | 20 -> 21 |
| 2020 | `published` | 冻结站项 | 26/44 | -0.240 km | +0.862 km | 12 -> 13 |
| 2020 | `finiteFaultSemanticFrozen2017` | 无站项 | 20/44 | +0.070 km | +1.286 km | 23 -> 24 |
| 2020 | `finiteFaultSemanticFrozen2017` | 冻结站项 | 16/44 | +0.143 km | +0.966 km | 24 -> 25 |
| 2021 | `published` | 无站项 | 30/51 | -0.101 km | +0.851 km | 23 -> 24 |
| 2021 | `published` | 冻结站项 | 28/51 | -0.025 km | +1.088 km | 18 -> 16 |
| 2021 | `finiteFaultSemanticFrozen2017` | 无站项 | 28/51 | -0.070 km | +0.677 km | 27 -> 27 |
| 2021 | `finiteFaultSemanticFrozen2017` | 冻结站项 | 25/51 | +0.023 km | +1.204 km | 29 -> 26 |

硬域粗起点确实会改变候选落点，但改善不是一致的。最稳定的正向信号只出现在
`published` 的冻结站项路径：2020 和 2021 的震中误差中位数分别下降 `0.240 km` 和
`0.025 km`，但仍分别有 `18/44` 和 `23/51` 个事件没有改善，而且 P90 都上升。
有限断层语义模型的冻结站项路径两年中位数分别恶化 `0.143 km` 和 `0.023 km`。

## 性能和边界

硬域粗起点的第一阶段候选量更大，运行成本上升明显，尤其是无站项路径：

| 年度 | 模型 | 路径 | 原始起点耗时中位数 | 硬域粗起点耗时中位数 | 增量中位数 |
|---|---|---|---:|---:|---:|
| 2020 | `published` | 无站项 | 849 ms | 2190.5 ms | +1238 ms |
| 2020 | `published` | 冻结站项 | 1774 ms | 2301.5 ms | +182 ms |
| 2020 | `finiteFaultSemanticFrozen2017` | 无站项 | 725 ms | 1933.5 ms | +1187.5 ms |
| 2020 | `finiteFaultSemanticFrozen2017` | 冻结站项 | 1457 ms | 2037 ms | +164.5 ms |
| 2021 | `published` | 无站项 | 878 ms | 2072 ms | +933 ms |
| 2021 | `published` | 冻结站项 | 2354 ms | 2440 ms | +28 ms |
| 2021 | `finiteFaultSemanticFrozen2017` | 无站项 | 852 ms | 1967 ms | +1210 ms |
| 2021 | `finiteFaultSemanticFrozen2017` | 冻结站项 | 1994 ms | 1902 ms | +36 ms |

耗时差异受候选路径和早停状态影响，不能把个别冻结站项事件的下降解释为算法整体
加速。硬边界数量也没有一致下降：2020 四条路径均增加 1 个；2021 只有冻结站项
两条路径减少，有限断层无站项不变，`published` 无站项增加 1 个。

## 决策

1. 硬域粗起点是有证据支持的候选覆盖诊断策略，但 2020/2021 没有证明它能稳定降低
   震中误差，也没有证明它改善深度可辨识性或边界问题。
2. 不接入生产，不改变当前初始搜索窗口、站项 `k`、震级范围、深度范围、候选预算或
   边界惩罚。
3. 后续若继续，应预先声明独立事件集合和评价指标，并单独研究“覆盖收益与候选量/耗时”
   的权衡；不能仅凭 `published` 冻结站项路径的中位数改善做全局推广。
