# 震源估算实施路线图

> 状态：P1 进行中
> 更新日期：2026-07-18
> 研究依据：[`source_estimation_research.md`](source_estimation_research.md)

## 1. 总体目标

建立一套可回放、可标定、可比较的实时震中估算框架，并在此基础上增加独立的 PLUM 类强震动预测能力。

实施原则：

1. 先冻结数据与基线，再改算法。
2. 所有结论以多事件回放指标为依据，不以单个案例截图为依据。
3. 震中估算与强震动预测分开建模、分开评价。
4. 产品输出不超过数据本身的可识别能力。
5. 新算法必须可以通过配置切回旧基线。

## 2. 完成定义

震中估算第一阶段完成需同时满足：

- 有可重复的事件回放数据格式和命令；
- 有冻结的旧算法基线报告；
- 不再重复使用伪 PGA/PGV/PGD；
- 新模型同时使用震度、到达时间区间和未触发台站；
- 输出 P50/P90 水平不确定度；
- 在独立测试事件上优于旧算法；
- 每帧 P95 计算时间满足 1 秒更新周期；
- 地图和调试页能明确显示方法版本及质量状态。

PLUM 第一阶段完成需满足：

- 不依赖当前震中估算结果；
- 能在回放中输出逐秒预测震度场；
- 以目标站点提前量、漏报率和误报率独立验收。

## 3. 阶段规划

### P0：冻结现状与接口

当前进度：

- [x] 建立 GIF 逐帧统一基准器；
- [x] 隔离运行加权质心、当前混合算法和旧 Scratch 算法；
- [x] 定义首个事件清单并生成逐帧 JSON 报告；
- [x] 冻结奈良 M3.6 单事件基线；
- [x] 建立多清单批量运行与总体汇总；
- [x] 接入萨摩半岛西方冲深源事件与静稳窗口；
- [x] 清除回放测试中的绝对路径并统一 GIF/JSON/Yahoo 读取代码；
- [x] 增加参数化 NIED GIF 窗口捕获脚本；
- [x] 将批量套件结果表改为测试自动生成；
- [x] 补充能够触发正式检测阶段的茨城县冲海域事件。

捕获脚本：

```powershell
.\tools\capture_nied_gif_window.ps1 `
  -OriginTime "2026-06-20T10:50:47+08:00" `
  -CaseId "20260620_satsuma_m26_d179" `
  -Latitude 31.11 -Longitude 130.06 `
  -DepthKm 179 -Magnitude 2.6 `
  -Region "薩摩半島西方沖"
```

`OriginTime` 必须包含显式 UTC 偏移。脚本统一换算为 JST 后生成 NIED 文件名；
例如 `10:50:47+08:00` 对应 `11:50:47+09:00`。禁止传入无偏移本地时间。

上游历史图像保留期较短。发现合适事件后应尽快捕获，不应等到后续开发阶段再补数据。

首份报告：[`docs/baselines/source_estimation_20260610_nara_m36.md`](baselines/source_estimation_20260610_nara_m36.md)

批量报告：[`docs/baselines/source_estimation_p0_suite.md`](baselines/source_estimation_p0_suite.md)

自动结果表：[`docs/baselines/source_estimation_p0_suite.generated.md`](baselines/source_estimation_p0_suite.generated.md)

目标：把当前实现固定成可比较基线。

任务：

- 为 `weighted_centroid_baseline`、`nied_gif_hybrid_v1` 和旧 `HypocenterEstimator` 建立统一回放入口；
- 固定 `SourceEstimationRequest`、`SourceEstimate` 和诊断字段快照；
- 记录每个模型版本、参数和输入数据版本；
- 输出按帧 CSV/JSON 报告，而不是只在测试中 `print`；
- 确认 GIF 与 Yahoo 路径的行为差异。

产物：

- 基线运行命令；
- 基线事件清单；
- 基线指标报告；
- 模型版本命名规则。

验收门槛：

- 同一数据和配置重复运行结果完全一致；
- CI 测试不依赖开发机绝对路径；
- 至少覆盖一个内陆事件、一个海域事件和一个无事件噪声窗口。

### P0.5：拆分事件检测层

研究结论：[`docs/event_detection_research.md`](event_detection_research.md)

目标：让事件检测独立回答“是否发生同一地震事件”，震源估算只处理已确认事件。

任务：

- [x] 定义单台状态、网络事件和检测器接口；
- [x] 增加旧检测逻辑适配器，并以 shadow 回调暴露独立事件状态；
- [x] 增加震源推算自己的触发门控，只消费 `EventDetection.confirmed/strong`；
- [x] 从 `ShakeDetectionService` 抽出震源推算入口，生产路径改由独立 `NiedSourceEstimationDriver` 驱动；
- [x] 保持旧检测行为作为基线，新检测器先以 shadow mode 运行；
- [x] 将检测召回率、误报率、候选延迟和确认延迟接入批量报告；
- [x] 分开记录检测漏报与已确认事件的震源漏估。
- [x] 定义目录事件、可观测事件、可检出事件标签和检出指标分母。
- [x] 增加震中周边 50/100/160 km 本地可观测性诊断。
- [x] 地图震源标记、自动聚焦和 P/S 波圈改为消费 `StationEventTracker.currentNiedEvent`；
- [x] 删除“最近台站”伪标记，改为显示本事件累计参与推算的台站；
- [x] 依据当前震源解和 JMA2001/JB 走时对触发时刻生成推定 P/S/O 分类，并在 UI 明示它不是真实震相拾取。
- [x] 在左上角 `AlertModule` 统一事件 UI 中显示本地震源报告序号、支持站、累计 P/S/O 和质量等级；
- [x] 质量行显示模型置信度、推定到时 RMS 残差和最大方位缺口，缺失量显示 `--`，不借用正式 EEW 字段。

生产 UI 的本地质量采用保守的最差项分级：模型置信度、关联台站数、推定到时
RMS 残差和最大方位缺口分别映射到 S/A/B/C/D，最终等级取四项中最低等级。
该等级只描述本地模型内部拟合与台网几何，不是 JMA、Hi-net 或 EQuake 官方精度。
P/S 和残差都来自一秒 GIF 阈值到时模型，不是真实波形震相拾取。

验收门槛：

- 检测器不依赖任何震源估算结果；
- 震源估算器不自行创建或合并事件；
- 同一回放可以独立比较检测算法和震源算法；
- UI、通知和震源推算分别消费明确的事件状态。

### P1：建立回放数据集与评测器

目标：让算法决策由事件级数据驱动。

任务：

- [x] 定义标准回放包结构、版本字段和结构验证器；
- [x] 增加实时捕获模式，记录逐图层真实接收完成时刻、重试次数和未校时时钟来源；
- [x] 支持旧捕获目录合成 legacy capture manifest，以迁移奈良和静稳窗口但不伪造接收时间；
- [x] 建立事件级 train/validation/test 清单，并增加测试集泄漏校验；
- [x] 抽出统一指标计算器，固定 percentile 与比例口径；
- [x] 回放 schema 支持保存事件前 30 秒至事件后 120 秒逐秒帧，并记录缺帧；
- [x] 保存缺帧、接收延迟、表层/井下选择和台站质量；
- [x] 实现 split-aware 统一评测器，按 train/validation/test 分别输出 source/detection 指标；
- [x] 建立可版本化的 JMA 最终目录导入、候选匹配和歧义拦截工具；
- [x] 明确 NIED Hi-net 自动震源为 preliminary reference，不与 JMA 最终目录混用；
- [ ] 使用真实冻结目录为现有事件关联 JMA 最终标签；
- [x] 在遵守 NIED 下载与再分发条款的前提下，为近期回放关联 Hi-net preliminary 标签；
- [ ] 扩充到至少 20 个有效地震事件和 10 个噪声窗口。

强震モニタ时间戳图像接口不是长期历史档案，实际只能回溯最近约
60/120 分钟。因此数据集扩充不能采用“事后列出旧事件再批量补抓 GIF”的方式。
正确采集流程是：

1. 常驻抓取 `jma_s/jma_b`，在本地维护至少 120 分钟滚动缓存；
2. 从 Hi-net/JMA/P2P 等事件源收到候选事件后，立即固化事件前后窗口；
3. 事件开始时优先固化缓存中的震前 30 秒，继续采集震后至少 120 秒；
4. 未发生事件的缓存按独立规则抽样为噪声窗口；
5. 超出上游回溯窗口的旧事件只允许使用已有本地 GIF 或正式波形数据，
   不得伪造为完整 GIF 回放。

执行约束补充：

- 用户后续提供的 JMA、Hi-net、EQSC、EQuake 或 P2P 参考事件，只要仍在
  KMoni 公开回放窗口内，第一动作必须是尝试抓取对应时间窗的本地
  `jma_s/jma_b` GIF；
- 只有在 GIF 抓取完成，或已明确超出公开保留窗口、无法再抓的情况下，
  才写入纯文本参考条目、Hi-net/JMA 标签或人工备注；
- 不允许出现“已收到事件文本但未先尝试 GIF 抓取，后续再以缺 GIF 作为事件
  不完整原因”的工作流。

Schema：[`docs/replay_package_schema.md`](replay_package_schema.md)

当前标准包：

- 奈良 M3.6：51 个时间戳，1 个历史缺帧；
- 静稳窗口：41 个时间戳，0 缺帧；
- 萨摩半岛西方冲 M2.6：151 个时间戳，0 缺帧；
- 京都府南部 M1.8：151 个时间戳，0 缺帧；
- 茨城县冲参考事件：151 个时间戳，0 缺帧。
- 岩手县冲参考事件：151 个时间戳，1 个历史缺帧，暂不纳入 split 指标。
- 岩手县冲 M3.3 EQuake 参考事件：151 个时间戳，0 缺帧，暂不纳入 split 指标。

岐阜飞驒 M2.8 报告时间为 `2026-06-20T22:55:39+08:00`，对应 NIED 的
`2026-06-20T23:55:39+09:00`。首次手工抓取误将 UTC+8 当作 JST，且发现错误时
已超出上游回溯窗口，因此该事件没有有效 GIF 包，不得进入事件或噪声数据集。
误抓窗口仅保留在 `tmp/quarantine/` 供审计。捕获脚本现强制要求显式 UTC 偏移并
统一换算为 JST。

所有包均含 2 个图层和 1749 台站快照。当前使用 `flat_capture_v1` 兼容原始平铺 GIF；逐帧 `receivedAt` 在旧捕获中不可恢复，明确记为未知。实时捕获模式只在新空目录中记录真实接收完成时刻。

岩手县冲参考诊断：[`docs/baselines/iwate_offshore_m34_reference.md`](baselines/iwate_offshore_m34_reference.md)

当前 split：

```text
train:      奈良、静稳窗口
validation: 萨摩、京都
test:       茨城县冲参考事件
```

该 split 目前只用于防止流程泄漏；样本量太少，不能用于声明算法优劣。

split-aware 评测命令：

```powershell
flutter test test/split_aware_replay_benchmark_test.dart
```

输出目录：

```text
.dart_tool/split_aware_replay_benchmark/
  summary.json
  summary.md
  train/source.json
  train/detection.json
  validation/source.json
  validation/detection.json
  test/source.json
  test/detection.json
```

建议回放包：

```text
replay/<event_id>/
  manifest.json
  truth.json
  stations.json
  frames/<timestamp>.json.zst
  raw/jma_s/*.gif        # 可选，仅用于重新解码
  raw/jma_b/*.gif        # 可选，仅用于重新解码
```

`manifest.json` 至少记录：

```text
schemaVersion
decoderVersion
stationDbVersion
startTime / endTime
expectedFrameInterval
missingFrames
sourceUrls
sensorSelectionPolicy
```

验收门槛：

- 初始不少于 20 个有效地震事件和 10 个噪声窗口；
- 测试集事件在参数标定过程中不可见；
- 评测器输出中位数、P90、时间分段误差、跳动和耗时。

### P1.5：历史震度与波形域预训练

详细规划：
[`docs/source_estimation_pretraining_plan.md`](source_estimation_pretraining_plan.md)

目标：在真实 GIF 事件不足时，先学习静态震度衰减、台站偏差和波形触发特征，
再使用真实 GIF 精调实时行为。

任务：

- [x] 完成数据来源、域标签、训练边界和验收指标规划；
- [x] 实现 JMA 年度震度数据与观测点表解析器；
- [x] 构建 `jma_final_intensity` 静态事件包和质量报告；
- [x] 按 2020/2021/2022 年冻结 train/validation/test 事件级 split；
- [x] 实现可复现的 20%/50%/80% 台站遮蔽和 `synthetic_reveal` 生成器；
- [x] 训练并在 validation 评测 P3 静态震度衰减 v1 基线；
- [x] 实现 K-NET/KiK-net ASCII/CSV 三分量波形解析器；
- [x] 生成逐秒 PGA、PGV、实时震度近似和触发特征 v1；
- [x] 区分 K-NET 地表、KiK-net 地表和井下角色；
- [x] 建立 K-NET/KiK-net 下载清单与 GIF/波形域对齐工具；
- [x] 填入第一批真实 K-NET/KiK-net 事件候选并生成下载 manifest；
- [x] 下载正式波形并生成第一批波形特征包；
- [x] 建立波形域训练索引；
- [x] 构建 `waveform_projected_gif` 投影数据集；
- [x] 基于 `waveform_projected_gif` 建立事件级留一秒级台站震度场基线；
- [x] 用统一时序缓冲实现历史峰值/相对到时约束并复跑留一评估；
- [ ] 真实同域事件出现后生成第一批 GIF/波形对齐报告；
- [ ] 用冻结 GIF train/validation 集精调，用 test 集做最终评测。

说明：

- 顶层 Hi-net preliminary 标签项已完成到 `accepted_constrained_reference`
  证据层，并已传播到 split readiness；这不等于 JMA final catalog truth，
  也不等于已经进入 metric-bearing ready。
- 当前 P1.5 的真实 GIF/波形对齐仍缺“同一事件同时具备本地 capture 包与正式
  K-NET/KiK-net 波形特征包”的重叠资产。现阶段先补齐本地 GIF 逐秒观测导出工具，
  一旦同域正式波形到位即可直接运行对齐报告。
- 当前 readiness 基线见
  [`docs/baselines/knet_gif_waveform_alignment_readiness.generated.md`](baselines/knet_gif_waveform_alignment_readiness.generated.md)：
  20 个本地 capture fixture 中已有 8 个进入 waveform candidate 清单，但这 8 个
  目前全部仍是 provisional directory id，尚无正式波形特征包；其余 12 个本地
  capture 仍处于 `capture_only_needs_waveform_candidate`。
- 目录号确认工单见
  [`docs/baselines/knet_waveform_directory_id_confirmation_worklist.generated.md`](baselines/knet_waveform_directory_id_confirmation_worklist.generated.md)：
  这是当前的直接操作入口，先确认这 8 个 provisional overlap 的正式
  NIED directory id。
- 当前已经确认并落地了 2 个官方 CSV 波形样本：
  `20260624_fukushima_aizu_m32_jma_eq5` -> `20260624132400`，
  `20260626_yamanashi_east_fuji_five_lakes_m56_jma_equake21` ->
  `20260626222900`。对应特征包和
  [`docs/baselines/knet_confirmation_alignment_readiness.generated.md`](baselines/knet_confirmation_alignment_readiness.generated.md)
  已生成；其余 6 个 provisional overlap 仍保留在确认队列中。
- 这两条已确认样本的 GIF / waveform 对齐结果已生成：
  [`docs/baselines/knet_confirmation_alignment_report.generated.md`](baselines/knet_confirmation_alignment_report.generated.md)。
  这意味着当前已经走通“确认目录 ID -> 下载官方 CSV 波形 -> 导出 GIF
  观察 -> 生成对齐报告”的完整诊断链路。
- 官方强震记录检索的汇总见
  [`docs/baselines/knet_official_search_review.generated.md`](baselines/knet_official_search_review.generated.md)：
  这次窗口内共返回 8 条官方行，其中 2 条和本地 capture 对上，
  其余 6 条在当前窗口里没有对应行，暂时保留为 unresolved。
- 这 6 条 unresolved 事件已收敛到
  [`docs/baselines/knet_official_unresolved_queue.generated.md`](baselines/knet_official_unresolved_queue.generated.md)：
  后续如果找到另一个 authoritative source，再回到这份队列里做同事件补全。
- 因此下一步优先级明确为：
  1. 先确认这 8 个 provisional overlap 的正式 NIED directory id，优先
     Fukushima Aizu `2026-06-24/27`、Yamanashi `2026-06-26` 序列、Kushiro
     `2026-06-22`、Iwate `2026-06-21/25/28`；
  2. 再把剩余仍未入清单的高价值本地 capture 继续补入 waveform candidate 清单；
  3. 同域正式波形一旦下载成功，立即生成 feature 包并跑第一批真实
     GIF/波形对齐报告。

禁止事项：

- 不把 JMA 最终峰值震度当作真实一秒时序；
- 不把理论走时揭示当作真实触发时间；
- 不把 K-NET/KiK-net 已发布台站当作全网未触发状态；
- 不把 `waveform_projected_gif` 当作真实强震モニタ GIF；
- 不把真实 PGA/PGV 压缩成 GIF 颜色后丢弃原始物理量；
- 不把同一事件的波形、震度和 GIF 派生样本分到不同 split。

验收门槛：

- 数据域和时间语义可从 manifest 明确识别；
- 静态预训练验证集优于加权质心；
- 波形派生量有版本、单位和质量标志；
- synthetic 数据不进入真实检测延迟和 P/S 到时指标；
- GIF 精调前后均保留冻结基线和独立测试集结果。

### P2：修正数据模型

目标：为概率模型提供语义正确、可追溯的输入。

任务：

- [x] 为每站增加 60 秒环形观测缓冲；
- [x] 明确区分 `dataTime`、`receivedAt` 和状态首次观察时间；
- [x] 把首次上升和触发表示为时间区间；
- [x] 记录每帧缺失、陈旧、像素不可解码等质量标志；
- [x] 从震源估算请求中移除派生 PGA/PGV/PGD，并只接受带独立图层来源的物理量；
- [x] 保留事件中已经结束台站的历史，避免有效证据随状态退出而消失；
- [x] 明确 K-NET 地表与 KiK-net 井下角色。

建议新增概念：

```text
StationObservationFrame
ObservationTimeInterval
StationObservationHistory
ObservationProvenance
SensorSelection
```

验收门槛：

- [x] 单元测试证明同一个 `colorPosition` 不会作为四份独立证据；
- 缺帧不会制造错误触发时间；
- 台站结束后历史记录仍可用于当前事件估算；
- 回放输入能重建完全一致的台站时序。

### P3：震度衰减反演基线

目标：先实现一个统计含义清楚的纯震度模型。

任务：

- 实现位置、发震时刻、等效规模和离散深度类别的候选模型；
- 实现带 `roleBias` 的震度衰减关系；
- 使用 Huber 或 Student-t 损失；
- 保存完整候选分数面；
- 从候选权重计算 P50/P90 水平不确定度；
- 暂不使用触发时间，隔离验证震度证据本身的效果。

JMA-style 传统法诊断：

- 增加一条独立 validation-only 路径：
  `JMA M/depth/source -> 司・翠川 PGV600 -> ARV 地盘增幅 -> 计测震度`；
- 使用 JMA 观测点表近邻 `ARV`，无法 5 km 内匹配时回退 `ARV=1.0`；
- 同时输出 catalog/oracle source 和 P3-estimated-source variant；
- 不含 PLUM；PLUM 仍在 P7 独立实现；
- 该路径只作为传统公式基线和校准参考，不替换 P3，也不进入 UI/通知。

求解器第一版：

```text
区域粗网格 -> 局部细网格 -> 对 sourceScale 解析/一维优化
                    -> 对 depthClass 离散边缘化
```

验收门槛：

- 独立测试集震中误差中位数优于加权质心；
- P90 不劣于 `nied_gif_hybrid_v1`；
- 不确定度覆盖率可计算且随证据增加而收缩；
- 单帧 P95 耗时低于预算。

### P4：加入到达时间与未触发约束

目标：改善事件早期定位并减少错误方向。

任务：

- 实现一秒时间区间似然；
- 标定不同阈值下的 `v_effective` 和时间噪声；
- 将健康但未触发台站作为删失观测；
- 加入数据新鲜度与离线站过滤；
- 通过消融实验分别测量时间项和未触发项的增益；
- 评估海域与台网边缘事件，避免未触发项过度拉回陆地。

验收门槛：

- 5 秒和 10 秒时点误差相对 P3 有稳定改善；
- 海域测试集没有系统性向陆地偏移恶化；
- 噪声窗口错误震中输出率不增加；
- 任一新增项无增益时可单独关闭，而不影响其他项。

### P5：递推估算与稳定性

目标：从逐帧重新搜索升级为连续后验更新。

任务：

- 定义 `SourceEstimatorState`，支持跨帧持有候选分布；
- 评估粒子滤波或保留 top-K 网格候选；
- 实现新证据更新、候选重采样和事件重启；
- 处理同时地震、多簇触发和事件合并/拆分；
- 使用后验更新控制地图跳动，而不是对输出坐标做无依据平滑。

验收门槛：

- 帧间跳动 P90 明显低于 P4；
- 不牺牲最终震中误差；
- 第二事件出现时不会被旧事件后验吞并；
- 相同输入保持确定性，或固定随机种子后确定。

### P6：标定与上线准备

目标：形成可解释、可灰度发布的模型版本。

任务：

- 仅在训练/验证事件上拟合衰减参数、角色偏置和台站偏置；
- 对 P50/P90 覆盖率做校准；
- 分桶报告内陆/海域、浅/深、小/大震性能；
- 定义数据不足、台网外事件和模型失配的降级规则；
- 增加运行时开关、诊断导出和旧算法回退；
- 地图标记改为概率区域，并显示 `beta` 和数据质量。

建议上线门槛在 P1 数据集建立后用基线数值确定，至少应包括：

```text
medianErrorKm <= 基线的 0.8 倍
p90ErrorKm    <= 基线的 0.9 倍
falseEstimateRate 不高于基线
p95RuntimeMs  < 500 ms（桌面参考设备）
P90 区域经验覆盖率接近 90%
```

### P7：PLUM 类强震动预测

目标：不依赖震源估算，提供局地强震动传播结果。

任务：

- 单独定义地面运动场状态和输出接口；
- 使用邻近台站当前震度、距离和时间窗预测目标网格；
- 实现双台站/邻域一致性确认，抑制单站噪声；
- 评估不同传播半径与场地修正；
- 输出预测震度、预计影响时间窗和证据台站；
- 与震中标记分层展示。

验收指标：

- 目标站达到指定震度前的提前量；
- 按震度阈值统计 precision、recall、漏报率；
- 空事件和单站异常的误报率；
- 大震、多重地震与震源失配情况下的稳定性。

当前状态（2026-06-27）：

- 已实现 validation-only 的 PLUM-like 观测摇晃传播诊断：
  `docs/baselines/plum_like_intensity.generated.md`。
- 该路径不使用震源经纬度、深度或震级；输入是 synthetic reveal 中保留的观测台站，
  且排除目标台站本身，避免最终峰值直接泄漏。
- 当前 validation 选择半径 30 km、衰减 0.25 震度 / 10 km、最小证据 1 站；
  `shindo4` 为 57.4% / 78.9% / 66.5%，`shindo5-` 为
  43.8% / 67.4% / 53.1%。
- 已新增组合诊断：
  `docs/baselines/combined_intensity_prediction.generated.md`，比较
  P3 static raw、P3 probability gate、JMA-style P3-source、PLUM-like 和
  `max(JMA-style, PLUM-like)`。
- `max(JMA-style, PLUM-like)` 将最大震度欠报率降到 16.9%，但会牺牲
  `shindo4` precision，因此不能直接作为生产策略。
- 已新增首个真实 replay-frame lead-time 诊断：
  `docs/baselines/plum_like_replay_leadtime.generated.md`。该报告只解码本地
  `jma_s` GIF 帧，按台站阈值首次达到时间计算提前量；当前两案共 451 帧、
  735130 个 station-frame，最高观测震度 1.7。`shindo1` recall 25.0%，
  false-alarm station 6 个；`min_evidence_1/2/3` 在当前小样本上无差异，
  因此误报控制不能只靠证据站数。

下一步：

- 扩大真实 replay-frame 样本，优先加入观测震度 >=2/3 的本地 capture；
- 为 PLUM-like/combined 分支评估邻域一致性、时间持续和静稳窗口误报控制；
- 在这些 validation-only 结果稳定前，不打开 frozen test，也不接 UI/通知。

### P8：条件性数据扩展

以下工作只有在新数据真实性确认后启动：

- 单独抓取并校验真实 PGA 图层；
- 获取真实 PGV/PGD 图层；
- 接入 K-NET/KiK-net 或其他网络连续波形；
- 进行 P/S 自动拾取；
- 评估 FinDer、IPFx 类实现；
- 在事件规模足够后评估 GNN/深度学习模型。

每增加一种观测都必须记录来源、单位、时间窗、传感器位置和解码版本，不能只扩展一个 `double` 字段。

## 4. 建议任务顺序

后续按以下顺序推进，避免算法与数据基础交叉返工：

1. P0：统一回放入口和冻结基线。
2. P0.5：拆分事件检测层并建立独立指标。
3. P1：定义回放格式、评测器和事件清单。
4. P1.5：用历史最终震度和正式波形预训练可迁移参数。
5. P2：增加时序缓冲并修正观测语义。
6. P3：实现纯震度概率反演并加载预训练参数。
7. P4：加入时间区间和未触发台站。
8. P5：递推更新、多事件和稳定性。
9. P6：标定、概率校准和灰度上线。
10. P7：独立实现 PLUM。
11. P8：有新物理量后再评估 FinDer/IPFx。

P0、P0.5 和 P1 的接口、回放与评测基础是必要前置。P1.5 可以与 P1 的真实
GIF 积累并行推进；P2 的统一时序模型需在波形域正式接入训练前完成。

## 5. 测试矩阵

### 单元测试

- Haversine 与候选距离；
- 时间区间损失边界；
- 未触发删失条件；
- Huber/Student-t 残差；
- 地表/井下角色偏置；
- 候选权重归一化；
- P50/P90 区域计算；
- 缺帧和陈旧台站过滤；
- 同源派生字段去重。

### 合成测试

- 理想圆形传播；
- 1 秒时间量化；
- 10%-30% 随机缺站；
- 单站强异常；
- 场地放大异常；
- 台网边缘与海域震源；
- 浅/深类别混淆；
- 两个相邻时间事件。

### 历史回放

- 内陆小震；
- 内陆中强震；
- 近海事件；
- 深源事件；
- 台网外事件；
- 多重/余震密集窗口；
- 非地震噪声与缺帧窗口。

## 6. 风险登记

| 风险 | 后果 | 应对 |
|---|---|---|
| GIF 颜色不是原始测量 | 模型上限受限 | 输出概率区域，保留数据来源说明 |
| 时间阈值不是 P 到时 | 固定波速产生偏差 | 区间似然、经验标定、消融验证 |
| 地表与井下混用 | 强度衰减系统偏差 | 角色偏置、分组标定 |
| 海域缺少包围台站 | 震中向陆地偏移 | 台网边缘先验、限制未触发惩罚、单独评测 |
| 小样本手工调参 | 回放看似提升但泛化失败 | 事件级盲测、冻结测试集 |
| 概率区域未校准 | 用户误解置信度 | 经验覆盖率校准，不足时标为质量等级 |
| 多事件混合 | 估算落在两个事件之间 | 空间时间聚类、多假设跟踪 |
| 计算量过高 | 无法每秒更新 | top-K、缓存距离、分层搜索、性能基准 |

## 7. 决策记录

已确定：

- `nied_gif_hybrid_v1` 只作为旧基线；
- 当前派生 PGA/PGV/PGD 不作为独立观测；
- 第一版不发布精确深度；
- 新方案优先采用可解释统计模型；
- 震中估算和 PLUM 分成两个模块；
- 所有参数通过事件级回放标定。

实施前仍需确定：

- 标准回放包是否保留原始 GIF；
- JMA 真值目录的获取与版本固定方式；
- 第一批事件清单和海域/深源比例；
- 桌面与移动端各自的计算预算；
- 概率区域在地图上的具体交互形式。

## 8. 下一步

下一次实施并行推进 P1 和 P1.5。P1 继续用常驻双图层采集器和本地滚动缓存
积累真实 GIF。P1.5 已完成 2020-2022 年最终逐站震度事件包、冻结 split、台站
遮蔽、`synthetic_reveal`、静态衰减 v1 validation 基线、
K-NET/KiK-net ASCII/CSV 波形解析器、逐秒波形特征 v1、下载清单与
GIF/波形域对齐工具，以及第一批真实 K-NET/KiK-net 事件候选下载 manifest。
NIED 正式波形直链无凭据访问返回 `401 Unauthorized`。已通过注册账号在本地
下载 8 个正式 zip，并生成 8 个波形特征包，覆盖 2016 熊本、2018 北海道胆振、
2021 福岛县冲和 2024 能登；波形域训练索引已生成在
`tmp/knet_features/knet_waveform_feature_index.json`。当前成功下载的强震事件
没有本项目对应 GIF 回放，因此不再等待同域事件作为当前阻塞项。已从正式波形
特征构建 `waveform_projected_gif` 投影数据集，输出 4 个事件、8 个 waveform
packages、4188 个台站/角色、706968 条 station-second 观测；其中 all-formats
版本只用于格式鲁棒性诊断，CSV-preferred 单格式版本仍是主预训练池。真实 GIF/波形
同域事件以后只作为校准/验证项，重点报告台站级时间滞后、幅值偏差和饱和范围。
已完成统一 60 秒台站观测缓冲和投影域时空留一基线。历史峰值与相对首次到时约束
把 4 个留出事件的首个可估位置误差中位数从 13.62 km 降至 7.40 km，并把震源后
120 秒逐帧中位误差从 74.48 km 降至 10.58 km。该结果仍不代表真实 GIF 检出延迟
或生产可用性。首次上升与首次触发时间区间也已贯通检测器、样本和事件记录。
ObservationProvenance/SensorSelection 已补齐，`jma` 不再派生 PGA/PGV/PGD，
且混合估算器已删除三份重复排序证据。生产轮询现按同一时间戳并发获取
`jma/acmap/vcmap/dcmap` 的地表与地中图层，统一合并后只广播一次；缺图层和像素
不可解码均有质量标志。首份静默时刻对齐报告覆盖 1630 个有扫描坐标台站，其中
1260 个四层均可解码。下一步应等待真实事件窗口，用事件期数据评估物理图层是否
改善定位，再决定是否进入生产评分。已新增 2026-06-21 能登 M2.7 真实事件窗口：
151 个时间戳、1208/1208 张 GIF、190041 条四层齐全 station-second。该事件暂为
`unassigned_reference`，不进入冻结指标。配对回放发现原震源专用触发阈值
`confirmedMinStations=6` 会漏掉该事件：震后 6 秒形成 5 台石川连续空间簇，
簇质心为 `37.3931, 137.1793`。震源专用检测器已独立改为
`candidate=4 / confirmed=5`，未修改 legacy/NIED 检出逻辑；现有静稳窗口回归
仍保持 0 candidate、0 confirmed。定位器同时改为只消费
`source_trigger_member_ids`，普通 `detectLevel >= 0` 不再自动成为首波证据，
事件尾段低于最小支持时保持最近稳定解，不再用两台站质心覆盖结果。

在该事件上，`nied_gif_hybrid_v1` 首次估算延迟为 6 秒，首报误差 7.46 km，
最终误差 5.99 km。固定权重的实验物理融合首报误差为 40.63 km，P90 跳动
37.57 km，相比 JMA-only 明显退化，因此 `acmap/vcmap/dcmap` 继续只作为独立
观测保存，不进入生产评分。报告见
`docs/baselines/noto_m27_20260621_multilayer_gain.generated.md`。下一步不是继续
调这一个事件的权重，而是先增加至少 3 个完整多图层事件和独立静稳窗口，验证
5 台确认阈值的召回/误报，再按事件级 validation 比较物理量的基线差分、峰值、
到峰时间和衰减特征。

2026-06-21 宫城县东南冲/福岛县冲 M3.2 参考事件已补为第二个完整多图层窗口：
151 个时间戳、1208/1208 张 GIF、190062 条四层齐全 station-second，0 失败。
该事件已关联用户提供的 Hi-net 震源标签：2026-06-21 22:41:12 UTC+8、
宫城县东南冲、37.616N/142.279E、M3.2、深度 29.8 km；EQuake 第 6 报
只保留为触发和质量参考。

2026-06-22 岩手县东北冲/岩手县冲 M3.4 参考事件已补为第三个完整多图层窗口：
151 个时间戳、1208/1208 张 GIF、190067 条四层齐全 station-second，0 失败。
该事件已关联用户提供的 Hi-net 震源标签：2026-06-22 08:28:23 UTC+8、
岩手县东北冲、40.392N/142.341E、M3.4、深度 50.2 km；EQuake 第 10 报
只保留为触发和质量参考。

2026-06-22 和歌山县南部 M2.5 Hi-net 标记事件已补为第四个完整多图层窗口：
151 个时间戳、1208/1208 张 GIF、189984 条四层齐全 station-second，0 失败。
该事件已关联用户提供的 Hi-net 震源标签：2026-06-22 08:51:17 UTC+8、
和歌山县南部、33.580N/135.791E、M2.5、深度 28.1 km。当前完整多图层事件数
为 4；下一步重点转为补充独立静稳窗口、复核事件级 split，然后统一验证 5 台
确认阈值及物理图层时序特征，禁止用单个事件调权重。

已新增 split 审计报告：
`docs/baselines/source_estimation_split_audit.generated.md`。它扫描
`test/fixtures/source_estimation` 下所有 replay fixture，并对照
`dataset_splits.json` 输出冻结 split、未分配 reference、噪声窗口数量和检出指标分母。
当前审计通过硬错误检查，但给出预期 warning：13 个事件尚未进入冻结 split，其中
13 个均已显式标为 `unassigned_reference` 且不进入检出指标分母。独立静稳窗口
目标已补齐为 2/2；新窗口为
`test/fixtures/source_estimation/quiet_20260625_233535_jst_live.json`，
对应采集目录 `tmp/captures/quiet_20260625_233535_jst_live`，300 秒、8 图层、
2400/2400 GIF 成功、0 失败。`test/quiet_window_20260625_replay_test.dart`
验证该窗口 300 帧完整解码，正式检测无 candidate/confirmed，所有震源估计方法
均为 0 estimate。因此下一步数据工作转为把 reference 事件逐个完成 split
assignment/JMA catalog linking 后再纳入任何冻结指标。
已新增 split assignment plan：
`docs/data/source_estimation_split_assignment_plan.json`。split audit 会检查所有
`unassigned_reference` 事件是否都有计划；当前 13/13 均已覆盖，未计划数量为 0。
该计划只记录用途和进入冻结 split 前的条件，不会把事件自动移入 train/validation/test。
已新增 quiet-window capture plan：
`docs/data/source_estimation_quiet_window_capture_plan.json`。split audit 会读取该
计划并报告目标/当前/剩余 quiet window 数量。当前目标为 2 个独立静稳窗口，已有
2 个，剩余 0 个；计划中的 live capture 已执行并清空，因此
`quiet_window_capture_plan_insufficient` 和
`independent_quiet_window_count_below_2` 均不再出现。
`tools/capture_nied_gif_live.ps1` 同时修复了 `-Layers` 参数绑定问题，并把同一
timestamp 的多图层下载改为并发请求加失败后补抓，以避免 8 图层 live capture
被单层网络抖动拖慢或误判失败。
本地验证命令：
`powershell -NoProfile -ExecutionPolicy Bypass -File tools\validate_source_estimation_split_audit.ps1`。
该命令会重新生成 split audit 报告并立即运行
`test/source_estimation_split_audit_report_test.dart`，避免过期报告通过评审。
当前 source-estimation 总体验证入口：
`powershell -NoProfile -ExecutionPolicy Bypass -File tools\validate_source_estimation_suite.ps1`。
它按顺序运行 split audit 和 candidate-region validation suite，并写出
`.dart_tool/source_estimation_validation_suite/summary.json`。该 summary 只证明当前
split/candidate-region 守卫通过；P3 概率校准和事件级 split assignment 仍未完成。

仍需复核
2022 福岛、2024 日向滩和 2026 岩手小震的 NIED 目录 ID。静态 v1 的 validation
中位/P90 误差为 33.98/92.55 km，略优于加权质心 35.68/94.91 km，但 P90 覆盖率
只有 78.2%，因此不接入生产，整体 P3 仍需概率校准和冻结 test 验收。
### 2026-06-22 Iwate East Offshore M3.0 Reference

- Linked user-provided Hi-net preliminary label: `2026-06-22 10:26:50 UTC+8`,
  `39.910N, 142.347E`, M3.0, depth 42.4 km.
- Captured 151 timestamps and 1208/1208 NIED GIFs across four physical layers
  and two sensor roles; 189782 complete four-layer station-seconds.
- This is the fifth complete multilayer event window in the current local set.
- Source-specific trigger candidate/confirmation: +15/+17 s.
- Current hybrid median/P90 location error: 65/615 km.
- Keep as `unassigned_reference`, outside frozen metrics. Use it to validate
  offshore one-sided geometry and late-frame stability, not to tune one event.
### 2026-06-22 Fukushima Offshore M2.2 Countercase

- Captured the sixth complete multilayer event window: 151 timestamps,
  1208/1208 GIFs and 189991 complete four-layer station-seconds.
- EQuake report 4 remains `reference_only`; no independent catalog truth yet.
- Legacy detection: candidate +21 s, no confirmation.
- Source-specific trigger now remains candidate-only from +49 s and rejects at
  +57 s; no source estimate is emitted.
- Production source confirmation requires a stable five-station compact core
  within 120 km for two frames. A candidate that has already failed coherence
  cannot recover by dropping edge stations.
- Rejected members must leave the triggered state before rearming.
### 2026-06-22 Kushiro Offshore M3.0 JMA Baseline

- Captured the seventh complete multilayer event window: 151 timestamps,
  1208/1208 GIFs and 190003 complete four-layer station-seconds.
- JMA-verified truth: `42.9N, 144.0E`, M3.0, depth 50 km, maximum shindo 1.
- Source trigger candidate/confirmation: +9/+11 s, with eight connected
  evidence stations within 50 km.
- Weighted centroid median/P90 error: 16.5/22.9 km.
- Hybrid median/P90 error: 28/118.2 km.
- Use this as the positive offshore/depth counterpart to the Fukushima M2.2
  false-association case when implementing locality and stability gates.

### 2026-06-22 Countercase Diagnostic Automation

- Added `tools/build_source_estimation_countercase_report.dart`.
- The tool reads existing per-case benchmark JSON without rerunning GIF decode.
- It compares `nied_gif_hybrid_v1`, `weighted_centroid_baseline`, and
  `scratch_scan_v1` using first, median, P90, final, worst-frame, jump, and
  first-estimate-delay diagnostics.
- Hi-net and EQuake labels remain `reference`; only JMA truth sources are
  rendered as `JMA verified`.
- Generated report:
  `docs/baselines/source_estimation_countercases.generated.md`.

Run:

```powershell
dart run tools/build_source_estimation_countercase_report.dart
```

Current priority countercases:

1. Fukushima/Miyagi offshore M3.2: hybrid median/P90/final error
   165/354/301 km with late drift. Inspect absolute geometry scoring and late
   member admission separately from the stability gate.
2. Kushiro offshore M3.0: JMA-verified case where centroid median/P90
   16.5/22.9 km beats hybrid 28/118.2 km. Use it to test one-sided offshore
   geometry and error-tail suppression.
3. Nara M3.6 was removed from the catastrophic-error priority after rerunning
   the current member-filtering implementation: first/worst/final error is now
   7/14/4 km. Keep it as the inland control case.

Do not tune production weights from one countercase. The next implementation
step is to export frame-level member changes and timing-pick geometry for these
three cases, then determine whether each failure belongs to source triggering,
observation timing, or estimator scoring.

### 2026-06-22 Frame-level Failure Trace

- Added `tools/build_source_estimation_failure_trace.dart` for the three
  priority countercases.
- The trace exports first, worst, largest-jump, and final frames together with
  source-trigger member changes, component geometry, hybrid timing picks,
  search bounds, and score components.
- Timing picks are explicitly split into stations inside and outside the
  source-trigger event membership. This distinguishes detector association
  failures from estimator observation-scope failures before weight changes.
- Generated report:
  `docs/baselines/source_estimation_failure_trace.generated.md`.

Run:

```powershell
dart run tools/build_source_estimation_failure_trace.dart
```

The trace must compare timing picks with accumulated event membership, matching
the benchmark and production `source_trigger_member_ids` semantics, rather
than only the members active in the current frame. After refreshing the three
benchmarks, no persistent evidence-scope mismatch remains in the Nara control.
The next estimator change should therefore address offshore search geometry:
the Fukushima truth is outside every station-derived search box. Event identity
replacement and the 253 km Kushiro jump must remain separate stability checks.

### 2026-06-22 Offshore Geometry Diagnostics

- Added candidate-relative station azimuthal gap, nearest-station distance,
  search-boundary margin, boundary-hit flag, and `one_sided`/`surrounded`
  classification to the NIED GIF hybrid diagnostics.
- The same geometry fields are available on the generic trigger-time grid for
  comparison, but production behavior and score weights are unchanged.
- Added a synthetic one-sided offshore unit case. The diagnostic uses a
  greater-than-180-degree station azimuthal gap as the geometric definition;
  it does not infer offshore status from Japanese place names or UI regions.
- Frame-level failure traces now preserve these fields for the first, worst,
  largest-jump, and final estimates.

Use the refreshed Fukushima, Kushiro, and Nara traces to choose a directional
search expansion rule. Do not enable a global symmetric padding increase: it
would enlarge ambiguous inland and noise searches without evidence.

Observed geometry after replay refresh:

- Nara first/worst/final solutions are `surrounded`, do not hit the search
  boundary, and retain 7/14/4 km error.
- Fukushima first solution has a 329.9-degree azimuthal gap, 113.5 km nearest
  station distance, and crosses the south search boundary. Its reference truth
  is southeast and remains outside the box.
- Kushiro first solution has a 326.5-degree gap and also approaches the south
  boundary, but its JMA truth is already inside the original search box.

Therefore boundary direction alone is not a valid offshore expansion rule.
The next implementation must compare an experimental one-sided-geometry score
against the unchanged production score on all offshore references plus Nara.
It should penalize unsupported distant boundary minima and report uncertainty;
search expansion may only be evaluated as one experimental factor.

### 2026-06-22 Offshore Geometry Experiment

- Added `test/source_estimation_offshore_geometry_experiment_test.dart`.
- The replay matrix compares the unchanged baseline, symmetric search
  expansion, expanded weak-center scoring, an experimental one-sided boundary
  centroid guard, and soft one-sided boundary penalties from 0.01 to 0.30.
- Generated report:
  `docs/baselines/source_estimation_offshore_geometry_experiment.generated.md`.

Run:

```powershell
flutter test test\source_estimation_offshore_geometry_experiment_test.dart
```

Result:

- Symmetric search expansion is rejected. It leaves Nara unchanged but worsens
  Iwate offshore, Fukushima/Miyagi offshore, and Kushiro offshore tails.
- Weakening the center penalty with the expanded box is also rejected; it does
  not recover the offshore cases and keeps the enlarged-tail failure mode.
- The centroid guard is mixed: it improves Fukushima/Miyagi median error
  165 -> 131 km, Iwate northeast median/jump 24/22 -> 17/7 km, and Kushiro
  P90 118.2 -> 40 km, but worsens Iwate offshore P90 54 -> 120 km and Iwate
  east P90 51 -> 68 km.
- Soft one-sided boundary penalties are safer than the hard centroid guard but
  still do not solve the main offshore failure. Penalties 0.01/0.03 mostly keep
  baseline metrics. Penalty 0.30 improves Kushiro P90 118.2 -> 84.7 km, but
  leaves Fukushima/Miyagi at 165/354 km and worsens Iwate northeast P90 jump
  22 -> 28.5 km.

Decision:

- Keep production on the baseline `nied_gif_hybrid_v1` parameters.
- Keep `useOneSidedBoundaryCentroidGuard` default-off as an experiment switch
  only.
- Keep `oneSidedBoundaryPenaltyPerKm` default-off. The current soft penalty is
  useful as an experiment but is not a production score change.
- Production diagnostics now include `geometry_penalty`,
  `horizontal_uncertainty_p50_km`, `horizontal_uncertainty_p90_km`, and
  `horizontal_uncertainty_model`.
- The next estimator change should separate uncertainty reporting from
  coordinate scoring: use the new geometry diagnostics to flag unreliable
  one-sided/near-boundary frames, then inspect attenuation or travel-time
  residual features for Fukushima/Miyagi before changing coordinates.

### 2026-06-23 Tomakomai Offshore and Candidate Corrections

- Added Tomakomai south offshore M3.5 as a complete Hi-net preliminary
  reference window:
  `docs/baselines/tomakomai_south_offshore_m35_20260622_reference.md`.
- Captured 151 timestamps and 1208/1208 NIED GIFs across four physical layers
  and two sensor roles; 190089 complete four-layer station-seconds.
- Source-specific trigger candidate/confirmation: +22/+29 s.
- Baseline `nied_gif_hybrid_v1` median/P90/final error against the preliminary
  Hi-net reference: 13/55/7 km.
- Worst frame is a one-sided boundary solution with 137 km error, 87 km jump,
  282.1 degree azimuth gap, and 195.6 km horizontal uncertainty P90.
- Residual report:
  `docs/baselines/tomakomai_south_offshore_m35_residual_report.generated.md`.

The offshore geometry experiment has been extended with two narrow centroid
guard variants:

- `centroid_guard_high_uncertainty` applies the correction only when the frame
  is one-sided, hits the search boundary, has horizontal uncertainty P90 of at
  least 180 km, and has nearest-station distance of at least 80 km.
- `centroid_guard_high_uncertainty_diagnostic` emits the same candidate under
  `diagnostics.candidate_corrections.one_sided_boundary_centroid_guard` but
  does not replace the production coordinates.

Replay outcome:

- Tomakomai baseline P90 remains 55 km; the diagnostic-only candidate emits
  three candidate corrections with 27.8 km median/P90 error and applied count 0.
- Kushiro baseline P90 remains 118.2 km; the diagnostic-only candidate emits
  eight candidate corrections with 22.5/24.1 km median/P90 error and applied
  count 0.
- Iwate offshore M3.4 emits no diagnostic candidates and keeps the 54 km P90
  baseline, avoiding the regression seen with the global centroid guard.
- Fukushima/Miyagi M3.2 emits eight diagnostic candidates with 132.3/136.7 km
  median/P90 candidate error. After source-trigger continuity, the production
  baseline P90 is 311 km and P90 jump is 4.5 km; this case still needs
  early-frame travel-time, attenuation, and search-box diagnosis.

Decision:

- Keep production on the baseline `nied_gif_hybrid_v1` coordinates.
- Keep `useOneSidedBoundaryCentroidGuard` default-off.
- Keep diagnostic-only candidate output as an evidence path, not as a
  coordinate replacement.
- Candidate corrections are currently useful for replay analysis and future
  UI uncertainty/candidate-region display, but they are not production truth.

Report/tooling status:

- `tools/build_source_estimation_countercase_report.dart` now shows candidate
  correction count, applied count, candidate median/P90 error, large-error
  coverage, large-error improvement coverage, and worst-frame
  baseline-versus-candidate error.
- `tools/build_source_estimation_residual_report.dart` now shows selected-frame
  candidate error, candidate RMS, candidate rank inversion, and median
  pick-distance estimate/candidate/truth when
  `diagnostics.candidate_corrections` is present.
- Generated countercase and residual reports have been refreshed for
  Fukushima/Miyagi M3.2, Kushiro M3.0, and Tomakomai M3.5.
- `docs/baselines/source_estimation_offshore_geometry_experiment.generated.md`
  now includes a promotion/rejection matrix derived from the diagnostic
  candidate replay. The matrix marks Tomakomai and Kushiro as
  `positive_boundary_candidate`, Iwate offshore as `pass_no_candidate`, Iwate
  east offshore as `reject_regression_risk`, and Fukushima/Miyagi as
  `reject_as_primary_fix`.

Next implementation step:

1. For Fukushima/Miyagi M3.2, inspect early travel-time residuals,
   attenuation residuals, and search-box construction because the candidate
   covers only 8/47 large-error frames and does not explain the worst early
   production error.
2. Convert the promotion/rejection matrix into a production-gate checklist:
   positive cases must improve every large-error boundary frame, regression
   guards must emit no candidate or reject it, and broad failures must remain
   diagnostic-only.
3. Keep production coordinate scoring unchanged until Fukushima/Miyagi has an
   independent residual/member-evolution explanation and the full countercase
   matrix remains green.

Fukushima/Miyagi trace refresh:

- `docs/baselines/source_estimation_failure_trace.generated.md` was refreshed
  from the existing benchmark diagnostics.
- The Fukushima/Miyagi selected frames all keep the truth outside the search
  bounding box: first 120 km error, worst 313 km error, largest jump 307 km
  error, and final 168 km error.
- After source-trigger continuity, the largest jump is a 278 km inter-frame move
  at `2026-06-21T23:41:51.000`, when the same source-trigger event expands from
  Miyagi stations into Fukushima/Iwate support while the geometry remains
  one-sided and the truth remains outside the search box.
- The late Kanto/Yamanashi replacement no longer drives the P90 jump tail. The
  remaining failure should be treated as an early search-window and
  travel-time/attenuation scoring problem before any production coordinate
  change. The diagnostic candidate correction remains rejected as the primary
  fix for this case.

Fukushima/Miyagi member-evolution report:

- Added `tools/build_source_member_evolution_report.dart`.
- Generated report:
  `docs/baselines/fukushima_miyagi_m32_member_evolution.generated.md`.
- The source-trigger event is replaced at `2026-06-21T23:42:49.000`, changing
  from `nied_gif-2026-06-21T23:41:49.000` to
  `nied_gif-2026-06-21T23:42:49.000`.
- The replacement event starts with `GNM010, IBR015, KNG006, YMN002`; its
  member centroid is 319.0 km from the Hi-net truth before the production
  estimate would previously jump.
- `SourceTriggerContinuityGate` now keeps the effective source event on
  `nied_gif-2026-06-21T23:41:49.000` for far replacements within the retention
  window. In the refreshed Fukushima/Miyagi replay it holds the replacement for
  20 frames, reducing hybrid P90 jump 41 km -> 4.5 km and hybrid P90 error
  354 km -> 311 km.
- Therefore the completed continuity gate fixes the late event-identity
  failure mode, but the dominant remaining error is the early one-sided
  search-window/scoring failure.

Next implementation step:

1. Build a Fukushima/Miyagi early-frame candidate report for the first 10
   estimate frames. Compare baseline coordinate, diagnostic centroid-guard
   candidate, travel-time residuals, intensity-distance rank residuals, and
   attenuation residuals frame by frame.
2. Add a production-gate checklist for candidate coordinates: candidate must
   improve every large-error boundary frame in positive cases, avoid known
   regression cases, and explain the large-error frame it proposes to replace.
3. Keep production coordinate scoring unchanged until the early-frame report
   explains Fukushima/Miyagi and the full offshore/countercase matrix remains
   green.

### 2026-06-23 Fukushima/Miyagi Early-Frame Candidate Report

- Added `tools/build_source_estimation_early_frame_report.dart`.
- Generated report:
  `docs/baselines/fukushima_miyagi_m32_early_frame_report.generated.md`.
- The first 10 estimate frames all have the Hi-net truth outside the hybrid
  search box and all are one-sided geometry frames.
- The diagnostic centroid-guard candidate is mixed:
  - frame 1 worsens location error, 120 km -> 138 km;
  - frames 2-8 improve location error, about 307-313 km -> 131-137 km;
  - frames 9-10 emit no candidate.
- However, the candidate has worse relative travel-time RMS than baseline on
  every candidate frame, and worse diagnostic static attenuation scatter on the
  candidate frames. The Hi-net truth also has poor travel-time RMS in these
  frames, so travel-time residuals alone do not select the catalog truth.

Decision:

- Do not promote the diagnostic centroid candidate directly to production
  coordinates.
- Treat the candidate as a useful alternative-region hint for one-sided
  offshore uncertainty, not as a solved location.
- Next implementation step: define a candidate promotion gate that requires
  location improvement evidence plus non-regression in residual/rank/attenuation
  diagnostics, then replay it across the offshore matrix.

### 2026-06-23 Candidate Promotion Gate Diagnostic

- Added `tools/build_source_candidate_promotion_report.dart`.
- Generated report:
  `docs/baselines/source_candidate_promotion_report.generated.md`.
- The gate is diagnostic-only and explicitly separates:
  - `productionGate`: uses only available residual signals, not truth labels;
  - `offlineEvaluation`: uses truth error only to score the gate after replay.
- Current production-available gate:
  - accept a diagnostic candidate only when rank inversion or static
    attenuation scatter supports it;
  - hard reject when rank inversion and attenuation scatter both strongly
    regress;
  - keep travel-time RMS diagnostic-only because it worsens in Fukushima and in
    the positive offshore candidates.
- Replay result across the current early-frame matrix:
  - Fukushima/Miyagi M3.2: 8 candidate frames, 0 accepted, 8 rejected, 0 false
    accepts, 7 offline missed positives;
  - Kushiro offshore M3.0: 8 candidate frames, 5 accepted, 3 rejected, 0 false
    accepts, 3 offline missed positives;
  - Tomakomai south offshore M3.5: 3 candidate frames, 3 accepted, 0 rejected,
    0 false accepts, 0 missed positives.

Decision:

- Do not promote diagnostic centroid candidates into production coordinates
  yet. The gate prevents the Fukushima/Miyagi false promotion pattern, but it
  still misses several offline-positive Kushiro early frames.
- Keep diagnostic candidate coordinates as alternative-region evidence and UI
  uncertainty material only.
- Next implementation step: add this promotion-gate diagnostic to the broader
  offshore/countercase refresh, then look for an additional production-available
  signal that recovers Kushiro early positives without accepting Fukushima.

### 2026-06-23 Broad Candidate Promotion Matrix

- `tools/build_source_estimation_early_frame_report.dart` now supports
  `--input-directory`, `--output-directory`, and `--markdown-directory` for
  reproducible batch early-frame diagnostics.
- Generated batch early-frame reports from
  `.dart_tool/source_estimation_benchmark` into
  `.dart_tool/source_estimation_early_frame_report/matrix`.
- Generated broad promotion matrix:
  `docs/baselines/source_candidate_promotion_matrix.generated.md`.
- Batch generation skipped `source_estimation_p0.json` because it has no truth
  latitude/longitude and cannot be used for offline candidate-location
  evaluation.
- Broad matrix coverage:
  - 10 early-frame cases with truth labels;
  - 3 cases emitted diagnostic candidates: Fukushima/Miyagi M3.2, Kushiro
    offshore M3.0, and Tomakomai south offshore M3.5;
  - 7 cases emitted no candidates: Nara, Gifu Hida, Iwate offshore M3.4,
    Fukushima M2.2 countercase, Iwate east offshore, Iwate offshore M3.0, and
    Wakayama south.
- Gate result remains unchanged after broader refresh:
  - Fukushima/Miyagi M3.2: 8 rejected / 0 accepted / 0 false accepts /
    7 missed offline positives;
  - Kushiro offshore M3.0: 5 accepted / 3 rejected / 0 false accepts /
    3 missed offline positives;
  - Tomakomai south offshore M3.5: 3 accepted / 0 rejected / 0 false accepts /
    0 missed positives.

Decision:

- The gate has no false accepts in the current broad matrix, but it is still too
  conservative to become a production coordinate switch because it misses early
  Kushiro positives.
- Next implementation step: inspect the three rejected-but-offline-positive
  Kushiro frames for additional production-available evidence. Prioritize
  geometry growth, station-member evolution, candidate distance from source
  trigger centroid, and consecutive-frame persistence before changing
  production coordinates.

### 2026-06-23 Delayed Candidate Confirmation Diagnostic

- `tools/build_source_candidate_promotion_report.dart` now adds
  `delayedConfirmationDiagnostic` per rejected candidate frame.
- The diagnostic marks a rejected candidate as recoverable only if a later
  frame in the same candidate area is accepted by the residual gate within
  5 seconds and 30 km.
- This still uses no truth labels in the gate; truth error remains only in
  `offlineEvaluation`.
- Broad matrix result:
  - Fukushima/Miyagi M3.2: 0 delayed recoveries and 0 delayed false recoveries;
  - Kushiro offshore M3.0: all 3 missed positives are recoverable after
    2-4 seconds by a later accepted candidate about 13.9 km away;
  - Tomakomai south offshore M3.5: no missed positives, so no delayed recovery
    is needed.

Decision:

- Delayed confirmation is the first production-plausible path that separates
  the Kushiro early positive pattern from Fukushima/Miyagi without using truth
  labels.
- Do not switch production coordinates immediately on a residual-unsupported
  candidate. Instead, consider a pending candidate-region state that can promote
  only after later residual support arrives in the same spatial cluster.
- Next implementation step: design the pending candidate-region state machine
  and add replay tests proving it does not alter immediate source coordinates,
  does not accept Fukushima/Miyagi, and can surface Kushiro as a delayed
  uncertainty/promotion candidate.

### 2026-06-23 Pending Candidate-Region State Machine

- Added `lib/core/source_estimation/source_candidate_region_tracker.dart`.
- Added `test/source_candidate_region_tracker_test.dart`.
- `SourceCandidateRegionTracker` is event-scoped and stateful:
  - unsupported candidate regions become `pending`;
  - later residual-supported candidates within 5 seconds and 30 km become
    `confirmedDelayed`;
  - residual-supported candidates with no pending predecessor become
    `confirmedImmediate`;
  - expired pending candidates cannot be confirmed by a later supported frame.
- `productionCoordinateSwitchAllowed` is always `false` in this implementation.
  The tracker can expose diagnostics or uncertainty material, but it does not
  change the immediate source coordinate.
- Added `SourceCandidateResidualGate`, which can build
  `SourceCandidateRegionObservation` directly from production
  `SourceEstimate.diagnostics`. It uses only available per-frame diagnostics:
  candidate correction coordinates, current estimate coordinates, top timing
  picks, rank inversion, and static attenuation scatter.
- `NiedGifHybridSourceEstimator` now includes station `network`, `latitude`,
  and `longitude` in `top_timing_picks`, so the production residual gate no
  longer needs the offline station DB used by the report tools.

Validation:

- `flutter test test/source_candidate_region_tracker_test.dart`
- `flutter analyze lib/core/source_estimation/source_candidate_region_tracker.dart
  lib/core/source_estimation/source_estimator.dart
  test/source_candidate_region_tracker_test.dart`

Decision:

- The pending-region mechanism is ready as a core diagnostic component, but it
  is not yet wired into `SeismicSourceTracker` or the NIED source-estimation
  driver.
- Next implementation step: wire it behind diagnostics metadata only. The first
  integration should annotate events with pending/confirmed candidate-region
  state while leaving `SourceEstimate.latitude/longitude` unchanged.

### 2026-06-23 Candidate-Region Metadata Integration

- `SeismicSourceTracker` now owns a per-source
  `SourceCandidateRegionTracker` and a `SourceCandidateResidualGate`.
- When a new estimate contains
  `diagnostics.candidate_corrections.one_sided_boundary_centroid_guard`, the
  tracker computes production-available residual support and writes:
  - `metadata.candidate_region`;
  - `metadata.candidate_region_residual_gate`.
- The integration is metadata-only:
  - `SourceEstimate.latitude` and `SourceEstimate.longitude` are unchanged;
  - `production_coordinate_switch_allowed` remains `false`;
  - unsupported regions stay `pending`;
  - later same-region residual support becomes `confirmedDelayed`.
- `candidate_region` metadata is cleared automatically when a later estimate no
  longer emits a candidate correction.
- Added tracker-level tests proving:
  - delayed candidate-region confirmation does not change estimate coordinates;
  - unsupported candidate regions remain pending and are not confirmed.

Validation:

- `flutter test test/source_candidate_region_tracker_test.dart
  test/seismic_source_tracker_test.dart`
- `flutter analyze lib/core/source_estimation/source_candidate_region_tracker.dart
  lib/core/source_estimation/source_estimator.dart
  lib/core/source_estimation/seismic_source_tracker.dart
  test/source_candidate_region_tracker_test.dart
  test/seismic_source_tracker_test.dart`

Decision:

- Pending candidate-region metadata is now available to downstream diagnostics
  and UI, but it is intentionally not a source-coordinate switch.
- Next implementation step: replay Fukushima/Miyagi and Kushiro through the
  tracker metadata path and compare `candidate_region` timelines with the
  existing offline promotion matrix before exposing it in production UI.

### 2026-06-23 Candidate-Region Timeline Replay

- `test/support/source_estimation_benchmark.dart` now exports per-method
  `eventMetadata`, so replay JSON includes tracker-produced
  `candidate_region` and `candidate_region_residual_gate` metadata.
- Refreshed reference replays:
  - `20260621_fukushima_offshore_m32_eq6.reference.json`;
  - `20260622_kushiro_offshore_m30_jma.reference.json`.
- Added `tools/build_source_candidate_region_timeline_report.dart`.
- Generated report:
  `docs/baselines/source_candidate_region_timeline.generated.md`.
- Metadata timeline result:
  - Fukushima/Miyagi M3.2: 8 candidate-region frames, 7 `pending`,
    1 `expired`, 0 `confirmedDelayed`, 0 `confirmedImmediate`, 0 coordinate
    switches;
  - Kushiro offshore M3.0: 8 candidate-region frames, 3 `pending`,
    1 `confirmedDelayed`, 4 `confirmedImmediate`, 0 coordinate switches.
- This matches the offline promotion matrix: Fukushima never gets residual
  confirmation, while Kushiro's initially unsupported region is confirmed after
  later same-region residual support.

Decision:

- The metadata path validates the delayed candidate-region concept without
  changing source coordinates.
- Next implementation step: expose `candidate_region` to diagnostics/UI as an
  uncertainty or alternative-region state, not as an estimated epicenter
  replacement. The UI should only display it when
  `production_coordinate_switch_allowed == false` as pending/confirmed
  candidate-region evidence.

### 2026-06-23 Candidate Region UI Exposure

- `AlertModule` now reads `sourceEvent.metadata['candidate_region']` for the
  unified source-estimation card.
- The candidate-region state is appended to the quality line, for example:
  - `候选区域 待确认`;
  - `候选区域 延迟确认 4.0s`;
  - `候选区域 已确认`;
  - `候选区域 已过期`.
- The UI only renders this text when
  `production_coordinate_switch_allowed == false`, so the candidate region is
  explicitly shown as diagnostic/uncertainty evidence rather than a replacement
  epicenter.
- Added widget coverage in `test/source_estimation_card_test.dart` proving:
  - the unified card displays candidate-region metadata;
  - the hypocenter text remains the actual `SourceEstimate` coordinate.

Validation:

- `flutter test test/source_estimation_card_test.dart`
- `flutter analyze lib/widgets/ui/alert_module.dart
  test/source_estimation_card_test.dart`

Decision:

- Candidate-region evidence is now visible in the unified left-top source card.
- Next implementation step: if needed, design a separate map overlay for the
  candidate region. Do not draw it as the estimated epicenter marker or use it
  for auto-focus until a later production switch is explicitly approved.

### 2026-06-23 Candidate Region Map Overlay

- `QuakeMapView` now renders a separate candidate-region overlay from
  `sourceEvent.metadata['candidate_region']`.
- The overlay is intentionally distinct from the estimated-epicenter marker:
  - it is drawn before the source marker;
  - it uses a semi-transparent 30 km minimum region circle;
  - it has its own status label (`候选区域`, `候选延迟确认`, `候选已确认`,
    `候选已过期`);
  - it never changes `SourceEstimate.latitude/longitude`;
  - it is not used by auto-focus or P/S wave rendering.
- The layer is still gated by the existing `showEstimatedEpicenter` setting,
  because it is source-estimation evidence. Turning that setting off hides the
  candidate-region overlay together with the source marker and trigger stations.

Validation:

- `flutter analyze lib/widgets/map/quake_map_view.dart`
- `flutter test test/source_estimation_card_test.dart
  test/source_candidate_region_tracker_test.dart
  test/seismic_source_tracker_test.dart`
- `flutter analyze lib/widgets/map/quake_map_view.dart
  lib/widgets/ui/alert_module.dart
  lib/core/source_estimation/source_candidate_region_tracker.dart
  lib/core/source_estimation/seismic_source_tracker.dart`

Decision:

- Candidate regions are now visible both in the unified card and on the map,
  but remain diagnostic-only. They are not estimated epicenter replacements and
  still do not participate in camera follow.
- Next implementation step: run a manual replay visual check for Fukushima and
  Kushiro, then decide whether the overlay needs a separate user setting or
  legend entry.

### 2026-06-23 Sanriku Far East Offshore Hi-net Pending Label

- Added a reference-only Hi-net preliminary label to
  `docs/data/hinet_reference_event_candidates.json`.
- Event id: `20260623_sanriku_far_east_offshore_m30_hinet`.
- User-provided Hi-net label:
  - origin: `2026-06-23 19:40:55 UTC+8`
    (`2026-06-23 20:40:55 JST`, `2026-06-23T11:40:55Z`);
  - region: Sanriku far east offshore (`三陸東方はるか沖`);
  - hypocenter: `39.772N, 143.327E`;
  - magnitude/depth: M3.0, 7.1 km.
- No matching local GIF replay package or EQuake report is currently present in
  the project. This entry is therefore not a replay fixture, not JMA final
  catalog truth, and not part of any train/validation/test denominator.
- Next action if more data appears: link the EQuake report text or a complete
  local GIF replay window to this event id, then promote it to a normal source
  estimation fixture only after capture provenance and split assignment are
  reviewed.

### 2026-06-23 Tokachi Southeast Offshore M3.4 Capture

- Added `20260623_tokachi_southeast_offshore_m34_hinet` as a complete Hi-net
  preliminary reference fixture.
- User-provided Hi-net label:
  - origin: `2026-06-23 22:13:06 UTC+8`
    (`2026-06-23 23:13:06 JST`, `2026-06-23T14:13:06Z`);
  - region: Tokachi southeast offshore (`十勝地方南東沖`);
  - hypocenter: `42.497N, 143.647E`;
  - magnitude/depth: M3.4, 55.5 km.
- EQuake final report 11 is retained as reference text only:
  `42.49N, 143.70E`, M3.1, depth 61 km, quality B 73.5%, RMS 0.75 s,
  azimuthal gap 155 deg and 54 triggered stations (`P:9 S:33 O:12`).
- Captured a complete 151-second, eight-layer NIED GIF window:
  `tmp/captures/tokachi_southeast_offshore_m34_20260623_221306_multilayer`,
  1208/1208 GIFs and 0 failures.
- Added fixture:
  `test/fixtures/source_estimation/tokachi_southeast_offshore_m34_20260623_hinet.json`.
- Added reports:
  - `docs/baselines/tokachi_southeast_offshore_m34_20260623_reference.md`;
  - `docs/baselines/tokachi_southeast_offshore_m34_20260623_multilayer_alignment.generated.md`;
  - `docs/baselines/tokachi_southeast_offshore_m34_residual_report.generated.md`.
- Replay diagnostics:
  - source-specific trigger candidate/confirmation: +16/+19 s;
  - max source active stations: 62;
  - robust station trigger: 28 max triggered, 70 unique triggered,
    6/19/26 unique triggered stations within 50/100/160 km;
  - weighted centroid median/P90: 63/162 km;
  - current hybrid median/P90: 18/45 km, with +20 s error 20 km;
  - late final frame drifts to a 98 km one-sided boundary solution with
    319.2 deg azimuthal gap and 187.9 km P90 horizontal uncertainty.

Decision:

- Tokachi is a useful Hokkaido offshore positive case where the current hybrid
  estimator clearly beats weighted centroid for the main event body.
- It also keeps a late one-sided drift tail, so the next algorithm work should
  evaluate candidate-region/continuity behavior on this event together with
  Kushiro and Tomakomai, instead of tuning only on Fukushima/Miyagi failures.

Follow-up diagnostics:

- Refreshed `docs/baselines/source_estimation_countercases.generated.md`.
  Tokachi is now listed as a reference countercase with hybrid
  first/median/P90/final error `57/18/45/98 km`.
- Added
  `docs/baselines/tokachi_southeast_offshore_m34_early_frame_report.generated.md`.
  The first 10 estimate frames show no diagnostic candidate-region frames; the
  Hi-net reference remains inside the search box and the hybrid estimate reaches
  12-13 km error by frames 8-10.
- Refreshed `docs/baselines/source_candidate_promotion_report.generated.md`.
  Tokachi is explicitly `no_candidate_frames`, so its late 98 km final drift is
  not a candidate-promotion problem.

Next implementation step:

- Evaluate late-event one-sided reliability handling using Tokachi, Kushiro and
  Tomakomai. The target is to suppress or downgrade unsupported late one-sided
  boundary estimates without breaking Tokachi's good early/mid-event 12-20 km
  estimates.
## 2026-06-24 状态补丁

- 已接入福岛会津 M3.2 JMA verified 事件：151 秒、多图层、1208/1208 GIF 成功，参考文档见 [`docs/baselines/fukushima_aizu_m32_20260624_reference.md`](baselines/fukushima_aizu_m32_20260624_reference.md)。
- 已生成会津单事件 residual、early-frame、member-evolution 报告，并重跑全局 countercase、candidate promotion 和 candidate-region timeline 报告。
- 会津事件当前 `nied_gif_hybrid_v1` 表现：first/median/P90/final error 为 1/9/16/16 km；前 10 个 estimate frames 均为 surrounded geometry，真值均在 search box 内，无 centroid-guard candidate frames。
- 会津尾部替换问题已接入 source-trigger continuity gate：约 +95 秒出现的新 raw candidate 被标记为 `source_trigger_replacement_held`，effective event ID 保持主事件，尾部候选随后 `candidate_timeout`/`rejected`，不再作为生产 `source_event_replacement`。
- 下一步不继续调会津早期定位权重；应把会津纳入 late-event stability 样本，和 Tokachi/Kushiro/Tomakomai 一起评估 late one-sided drift、候选超时和生产估计冻结/降级策略。
- 当前全局 countercase 矩阵为 12 个 source-estimation case、10 个 actionable cases。会津作为内陆 JMA verified 正样本，暂保持 `unassigned_reference`，不进入 frozen detection metrics，直到事件级 split assignment 完成。

## 2026-06-25 Iwate Offshore M3.2 JMA Reference Label

- Added a JMA source-and-intensity reference fixture:
  `test/fixtures/source_estimation/iwate_offshore_m32_20260625_jma.json`.
- Added reference note:
  `docs/baselines/iwate_offshore_m32_20260625_reference.md`.
- User-provided JMA label:
  - origin: `2026-06-25 18:21:49 UTC+8`
    (`2026-06-25 19:21:49 JST`);
  - region: Iwate offshore (`岩手県沖`);
  - hypocenter: `39.7N, 142.1E`;
  - magnitude/depth: M3.2, 50 km;
  - maximum intensity: JMA shindo 1;
  - tsunami: no concern.
- User-provided EQuake final report 14 is linked as reference-only metadata:
  - origin: `2026-06-25 18:21:43 UTC+8`
    (`2026-06-25 19:21:43 JST`);
  - hypocenter: `39.65N, 142.08E`;
  - magnitude/depth: M3.5, 36 km;
  - quality: A, 82.6%, RMS 1.18 s, azimuthal gap 224 deg;
  - triggered stations: 89 (`P:27 S:50 O:12`);
  - magnitude stations: 68;
  - observed/estimated maximum intensity: observed shindo 1 (`1.4`),
    estimated shindo 2 (`1.5` to `2.4`).
- JMA remains the truth source. EQuake hypocenter, magnitude, depth, quality and
  trigger counts are retained only for source-estimation comparison.
- A complete local `20260625` NIED GIF replay package was captured:
  `tmp/captures/iwate_offshore_m32_20260625_182149_multilayer`.
  It contains 151 timestamps, 8 layers, 1208/1208 GIFs and 0 failures.
- Generated reports:
  - `docs/baselines/iwate_offshore_m32_20260625_reference.md`;
  - `docs/baselines/iwate_offshore_m32_20260625_multilayer_alignment.generated.md`;
  - `docs/baselines/iwate_offshore_m32_20260625_residual_report.generated.md`;
  - `docs/baselines/iwate_offshore_m32_20260625_early_frame_report.generated.md`;
  - `docs/baselines/iwate_offshore_m32_20260625_member_evolution.generated.md`.
- Replay diagnostics:
  - source-specific trigger candidate/confirmation: +7/+8 s;
  - max source active stations: 103;
  - max decoded shindo: 1, matching JMA maximum intensity;
  - weighted centroid median/P90 error: 63.5/86 km;
  - current hybrid median/P90 error: 25/66 km;
  - current hybrid error at +10/+20 s: 123/26 km;
  - early frames 1-3 are one-sided boundary frames where the diagnostic
    candidate improves error from 144/123/123 km to 23.8/29.1/30.0 km.
- Decision: this is a useful Iwate offshore JMA-verified positive case. It
  supports the current candidate-region direction: early diagnostic candidate
  regions can be much better than production coordinates, but production must
  still avoid immediate coordinate replacement and preserve the good +20 s
  hybrid estimate.
- Candidate reliability refresh:
  - `source_candidate_promotion_report.generated.md` and
    `source_candidate_promotion_matrix.generated.md` now cover 11 early-frame
    cases including `20260625_iwate_offshore_m32_jma`;
  - current promotion gate rejects all 3 Iwate candidate frames;
  - all 3 rejected frames are offline-improved positives
    (`144/123/123 km` baseline vs `23.8/29.1/30.0 km` candidate);
  - delayed confirmation does not recover the Iwate pattern;
  - timeline status is 3 pending frames, 0 confirmed, 0 coordinate switches.
- Decision update: the existing rank/attenuation residual gate remains safe
  against false accepts, but is now too conservative for an Iwate-style
  early one-sided positive. Candidate regions must remain diagnostic-only.
- Member-evolution comparison gives a concrete next signal:
  - Iwate first estimate: source-member centroid about 28.6 km from JMA truth,
    truth inside search box, local Iwate station support grows from 5 to 10
    members by the large jump frame;
  - Fukushima/Miyagi first estimate: source-member centroid about 137.6 km
    from truth, truth outside search box, later replacement drifts to a 319 km
    member centroid.
  - This suggests checking local support growth and search-box truth/proxy
    consistency before promoting or confirming pending candidate regions.
- Current labels:
  - `catalogEvent=true`;
  - `catalogTruthVerified=true`;
  - `observableEvent=true`;
  - `detectableEvent=true`;
  - `includeInDetectionMetrics=false`;
  - `splitStatus=unassigned_reference`.
- Next action: inspect production-available signals that can separate
  Iwate-style true early one-sided candidates from Fukushima/Miyagi false
  candidates. Prioritize candidate persistence, post-candidate baseline
  convergence, station-member evolution and local support growth. Do not
  change production coordinate scoring yet.

## 2026-06-25 Candidate-Region Local Support Gate

- Implemented a diagnostic-only `SourceCandidateLocalSupportGate` in
  `lib/core/source_estimation/source_candidate_region_tracker.dart`.
- The gate does not change `SourceEstimate.latitude/longitude` and never sets
  `production_coordinate_switch_allowed=true`.
- Runtime inputs are production-available only:
  - current `source_trigger_member_ids`;
  - station records already held by `SeismicSourceTracker`;
  - current estimate coordinate;
  - estimate diagnostics `station_geometry`;
  - the pending candidate-region first local-support snapshot.
- Confirmation requires a pending candidate-region inside the existing
  5-second window, current member count >= 8, positive source-member growth
  relative to the pending first frame, current estimate-to-member-centroid
  distance <= 50 km, convergence >= 80 km, and non-`one_sided` current
  geometry.
- `SeismicSourceTracker` now writes
  `candidate_region_local_support_gate` metadata and can confirm an existing
  pending candidate-region even when the current frame has no new diagnostic
  candidate correction.
- Refreshed replay timeline:
  - `20260625_iwate_offshore_m32_jma`: 3 pending candidate frames followed by
    local-support `confirmedDelayed`; coordinate switches remain 0.
  - `20260621_fukushima_offshore_m32_eq6`: 11 pending frames, 2 expired,
    0 confirmed, 0 coordinate switches.
  - `20260622_kushiro_offshore_m30_jma`: existing residual delayed/immediate
    confirmation behavior is unchanged; 0 coordinate switches.
  - `20260622_tomakomai_south_offshore_m35_hinet`: 3 residual immediate
    candidate-region confirmations, 0 local-support confirmations and
    0 coordinate switches.
  - `20260623_tokachi_southeast_offshore_m34_hinet`: 0 candidate-region frames.
- Updated reports:
  - `docs/baselines/source_candidate_region_timeline.generated.md`;
  - `docs/baselines/source_candidate_promotion_matrix.generated.md`;
  - `docs/baselines/iwate_offshore_m32_20260625_member_evolution.generated.md`.
- Tokachi/Tomakomai replay check is complete. The local-support gate introduces
  no false recovery on those cases.
- The unified source-estimation card now appends local-support diagnostics to
  the candidate-region quality line when
  `candidate_region_local_support_gate` metadata is present. It shows source
  member count/growth, current estimate-to-member-centroid distance and
  convergence while retaining the actual `SourceEstimate` coordinate.
- Widget coverage in `test/source_estimation_card_test.dart` verifies a
  local-support delayed confirmation is displayed and the hypocenter remains
  the current production estimate, not the candidate-region coordinate.
- `DebugPage` now adds candidate-region diagnostics to the existing
  `NIED Source Estimation` card: candidate status/reason/point, coordinate
  switch flag, residual gate support and local-support member/geometry
  convergence. This is read-only debug exposure and does not alter map, camera
  or source-coordinate behavior.
- Added `test/source_candidate_region_timeline_report_test.dart` as a local
  replay-matrix guard. After regenerating
  `source_candidate_region_timeline_report/report.json`, it asserts:
  - all six core cases keep `coordinateSwitchAllowedCount == 0`;
  - only `20260625_iwate_offshore_m32_jma` has local-support recovery;
  - Fukushima/Miyagi has no delayed/immediate confirmation;
  - Kushiro keeps the existing residual delayed/immediate confirmations;
  - Tomakomai has residual immediate confirmations only;
  - Tokachi and Aizu have no candidate-region frames.
- `tools/build_source_candidate_region_timeline_report.dart` now writes the
  same matrix check into `validation.status` and `validation.violations`, and
  the generated Markdown includes a `Validation` section. The current six-case
  report is `pass` with no violations.
- The timeline report now also splits delayed confirmation counts by source:
  Kushiro is the residual-delayed case, while Iwate M3.2 is the
  local-support-delayed case. This keeps the residual promotion matrix and the
  local-support recovery path from being conflated.
- Added `test/source_candidate_promotion_matrix_report_test.dart` and
  `tools\validate_source_candidate_promotion_matrix.ps1` to guard the residual
  promotion matrix. The guard regenerates early-frame reports and the promotion
  matrix, then asserts zero offline false accepts, zero delayed false
  recoveries, Fukushima/Iwate residual rejection, and the existing
  Kushiro/Tomakomai accept/recovery behavior.
- `tools/build_source_candidate_promotion_report.dart` now also writes these
  checks into `validation.status` and `validation.violations`, so the generated
  promotion matrix can fail visibly even before the test is opened.
- Local validation command:
  `powershell -NoProfile -ExecutionPolicy Bypass -File tools\validate_source_candidate_region_timeline.ps1`.
  It regenerates `source_candidate_region_timeline_report/report.json` and
  immediately runs `test/source_candidate_region_timeline_report_test.dart`.
  Residual promotion validation command:
  `powershell -NoProfile -ExecutionPolicy Bypass -File tools\validate_source_candidate_promotion_matrix.ps1`.
- Combined candidate-region validation command:
  `powershell -NoProfile -ExecutionPolicy Bypass -File tools\validate_source_candidate_region_suite.ps1`.
  Run this after adding or refreshing replay cases so both the residual
  promotion matrix and the local-support timeline are regenerated and checked.
  The suite also runs `test/source_candidate_validation_scripts_test.dart` so
  the validation entrypoint itself is guarded. On success it writes
  `.dart_tool/source_candidate_region_suite/summary.json`, including the
  embedded `validation.status` and `validation.violations` from both generated
  reports. The suite fails immediately if either embedded report validation is
  not `pass` or contains violations.
- Added `test/source_candidate_validation_scripts_test.dart` as a lightweight
  guard for the validation scripts themselves. It verifies that the suite runs
  both matrix guards and that each guard regenerates its report before running
  its test.
- Added `test/source_candidate_region_suite_summary_test.dart` to validate the
  generated suite summary artifact. The combined suite runs it after writing
  `.dart_tool/source_candidate_region_suite/summary.json`.
- Added `docs/data/source_candidate_region_validation_manifest.json` as the
  machine-readable coverage manifest for candidate-region replay validation.
  `tools/build_source_candidate_region_timeline_report.dart` now uses this
  manifest for its default benchmark inputs and per-case expectations, and the
  generated timeline report embeds the manifest path, roles and expectation
  counters. Future live/replay events should be promoted into this manifest
  before being treated as candidate-region guard coverage.
- Next action: observe more live/replay events and only tune local-support
  thresholds if a false recovery appears. Do not enable production coordinate
  switching, map auto-focus changes or P/S wave behavior from this metadata yet.

## 2026-06-25 Split Assignment Readiness Next-Action Queue

- Extended `tools/build_source_estimation_split_assignment_readiness_report.dart`
  so the readiness report no longer treats every `unassigned_reference` case as
  the same kind of blocker.
- The generated report now includes:
  - `readyForManualSplitAssignment`;
  - `nextAction`;
  - `readyForManualSplitAssignmentCount`;
  - `nextActionCounts`.
- Current generated state:
  - `readyForFrozenSplitCount=1`;
  - `readyForManualSplitAssignmentCount=0`;
  - 12 reference cases still have `assign_event_level_split` pending;
  - `20260622_fukushima_offshore_m22_eq4` has completed its constrained
    event-level split assignment and now reports
    `nextAction=split_assignment_complete`;
  - the plan now recommends `validation` for
    `20260622_fukushima_offshore_m22_eq4` only, with constraints to keep
    `includeInDetectionMetrics=false`, not treat EQuake as catalog truth, and
    not use it for final test claims;
  - recent JMA cases remain blocked by `review_jma_catalog_link` until a
    versioned final catalog source exists;
  - Hi-net preliminary cases remain blocked by manual truth-quality review;
  - `noto_m27_20260621_jma_eq5` remains blocked by source-trigger threshold
    review and capture provenance.
- The small Fukushima offshore reference-only case is now in the validation
  split as `validation_reference`, while `includeInDetectionMetrics=false`,
  `catalogTruthVerified=false` and the no-final-test-claims constraint remain
  intact.
- Validation command:
  `powershell -NoProfile -ExecutionPolicy Bypass -File tools\validate_source_estimation_split_assignment_readiness.ps1`.
- Next action: work the remaining blockers. Do not assign any JMA/Hi-net recent
  event before its catalog/review blocker is cleared.

## 2026-06-25 Split Assignment Patch Dry Run

- Added `tools/build_source_estimation_split_assignment_patch.dart`.
- Default mode is dry-run only. It reads
  `docs/data/source_estimation_split_assignment_plan.json`,
  `test/fixtures/source_estimation/dataset_splits.json` and the fixture
  directory, then writes:
  - `.dart_tool/source_estimation_split_assignment_patch/report.json`;
  - `docs/baselines/source_estimation_split_assignment_patch.generated.md`.
- Current patch report:
  - proposals: 1;
  - ready to apply: 0;
  - already applied: 1;
  - apply requested: false;
  - case: `20260622_fukushima_offshore_m22_eq4`;
  - split: `validation`;
  - fixture `splitStatus`: `validation_reference`;
  - actions: none, because the recommendation is now idempotently applied.
- Added `tools\validate_source_estimation_split_assignment_patch.ps1` and
  `test/source_estimation_split_assignment_patch_test.dart` so the dry-run
  patch is regenerated and checked before review. The test also exercises
  `--apply` against temporary split/fixture files, proving the apply path adds
  the proposal to the requested split and updates only the requested fixture
  `splitStatus`.
- `tools\validate_source_estimation_suite.ps1` now runs the patch dry-run guard
  after split assignment readiness and before candidate-region validation. The
  suite summary records the patch report path, `applyRequested=false` and
  `alreadyAppliedCount=1`.
- Applied the recommendation with
  `dart run tools\build_source_estimation_split_assignment_patch.dart --apply`.
  `test/fixtures/source_estimation/dataset_splits.json` now includes
  `fukushima_offshore_m22_20260622_eq4.json` in `validation`, and the fixture
  now has `splitStatus=validation_reference`.

## 2026-06-26 Split Blocker Queue

- Added `tools/build_source_estimation_split_blocker_queue_report.dart`.
- Added validation entrypoint
  `tools\validate_source_estimation_split_blocker_queue.ps1`.
  It regenerates split assignment readiness first, then writes:
  - `.dart_tool/source_estimation_split_blocker_queue/report.json`;
  - `docs/baselines/source_estimation_split_blocker_queue.generated.md`.
- Added `test/source_estimation_split_blocker_queue_report_test.dart`.
  The test verifies:
  - blocked cases: 11;
  - completed split assignments: 2;
  - no manual-ready blocked cases remain;
  - `20260622_fukushima_offshore_m22_eq4` and
    `noto_m27_20260621_jma_eq5` are listed only under completed split
    assignments, not blockers;
  - current blocker counts are 3 JMA catalog links, 6 Hi-net preliminary truth
    reviews, 1 Hi-net truth review and 1 final-catalog-or-Hi-net-revision link.
- `tools\validate_source_estimation_suite.ps1` now runs the blocker queue guard
  after split readiness and before the JMA catalog availability guard. Its
  summary records `blockedCaseCount=11` and `completedSplitAssignmentCount=2`.
- Next action: clear blockers by evidence class, not by ad hoc split edits:
  first link versioned JMA final catalog records when available, then review
  Hi-net preliminary truth quality. Noto's trigger-threshold/capture blocker is
  already cleared by the constrained validation split below. Do not assign any
  remaining blocker case to train/validation/test until its queue entry
  disappears.

## 2026-06-26 JMA Catalog Availability Guard

- Added `docs/data/jma_catalog_availability.json` as the machine-readable
  availability manifest for official JMA final hypocenter catalog coverage.
    Current evidence is `asOf=2026-06-26`,
    `latestAvailableFinalCatalogYear=2023` and
    `latestAvailableFinalCatalogPeriodEnd=2023-12-31`.
    The 2026-06-26 recheck records observed latest official yearly link `2023`;
    links for 2024/2025/2026 were still absent, so recent 2026 JMA
    source/intensity labels remain reference-only.
- Added `tools/build_jma_catalog_availability_report.dart`.
  It reads the split assignment readiness report and fixture files, then
  isolates pending `review_jma_catalog_link` blockers. A blocker is treated as:
  - `external_catalog_not_yet_available` when its event year is after the
    latest available final catalog year;
  - `catalog_available_link_missing` when the event year is covered but the
    fixture still lacks a versioned `jma_final_catalog` link.
- The report intentionally fails on `catalog_available_link_missing`. This
  turns future JMA catalog publication into an actionable failure instead of a
  silent stale blocker.
- Added validation entrypoint `tools\validate_jma_catalog_availability.ps1`.
  It regenerates split assignment readiness first, builds:
  - `.dart_tool/jma_catalog_availability_report/report.json`;
  - `docs/baselines/jma_catalog_availability.generated.md`;
  then runs `test/jma_catalog_availability_report_test.dart`.
- Current generated state:
  - `jmaCatalogBlockerCount=3`;
  - `externalCatalogNotYetAvailableCount=3`;
  - `catalogAvailableLinkMissingCount=0`;
  - affected cases:
    `20260622_kushiro_offshore_m30_jma`,
    `20260624_fukushima_aizu_m32_jma_eq5`,
    `20260625_iwate_offshore_m32_jma`.
- `tools\validate_source_estimation_suite.ps1` now runs the JMA availability
  guard after blocker queue and before split patch dry-run. Its summary records
  the JMA report path and the three availability counters.
- This does not clear the JMA blockers or promote any 2026 JMA source/intensity
  fixture to `catalog_verified`; it only proves that the current blocker is
  external catalog availability, not missing local link work.
- Next action: continue with the next evidence class in the blocker queue:
  Hi-net preliminary truth-quality review, then Noto trigger-threshold/capture
  provenance.

## 2026-06-26 Hi-net Truth-Quality Review Queue

- Added `tools/build_hinet_truth_quality_review_report.dart`.
  It consumes the split assignment readiness report and extracts pending
  `review_hinet_preliminary_truth_quality` / `review_hinet_truth_quality`
  cases into a focused manual-review ledger.
- Added validation entrypoint `tools\validate_hinet_truth_quality_review.ps1`.
  It regenerates split assignment readiness first, then writes:
  - `.dart_tool/hinet_truth_quality_review/report.json`;
  - `docs/baselines/hinet_truth_quality_review.generated.md`;
  and runs `test/hinet_truth_quality_review_report_test.dart`.
- Current generated state:
  - `hinetReviewCaseCount=7`;
  - `captureDirectoryExistsCount=7`;
  - `referenceIsolatedCount=7`;
  - `manualReviewReadyCount=7`;
  - `catalogTruthFlagMismatchCount=3`.
- The mismatch count is intentional review evidence: some Hi-net
  user-provided/preliminary fixtures have `catalogTruthVerified=true`, but
  their truth source is not `jma_final_catalog`. The report treats that as a
  flag requiring manual review, not as final catalog evidence.
- `tools\validate_source_estimation_suite.ps1` now runs the Hi-net
  truth-quality review guard after JMA catalog availability and before split
  patch dry-run. Its summary records the Hi-net report path and review
  counters.
- This does not clear any Hi-net blocker and does not promote any Hi-net case
  into frozen train/validation/test metrics. It makes the review queue
  auditable and keeps preliminary labels reference-only until a human review or
  later catalog revision resolves each case.

## 2026-06-26 Iwate Offshore M4.6 JMA Candidate

- Added `docs/data/jma_reference_event_candidates.json`.
- Recorded the user-provided JMA source/intensity event:
  - event id: `20260625_iwate_offshore_m46_jma_eqsc9`;
  - origin: `2026-06-26T00:11:51+08:00`
    (`2026-06-26T01:11:51+09:00`);
  - hypocenter: Iwate offshore, `40.3N 142.2E`, M4.6, depth 50 km;
  - maximum shindo: 3;
  - tsunami concern: none.
- Retained the JMA EQSC forecast final report 9 as forecast/reference metadata:
  origin `2026-06-26T00:11:42+08:00`, M4.6, depth 50 km,
  observed max shindo 1 (1.3), estimated max shindo 3 (2.5-3.4).
- Status is `pending_capture_association`, with `captureDirectory=null`.
  It must not enter source-estimation replay denominators until a local NIED
  GIF replay package is associated, and it must not become `catalog_verified`
  until a versioned JMA final catalog record is linked.
- Added `test/jma_reference_event_candidates_test.dart` to keep the JMA
  candidate list reference-only and pending-capture by default.
- Added `tools\validate_jma_reference_event_candidates.ps1` and integrated it
  into `tools\validate_source_estimation_suite.ps1`.
  The guard writes `.dart_tool/jma_reference_event_candidates/summary.json`
  and records the candidate count, pending-capture count, capture-associated
  count, reference-only count, final-catalog-pending count, final EQSC report
  count and final EQuake reference report count.
- This keeps new JMA/EQSC/EQuake-reference candidates auditable without promoting them into
  replay denominators or frozen train/validation/test splits.

## 2026-06-26 Yamanashi Central-West M2.6 JMA Candidate

- Added the user-provided JMA source/intensity event to
  `docs/data/jma_reference_event_candidates.json`:
  - event id: `20260626_yamanashi_central_west_m26_jma_equake5`;
  - origin: `2026-06-26T14:41:13+08:00`
    (`2026-06-26T15:41:13+09:00`);
  - hypocenter: Yamanashi central-west, `35.8N 138.3E`, M2.6, depth 10 km;
  - maximum shindo: 1;
  - tsunami concern: none.
- Retained the EQuake final report 5 as `equakeReport`, not `eqscReport`, to
  avoid mixing EQuake source-estimation reference metadata with JMA EQSC/EEW
  forecast metadata:
  - EQuake origin `2026-06-26T14:41:12+08:00`;
  - EQuake estimate `35.78N 138.25E`, M2.7, depth 18 km;
  - quality A, confidence 83.5%, RMS 0.64 s, azimuthal gap 35 deg;
  - triggers: 102 stations (`P:29`, `S:57`, `O:16`).
- Status is `pending_capture_association`, with `captureDirectory=null`.
  It remains reference-only until a local replay/capture package is explicitly
  linked, and it remains pending final-catalog verification until a versioned
  JMA final catalog record is available.

## 2026-06-26 JMA Reference Capture Association Guard

- Added `tools/build_jma_reference_capture_association_report.dart`.
  It reads `docs/data/jma_reference_event_candidates.json`, scans local
  `tmp/captures` and `test/fixtures/source_estimation`, and reports whether a
  recent JMA reference candidate has an associated local replay/capture package.
- Added `tools\validate_jma_reference_capture_association.ps1` and
  `test/jma_reference_capture_association_report_test.dart`.
- Integrated the guard into `tools\validate_source_estimation_suite.ps1` after
  JMA reference-candidate manifest validation and before Hi-net review.
- Current generated state:
  - event count: 2;
  - pending capture: 2;
  - capture associated: 0;
  - missing local association: 2;
  - local capture candidate matches: 0;
  - local fixture candidate matches: 0.
- For `20260625_iwate_offshore_m46_jma_eqsc9` and
  `20260626_yamanashi_central_west_m26_jma_equake5`, the current authoritative
  local state is therefore: reference-only, pending capture, no local capture
  directory, no replay fixture, and no candidate local match. Do not use either
  case in replay denominators until a capture package is explicitly linked.
- Validation:
    - `dart run tools\build_jma_reference_capture_association_report.dart`;
    - `flutter test test\jma_reference_capture_association_report_test.dart`;
    - `powershell -NoProfile -ExecutionPolicy Bypass -File
      tools\validate_jma_reference_event_candidates.ps1`;
    - `powershell -NoProfile -ExecutionPolicy Bypass -File
      tools\validate_jma_reference_capture_association.ps1`;
    - `powershell -NoProfile -ExecutionPolicy Bypass -File
      tools\validate_source_estimation_suite.ps1`.
  - 2026-06-26 verification after the user-provided Iwate M4.6 JMA/EQSC
    reference confirms the candidate remains reference-only and pending local
    capture association; the full source-estimation validation suite passes.

## 2026-06-26 Noto Source-Trigger Threshold Review

- Repaired the Noto M2.7 fixture JSON region field so strict JSON tools can
  consume `test/fixtures/source_estimation/noto_m27_20260621_jma_eq5.json`.
- Extended split-assignment readiness capture provenance resolution to support
  both current `captureDirectory` and legacy `capture.directory`. This clears
  Noto's `confirm_capture_provenance` condition using existing local evidence,
  without changing its split assignment.
- Refreshed the Noto multilayer gain report after the fixture repair:
  - capture: 151 timestamps, 8 layers, 1208/1208 GIFs, 0 failures;
  - `receivedAtStatus=unavailable_historical_fetch`, so live receive timing is
    still not proven;
  - source trigger missed event: false;
  - triggered frames: 32;
  - JMA-only first estimate delay: 6.0 s;
  - JMA-only first error: 7.46 km;
  - experimental physical fusion first error: 40.63 km.
- Added `tools/build_source_trigger_threshold_review_report.dart` and
  `tools\validate_source_trigger_threshold_review.ps1`.
  The report writes:
  - `.dart_tool/source_trigger_threshold_review/report.json`;
  - `docs/baselines/source_trigger_threshold_review.generated.md`.
- Added `test/source_trigger_threshold_review_report_test.dart` and integrated
  the guard into `tools\validate_source_estimation_suite.ps1`.
- Current decision:
  - capture provenance is locally complete for Noto;
  - the source trigger did not miss the event;
  - `review_source_trigger_threshold_effect` remains pending because the
    existing evidence is a single event plus historical fetch and still lacks
    an independent noise-window validation;
  - physical fusion remains diagnostic/non-production and is not tuned from
    this case.
- Next action: build or select independent quiet/noise windows for the same
  source-trigger threshold configuration, then rerun the threshold review. Only
  after that should Noto move from threshold review to manual split assignment.

## 2026-06-26 Noto Quiet-Window Threshold Validation

- Upgraded `tools/build_source_trigger_threshold_review_report.dart` to
  `source_trigger_threshold_review_v2`.
- `tools\validate_source_trigger_threshold_review.ps1` now regenerates the two
  quiet-window replay artifacts before building the threshold review:
  - `test/source_estimation_batch_test.dart` provides
    `20260614_quiet_175544` from
    `.dart_tool/source_estimation_benchmark/source_estimation_p0.json`;
  - `test/quiet_window_20260625_replay_test.dart` provides
    `quiet_20260625_233535_jst_live` from
    `.dart_tool/source_estimation_benchmark/quiet_20260625_233535_jst_live.json`.
- Current quiet-window validation:
  - quiet windows: 2/2 passed;
  - decoded quiet frames: 341;
  - source-trigger candidate frames: 0;
  - source-trigger confirmed frames: 0;
  - source-estimate false frames: 0.
- Current Noto threshold review:
  - capture provenance locally complete;
  - historical-fetch warning retained;
  - Noto event source trigger was not missed (`triggeredFrameCount=32`);
  - threshold review cleared;
  - physical fusion remains diagnostic/non-production because the first error
    is worse than JMA-only on this case.
- `tools/build_source_estimation_split_assignment_readiness_report.dart` now
  consumes `.dart_tool/source_trigger_threshold_review/report.json` for
  `review_source_trigger_threshold_effect`.
- Readiness/blocker queue state after the refresh:
  - `noto_m27_20260621_jma_eq5`
    `review_source_trigger_threshold_effect=complete`;
  - `confirm_capture_provenance=complete`;
  - remaining condition is only `assign_event_level_split`;
  - Noto is the sole manual-ready blocker.
- `tools\validate_source_estimation_suite.ps1` now runs source-trigger
  threshold review before split-assignment readiness so the blocker queue uses
  the latest quiet-window evidence.
- Next action: decide Noto's constrained split assignment. It should remain
  reference-only (`includeInDetectionMetrics=false`) and should not be used for
  final test claims unless an explicit manual split recommendation is added.

## 2026-06-26 Noto Constrained Validation Split

- Applied the constrained manual split recommendation for
  `noto_m27_20260621_jma_eq5`.
- `test/fixtures/source_estimation/dataset_splits.json` now includes
  `noto_m27_20260621_jma_eq5.json` in the validation split.
- `test/fixtures/source_estimation/noto_m27_20260621_jma_eq5.json` now has
  `splitStatus=validation_reference`.
- Guardrails retained:
  - `includeInDetectionMetrics=false`;
  - JMA source/intensity values remain
    `jma_source_and_intensity_reference_pending_final_catalog`;
  - EQuake remains reference-only;
  - physical fusion remains diagnostic-only;
  - the historical-fetch receive-time warning remains documented;
  - Noto must not be used for final test claims.
- Split/report state after regeneration:
  - frozen-ready source-estimation cases: 2;
  - manual-ready blocked cases: 0;
  - completed split assignments: 2;
  - unassigned reference events: 11.
- Fixed `tools\build_source_trigger_threshold_review_report.dart` so a case
  that already has a non-`unassigned_reference` split reports
  `split_assignment_complete` instead of continuing to request
  `assign_event_level_split`.
- Fixed `tools\validate_source_estimation_suite.ps1` to read and write JSON as
  UTF-8 explicitly, because generated audit reports can contain Japanese region
  labels.
- Validation:
  - `tools\validate_source_trigger_threshold_review.ps1`;
  - `tools\validate_source_estimation_split_assignment_patch.ps1`;
  - `tools\validate_source_estimation_split_assignment_readiness.ps1`;
  - `tools\validate_source_estimation_split_blocker_queue.ps1`;
  - `tools\validate_source_estimation_split_audit.ps1`;
  - `tools\validate_source_estimation_suite.ps1`.
- Next action: continue the remaining blocker queue. The immediate highest
  priority is not another split assignment; it is linking/reviewing source truth
  quality for the 11 remaining unassigned reference events, starting with the
  JMA final-catalog blockers when catalog records become available and the
  Hi-net preliminary review queue otherwise.

## 2026-06-26 Hi-net Review Decision Ledger

- Added `docs/data/hinet_truth_quality_review_decisions.json`.
- The file is a versioned decision ledger for the 7 current Hi-net
  truth-quality review cases.
- Every current case is explicitly recorded as `pending_manual_review`.
- `acceptedForConstrainedReferenceSplit=false` for all 7 cases, so this step
  does not clear any Hi-net blocker and does not create a split recommendation.
- Required follow-up actions are captured per case:
  - catalog truth flag mismatch cases must resolve the mismatch before
    acceptance;
  - preliminary cases must verify a Hi-net revised source or equivalent
    reviewer evidence;
  - `20260620_iwate_offshore_m34_ref` also still needs its capture manifest
    failure resolved before split assignment.
- Extended `tools/build_hinet_truth_quality_review_report.dart` to consume the
  decision ledger and validate:
  - every queued Hi-net review case has a decision entry;
  - accepted decisions must use `accepted_constrained_reference`;
  - accepted decisions must include reviewer, review time and evidence.
- Current generated state:
  - Hi-net review cases: 7;
  - decision cases: 7;
  - pending decisions: 7;
  - accepted constrained references: 0;
  - catalog truth flag mismatches: 3.
- Validation:
  - `tools\validate_hinet_truth_quality_review.ps1`.
- Next action: perform case-by-case Hi-net truth-quality review. Until a case
  is explicitly accepted in the decision ledger with evidence, it must remain
  reference-only and blocked from split assignment.

## 2026-06-26 Hi-net Capture Provenance Detail

- Extended `tools/build_hinet_truth_quality_review_report.dart` so Hi-net
  review cases now read local `capture_manifest.json` and replay `manifest.json`
  when available.
- The generated report now exposes per-case capture provenance fields:
  expected GIF count, downloaded GIF count, failed GIF count, missing replay
  frame count, received-at status and `captureProvenanceComplete`.
- Current generated state:
  - Hi-net review cases: 7;
  - capture manifests present: 7;
  - capture provenance complete: 6;
  - capture manifest failures: 1.
- `20260620_iwate_offshore_m34_ref` is now explicitly flagged with:
  - `captureExpectedGifCount=302`;
  - `captureDownloadedGifCount=301`;
  - `captureFailedGifCount=1`;
  - `captureMissingFrameCount=1`;
  - `capture_provenance_incomplete`.
- Attempted to repair the missing original GIF
  `20260620212727.jma_b.gif` from the recorded NIED URL; the source returned
  HTTP 404, so the file cannot currently be restored from that URL.
- Recorded that failed repair attempt in
  `docs/data/hinet_truth_quality_review_decisions.json` as blocking evidence
  for `20260620_iwate_offshore_m34_ref`.
- The Hi-net review report now parses, validates and exports
  `blockingEvidence` entries. Current generated state:
  - blocking-evidence cases: 1;
  - blocking-evidence entries: 1;
  - blocking-evidence type count: `capture_repair_attempt=1`.
- The top-level source-estimation validation suite also carries
  `blockingEvidenceCaseCount` and `blockingEvidenceCount` in its
  `hinet_truth_quality_review` guard summary.
- This does not clear any Hi-net truth-quality blocker. It only prevents the
  review queue from treating "capture directory exists" as equivalent to a
  complete replay package.
- Validation:
  - `dart run tools\build_hinet_truth_quality_review_report.dart`;
  - `flutter test test\hinet_truth_quality_review_report_test.dart`;
  - `flutter analyze tools\build_hinet_truth_quality_review_report.dart
    test\hinet_truth_quality_review_report_test.dart
    test\source_estimation_validation_suite_test.dart`.
- Next action: explicitly exclude the failed
  `20260620_iwate_offshore_m34_ref` GIF or replace the case with a complete
  capture before that case can be accepted for any constrained reference split;
  do not propose historical re-download after the 3-hour GIF repair window has
  elapsed. Continue truth-quality review for the other six Hi-net cases using
  external revised Hi-net/JMA evidence.

## 2026-06-26 Hi-net Review Queue Prioritization

- Added `tools/build_hinet_truth_quality_review_queue_report.dart`.
  It consumes `.dart_tool/hinet_truth_quality_review/report.json` and turns the
  seven pending Hi-net review cases into an ordered evidence queue.
- Added `tools\validate_hinet_truth_quality_review_queue.ps1` and
  `test/hinet_truth_quality_review_queue_report_test.dart`.
- Integrated the queue guard into `tools\validate_source_estimation_suite.ps1`
  after Hi-net truth-quality review and before split assignment patch dry-run.
- Current generated state:
  - Hi-net review queue cases: 7;
  - priority external-evidence reviews: 3;
  - catalog-flag-mismatch blocked: 3;
  - capture-repair blocked: 1;
  - external evidence missing: 7;
  - accepted constrained references: 0.
- Priority external-evidence review targets are:
  - `20260622_iwate_east_offshore_m30_hinet`;
  - `20260622_tomakomai_south_offshore_m35_hinet`;
  - `20260623_tokachi_southeast_offshore_m34_hinet`.
- These three are first because their local capture packages are complete and
  they do not carry the `catalogTruthVerified=true` / Hi-net-source mismatch.
  They still require a revised Hi-net source or JMA final-catalog link plus
  reviewer metadata before any constrained reference split can be accepted.
- The three catalog-flag-mismatch cases remain blocked until the invalid final
  catalog implication is removed or justified:
  - `20260621_fukushima_offshore_m32_eq6`;
  - `20260622_iwate_offshore_m30_eq10`;
  - `20260622_wakayama_south_m25_hinet`.
- `20260620_iwate_offshore_m34_ref` remains last because the local capture
  package is incomplete and the failed GIF repair attempt is recorded as
  blocking evidence.
- Validation:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_hinet_truth_quality_review_queue.ps1`.
- Next action: collect external revised Hi-net/JMA evidence for the three
  priority cases above. Do not accept them from local capture evidence alone.

## 2026-06-26 Hi-net External Evidence Targets

- Added `docs/data/hinet_external_evidence_targets.json` as the versioned
  checklist for the three priority Hi-net review cases:
  - `20260622_iwate_east_offshore_m30_hinet`;
  - `20260622_tomakomai_south_offshore_m35_hinet`;
  - `20260623_tokachi_southeast_offshore_m34_hinet`.
- Each target records fixture path, origin time, hypocenter fields, capture
  directory, current truth quality and the required external evidence:
  revised Hi-net or JMA final-catalog link plus reviewer/timestamp metadata.
- The target policy explicitly rejects user-provided screenshots/text, EQuake
  source estimates and local capture-only evidence as catalog truth.
- Added `test/hinet_external_evidence_targets_test.dart` and
  `tools\validate_hinet_external_evidence_targets.ps1`.
- Integrated the target guard into
  `tools\validate_source_estimation_suite.ps1`; the suite summary now records
  `targetCount=3` and `pendingExternalEvidenceCount=3`.
- No split, truth-quality, `catalogTruthVerified` or
  `includeInDetectionMetrics` status changes were made.
- Next action: manually collect external evidence for these three targets and
  update `docs/data/hinet_truth_quality_review_decisions.json` only after the
  source link and reviewer metadata are available.

## 2026-06-26 JMA Daily Evidence Collection Pass

- Checked the official JMA daily hypocenter lists for the three Hi-net external
  evidence targets.
- Recorded one `jma_daily_hypocenter_list` finding for each target in
  `docs/data/hinet_external_evidence_targets.json`:
  - `20260622_iwate_east_offshore_m30_hinet` matched the 2026-06-22 JMA daily
    entry at `2026-06-22T11:26:50.1` JST;
  - `20260622_tomakomai_south_offshore_m35_hinet` matched the 2026-06-22 JMA
    daily entry at `2026-06-22T20:37:46.9` JST;
  - `20260623_tokachi_southeast_offshore_m34_hinet` matched the 2026-06-23 JMA
    daily entry at `2026-06-23T23:13:05.7` JST.
- These findings are official external matches, but they are explicitly marked
  `not_sufficient_final_catalog_or_hinet_revised_source` because the target
  policy requires a revised Hi-net source or JMA final/unified catalog evidence
  before constrained split acceptance.
- `test/hinet_external_evidence_targets_test.dart` now asserts that daily JMA
  findings do not change the review decision ledger: all three cases remain
  `pending_manual_review` and `acceptedForConstrainedReferenceSplit=false`.
- The validation suite summary now records:
  - `jmaDailyFindingCount=3`;
  - `sufficientExternalEvidenceCount=0`.
- Next action: try the Hi-net hypocenter map / revised-source path for these
  three cases, or wait for/link a versioned JMA final/unified catalog record.

## 2026-06-26 Hi-net Source Availability Pass

- Checked the official Hi-net source paths for the same three priority targets
  and recorded the result in
  `docs/data/hinet_external_evidence_targets.json` under
  `sourceAvailabilityChecks`.
- Public Hi-net hypocenter map:
  - `https://www.hinet.bosai.go.jp/hypomap/?LANG=en`;
  - available publicly, but only as map-level evidence for recent hypocenters;
  - recorded as
    `not_sufficient_event_level_revised_or_final_source`.
- Hi-net preliminary hypocenter catalog:
  - `https://hinetwww11.bosai.go.jp/auth/hinet_hypolist/?LANG=en`;
  - unauthenticated request returns the registered-user login page;
  - recorded as `login_required` and
    `not_sufficient_without_authenticated_event_row`.
- Hi-net-hosted JMA unified hypocenter catalog:
  - `https://hinetwww11.bosai.go.jp/auth/JMA/?LANG=en`;
  - unauthenticated request returns the registered-user login page;
  - recorded as `login_required` and
    `not_sufficient_without_authenticated_event_row`.
- Hi-net data policy:
  - `https://www.hinet.bosai.go.jp/about_data/?LANG=en`;
  - confirms the automatic Hi-net catalog is preliminary and formal use should
    prefer JMA official/final catalog evidence.
- Added validation coverage so source-availability checks cannot be mistaken
  for event-level accepted evidence:
  - `hinetAvailabilityCheckCount=4`;
  - `hinetLoginRequiredCheckCount=2`;
  - `hinetAcceptedEventEvidenceCheckCount=0`.
- No case was accepted into constrained split; all three targets remain
  `pending_external_evidence`.
- Next action: if authenticated Hi-net access is available, export event-level
  rows from the preliminary/JMA unified catalogs with URL, checked date and
  source/version metadata. Otherwise keep waiting for/linking JMA final or
  unified catalog records.

## 2026-06-26 Authenticated Hi-net Export Request

- Added `docs/data/hinet_authenticated_export_request.json` so the login-gated
  Hi-net step has a concrete, reviewable input contract.
- The request file covers the same three priority cases and records:
  - target origin time and a +/- five-minute JST query window;
  - target hypocenter/magnitude fields from the current fixture label;
  - preferred source `hinet_jma_unified_catalog`;
  - fallback source `hinet_preliminary_catalog`;
  - status `pending_authenticated_export`.
- Required exported row fields are explicit:
  `caseId`, `sourceType`, `sourceUrl`, `sourceVersionOrPageDate`,
  `checkedAtUtc`, `reviewer`, `originTimeJst`, `latitude`, `longitude`,
  `depthKm`, `magnitude`, `region` and `rawRowText`.
- Rejection rules explicitly reject public hypomap-only rows, JMA daily-only
  rows, screenshots without source URL and EQuake estimates.
- Added validation coverage in `test/hinet_external_evidence_targets_test.dart`
  and included the request file in the source-estimation validation-suite
  summary:
  - `authenticatedExportRequestCount=3`;
  - `pendingAuthenticatedExportCount=3`.
- This still does not accept any case. It only makes the authenticated export
  step deterministic once a logged-in Hi-net/JMA catalog row is available.
- Next action: use an authenticated Hi-net session to fill event-level rows for
  the three requests, then update
  `docs/data/hinet_truth_quality_review_decisions.json` only if the row passes
  the required-field and rejection-rule checks.

## 2026-06-26 Authenticated Hi-net Export Row Intake Guard

- Added `docs/data/hinet_authenticated_export_rows.json` as the row-intake
  ledger for authenticated Hi-net/JMA catalog exports.
- The file currently contains one `pending_export` placeholder for each
  authenticated export request:
  - `20260622_iwate_east_offshore_m30_hinet`;
  - `20260622_tomakomai_south_offshore_m35_hinet`;
  - `20260623_tokachi_southeast_offshore_m34_hinet`.
- Pending rows have `submittedRow=null`, `decisionImpact=none_pending_only`
  and do not clear any truth-quality decision.
- Submitted rows must include all source-bound fields before review:
  `caseId`, `sourceType`, `sourceUrl`, `sourceVersionOrPageDate`,
  `checkedAtUtc`, `reviewer`, `originTimeJst`, `latitude`, `longitude`,
  `depthKm`, `magnitude`, `region` and `rawRowText`.
- Accepted source types are deliberately limited to:
  - `hinet_jma_unified_catalog`;
  - `hinet_preliminary_catalog`.
- `test/hinet_external_evidence_targets_test.dart` now validates:
  - row case IDs exactly match authenticated export requests;
  - pending rows remain inert and leave
    `hinet_truth_quality_review_decisions.json` pending;
  - submitted-row validation rejects missing required fields and unsupported
    sources such as JMA daily-only rows.
- `tools\validate_source_estimation_suite.ps1` now includes the row ledger in
  the suite summary:
  - `authenticatedExportRowCount=3`;
  - `pendingAuthenticatedExportRowCount=3`;
  - `submittedAuthenticatedExportRowCount=0`;
  - `rejectedAuthenticatedExportRowCount=0`.
- This still does not accept any case into constrained split. It only creates
  the safe intake point for authenticated event-level rows.
- Next action: fill one row from an authenticated Hi-net/JMA unified catalog
  export, then add a review step that can convert a valid submitted row into
  explicit evidence in `hinet_truth_quality_review_decisions.json`.

## 2026-06-26 Authenticated Hi-net Export Review Guard

- Added `tools/build_hinet_authenticated_export_review_report.dart`.
  It reads:
  - `docs/data/hinet_authenticated_export_request.json`;
  - `docs/data/hinet_authenticated_export_rows.json`;
  - `docs/data/hinet_truth_quality_review_decisions.json`.
- Added `tools\validate_hinet_authenticated_export_review.ps1` and
  `test/hinet_authenticated_export_review_report_test.dart`.
- The report writes:
  - `.dart_tool/hinet_authenticated_export_review/report.json`;
  - `docs/baselines/hinet_authenticated_export_review.generated.md`.
- Current generated state:
  - row count: 3;
  - pending exports: 3;
  - submitted for review: 0;
  - valid submitted rows: 0;
  - decision-evidence ready: 0;
  - accepted decisions: 0.
- The report validates submitted rows against the source-bound required fields
  and accepted source types, then emits an `authenticated_hinet_export_row`
  evidence candidate only when the row is valid.
- The report deliberately does not edit
  `docs/data/hinet_truth_quality_review_decisions.json`. A reviewer must still
  explicitly copy/accept the evidence in the decision ledger before any case can
  clear the Hi-net truth-quality blocker.
- `tools\validate_source_estimation_suite.ps1` now runs the authenticated export
  review guard after `validate_hinet_external_evidence_targets.ps1` and before
  split assignment patch validation.
- Validation:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_hinet_authenticated_export_review.ps1`.
- Next action: once an authenticated Hi-net/JMA row is available, fill one
  `submitted_for_review` row and use this report to produce the exact evidence
  candidate for manual decision-ledger review.

## 2026-06-26 Hi-net Capture Provenance Repair/Exclusion Guard

- Added `docs/data/hinet_capture_provenance_review_decisions.json` as the
  explicit repair/exclusion decision ledger for Hi-net cases whose local
  capture package is incomplete.
- Added `tools/build_hinet_capture_provenance_review_report.dart`,
  `tools\validate_hinet_capture_provenance_review.ps1` and
  `test/hinet_capture_provenance_review_report_test.dart`.
- The report writes:
  - `.dart_tool/hinet_capture_provenance_review/report.json`;
  - `docs/baselines/hinet_capture_provenance_review.generated.md`.
- Current generated state:
  - cases: 1;
  - pending repair/exclusion: 1;
  - exclusion approved: 0;
  - ready after exclusion: 0;
  - unresolved capture issues: 1;
  - failed GIFs: 1;
  - missing frames: 1;
  - blocking evidence: 1.
- The blocked case is `20260620_iwate_offshore_m34_ref`; the missing/failed
  file remains `20260620212727.jma_b.gif`, and the recorded repair URL returned
  HTTP 404.
- `tools\validate_source_estimation_suite.ps1` now runs this guard after
  `validate_hinet_truth_quality_review.ps1` and before
  `validate_hinet_truth_quality_review_queue.ps1`.
- `test/source_estimation_validation_suite_test.dart` now asserts the new
  validation node, summary path, failure sentinel and current unresolved
  capture counts.
- This still does not accept, repair or exclude any case automatically. A
  capture-incomplete Hi-net case remains blocked until the missing frame is
  repaired within the 3-hour historical GIF window, replaced from a verified
  non-expired source, or a reviewer explicitly approves exclusion in the
  decision ledger.
- Validation:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_hinet_capture_provenance_review.ps1`;
  - `flutter analyze tools\build_hinet_capture_provenance_review_report.dart
    test\hinet_capture_provenance_review_report_test.dart
    test\source_estimation_validation_suite_test.dart`;
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_source_estimation_suite.ps1`.
- Next action: either find an alternate source for
  `20260620212727.jma_b.gif`, or make a reviewed exclusion decision with
  reviewer/time/reason/excluded-file metadata. Do not add
  `20260620_iwate_offshore_m34_ref` to train/validation/test until this blocker
  is cleared.

## 2026-06-26 Hi-net Capture Repair Probe

- Extended `tools/build_hinet_capture_repair_probe_report.dart`.
  It reads `.dart_tool/hinet_capture_provenance_review/report.json`, scans local
  repair-candidate roots for affected missing/failed GIF filenames, and emits
  deterministic remote retrieval hints for recognized kmoni GIF filenames.
- Default scan roots:
  - `tmp/captures`;
  - `tmp/quarantine`;
  - `test/fixtures/source_estimation`.
- Added `tools\validate_hinet_capture_repair_probe.ps1` and
  `test/hinet_capture_repair_probe_report_test.dart`.
- The report writes:
  - `.dart_tool/hinet_capture_repair_probe/report.json`;
  - `docs/baselines/hinet_capture_repair_probe.generated.md`.
- Current generated state:
  - cases: 1;
  - affected files: 1;
  - local candidates: 0;
  - valid GIF candidates: 0;
  - remote retrieval hints: 1;
  - repair-candidate ready cases: 0;
  - unresolved repair cases: 1.
- The affected file remains `20260620212727.jma_b.gif`. No matching local GIF
  was found under the configured repair-candidate roots.
- The report now records the deterministic kmoni RealTimeImg hint:
  `https://www.kmoni.bosai.go.jp/data/map_img/RealTimeImg/jma_b/2026/06/20/20260620212727.jma_b.gif`.
  Because public kmoni replay has short retention, old frames are still
  expected to return 404 unless mirrored locally.
- A found GIF would only become a repair candidate with path, byte count and
  SHA-256 metadata. A remote hint is weaker than a found GIF. The probe does
  not download, copy into the capture package, approve exclusion, or approve
  split use.
- `tools\validate_source_estimation_suite.ps1` now runs this probe after
  `validate_hinet_capture_provenance_review.ps1` and before
  `validate_hinet_truth_quality_review_queue.ps1`.
- Validation:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_hinet_capture_repair_probe.ps1`;
  - `flutter analyze tools\build_hinet_capture_repair_probe_report.dart
    test\hinet_capture_repair_probe_report_test.dart
    test\source_estimation_validation_suite_test.dart`;
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_source_estimation_suite.ps1`.
- Next action: obtain `20260620212727.jma_b.gif` from an external/local archive
  and place it under a scanned root for review, or make an explicit reviewed
  exclusion decision. Until then, `20260620_iwate_offshore_m34_ref` remains
  blocked from train/validation/test.

## 2026-06-26 Source-Estimation External Input Queue

- Added `tools/build_source_estimation_external_input_queue_report.dart`.
  It consumes the current generated blocker/capture/export reports and produces
  one consolidated list of external or user-provided inputs that can unblock the
  remaining source-estimation data path.
- Added `tools\validate_source_estimation_external_input_queue.ps1` and
  `test/source_estimation_external_input_queue_report_test.dart`.
- The report writes:
  - `.dart_tool/source_estimation_external_input_queue/report.json`;
  - `docs/baselines/source_estimation_external_input_queue.generated.md`.
- Current generated state:
  - input items: 10;
  - automatic clearances: 0;
  - missing GIF archive copies: 1;
  - authenticated Hi-net/JMA export rows: 3;
  - local JMA reference capture packages: 2;
  - versioned JMA final catalog records: 3;
  - final catalog or Hi-net revision links: 1.
- Highest-priority input remains the missing
  `20260620212727.jma_b.gif` archive copy for
  `20260620_iwate_offshore_m34_ref`. The queue preserves the deterministic
  kmoni hint, but it does not download or repair the capture package.
- The next authenticated inputs are the three pending Hi-net/JMA export rows:
  - `20260622_iwate_east_offshore_m30_hinet`;
  - `20260622_tomakomai_south_offshore_m35_hinet`;
  - `20260623_tokachi_southeast_offshore_m34_hinet`.
- The queue also records the two recent JMA reference candidates still waiting
  for local capture/replay association:
  - `20260625_iwate_offshore_m46_jma_eqsc9`;
  - `20260626_yamanashi_central_west_m26_jma_equake5`.
- This report is intentionally input-only. Providing one queued input merely
  allows the downstream guard to re-evaluate; it does not modify split manifests,
  review ledgers, capture packages or production source-estimation behavior.
- `tools\validate_source_estimation_suite.ps1` now runs this queue after
  authenticated export review and before split-assignment patch validation.
- Validation:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_source_estimation_external_input_queue.ps1`;
  - `flutter analyze tools\build_source_estimation_external_input_queue_report.dart
    test\source_estimation_external_input_queue_report_test.dart
    test\source_estimation_validation_suite_test.dart`.
- Next action: use this queue as the authoritative short list for external
  evidence intake. Do not add the queued cases to train/validation/test until
  their downstream blockers disappear from the generated reports.

## 2026-06-26 Source-Estimation External Input Templates

- Added `tools/build_source_estimation_external_input_template_report.dart`.
  It consumes `.dart_tool/source_estimation_external_input_queue/report.json`
  and turns every queued external input into a machine-readable intake
  template.
- Added `tools\validate_source_estimation_external_input_templates.ps1` and
  `test/source_estimation_external_input_template_report_test.dart`.
- The report writes:
  - `.dart_tool/source_estimation_external_input_templates/report.json`;
  - `docs/baselines/source_estimation_external_input_templates.generated.md`.
- Current generated state:
  - templates: 10;
  - manual-review required: 10;
  - automatic clearances: 0;
  - ledger mutations: 0;
  - missing GIF archive copy templates: 1;
  - authenticated Hi-net/JMA export row templates: 3;
  - local JMA reference capture package templates: 2;
  - versioned JMA final catalog record templates: 3;
  - final catalog or Hi-net revision templates: 1.
- Template coverage now includes concrete intake targets:
  - `20260620212727.jma_b.gif` must be placed under a repair scan root before
    the repair probe can treat it as evidence;
  - the three authenticated Hi-net rows must be submitted through
    `docs/data/hinet_authenticated_export_rows.json` with source-bound fields;
  - `20260625_iwate_offshore_m46_jma_eqsc9` and
    `20260626_yamanashi_central_west_m26_jma_equake5` require explicit
    `captureDirectory` associations in the JMA reference candidate manifest;
  - the three recent JMA blockers must be linked through a versioned official
    JMA final catalog import/link flow;
  - `20260621_iwate_offshore_m33_eq8` still needs a final catalog row or
    reviewed revised Hi-net source.
- `tools\validate_source_estimation_suite.ps1` now runs this template guard
  immediately after the external input queue and before split-assignment patch
  validation. The suite summary records the template count, input type counts,
  manual-review count and the invariant that no automatic clearance or ledger
  mutation occurred.
- The standalone template validator refreshes the external input queue by
  default. The full validation suite passes `-UseExistingQueue` after it has
  already validated the queue, so one suite run does not rebuild the same
  external-evidence dependency chain twice.
- This report is intentionally operational documentation, not evidence. Filling
  a template only makes the downstream guard eligible to re-run; it does not
  clear source truth, capture provenance, final-catalog or split blockers.
- Validation:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_source_estimation_external_input_templates.ps1`;
  - `flutter analyze tools\build_source_estimation_external_input_template_report.dart
    test\source_estimation_external_input_template_report_test.dart
    test\source_estimation_validation_suite_test.dart`.
- Next action: when one external input becomes available, fill exactly the
  matching template, rerun its local validator, then rerun
  `tools\validate_source_estimation_external_input_queue.ps1` and
  `tools\validate_source_estimation_external_input_templates.ps1` to confirm
  the queue changes before any split assignment is considered.

## 2026-06-26 Source-Estimation External Input Delta Guard

- Added `tools/build_source_estimation_external_input_delta_report.dart`.
  It compares `.dart_tool/source_estimation_external_input_queue/report.json`
  with `.dart_tool/source_estimation_external_input_templates/report.json` by
  the stable key `inputType::caseId`.
- Added `tools\validate_source_estimation_external_input_delta.ps1` and
  `test/source_estimation_external_input_delta_report_test.dart`.
- The report writes:
  - `.dart_tool/source_estimation_external_input_delta/report.json`;
  - `docs/baselines/source_estimation_external_input_delta.generated.md`.
- Current generated state:
  - delta rows: 10;
  - matched templates: 10;
  - missing templates: 0;
  - stale templates: 0;
  - priority mismatches: 0;
  - non-manual-review templates: 0;
  - automatic-clearance templates: 0.
- The guard fails if:
  - a queued external input has no matching template;
  - a template exists for an input no longer in the queue;
  - a template changes the queued priority;
  - a template is not manual-review-gated;
  - a template or template summary allows automatic clearance or ledger
    mutation.
- Integrated the delta guard into `tools\validate_source_estimation_suite.ps1`
  immediately after external input templates and before split-assignment patch
  validation. The suite summary now records coverage and safety booleans:
  `coverageComplete=true` and `safeTemplateSemantics=true`.
- This guard still does not clear any blocker, edit any ledger, modify capture
  packages or promote split assignment. It only proves that the operational
  intake instructions stay synchronized with the authoritative queue.
- Validation:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_source_estimation_external_input_delta.ps1
    -UseExistingQueue -UseExistingTemplates`;
  - `flutter analyze tools\build_source_estimation_external_input_delta_report.dart
    test\source_estimation_external_input_delta_report_test.dart
    test\source_estimation_validation_suite_test.dart`.
- Next action: continue working the external input queue by evidence class. If
  a user provides a GIF, authenticated Hi-net row, local capture package or JMA
  final catalog file, fill only its matching template, rerun the local validator,
  then rerun queue, template and delta guards before any split assignment is
  considered.

## 2026-06-26 External Input Queue Validator Dependency Reuse

- Extended `tools\validate_source_estimation_external_input_queue.ps1` with
  dependency reuse switches:
  - `-UseExistingDependencies`;
  - `-UseExistingBlockerQueue`;
  - `-UseExistingJmaCapture`;
  - `-UseExistingHinetRepair`;
  - `-UseExistingHinetExport`.
- Standalone queue validation still refreshes every dependency by default, so
  direct use remains safe.
- `tools\validate_source_estimation_suite.ps1` now calls the queue validator
  with `-UseExistingDependencies` because the suite has already validated and
  regenerated:
  - split blocker queue;
  - JMA reference capture association;
  - Hi-net capture repair probe;
  - authenticated Hi-net export review.
- This is a validation-runtime optimization only. It does not change queue
  contents, external evidence semantics, templates, delta coverage, split
  readiness, ledgers, capture packages or production source-estimation
  behavior.
- Next action remains unchanged: work the external input queue by evidence
  class, then rerun the relevant local validator plus queue/template/delta
  guards before considering split assignment.

## 2026-06-26 Hi-net Validator Dependency Reuse

- Extended Hi-net validation scripts with suite-only dependency reuse switches:
  - `tools\validate_hinet_capture_provenance_review.ps1
    -UseExistingTruthReview`;
  - `tools\validate_hinet_capture_repair_probe.ps1
    -UseExistingProvenanceReview`;
  - `tools\validate_hinet_truth_quality_review_queue.ps1
    -UseExistingTruthReview`.
- Standalone execution still refreshes dependencies by default:
  - provenance review refreshes truth-quality review;
  - repair probe refreshes provenance review;
  - truth-quality review queue refreshes truth-quality review.
- `tools\validate_source_estimation_suite.ps1` now uses those switches because
  the suite already runs the required upstream validators before each dependent
  guard.
- The suite summary records the exact reuse commands for the three Hi-net
  validations, making accidental regression to dependency re-expansion visible
  in `test/source_estimation_validation_suite_test.dart`.
- This is a validation-runtime optimization only. It does not alter Hi-net
  review decisions, capture repair/exclusion state, repair probe candidates,
  external input queue contents, split readiness or production behavior.
- Next action remains unchanged: clear external evidence blockers or keep
  reducing validation friction without changing evidence semantics.

## 2026-06-26 Validation Suite Readiness Dependency Reuse

- Extended the remaining readiness-dependent validators with suite-only reuse
  switches:
  - `tools\validate_source_estimation_split_blocker_queue.ps1
    -UseExistingReadiness`;
  - `tools\validate_jma_catalog_availability.ps1 -UseExistingReadiness`;
  - `tools\validate_hinet_truth_quality_review.ps1 -UseExistingReadiness`;
  - `tools\validate_hinet_authenticated_export_review.ps1
    -UseExistingExternalEvidenceTargets`.
- Standalone execution remains conservative:
  - split blocker queue, JMA catalog availability and Hi-net truth-quality
    review still regenerate split-assignment readiness unless the explicit
    reuse switch is passed;
  - authenticated export review still validates external evidence targets
    unless the explicit reuse switch is passed.
- `tools\validate_source_estimation_suite.ps1` now passes these switches only
  after the suite has already regenerated the corresponding upstream reports.
  The generated suite summary records the exact command strings, and
  `test/source_estimation_validation_suite_test.dart` fails if those reuse
  commands regress.
- This is a validation-runtime optimization only. It does not change split
  readiness, blocker counts, JMA catalog availability, Hi-net review decisions,
  external input queue contents, templates, delta coverage or production
  source-estimation behavior.
- Next action remains unchanged: continue the external input queue by evidence
  class. If no external evidence is available, continue reducing validation
  friction only where standalone validators keep safe dependency regeneration
  by default.

## 2026-06-26 External Input Attempt Ledger

- Added `docs/data/source_estimation_external_input_attempts.json` for
  negative operational attempts against queued external inputs.
- Added `tools/build_source_estimation_external_input_attempt_report.dart`,
  `tools\validate_source_estimation_external_input_attempts.ps1` and
  `test/source_estimation_external_input_attempt_report_test.dart`.
- The report writes:
  - `.dart_tool/source_estimation_external_input_attempts/report.json`;
  - `docs/baselines/source_estimation_external_input_attempts.generated.md`.
- Current recorded attempts cover the highest-priority missing GIF blocker and
  the two pending JMA reference capture packages:
  - local exact filename scan for `20260620212727.jma_b.gif` across
    `tmp/captures`, `tmp/quarantine`, `test/fixtures/source_estimation`,
    `C:/Users/Rhythm/Downloads` and `C:/Users/Rhythm/Pictures` found no valid
    `jma_b` copy;
  - remote kmoni hint recheck for the same timestamp failed by timeout or
    connection failure from the current environment.
  - repeated local exact filename scan still found no valid
    `20260620212727.jma_b.gif`;
  - local timestamp/keyword scan found no replay or capture package for
    `20260625_iwate_offshore_m46_jma_eqsc9`;
  - local timestamp/keyword scan found no replay or capture package for
    `20260626_yamanashi_central_west_m26_jma_equake5`.
  - both authenticated Hi-net/JMA source paths returned the registered-user
    login page from the current command environment, so no event-level
    authenticated row could be exported for
    `20260622_iwate_east_offshore_m30_hinet`,
    `20260622_tomakomai_south_offshore_m35_hinet` or
    `20260623_tokachi_southeast_offshore_m34_hinet`.
  - a later cookie-backed form-login attempt against the same authenticated
    Hi-net/JMA source paths still redirected both catalog pages back to the
    registered-user login page for those three cases. No credentials, cookies
    or exported rows are stored in the repository.
  - official JMA monthly hypocenter bulletin availability was rechecked for
    `20260622_kushiro_offshore_m30_jma`,
    `20260624_fukushima_aizu_m32_jma_eq5` and
    `20260625_iwate_offshore_m32_jma`; the latest yearly final-catalog link is
    still 2023, so those 2026 cases cannot be linked to a versioned JMA final
    catalog yet.
  - `20260621_iwate_offshore_m33_eq8` was checked against the same JMA final
    catalog availability plus the currently reachable authenticated Hi-net/JMA
    revision paths; no final catalog row or revised event-level Hi-net/JMA
    source row is available to this environment yet, so the EQuake text remains
    reference-only.
- These rows are explicitly `negative_attempt_only` and
  `automaticClearance=false`. They do not prove the frame is permanently
  unavailable, do not copy any file into a capture package, do not approve an
  exclusion, do not edit review ledgers, do not reject the authenticated row
  path and do not change split assignment.
- `tools\validate_source_estimation_suite.ps1` runs this guard after queue,
  template and delta validation and before split-assignment patch validation,
  using `-UseExistingQueue` because the suite already regenerated the queue.
- Next action remains unchanged: obtain a valid local copy of
  `20260620212727.jma_b.gif` or make an explicit reviewed exclusion decision.
  Until then, the attempt ledger only prevents repeated untracked searches.

## 2026-06-26 External Input Worklist

- Added `tools/build_source_estimation_external_input_worklist_report.dart`.
  It joins the external input queue, generated templates and negative-attempt
  report into one operational worklist.
- Added `tools\validate_source_estimation_external_input_worklist.ps1` and
  `test/source_estimation_external_input_worklist_report_test.dart`.
- The report writes:
  - `.dart_tool/source_estimation_external_input_worklist/report.json`;
  - `docs/baselines/source_estimation_external_input_worklist.generated.md`.
- Current generated state:
  - open external inputs: 10;
  - inputs with recorded attempts: 10;
  - inputs without attempts: 0;
  - recorded negative attempts: 15;
  - manual-review required: 10;
  - automatic clearances: 0;
  - highest-priority input remains
    `missing_gif_archive_copy::20260620_iwate_offshore_m34_ref`.
- This worklist is deliberately operational only. It does not clear capture,
  catalog, truth-quality or split blockers, and it does not turn negative
  attempts into evidence.
- `tools\validate_source_estimation_suite.ps1` now runs this guard after
  external input attempts and before split-assignment patch validation, using
  existing queue/template/attempt reports already generated by the suite.
- Validation:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_source_estimation_external_input_worklist.ps1
    -UseExistingQueue -UseExistingTemplates -UseExistingAttempts`;
  - `flutter analyze tools\build_source_estimation_external_input_worklist_report.dart
    test\source_estimation_external_input_worklist_report_test.dart
    test\source_estimation_validation_suite_test.dart`.
- Next action remains unchanged: obtain the missing GIF, submit one
  authenticated Hi-net/JMA row, associate a local JMA reference capture package
  or link a versioned JMA final catalog record. After any one of those inputs
  changes, rerun the local validator plus queue/template/delta/attempt/worklist
  guards before considering split assignment.

## 2026-06-26 Authenticated Export Row Importer

- Added `tools/import_hinet_authenticated_export_row.dart` as the safe intake
  path for a manually exported Hi-net/JMA authenticated event row.
- The importer reads one JSON payload containing only the required event-level
  fields, validates it against `docs/data/hinet_authenticated_export_rows.json`,
  and replaces the matching `pending_export` row with
  `submitted_for_review`.
- The importer rejects payloads that contain credential or session-like fields
  such as `username`, `password`, `cookie`, `authorization`, `session` or
  `token`. It stores only source-bound event evidence and never stores login
  material.
- The importer still does not approve the row for split use. A valid submitted
  row only makes the authenticated export review report produce an
  `evidenceCandidate`; a reviewer still has to update the truth-quality
  decision ledger explicitly.
- Usage:

```powershell
dart run tools\import_hinet_authenticated_export_row.dart `
  --input tmp\hinet_authenticated_row.json

powershell -NoProfile -ExecutionPolicy Bypass -File `
  tools\validate_hinet_authenticated_export_review.ps1
```

- Validation:
  - `flutter test test\hinet_authenticated_export_row_import_test.dart`;
  - `flutter analyze tools\import_hinet_authenticated_export_row.dart
    test\hinet_authenticated_export_row_import_test.dart`.

## 2026-06-26 Authenticated Export Row Scratch Templates

- Added `tools/build_hinet_authenticated_export_row_templates.dart` to generate
  per-case scratch JSON files for the three pending authenticated Hi-net/JMA
  export rows.
- The generated files live under
  `.dart_tool/hinet_authenticated_export_row_templates/files/` and are not
  committed evidence. They only give the reviewer a safe, source-bound shape to
  fill from an authenticated event-level row.
- The template report writes:
  - `.dart_tool/hinet_authenticated_export_row_templates/report.json`;
  - `docs/baselines/hinet_authenticated_export_row_templates.generated.md`.
- The importer now rejects unresolved `<fill-...>` placeholders, so a scratch
  template cannot be imported until reviewer, checked time, source version,
  numeric hypocenter fields and raw row text are actually filled.
- `tools\validate_hinet_authenticated_export_review.ps1` now builds these
  scratch templates and runs `test\hinet_authenticated_export_row_template_test.dart`
  alongside the existing review and importer tests.
- This still does not clear any blocker. The authenticated export rows remain
  `pending_export` until a real filled row is imported, and even then the row is
  only `submitted_for_review`.
- `tools\validate_source_estimation_suite.ps1` records the scratch-template
  report path and row-template counts in the suite summary so the generated
  review scaffolding is visible to the top-level guard, not only to the nested
  authenticated-export validator.

## 2026-06-26 Hi-net Capture Exclusion Scratch Templates

- Added `tools/build_hinet_capture_exclusion_template_report.dart` to generate
  manual-review scratch templates for unresolved Hi-net capture provenance
  cases.
- The current template targets
  `20260620_iwate_offshore_m34_ref`, where
  `20260620212727.jma_b.gif` is missing and one frame remains unresolved.
- The report writes:
  - `.dart_tool/hinet_capture_exclusion_templates/report.json`;
  - `.dart_tool/hinet_capture_exclusion_templates/files/*.json`;
  - `docs/baselines/hinet_capture_exclusion_templates.generated.md`.
- These files are operational scaffolding only. They do not edit
  `docs/data/hinet_capture_provenance_review_decisions.json`, do not approve
  an exclusion, do not clear the capture blocker and do not change split
  assignment.
- The generated template requires explicit reviewer, reviewed timestamp,
  excluded file list and reason before it can be copied into the decision
  ledger. Prefer repairing the missing GIF before using the exclusion path.
- `tools\validate_hinet_capture_provenance_review.ps1` now builds the scratch
  template report and runs
  `test\hinet_capture_exclusion_template_report_test.dart`.
- `tools\validate_source_estimation_suite.ps1` records the exclusion-template
  report path and safety counts in the suite summary. The suite asserts:
  - manual-review required: `1`;
  - automatic clearances: `0`;
  - ledger mutations: `0`;
  - affected files: `1`.
- Added `tools/build_hinet_capture_exclusion_review_packet.dart` to collect the
  unresolved capture issue, blocking evidence, generated exclusion template,
  suggested excluded files and importer dry-run command into one manual review
  packet.
- The review packet writes:
  - `.dart_tool/hinet_capture_exclusion_review_packet/report.json`;
  - `docs/baselines/hinet_capture_exclusion_review_packet.generated.md`.
- The review packet is not approval evidence. It records
  `automaticClearance=0`, `ledgerMutation=0` and
  `readyAfterExclusion=0`; the capture blocker stays open until a valid GIF is
  repaired or an explicit reviewed decision is imported.
- Added `tools/import_hinet_capture_exclusion_decision.dart` as the safe
  intake path for a filled exclusion template. It rejects unresolved
  `<fill-...>` placeholders, credential/session-like fields, non-pending
  cases, unsupported decision status, invalid review timestamps and excluded
  file lists that do not cover the reported capture issue.
- The importer writes only a sanitized white-listed decision object into
  `docs/data/hinet_capture_provenance_review_decisions.json`; `_instructions`,
  `_captureIssue` and any operational scratch fields are never persisted.
- Use `--dry-run` first to verify a filled template without mutating the
  decision ledger:

```powershell
dart run tools\import_hinet_capture_exclusion_decision.dart `
  --input tmp\filled_hinet_capture_exclusion.json `
  --dry-run
```

- `tools\validate_hinet_capture_provenance_review.ps1` now also runs
  `test\hinet_capture_exclusion_decision_import_test.dart`, so the importer
  remains covered by the same capture-provenance guard.
- Next action remains unchanged: obtain a valid
  `20260620212727.jma_b.gif` archive copy, or make an explicit reviewed
  exclusion decision. Until then, the blocker remains open by design.

## 2026-06-26 Hi-net Authenticated Export Review Packet

- Added `tools/build_hinet_authenticated_export_review_packet.dart` to collect
  the three pending authenticated Hi-net/JMA row exports into per-case manual
  review packets.
- The packet joins:
  - `docs/data/hinet_authenticated_export_request.json`;
  - `docs/data/hinet_authenticated_export_rows.json`;
  - `.dart_tool/hinet_authenticated_export_row_templates/report.json`.
- The report writes:
  - `.dart_tool/hinet_authenticated_export_review_packet/report.json`;
  - `docs/baselines/hinet_authenticated_export_review_packet.generated.md`.
- Current generated state:
  - packets: `3`;
  - manual-review required: `3`;
  - automatic clearances: `0`;
  - ledger mutations: `0`;
  - submitted rows: `0`;
  - decision-ready evidence rows: `0`;
  - credential fields: `0`.
- Each packet records the target origin, query window, preferred/fallback
  authenticated source type, scratch template path and importer dry-run
  command. It does not store credentials, cookies, sessions or tokens.
- `tools\validate_hinet_authenticated_export_review.ps1` now builds the packet
  after scratch templates and runs
  `test\hinet_authenticated_export_review_packet_test.dart`.
- `tools\validate_source_estimation_suite.ps1` records the packet report path
  and safety counters in the top-level summary.
- This packet is operational intake scaffolding only. It does not submit a row,
  approve truth-quality review, mutate the decision ledger, clear external
  evidence blockers, change split assignment or affect production source
  estimation.
- Next action remains unchanged: obtain a real authenticated event-level
  Hi-net/JMA row, import it with `--dry-run` first, then rerun the authenticated
  export validator and the top-level source-estimation suite.

## 2026-06-26 JMA Reference Capture Review Packet

- Added `tools/build_jma_reference_capture_review_packet.dart` to collect the
  pending recent JMA source/intensity reference events that still need an
  existing local replay/capture package.
- The packet joins:
  - `docs/data/jma_reference_event_candidates.json`;
  - `.dart_tool/jma_reference_capture_association/report.json`.
- The report writes:
  - `.dart_tool/jma_reference_capture_review_packet/report.json`;
  - `docs/baselines/jma_reference_capture_review_packet.generated.md`.
- Current generated state:
  - packets: `2`;
  - manual-review required: `2`;
  - automatic clearances: `0`;
  - manifest mutations: `0`;
  - capture associations cleared by packet: `0`;
  - final catalog truth labels: `0`;
  - local candidate matches: `0`.
- Each packet records the reference event origin, location, max shindo,
  existing local capture/fixture candidates, required local files and the
  validation command. It intentionally does not depend on the external-input
  template report because that queue is generated downstream from the capture
  association report.
- `tools\validate_jma_reference_capture_association.ps1` now builds the packet
  after the association report and runs
  `test\jma_reference_capture_review_packet_test.dart`.
- `tools\validate_source_estimation_suite.ps1` records the packet report path
  and safety counters in the top-level summary.
- This packet is operational intake scaffolding only. It does not edit
  `docs/data/jma_reference_event_candidates.json`, does not associate a capture
  package, does not mark final-catalog truth, does not clear split blockers and
  does not affect production source estimation.
- Next action remains unchanged: provide or locate a real local replay/capture
  package for one of the two pending JMA reference events, then rerun
  `tools\validate_jma_reference_capture_association.ps1` and the top-level
  source-estimation suite.

## 2026-06-26 JMA Final Catalog Review Packet

- Added `tools/build_jma_final_catalog_review_packet.dart` to collect the
  `versioned_jma_final_catalog_record` blockers into per-case manual review
  packets.
- The packet joins:
  - `.dart_tool/jma_catalog_availability_report/report.json`;
  - `docs/data/jma_catalog_availability.json` through the availability report.
- The report writes:
  - `.dart_tool/jma_final_catalog_review_packet/report.json`;
  - `docs/baselines/jma_final_catalog_review_packet.generated.md`.
- Current generated state:
  - packets: `3`;
  - manual-review required: `3`;
  - automatic clearances: `0`;
  - fixture mutations: `0`;
  - catalog truth writes: `0`;
  - write-link allowed: `0`;
  - external catalog not yet available: `3`.
- Current availability evidence still records 2023 as the latest official JMA
  final-catalog year, with 2024, 2025 and 2026 links missing. Therefore the
  2026 Kushiro, Fukushima Aizu and Iwate blockers remain
  `external_catalog_not_yet_available`.
- Each packet records the fixture path, event year, availability evidence,
  import command and dry-run link command. `--write` is listed only as a
  future command and is currently gated by `writeLinkAllowed=false`.
- `tools\validate_jma_catalog_availability.ps1` now builds the packet after
  the availability report and runs
  `test\jma_final_catalog_review_packet_test.dart`.
- `tools\validate_source_estimation_suite.ps1` records the packet report path
  and safety counters in the top-level summary.
- This packet is operational intake scaffolding only. It does not import a
  catalog, does not run `link_jma_catalog.dart --write`, does not mutate
  fixtures, does not mark final-catalog truth, does not clear split blockers
  and does not affect production source estimation.
- Next action remains unchanged: once a versioned official JMA final catalog
  covering 2026 is available, import it, run the link command without `--write`
  first, inspect the match, then rerun catalog availability and the top-level
  source-estimation suite before any fixture mutation is considered.

## 2026-06-26 Final Catalog Or Hi-net Revision Review Packet

- Added `tools/build_final_catalog_or_hinet_revision_review_packet.dart` to
  collect blockers whose required evidence can be either a versioned JMA final
  catalog row or an authenticated revised Hi-net/JMA source row.
- The current packet targets `20260621_iwate_offshore_m33_eq8`, which is still
  based on a user-provided EQuake final report and therefore remains
  `reference_only`.
- The packet joins:
  - `.dart_tool/source_estimation_split_blocker_queue/report.json`;
  - `docs/data/source_estimation_external_input_attempts.json`;
  - `test/fixtures/source_estimation/*.json`.
- The report writes:
  - `.dart_tool/final_catalog_or_hinet_revision_review_packet/report.json`;
  - `docs/baselines/final_catalog_or_hinet_revision_review_packet.generated.md`.
- Current generated state:
  - packets: `1`;
  - manual-review required: `1`;
  - automatic clearances: `0`;
  - fixture mutations: `0`;
  - split manifest mutations: `0`;
  - truth promotions: `0`;
  - negative attempts: `1`;
  - resolution allowed by packet: `0`.
- `tools\validate_source_estimation_split_blocker_queue.ps1` now builds this
  packet after regenerating the blocker queue and runs
  `test\final_catalog_or_hinet_revision_review_packet_test.dart`.
- `tools\validate_source_estimation_suite.ps1` records the packet report path
  and safety counters in the top-level summary.
- This packet is operational intake scaffolding only. It does not promote
  EQuake source-estimation text to truth, does not link a final catalog, does
  not accept a Hi-net revision, does not mutate fixtures or split manifests and
  does not affect production source estimation.
- Next action remains unchanged: obtain either a versioned JMA final catalog
  row for the event or an authenticated revised Hi-net/JMA event row, then
  rerun the split blocker queue and top-level source-estimation suite before
  considering split assignment.

## 2026-06-26 Hi-net Capture Repair Candidate Importer

- Added `tools/import_hinet_capture_repair_candidate.dart` as the safe intake
  path for a reviewer-supplied local GIF repair candidate.
- The importer validates:
  - the case is still `pending_capture_repair_or_exclusion`;
  - the candidate file name matches the missing GIF exactly;
  - the candidate is a GIF;
  - the supplied SHA-256 matches the local bytes;
  - reviewer, reviewed time and source description are filled;
  - no credential, cookie, session, token or auth-like field is present.
- In `--dry-run` mode it validates the repair package without copying the GIF
  or mutating any manifest or decision file.
- Without `--dry-run`, it copies the reviewed GIF into the capture package,
  removes the matching `manifest.json` missing-frame entry, repairs the
  matching `capture_manifest.json` failed record and records
  `capture_frame_repaired` in
  `docs/data/hinet_capture_provenance_review_decisions.json`.
- The importer is intentionally narrow: it only repairs the exact affected file
  and never changes source truth, split assignment, final-catalog labels,
  Hi-net truth-quality decisions or production source-estimation behavior.
- `tools\validate_hinet_capture_repair_probe.ps1` now runs
  `test\hinet_capture_repair_candidate_import_test.dart`, covering dry-run,
  temp-package repair and rejection of placeholders or auth material.
- `tools/build_hinet_capture_provenance_review_report.dart` no longer warns
  when a completed repair decision is absent from the incomplete-capture queue.
- Validation:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_hinet_capture_repair_probe.ps1
    -UseExistingProvenanceReview`.
- Next action remains unchanged: obtain a valid local
  `20260620212727.jma_b.gif`, run the importer with `--dry-run` first, then
  rerun capture repair/provenance review and the top-level source-estimation
  suite before considering any split assignment.

## 2026-06-26 Hi-net Capture Repair Import Template

- Extended `tools/build_hinet_capture_repair_probe_report.dart` so the repair
  probe now emits a concrete scratch import template for each affected GIF.
- The current generated template targets:
  - case: `20260620_iwate_offshore_m34_ref`;
  - missing file: `20260620212727.jma_b.gif`;
  - capture directory:
    `tmp/captures/20260620_212527_jst_iwate_offshore_m34_ref`;
  - output file:
    `.dart_tool/hinet_capture_repair_probe/files/20260620_iwate_offshore_m34_ref.20260620212727.jma_b.gif.repair.json`.
- The repair probe report now records:
  - template directory:
    `.dart_tool/hinet_capture_repair_probe/files`;
  - repair input templates: `1`;
  - manual-review required: `1`;
  - automatic clearances: `0`;
  - repair-candidate ready cases: `0`;
  - unresolved repair cases: `1`.
- The scratch template is intentionally not importable as generated. It keeps
  `<fill-...>` placeholders for reviewer, reviewed timestamp, local
  `candidatePath`, exact `expectedSha256` and source description until a real
  local GIF candidate exists.
- If exactly one valid local GIF candidate is later found by the probe, the
  corresponding template is prefilled with that local candidate path and
  SHA-256 while still requiring reviewer metadata before the importer accepts
  it.
- This remains an intake aid only. It does not copy files, clear blockers,
  mutate capture manifests, edit decision ledgers, promote source truth, change
  split assignment or affect production source-estimation behavior.
- Validation:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_hinet_capture_repair_probe.ps1
    -UseExistingProvenanceReview`.
- Next action remains unchanged: place a reviewed local copy of
  `20260620212727.jma_b.gif` under a repair scan root, rerun the repair probe,
  fill the generated template, run
  `dart run tools\import_hinet_capture_repair_candidate.dart --input
  .dart_tool/hinet_capture_repair_probe/files/20260620_iwate_offshore_m34_ref.20260620212727.jma_b.gif.repair.json
  --dry-run`, then only after review run the importer without `--dry-run`.

## 2026-06-26 External Worklist Operation Artifact Link

- Extended `tools/build_source_estimation_external_input_worklist_report.dart`
  so the external-input worklist can join the Hi-net capture repair probe.
- `tools\validate_source_estimation_external_input_worklist.ps1` now refreshes
  the repair probe by default. The top-level validation suite passes
  `-UseExistingRepairProbe` because the repair probe is already generated
  earlier in the suite.
- The worklist report now records:
  - `repairProbePath`:
    `.dart_tool/hinet_capture_repair_probe/report.json`;
  - operation artifacts: `1`;
  - the next input remains
    `missing_gif_archive_copy::20260620_iwate_offshore_m34_ref`;
  - the first row links the repair import template:
    `.dart_tool/hinet_capture_repair_probe/files/20260620_iwate_offshore_m34_ref.20260620212727.jma_b.gif.repair.json`;
  - the linked artifact still has candidate status
    `awaiting_local_gif_candidate`.
- `operationArtifact` is deliberately named as an operational aid, not as
  evidence. It points reviewers to the next file/command to use after a real
  GIF candidate exists. It does not clear any external input, does not approve
  truth, does not edit capture manifests, does not change split assignment and
  does not affect production source-estimation behavior.
- Validation:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_source_estimation_external_input_worklist.ps1
    -UseExistingQueue -UseExistingTemplates -UseExistingAttempts
    -UseExistingRepairProbe`.
- Next action remains unchanged: obtain or provide a reviewed local
  `20260620212727.jma_b.gif`, rerun the repair probe so the operation artifact
  can become prefilled, then dry-run the generated repair import template.

## 2026-06-26 Authenticated Export Worklist Operation Artifact Link

- Extended `tools/build_source_estimation_external_input_worklist_report.dart`
  so the external-input worklist can also join
  `.dart_tool/hinet_authenticated_export_review_packet/report.json`.
- `tools\validate_source_estimation_external_input_worklist.ps1` now refreshes
  the authenticated export review packet by default. The top-level validation
  suite passes `-UseExistingAuthenticatedExportPacket` because the packet is
  already generated earlier in the suite.
- The worklist report now records:
  - `authenticatedExportPacketPath`:
    `.dart_tool/hinet_authenticated_export_review_packet/report.json`;
  - operation artifacts: `4`;
  - one capture repair artifact for
    `missing_gif_archive_copy::20260620_iwate_offshore_m34_ref`;
  - three authenticated export row artifacts for:
    `20260622_iwate_east_offshore_m30_hinet`,
    `20260622_tomakomai_south_offshore_m35_hinet` and
    `20260623_tokachi_southeast_offshore_m34_hinet`.
- Each authenticated export artifact links the per-case scratch JSON template,
  importer dry-run command, preferred/fallback Hi-net source URLs, query window
  and row status. The current row status remains `pending_export`.
- This is still operational scaffolding only. It does not store credentials,
  cookies, sessions or tokens; does not submit a row; does not accept a truth
  label; does not mutate review ledgers; does not clear split blockers; and
  does not affect production source-estimation behavior.
- Validation:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_source_estimation_external_input_worklist.ps1
    -UseExistingQueue -UseExistingTemplates -UseExistingAttempts
    -UseExistingRepairProbe -UseExistingAuthenticatedExportPacket`.
- Next action remains unchanged: fill one authenticated event-level Hi-net/JMA
  row into its generated template, run the importer with `--dry-run`, then
  rerun authenticated export review and the top-level source-estimation suite
  before considering any truth-quality decision.

## 2026-06-26 External Worklist Full Operation Artifact Coverage

- Extended `tools/build_source_estimation_external_input_worklist_report.dart`
  so the external-input worklist also joins:
  - `.dart_tool/jma_reference_capture_review_packet/report.json`;
  - `.dart_tool/jma_final_catalog_review_packet/report.json`;
  - `.dart_tool/final_catalog_or_hinet_revision_review_packet/report.json`.
- The worklist now has operation-artifact coverage for every open input:
  - operation artifacts: `12`;
  - rows without operation artifacts: `0`;
  - Hi-net capture repair input templates: `1`;
  - Hi-net authenticated export row templates: `3`;
  - JMA reference capture review packets: `4`;
  - JMA final catalog review packets: `3`;
  - final catalog or Hi-net revision review packets: `1`.
- `tools\validate_source_estimation_external_input_worklist.ps1` now refreshes
  the three new packet sources by default. The top-level validation suite passes
  the corresponding `-UseExisting...` switches because those packet reports are
  already generated earlier in the suite.
- The worklist rejects unsafe packet semantics:
  - JMA reference capture artifacts must remain manual-only and cannot clear
    capture association, mutate manifests or write final-catalog truth;
  - JMA final catalog artifacts must not allow `--write`, fixture mutation or
    catalog-truth writes while the 2026 official final catalog is unavailable;
  - final-catalog-or-Hi-net-revision artifacts must not promote truth, mutate
    split manifests or clear the blocker from negative attempts.
- This remains operational scaffolding only. It makes the external evidence
  work queue executable and auditable, but it does not accept any evidence,
  assign split membership, change frozen metrics or affect production source
  estimation.
- Validation:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_source_estimation_external_input_worklist.ps1
    -UseExistingQueue -UseExistingTemplates -UseExistingAttempts
    -UseExistingRepairProbe -UseExistingAuthenticatedExportPacket
    -UseExistingJmaReferenceCapturePacket -UseExistingJmaFinalCatalogPacket
    -UseExistingFinalCatalogOrHinetRevisionPacket`.
- Next action remains evidence-bound: once a real GIF, local capture package,
  authenticated Hi-net/JMA row or versioned JMA final catalog record is
  available, fill only the matching artifact/template, run its dry-run path,
  then rerun the worklist and top-level source-estimation suite before any
  ledger or split decision.

## 2026-06-26 Yamanashi East / Fuji Five Lakes Reference Events

- Added two user-provided JMA source-and-intensity events to
  `docs/data/jma_reference_event_candidates.json`:
  - `20260626_yamanashi_east_fuji_five_lakes_m56_jma_equake21`;
  - `20260626_yamanashi_east_fuji_five_lakes_m33_jma_equake8`.
- The M5.6 event records:
  - JMA origin: `2026-06-26T21:29:02+08:00`;
  - JMA hypocenter: `35.6N, 139.0E`, depth `20 km`, M`5.6`;
  - JMA maximum shindo: `6-`;
  - attached EQuake screenshot as a non-final reference snapshot only:
    report `21`, origin `2026-06-26T21:28:59+08:00`, M`5.8`,
    depth `17 km`, observed real-time maximum shindo `5+`.
- The M3.3 aftershock event records:
  - JMA origin: `2026-06-26T22:17:46+08:00`;
  - JMA hypocenter: `35.5N, 139.0E`, depth `20 km`, M`3.3`;
  - JMA maximum shindo: `3`;
  - EQuake final report `8` as source-estimation reference metadata only:
    origin `2026-06-26T22:17:44+08:00`, `35.55N, 138.96E`,
    M`3.5`, depth `10 km`, quality `A`, `81.6%`, RMS `0.81 s`,
    gap `20 deg`, triggered stations `230` (`P:90`, `S:109`, `O:31`).
- Both events remain:
  - `reference_only`;
  - `pending_capture_association`;
  - `jma_source_and_intensity_reference_pending_final_catalog`.
- Local timestamp/keyword scans found no matching replay/capture package under
  `tmp/captures`, `tmp/quarantine`, `test/fixtures/source_estimation`,
  `C:/Users/Rhythm/Downloads` or `C:/Users/Rhythm/Pictures`. These scans are
  recorded in `docs/data/source_estimation_external_input_attempts.json` as
  `negative_attempt_only` and do not clear the local capture requirement.
- Current generated state after these additions:
  - JMA reference candidates: `4`;
  - pending local capture associations: `4`;
  - external input queue items: `12`;
  - negative external-input attempts: `17`;
  - worklist operation artifacts: `12`.
- Validation:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_jma_reference_event_candidates.ps1`;
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_jma_reference_capture_association.ps1`;
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_source_estimation_external_input_worklist.ps1
    -UseExistingQueue -UseExistingTemplates -UseExistingAttempts
    -UseExistingRepairProbe -UseExistingAuthenticatedExportPacket
    -UseExistingJmaReferenceCapturePacket -UseExistingJmaFinalCatalogPacket
    -UseExistingFinalCatalogOrHinetRevisionPacket`.

## 2026-06-26 JMA Reference Capture Package Importer

- Added `tools/import_jma_reference_capture_package.dart` as the safe intake
  path for reviewer-supplied local replay/capture packages attached to recent
  JMA source-and-intensity reference candidates.
- The importer accepts a reviewed JSON input with:
  - `eventId`;
  - `status=capture_associated_pending_final_catalog`;
  - `reviewedAtUtc`;
  - `reviewer`;
  - `captureDirectory`;
  - `manifestPath`;
  - `packageSource`;
  - `associationReason`.
- Validation requires:
  - the event exists in `docs/data/jma_reference_event_candidates.json`;
  - the event is still `pending_capture_association`;
  - `captureDirectory` is currently unset;
  - the event truth quality still contains `pending_final_catalog`;
  - the capture directory exists;
  - `manifestPath` exists under that capture directory;
  - the package has frame evidence through a manifest `records` list, a
    `frameIndexPath`, or local GIF files;
  - no password, cookie, authorization, session, token, username or user fields
    are present;
  - no `<fill-...>` placeholders remain.
- In `--dry-run` mode it validates the package without mutating the JMA
  reference candidate manifest.
- Without `--dry-run`, it only writes:
  - `status=capture_associated_pending_final_catalog`;
  - `captureDirectory`;
  - a `captureAssociation` review block with reviewer, reviewed time,
    manifest path, package source and association reason.
- It deliberately does not:
  - change `truthQuality`;
  - write a JMA final catalog truth label;
  - assign train/validation/test split membership;
  - clear final-catalog blockers;
  - affect production source-estimation behavior.
- `tools\validate_jma_reference_capture_association.ps1` now runs
  `test\jma_reference_capture_package_import_test.dart`, covering dry-run,
  write-on-review and rejection of placeholders/auth material.
- `tools/build_jma_reference_capture_review_packet.dart` now exposes the
  importer dry-run command, and the external input worklist carries that command
  in each `local_jma_reference_capture_package` operation artifact.
- Current generated state remains evidence-bound:
  - JMA reference candidates: `4`;
  - pending capture associations: `4`;
  - capture associated: `0`;
  - external input queue items: `12`;
  - worklist operation artifacts: `12`.
- Validation:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_jma_reference_capture_association.ps1`;
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_source_estimation_external_input_worklist.ps1
    -UseExistingQueue -UseExistingTemplates -UseExistingAttempts
    -UseExistingRepairProbe -UseExistingAuthenticatedExportPacket
    -UseExistingJmaReferenceCapturePacket -UseExistingJmaFinalCatalogPacket
    -UseExistingFinalCatalogOrHinetRevisionPacket`.
- Next action remains evidence-bound: when a real local replay/capture package
  for one of the four JMA reference candidates is available, fill a reviewed
  capture-association JSON, run
  `dart run tools\import_jma_reference_capture_package.dart --input
  <reviewed-capture-association.json> --dry-run`, then rerun JMA capture
  association, the external worklist and the top-level source-estimation suite
  before considering any later final-catalog or split decision.

## 2026-06-26 JMA Reference Capture External Input Template Upgrade

- Upgraded `tools/build_source_estimation_external_input_template_report.dart`
  so each `local_jma_reference_capture_package` template now matches the
  reviewed JSON required by `tools/import_jma_reference_capture_package.dart`.
- The generated template now includes:
  - `eventId`;
  - `status=capture_associated_pending_final_catalog`;
  - `reviewedAtUtc`;
  - `reviewer`;
  - `captureDirectory`;
  - `manifestPath`;
  - `packageSource`;
  - `associationReason`;
  - required local frame evidence hints;
  - an importer `--dry-run` command;
  - post-fill validation instructions.
- This closes the previous operational gap where the worklist could request a
  local JMA reference capture association but only emitted a minimal path-only
  template that was not directly compatible with the safe importer.
- The template is still manual-review-only:
  - `automaticClearance=false`;
  - no capture association is imported automatically;
  - no JMA final catalog truth is written;
  - no split membership is assigned;
  - no final-catalog blocker is cleared.
- Current generated state remains unchanged and evidence-bound:
  - JMA reference candidates: `4`;
  - pending capture associations: `4`;
  - capture associated: `0`;
  - external input queue items: `12`;
  - worklist operation artifacts: `12`.
- Validation:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_source_estimation_external_input_templates.ps1
    -UseExistingQueue`.
- Next action remains evidence-bound: when a real local replay/capture package
  exists for one of the four JMA reference candidates, fill the generated
  capture-association template, run the importer dry-run, and only then review
  whether to execute the non-dry-run association import.

## 2026-06-26 Missing Iwate JMA-B Extended Local Scan

- Followed the current external-input worklist next item:
  - input type: `missing_gif_archive_copy`;
  - case id: `20260620_iwate_offshore_m34_ref`;
  - missing file: `20260620212727.jma_b.gif`.
- Ran an extended exact-filename scan for `20260620212727.jma_b.gif` across:
  - `D:/flutterApp/flutterrhythmquake`;
  - `D:/Users/Rhythm/Downloads`;
  - `C:/Users/Rhythm/Downloads`;
  - `C:/Users/Rhythm/Documents`;
  - `C:/Users/Rhythm/Desktop`;
  - `C:/Users/Rhythm/AppData/Local/Temp`.
- Result: `not_found`.
- Recorded this as
  `20260626_iwate_m34_missing_jma_b_extended_user_roots_scan` in
  `docs/data/source_estimation_external_input_attempts.json`.
- This is still `negative_attempt_only`:
  - no repair candidate is created;
  - no capture blocker is cleared;
  - no ledger is mutated;
  - no split assignment is changed;
  - no production source-estimation behavior is affected.
- Current expected generated state after this scan:
  - external-input attempts: `18`;
  - missing-GIF attempts: `4`;
  - automatic clearances: `0`;
  - worklist open inputs remain `12`;
  - next worklist item remains
    `missing_gif_archive_copy::20260620_iwate_offshore_m34_ref`.
- Next action remains evidence-bound: obtain a valid
  `20260620212727.jma_b.gif` copy from an external/local archive, place it
  under a repair scan root, then run the generated repair importer with
  `--dry-run` before any mutation.

## 2026-06-26 KMoni GIF Remote Retention Guard

- Added an explicit guard for KMoni GIF repair hints:
  - do not remotely fetch KMoni GIF frames older than `3` hours;
  - deterministic KMoni URLs for older frames are retained only as historical
    provenance/location hints;
  - old-frame repair must use a local or mirrored archive copy, or a reviewed
    exclusion decision.
- Updated `tools/build_hinet_capture_repair_probe_report.dart` so each remote
  hint now records:
  - `remoteRetrievalAllowed=false`;
  - `maxRemoteAgeHours=3`;
  - notes warning not to remotely fetch GIFs older than 3 hours.
- Updated the external-input queue/template generators so the missing
  `20260620212727.jma_b.gif` item is emitted as `historicalRemoteHint`, not as
  a live retrieval path.
- This prevents repeating remote KMoni fetch attempts for the 2026-06-20
  missing JMA-B frame while keeping enough provenance to identify the exact
  expected file.
- This guard does not:
  - create a repair candidate;
  - clear the capture blocker;
  - mutate capture manifests;
  - write review ledgers;
  - change split assignment;
  - affect production source-estimation behavior.
- Next action for `20260620_iwate_offshore_m34_ref` remains one of:
  - place a valid local/mirrored `20260620212727.jma_b.gif` under a repair scan
    root and run the repair importer with `--dry-run`;
  - make an explicit reviewed exclusion decision for constrained split use.

## 2026-06-27 P2PQuake/JMA Recent Event GIF Backfill

- Corrected the intake workflow: every user-provided JMA, EQuake, Hi-net or
  EQSC event must first attempt a within-retention KMoni GIF capture for the
  event time window, then store text/image metadata separately. Text-only
  scraping is not enough when the event is still inside the public GIF
  retention window.
- Queried the P2PQuake JMA history feed for recent `DetailScale` events and
  matched the user-provided JMA list screenshot for
  `山梨県東部・富士五湖`.
- Captured `jma_s` and `jma_b` GIF windows with `origin - 30 s` to
  `origin + 120 s` for four events:
  - `20260626_yamanashi_east_fuji_five_lakes_m56_jma_p2p`:
    P2PQuake id `6a3e817ae88ee598246bee1f`, 2026-06-26 22:29 JST,
    35.6N/139.0E, depth 20 km, M5.6, max scale 55, 287/302 GIFs
    captured;
  - `20260626_yamanashi_east_fuji_five_lakes_m26_jma_p2p`:
    P2PQuake id `6a3e8776e88ee598246bee20`, 2026-06-26 23:04 JST,
    35.6N/139.0E, depth 20 km, M2.6, max scale 10, 279/302 GIFs
    captured;
  - `20260626_yamanashi_east_fuji_five_lakes_m33_jma_p2p`:
    P2PQuake id `6a3e8acbe88ee598246bee23`, 2026-06-26 23:17 JST,
    35.5N/139.0E, depth 20 km, M3.3, max scale 30, 286/302 GIFs
    captured;
  - `20260627_yamanashi_east_fuji_five_lakes_m24_jma_p2p`:
    P2PQuake id `6a3e9c45e88ee598246bee24`, 2026-06-27 00:33 JST,
    35.5N/139.0E, depth 20 km, M2.4, max scale 10, 290/302 GIFs
    captured.
- Associated local capture packages for the existing M5.6 and M3.3 reference
  candidates and added new P2PQuake/JMA reference candidates for the M2.6 and
  M2.4 events. All remain `reference_only` and
  `jma_source_and_intensity_reference_pending_final_catalog`; no final-catalog
  truth or split assignment is created by this backfill.
- Current generated state after the backfill:
  - JMA reference candidates: `6`;
  - pending capture associations: `2`;
  - capture associated: `4`;
  - external input queue items: `10`;
  - worklist operation artifacts: `10`;
  - automatic clearances: `0`.
- Validation:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_jma_reference_event_candidates.ps1`;
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_jma_reference_capture_association.ps1`;
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_source_estimation_external_input_queue.ps1
    -UseExistingDependencies`;
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_source_estimation_external_input_templates.ps1
    -UseExistingQueue`;
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_source_estimation_external_input_worklist.ps1
    -UseExistingQueue -UseExistingTemplates -UseExistingAttempts
    -UseExistingRepairProbe -UseExistingAuthenticatedExportPacket
    -UseExistingJmaReferenceCapturePacket -UseExistingJmaFinalCatalogPacket
    -UseExistingFinalCatalogOrHinetRevisionPacket`.

## 2026-06-27 Proactive P2PQuake Intake Check

- Intake rule refinement: Codex should proactively poll the P2PQuake JMA
  history feed (`codes=551`, newest rows first) for events still inside the
  KMoni public GIF retention window. For each uncovered recent `DetailScale`
  event, capture KMoni GIFs first, then write reference metadata.
- Deduplication rule: if a P2PQuake row is an earlier/later report for an event
  that already has an associated capture package, record the check but do not
  create a duplicate JMA reference candidate.
- Check result at 2026-06-27 00:46 UTC+8:
  - recent within-retention JMA rows were the already-associated Yamanashi east
    / Fuji Five Lakes sequence at 22:29, 23:04, 23:17 and 00:33 JST;
  - no new uncovered `DetailScale` event required another GIF capture;
  - existing JMA reference candidate counts remain unchanged: `6` total,
    `4` capture-associated, `2` pending capture association.

## 2026-06-27 Dataset Use Tiering

- Added explicit dataset-use tiering to
  `tools/build_source_estimation_split_assignment_readiness_report.dart`.
- Each planned source-estimation case now has:
  - `datasetUseTier`;
  - `datasetUseTierReason`.
- Tier definitions:
  - `strict_ready`: all frozen split requirements are complete; allowed for
    frozen validation metrics.
  - `diagnostic_ready`: local fixture or capture is usable, but catalog/review
    or split assignment is still pending; allowed for algorithm diagnosis and
    counterexample analysis only.
  - `metadata_only_or_incomplete`: local capture is missing or has failed
    frames, or the local fixture/capture is not confirmed; keep as reference
    metadata only.
- Current planned-case tier counts:
  - `strict_ready`: `2`;
  - `diagnostic_ready`: `10`;
  - `metadata_only_or_incomplete`: `1`.
- The only current planned-case `metadata_only_or_incomplete` item is
  `20260620_iwate_offshore_m34_ref`, because its local capture still has the
  unresolved missing frame `20260620212727.jma_b.gif`.
- Operational rule: continue algorithm work using `diagnostic_ready` cases, but
  keep final metric claims and frozen split reporting limited to
  `strict_ready` cases.
- Validation:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_source_estimation_split_assignment_readiness.ps1`.

## 2026-06-27 Fukushima Aizu M3.6 JMA/EQuake Intake

- User-provided event:
  - JMA source/intensity: 2026-06-27 01:33:00 UTC+8, Fukushima Aizu,
    37.1N/139.4E, M3.6, depth 10 km, maximum shindo 3.
  - EQuake final report 17: 2026-06-27 01:32:58 UTC+8, Fukushima Aizu,
    37.02N/139.26E, M3.4, depth 4 km, observed shindo 2 (1.7), estimated
    shindo 2 (1.5-2.4), quality C 68.6%, RMS 2.69 s, azimuthal gap 13 deg,
    triggered stations 211 (P:61, S:131, O:19).
- Within-retention GIF workflow was applied first:
  - current local time at intake check: 2026-06-27 01:48 UTC+8;
  - event age was about 15 minutes, so remote KMoni GIF capture was allowed;
  - captured `jma_s` and `jma_b` from origin -30 s to origin +120 s into
    `tmp/captures/20260627_fukushima_aizu_m36_jma_equake17`;
  - capture result: 302/302 GIFs, 0 failures.
- P2PQuake/JMA DetailScale match:
  - id `6a3eb87be88ee598246bee27`;
  - issue time 2026-06-27 02:35:55 JST;
  - Fukushima Aizu, 37.1N/139.4E, depth 10 km, M3.6, max scale 30,
    7 observation points.
- Added `20260627_fukushima_aizu_m36_jma_equake17` to
  `docs/data/jma_reference_event_candidates.json` as
  `capture_associated_pending_final_catalog`.
- This event remains `reference_only` and
  `jma_source_and_intensity_reference_pending_final_catalog`; no final-catalog
  truth, frozen split assignment, or production behavior is changed by this
  intake.
- Updated generated JMA capture association state:
  - JMA reference candidates: `7`;
  - pending capture associations: `2`;
  - capture associated: `5`.

## 2026-06-27 Diagnostic-Ready Systematic Analysis

- Added a diagnostic-only aggregation report:
  - tool: `tools/build_source_estimation_diagnostic_ready_report.dart`;
  - validator: `tools/validate_source_estimation_diagnostic_ready.ps1`;
  - JSON: `.dart_tool/source_estimation_diagnostic_ready/report.json`;
  - Markdown: `docs/baselines/source_estimation_diagnostic_ready.generated.md`.
- The report consumes:
  - split-assignment readiness tiers;
  - early-frame reports;
  - candidate promotion matrix;
  - candidate-region timeline.
- Current diagnostic-ready summary:
  - diagnostic-ready cases: `10`;
  - strict metric eligible cases in this report: `0`;
  - production coordinate switch allowed: `0`;
  - candidate frames: `22`;
  - offline missed positive frames: `13`;
  - offline false accept frames: `0`;
  - delayed recovered missed positives: `3`.
- Diagnostic roles:
  - `false_recovery_guard`: `1`;
  - `residual_candidate_region_guard`: `2`;
  - `local_support_positive_guard`: `1`;
  - `no_candidate_control`: `6`.
- Highest-value next diagnostic actions:
  - `20260621_fukushima_offshore_m32_eq6`: inspect candidate rejection
    residuals. It has 8 candidate frames, 7 offline-improved frames, and 0
    false accepts, but the current gate rejects all candidates.
  - `20260622_kushiro_offshore_m30_jma`: study delayed confirmation recovery.
    It has 8 candidate frames, 5 immediate accepts, 3 missed positives, and 3
    delayed recoveries.
  - `20260622_tomakomai_south_offshore_m35_hinet`: keep as positive residual
    guard. It has 3 accepted candidate frames and 0 false accepts.
  - `20260625_iwate_offshore_m32_jma`: inspect local-support positive path. It
    has 3 offline-improved rejected candidate frames and 1 local-support
    delayed confirmation.
- The report deliberately keeps all diagnostic-ready cases out of final metric
  claims and frozen split reporting.
- Validation:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_source_estimation_diagnostic_ready.ps1`.

## 2026-06-27 Core Candidate Rejection Residual Report

- Added a diagnostic-only core-case residual inspection report:
  - tool: `tools/build_source_candidate_rejection_residual_report.dart`;
  - validator:
    `tools/validate_source_candidate_rejection_residual_report.ps1`;
  - test: `test/source_candidate_rejection_residual_report_test.dart`;
  - JSON:
    `.dart_tool/source_candidate_rejection_residual_report/report.json`;
  - Markdown:
    `docs/baselines/source_candidate_rejection_residual_report.generated.md`.
- The report consumes:
  - `source_estimation_diagnostic_ready`;
  - `source_candidate_promotion_report`;
  - `source_candidate_region_timeline_report`.
- Scope is the current 4 core diagnostic cases:
  - `20260621_fukushima_offshore_m32_eq6`;
  - `20260622_kushiro_offshore_m30_jma`;
  - `20260622_tomakomai_south_offshore_m35_hinet`;
  - `20260625_iwate_offshore_m32_jma`.
- Current generated summary:
  - core cases: `4`;
  - inspect-candidate-rejection cases: `2`;
  - candidate frames: `22`;
  - inspect rejected offline-positive frames: `10`;
  - core rejected offline-positive frames: `13`;
  - residual delayed recovered frames: `3`;
  - local-support confirmed-delayed cases: `1`;
  - offline false accepts: `0`;
  - production coordinate switches: `0`.
- Case-level interpretation:
  - Fukushima offshore M3.2 remains the residual over-rejection guard:
    rejected offline-positive frames exist, but delayed/local-support recovery
    remains blocked. Early candidate frames show residual regression and weak
    local support; later member geometry improves, but not as a valid
    confirmation of the pending candidate-region path.
  - Kushiro offshore M3.0 remains the residual delayed-recovery positive guard:
    early rejected positives are recovered by later same-region residual support.
  - Tomakomai south offshore M3.5 remains the immediate residual positive guard:
    all candidate frames are accepted and no false accept is introduced.
  - Iwate offshore M3.2 remains the local-support positive guard:
    residual gate rejects the early candidate frames, but local member support
    later confirms the pending region without allowing production coordinate
    switching.
- Next algorithm step:
  - compare Fukushima vs Iwate local-support timelines frame by frame;
  - identify which local-support fields separate safe recovery from false
    recovery (`memberCount`, `estimateMemberDistanceKm`, `convergenceKm`,
    `geometry`);
  - keep residual gate thresholds unchanged until this separation is stable
    across the diagnostic-ready controls.
- Validation:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_source_candidate_rejection_residual_report.ps1`.

## 2026-06-27 Local-Support Separation Guard

- Re-ran the Fukushima offshore M3.2 and Iwate offshore M3.2 reference replay
  benchmarks before changing the gate. This exposed a real regression:
  Fukushima could be locally confirmed by the current default local-support
  gate while the validation manifest still requires it to remain blocked.
- Tightened the diagnostic local-support member-growth threshold:
  - `SourceCandidateLocalSupportGateConfig.minMemberGrowth`: `1` -> `4`.
- Rationale:
  - Fukushima false-recovery guard reaches strong distance/convergence/geometry
    late in the pending path, but only has local member growth `+1` or `+2`;
  - Iwate local-support positive guard reaches growth `+5` with all local
    support booleans true and remains confirmed-delayed;
  - production coordinate switching remains disabled for all candidate-region
    confirmations.
- Added a dedicated separation report:
  - tool: `tools/build_source_local_support_separation_report.dart`;
  - validator: `tools/validate_source_local_support_separation.ps1`;
  - test: `test/source_local_support_separation_report_test.dart`;
  - JSON: `.dart_tool/source_local_support_separation_report/report.json`;
  - Markdown:
    `docs/baselines/source_local_support_separation_report.generated.md`.
- Current generated summary:
  - cases: `2`;
  - false-recovery guard confirmations: `0`;
  - positive guard confirmations: `1`;
  - near-complete frames blocked only by member growth: `3`;
  - production coordinate switches: `0`.
- Key frame-level separation:
  - Fukushima `2026-06-21T23:42:00`: count `17`, growth `1`, distance
    `5.7 km`, convergence `182.2 km`, geometry `surrounded`; blocked only by
    member-growth threshold.
  - Iwate `2026-06-25T19:22:00`: count `11`, growth `5`, distance `19.1 km`,
    convergence `137.4 km`, geometry `surrounded`; confirmed delayed by full
    local support.
- Validation:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_source_local_support_separation.ps1`.
- Next algorithm step:
  - run the tightened local-support gate across the remaining diagnostic-ready
    controls, especially Kushiro, Tomakomai and Tokachi, and fail the report if
    any new local-support false recovery or coordinate switch appears.

## 2026-06-27 Local-Support All-Control Guard

- Added a manifest-wide local-support control report:
  - tool: `tools/build_source_local_support_control_report.dart`;
  - validator: `tools/validate_source_local_support_control.ps1`;
  - test: `test/source_local_support_control_report_test.dart`;
  - JSON: `.dart_tool/source_local_support_control_report/report.json`;
  - Markdown:
    `docs/baselines/source_local_support_control_report.generated.md`.
- The report consumes
  `docs/data/source_candidate_region_validation_manifest.json` and all listed
  benchmark inputs. It treats local-support confirmation as allowed only for
  roles explicitly listed as local-support positive guards.
- Current generated summary:
  - manifest cases: `6`;
  - cases with candidate-region frames: `4`;
  - local-support confirmed cases: `1`;
  - unexpected local-support confirmations: `0`;
  - production coordinate switches: `0`.
- Control results:
  - Fukushima offshore M3.2: no local-support false recovery;
  - Kushiro offshore M3.0: residual delayed recovery remains residual-only;
  - Tomakomai south offshore M3.5: residual immediate positives remain
    residual-only;
  - Tokachi southeast offshore M3.4: no candidate-region frames;
  - Fukushima Aizu M3.2: no candidate-region frames;
  - Iwate offshore M3.2: exactly one expected local-support delayed
    confirmation.
- Validation:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_source_local_support_control.ps1`.
- Next algorithm step:
  - move from local-support gate safety to residual-gate analysis for Kushiro
    delayed recovery: identify why the first 3 positive candidate frames are
    rejected and then recovered by same-region residual support, without
    relaxing the residual gate enough to accept Fukushima.

## 2026-06-27 Residual Delayed-Recovery Analysis

- Added a residual delayed-recovery report:
  - tool: `tools/build_source_residual_delayed_recovery_report.dart`;
  - validator: `tools/validate_source_residual_delayed_recovery.ps1`;
  - test: `test/source_residual_delayed_recovery_report_test.dart`;
  - JSON: `.dart_tool/source_residual_delayed_recovery_report/report.json`;
  - Markdown:
    `docs/baselines/source_residual_delayed_recovery_report.generated.md`.
- The report compares:
  - `20260622_kushiro_offshore_m30_jma` as the residual delayed-positive
    guard;
  - `20260622_tomakomai_south_offshore_m35_hinet` as the residual
    immediate-positive guard;
  - `20260621_fukushima_offshore_m32_eq6` as the false-recovery guard.
- Current generated summary:
  - delayed recovered positive frames: `3`;
  - false-recovery guard delayed recovered frames: `0`;
  - positive guard delayed recovered frames: `3`;
  - immediate positive guard accepted frames: `3`;
  - production coordinate switches: `0`.
- Kushiro interpretation:
  - the first three positive candidate frames are rejected because rank and
    attenuation do not yet support the candidate;
  - they do not show dual residual regression;
  - all three are recovered by the 2026-06-22T16:38:27 same-region residual
    confirmation frame;
  - the confirming frame has rank delta `-0.267` and attenuation delta
    `-0.138`, so both residual metrics support the candidate.
- Fukushima interpretation:
  - all seven rejected offline-positive candidate frames show dual residual
    regression;
  - attenuation ratios are about `2.56` to `2.71`, and rank deltas are
    positive;
  - therefore Fukushima remains the guard that prevents relaxing the initial
    residual gate just because a candidate is closer to offline truth.
- Tomakomai interpretation:
  - all three candidate frames are immediate residual-positive accepts;
  - rank delta is `-0.462` for all three frames;
  - attenuation ratio is `0.43` to `0.60`;
  - this is the clean immediate-accept signature that separates Tomakomai from
    Kushiro's early pending frames and Fukushima's dual-regression rejection.
- Decision:
  - do not relax the initial residual gate based on Kushiro;
  - keep same-region delayed residual confirmation as the recovery mechanism;
  - keep immediate acceptance limited to frames where residual metrics already
    support the candidate, as in Tomakomai;
  - keep candidate coordinates diagnostic-only and keep production coordinate
    switching disabled.
- Validation:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_source_residual_delayed_recovery.ps1`.
- Next algorithm step:
  - codify the residual decision matrix from these three signatures:
    immediate accept, delayed same-region recovery, and false-recovery
    rejection. Then verify it against all candidate-region manifest controls
    before considering any production-facing confidence wording.

## 2026-06-27 Residual Decision Matrix

- Added a residual decision matrix report:
  - tool: `tools/build_source_residual_decision_matrix_report.dart`;
  - validator: `tools/validate_source_residual_decision_matrix.ps1`;
  - test: `test/source_residual_decision_matrix_report_test.dart`;
  - JSON: `.dart_tool/source_residual_decision_matrix/report.json`;
  - Markdown:
    `docs/baselines/source_residual_decision_matrix.generated.md`.
- The report consumes:
  - `.dart_tool/source_residual_delayed_recovery_report/report.json`;
  - `.dart_tool/source_local_support_control_report/report.json`.
- Current generated summary:
  - matrix rows: `5`;
  - passed rows: `5`;
  - manifest cases: `6`;
  - manifest cases with candidate-region frames: `4`;
  - delayed recovered positive frames: `3`;
  - local-support confirmed cases: `1`;
  - unexpected local-support confirmations: `0`;
  - production coordinate switches: `0`.
- Codified diagnostic signatures:
  - `immediate_accept`: Tomakomai south offshore M3.5 remains the direct
    residual-supported positive guard with `3` accepted positive frames and
    `3` immediate confirmations.
  - `delayed_same_region_recovery`: Kushiro offshore M3.0 keeps `3` early
    no-support positive frames recovered by `1` later same-region residual
    delayed confirmation.
  - `false_recovery_reject`: Fukushima offshore M3.2 keeps `7` rejected
    offline-positive frames blocked by dual rank/attenuation regression.
  - `local_support_delayed_confirmation`: Iwate offshore M3.2 keeps exactly
    `1` local-support delayed confirmation, diagnostic-only.
  - `no_candidate_region_control`: Tokachi southeast offshore M3.4 and
    Fukushima Aizu M3.2 keep `0` candidate-region frames.
- Decision:
  - keep candidate-region coordinates diagnostic-only;
  - keep production coordinate switching disabled;
  - do not relax the initial residual gate;
  - allow delayed confirmation only through explicitly validated residual or
    local-support evidence paths.
- Validation:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_source_residual_decision_matrix.ps1`.
- Next algorithm step:
  - define the production-facing confidence wording boundary from this matrix:
    what can be shown as diagnostic uncertainty, what can be shown as a
    delayed-confirmed candidate-region, and what must remain hidden from
    production alert wording until event-level split/metric gates are ready.

## 2026-06-27 Confidence Wording Boundary

- Added a confidence wording boundary report:
  - tool: `tools/build_source_confidence_wording_boundary_report.dart`;
  - validator: `tools/validate_source_confidence_wording_boundary.ps1`;
  - test: `test/source_confidence_wording_boundary_report_test.dart`;
  - JSON: `.dart_tool/source_confidence_wording_boundary/report.json`;
  - Markdown:
    `docs/baselines/source_confidence_wording_boundary.generated.md`.
- The report consumes
  `.dart_tool/source_residual_decision_matrix/report.json` and turns the
  diagnostic matrix into surface-level wording rules.
- Current generated summary:
  - boundaries: `6`;
  - passed boundaries: `6`;
  - source-card visible boundaries: `4`;
  - official alert wording allowed: `0`;
  - production coordinate switches allowed: `0`.
- Surface boundary:
  - source-estimation unified card may show production estimate quality and
    explicitly diagnostic candidate-region state;
  - generated reports and debug surfaces may show full candidate-region
    residual/local-support details;
  - official alert wording, voice/push wording and production coordinate
    replacement remain disallowed;
  - event-level split and metric gates must be completed before calibrated
    production accuracy wording is introduced.
- Signal-level decisions:
  - `production_estimate_quality`: show quality grade/confidence, RMS/gap/P90,
    estimated shindo badge and station counts on the source-estimation card;
  - `candidate_region_pending`: show only as uncertainty evidence;
  - `candidate_region_residual_confirmed`: show only as diagnostic
    candidate-region confirmation;
  - `candidate_region_local_support_confirmed`: show only as diagnostic
    candidate-region confirmation with local-support evidence;
  - `candidate_region_rejected_or_expired`: hide from alert copy or keep
    debug/report-only;
  - `event_level_metrics_and_split`: not ready for production-facing accuracy
    wording.
- Validation:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_source_confidence_wording_boundary.ps1`.
- Next algorithm step:
  - audit the current unified source-estimation card against this boundary.
    In particular, verify that `candidate_region` copy is explicitly
    diagnostic, rejected/expired regions do not appear as alert uncertainty,
    and no voice/push/official alert path consumes candidate-region wording.

## 2026-06-27 Source Wording Surface Audit

- Added a source wording surface audit report:
  - tool: `tools/build_source_wording_surface_audit_report.dart`;
  - validator: `tools/validate_source_wording_surface_audit.ps1`;
  - test: `test/source_wording_surface_audit_report_test.dart`;
  - JSON: `.dart_tool/source_wording_surface_audit/report.json`;
  - Markdown: `docs/baselines/source_wording_surface_audit.generated.md`.
- The report consumes
  `.dart_tool/source_confidence_wording_boundary/report.json` and scans the
  current UI, provider, voice/TTS, debug and official adapter source files.
- Current generated summary:
  - checks: `7`;
  - passed checks: `7`;
  - failed checks: `0`;
  - source-card checks: `3`;
  - voice-path checks: `1`;
  - official-adapter checks: `1`.
- Code-path decisions:
  - candidate-region wording is limited to the source-estimation unified-card
    `apiTypeLabel`;
  - expired candidate-region state is hidden from the source card and remains
    debug/report-only;
  - source-estimation `warnArea` remains trigger P/S/O text, not
    candidate-region wording;
  - source-estimation events are composed locally from
    `StationEventTracker.currentNiedEvent` and are not inserted into
    `QuakeProvider.unifiedEvents`;
  - voice/TTS and official adapter paths do not consume candidate-region
    metadata;
  - debug surfaces keep full candidate-region residual/local-support metadata.
- Implementation adjustment:
  - `AlertModule._sourceCandidateRegionText` now maps `expired` to `null`, so
    expired candidates are no longer shown as alert-card uncertainty.
- Validation:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_source_wording_surface_audit.ps1`.
- Next algorithm step:
  - return to event-level split/metric readiness. Use the existing
    `source_estimation_split_assignment_readiness` and blocker queue reports to
    identify which diagnostic-ready events can move toward metric-bearing
    validation and which still need external evidence or replay-package repair.

## 2026-06-27 Metric-Readiness Triage

- Added a metric-readiness triage report:
  - tool: `tools/build_source_metric_readiness_triage_report.dart`;
  - validator: `tools/validate_source_metric_readiness_triage.ps1`;
  - test: `test/source_metric_readiness_triage_report_test.dart`;
  - JSON: `.dart_tool/source_metric_readiness_triage/report.json`;
  - Markdown: `docs/baselines/source_metric_readiness_triage.generated.md`.
- The report consumes:
  - `.dart_tool/source_estimation_split_assignment_readiness/report.json`;
  - `.dart_tool/source_estimation_split_blocker_queue/report.json`.
- Current generated summary:
  - cases: `13`;
  - metric-bearing ready: `0`;
  - reference-validation only: `2`;
  - diagnostic-ready blocked: `10`;
  - metadata-only/incomplete: `1`;
  - candidate-region diagnostic blocked: `5`;
  - ready for manual split assignment: `0`.
- Decision:
  - no current case is ready for metric-bearing validation or final accuracy
    claims;
  - the two strict-ready cases remain reference-validation only because their
    constraints forbid final test claims and catalog-truth use;
  - the ten diagnostic-ready cases remain useful for algorithm diagnostics but
    are blocked by JMA catalog, Hi-net review, or final-catalog/revision
    evidence;
  - `20260620_iwate_offshore_m34_ref` remains metadata-only/incomplete because
    capture provenance still has a failed/missing GIF and Hi-net review is
    pending.
- Next evidence queue by action:
  - `review_jma_catalog_link`: `3` cases
    (`20260622_kushiro_offshore_m30_jma`,
    `20260624_fukushima_aizu_m32_jma_eq5`,
    `20260625_iwate_offshore_m32_jma`);
  - `review_hinet_preliminary_truth_quality`: `6` cases;
  - `review_hinet_truth_quality`: `1` case
    (`20260621_fukushima_offshore_m32_eq6`);
  - `link_final_catalog_or_hinet_revision`: `1` case
    (`20260621_iwate_offshore_m33_eq8`).
- Validation:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_source_metric_readiness_triage.ps1`.
- Next algorithm step:
  - work the highest-impact evidence class without assigning splits: generate a
    focused JMA-catalog-link triage packet for the three JMA-blocked
    diagnostic-ready cases, and keep them out of metric-bearing validation
    until a versioned final catalog or equivalent reviewed source is linked.

## 2026-06-27 Source JMA Catalog-Link Triage Packet

- Added a focused source-estimation JMA catalog-link triage packet:
  - tool: `tools/build_source_jma_catalog_link_triage_packet.dart`;
  - validator: `tools/validate_source_jma_catalog_link_triage.ps1`;
  - test: `test/source_jma_catalog_link_triage_packet_test.dart`;
  - JSON:
    `.dart_tool/source_jma_catalog_link_triage_packet/report.json`;
  - Markdown:
    `docs/baselines/source_jma_catalog_link_triage.generated.md`.
- The packet consumes:
  - `.dart_tool/source_metric_readiness_triage/report.json`;
  - `.dart_tool/jma_final_catalog_review_packet/report.json`.
- Current generated summary:
  - packets: `3`;
  - latest available JMA final catalog year: `2023`;
  - target event year: `2026`;
  - external catalog not yet available: `3`;
  - manual-review required: `3`;
  - write-link allowed: `0`;
  - metric promotion allowed: `0`;
  - split assignment allowed: `0`.
- Focused cases:
  - `20260622_kushiro_offshore_m30_jma`
    (`candidate_region_residual_positive_guard`);
  - `20260624_fukushima_aizu_m32_jma_eq5`
    (`inland_surrounded_control`);
  - `20260625_iwate_offshore_m32_jma`
    (`candidate_region_local_support_positive_guard`).
- Decision:
  - keep all three cases diagnostic-only until a versioned JMA final catalog or
    equivalent reviewed source is linked;
  - do not mutate fixtures, assign splits or promote catalog truth from this
    packet;
  - JMA source/intensity text captured from live feeds remains reference
    metadata, not final catalog truth.
- Validation:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_source_jma_catalog_link_triage.ps1`.
- Next evidence step:
  - continue the non-JMA evidence queue without metric promotion. Highest-count
    blocker is `review_hinet_preliminary_truth_quality` for the six Hi-net
    preliminary diagnostic-ready cases; after that, handle the single
    `review_hinet_truth_quality` Fukushima/Miyagi guard and the single
    `link_final_catalog_or_hinet_revision` Iwate reference case.

## 2026-06-27 Source Hi-net Truth-Quality Triage Packet

- Added a source-focused Hi-net truth-quality triage packet:
  - tool: `tools/build_source_hinet_truth_quality_triage_packet.dart`;
  - validator: `tools/validate_source_hinet_truth_quality_triage.ps1`;
  - test: `test/source_hinet_truth_quality_triage_packet_test.dart`;
  - JSON:
    `.dart_tool/source_hinet_truth_quality_triage_packet/report.json`;
  - Markdown:
    `docs/baselines/source_hinet_truth_quality_triage.generated.md`.
- The packet consumes:
  - `.dart_tool/source_metric_readiness_triage/report.json`;
  - `.dart_tool/hinet_truth_quality_review_queue/report.json`.
- Current generated summary:
  - packets: `7`;
  - diagnostic-ready blocked: `6`;
  - metadata-only/incomplete: `1`;
  - priority external-evidence reviews: `3`;
  - catalog-flag-mismatch blocked: `3`;
  - capture-repair blocked: `1`;
  - truth-quality acceptance allowed: `0`;
  - metric promotion allowed: `0`;
  - split assignment allowed: `0`.
- Priority 1 review targets:
  - `20260622_iwate_east_offshore_m30_hinet`;
  - `20260622_tomakomai_south_offshore_m35_hinet`;
  - `20260623_tokachi_southeast_offshore_m34_hinet`.
- Priority 2 blockers:
  - `20260621_fukushima_offshore_m32_eq6`;
  - `20260622_iwate_offshore_m30_eq10`;
  - `20260622_wakayama_south_m25_hinet`;
  - all require `remove_or_justify_catalog_truth_verified_flag` before
    truth-quality review can proceed.
- Priority 3 blocker:
  - `20260620_iwate_offshore_m34_ref` remains metadata-only/incomplete until
    its local capture package is repaired or explicitly excluded.
- Decision:
  - keep all Hi-net-blocked cases out of metric-bearing validation until manual
    truth-quality evidence is reviewed;
  - collect revised Hi-net or JMA evidence for the three Priority 1 preliminary
    cases first;
  - do not accept truth quality, mutate fixtures, assign splits or promote
    metrics from this packet.
- Validation:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_source_hinet_truth_quality_triage.ps1`.
- Next evidence step:
  - generate or fill a manual evidence template for the three Priority 1
    cases. The template should require a revised Hi-net or JMA source link plus
    reviewer/timestamp metadata, and should keep the result pending until an
    explicit accepted decision is imported.

## 2026-06-27 Source Hi-net Priority Evidence Templates

- Added a source-focused Priority 1 Hi-net evidence template packet:
  - tool: `tools/build_source_hinet_priority_evidence_template_packet.dart`;
  - validator: `tools/validate_source_hinet_priority_evidence_templates.ps1`;
  - test: `test/source_hinet_priority_evidence_template_packet_test.dart`;
  - JSON:
    `.dart_tool/source_hinet_priority_evidence_template_packet/report.json`;
  - Markdown:
    `docs/baselines/source_hinet_priority_evidence_templates.generated.md`.
- The packet consumes:
  - `.dart_tool/source_hinet_truth_quality_triage_packet/report.json`;
  - `.dart_tool/hinet_authenticated_export_review/report.json`;
  - `.dart_tool/hinet_authenticated_export_row_templates/report.json`.
- Current generated summary:
  - packets: `3`;
  - pending exports: `3`;
  - template files: `3`;
  - missing-template-field cases: `0`;
  - credential fields present: `0`;
  - decision evidence ready: `0`;
  - accepted constrained references: `0`;
  - decision ledger writes allowed: `0`;
  - truth-quality acceptance allowed: `0`.
- Template files:
  - `.dart_tool/hinet_authenticated_export_row_templates/files/20260622_iwate_east_offshore_m30_hinet.json`;
  - `.dart_tool/hinet_authenticated_export_row_templates/files/20260622_tomakomai_south_offshore_m35_hinet.json`;
  - `.dart_tool/hinet_authenticated_export_row_templates/files/20260623_tokachi_southeast_offshore_m34_hinet.json`.
- Decision:
  - fill these templates only from authenticated event-level Hi-net/JMA rows;
  - a filled row may be imported for review, but this packet does not write the
    decision ledger or accept truth quality;
  - keep all three cases pending until an explicit accepted decision is
    recorded with reviewer metadata.
- Validation:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_source_hinet_priority_evidence_templates.ps1`.
- Next evidence step:
  - either fill one of the three `.dart_tool` templates from an authenticated
    event-level row and dry-run `tools\import_hinet_authenticated_export_row.dart`,
    or, if no authenticated row is available, add a no-row-found review packet
    that keeps the case pending without mutating truth quality.

## 2026-06-27 Source Hi-net No-Row-Found Review Packet

- Added a source-focused no-row-found review packet for the three Priority 1
  Hi-net preliminary cases:
  - tool: `tools/build_source_hinet_no_row_found_review_packet.dart`;
  - validator: `tools/validate_source_hinet_no_row_found_review.ps1`;
  - test: `test/source_hinet_no_row_found_review_packet_test.dart`;
  - JSON:
    `.dart_tool/source_hinet_no_row_found_review_packet/report.json`;
  - Markdown:
    `docs/baselines/source_hinet_no_row_found_review_packet.generated.md`;
  - template directory:
    `.dart_tool/source_hinet_no_row_found_review/files`.
- The packet consumes:
  - `.dart_tool/source_hinet_priority_evidence_template_packet/report.json`.
- Current generated summary:
  - packets: `3`;
  - pending exports: `3`;
  - no-row templates: `3`;
  - missing-template-field cases: `0`;
  - credential fields present: `0`;
  - no-row findings submitted: `0`;
  - decision evidence ready: `0`;
  - truth-quality acceptance allowed: `0`.
- Generated no-row-found templates:
  - `.dart_tool/source_hinet_no_row_found_review/files/20260622_iwate_east_offshore_m30_hinet.no_row_found.json`;
  - `.dart_tool/source_hinet_no_row_found_review/files/20260622_tomakomai_south_offshore_m35_hinet.no_row_found.json`;
  - `.dart_tool/source_hinet_no_row_found_review/files/20260623_tokachi_southeast_offshore_m34_hinet.no_row_found.json`.
- Decision:
  - these are manual no-row-found finding templates only; they do not prove an
    authenticated search happened until filled by a reviewer;
  - a no-row-found finding keeps the case pending and does not accept truth
    quality or assign a split;
  - prefer a real authenticated event-level row whenever one is available.
- Validation:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_source_hinet_no_row_found_review.ps1`.
- Next evidence step:
  - either fill an authenticated event-level row template and import it for
    review, or fill a no-row-found template after manual authenticated search.
    Both paths must leave truth-quality acceptance pending until an explicit
    reviewer decision is recorded.

## 2026-06-27 Source Hi-net No-Row-Found Finding Intake

- Added a pending no-row-found finding ledger:
  - data: `docs/data/source_hinet_no_row_found_findings.json`.
- Added a safe no-row-found finding importer:
  - tool: `tools/import_source_hinet_no_row_found_finding.dart`;
  - test: `test/source_hinet_no_row_found_finding_import_test.dart`.
- `tools/validate_source_hinet_no_row_found_review.ps1` now runs the importer
  test after regenerating the no-row-found review packet.
- Current ledger state:
  - `20260622_iwate_east_offshore_m30_hinet`: `pending_finding`;
  - `20260622_tomakomai_south_offshore_m35_hinet`: `pending_finding`;
  - `20260623_tokachi_southeast_offshore_m34_hinet`: `pending_finding`.
- Import behavior:
  - accepts only filled findings for pending cases;
  - rejects credentials, cookies, tokens and session fields;
  - rejects unresolved placeholders, non-HTTPS source URLs, unparsable
    `checkedAtUtc`, invalid query-window ranges and non-numeric searched
    coordinates;
  - requires `searchResult` to be exactly `no_event_row_found`;
  - writes `submitted_no_row_found` with `decisionImpact:
    none_review_required`;
  - does not write `docs/data/hinet_truth_quality_review_decisions.json` and
    does not accept truth quality.
- Validation:
  - `flutter test test\source_hinet_no_row_found_finding_import_test.dart`;
  - `flutter analyze tools\import_source_hinet_no_row_found_finding.dart
    test\source_hinet_no_row_found_finding_import_test.dart`;
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_source_hinet_no_row_found_review.ps1`.
- Next evidence step:
  - create a review report that reads both authenticated submitted rows and
    no-row-found submitted findings, then keeps every case blocked until a
    separate explicit truth-quality decision is recorded.

## 2026-06-27 Source Hi-net Evidence Review

- Added a combined source Hi-net evidence review report:
  - tool: `tools/build_source_hinet_evidence_review_report.dart`;
  - validator: `tools/validate_source_hinet_evidence_review.ps1`;
  - test: `test/source_hinet_evidence_review_report_test.dart`;
  - JSON: `.dart_tool/source_hinet_evidence_review/report.json`;
  - Markdown: `docs/baselines/source_hinet_evidence_review.generated.md`.
- The report consumes:
  - `.dart_tool/hinet_authenticated_export_review/report.json`;
  - `docs/data/source_hinet_no_row_found_findings.json`;
  - `docs/data/hinet_truth_quality_review_decisions.json`.
- Current generated summary:
  - cases: `3`;
  - pending evidence: `3`;
  - authenticated evidence ready: `0`;
  - no-row evidence ready: `0`;
  - combined evidence ready: `0`;
  - accepted decisions: `0`;
  - truth-quality acceptance allowed: `0`;
  - metric promotion allowed: `0`;
  - split assignment allowed: `0`.
- Decision:
  - evidence readiness is not truth-quality acceptance;
  - authenticated rows and no-row-found findings both remain blocked until a
    separate reviewer decision accepts the case;
  - this report does not write the decision ledger, assign splits or change
    metric eligibility.
- Validation:
  - `flutter test test\source_hinet_evidence_review_report_test.dart`;
  - `flutter analyze tools\build_source_hinet_evidence_review_report.dart
    test\source_hinet_evidence_review_report_test.dart`;
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_source_hinet_evidence_review.ps1`.
- Next evidence step:
  - add an explicit reviewer-decision staging report. It should read the
    combined evidence review and `hinet_truth_quality_review_decisions.json`,
    then identify which cases are eligible for a human reviewer to accept
    without automatically mutating split assignment or metrics.

## 2026-06-27 Source Hi-net Reviewer-Decision Staging

- Added a source Hi-net reviewer-decision staging report:
  - tool: `tools/build_source_hinet_reviewer_decision_staging_report.dart`;
  - validator: `tools/validate_source_hinet_reviewer_decision_staging.ps1`;
  - test: `test/source_hinet_reviewer_decision_staging_report_test.dart`;
  - JSON: `.dart_tool/source_hinet_reviewer_decision_staging/report.json`;
  - Markdown:
    `docs/baselines/source_hinet_reviewer_decision_staging.generated.md`.
- The report consumes:
  - `.dart_tool/source_hinet_evidence_review/report.json`;
  - `docs/data/hinet_truth_quality_review_decisions.json`.
- Current generated summary:
  - cases: `3`;
  - reviewer-decision eligible: `0`;
  - blocked: `3`;
  - evidence not ready: `3`;
  - conflicting evidence ready: `0`;
  - already accepted: `0`;
  - decision ledger writes allowed: `0`;
  - truth-quality acceptance allowed: `0`;
  - metric promotion allowed: `0`;
  - split assignment allowed: `0`.
- Case state:
  - `20260622_iwate_east_offshore_m30_hinet`: `pending_evidence`,
    blocker `evidence_not_ready`;
  - `20260622_tomakomai_south_offshore_m35_hinet`: `pending_evidence`,
    blocker `evidence_not_ready`;
  - `20260623_tokachi_southeast_offshore_m34_hinet`: `pending_evidence`,
    blocker `evidence_not_ready`.
- Decision:
  - this is staging-only human-review work, not truth acceptance;
  - eligible means evidence is ready and the existing decision remains
    `pending_manual_review`;
  - the report never writes the decision ledger, assigns split membership or
    changes metric eligibility;
  - all three Priority 1 Hi-net cases remain blocked until an authenticated row
    or reviewed no-row-found finding is submitted and a separate reviewer
    decision is imported.
- Validation:
  - `flutter test test\source_hinet_reviewer_decision_staging_report_test.dart`;
  - `flutter analyze tools\build_source_hinet_reviewer_decision_staging_report.dart
    test\source_hinet_reviewer_decision_staging_report_test.dart`;
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_source_hinet_reviewer_decision_staging.ps1`.
- Next evidence step:
  - add a safe reviewer-decision template/import path that can record an
    explicit human acceptance or rejection only after evidence is ready, while
    still keeping split assignment and metric eligibility as separate guarded
    steps.

## 2026-06-27 Source Hi-net Reviewer-Decision Templates and Import

- Added a source Hi-net reviewer-decision template packet:
  - tool: `tools/build_source_hinet_reviewer_decision_template_packet.dart`;
  - validator: `tools/validate_source_hinet_reviewer_decision_templates.ps1`;
  - test: `test/source_hinet_reviewer_decision_template_packet_test.dart`;
  - JSON: `.dart_tool/source_hinet_reviewer_decision_templates/report.json`;
  - Markdown:
    `docs/baselines/source_hinet_reviewer_decision_templates.generated.md`;
  - template directory:
    `.dart_tool/source_hinet_reviewer_decision_templates/files`.
- Added the safe reviewer-decision importer:
  - tool: `tools/import_source_hinet_reviewer_decision.dart`;
  - test: `test/source_hinet_reviewer_decision_import_test.dart`.
- Current generated summary:
  - cases: `3`;
  - reviewer-decision eligible: `0`;
  - templates emitted: `0`;
  - blocked: `3`;
  - decision ledger writes allowed by template packet: `0`;
  - truth-quality acceptance allowed by template packet: `0`;
  - metric promotion allowed: `0`;
  - split assignment allowed: `0`.
- Importer gates:
  - requires `source_hinet_reviewer_decision_staging` status `pass`;
  - requires the target case to have `reviewerDecisionEligible=true`;
  - requires `evidenceType` to be one of the staging case
    `readyEvidenceTypes`;
  - accepts only `accepted_constrained_reference` or
    `rejected_constrained_reference`;
  - rejects credentials, cookies, tokens, sessions, unresolved placeholders,
    non-pending decisions and cases with staging blockers;
  - requires `splitAssignmentAllowed=false` and
    `metricPromotionAllowed=false` in the submitted payload.
- Decision:
  - real current data emits no reviewer-decision templates because all three
    Priority 1 cases are still `evidence_not_ready`;
  - tests simulate an eligible case and verify both acceptance and rejection
    payloads, dry-run immutability and a temp-ledger write path;
  - importing an accepted reviewer decision updates only
    `docs/data/hinet_truth_quality_review_decisions.json`; it still does not
    mutate split manifests, fixture split status or metric eligibility.
- Validation:
  - `flutter test test\source_hinet_reviewer_decision_template_packet_test.dart
    test\source_hinet_reviewer_decision_import_test.dart`;
  - `flutter analyze tools\build_source_hinet_reviewer_decision_template_packet.dart
    tools\import_source_hinet_reviewer_decision.dart
    test\source_hinet_reviewer_decision_template_packet_test.dart
    test\source_hinet_reviewer_decision_import_test.dart`;
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_source_hinet_reviewer_decision_templates.ps1`.
- Next evidence step:
  - fill either an authenticated Hi-net/JMA event-level row template or a
    reviewed no-row-found finding for one Priority 1 case, import it through
    its evidence intake, rerun staging, then use the new reviewer-decision
    importer only if a template is emitted.

## 2026-06-27 Source Hi-net Evidence Intake Worklist

- Added a source Hi-net evidence intake worklist:
  - tool: `tools/build_source_hinet_evidence_intake_worklist.dart`;
  - validator: `tools/validate_source_hinet_evidence_intake_worklist.ps1`;
  - test: `test/source_hinet_evidence_intake_worklist_test.dart`;
  - JSON: `.dart_tool/source_hinet_evidence_intake_worklist/report.json`;
  - Markdown:
    `docs/baselines/source_hinet_evidence_intake_worklist.generated.md`.
- The worklist consumes:
  - `.dart_tool/source_hinet_priority_evidence_template_packet/report.json`;
  - `.dart_tool/source_hinet_no_row_found_review_packet/report.json`;
  - `.dart_tool/source_hinet_evidence_review/report.json`;
  - `.dart_tool/source_hinet_reviewer_decision_templates/report.json`.
- Current generated summary:
  - cases: `3`;
  - authenticated-row templates ready: `3`;
  - no-row-found templates ready: `3`;
  - authenticated evidence ready: `0`;
  - no-row evidence ready: `0`;
  - reviewer-decision templates emitted: `0`;
  - next action: `fill_authenticated_row_or_no_row_finding` for all three
    cases.
- Current worklist targets:
  - `20260622_iwate_east_offshore_m30_hinet`:
    `2026-06-22T11:21:50..2026-06-22T11:31:50`;
  - `20260622_tomakomai_south_offshore_m35_hinet`:
    `2026-06-22T20:32:47..2026-06-22T20:42:47`;
  - `20260623_tokachi_southeast_offshore_m34_hinet`:
    `2026-06-23T23:08:06..2026-06-23T23:18:06`.
- Decision:
  - fill an authenticated-row template first when a matching event row exists;
  - fill a no-row-found template only after an authenticated search finds no
    matching row;
  - after importing any evidence, rerun reviewer-decision staging/templates
    before importing a truth-quality decision;
  - this worklist does not submit evidence, write the decision ledger, accept
    truth quality, assign splits or change metric eligibility.
- Validation:
  - `flutter test test\source_hinet_evidence_intake_worklist_test.dart`;
  - `flutter analyze tools\build_source_hinet_evidence_intake_worklist.dart
    test\source_hinet_evidence_intake_worklist_test.dart`;
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_source_hinet_evidence_intake_worklist.ps1`.
- Next evidence step:
  - use the worklist to fill one Priority 1 evidence template from an
    authenticated Hi-net/JMA event-level search, dry-run the matching importer,
    then import only if the filled template contains no credentials and passes
    validation.

## 2026-06-27 Source Hi-net Unfilled Evidence Template Guard

- Added an unfilled evidence template guard:
  - tool: `tools/build_source_hinet_unfilled_evidence_template_guard.dart`;
  - validator:
    `tools/validate_source_hinet_unfilled_evidence_template_guard.ps1`;
  - test: `test/source_hinet_unfilled_evidence_template_guard_test.dart`;
  - JSON:
    `.dart_tool/source_hinet_unfilled_evidence_template_guard/report.json`;
  - Markdown:
    `docs/baselines/source_hinet_unfilled_evidence_template_guard.generated.md`.
- The guard consumes:
  - `.dart_tool/source_hinet_evidence_intake_worklist/report.json`;
  - `docs/data/hinet_authenticated_export_rows.json`;
  - `docs/data/source_hinet_no_row_found_findings.json`.
- Current generated summary:
  - cases: `3`;
  - authenticated templates rejected: `3`;
  - no-row-found templates rejected: `3`;
  - credential fields present: `0`;
  - accidental importable templates: `0`.
- Decision:
  - generated templates are intentionally not importable while they still
    contain placeholders or null numeric fields;
  - the guard calls import validators directly and never executes import
    commands;
  - no evidence ledger, decision ledger, truth quality, split assignment or
    metric eligibility is changed.
- Validation:
  - `flutter test
    test\source_hinet_unfilled_evidence_template_guard_test.dart`;
  - `flutter analyze
    tools\build_source_hinet_unfilled_evidence_template_guard.dart
    test\source_hinet_unfilled_evidence_template_guard_test.dart`;
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_source_hinet_unfilled_evidence_template_guard.ps1`.
- Next evidence step:
  - fill one authenticated-row or no-row-found evidence template with real
    authenticated search results, rerun the unfilled-template guard and expect
    exactly that filled template to become importable before running its
    importer.

## 2026-06-27 Source Hi-net Evidence Template Target Guard

- Strengthened evidence intake importers so filled templates must match their
  `_queryTarget` metadata:
  - `tools/import_hinet_authenticated_export_row.dart`;
  - `tools/import_source_hinet_no_row_found_finding.dart`.
- Authenticated-row importer now checks, when `_queryTarget` is present:
  - payload `caseId` matches target `caseId`;
  - `originTimeJst` is inside the template query window;
  - filled latitude/longitude remain within 1 degree of the target location;
  - filled magnitude remains within 1.0 of the target magnitude.
- No-row-found importer now checks, when `_queryTarget` is present:
  - payload `caseId` matches target `caseId`;
  - submitted `queryWindowJst` exactly matches the template target window.
- Decision:
  - a reviewer can still submit a revised row that differs from preliminary
    depth or exact hypocenter, but an unrelated row outside the intended
    window/location/magnitude guard is rejected before it becomes evidence;
  - this only tightens evidence intake validation and does not write evidence,
    accept truth quality, assign split membership or change metrics.
- Validation:
  - `flutter test test\hinet_authenticated_export_row_import_test.dart
    test\source_hinet_no_row_found_finding_import_test.dart`;
  - `flutter analyze tools\import_hinet_authenticated_export_row.dart
    tools\import_source_hinet_no_row_found_finding.dart
    test\hinet_authenticated_export_row_import_test.dart
    test\source_hinet_no_row_found_finding_import_test.dart`;
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_source_hinet_unfilled_evidence_template_guard.ps1`.
- Next evidence step:
  - fill one Priority 1 evidence template from the authenticated event-level
    search and dry-run it. The dry-run must pass both required-field validation
    and the `_queryTarget` guard before import.

## 2026-06-27 Source Hi-net No-Row Target Guard

- Strengthened the no-row-found evidence path:
  - `tools/build_source_hinet_no_row_found_review_packet.dart` now copies
    `targetLatitude`, `targetLongitude` and `targetMagnitude` from the
    authenticated-row template `_queryTarget` into the no-row template
    `_queryTarget`;
  - `tools/import_source_hinet_no_row_found_finding.dart` now rejects filled
    no-row findings whose searched latitude/longitude differ from the target by
    more than 1 degree, or whose searched magnitude differs by more than 1.0.
- Decision:
  - no-row-found evidence must prove the reviewer searched the same intended
    event target, not just the same time window;
  - this keeps no-row findings aligned with authenticated-row target guards;
  - no evidence ledger, decision ledger, truth quality, split assignment or
    metric eligibility is changed.
- Validation:
  - `flutter test test\source_hinet_no_row_found_review_packet_test.dart
    test\source_hinet_no_row_found_finding_import_test.dart`;
  - `flutter analyze tools\build_source_hinet_no_row_found_review_packet.dart
    tools\import_source_hinet_no_row_found_finding.dart
    test\source_hinet_no_row_found_review_packet_test.dart
    test\source_hinet_no_row_found_finding_import_test.dart`;
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_source_hinet_unfilled_evidence_template_guard.ps1`.
- Next evidence step:
  - fill a real authenticated-row template when a matching event row exists;
    fill no-row-found only after an authenticated search for the same target
    event returns no matching row.

## 2026-06-27 Source Hi-net Evidence Propagation Rehearsal

- Added a temporary-file-only evidence propagation rehearsal:
  - tool: `tools/build_source_hinet_evidence_propagation_rehearsal.dart`;
  - validator:
    `tools\validate_source_hinet_evidence_propagation_rehearsal.ps1`;
  - test: `test/source_hinet_evidence_propagation_rehearsal_test.dart`;
  - JSON:
    `.dart_tool/source_hinet_evidence_propagation_rehearsal/report.json`;
  - Markdown:
    `docs/baselines/source_hinet_evidence_propagation_rehearsal.generated.md`.
- The rehearsal:
  - reads the current evidence intake worklist;
  - builds one synthetic authenticated row from the first template target;
  - validates it through `import_hinet_authenticated_export_row.dart`;
  - writes only temporary copies of rows/auth-review/evidence-review/staging
    artifacts;
  - verifies the downstream chain:
    `authenticatedEvidenceReady -> sourceEvidenceReady ->
    reviewerDecisionEligible -> reviewerDecisionTemplateEmitted`.
- Current generated summary:
  - rehearsal case: `20260622_iwate_east_offshore_m30_hinet`;
  - import validation errors: `0`;
  - authenticated evidence ready: `true`;
  - source evidence ready: `true`;
  - reviewer-decision eligible: `true`;
  - reviewer-decision template emitted: `true`;
  - real evidence ledger writes: `0`;
  - real decision ledger writes: `0`.
- Decision:
  - this proves the guarded pipeline will progress after a valid evidence
    import;
  - it does not prove any real Hi-net/JMA row exists;
  - it does not accept truth quality, assign split membership or change metric
    eligibility.
- Validation:
  - `flutter test test\source_hinet_evidence_propagation_rehearsal_test.dart`;
  - `flutter analyze
    tools\build_source_hinet_evidence_propagation_rehearsal.dart
    test\source_hinet_evidence_propagation_rehearsal_test.dart`;
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_source_hinet_evidence_propagation_rehearsal.ps1`.
- Next evidence step:
  - perform the real authenticated event-level search for one Priority 1 case,
    fill the matching evidence template, and compare the real post-import
    chain against this rehearsal.

## 2026-06-27 JMA Reference Label Accounting

- Updated the metric-readiness triage report so JMA source-and-intensity
  labels are counted explicitly as reference labels:
  - tool: `tools/build_source_metric_readiness_triage_report.dart`;
  - test: `test/source_metric_readiness_triage_report_test.dart`;
  - JSON: `.dart_tool/source_metric_readiness_triage/report.json`;
  - Markdown: `docs/baselines/source_metric_readiness_triage.generated.md`.
- Current generated summary:
  - reference labels available: `13`;
  - JMA reference labels available: `4`;
  - metric-bearing ready: `0`;
  - diagnostic-ready blocked: `10`.
- Decision:
  - JMA source-and-intensity labels count as usable reference labels for
    diagnostic/replay analysis;
  - pending JMA final-catalog linkage only blocks metric-bearing truth claims,
    final accuracy wording and frozen split promotion;
  - reports must not describe JMA-labelled cases as missing labels.
- Validation:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_source_metric_readiness_triage.ps1`.
- Next algorithm step:
  - continue candidate-region diagnostics with the JMA-labelled cases included
    as reference-labelled diagnostic inputs, while keeping production metric
    promotion blocked until final-catalog or reviewed evidence is linked.

## 2026-06-27 Candidate-Region Four-Case Guard Report

- Added a four-case candidate-region guard summary:
  - tool: `tools/build_source_candidate_region_four_case_report.dart`;
  - validator: `tools\validate_source_candidate_region_four_case.ps1`;
  - test: `test/source_candidate_region_four_case_report_test.dart`;
  - JSON: `.dart_tool/source_candidate_region_four_case/report.json`;
  - Markdown:
    `docs/baselines/source_candidate_region_four_case.generated.md`.
- The report consumes the existing residual delayed-recovery and local-support
  separation reports and puts the four active guard cases in one table:
  - `20260621_fukushima_offshore_m32_eq6`:
    false-recovery guard blocked by dual residual regression and local member
    growth;
  - `20260622_kushiro_offshore_m30_jma`:
    residual delayed-positive guard remains recovered by same-region residual
    confirmation;
  - `20260622_tomakomai_south_offshore_m35_hinet`:
    residual immediate-positive guard remains accepted immediately;
  - `20260625_iwate_offshore_m32_jma`:
    local-support delayed-positive guard remains confirmed by full local
    support.
- Current generated summary:
  - cases: `4`;
  - false-recovery guards blocked: `1`;
  - residual delayed positives: `1`;
  - residual immediate positives: `1`;
  - local-support delayed positives: `1`;
  - production coordinate switches: `0`.
- Decision:
  - this report is diagnostic-only and does not authorize candidate-coordinate
    replacement, metric promotion or split assignment;
  - future residual/local-support threshold tuning must keep all four roles
    unchanged unless a reviewed roadmap decision explicitly changes the guard
    expectations.
- Validation:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_source_candidate_region_four_case.ps1`.
- Next algorithm step:
  - use this four-case guard as the fast checklist before tuning any
    candidate-region residual or local-support threshold.

## 2026-06-27 Iwate M3.4 Capture-Gap Scope

- Clarified the scope for `20260620_iwate_offshore_m34_ref`:
  - the missing local file remains `20260620212727.jma_b.gif`;
  - the event is older than the public KMoni replay retention window, so public
    GIF refetch must not be attempted;
  - keep the case as metadata-only/incomplete or capture-gap regression test
    material unless a local/mirror archive copy is found.
- Decision:
  - this case can be used to test capture-provenance and missing-frame guards;
  - it must not be promoted to algorithm metrics, frozen split assignment or
    catalog-truth validation from the incomplete public capture.

## 2026-06-27 Authenticated JMA Arrival-Time Intake Update

- Processed the authenticated JMA unified arrival-time download provided as
  `D:\Users\Rhythm\Downloads\measure_20260622_1.txt`.
- Imported two matching Priority 1 source-estimation evidence rows into
  `docs/data/hinet_authenticated_export_rows.json` as
  `submitted_for_review`:
  - `20260622_iwate_east_offshore_m30_hinet`;
  - `20260622_tomakomai_south_offshore_m35_hinet`.
- The imported rows are evidence only. They do not automatically accept truth
  quality, assign split membership, or change metric eligibility.
- Updated reviewer-decision staging/templates and the evidence-intake worklist
  for the new state:
  - cases: `3`;
  - authenticated evidence ready: `2`;
  - reviewer-decision templates emitted: `2`;
  - remaining pending evidence case: `20260623_tokachi_southeast_offshore_m34_hinet`.
- Updated the worklist validator so cases that already have authenticated
  evidence are no longer required to keep authenticated/no-row intake templates;
  they now require reviewer-decision template commands instead.
- Validation:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File tools\validate_source_hinet_evidence_intake_worklist.ps1`.
- Next evidence step:
  - download authenticated JMA arrival-time data for `2026-06-23 JST` from
    `https://hinetwww11.bosai.go.jp/auth/JMA/?LANG=en`;
  - target case: `20260623_tokachi_southeast_offshore_m34_hinet`;
  - query window: `2026-06-23T23:08:06..2026-06-23T23:18:06 JST`;
  - if a matching row exists, fill
    `.dart_tool/hinet_authenticated_export_row_templates/files/20260623_tokachi_southeast_offshore_m34_hinet.json`;
  - if no matching row exists after authenticated search, fill the no-row
    finding template instead.

## 2026-06-27 Authenticated JMA Tokachi Row Intake

- Processed the authenticated JMA unified arrival-time download provided as
  `D:\Users\Rhythm\Downloads\measure_20260623_1.txt`.
- Matched the Priority 1 Tokachi case to this event row:
  - raw row:
    `J2026062323130579 011 422996 034 1434090 057 559211230V   711   1 28SE OFF TOKACHI           39K`;
  - origin: `2026-06-23T23:13:05.79 JST`;
  - latitude: `42.499333333333`;
  - longitude: `143.681666666667`;
  - depth: `55.92 km`;
  - magnitude: `M3.0`;
  - region: `SE OFF TOKACHI`.
- Imported `20260623_tokachi_southeast_offshore_m34_hinet` into
  `docs/data/hinet_authenticated_export_rows.json` as
  `submitted_for_review`.
- Current Priority 1 Hi-net evidence state:
  - cases: `3`;
  - authenticated evidence ready: `3`;
  - pending authenticated-row templates: `0`;
  - pending no-row-found templates: `0`;
  - reviewer-decision templates emitted: `3`.
- Decision:
  - all three Priority 1 cases now have authenticated event-level evidence and
    have moved from evidence intake to reviewer-decision staging;
  - this still does not accept truth quality, assign split membership, or
    change metric eligibility.
- Validation:
  - `dart run tools\import_hinet_authenticated_export_row.dart --input .dart_tool\hinet_authenticated_export_row_templates\files\20260623_tokachi_southeast_offshore_m34_hinet.json --dry-run`;
  - `dart run tools\import_hinet_authenticated_export_row.dart --input .dart_tool\hinet_authenticated_export_row_templates\files\20260623_tokachi_southeast_offshore_m34_hinet.json`;
  - `powershell -NoProfile -ExecutionPolicy Bypass -File tools\validate_source_hinet_evidence_intake_worklist.ps1`.
- Next evidence step:
  - fill and dry-run the three reviewer-decision templates under
    `.dart_tool/source_hinet_reviewer_decision_templates/files`;
  - importing accepted reviewer decisions updates only
    `docs/data/hinet_truth_quality_review_decisions.json`; split and metric
    promotion remain separate guarded steps.

## 2026-06-27 Source Hi-net Reviewer Decisions Accepted

- Filled and imported the three Priority 1 reviewer-decision templates as
  `accepted_constrained_reference`:
  - `20260622_iwate_east_offshore_m30_hinet`;
  - `20260622_tomakomai_south_offshore_m35_hinet`;
  - `20260623_tokachi_southeast_offshore_m34_hinet`.
- The accepted decisions were written only to
  `docs/data/hinet_truth_quality_review_decisions.json` with
  `acceptedForConstrainedReferenceSplit=true`.
- Policy remains constrained:
  - `splitAssignmentAllowed=false`;
  - `metricPromotionAllowed=false`;
  - no production source-estimation behavior changes;
  - authenticated Hi-net/JMA rows remain reviewer evidence, not final catalog
    truth.
- Updated `tools/build_source_hinet_evidence_intake_worklist.dart` so accepted
  cases are terminal for evidence intake:
  - next action:
    `accepted_constrained_reference_waiting_split_gate`;
  - authenticated/no-row/reviewer import commands are all `null`;
  - reviewer templates are no longer re-emitted for accepted cases.
- Current generated evidence-intake summary:
  - cases: `3`;
  - authenticated evidence ready: `0`;
  - reviewer-decision templates emitted: `0`;
  - accepted constrained references: `3`;
  - next action counts:
    `{accepted_constrained_reference_waiting_split_gate: 3}`;
  - metric promotion allowed: `0`;
  - split assignment allowed: `0`.
- Validation:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File tools\validate_source_hinet_evidence_intake_worklist.ps1`.
- Next gated step:
  - implement or run the constrained split-assignment readiness gate for these
    three accepted references;
  - do not add them to metric-bearing validation until a separate metric
    readiness gate explicitly allows it.

## 2026-06-27 Split Readiness Propagation After Hi-net Acceptance

- Propagated accepted Hi-net/JMA constrained-reference decisions into split
  assignment readiness:
  - tool updated:
    `tools/build_source_estimation_split_assignment_readiness_report.dart`;
  - decision input:
    `docs/data/hinet_truth_quality_review_decisions.json`;
  - tests updated:
    `test/source_estimation_split_assignment_readiness_report_test.dart`,
    `test/source_estimation_split_blocker_queue_report_test.dart`,
    `test/source_metric_readiness_triage_report_test.dart`.
- Current split-readiness summary:
  - cases: `13`;
  - ready for frozen split: `2`;
  - ready for manual split assignment: `3`;
  - new manual-ready cases:
    `20260622_iwate_east_offshore_m30_hinet`,
    `20260622_tomakomai_south_offshore_m35_hinet`,
    `20260623_tokachi_southeast_offshore_m34_hinet`;
  - next action counts now include `assign_event_level_split: 3`.
- Current metric-readiness summary:
  - metric-bearing ready: `0`;
  - diagnostic-ready blocked: `10`;
  - metadata-only/incomplete: `1`;
  - ready for manual split assignment: `3`.
- Decision:
  - accepted constrained references can advance to manual event-level split
    assignment;
  - this does not promote them to metric-bearing validation;
  - production source coordinates and candidate-region coordinate switching
    remain unchanged.
- Validation:
  - `powershell -NoProfile -ExecutionPolicy Bypass -File tools\validate_source_estimation_split_assignment_readiness.ps1`;
  - `powershell -NoProfile -ExecutionPolicy Bypass -File tools\validate_source_estimation_split_blocker_queue.ps1 -UseExistingReadiness`;
  - `powershell -NoProfile -ExecutionPolicy Bypass -File tools\validate_source_metric_readiness_triage.ps1`.

## 2026-06-27 Candidate-Region Manifest Non-Regression After Split Readiness

- Re-ran the candidate-region validation suite after evidence/split readiness
  propagation:
  - command:
    `powershell -NoProfile -ExecutionPolicy Bypass -File tools\validate_source_candidate_region_suite.ps1`.
- Result:
  - candidate promotion matrix: pass;
  - candidate-region timeline: pass;
  - validation scripts guard: pass;
  - suite summary: pass.
- Scope note:
  - 13 early-frame reports were generated;
  - 2 inputs without truth latitude/longitude were skipped as non-candidate
    benchmark/noise inputs.
- Decision:
  - residual and local-support candidate-region guard behavior did not regress;
  - candidate coordinates remain diagnostic-only;
  - production coordinate switching remains disabled.
- Next implementation step:
  - add explicit manual split-assignment recommendations for the three
    manual-ready constrained references, keeping them out of final metric
    claims unless a later metric-readiness gate approves them.

## 2026-06-27 Surface-Image-Only Source Estimation Probe

- Added a diagnostic replay input mode for source-estimation benchmarks:
  - `SourceEstimationBenchmarkInputMode.surfaceImageOnly`;
  - meaning: use `jma_s` surface GIF pixels for every station, including
    KiK-net stations; do not feed `jma_b` borehole GIF pixels.
- Added the surface-only comparison report:
  - tool: `tools/build_source_surface_image_only_comparison.dart`;
  - validator: `tools\validate_source_surface_image_only_comparison.ps1`;
  - test: `test/source_surface_image_only_comparison_test.dart`;
  - JSON:
    `.dart_tool/source_surface_image_only_comparison/report.json`;
  - Markdown:
    `docs/baselines/source_surface_image_only_comparison.generated.md`.
- Current generated summary over local usable fixtures:
  - cases run: `18`;
  - event cases: `16`;
  - skipped: `1` legacy-format Noto fixture;
  - median of median-error delta: `0.0 km`;
  - median of P90-error delta: `0.0 km`;
  - better / equal / worse median-error cases: `4 / 5 / 3`;
  - noise false estimates remain `0`.
- Notable surface-only changes:
  - Fukushima Aizu M3.2 improves slightly:
    median `9 -> 8 km`, error at +10 s `15 -> 7 km`;
  - Kushiro offshore M3.0 improves slightly:
    median `28 -> 26 km`, P90 `118.2 -> 117.4 km`;
  - Nara M3.6 improves:
    median `8 -> 7 km`, P90 `13 -> 10 km`;
  - Wakayama M2.5 improves:
    median `5 -> 4 km`, P90 `6.8 -> 6 km`;
  - Iwate offshore M3.2 worsens materially:
    median `25 -> 75 km`, P90 `66 -> 76 km`;
  - Iwate offshore M3.4 worsens in tail:
    median `43 -> 45.5 km`, P90 `54 -> 96 km`;
  - Tokachi southeast offshore M3.4 worsens in tail:
    median unchanged `18 km`, P90 `45 -> 68 km`;
  - Tomakomai south offshore M3.5 worsens slightly:
    median `13 -> 15 km`, P90 unchanged `55 km`.
- Decision:
  - historical diagnostic result: surface-image-only was not a clear accuracy
    improvement in this replay comparison;
  - this accuracy result is superseded by the later surface-only default input
    semantics decision;
  - any offshore regressions after the switch must be handled by trigger
    membership, geometry priors, uncertainty gates, or attenuation calibration,
    not by silently mixing borehole and surface shindo values.
- Validation:
  - `flutter test test\source_surface_image_only_comparison_test.dart`;
  - `flutter analyze test\support\source_estimation_benchmark.dart
    tools\build_source_surface_image_only_comparison.dart
    test\source_surface_image_only_comparison_test.dart`.

## 2026-06-27 NIED Station Layer Role Audit

- Added an explicit audit for station layer routing:
  - tool: `tools/build_nied_station_layer_role_audit.dart`;
  - test: `test/nied_station_layer_role_audit_test.dart`;
  - JSON: `.dart_tool/nied_station_layer_role_audit/report.json`;
  - Markdown:
    `docs/baselines/nied_station_layer_role_audit.generated.md`.
- Current project behavior is now documented:
  - all `K-NET` stations are routed to `jma_s`;
  - all `KiK-net` stations are routed to `jma_b`;
  - this is inferred from `network contains "kik"`, not from an explicit
    per-station GIF layer role.
- Current counts:
  - station DB: `1749`;
  - K-NET: `1047`;
  - KiK-net: `702`;
  - scan-mapped stations used by GIF sampling: `1630`;
  - scan-mapped `jma_s` primary: `936`;
  - scan-mapped `jma_b` primary: `694`.
- Probe result over 24 local `jma_s/jma_b` pairs:
  - `153` KiK-net stations were flagged as surface-dominant candidates in the
    sampled frames;
  - top examples include `TCGH16`, `CHBH14`, and `IBRH21`.
- Decision:
  - superseded by the later surface-only default input decision below;
  - split station metadata into `physicalSensorRole` and
    `gifDisplayPrimaryLayer`;
  - map display should consume `gifDisplayPrimaryLayer`;
  - source estimation should continue to use an explicit sensor-selection
    policy and replay gates before any behavior change.
- Validation:
  - `flutter test test\nied_station_layer_role_audit_test.dart`;
  - `dart run tools\build_nied_station_layer_role_audit.dart --probe-root
    tmp\captures --max-probe-frames 24`;
  - `flutter analyze tools\build_nied_station_layer_role_audit.dart
    test\nied_station_layer_role_audit_test.dart`;
  - `git diff --check -- tools/build_nied_station_layer_role_audit.dart
    test/nied_station_layer_role_audit_test.dart
    docs/baselines/nied_station_layer_role_audit.generated.md`.

## 2026-06-27 Surface-Only Default Input Decision

- Decision:
  - default real-time NIED GIF shindo input must read the surface layer
    `jma_s` for all scan-mapped stations, including KiK-net stations;
  - `jma_b` remains a borehole/underground auxiliary layer for capture,
    provenance, diagnostics, and future explicitly configured experiments;
  - `jma_b` must not be used by the default source-estimation shindo score,
    map station display, source-trigger member display, or production quality
    lines unless a future validation gate enables a named borehole policy.
- Rationale:
  - official NIED semantics distinguish K-NET surface stations from KiK-net
    stations that have both surface and borehole sensors;
  - therefore `network contains "kik"` is not a valid rule for choosing the
    GIF display/input layer;
  - the project needs a consistent surface shindo field before continuing
    attenuation calibration or source-estimation tuning.
- Implementation status:
  - replaced the implicit `KiK-net => jma_b` routing in
    `LmoniImageService.processPixels`, `processSampledFrame`,
    `processPhysicalLayerPixels`, background scan configs, and station
    descriptor/provenance tags with an explicit policy:
    `gifDisplayPrimaryLayer=jma_s`;
  - preserved `physicalSensorRole` separately so official waveform and borehole
    diagnostics can still distinguish KiK-net surface and borehole records;
  - regenerated the station-layer audit and surface-only comparison after the
    code switch;
  - reran split readiness, metric readiness, candidate-region validation, and
    the top-level source-estimation validation suite after the code switch;
  - regenerated the referenced per-capture layer-alignment reports with
    `tools/build_nied_layer_alignment_report.dart`; these remain diagnostic
    event-specific sensor-domain reports, not global gate blockers.
- Risk note:
  - the earlier diagnostic surface-only comparison showed some offshore
    regressions, so the switch is a data-semantics correction, not a claimed
    accuracy improvement;
  - production coordinate switching and candidate-region promotion remain
    disabled until the metric-readiness gate is updated and passes.

## 2026-06-27 Intensity Estimation Status

- Production already has legacy empirical intensity calculation from known
  hypocenter parameters, but that is separate from the new station-evidence
  source-estimation work.
- The new P3 static intensity attenuation baseline is implemented and trained
  from JMA final station-intensity synthetic-reveal data.
- Current validation-only result:
  - P3 median/P90: `33.98 km / 92.55 km`;
  - weighted-centroid median/P90: `35.68 km / 94.91 km`;
  - P90 uncertainty coverage: `78.2%`.
- Forecast validation-only result on synthetic reveal final peak intensities:
  - max-shindo class MAE: `0.61` classes;
  - max-shindo numeric MAE: `0.62`;
  - station intensity MAE: `0.67`;
  - exact / within-one max-class accuracy: `47.2% / 92.7%`;
  - max-class underestimation rate: `52.8%`;
  - high-shindo threshold recall is high but precision is low (`shindo4`
    precision `28.3%`, `shindo5-` precision `17.2%`), so the model is not yet
    production-calibrated.
- Global additive calibration scan:
  - diagnostic best offset: `-0.20`;
  - station intensity MAE improves `0.67 -> 0.59`;
  - `shindo4` precision improves `28.3% -> 33.5%`, recall decreases
    `88.6% -> 83.0%`;
  - `shindo5-` precision improves `17.2% -> 22.4%`, recall decreases
    `74.9% -> 57.2%`;
  - max-class MAE worsens `0.61 -> 0.77` and underestimation worsens
    `52.8% -> 65.8%`, so a single global offset is not acceptable as a final
    calibration policy.
- Precision-safe stratified calibration scan:
  - buckets: baseline predicted maximum class x P90 location-uncertainty bucket;
  - changed strata: `1/3`;
  - selected offset: `pred_le_2/p90_50_100km -> +0.10`;
  - max-class MAE improves `0.61 -> 0.56`;
  - max-class underestimation improves `52.8% -> 48.7%`;
  - station MAE worsens `0.67 -> 0.70`;
  - high-shindo precision does not improve (`shindo4` and `shindo5-` P/R/F1
    are unchanged overall), so this remains diagnostic-only.
- Station-distance diagnostic:
  - `gt_200km` stations have mean residual `+1.09` and MAE `1.14`;
  - this long-distance positive residual is the next likely source of
    high-shindo false positives.
- Distance residual correction scan:
  - all-distance correction improves station MAE `0.67 -> 0.50` and
    high-shindo precision, but damages max-class MAE `0.61 -> 0.95` and
    underestimation `52.8% -> 76.2%`;
  - targeted `gt_200km` correction preserves max-class MAE and underestimation
    while improving station MAE `0.67 -> 0.56`;
  - targeted `gt_200km` correction improves `shindo4` precision
    `28.3% -> 46.2%` and `shindo5-` precision `17.2% -> 33.3%`;
  - this is promising as a probability/confidence feature, but not yet a
    direct runtime intensity-field correction.
- Probability/confidence gate scan:
  - raw intensity field remains unchanged;
  - `shindo3` gate: precision/recall/F1 `41.6% / 84.6% / 55.8%`;
  - `shindo4` gate: precision/recall/F1 `55.1% / 63.6% / 59.0%`;
  - `shindo5-` gate: precision/recall/F1 `33.3% / 71.1% / 45.3%`;
  - `shindo4` precision and F1 improve substantially, but recall loss is now
    the acceptance-risk item.
- Probability-gate acceptance:
  - criteria: precision gain >= `10%`, F1 gain >= `10%`, recall loss <=
    `18%`, false-negative ratio <= `3.0x`;
  - `shindo5-` passes;
  - `shindo4` is `warn` because recall loss is `24.9%` and false-negative
    ratio is `3.18x`;
  - ready for frozen test: `false`;
  - requires manual product/algorithm decision: `true`.
- Baseline report:
  `docs/baselines/static_attenuation_validation.generated.md`.
- Forecast metric report:
  `docs/baselines/static_intensity_forecast_validation.generated.md`.
- Calibration scan report:
  `docs/baselines/static_intensity_calibration.generated.md`.
- Stratified calibration report:
  `docs/baselines/static_intensity_stratified_calibration.generated.md`.
- Distance residual calibration report:
  `docs/baselines/static_intensity_distance_residual_calibration.generated.md`.
- Probability-gate literature notes:
  `docs/baselines/static_intensity_probability_gate_literature.md`.
- Probability gate report:
  `docs/baselines/static_intensity_probability_gate.generated.md`.
- Probability gate acceptance report:
  `docs/baselines/static_intensity_probability_gate_acceptance.generated.md`.
- JMA-style traditional intensity diagnostic:
  `docs/baselines/jma_style_intensity.generated.md`.
  - oracle-source validation cases: `896`;
  - station forecasts: `61898`;
  - max-shindo class MAE: `0.43` classes;
  - max-shindo within-one accuracy: `97.1%`;
  - `shindo4`: precision `78.3%`, recall `27.5%`, F1 `40.7%`;
  - `shindo5-`: precision `65.0%`, recall `4.0%`, F1 `7.5%`;
  - P3-estimated-source variants: `2688` cases, `185694` station forecasts;
  - P3-estimated-source max-shindo class MAE: `0.59` classes;
  - P3-estimated-source within-one accuracy: `92.9%`;
  - P3-estimated-source `shindo4`: precision `56.5%`, recall `51.0%`,
    F1 `53.6%`;
  - P3-estimated-source `shindo5-`: precision `87.8%`, recall `8.1%`,
    F1 `14.8%`;
  - default ARV rate: `0.1%`.
- Decision:
  - keep it diagnostic-only;
  - do not expose it as predicted maximum shindo or production accuracy;
  - do not describe this as realtime lead-time validation because it uses
    final peak station intensities with synthetic reveal masks;
  - use distance residuals as threshold probability/confidence features before
    considering any raw intensity-field mutation;
  - use JMA-style traditional PGV attenuation as a conservative baseline and
    calibration reference only, because high-shindo recall is too low under
    both oracle and P3-estimated source variants;
  - do not open frozen test until surface-default-aligned recalibration and
    acceptance criteria are defined.
- Next algorithm step:
  - resolve the `shindo4` warning before frozen test:
    either relax the operating point to recover recall while preserving a
    precision/F1 gain, or explicitly accept the current precision-vs-recall
    tradeoff as product policy;
  - implement PLUM-like observed-shaking propagation separately and compare it
    against the traditional path before any production forecast decision;
  - only after that decision, run the frozen-test evaluation;
  - define frozen-test acceptance criteria before any production UI use.

## 2026-06-27 PLUM-Like Replay Radius/Damping Diagnostic

- Updated the PLUM-like replay lead-time diagnostic to remain source
  independent and surface-only:
  `docs/baselines/plum_like_replay_leadtime.generated.md`.
- The replay set now covers 7 local `jma_s` cases, 1201 decoded frames and
  1957630 station-frames, including the Yamanashi M5.6 strong-motion replay.
- Baseline `30 km / 0.25 shindo per 10 km` propagation remains diagnostic-only:
  - `shindo4`: recall `84.4%`, false-alarm ratio `49.1%`;
  - `shindo5-`: recall `50.0%`, false-alarm ratio `86.4%`.
- Evidence-count gates (`1/2/3`) do not change the current result. Persistence
  gates reduce recall but do not materially remove high-threshold false-alarm
  stations.
- Added radius/damping grid comparison inside the same replay pass. Current
  diagnostic candidates:
  - `20 km / 0.50`: `shindo4` recall `56.3%`, 14 false-alarm stations;
  - `30 km / 0.50`: `shindo4` recall `62.5%`, 17 false-alarm stations;
  - stronger damping (`0.75` to `1.00`) cuts false alarms further but loses too
    much recall for a first operating point.
- Added the three new replay references to
  `docs/data/source_estimation_split_assignment_plan.json` as
  `unassigned_reference` with `keep_plum_like_diagnostic_only`; they remain
  outside frozen metrics.
- Validation:
  - `flutter test test\plum_like_replay_leadtime_report_test.dart`;
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_source_estimation_split_audit.ps1`;
  - `powershell -NoProfile -ExecutionPolicy Bypass -File
    tools\validate_source_estimation_split_assignment_readiness.ps1`.
- Next algorithm step:
  - choose a PLUM-like operating-point candidate from the radius/damping grid;
  - run it against the combined JMA-style/P3 branch as diagnostic-only;
  - do not connect this to production UI, notification wording or frozen-test
    claims until acceptance criteria are written and passed.

## 2026-06-27 Combined PLUM Operating-Point Diagnostic

- Updated `tools/build_combined_intensity_prediction_report.dart` to include
  the replay-grid PLUM candidates `plum_like_r20_d0_50` and
  `plum_like_r30_d0_50`, plus their station-level `max(JMA-style, PLUM)`
  variants.
- This report is still synthetic-reveal validation, not realtime lead-time:
  `docs/baselines/combined_intensity_prediction.generated.md`.
- Baseline `plum_like` (`30 km / 0.25`) keeps high recall but remains
  false-positive heavy:
  - `shindo4`: `57.4% / 78.9% / 66.5%`;
  - `shindo5-`: `43.8% / 67.4% / 53.1%`.
- Candidate `plum_like_r30_d0_50` shifts toward precision:
  - `shindo4`: `69.7% / 62.8% / 66.1%`;
  - `shindo5-`: `58.1% / 45.5% / 51.0%`.
- Candidate combined branch `max_jma_style_plum_like_r30_d0_50`:
  - max-class MAE `0.44`;
  - max-class underestimation `20.2%`;
  - `shindo4`: `55.9% / 72.5% / 63.1%`;
  - `shindo5-`: `58.8% / 46.9% / 52.2%`.
- Interpretation:
  - `30 km / 0.50` is the best current diagnostic candidate because it reduces
    false positives while avoiding the larger recall loss of stricter damping;
  - it does not replace the baseline and is not production-selected;
  - the next gate should define explicit acceptance criteria across both
    synthetic reveal and real replay lead-time before opening frozen test.
- Validation:
  - `flutter test test\combined_intensity_prediction_report_test.dart`;
  - `dart analyze tools\build_combined_intensity_prediction_report.dart
    test\combined_intensity_prediction_report_test.dart`.

## 2026-06-27 PLUM Operating-Point Acceptance Diagnostic

- Added `tools/build_plum_operating_point_acceptance_report.dart`.
- The report reads the generated combined synthetic-reveal report and the real
  replay lead-time report; it does not rerun replay decoding and does not touch
  production code.
- Generated report:
  `docs/baselines/plum_operating_point_acceptance.generated.md`.
- Current diagnostic criteria:
  - replay `shindo4` recall >= `60%`;
  - replay `shindo4` false-alarm station reduction >= `25%` versus baseline;
  - combined synthetic-reveal `shindo4` recall >= `70%`;
  - combined synthetic-reveal `shindo4` F1 must not fall below baseline
    combined;
  - replay coverage must include at least `7` complete cases and `1000`
    decoded frames.
- Result:
  - after the complete-capture guard, the replay set has only `6` complete
    cases and `906` decoded frames;
  - `plum_like_r20_d0_50`: `warn`, because replay `shindo4` recall is `56.3%`
    and `replayCoverage=false`;
  - `plum_like_r30_d0_50`: `warn`, because `replayCoverage=false` even though
    replay `shindo4` recall is `62.5%`, replay false-alarm station reduction
    is `37.0%`, and combined `shindo4` P/R/F1 is
    `55.9% / 72.5% / 63.1%`.
- Decision:
  - recommended diagnostic candidate: `none`;
  - `advanceToFrozenTest=false`;
  - `advanceToProduction=false`.
- Next algorithm step:
  - restore replay coverage by adding complete high-shindo local captures, or by
    repairing failed GIF captures only while they are still inside the 3-hour
    historical GIF window, before writing any new frozen-test acceptance
    criteria;
  - keep production UI, notifications and warning wording disconnected.
- Validation:
  - `flutter test test\plum_operating_point_acceptance_report_test.dart`;
  - `dart run tools\build_plum_operating_point_acceptance_report.dart`;
  - `dart analyze tools\build_plum_operating_point_acceptance_report.dart
    test\plum_operating_point_acceptance_report_test.dart`.

## 2026-06-28 PLUM Frozen-Test Acceptance Criteria

- Added `tools/build_plum_frozen_test_acceptance_criteria_report.dart`.
- This report freezes the diagnostic candidate and acceptance thresholds before
  the frozen split is opened. It does not evaluate frozen data and does not
  touch production code.
- Generated report:
  `docs/baselines/plum_frozen_test_acceptance_criteria.generated.md`.
- Selected diagnostic operating point:
  - candidate: `plum_like_r30_d0_50`;
  - combined method: `max_jma_style_plum_like_r30_d0_50`;
  - replay key: `r30_d0.50`;
  - radius `30 km`, damping `0.50 shindo / 10 km`, minimum evidence `1`;
  - surface input only, source-independent PLUM branch.
- Synthetic-reveal frozen criteria:
  - max-class MAE <= `0.50`;
  - max-class underestimation <= `25%`;
  - max-class within-one accuracy >= `94%`;
  - `shindo4` P/R/F1 >= `52% / 68% / 60%`;
  - `shindo5-` P/R/F1 >= `52% / 40% / 48%`.
- Real-replay frozen criteria:
  - case count >= `7`;
  - decoded frames >= `1000`;
  - actual `shindo4` stations >= `20`;
  - `shindo4` recall >= `55%`;
  - `shindo4` false-alarm station reduction >= `25%`;
  - `shindo4` false-alarm ratio <= `50%`;
  - median lead >= `0 s`;
  - `shindo5-` stays a watch metric until actual station count reaches `10`.
- Decision:
  - ready to run frozen evaluation: `true`;
  - advance to production: `false`;
  - next action: `run_plum_frozen_test_evaluation_once`.
- Validation:
  - `flutter test test\plum_frozen_test_acceptance_criteria_report_test.dart`;
  - `dart run tools\build_plum_frozen_test_acceptance_criteria_report.dart`;
  - `dart analyze tools\build_plum_frozen_test_acceptance_criteria_report.dart
    test\plum_frozen_test_acceptance_criteria_report_test.dart`.

## 2026-06-28 PLUM Frozen-Test Evaluation

- Added `tools/build_plum_frozen_test_evaluation_report.dart`.
- Extended `SyntheticRevealDatasetBuilder` with explicit `generatedSplits`, so
  the default build still excludes test data, while the frozen evaluation can
  generate `synthetic_reveal_test.json` only after criteria are fixed.
- Generated report:
  `docs/baselines/plum_frozen_test_evaluation.generated.md`.
- Candidate evaluated:
  - `plum_like_r30_d0_50`;
  - combined method `max_jma_style_plum_like_r30_d0_50`;
  - 2022 frozen synthetic-reveal test split;
  - 919 events, 2757 variants, 179844 station forecasts.
- Outcome: `fail`.
- Passing checks:
  - max-class MAE `0.440` <= `0.50`;
  - max-class underestimation `17.2%` <= `25%`;
  - max-class within-one accuracy `95.4%` >= `94%`.
- Failed high-shindo checks:
  - `shindo4` P/R/F1 `38.0% / 57.2% / 45.7%`;
  - required `shindo4` P/R/F1 >= `52% / 68% / 60%`;
  - `shindo5-` P/R/F1 `26.5% / 38.1% / 31.3%`;
  - required `shindo5-` P/R/F1 >= `52% / 40% / 48%`.
- Decision:
  - production remains blocked;
  - do not revise thresholds using this frozen result as a tuning set;
  - next action is frozen-regression diagnosis before any production-readiness
    gate.
- Validation:
  - `flutter test test\synthetic_reveal_dataset_test.dart
    test\plum_frozen_test_evaluation_report_test.dart`;
  - `dart analyze lib\core\replay\synthetic_reveal_dataset.dart
    test\synthetic_reveal_dataset_test.dart
    tools\build_combined_intensity_prediction_report.dart
    tools\build_plum_frozen_test_evaluation_report.dart
    test\plum_frozen_test_evaluation_report_test.dart`.

## 2026-06-28 PLUM Frozen Regression Diagnostic

- Added `tools/build_plum_frozen_regression_diagnostic_report.dart`.
- The diagnostic compares validation vs frozen test for the frozen diagnostic
  method `max_jma_style_plum_like_r30_d0_50`; it does not change thresholds,
  model parameters, production UI, notifications or warning wording.
- Generated report:
  `docs/baselines/plum_frozen_regression_diagnostic.generated.md`.
- Overall regression:
  - `shindo4` validation P/R/F1 `55.9% / 72.5% / 63.1%`;
  - `shindo4` test P/R/F1 `38.0% / 57.2% / 45.7%`;
  - delta `-17.9 / -15.2 / -17.4` points;
  - `shindo5-` validation P/R/F1 `58.8% / 46.9% / 52.2%`;
  - `shindo5-` test P/R/F1 `26.5% / 38.1% / 31.3%`;
  - delta `-32.3 / -8.9 / -20.9` points.
- Worst `shindo4` F1 drops:
  - `eventLatitudeBand=kanto_chubu`: validation `69.5%`, test `23.5%`,
    delta `-46.0` points;
  - `stationDistance=030_060km`: validation `71.2%`, test `45.6%`,
    delta `-25.6` points;
  - `maskRate=80pct`: validation `59.4%`, test `37.2%`,
    delta `-22.2` points;
  - `actualMaxClass=max_5plus`: validation `68.8%`, test `50.6%`,
    delta `-18.1` points.
- Interpretation:
  - the validation gate did not sufficiently cover geographic generalization
    and high-mask high-shindo degradation;
  - the problem is not only far-distance false positives, because `030_060km`
    and `060_100km` also regress strongly;
  - production remains blocked.
- Next action:
  - build event/station-level drilldown for the worst buckets, starting with
    `kanto_chubu`, `030_060km`, and `80pct`;
  - inspect false-positive and false-negative exemplars before any model-family
    revision or new validation gate.
- Validation:
  - `flutter test test\plum_frozen_regression_diagnostic_report_test.dart`;
  - `dart run tools\build_plum_frozen_regression_diagnostic_report.dart`;
  - `dart analyze tools\build_plum_frozen_regression_diagnostic_report.dart
    test\plum_frozen_regression_diagnostic_report_test.dart`.

## 2026-06-28 PLUM Frozen Regression Drilldown

- Added `tools/build_plum_frozen_regression_drilldown_report.dart` and
  `test/plum_frozen_regression_drilldown_report_test.dart`.
- Generated report:
  `docs/baselines/plum_frozen_regression_drilldown.generated.md`.
- Scope:
  - diagnostic-only analysis of the already-opened frozen synthetic-reveal test
    split;
  - no production UI, notification, warning wording or runtime intensity field
    changes;
  - no new coordinate/source-location switching.
- Coverage:
  - 179844 station forecasts;
  - 0 skipped no-estimate variants.
- Target buckets inspected:
  - `eventLatitudeBand_kanto_chubu`;
  - `stationDistance_030_060km`;
  - `maskRate_80pct`;
  - `actualMaxClass_max_5plus`.
- Key drilldown counts:
  - `eventLatitudeBand_kanto_chubu`: 257 false positives and 257 false
    negatives;
  - `stationDistance_030_060km`: 224 false positives and 196 false
    negatives;
  - `maskRate_80pct`: 910 false positives and 865 false negatives;
  - `actualMaxClass_max_5plus`: 3054 false positives and 1459 false
    negatives.
- Interpretation:
  - the frozen failure is not a single far-distance problem;
  - false positives show strong local observed shaking being propagated into
    weak stations;
  - false negatives show high-mask variants and true strong stations not being
    recovered by the current `max(JMA-style, PLUM-like)` branch;
  - a simple station-distance cap alone would likely trade one error mode for
    the other.
- Decision:
  - production remains blocked;
  - the opened frozen split must not be used for tuning claims;
  - next work must design a validation-only guard/model-family revision and
    prove it on train/validation/replay diagnostics before any future frozen
    decision.
- Candidate next guard ideas, validation-only:
  - local contrast/gradient guard to stop spreading isolated strong evidence
    into clearly weak neighborhoods;
  - strong-evidence neighborhood shape guard before high-shindo propagation;
  - mask/evidence robustness requirement for high-threshold predictions;
  - region/site-amplification calibration using training and validation only.
- Validation:
  - `flutter test test\plum_frozen_regression_drilldown_report_test.dart`;
  - `dart run tools\build_plum_frozen_regression_drilldown_report.dart`;
  - `dart analyze tools\build_plum_frozen_regression_drilldown_report.dart
    test\plum_frozen_regression_drilldown_report_test.dart`.

## 2026-06-28 PLUM Validation Local-Contrast Guard

- Added `tools/build_plum_validation_guard_report.dart` and
  `test/plum_validation_guard_report_test.dart`.
- Generated report:
  `docs/baselines/plum_validation_guard.generated.md`.
- Scope:
  - validation-only guard-family diagnostic;
  - frozen test is not evaluated;
  - production UI, notifications and warning wording remain disconnected;
  - the guard caps only the diagnostic PLUM branch, not raw observed station
    values or JMA-style estimates.
- Guard family:
  - baseline is `max_jma_style_plum_like_r30_d0_50`;
  - local-contrast candidates cap PLUM propagation when the nearest retained
    neighbor inside a local radius is weak;
  - this directly targets the drilldown FP mode where strong local observed
    shaking spreads into weak stations.
- Validation coverage:
  - 185694 station forecasts;
  - 0 missing-magnitude events;
  - 0 no-source-estimate variants.
- Best current validation-only candidate:
  - `local_contrast_r20_w3_0_m1_cap0_5`;
  - triggered on 490 station forecasts;
  - `shindo4` precision/recall/F1 changes from
    `55.9% / 72.5% / 63.1%` to `56.9% / 71.9% / 63.5%`;
  - `shindo4` false positives reduce from 3015 to 2872;
  - `shindo4` false negatives increase from 1453 to 1483;
  - `shindo5-` F1 drops from 52.2% to 50.0%.
- Decision:
  - this is a candidate for further real-replay validation only;
  - it is not production-ready because the improvement is modest and there is
    a measurable `shindo5-` recall/F1 cost;
  - do not open or retune against frozen test for this guard family yet.
- Next action:
  - run the recommended local-contrast candidate through the existing
    `plum_like_replay_leadtime` real replay cases;
  - compare false-alarm station reduction, `shindo4` recall, `shindo5-` watch
    metrics and lead-time impact;
  - if replay regresses, revise guard family on validation/replay diagnostics
    only.
- Validation:
  - `flutter test test\plum_validation_guard_report_test.dart`;
  - `dart run tools\build_plum_validation_guard_report.dart`;
  - `dart analyze tools\build_plum_validation_guard_report.dart
    test\plum_validation_guard_report_test.dart`.

## 2026-06-28 PLUM Replay Local-Contrast Guard Check

- Extended `tools/build_plum_like_replay_leadtime_report.dart` with the
  validation-selected local contrast row:
  `r30_d0.50_local_contrast_r20_w3.0`.
- Generated report:
  `docs/baselines/plum_like_replay_leadtime.generated.md`.
- Complete-capture guard:
  - the report now excludes any replay case whose capture manifest has
    `failedGifCount > 0`;
  - `20260626_yamanashi_east_fuji_five_lakes_m33_jma_equake8` is therefore
    kept in `skippedCases` instead of contributing incomplete frames to the
    lead-time metrics.
- Replay comparison:
  - baseline candidate `r30_d0.50`: `shindo4` recall/false alarms
    `62.5% / 17`;
  - local contrast guard: `shindo4` recall/false alarms `40.6% / 12`;
  - `shindo5-` remains `25.0% / 5`.
- Decision:
  - reject this local-contrast guard for now;
  - the false-alarm reduction is real but the replay `shindo4` recall loss is
    too large;
  - do not advance it to frozen test or production.
- Updated interpretation:
  - the validation-only local contrast signal is too brittle under real replay
    timing and GIF observation sparsity;
  - the next guard family should be softer than hard capping, likely a
    confidence/wording gate or a threshold-probability feature rather than raw
    PLUM intensity suppression.
- Validation:
  - `flutter test test\plum_like_replay_leadtime_report_test.dart`;
  - `dart analyze tools\build_plum_like_replay_leadtime_report.dart
    test\plum_like_replay_leadtime_report_test.dart`.

## 2026-06-28 PLUM Confidence Gate Triage

- Added validation-only confidence gate tooling:
  - `tools/build_plum_confidence_gate_report.dart`;
  - `test/plum_confidence_gate_report_test.dart`;
  - `docs/baselines/plum_confidence_gate.generated.md`.
- Added validation-plus-replay triage tooling:
  - `tools/build_plum_confidence_gate_acceptance_report.dart`;
  - `test/plum_confidence_gate_acceptance_report_test.dart`;
  - `docs/baselines/plum_confidence_gate_acceptance.generated.md`.
- Scope:
  - confidence gates do not mutate raw predicted intensity;
  - they only decide whether a high-threshold prediction is confidence
    supported;
  - frozen test, production UI, notifications and warning wording remain
    disconnected.
- Product boundary:
  - raw predicted intensity remains the canonical prediction output;
  - confidence gates must not replace, cap or hide predicted intensity;
  - confidence gates may only feed a later wording layer, such as
    `high_confidence`, `possible`, or `reference`;
  - notification triggering must not consume this confidence layer until a
    separate notification policy and tests are written.
- Validation result:
  - recommended gate: `plum_r20_d0_50_only`;
  - baseline raw signal: `max(JMA-style, PLUM r30/d0.50)`;
  - `shindo4` precision/recall/F1 changes from
    `55.9% / 72.5% / 63.1%` to `69.6% / 60.7% / 64.8%`;
  - `shindo4` false positives reduce from 3015 to 1399;
  - `shindo4` false negatives increase from 1453 to 2076.
- Replay triage:
  - matching replay row: `r20_d0.50`;
  - baseline `r30_d0.50` replay `shindo4` recall/false alarms:
    `62.5% / 17`;
  - confidence gate replay `shindo4` recall/false alarms: `56.3% / 14`;
  - false-alarm reduction is `17.6%`.
- Decision:
  - status `fail`;
  - ready for frozen criteria: `false`;
  - requires manual decision: `true`;
  - reasons:
    - replay recall is below the preferred `60%` floor even though it is above
      the hard minimum `55%`;
    - replay coverage is below the minimum `7` complete cases / `1000` decoded
      frames after incomplete captures are skipped.
- Next action:
  - do not open frozen test or production wiring;
  - keep predicted intensity display separate from confidence wording;
  - wording labels such as `high_confidence`, `possible`, and `reference` are
    deferred to a later UI/wording design step;
  - if that later step proceeds, define wording-only acceptance criteria before
    any further frozen evaluation.
- Validation:
  - `flutter test test\plum_confidence_gate_report_test.dart`;
  - `flutter test test\plum_confidence_gate_acceptance_report_test.dart`;
  - `dart run tools\build_plum_confidence_gate_report.dart`;
  - `dart run tools\build_plum_confidence_gate_acceptance_report.dart`;
  - `dart analyze tools\build_plum_confidence_gate_report.dart
    test\plum_confidence_gate_report_test.dart
    tools\build_plum_confidence_gate_acceptance_report.dart
    test\plum_confidence_gate_acceptance_report_test.dart`.

## 2026-06-28 PLUM Strong-Evidence Shape Diagnostic

- Added `tools/build_plum_evidence_shape_report.dart` and
  `test/plum_evidence_shape_report_test.dart`.
- Generated report:
  `docs/baselines/plum_evidence_shape.generated.md`.
- Scope:
  - validation-only PLUM strong-evidence neighborhood shape diagnostic;
  - frozen test is not evaluated;
  - production predicted intensity, UI, notifications and wording remain
    disconnected;
  - raw production intensity is not mutated.
- Baseline:
  - `max(JMA-style, PLUM r30/d0.50)`;
  - validation `shindo4` precision/recall/F1:
    `55.9% / 72.5% / 63.1%`;
  - validation `shindo4` false positives/false negatives: `3015 / 1453`.
- Shape candidates checked:
  - `shape_t4_min2_r30_margin0_5_spread0`;
  - `shape_t4_min2_r30_margin0_5_spread10`;
  - `shape_t4_min3_r30_margin0_5_spread10`;
  - `shape_t5_min2_r30_margin0_5_spread10`.
- Result:
  - all candidates reduce some `shindo4` false positives;
  - no candidate improves or preserves `shindo4` F1 versus baseline;
  - best false-positive reduction candidate, `shape_t4_min3_r30_margin0_5_spread10`,
    reduces `shindo4` false positives from 3015 to 2674, but recall falls from
    72.5% to 69.1% and F1 falls from 63.1% to 62.9%;
  - `recommendedForReplayValidation=null`.
- Decision:
  - reject this hard strong-evidence shape gate family for now;
  - do not run it on replay, frozen test, UI, notification or wording paths;
  - shape information may still be useful as a soft diagnostic feature, but not
    as a hard PLUM suppression rule.
- Next action:
  - move away from hard suppression gates;
  - investigate non-suppressive features such as per-region/site calibration,
    mask/evidence robustness scoring, or probability/confidence features that
    preserve raw predicted intensity.
- Validation:
  - `flutter test test\plum_evidence_shape_report_test.dart`;
  - `dart run tools\build_plum_evidence_shape_report.dart`;
  - `dart analyze tools\build_plum_evidence_shape_report.dart
    test\plum_evidence_shape_report_test.dart`.

## 2026-06-28 PLUM Evidence Robustness Diagnostic

- Added `tools/build_plum_evidence_robustness_report.dart` and
  `test/plum_evidence_robustness_report_test.dart`.
- Generated report:
  `docs/baselines/plum_evidence_robustness.generated.md`.
- Scope:
  - validation-only, non-suppressive evidence scoring;
  - frozen test is not evaluated;
  - raw predicted intensity is not replaced, capped, hidden or relabeled;
  - production UI, notifications and wording remain disconnected.
- Method:
  - baseline high-threshold signal is `max(JMA-style, PLUM r30/d0.50)`;
  - predicted-positive stations are stratified by:
    - mask rate;
    - retained station count;
    - PLUM evidence count;
    - nearest PLUM evidence distance;
    - branch agreement across JMA-style, `r20/d0.50`, and `r30/d0.75`;
    - combined robustness score.
- `shindo4` baseline:
  - precision/recall/F1: `55.9% / 72.5% / 63.1%`;
  - true/false positives: `3824 / 3015`.
- Key `shindo4` findings:
  - `maskRate` alone is not the discriminator: predicted-positive precision is
    `54.4% / 56.1% / 57.8%` for `20pct / 50pct / 80pct`;
  - low retained station count is a strong danger signal:
    `lt_8` precision `1.9%`, `08_15` precision `5.0%`, but sample sizes are
    small;
  - branch agreement is the strongest current signal:
    `agree_1` precision `29.9%`, `agree_2` precision `67.2%`,
    `agree_3` precision `83.2%`;
  - combined robustness score is also useful:
    `score_7` precision `82.6%`, `score_6` precision `67.6%`, while
    `score_4` and `score_5` remain poor at `35.4%` and `36.6%`.
- `shindo5-` findings:
  - branch agreement remains useful:
    `agree_1` precision `39.3%`, `agree_2` precision `67.0%`,
    `agree_3` precision `87.1%`;
  - high robustness scores remain higher precision:
    `score_7` precision `86.4%`, `score_6` precision `68.3%`.
- Decision:
  - this is the first non-suppressive feature family that clearly separates
    reliable and unreliable high-threshold predictions;
  - do not turn it into a hard gate yet;
  - use it to design a future confidence/calibration layer that preserves raw
    predicted intensity.
- Next action:
  - build a validation-only robustness-score calibration report that maps
    branch agreement and robustness score to threshold confidence buckets;
  - keep it separate from predicted intensity, UI, notification and wording
    until explicit wording-only acceptance criteria exist.
- Validation:
  - `flutter test test\plum_evidence_robustness_report_test.dart`;
  - `dart run tools\build_plum_evidence_robustness_report.dart`;
  - `dart analyze tools\build_plum_evidence_robustness_report.dart
    test\plum_evidence_robustness_report_test.dart`.

## 2026-06-28 PLUM Evidence Robustness Calibration Diagnostic

This follows up on the robustness stratification above with a joint
calibration table. The previous report only inspected **marginal** buckets
(one feature at a time); this one inspects **joint** buckets of
`branchAgreement` x `robustnessScore` and maps each non-empty bucket to an
empirical confidence band. It is still non-suppressive: it does not change,
cap, hide, or relabel the predicted intensity, and it must not feed
notifications or UI wording until explicit wording-only acceptance criteria
exist.

- Tool: `tools/build_plum_evidence_robustness_calibration_report.dart`.
- Test: `test/plum_evidence_robustness_calibration_report_test.dart`
  (asserts `rawPredictedIntensityMutated=false`, `frozenTestEvaluated=false`,
  `productionReady=false`, `diagnosticOnly=true`, and that every joint bucket
  carries a band label in `high|medium|low|insufficient`).
- Report: `docs/baselines/plum_evidence_robustness_calibration.generated.md`
  (185694 station forecasts, status `pass`).
- Policy: validation split only, frozen test not evaluated, production and UI
  not connected, raw predicted intensity field not mutated.

### Method

- Baseline raw signal is `max(JMA-style, PLUM r30/d0.50)` (same as the
  robustness stratification report and the confidence gate report).
- For each high-threshold predicted positive (`shindo4` >= 3.5,
  `shindo5-` >= 4.5), compute the joint key
  `(branchAgreement, robustnessScore)` where:
  - `branchAgreement = agree_{0..3}` counts how many of
    `{JMA-style, PLUM r20/d0.50, PLUM r30/d0.75}` cross the threshold;
  - `robustnessScore = score_{1..7}` sums four evidence-quality indicators
    (low mask rate, sufficient retained stations, multiple evidence stations,
    near evidence) plus the same three-branch agreement count.
- For each non-empty joint bucket, record predicted-positive count, true
  positives, false positives, and empirical precision. Assign a band:
  - `high` if precision >= 0.75 and sample >= 20;
  - `medium` if 0.55 <= precision < 0.75 and sample >= 20;
  - `low` if precision < 0.55 and sample >= 20;
  - `insufficient` if sample < 20 (band suppressed for low-sample cells).
- Bands are diagnostic labels, not thresholds; they do not modify the raw
  predicted intensity field.

### Findings

`shindo4` (baseline P/R/F1 = 55.9% / 72.5% / 63.1%):

| Band | Buckets | Pred+ | Precision |
| --- | ---: | ---: | ---: |
| `high` | 3 | 2635 | 82.2% |
| `medium` | 1 | 1156 | 62.5% |
| `low` | 5 | 2993 | 30.2% |
| `insufficient` | 6 | 55 | 60.0% |

- The three `high`-band cells are `agree_3/score_6` (87.3%),
  `agree_3/score_7` (82.6%), and `agree_2/score_5` (77.5%). Together they
  cover 2635 predicted positives at 82.2% precision, well above the 55.9%
  baseline.
- The `low`-band mass is dominated by `agree_1` rows:
  `agree_1/score_5` (25.3%), `agree_1/score_4` (33.9%),
  `agree_1/score_3` (49.7%), `agree_1/score_2` (54.4%), plus
  `agree_0/score_4` (47.2%). These 2993 predicted positives run at 30.2%
  precision and are exactly the cell where a future wording layer would
  attach a low-confidence label without suppressing the prediction.
- `agree_2/score_6` is the single `medium` band (62.5%, 1156 pred+): a
  transitional cell that branch agreement alone cannot isolate.

`shindo5-` (baseline P/R/F1 = 58.8% / 46.9% / 52.2%):

| Band | Buckets | Pred+ | Precision |
| --- | ---: | ---: | ---: |
| `high` | 1 | 44 | 86.4% |
| `medium` | 3 | 445 | 66.7% |
| `low` | 2 | 267 | 38.6% |
| `insufficient` | 5 | 25 | 84.0% |

- Only `agree_3/score_7` reaches the `high` band (86.4%, 44 pred+). The
  higher threshold naturally concentrates reliable predictions in the
  top-right corner of the joint table.
- The `medium` band is `agree_0/score_4` (60.9%), `agree_2/score_5`
  (65.5%), and `agree_2/score_6` (67.3%); `agree_2/score_6` is the largest
  medium cell (364 pred+).
- The `low` band is `agree_1/score_4` (48.9%) and `agree_1/score_5`
  (36.5%), again dominated by single-branch predictions.

### Decision

- This is the first joint calibration table that maps evidence conditions to
  empirical confidence for high-threshold PLUM-like predictions. It separates
  reliable from unreliable predictions more sharply than the marginal
  buckets in the stratification report: at `shindo4`, the `high` band
  reaches 82.2% precision versus 30.2% in the `low` band, both computed on
  the same validation split and the same raw predicted intensity.
- The calibration table is **not** a gate and **not** a suppression. It does
  not change the predicted intensity, does not block any prediction, and
  does not feed UI or notifications. Production remains blocked and the
  frozen test remains closed.
- Next action:
  - design explicit wording-only acceptance criteria (e.g. precision and
    coverage targets per band) before any future frozen evaluation of a
    wording layer that consumes this table;
  - keep the raw predicted intensity as the canonical prediction output;
    any future confidence label must be a separate field layered on top of
    this table, never a replacement or cap.
- Validation:
  - `flutter test test\plum_evidence_robustness_calibration_report_test.dart`;
  - `dart run tools\build_plum_evidence_robustness_calibration_report.dart`;
  - `dart analyze tools\build_plum_evidence_robustness_calibration_report.dart
    test\plum_evidence_robustness_calibration_report_test.dart`.

## 2026-06-28 PLUM Robustness Confidence-Band Wording-Only Acceptance Criteria

This section defines acceptance criteria for any future **wording-only**
confidence layer that consumes the joint calibration table above. It fills a
gap left by the existing acceptance docs:

- `plum_frozen_test_acceptance_criteria.generated.md` governs the **prediction
  itself** (operating-point P/R/F1, false-alarm reduction). It does not
  govern confidence bands.
- `source_confidence_wording_boundary.generated.md` governs the
  source-estimation card wording for `candidate_region_*` and
  `production_estimate_quality` signals. It does not govern PLUM confidence
  bands either, and it explicitly leaves official alert wording at `0`.
- This section governs the **confidence band** as a separate diagnostic
  field layered on top of the raw predicted intensity.

### Wording layer shape (specification, not yet implemented)

- A separate field `confidence_band` in `{high, medium, low, insufficient}`
  computed by looking up `(branchAgreement, robustnessScore)` in the joint
  calibration table.
- Raw predicted intensity remains the canonical prediction output. The band
  is layered on top and must never replace, cap, hide, or relabel the
  intensity.
- `insufficient`-sample buckets must render as `insufficient` and must never
  be displayed as `high`, `medium`, or `low` in any surface.

### Validation acceptance (must hold before any frozen evaluation of a wording layer)

These are gates the calibration table itself must pass on the validation
split before a wording layer consuming it may be evaluated on frozen test.

| ID | Criterion | shindo4 | shindo5- |
| --- | --- | --- | --- |
| C1 | Band monotonicity: `P(high) > P(medium) > P(low)` | 82.2 > 62.5 > 30.2 pass | 86.4 > 66.7 > 38.6 pass |
| C2 | High band precision floor: `P(high) >= 0.75` | 82.2% pass | 86.4% pass |
| C3 | Low band isolation: `P(low) <= P(baseline) - 0.10` | 30.2% <= 45.9% pass | 38.6% <= 48.8% pass |
| C4 | High band coverage floor: `share(high) >= 15%` of predicted positives | 38.5% pass | 5.6% **fail** |

Current validation status (snapshot 2026-06-28, 185694 station forecasts):

- `shindo4`: passes C1-C4. A wording layer at `shindo4` is **eligible for
  frozen evaluation**.
- `shindo5-`: passes C1-C3 but **fails C4**. The `high` band covers only
  44 predicted positives (5.6%), which is too narrow to support a
  high-confidence wording label. A `shindo5-` wording layer must NOT proceed
  to frozen evaluation until the high band gains coverage (e.g. by adding
  features, relaxing the high-band precision threshold with explicit
  justification, or accumulating more validation mass).

### Frozen-test acceptance (must hold before any UI wording connection)

When a wording layer that passes validation acceptance is evaluated on the
frozen test, it must additionally satisfy:

| ID | Criterion |
| --- | --- |
| F1 | Band monotonicity preserved on frozen test: `P(high) > P(medium) > P(low)` |
| F2 | High band precision hold: `frozen P(high) >= validation P(high) - 0.05` |
| F3 | No band collapse: `frozen P(band) >= validation P(band) - 0.15` for each band |
| F4 | Coverage hold: `frozen share(high+medium) >= 0.5 * validation share(high+medium)` |

F1-F3 are correctness gates (precision ranking and floors must survive
distribution shift). F4 is a usefulness gate (the bands must still cover
meaningful mass on frozen test). Failure of any F-criterion blocks UI
wording connection and returns the wording layer to validation-only.

### Boundary (explicit prohibitions)

- The confidence band field must not modify, cap, hide, or relabel the raw
  predicted intensity.
- The confidence band must not feed EEW, push, or voice alert wording until
  a separate alert-wording acceptance track exists; the existing
  `source_confidence_wording_boundary` matrix leaves official alert wording
  at `0` and this changes nothing there.
- `insufficient` band must not be rendered as `high`/`medium`/`low` in any
  UI surface, including debug surfaces.
- On the source-estimation diagnostic card, the confidence band may appear
  as a quality line only, consistent with the existing
  `production_estimate_quality` row of the wording boundary matrix. It must
  not appear as an official alert, a coordinate correction, or a final
  hypocenter wording.

### Decision

- `shindo4` wording layer: **validation-eligible**, may proceed to a
  one-time frozen evaluation once the frozen test is opened. Not yet
  authorized for production UI.
- `shindo5-` wording layer: **blocked at validation** on C4 coverage. Do
  not frozen-evaluate until high-band coverage crosses 15%.
- Production UI connection for any confidence-band wording remains blocked
  until F1-F4 pass on frozen test.
- Next action:
  - open a one-time frozen evaluation for the `shindo4` confidence-band
    wording layer only, reusing the frozen split already used by the PLUM
    frozen-test acceptance track;
  - for `shindo5-`, investigate high-band coverage gain (feature additions
    or threshold review) on validation only, before any frozen attempt.

## 2026-06-28 PLUM Confidence-Band One-Shot Frozen Evaluation (shindo4)

This section records the single one-shot frozen evaluation of the `shindo4`
confidence-band wording layer. The frozen test split is the 2022 annual
events (`jma_final_intensity_2022.json`) built into a synthetic-reveal test
dataset by `SyntheticRevealDatasetBuilder`, the same split used by the PLUM
operating-point frozen-test evaluation. Band labels are looked up from the
validation calibration table only; they are not recomputed on test. F1-F4
were pre-registered in the acceptance section above and were not tuned after
seeing frozen results.

- Tool: `tools/build_plum_confidence_band_frozen_evaluation_report.dart`.
- Test: `test/plum_confidence_band_frozen_evaluation_report_test.dart`
  (asserts one-shot, non-suppressive policy, and F1-F4 check keys present).
- Report: `docs/baselines/plum_confidence_band_frozen_evaluation.generated.md`
  (179844 frozen station forecasts, 6288 predicted positives).
- Policy: split `test`, `frozenTestEvaluated=true`, `oneShot=true`,
  `productionUiConnected=false`, `rawPredictedIntensityMutated=false`,
  `diagnosticOnly=true`.

### Frozen Results (shindo4)

Validation reference (from the calibration report):

| Band | Validation precision | Validation pred+ |
| --- | ---: | ---: |
| `high` | 82.2% | 2635 |
| `medium` | 62.5% | 1156 |
| `low` | 30.2% | 2993 |
| `insufficient` | 60.0% | 55 |

Frozen test (baseline P/R = 38.0% / 57.2%, versus validation 55.9% / 72.5%):

| Band | Frozen pred+ | Frozen TP | Frozen FP | Frozen precision | Δ vs validation |
| --- | ---: | ---: | ---: | ---: | ---: |
| `high` | 782 | 425 | 357 | 54.3% | -27.9 pp |
| `medium` | 2605 | 1110 | 1495 | 42.6% | -19.9 pp |
| `low` | 2795 | 809 | 1986 | 28.9% | -1.3 pp |
| `insufficient` | 106 | 45 | 61 | 42.5% | -17.5 pp |

Criteria checks:

| Check | Status | Actual | Required |
| --- | --- | --- | --- |
| `F1_band_monotonicity` | `pass` | 54.3 > 42.6 > 28.9 | P(high) > P(medium) > P(low) |
| `F2_high_precision_hold` | `fail` | 54.3% | >= 77.2% (82.2% - 5%) |
| `F3_no_collapse_high` | `fail` | 54.3% | >= 67.2% (82.2% - 15%) |
| `F3_no_collapse_medium` | `fail` | 42.6% | >= 47.5% (62.5% - 15%) |
| `F3_no_collapse_low` | `pass` | 28.9% | >= 15.2% (30.2% - 15%) |
| `F4_coverage_hold` | `pass` | 53.9% | >= 27.7% (50% * 55.4%) |

### Decision

- Outcome: `fail`. The shindo4 confidence-band wording layer is **blocked
  from production UI connection**. It remains a validation-only diagnostic.
- The band **ordering is preserved** on frozen test (F1 passes: high >
  medium > low), so the relative ranking of evidence conditions is still
  informative. But the **absolute precision levels do not transfer**: the
  high band collapses 27.9 pp and the medium band 19.9 pp, both exceeding
  the 15 pp collapse tolerance. Only the low band is stable (-1.3 pp).
- This is consistent with the raw intensity baseline itself dropping 17.9 pp
  on frozen test (55.9% -> 38.0%): the 2022 test distribution is harder, and
  the validation-calibrated high/medium bands were partly riding
  validation-specific patterns that do not generalize. The low band (dominated
  by `agree_1` single-branch predictions) is stable because it identifies a
  genuinely unreliable pattern that transfers.
- The one-shot frozen evaluation is now spent for the shindo4 confidence-band
  wording layer. It must not be re-run after tuning the calibration table or
  the F-criteria; any future frozen attempt requires a new pre-registered
  acceptance track.
- Next action:
  - keep the confidence band as a validation-only diagnostic; do not connect
    UI wording, notifications, or alert copy;
  - the underlying blocker is the raw intensity prediction's frozen-test
    regression (P3 static attenuation + PLUM r30/d0.50), not the band
    calibration itself; prioritize improving raw intensity transfer before
    re-attempting any confidence-band wording layer;
  - for `shindo5-`, the validation C4 coverage block remains; no frozen
    attempt is warranted.
- Validation:
  - `flutter test test\plum_confidence_band_frozen_evaluation_report_test.dart`;
  - `dart run tools\build_plum_confidence_band_frozen_evaluation_report.dart`;
  - `dart analyze tools\build_plum_confidence_band_frozen_evaluation_report.dart
    test\plum_confidence_band_frozen_evaluation_report_test.dart`.

## 2026-06-28 PLUM Region/Site Calibration Diagnostic

This is the last of the four validation-only guard candidates listed in the
frozen regression drilldown (the other three — local-contrast guard,
strong-evidence shape guard, and mask/evidence robustness calibration — were
already built and either rejected or frozen-failed). It tests whether
**geographic** features (estimated-source latitude band as region, station
latitude band as a coarse site-amplification proxy) can separate reliable
from unreliable high-threshold predictions. It is still non-suppressive: it
does not change, cap, hide, or relabel the predicted intensity, and it must
not feed notifications or UI wording.

- Tool: `tools/build_plum_region_site_calibration_report.dart`.
- Test: `test/plum_region_site_calibration_report_test.dart`
  (asserts `rawPredictedIntensityMutated=false`, `frozenTestEvaluated=false`,
  `productionReady=false`, `diagnosticOnly=true`, and that every joint bucket
  carries a band label in `high|medium|low|insufficient`).
- Report: `docs/baselines/plum_region_site_calibration.generated.md`
  (185694 station forecasts, status `pass`).
- Policy: validation split only, frozen test not evaluated, production and UI
  not connected, raw predicted intensity field not mutated.

### Method

- Baseline raw signal is `max(JMA-style, PLUM r30/d0.50)` (same as the
  robustness calibration report and the confidence gate report).
- `region` is the latitude band of the **estimated** source
  (`StaticIntensityLocator.locate(retained)`), not the truth latitude, so the
  bucket is production-available. Bands: `hokkaido` (lat >= 41), `tohoku`
  (37.5 <= lat < 41), `kanto_chubu` (34.5 <= lat < 37.5), `west_south`
  (lat < 34.5). These match `_eventLatitudeBucket` in the frozen regression
  diagnostic so the two reports can be read against each other.
- `site` is the latitude band of the **station**, using the same band
  boundaries. This is a coarse site-amplification proxy (station latitude
  stands in for geographic/geological location).
- For each non-empty `region x site` joint bucket, record predicted-positive
  count, true positives, false positives, and empirical precision. Assign a
  band using the same thresholds as the evidence robustness calibration
  (`high` >= 0.75, `medium` >= 0.55, `low` < 0.55, `insufficient` if sample
  < 20) so the two calibration tables are directly comparable.
- Bands are diagnostic labels, not thresholds; they do not modify the raw
  predicted intensity field.

### Findings

`shindo4` (baseline P/R/F1 = 55.9% / 72.5% / 63.1%):

| Band | Buckets | Pred+ | Precision |
| --- | ---: | ---: | ---: |
| `high` | 0 | 0 | - |
| `medium` | 1 | 1698 | 65.7% |
| `low` | 4 | 5140 | 52.7% |
| `insufficient` | 1 | 1 | 100.0% |

- The single `medium` cell is `tohoku x kanto_chubu` (65.7%, 1698 pred+):
  estimated source in Tohoku, station in Kanto/Chubu. This is the only
  cross-region combination with enough mass and meaningful precision lift.
- All same-region cells land in `low`: `kanto_chubu x kanto_chubu` 53.5%
  (1676 pred+), `tohoku x tohoku` 54.9% (3223 pred+), `west_south x
  west_south` 21.8% (193 pred+), `hokkaido x hokkaido` 2.1% (48 pred+).
- `hokkaido x hokkaido` at 2.1% precision is almost entirely false alarms
  (47 FP / 1 TP). Hokkaido station sparsity likely distorts PLUM propagation;
  this is a candidate for region-specific handling in any future model
  revision.

`shindo5-` (baseline P/R/F1 = 58.8% / 46.9% / 52.2%):

| Band | Buckets | Pred+ | Precision |
| --- | ---: | ---: | ---: |
| `high` | 1 | 126 | 79.4% |
| `medium` | 1 | 447 | 72.0% |
| `low` | 1 | 205 | 18.0% |
| `insufficient` | 1 | 3 | 0.0% |

- The single `high` cell is `tohoku x kanto_chubu` (79.4%, 126 pred+). The
  higher threshold concentrates reliable predictions into the same
  cross-region cell that was `medium` at `shindo4`.
- `kanto_chubu x kanto_chubu` drops to 18.0% at `shindo5-`, well below the
  53.5% at `shindo4`: same-region Kanto/Chubu predictions are much less
  reliable at the higher threshold.

### Comparison with evidence robustness calibration

| Calibration | shindo4 high P | shindo4 low P | spread |
| --- | ---: | ---: | ---: |
| evidence robustness (branchAgreement x robustnessScore) | 82.2% | 30.2% | 52.0 pp |
| region/site (region x site) | none | 52.7% | 13.0 pp (medium vs low) |

- The evidence robustness calibration separates high-threshold predictions
  far more sharply (52.0 pp spread vs 13.0 pp). `branchAgreement` and
  `robustnessScore` carry more discriminative signal than geographic
  latitude bands.
- The region/site table still adds information the robustness table does
  not: it localises the geographic weak spots. `kanto_chubu` region at
  53.5% validation precision is the same bucket that dropped 46.0 pp in F1
  on the frozen test (`eventLatitudeBand=kanto_chubu` in the frozen
  regression diagnostic). The frozen regression was therefore visible as a
  validation-precision deficit in the region/site table, even though the
  robustness table did not flag it.

### Decision

- This completes the fourth and final validation-only guard candidate from
  the frozen regression drilldown. None of the four (local-contrast,
  strong-evidence shape, mask/evidence robustness, region/site) produced a
  production-ready wording layer: the first two were rejected on replay,
  the robustness calibration failed its one-shot frozen evaluation, and the
  region/site calibration has no `high` band at `shindo4` and a very narrow
  `high` band at `shindo5-` (126 pred+).
- The region/site table is **not** a gate and **not** a suppression. It
  does not change the predicted intensity, does not block any prediction,
  and does not feed UI or notifications. Production remains blocked and the
  frozen test for any confidence-band wording layer remains spent.
- Next action:
  - keep the region/site table as a validation-only geographic diagnostic;
    do not connect UI wording, notifications, or alert copy;
  - the `kanto_chubu` validation-precision deficit (53.5% at `shindo4`,
    18.0% at `shindo5-`) and the near-zero `hokkaido` precision (2.1%) are
    inputs for a future raw-intensity model-family revision, not for a
    wording layer;
  - the underlying blocker remains the raw intensity prediction's frozen-
    test regression (P3 static attenuation + PLUM r30/d0.50); improving
    raw intensity transfer is the prerequisite before re-attempting any
    confidence-band wording layer.
- Validation:
  - `flutter test test\plum_region_site_calibration_report_test.dart`;
  - `dart run tools\build_plum_region_site_calibration_report.dart`;
  - `dart analyze tools\build_plum_region_site_calibration_report.dart
    test\plum_region_site_calibration_report_test.dart`.

## 2026-06-28 Raw Intensity Frozen Source Diagnostic

This is the prerequisite diagnostic for improving raw intensity frozen
migration (the underlying blocker flagged by the confidence band frozen
evaluation and the region/site calibration). It decomposes the baseline
(`max(JMA-style, PLUM r30/d0.50)`) frozen-test precision drop into the
contributions of the two component predictors, so that future model-family
revisions can target the right component. It is non-suppressive: it does not
modify raw predicted intensity, does not connect to UI/wording, and does not
tune any parameter.

- Tool: `tools/build_raw_intensity_frozen_source_diagnostic_report.dart`.
- Test: `test/raw_intensity_frozen_source_diagnostic_report_test.dart`
  (8-minute timeout, real data; asserts the non-suppressive policy, the
  three-component x two-split structure, and the FP trigger-source
  decomposition).
- Report: `docs/baselines/raw_intensity_frozen_source_diagnostic.generated.md`
  (validation 185694 + test 179844 station forecasts, status `pass`).
- Policy: `rawPredictedIntensityMutated=false`, `frozenTestEvaluated=true`
  (diagnostic only, not a wording-layer evaluation), `productionReady=false`,
  `productionUiConnected=false`, `diagnosticOnly=true`, `parametersTuned=
  false`.
- One-shot compliance: this diagnostic does not touch the confidence band
  wording layer, does not tune parameters, and does not re-run the
  confidence band frozen evaluation. It only decomposes raw intensity
  performance on the frozen test split.

### Method

- Reuses `SyntheticRevealDatasetBuilder(generatedSplits: ['validation',
  'test'])` to build both splits, and reuses `StaticIntensityLocator`,
  `JmaStyleIntensityPredictor`, `PlumLikeIntensityPredictor(r=30km,
  d=0.50/km)` exactly as the frozen evaluation tool does.
- `baseline = max(JMA-style, PLUM r30/d0.50)`. For each high-threshold
  prediction, records TP/FP/FN/TN for all three components (`jmaStyle`,
  `plumR30D050`, `baselineMax`) on both splits.
- Region bucket uses the **estimated** source latitude (production-available,
  same `_eventLatitudeBucket` bands as the frozen regression diagnostic);
  distance bucket uses estimated-source -> station haversine distance (same
  `_distanceBucket` bands). The frozen regression diagnostic uses
  `station.surfaceDistanceKm` (truth -> station), but `StaticIntensityStation`
  does not expose that field, so this tool uses estimate -> station for
  consistency with the region bucket (both based on the production-available
  estimate, not truth).
- FP trigger source: each baseline FP is classified as `jma_only`
  (JMA >= threshold, PLUM < threshold), `plum_only` (PLUM >= threshold,
  JMA < threshold), or `both` (both >= threshold). Since `baseline = max`,
  a baseline FP always has at least one component crossing, so `neither` is
  impossible.
- `precisionDelta = testPrecision - validationPrecision` per component;
  `largestDropComponent` is the component with the most negative delta.

### Findings

`shindo4` three-component P/R/F1 (validation vs test):

| Component | Split | Precision | Recall | F1 |
| --- | --- | ---: | ---: | ---: |
| `jmaStyle` | validation | 56.5% | 51.0% | 53.6% |
| `plumR30D050` | validation | 69.7% | 62.8% | 66.1% |
| `baselineMax` | validation | 55.9% | 72.5% | 63.1% |
| `jmaStyle` | test | 27.7% | 9.3% | 14.0% |
| `plumR30D050` | test | 43.0% | 54.3% | 48.0% |
| `baselineMax` | test | 38.0% | 57.2% | 45.7% |

`shindo4` precision delta (test - validation):

| Component | Validation P | Test P | Delta |
| --- | ---: | ---: | ---: |
| `jmaStyle` | 56.5% | 27.7% | **-28.7% (largest drop)** |
| `plumR30D050` | 69.7% | 43.0% | -26.7% |
| `baselineMax` | 55.9% | 38.0% | -17.9% |

- The baseline drop (-17.9pp) is smaller than either component drop because
  the `max` combination spreads FPs and partially offsets the regression.
- `jmaStyle` is the largest-drop component at `shindo4` (-28.7pp). JMA-style
  attenuation generalises worse from validation to test than PLUM r30/d0.50
  does on precision, and its recall also collapses (51.0% -> 9.3%).

`shindo4` region buckets (precision by estimated-source latitude):

| Region | Split | jmaStyle P | plumR30D050 P | baselineMax P |
| --- | --- | ---: | ---: | ---: |
| `kanto_chubu` | validation | 49.0% | 65.1% | 53.5% |
| `kanto_chubu` | test | 3.6% | 26.6% | 11.8% |

- `kanto_chubu` is the geographic hot spot: `jmaStyle` drops -45.4pp (49.0%
  -> 3.6%), the worst component-region regression. `plumR30D050` drops
  -38.5pp (65.1% -> 26.6%). The baseline drops -41.7pp (53.5% -> 11.8%),
  consistent with the -46.0pp F1 drop on `kanto_chubu` flagged by the frozen
  regression diagnostic. The source diagnostic now attributes the bulk of
  that drop to the JMA-style attenuation branch in `kanto_chubu`.

`shindo4` FP trigger source (baseline FP decomposition):

| Split | jma_only | plum_only | both |
| --- | ---: | ---: | ---: |
| validation | 1572 | 940 | 503 |
| test | 894 | 2886 | 119 |

- On test, baseline FPs are dominated by `plum_only` (2886/3899 = 74%),
  versus 31% on validation. PLUM r30/d0.50 crosses the threshold alone far
  more often on test, meaning PLUM's specificity regresses harder than
  JMA's. `both` drops from 503 to 119, consistent with JMA's recall collapse
  on test (JMA crosses the threshold far less often).

`shindo5-` three-component P/R/F1 (validation vs test):

| Component | Split | Precision | Recall | F1 |
| --- | --- | ---: | ---: | ---: |
| `jmaStyle` | validation | 87.8% | 8.1% | 14.8% |
| `plumR30D050` | validation | 58.1% | 45.5% | 51.0% |
| `baselineMax` | validation | 58.8% | 46.9% | 52.2% |
| `jmaStyle` | test | 0.0% | 0.0% | 0.0% |
| `plumR30D050` | test | 26.5% | 38.1% | 31.3% |
| `baselineMax` | test | 26.5% | 38.1% | 31.3% |

- `jmaStyle` on test has only 2 predicted positives (0 TP / 2 FP), so the
  -87.8% delta is a small-sample artefact. The real signal is that JMA-style
  attenuation systematically under-predicts at `shindo5-` magnitude on test
  (recall 0%), so the baseline at `shindo5-` is effectively PLUM-only on
  test.
- `shindo5-` baseline FPs on test are 99.6% `plum_only` (913/915), confirming
  that the `shindo5-` specificity problem is entirely a PLUM r30/d0.50
  over-prediction problem on test.

### Decision

- This diagnostic is non-suppressive and does not authorise production UI,
  notifications, or wording. It does not tune any parameter and does not
  re-run the confidence band wording-layer frozen evaluation.
- Next action:
  - the `kanto_chubu` regression is driven primarily by the JMA-style
    attenuation branch (`jmaStyle` -45.4pp); a future raw-intensity
    model-family revision should prioritise JMA-style attenuation
    generalisation in `kanto_chubu` before re-attempting any
    confidence-band wording layer;
  - the `shindo4` and `shindo5-` FP excess on test is dominated by
    `plum_only` triggers (74% and 99.6%); PLUM r30/d0.50 specificity on
    test is the second priority for raw-intensity revision;
  - JMA-style recall collapse on test (`shindo4` 51.0% -> 9.3%) is a
    separate problem from precision and must be addressed before JMA-style
    can serve as a high-recall branch of the baseline;
  - all calibration tables (evidence robustness, region/site, source
    decomposition) remain validation-only diagnostics; none of them feed
    UI/wording.
- Validation:
  - `flutter test test\raw_intensity_frozen_source_diagnostic_report_test.dart`;
  - `dart run tools\build_raw_intensity_frozen_source_diagnostic_report.dart`;
  - `dart analyze tools\build_raw_intensity_frozen_source_diagnostic_report.dart
    test\raw_intensity_frozen_source_diagnostic_report_test.dart`.

## 2026-06-28 JMA-Style Kanto/Chubu Attenuation Diagnostic

This follows the raw-intensity source diagnostic. The previous report showed
that the `kanto_chubu` regression is driven strongly by the JMA-style branch
(`jmaStyle` precision 49.0% -> 3.6% at `shindo4`). This drilldown keeps the
same non-suppressive boundary and asks whether the regression is mostly a
source-location problem or a JMA-style attenuation/sample-transfer problem.

- Tool:
  `tools/build_jma_style_kanto_chubu_attenuation_diagnostic_report.dart`.
- Test:
  `test/jma_style_kanto_chubu_attenuation_diagnostic_report_test.dart`
  (8-minute timeout, real data; asserts non-production policy, validation/test
  structure, estimated-source vs oracle-source branches, and bucket schemas).
- Report:
  `docs/baselines/jma_style_kanto_chubu_attenuation_diagnostic.generated.md`
  (validation 1067 variants / 84634 station forecasts; test 978 variants /
  88879 station forecasts; status `pass`).
- Policy: `rawPredictedIntensityMutated=false`, `frozenTestEvaluated=true`
  (diagnostic only), `productionReady=false`, `productionUiConnected=false`,
  `diagnosticOnly=true`, `parametersTuned=false`.
- Target sample: synthetic-reveal variants whose **estimated-source**
  latitude is in `kanto_chubu` (`34.5 <= lat < 37.5`).
- Branch comparison:
  - `estimatedSourceJma`: JMA-style PGV attenuation using the
    `StaticIntensityLocator` estimate;
  - `oracleSourceJma`: the same formula using the catalog source and depth;
  - bucket tables use `estimatedSourceJma` and split by source error,
    estimate-to-station distance, estimated depth, magnitude, and ARV
    amplification.

### Findings

`shindo4` estimated vs oracle source:

| Split | Branch | Precision | Recall | F1 | FP | FN |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| validation | `estimatedSourceJma` | 49.0% | 25.7% | 33.7% | 324 | 901 |
| validation | `oracleSourceJma` | 92.3% | 11.9% | 21.1% | 12 | 1068 |
| test | `estimatedSourceJma` | 3.6% | 4.7% | 4.1% | 508 | 384 |
| test | `oracleSourceJma` | 28.6% | 3.0% | 5.4% | 30 | 391 |

- Using catalog/oracle source removes many false positives, but it does **not**
  restore frozen precision: `oracleSourceJma` still drops from 92.3% to 28.6%
  (`-63.7pp`). This means the blocker is not only source-location error; the
  JMA-style attenuation branch itself is not transferring across splits in
  `kanto_chubu`.
- `estimatedSourceJma` false positives on test concentrate in the worst
  source-error bucket: `gt_200km` has 502 FP and only 3 TP at `shindo4`
  (0.6% precision). Large source errors still matter, but the oracle-source
  result shows they are not the whole explanation.
- The near-distance test buckets also collapse: `030_060km` precision drops
  to 2.7%, and `060_100km` to 0.7%. This points at threshold crossing and
  attenuation shape around local/near-field stations, not just far-field
  extrapolation.
- The `gte_m5` magnitude bucket is where all `shindo4` positives are coming
  from in this target region. Validation precision is 49.0%; test precision is
  3.6%, with 508 FP. Future model-family revision should inspect M5-class
  `kanto_chubu` samples first.
- ARV is not the primary missing-data issue: `default_arv` has only 27
  validation and 3 test station forecasts. The FP mass sits in `gte_1_2`
  amplification, not in unmapped/default sites.

`shindo5-` result:

- JMA-style produces no positive predictions on either split in this
  `kanto_chubu` drilldown (`0 TP / 0 FP` for estimated source). This matches
  the previous source diagnostic conclusion that `shindo5-` test behavior is
  effectively PLUM-only and should not be solved by this JMA-style drilldown.

### Decision

- This report stays diagnostic-only. It does not authorize production
  intensity, UI, wording, notification, or coordinate changes.
- Next action:
  - do not spend more effort on confidence-band wording until raw intensity
    transfer improves;
  - for JMA-style, inspect/revise the attenuation family on `kanto_chubu`
    M5-class local/near-field samples, with special attention to source-error
    `gt_200km` cases and near-distance `030_060km` / `060_100km` threshold
    crossings;
  - separately continue the PLUM r30/d0.50 specificity line, because
    `shindo4`/`shindo5-` baseline false positives on frozen test are still
    dominated by PLUM-only triggers.
- Validation:
  - `dart analyze tools\build_jma_style_kanto_chubu_attenuation_diagnostic_report.dart
    test\jma_style_kanto_chubu_attenuation_diagnostic_report_test.dart`;
  - `flutter test test\jma_style_kanto_chubu_attenuation_diagnostic_report_test.dart`;
  - `dart run tools\build_jma_style_kanto_chubu_attenuation_diagnostic_report.dart`.

## 2026-06-28 PLUM Specificity Frozen Diagnostic

This follows the raw-intensity source diagnostic and the JMA-style
`kanto_chubu` drilldown. The raw source report showed that frozen-test
baseline false positives are dominated by PLUM-only triggers (`shindo4`:
2886/3899, `shindo5-`: 913/915). This diagnostic isolates
`PLUM r30/d0.50` specificity before any radius/damping or product behavior is
changed.

- Spec:
  `.trae/specs/plum-specificity-frozen-diagnostic/spec.md`,
  `tasks.md`, `checklist.md`.
- Tool: `tools/build_plum_specificity_frozen_diagnostic_report.dart`.
- Test: `test/plum_specificity_frozen_diagnostic_report_test.dart`
  (8-minute timeout, real data; asserts non-production policy, split
  structure, specificity metrics, PLUM-only FP, and bucket schemas).
- Report: `docs/baselines/plum_specificity_frozen_diagnostic.generated.md`
  (validation 2688 variants / 185694 station forecasts; test 2757 variants /
  179844 station forecasts; status `pass`).
- Policy: `rawPredictedIntensityMutated=false`, `frozenTestEvaluated=true`,
  `productionReady=false`, `productionUiConnected=false`,
  `diagnosticOnly=true`, `parametersTuned=false`.
- PLUM config is fixed to the existing frozen candidate:
  `radiusKm=30`, `dampingPer10Km=0.50`.
- Buckets:
  - estimated-source region;
  - estimated-source -> station distance;
  - mask rate;
  - PLUM evidence count;
  - nearest evidence distance;
  - strongest evidence intensity;
  - prediction margin above threshold.

### Findings

Overall PLUM r30/d0.50:

| Threshold | Split | Precision | Recall | Specificity | FP | PLUM-only FP |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `shindo4` | validation | 69.7% | 62.8% | 99.2% | 1443 | 940 |
| `shindo4` | test | 43.0% | 54.3% | 98.3% | 3005 | 2886 |
| `shindo5-` | validation | 58.1% | 45.5% | 99.8% | 321 | 311 |
| `shindo5-` | test | 26.5% | 38.1% | 99.5% | 913 | 913 |

- Specificity changes look numerically small because the negative class is
  huge (`shindo4` 99.2% -> 98.3%), but FP count more than doubles
  (1443 -> 3005), which is the operational problem.
- `shindo4` precision drops -26.7pp, and `shindo5-` precision drops -31.5pp.

`shindo4` region buckets:

| Region | Split | Precision | FP | PLUM-only FP |
| --- | --- | ---: | ---: | ---: |
| `tohoku` | validation | 72.9% | 887 | 412 |
| `tohoku` | test | 40.7% | 2565 | 2496 |
| `kanto_chubu` | validation | 65.1% | 480 | 456 |
| `kanto_chubu` | test | 26.6% | 270 | 267 |

- PLUM specificity failure is **not** the same hotspot as the JMA-style
  `kanto_chubu` attenuation failure. The PLUM shindo4 FP mass is dominated by
  `tohoku` on the frozen test (2565 FP, 2496 PLUM-only FP).
- `kanto_chubu` still degrades, but it is not the main PLUM FP source.

`shindo4` evidence/distance shape:

- Evidence count `gte_8` dominates FP:
  validation 1323 FP / 871 PLUM-only FP; test 2824 FP / 2723 PLUM-only FP.
  More local evidence does not guarantee correctness; dense evidence can
  propagate a broad false-positive field.
- Nearest evidence distance `000_010km` dominates FP:
  validation 1314 FP / 874 PLUM-only FP; test 2573 FP / 2474 PLUM-only FP.
  The issue is not lack of nearby evidence; it is propagation from strong
  nearby evidence into stations whose final intensity stays below threshold.
- Estimated-source distance buckets show the frozen FP mass spread into
  middle/far ranges:
  `060_100km` has 560 FP, `100_200km` has 826 FP, and `gt_200km` has 840 FP
  on test.
- Prediction margin shows this is not only near-threshold noise. At `shindo4`,
  test FP in the `gte_100` margin bucket rise to 663 (validation 92), so many
  wrong positives are more than 1.0 shindo above threshold.

`shindo5-`:

- The PLUM specificity failure is even more concentrated:
  `tohoku` test has 863 FP / 863 PLUM-only FP.
- Evidence count `gte_8` has 887 FP / 887 PLUM-only FP.
- Nearest evidence distance `000_010km` has 842 FP / 842 PLUM-only FP.
- This confirms that `shindo5-` frozen behavior is effectively PLUM-only and
  controlled by strong nearby evidence propagation.

### Decision

- This report is diagnostic-only. It does not authorize production intensity,
  UI, wording, notification, or parameter changes.
- Next action:
  - do **not** use a simple evidence-count confidence rule: the worst FP bucket
    is `evidenceCount=gte_8`;
  - investigate a non-suppressive PLUM propagation-shape diagnostic for
    `tohoku`, especially strong-nearby-evidence cases whose propagation margin
    is `>=1.0` shindo;
  - if a future operational change is considered, compare damping/radius only
    through validation-first specs and do not reuse the spent confidence-band
    frozen wording path.
- Validation:
  - `dart analyze tools\build_plum_specificity_frozen_diagnostic_report.dart
    test\plum_specificity_frozen_diagnostic_report_test.dart`;
  - `flutter test test\plum_specificity_frozen_diagnostic_report_test.dart`;
  - `dart run tools\build_plum_specificity_frozen_diagnostic_report.dart`.

## 2026-06-28 PLUM Tohoku Propagation-Shape Diagnostic

This follows the PLUM specificity frozen diagnostic. That report showed the
frozen-test PLUM false-positive mass is dominated by `tohoku`, especially
`evidenceCount=gte_8`, `nearestEvidence=000_010km`, and high prediction margin
cases. This drilldown asks whether those cases can be separated by
propagation-shape rather than by simple evidence count.

- Spec:
  `.trae/specs/plum-tohoku-propagation-shape-diagnostic/spec.md`,
  `tasks.md`, `checklist.md`.
- Tool:
  `tools/build_plum_tohoku_propagation_shape_diagnostic_report.dart`.
- Test:
  `test/plum_tohoku_propagation_shape_diagnostic_report_test.dart`
  (8-minute timeout, real data; asserts non-production policy, focus filter,
  threshold/split structure, feature aggregates, and markdown sections).
- Report:
  `docs/baselines/plum_tohoku_propagation_shape_diagnostic.generated.md`
  (validation 2688 variants / 185694 station forecasts; test 2757 variants /
  179844 station forecasts; status `pass`).
- Policy:
  `rawPredictedIntensityMutated=false`, `frozenTestEvaluated=true`,
  `productionReady=false`, `productionUiConnected=false`,
  `diagnosticOnly=true`, `parametersTuned=false`,
  `suppressionApplied=false`.
- Focus subset:
  estimated-source region `tohoku`, evidence count `>=8`, nearest evidence
  distance `<10 km`, prediction margin `>=1.0` shindo.

### Findings

`shindo4` focus subset:

| Split | Samples | TP | FP | Precision | PLUM-only FP |
| --- | ---: | ---: | ---: | ---: | ---: |
| validation | 457 | 389 | 68 | 85.1% | 0 |
| test | 1051 | 458 | 593 | 43.6% | 549 |

`shindo5-` focus subset:

| Split | Samples | TP | FP | Precision | PLUM-only FP |
| --- | ---: | ---: | ---: | ---: | ---: |
| validation | 28 | 26 | 2 | 92.9% | 0 |
| test | 40 | 10 | 30 | 25.0% | 30 |

- The frozen-test hotspot is real and concentrated: after applying the focus
  filter, precision still collapses from 85.1% to 43.6% at `shindo4` and from
  92.9% to 25.0% at `shindo5-`.
- A simple "strong evidence geometry" hard gate does **not** look promising.
  In the test split, TP and FP have very similar production-available support
  geometry:
  - `shindo4` supporting-evidence count: TP `12.88`, FP `12.83`;
  - quadrant coverage: TP `2.28`, FP `2.31`;
  - centroid offset: TP `10.53 km`, FP `10.24 km`;
  - max spread: TP `28.15 km`, FP `28.43 km`.
- What separates TP and FP much more strongly is the diagnostic-only target
  outcome itself:
  - `shindo4` actual intensity: TP `4.67`, FP `1.66`;
  - evidence-target gap: TP `0.85`, FP `3.84`;
  - `shindo5-` actual intensity: TP `5.54`, FP `2.21`;
  - evidence-target gap: TP `0.46`, FP `3.79`.
- The local actual neighborhood also stays weak for many false positives, but
  this is an offline diagnostic feature, not a direct production signal.
- Therefore the next step should favor non-suppressive robustness scoring or
  region/site calibration, not a new hard propagation-shape gate.

### Decision

- Keep this line diagnostic-only.
- Do not tune PLUM radius/damping from this report.
- Do not add a suppression gate based only on evidence count, quadrant
  coverage, centroid offset, or spread.
- Use this report to inform the next calibration stage:
  non-suppressive robustness scoring for `tohoku` strong-nearby-evidence
  cases, or region/site calibration refinement.

## 2026-06-28 PLUM Tohoku Focus Robustness Frozen Diagnostic

This follows the propagation-shape drilldown. The question here is narrower:
inside the `tohoku` strong-nearby-evidence hotspot, does the existing
production-available robustness table (`branchAgreement x robustnessScore`)
still transfer from validation to frozen test, or does it collapse too?

- Spec:
  `.trae/specs/plum-tohoku-focus-robustness-frozen-diagnostic/spec.md`,
  `tasks.md`, `checklist.md`.
- Tool:
  `tools/build_plum_tohoku_focus_robustness_frozen_diagnostic_report.dart`.
- Test:
  `test/plum_tohoku_focus_robustness_frozen_diagnostic_report_test.dart`
  (8-minute timeout, real data; asserts non-production policy, focus filter,
  bucket/band transfer structure, and that `shindo4` validation precision
  exceeds test precision).
- Report:
  `docs/baselines/plum_tohoku_focus_robustness_frozen_diagnostic.generated.md`
  (validation 2688 variants / 185694 station forecasts; test 2757 variants /
  179844 station forecasts; status `pass`).
- Policy:
  `rawPredictedIntensityMutated=false`, `frozenTestEvaluated=true`,
  `productionReady=false`, `productionUiConnected=false`,
  `diagnosticOnly=true`, `parametersTuned=false`,
  `suppressionApplied=false`.
- Focus subset:
  estimated-source region `tohoku`, evidence count `>=8`, nearest evidence
  distance `<10 km`, PLUM margin `>=1.0` shindo, and baseline threshold
  crossing required.

### Findings

Focus baseline:

| Threshold | Split | Samples | TP | FP | Precision |
| --- | --- | ---: | ---: | ---: | ---: |
| `shindo4` | validation | 457 | 389 | 68 | 85.1% |
| `shindo4` | test | 1051 | 458 | 593 | 43.6% |
| `shindo5-` | validation | 28 | 26 | 2 | 92.9% |
| `shindo5-` | test | 40 | 10 | 30 | 25.0% |

- The current robustness table does **not** transfer cleanly inside the focus
  hotspot.
- `shindo4` validation `high` buckets collapse on test:
  - `agree_3 / score_6`: `94.3% -> 50.0%`
  - `agree_3 / score_7`: `84.3% -> 46.7%`
  - projected `high` band overall: `85.1% -> 47.4%`
- The main test mass falls into validation-poor coverage:
  - validation `agree_2 / score_6` has only `2` samples and is therefore
    `insufficient`;
  - test `agree_2 / score_6` explodes to `839` samples at `43.1%` precision.
- `shindo5-` fails even harder:
  - validation `agree_2 / score_6` is `100.0%` on `21` samples;
  - test `agree_2 / score_6` becomes `25.0%` on `40` samples.
- Therefore the existing production-available robustness features are not
  stable enough to serve as the next confidence layer for this hotspot.

### Decision

- Keep this line diagnostic-only.
- Do not tune PLUM radius/damping from this report.
- Do not promote the current `branchAgreement x robustnessScore` table into
  wording or confidence for `tohoku` strong-nearby-evidence cases.
- Next step should shift from generic robustness scoring to
  focus-specific `region/site` or related production-available calibration
  features, because the current robustness buckets do not generalize across
  the frozen transfer.

## 2026-06-28 PLUM Tohoku Focus Region-Site Frozen Diagnostic

This follows the focus robustness frozen diagnostic. The narrower question
here is whether the existing geographic `region/site` view becomes stable when
restricted to the same `tohoku` strong-nearby-evidence hotspot.

- Spec:
  `.trae/specs/plum-tohoku-focus-region-site-frozen-diagnostic/spec.md`,
  `tasks.md`, `checklist.md`.
- Tool:
  `tools/build_plum_tohoku_focus_region_site_frozen_diagnostic_report.dart`.
- Test:
  `test/plum_tohoku_focus_region_site_frozen_diagnostic_report_test.dart`
  (8-minute timeout, real data; asserts non-production policy, focus filter,
  region/site transfer structure, and `shindo4` validation precision > test).
- Report:
  `docs/baselines/plum_tohoku_focus_region_site_frozen_diagnostic.generated.md`
  (validation 2688 variants / 185694 station forecasts; test 2757 variants /
  179844 station forecasts; status `pass`).
- Policy:
  `rawPredictedIntensityMutated=false`, `frozenTestEvaluated=true`,
  `productionReady=false`, `productionUiConnected=false`,
  `diagnosticOnly=true`, `parametersTuned=false`,
  `suppressionApplied=false`.
- Focus subset:
  estimated-source region `tohoku`, evidence count `>=8`, nearest evidence
  distance `<10 km`, PLUM margin `>=1.0` shindo, and baseline threshold
  crossing required.

### Findings

Focus baseline:

| Threshold | Split | Samples | TP | FP | Precision |
| --- | --- | ---: | ---: | ---: | ---: |
| `shindo4` | validation | 457 | 389 | 68 | 85.1% |
| `shindo4` | test | 1051 | 458 | 593 | 43.6% |
| `shindo5-` | validation | 28 | 26 | 2 | 92.9% |
| `shindo5-` | test | 40 | 10 | 30 | 25.0% |

- The coarse `region/site` view also fails to transfer inside the hotspot.
- `shindo4`:
  - validation `tohoku -> tohoku`: `83.4%` on 368 samples;
  - test `tohoku -> tohoku`: `43.8%` on 783 samples;
  - validation `tohoku -> kanto_chubu`: `92.1%` on 89 samples;
  - test `tohoku -> kanto_chubu`: `42.9%` on 268 samples.
- `shindo5-`:
  - validation `tohoku -> tohoku`: `90.0%` on 20 samples;
  - test `tohoku -> tohoku`: `25.0%` on 40 samples.
- Validation labels are misleading here because every populated `shindo4`
  bucket is `high`, but their projected test precision collapses together to
  `43.6%`.
- This means the current coarse geographic partition is still too blunt for
  the `tohoku` hotspot. The next diagnostic must move to a finer
  production-available geographic breakdown, not just reuse the existing
  latitude-band site classes.

### Decision

- Keep this line diagnostic-only.
- Do not tune PLUM radius/damping from this report.
- Do not promote the current coarse `region/site` table into confidence or
  wording for `tohoku` strong-nearby-evidence cases.
- Next step should refine the geography itself:
  e.g. `tohoku` source sub-bands, offshore-distance/site combinations, or
  similar production-available geographic partitions.

## 2026-06-28 PLUM Tohoku Focus Distance-Site Frozen Diagnostic

This follows the coarse focus `region/site` frozen diagnostic. The next
refinement is to replace broad latitude bands with a more offshore-sensitive,
production-available partition: estimated-source distance to station, crossed
with site band.

- Spec:
  `.trae/specs/plum-tohoku-focus-distance-site-frozen-diagnostic/spec.md`,
  `tasks.md`, `checklist.md`.
- Tool:
  `tools/build_plum_tohoku_focus_distance_site_frozen_diagnostic_report.dart`.
- Test:
  `test/plum_tohoku_focus_distance_site_frozen_diagnostic_report_test.dart`
  (8-minute timeout, real data; asserts non-production policy, focus filter,
  distance-site transfer structure, and `shindo4` validation precision > test).
- Report:
  `docs/baselines/plum_tohoku_focus_distance_site_frozen_diagnostic.generated.md`
  (validation 2688 variants / 185694 station forecasts; test 2757 variants /
  179844 station forecasts; status `pass`).
- Policy:
  `rawPredictedIntensityMutated=false`, `frozenTestEvaluated=true`,
  `productionReady=false`, `productionUiConnected=false`,
  `diagnosticOnly=true`, `parametersTuned=false`,
  `suppressionApplied=false`.
- Focus subset:
  estimated-source region `tohoku`, evidence count `>=8`, nearest evidence
  distance `<10 km`, PLUM margin `>=1.0` shindo, and baseline threshold
  crossing required.

### Findings

Focus baseline:

| Threshold | Split | Samples | TP | FP | Precision |
| --- | --- | ---: | ---: | ---: | ---: |
| `shindo4` | validation | 457 | 389 | 68 | 85.1% |
| `shindo4` | test | 1051 | 458 | 593 | 43.6% |
| `shindo5-` | validation | 28 | 26 | 2 | 92.9% |
| `shindo5-` | test | 40 | 10 | 30 | 25.0% |

- Distance adds structure, but still does not transfer cleanly enough.
- `shindo4` marginal distance precision:
  - `000_030km`: `74.3% -> 48.0%`
  - `030_060km`: `79.3% -> 45.5%`
  - `060_100km`: `95.9% -> 42.9%`
  - `100_200km`: `100.0% -> 37.6%`
- The `000_030km` bucket is the least bad transfer (`-26.3pp`), but still too
  weak for a confidence layer.
- Validation high buckets remain misleading:
  - projected `high` band overall: `90.3% -> 43.6%`
  - `060_100km x tohoku`: `94.4% -> 41.0%`
  - `100_200km x tohoku`: `100.0% -> 30.4%`
- So `distance x site` is more informative than coarse `region/site`, but it
  still does not generalize enough inside the hotspot.

### Decision

- Keep this line diagnostic-only.
- Do not tune PLUM radius/damping from this report.
- Do not promote the current `distance x site` table into confidence or
  wording for `tohoku` strong-nearby-evidence cases.
- Next step should move to an even finer production-available geography,
  especially `tohoku` source sub-bands and/or source-sub-band x distance/site
  combinations, because simple distance/site partitioning still collapses on
  frozen transfer.

## 2026-06-28 PLUM Tohoku Focus Source-Band/Site Frozen Diagnostic

This follows the focus `distance/site` frozen diagnostic. The next documented
refinement is to add production-available Tohoku source sub-bands on top of the
hotspot, while keeping the existing site bands fixed.

- Spec:
  `.trae/specs/plum-tohoku-focus-source-band-site-frozen-diagnostic/spec.md`,
  `tasks.md`, `checklist.md`.
- Tool:
  `tools/build_plum_tohoku_focus_source_band_site_frozen_diagnostic_report.dart`.
- Test:
  `test/plum_tohoku_focus_source_band_site_frozen_diagnostic_report_test.dart`
  (8-minute timeout, real data; asserts non-production policy, focus filter,
  source-band/site transfer structure, and `shindo4` validation precision >
  test).
- Report:
  `docs/baselines/plum_tohoku_focus_source_band_site_frozen_diagnostic.generated.md`
  (validation 2688 variants / 185694 station forecasts; test 2757 variants /
  179844 station forecasts; status `pass`).
- Policy:
  `rawPredictedIntensityMutated=false`, `frozenTestEvaluated=true`,
  `productionReady=false`, `productionUiConnected=false`,
  `diagnosticOnly=true`, `parametersTuned=false`,
  `suppressionApplied=false`.
- Focus subset:
  estimated-source region `tohoku`, evidence count `>=8`, nearest evidence
  distance `<10 km`, PLUM margin `>=1.0` shindo, and baseline threshold
  crossing required.

### Findings

Focus baseline:

| Threshold | Split | Samples | TP | FP | Precision |
| --- | --- | ---: | ---: | ---: | ---: |
| `shindo4` | validation | 457 | 389 | 68 | 85.1% |
| `shindo4` | test | 1051 | 458 | 593 | 43.6% |
| `shindo5-` | validation | 28 | 26 | 2 | 92.9% |
| `shindo5-` | test | 40 | 10 | 30 | 25.0% |

- The hotspot is heavily concentrated in `south_tohoku`, but that concentration
  does not rescue frozen transfer.
- `shindo4` marginal source-band precision:
  - `south_tohoku`: `84.4% -> 43.6%`
  - `mid_tohoku`: `100.0% -> 0.0%` on sparse validation-only mass
  - `north_tohoku`: no material mass in either split.
- `shindo4` populated source-band/site buckets all remain misleading:
  - `south_tohoku x tohoku`: `82.4% -> 43.8%`
  - `south_tohoku x kanto_chubu`: `92.1% -> 42.9%`
  - `mid_tohoku x tohoku`: `100.0% -> 0.0%` but test mass is `0`.
- `shindo5-` is even less stable:
  - `south_tohoku`: `92.9% -> 25.0%`
  - projected `high` band: `90.0% -> 25.0%`
- So the added source sub-band dimension explains where the hotspot mass lives,
  but still does not produce a transferable confidence partition.

### Decision

- Keep this line diagnostic-only.
- Do not tune PLUM radius/damping from this report.
- Do not promote the current `source-band x site` table into confidence or
  wording for `tohoku` strong-nearby-evidence cases.
- Next step should combine source sub-band with the more offshore-sensitive
  distance/site view, because source-band/site alone still collapses on frozen
  transfer.

## 2026-06-28 PLUM Tohoku Focus Source-Band Distance/Site Frozen Diagnostic

This follows the focus `source-band/site` frozen diagnostic. The next
documented refinement is to combine the two most informative production
dimensions together: Tohoku source sub-band and source-to-station
distance/site.

- Spec:
  `.trae/specs/plum-tohoku-focus-source-band-distance-site-frozen-diagnostic/spec.md`,
  `tasks.md`, `checklist.md`.
- Tool:
  `tools/build_plum_tohoku_focus_source_band_distance_site_frozen_diagnostic_report.dart`.
- Test:
  `test/plum_tohoku_focus_source_band_distance_site_frozen_diagnostic_report_test.dart`
  (8-minute timeout, real data; asserts non-production policy, focus filter,
  source-band-distance/site transfer structure, and `shindo4` validation
  precision > test).
- Report:
  `docs/baselines/plum_tohoku_focus_source_band_distance_site_frozen_diagnostic.generated.md`
  (validation 2688 variants / 185694 station forecasts; test 2757 variants /
  179844 station forecasts; status `pass`).
- Policy:
  `rawPredictedIntensityMutated=false`, `frozenTestEvaluated=true`,
  `productionReady=false`, `productionUiConnected=false`,
  `diagnosticOnly=true`, `parametersTuned=false`,
  `suppressionApplied=false`.
- Focus subset:
  estimated-source region `tohoku`, evidence count `>=8`, nearest evidence
  distance `<10 km`, PLUM margin `>=1.0` shindo, and baseline threshold
  crossing required.

### Findings

Focus baseline:

| Threshold | Split | Samples | TP | FP | Precision |
| --- | --- | ---: | ---: | ---: | ---: |
| `shindo4` | validation | 457 | 389 | 68 | 85.1% |
| `shindo4` | test | 1051 | 458 | 593 | 43.6% |
| `shindo5-` | validation | 28 | 26 | 2 | 92.9% |
| `shindo5-` | test | 40 | 10 | 30 | 25.0% |

- The combined geography is more descriptive, but it still does not yield a
  transferable confidence partition.
- `shindo4` reveals one less-bad medium bucket, but not a usable one:
  - `south_tohoku x 000_030km x tohoku`: `70.5% -> 48.0%`
- Every populated validation `high` bucket still collapses on test:
  - projected `high` overall: `90.8% -> 43.6%`
  - `south_tohoku x 030_060km x tohoku`: `79.8% -> 45.4%`
  - `south_tohoku x 060_100km x tohoku`: `94.4% -> 41.0%`
  - `south_tohoku x 100_200km x tohoku`: `100.0% -> 30.4%`
- Hotspot mass is now clearly localized:
  - essentially all test mass is `south_tohoku`;
  - `mid_tohoku` only appears in sparse validation-only buckets;
  - no material `north_tohoku` mass appears in either split.
- `shindo5-` remains completely unusable for confidence in this partition:
  every populated bucket is `insufficient`, and projected precision stays
  `25.0%`.
- Therefore even the combined production-available geography is exhausted as a
  confidence strategy for this hotspot.

### Decision

- Keep this line diagnostic-only.
- Do not tune PLUM radius/damping from this report.
- Do not promote the current `source-band x distance/site` table into
  confidence or wording for `tohoku` strong-nearby-evidence cases.
- Next step should stop refining geography and instead move to a validation-only
  event-family / propagation-family diagnostic for this hotspot, because the
  production-available geographic partitions no longer transfer.

## 2026-06-28 PLUM Tohoku Validation Event/Propagation-Family Diagnostic

This follows the last geographic hotspot drilldown. The next documented step is
to stay off frozen test for a moment and inspect whether the validation split
contains stable non-geographic propagation families at the event level.

- Spec:
  `.trae/specs/plum-tohoku-validation-event-family-diagnostic/spec.md`,
  `tasks.md`, `checklist.md`.
- Tool:
  `tools/build_plum_tohoku_validation_event_family_diagnostic_report.dart`.
- Test:
  `test/plum_tohoku_validation_event_family_diagnostic_report_test.dart`
  (8-minute timeout, real data; asserts validation-only policy, family
  definitions, and event-signature/family-aggregate sections).
- Report:
  `docs/baselines/plum_tohoku_validation_event_family_diagnostic.generated.md`
  (validation 2688 variants / 185694 station forecasts; status `pass`).
- Policy:
  `rawPredictedIntensityMutated=false`, `frozenTestEvaluated=false`,
  `validationOnly=true`, `productionReady=false`,
  `productionUiConnected=false`, `diagnosticOnly=true`,
  `parametersTuned=false`, `suppressionApplied=false`.
- Focus subset:
  estimated-source region `tohoku`, evidence count `>=8`, nearest evidence
  distance `<10 km`, PLUM margin `>=1.0` shindo, and baseline threshold
  crossing required.

### Findings

- Validation-only `shindo4` hotspot mass currently comes from just **3**
  events, and those 3 events separate into distinct propagation families.
- `shindo4` family aggregates:
  - `consistent/surrounded/wide`: `345` samples, `91.9%` precision
  - `mismatch/surrounded/moderate`: `90` samples, `55.6%` precision
  - `consistent/surrounded/moderate`: `22` samples, `100.0%` precision
- The clearly weakest validation family is
  `mismatch/surrounded/moderate`:
  - event `2021032018094483-38.4680-141.6277`
  - median below-threshold local share `50.0%`
  - median quadrant coverage `3.0`
  - median max spread `30.52 km`
  - precision `55.6%`
- By contrast, the dominant validation-positive family
  `consistent/surrounded/wide` is strong:
  - event `2021021323075051-37.7288-141.6985`
  - `345` samples
  - precision `91.9%`
  - median below-threshold local share `0.0%`
  - median max spread `47.14 km`
- `shindo5-` validation diversity is too small to generalize:
  - only `1` event contributes (`28` samples, `92.9%` precision)
  - only one family appears: `consistent/one_sided/compact`
- No validation family contains PLUM-only false positives in this current
  subset, so this report identifies candidate family structure but does **not**
  yet prove which family explains the frozen-test collapse.

### Decision

- Keep this line diagnostic-only and validation-only.
- Do not tune PLUM radius/damping from this report.
- Do not promote these family labels into confidence or wording.
- Next step should freeze these validation-defined family labels and run a
  single frozen-transfer comparison against the already-known Tohoku hotspot,
  to test whether `mismatch/surrounded/moderate` or adjacent families explain
  the frozen collapse.

## 2026-06-28 PLUM Tohoku Frozen Family Transfer Diagnostic

This follows the validation-only event/propagation-family diagnostic. The next
documented step is to reopen frozen test once, without changing the family
definitions, and check whether the frozen hotspot actually lands in the weak
validation family or an adjacent one.

- Spec:
  `.trae/specs/plum-tohoku-frozen-family-transfer-diagnostic/spec.md`,
  `tasks.md`, `checklist.md`.
- Tool:
  `tools/build_plum_tohoku_frozen_family_transfer_diagnostic_report.dart`.
- Test:
  `test/plum_tohoku_frozen_family_transfer_diagnostic_report_test.dart`
  (8-minute timeout, real data; asserts non-production policy, family
  definitions, and split/family transfer sections).
- Report:
  `docs/baselines/plum_tohoku_frozen_family_transfer_diagnostic.generated.md`
  (validation 2688 variants / 185694 station forecasts; test 2757 variants /
  179844 station forecasts; status `pass`).
- Policy:
  `rawPredictedIntensityMutated=false`, `frozenTestEvaluated=true`,
  `productionReady=false`, `productionUiConnected=false`,
  `diagnosticOnly=true`, `parametersTuned=false`,
  `suppressionApplied=false`.
- Focus subset:
  estimated-source region `tohoku`, evidence count `>=8`, nearest evidence
  distance `<10 km`, PLUM margin `>=1.0` shindo, and baseline threshold
  crossing required.

### Findings

- The frozen hotspot does **not** fall into the weakest validation family
  `mismatch/surrounded/moderate`.
- Instead, the entire `shindo4` frozen hotspot lands in an adjacent but
  previously unseen family:
  - `mismatch/one_sided/moderate`
  - `1051` samples
  - `458 TP / 593 FP`
  - precision `43.6%`
  - `549` PLUM-only FP
- Validation `shindo4` families were:
  - `consistent/surrounded/wide`: `345` samples, `91.9%`
  - `mismatch/surrounded/moderate`: `90` samples, `55.6%`
  - `consistent/surrounded/moderate`: `22` samples, `100.0%`
- So the transfer failure is not "the weak validation family got bigger"; it is
  "test moved into a nearby family with the same mismatch/spread character but
  a different geometry regime: `one_sided` instead of `surrounded`."
- `shindo5-` shows the same pattern:
  - validation: `consistent/one_sided/compact`, `92.9%`
  - test: `mismatch/one_sided/compact`, `25.0%`
- This means the missing axis is more specific than geography and more specific
  than broad family grouping: the frozen hotspot is characterized by
  **mismatch + one-sidedness**, with spread staying moderate/compact.

### Decision

- Keep this line diagnostic-only.
- Do not tune PLUM radius/damping from this report.
- Do not promote these family labels into confidence or wording.
- Next step should specifically drill into the `mismatch + one_sided` regime,
  not invent more geography. The next diagnostic should test whether
  one-sidedness is the transfer-breaking dimension inside mismatch families.

## 2026-06-28 PLUM Tohoku Mismatch One-Sided Transfer Diagnostic

This follows the frozen family transfer diagnostic. The next question is
narrower: once local mismatch exists, is `one_sided` geometry itself the
transfer-breaking dimension, or is the problem broader than that?

- Spec:
  `.trae/specs/plum-tohoku-mismatch-one-sided-transfer-diagnostic/spec.md`,
  `tasks.md`, `checklist.md`.
- Tool:
  `tools/build_plum_tohoku_mismatch_one_sided_transfer_diagnostic_report.dart`.
- Test:
  `test/plum_tohoku_mismatch_one_sided_transfer_diagnostic_report_test.dart`
  (8-minute timeout, real data; asserts non-production policy, regime
  definitions, and mismatch transfer sections).
- Report:
  `docs/baselines/plum_tohoku_mismatch_one_sided_transfer_diagnostic.generated.md`
  (validation 2688 variants / 185694 station forecasts; test 2757 variants /
  179844 station forecasts; status `pass`).
- Policy:
  `rawPredictedIntensityMutated=false`, `frozenTestEvaluated=true`,
  `productionReady=false`, `productionUiConnected=false`,
  `diagnosticOnly=true`, `parametersTuned=false`,
  `suppressionApplied=false`.
- Focus subset:
  estimated-source region `tohoku`, evidence count `>=8`, nearest evidence
  distance `<10 km`, PLUM margin `>=1.0` shindo, and baseline threshold
  crossing required.

### Findings

- `one_sided` is **not** the sole transfer-breaking dimension.
- At sample level, validation already contains `mismatch/one_sided/*` buckets,
  and they are already weak:
  - `mismatch/one_sided/moderate`: `13` samples, `53.8%`
  - `mismatch/one_sided/compact`: `8` samples, `50.0%`
- On frozen test, those same regimes stay weak but do **not** collapse much
  further:
  - `mismatch/one_sided/moderate`: `253` samples, `43.5%` (`-10.4pp`)
  - `mismatch/one_sided/compact`: `249` samples, `45.0%` (`-5.0pp`)
- The same is true for `mismatch/surrounded/*`:
  - validation `mismatch/surrounded/moderate`: `30` samples, `50.0%`
  - test `mismatch/surrounded/moderate`: `224` samples, `43.3%`
- So the bigger transfer problem is **mass shift**, not just precision shift:
  - validation mismatch buckets are small (`2` to `30` samples each)
  - frozen test mismatch buckets dominate the hotspot (`170` to `253` samples`)
- `shindo5-` is even more extreme:
  - validation has **no** mismatch buckets
  - frozen test is entirely `mismatch/one_sided/compact|moderate` at `25.0%`
- Therefore the key failure mode is not "one-sidedness suddenly breaks a good
  regime"; it is "test produces far more samples in already-weak mismatch
  regimes."

### Decision

- Keep this line diagnostic-only.
- Do not tune PLUM radius/damping from this report.
- Do not promote these regime labels into confidence or wording.
- Next step should explain the **regime-mass shift** into mismatch buckets on
  frozen test, rather than continuing to hunt for a small extra precision drop.

## 2026-06-28 PLUM Tohoku Mismatch Gap-Transition Diagnostic

This follows the mismatch regime mass-shift diagnostic. The next step is to
look only inside mismatch samples and ask whether frozen test introduces new
`actual-gap x evidence-gap` cells that validation simply did not cover.

- Spec:
  `.trae/specs/plum-tohoku-mismatch-gap-transition-diagnostic/spec.md`,
  `tasks.md`, `checklist.md`.
- Tool:
  `tools/build_plum_tohoku_mismatch_gap_transition_diagnostic_report.dart`.
- Test:
  `test/plum_tohoku_mismatch_gap_transition_diagnostic_report_test.dart`
  (8-minute timeout, real data; asserts non-production policy, gap-band
  definitions, and mismatch matrix sections).
- Report:
  `docs/baselines/plum_tohoku_mismatch_gap_transition_diagnostic.generated.md`
  (validation 2688 variants / 185694 station forecasts; test 2757 variants /
  179844 station forecasts; status `pass`).
- Policy:
  `rawPredictedIntensityMutated=false`, `frozenTestEvaluated=true`,
  `productionReady=false`, `productionUiConnected=false`,
  `diagnosticOnly=true`, `parametersTuned=false`,
  `suppressionApplied=false`.
- Focus subset:
  estimated-source region `tohoku`, evidence count `>=8`, nearest evidence
  distance `<10 km`, PLUM margin `>=1.0` shindo, and baseline threshold
  crossing required.

### Findings

- Validation `shindo4` mismatch cells are strongly polarized:
  - false side:
    - `lt_-2.0 x gte_3.0`: `18`, `0.0%`
    - `-2.0_to_-1.0 x gte_3.0`: `12`, `0.0%`
  - true side:
    - `0.0_to_1.0 x lt_1.0`: `5`, `100.0%`
    - `gte_1.0 x lt_1.0`: `26`, `100.0%`
- Frozen test keeps those polarized cells, but also introduces **new middle
  cells** that validation had no mass in.
- The most important new `shindo4` mismatch cells are:
  - `0.0_to_1.0 x 1.0_to_2.0`: `117`, `100.0%`
  - `0.0_to_1.0 x 2.0_to_3.0`: `47`, `100.0%`
  - `-1.0_to_0.0 x 2.0_to_3.0`: `55`, `0.0%`
  - `-1.0_to_0.0 x 1.0_to_2.0`: `27`, `0.0%`
- So frozen test is not just enlarging old extremes; it is adding a broad
  **near-threshold / medium-gap transition zone** around the boundary.
- `shindo5-` shows the same pattern in smaller form:
  - validation has no mismatch cells at all;
  - test introduces both far-below-threshold / huge-gap cells and
    near-threshold / middle-gap cells.
- Therefore the transferable candidate signal is no longer geometry or broad
  regime naming. It is the emergence of **near-threshold mismatch transition
  cells with medium evidence gap**.

### Decision

- Keep this line diagnostic-only.
- Do not tune PLUM radius/damping from this report.
- Do not promote these mismatch cells into confidence or wording.
- Next step should isolate the new middle transition cells
  (`actual in [-1, +1] around threshold` with `evidence gap 1-3`) and test
  whether that narrower transition zone is the real frozen-only signature.

## 2026-06-28 Iwate Offshore M4.1 GIF-First Reference Intake

- Applied the GIF-first intake rule to the user-provided JMA/EQuake event:
  - JMA source/intensity information:
    `2026-06-28 13:39:37 UTC+8`, `岩手県沖`, `40.1N 142.4E`, `M4.1`,
    depth `40 km`, maximum shindo `1`;
  - EQuake final report 13 reference:
    `2026-06-28 13:39:31 UTC+8`, `岩手県沖`, `40.14N 142.45E`, `M4.0`,
    depth `22 km`, quality `A`, confidence `80.5%`, RMS `0.87 s`,
    azimuthal gap `163 deg`, 196 triggered stations (`P:87 S:83 O:26`).
- The UTC+8 event time was converted to JST before capture:
  `2026-06-28T13:39:37+08:00` -> `2026-06-28T14:39:37+09:00`.
- Captured a complete local two-layer replay package:
  - directory: `tmp/captures/20260628_iwate_offshore_m41_jma`;
  - window: `2026-06-28T14:39:07+09:00` to
    `2026-06-28T14:41:37+09:00`;
  - timestamps: `151`;
  - layers: `jma_s`, `jma_b`;
  - GIFs: `302/302`;
  - failures: `0`;
  - decoder: `nied_gif_layered_v2`;
  - sensor selection policy: `surface_jma_s_primary_v1`.
- Added the reference record:
  - `docs/baselines/iwate_offshore_m41_20260628_reference.md`;
  - `test/fixtures/source_estimation/iwate_offshore_m41_20260628_jma.json`.
- Classification:
  - truth source: `jma_source_and_intensity_information`;
  - truth quality: `jma_source_and_intensity_verified_user_provided`;
  - split status: `unassigned_reference`;
  - keep outside frozen metrics until capture provenance and event-level split
    assignment are reviewed.
- This event is intentionally stored as a **two-layer** `jma_s/jma_b` capture.
  It must not be mislabeled as a multi-layer physical replay package.

## 2026-06-28 PLUM Tohoku Middle-Gap Transition-Zone Diagnostic

- Added
  [tools/build_plum_tohoku_middle_gap_transition_zone_diagnostic_report.dart](../tools/build_plum_tohoku_middle_gap_transition_zone_diagnostic_report.dart),
  [test/plum_tohoku_middle_gap_transition_zone_diagnostic_report_test.dart](../test/plum_tohoku_middle_gap_transition_zone_diagnostic_report_test.dart),
  and generated
  [docs/baselines/plum_tohoku_middle_gap_transition_zone_diagnostic.generated.md](baselines/plum_tohoku_middle_gap_transition_zone_diagnostic.generated.md)
  (validation 2688 variants / 185694 station forecasts; test 2757 variants /
  179844 station forecasts; status `pass`).
- Policy:
  `rawPredictedIntensityMutated=false`, `frozenTestEvaluated=true`,
  `productionReady=false`, `productionUiConnected=false`,
  `diagnosticOnly=true`, `parametersTuned=false`,
  `suppressionApplied=false`.
- Focus subset:
  estimated-source region `tohoku`, evidence count `>=8`, nearest evidence
  distance `<10 km`, PLUM margin `>=1.0` shindo, and baseline threshold
  crossing required.

### Findings

- `shindo4` confirms that the new frozen-only mass is concentrated in the
  narrow middle zone:
  - `middle_transition_zone`: `0.0% -> 25.2%`, precision `66.7%`
  - `extreme_false_zone`: `49.2% -> 44.7%`, precision `0.0%`
  - `extreme_true_zone`: `50.8% -> 25.3%`, precision `100.0%`
- Therefore the dominant `shindo4` transfer signature is
  `middle_transition_zone` (`+25.2pp` share delta) rather than the old extreme
  mismatch cells.
- `shindo5-` does not reduce to the same rule:
  - `middle_transition_zone`: `0.0% -> 25.0%`, precision `20.0%`
  - `extreme_false_zone`: `0.0% -> 50.0%`, precision `0.0%`
  - `extreme_true_zone`: `0.0% -> 20.0%`, precision `100.0%`
- So the narrow middle zone is the main frozen-only signature for `shindo4`,
  but not a universal cross-threshold signature.
- This also means the next diagnostic question is no longer “is the middle zone
  real?”; that answer is effectively yes for `shindo4`. The remaining problem is
  how to approximate it with **production-available** features, because the
  current zone definition depends on true actual-gap.

### Decision

- Keep this line diagnostic-only.
- Do not connect the middle-transition label to UI, wording, or notification.
- Do not tune PLUM radius/damping from this report.
- Next step should shift from truth-defined zones to production-available
  proxy search for `shindo4`, while keeping `shindo5-` as a separate
  extreme-false audit track.

## 2026-06-28 PLUM Tohoku Middle-Transition Proxy Diagnostic

- Added
  [tools/build_plum_tohoku_middle_transition_proxy_diagnostic_report.dart](../tools/build_plum_tohoku_middle_transition_proxy_diagnostic_report.dart),
  [test/plum_tohoku_middle_transition_proxy_diagnostic_report_test.dart](../test/plum_tohoku_middle_transition_proxy_diagnostic_report_test.dart),
  and generated
  [docs/baselines/plum_tohoku_middle_transition_proxy_diagnostic.generated.md](baselines/plum_tohoku_middle_transition_proxy_diagnostic.generated.md)
  (validation 2688 variants / 185694 station forecasts; test 2757 variants /
  179844 station forecasts; status `pass`).
- Policy:
  `rawPredictedIntensityMutated=false`, `frozenTestEvaluated=true`,
  `productionReady=false`, `productionUiConnected=false`,
  `diagnosticOnly=true`, `parametersTuned=false`,
  `suppressionApplied=false`.
- Focus subset:
  estimated-source region `tohoku`, evidence count `>=8`, nearest evidence
  distance `<10 km`, PLUM margin `>=1.0` shindo, and baseline threshold
  crossing required.

### Findings

- Validation still contains no `middle_transition_zone` samples in the
  `tohoku` focus subset, while frozen test contains `246 / 1051` (`23.4%`).
- Current production-available bucket families do **not** isolate that zone
  sharply.
- The largest mass-shift buckets are broad runtime states with almost no lift
  over the test base rate:
  - `branchAgreement=agree_2`: `885` samples, `23.5%`, `1.00x` lift
  - `robustnessScore=score_6`: `885` samples, `23.5%`, `1.00x` lift
- Geometry/spread buckets are only slightly above baseline:
  - `supportSpreadBand=moderate`: `23.6%`, `1.01x`
  - `quadrantCoverageBand=q2`: `24.6%`, `1.05x`
  - `geometrySpread=surrounded/moderate`: `25.0%`, `1.07x`
- The best non-trivial current joint bucket is
  `plumMarginBand=1.0_to_1.5` plus `geometrySpread=surrounded/moderate`:
  `140` test samples, `39` positives, `27.9%`, `1.19x` lift, `15.9%`
  capture share.
- Therefore the present proxy family explains the **mass redistribution** into
  frozen test better than it explains the label itself. No current bucket is a
  strong enough proxy for the middle-transition zone.

### Decision

- Keep this line diagnostic-only.
- Do not connect any current proxy bucket to UI, wording, or notification.
- Do not tune PLUM radius/damping from this report.
- Next step should stop refining the same coarse bucket families and instead
  add richer production-available continuous features for `shindo4`, such as
  support-contribution concentration, top-support dominance, or propagated
  margin spread, before re-running proxy search.

## 2026-06-28 PLUM Tohoku Middle-Transition Runtime-Signal Diagnostic

- Added
  [tools/build_plum_tohoku_middle_transition_runtime_signal_diagnostic_report.dart](../tools/build_plum_tohoku_middle_transition_runtime_signal_diagnostic_report.dart),
  [test/plum_tohoku_middle_transition_runtime_signal_diagnostic_report_test.dart](../test/plum_tohoku_middle_transition_runtime_signal_diagnostic_report_test.dart),
  and generated
  [docs/baselines/plum_tohoku_middle_transition_runtime_signal_diagnostic.generated.md](baselines/plum_tohoku_middle_transition_runtime_signal_diagnostic.generated.md)
  (validation 2688 variants / 185694 station forecasts; test 2757 variants /
  179844 station forecasts; status `pass`).
- Policy:
  `rawPredictedIntensityMutated=false`, `frozenTestEvaluated=true`,
  `productionReady=false`, `productionUiConnected=false`,
  `diagnosticOnly=true`, `parametersTuned=false`,
  `suppressionApplied=false`.
- Focus subset:
  estimated-source region `tohoku`, evidence count `>=8`, nearest evidence
  distance `<10 km`, PLUM margin `>=1.0` shindo, and baseline threshold
  crossing required.

### Findings

- Richer runtime-visible support-contribution signals improve the picture only
  modestly; they still do not form a strong discrete separator.
- The best current joint runtime-signal buckets are:
  - `contributionHhiBand=lt_0.10` + `plumMarginBand=1.0_to_1.5`:
    `308` test samples, `82` positives, `26.6%`, `1.14x` lift,
    `33.3%` capture share
  - `marginStdDevBand=0.30_to_0.50` + `plumMarginBand=1.0_to_1.5`:
    `325` test samples, `86` positives, `26.5%`, `1.13x` lift,
    `35.0%` capture share
- Single-feature signals remain weak:
  - `contributionHhiBand=lt_0.10`: `24.9%`, `1.06x`
  - `marginStdDevBand=0.30_to_0.50`: `25.1%`, `1.07x`
  - `effectiveSupportCountBand=gte_8`: `24.5%`, `1.05x`
- Dominance signals are not useful here:
  - frozen-test mass collapses entirely into
    `dominanceShareGapBand=lt_0.05`
  - and into `dominanceMarginGapBand=lt_0.10`
- Outcome means suggest only a subtle regime shift:
  middle-transition samples have slightly lower concentration, slightly higher
  effective support count, and slightly higher spread variation.
- So the middle-transition regime now looks more like a **diffuse,
  mildly-low-concentration, moderate-spread, low-to-mid-PLUM-margin**
  cluster than a crisp bucket boundary.

### Decision

- Keep this line diagnostic-only.
- Do not connect any current runtime-signal bucket to UI, wording, or
  notification.
- Do not tune PLUM radius/damping from this report.
- Next step should stop adding more discrete buckets and instead build a small
  diagnostic-only continuous runtime score from the mildly informative
  directions now observed: low concentration, moderate spread variance, and
  low-to-mid PLUM margin.

## 2026-06-28 PLUM Tohoku Middle-Transition Runtime-Score Diagnostic

- Added
  [tools/build_plum_tohoku_middle_transition_runtime_score_diagnostic_report.dart](../tools/build_plum_tohoku_middle_transition_runtime_score_diagnostic_report.dart),
  [test/plum_tohoku_middle_transition_runtime_score_diagnostic_report_test.dart](../test/plum_tohoku_middle_transition_runtime_score_diagnostic_report_test.dart),
  and generated
  [docs/baselines/plum_tohoku_middle_transition_runtime_score_diagnostic.generated.md](baselines/plum_tohoku_middle_transition_runtime_score_diagnostic.generated.md)
  (validation 2688 variants / 185694 station forecasts; test 2757 variants /
  179844 station forecasts; status `pass`).
- Policy:
  `rawPredictedIntensityMutated=false`, `frozenTestEvaluated=true`,
  `productionReady=false`, `productionUiConnected=false`,
  `diagnosticOnly=true`, `parametersTuned=false`,
  `suppressionApplied=false`.
- Focus subset:
  estimated-source region `tohoku`, evidence count `>=8`, nearest evidence
  distance `<10 km`, PLUM margin `>=1.0` shindo, and baseline threshold
  crossing required.

### Findings

- The continuous runtime score is mildly informative, but not sharply
  separating:
  - mean score: `0.631` for middle-transition samples vs `0.616` for other
    focus samples
  - top decile positive rate: `26.4%`
  - bottom decile positive rate: `22.9%`
  - top-to-bottom lift: `1.16x`
- Validation-anchored band transfer shows only modest enrichment in the upper
  bands:
  - `mid_high`: `26.4%`, `1.13x`
  - `high`: `26.3%`, `1.12x`
  - `low`: `22.4%`, `0.96x`
  - `mid_low`: `21.7%`, `0.93x`
- Therefore the score behaves more like a soft ranking signal than a strong
  class boundary.
- It also does not materially beat the best previous joint discrete buckets,
  which were already around `1.13x` to `1.14x` lift.

### Decision

- Keep this line diagnostic-only.
- Do not connect this runtime score to UI, wording, or notification.
- Do not tune PLUM radius/damping from this report.
- Next step should not be blind weight tuning. Instead, audit the strongest
  omitted production-available axis next: add a continuous
  `localBelowThresholdShare10Km` ramp and test whether
  `runtimeScore x local-mismatch-ramp` materially improves monotonicity. If it
  does not, stop direct middle-transition proxy optimization and keep this
  score as diagnostic-only evidence.

## 2026-06-28 PLUM Tohoku Middle-Transition Local-Mismatch-Ramp Diagnostic

- Added
  [tools/build_plum_tohoku_middle_transition_local_mismatch_ramp_diagnostic_report.dart](../tools/build_plum_tohoku_middle_transition_local_mismatch_ramp_diagnostic_report.dart),
  [test/plum_tohoku_middle_transition_local_mismatch_ramp_diagnostic_report_test.dart](../test/plum_tohoku_middle_transition_local_mismatch_ramp_diagnostic_report_test.dart),
  and generated
  [docs/baselines/plum_tohoku_middle_transition_local_mismatch_ramp_diagnostic.generated.md](baselines/plum_tohoku_middle_transition_local_mismatch_ramp_diagnostic.generated.md)
  (validation 2688 variants / 185694 station forecasts; test 2757 variants /
  179844 station forecasts; status `pass`).
- Policy:
  `rawPredictedIntensityMutated=false`, `frozenTestEvaluated=true`,
  `productionReady=false`, `productionUiConnected=false`,
  `diagnosticOnly=true`, `parametersTuned=false`,
  `suppressionApplied=false`.
- Focus subset:
  estimated-source region `tohoku`, evidence count `>=8`, nearest evidence
  distance `<10 km`, PLUM margin `>=1.0` shindo, and baseline threshold
  crossing required.

### Findings

- Multiplying by the local-mismatch ramp improves the raw top-to-bottom decile
  lift a little:
  - base: `1.16x`
  - adjusted: `1.26x`
- But the adjusted score does **not** reduce monotonicity breaks:
  - base decreasing adjacent pairs: `3`
  - adjusted decreasing adjacent pairs: `3`
- And the validation-anchored adjusted-score bands collapse:
  - validation anchors become `q25=0.0`, `q50=0.0`, `q75≈0.097`
  - validation mass is mostly `low`
  - frozen test mass is entirely `high`
- So this is not a robust transferable improvement. It changes ordering
  numerically, but it does not produce a stable validation-anchored partition.

### Decision

- Stop direct middle-transition proxy optimization here.
- Keep this runtime score and local-mismatch-ramp result as diagnostic-only
  evidence.
- Do not connect either score to UI, wording, or notification.
- Next step should return to broader transferable analysis and use this
  evidence as context, rather than continuing to tune a dedicated
  middle-transition proxy.

## 2026-06-28 PLUM Tohoku Upstream Source-Family Diagnostic

- Added
  [tools/build_plum_tohoku_upstream_source_family_diagnostic_report.dart](../tools/build_plum_tohoku_upstream_source_family_diagnostic_report.dart),
  [test/plum_tohoku_upstream_source_family_diagnostic_report_test.dart](../test/plum_tohoku_upstream_source_family_diagnostic_report_test.dart),
  and generated
  [docs/baselines/plum_tohoku_upstream_source_family_diagnostic.generated.md](baselines/plum_tohoku_upstream_source_family_diagnostic.generated.md)
  (validation 2688 variants / 69909 station forecasts; test 2757 variants /
  60373 station forecasts; status `pass`).
- Policy:
  `rawPredictedIntensityMutated=false`, `frozenTestEvaluated=true`,
  `productionReady=false`, `productionUiConnected=false`,
  `diagnosticOnly=true`, `parametersTuned=false`,
  `suppressionApplied=false`.
- Focus subset:
  estimated-source region `tohoku`, evidence count `>=8`, nearest evidence
  distance `<10 km`, baseline threshold crossing required, and no extra
  PLUM-margin gate.

### Findings

- The broader hotspot is overwhelmingly `PLUM`-led on frozen test:
  - source trigger family shifts from `plum_only 21.3%` / `both 53.6%` on
    validation to `plum_only 96.9%` / `both 2.8%` on test
  - source winner family shifts from `plum_higher 59.7%` / `jma_higher 40.3%`
    on validation to `plum_higher 99.6%` / `jma_higher 0.4%` on test
- Precision drop is therefore not a JMA-led transfer story inside this
  hotspot:
  - `plum_higher` precision falls from `69.8%` to `40.4%`
  - `jma_higher` nearly disappears instead of becoming the failure mass
- The middle-transition mass also sits almost entirely inside the PLUM-led
  branch:
  - `plum_higher + middle_transition_zone` grows from `2.3%` of validation
    focus mass to `14.9%` of test focus mass
  - `jma_higher + middle_transition_zone` goes from `0.6%` to `0.0%`
- The dominant frozen family is now clearly
  `plum_higher + mismatch/one_sided/compact`:
  - validation `13.4%`
  - test `63.9%`
  - share delta `+50.5pp`
- Test concentration is extreme:
  - event `2022031623342701-37.6810-141.6062` contributes `3511 / 3598`
    (`97.6%`) of the focus samples
  - it is also `plum_only`-dominant and `plum_higher`-dominant

### Decision

- Freeze the source-family conclusion: this hotspot is currently a PLUM-led
  transfer problem, not a JMA-style-led one.
- Keep all source-family and middle-transition labels diagnostic-only.
- Do not tune PLUM radius/damping or connect any of these labels to UI,
  wording, or notification.
- Next step should not generalize from this hotspot yet. First run an
  event-concentration / leave-top-event-out diagnostic on the PLUM-led
  hotspot, centered on `2022031623342701-37.6810-141.6062`, to determine how
  much of the current frozen regression is truly cross-event transferable.

## 2026-06-28 PLUM Tohoku Event-Concentration Diagnostic

- Added
  [tools/build_plum_tohoku_event_concentration_diagnostic_report.dart](../tools/build_plum_tohoku_event_concentration_diagnostic_report.dart),
  [test/plum_tohoku_event_concentration_diagnostic_report_test.dart](../test/plum_tohoku_event_concentration_diagnostic_report_test.dart),
  and generated
  [docs/baselines/plum_tohoku_event_concentration_diagnostic.generated.md](baselines/plum_tohoku_event_concentration_diagnostic.generated.md)
  (validation 2688 variants / 69909 station forecasts; test 2757 variants /
  60373 station forecasts; status `pass`).
- Policy:
  `rawPredictedIntensityMutated=false`, `frozenTestEvaluated=true`,
  `productionReady=false`, `productionUiConnected=false`,
  `diagnosticOnly=true`, `parametersTuned=false`,
  `suppressionApplied=false`.
- Focus subset:
  estimated-source region `tohoku`, evidence count `>=8`, nearest evidence
  distance `<10 km`, baseline threshold crossing required, and no extra
  PLUM-margin gate.

### Findings

- The hotspot is almost entirely concentrated in one test event:
  - dominant event `2022031623342701-37.6810-141.6062`
  - focus share `97.6%` (`3511 / 3598`)
  - top-3 cumulative share `99.7%`
  - top-5 cumulative share `100.0%`
- Removing the dominant event improves precision materially, but does **not**
  remove the PLUM-led character:
  - full test precision `40.4%`
  - leave-top-event-out precision `51.7%`
  - precision recovery `+11.3pp`
  - remaining slice is still `plum_only 97.7%` and `plum_higher 97.7%`
- So the current frozen regression is partly concentration-driven, but not
  purely a single-event artifact:
  - dominant event contributes `2044 / 2085` PLUM-only false positives
  - remainder still has `41` PLUM-only false positives out of `42` false
    positives
- The middle-transition label also remains active in the remainder:
  - full test middle-transition share `14.9%`
  - leave-top-event-out middle-transition share `17.2%`
  - but the remainder sample count is only `87`, so the estimate is too small
    to generalize from directly.

### Decision

- Freeze the concentration conclusion: the current hotspot is dominated by one
  event, and current full-test numbers overstate cross-event confidence.
- Also freeze the residual conclusion: even after removing the dominant event,
  the remainder is still overwhelmingly PLUM-led.
- Keep all event-concentration, source-family, and middle-transition labels
  diagnostic-only.
- Do not tune PLUM radius/damping or introduce any gate from this report.
- Next step should narrow to the remainder slice: run a residual
  leave-top-event-out family audit on the `87` remaining samples, focused on
  whether the surviving `plum_only / plum_higher` false positives collapse to
  one stable geometry family or are too sparse for transferable calibration.

## 2026-06-28 PLUM Tohoku Residual Remainder Family Audit

- Added
  [tools/build_plum_tohoku_residual_remainder_family_audit_report.dart](../tools/build_plum_tohoku_residual_remainder_family_audit_report.dart),
  [test/plum_tohoku_residual_remainder_family_audit_report_test.dart](../test/plum_tohoku_residual_remainder_family_audit_report_test.dart),
  and generated
  [docs/baselines/plum_tohoku_residual_remainder_family_audit.generated.md](baselines/plum_tohoku_residual_remainder_family_audit.generated.md)
  (validation 2688 variants / 69909 station forecasts; test 2757 variants /
  60373 station forecasts; status `pass`).
- Policy:
  `rawPredictedIntensityMutated=false`, `frozenTestEvaluated=true`,
  `productionReady=false`, `productionUiConnected=false`,
  `diagnosticOnly=true`, `parametersTuned=false`,
  `suppressionApplied=false`.
- Scope:
  same broader `tohoku` hotspot, but with dominant event
  `2022031623342701-37.6810-141.6062` removed before family audit.

### Findings

- The leave-top-event-out remainder is small but **not** family-random:
  - remainder samples `87`
  - remainder false positives `42`
  - remainder `plum_only` false positives `41`
  - remainder `plum_higher` false positives `41`
- The surviving remainder strongly collapses into one family:
  - overall remainder top family:
    `mismatch/one_sided/compact` with `77.0%`
  - remainder false positives top family:
    `mismatch/one_sided/compact` with `85.7%`
  - remainder `plum_only` false positives top family:
    `mismatch/one_sided/compact` with `85.4%`
  - top-2 remainder `plum_only` false-positive families already cover `97.6%`
- However this is **not** a new frozen-only family:
  - validation already has `mismatch/one_sided/compact` as the largest family
    (`1254` samples)
  - validation precision there is already weak at `25.4%`
  - so the surviving remainder is collapsing into an already-known weak family,
    not inventing a new transferable family signature
- The residual remainder is event-sparse:
  - `2022070605102497-38.4125-141.9545`: `53` samples
  - `2022080409481868-37.6118-141.6195`: `23` samples
  - remaining two events only `6` and `5` samples

### Decision

- Freeze the remainder-family conclusion: the surviving PLUM-led remainder does
  collapse strongly, but it collapses into `mismatch/one_sided/compact`, which
  is already a weak validation family.
- Therefore this remainder does **not** justify a new transferable family gate
  or direct hotspot-specific calibration on its own.
- Keep all family labels diagnostic-only and do not tune PLUM from this report.
- Next step should move one level deeper, not wider: audit the sub-regimes
  inside `mismatch/one_sided/compact`, comparing validation vs residual
  remainder on middle-transition share, local mismatch, and event mix, to see
  whether there is a narrower frozen-only slice inside that already-weak
  family.

## 2026-06-28 PLUM Tohoku mismatch/one_sided/compact Sub-Regime Audit

- Added
  [tools/build_plum_tohoku_mismatch_one_sided_compact_subregime_audit_report.dart](../tools/build_plum_tohoku_mismatch_one_sided_compact_subregime_audit_report.dart),
  [test/plum_tohoku_mismatch_one_sided_compact_subregime_audit_report_test.dart](../test/plum_tohoku_mismatch_one_sided_compact_subregime_audit_report_test.dart),
  and generated
  [docs/baselines/plum_tohoku_mismatch_one_sided_compact_subregime_audit.generated.md](baselines/plum_tohoku_mismatch_one_sided_compact_subregime_audit.generated.md)
  (validation family samples `1254`; leave-top-event-out family samples `67`;
  status `pass`).
- Policy:
  `rawPredictedIntensityMutated=false`, `frozenTestEvaluated=true`,
  `productionReady=false`, `productionUiConnected=false`,
  `diagnosticOnly=true`, `parametersTuned=false`,
  `suppressionApplied=false`.
- Scope:
  family fixed at `mismatch/one_sided/compact`, with dominant event
  `2022031623342701-37.6810-141.6062` removed before remainder comparison.

### Findings

- There is a real within-family shift, but it is not a single clean new rule:
  - validation middle-transition share: `7.1%`
  - remainder middle-transition share: `22.4%`
  - remainder false-positive middle-transition share: `41.7%`
- The remainder does **not** shift toward more extreme local mismatch:
  - `0.50_to_0.67` local-mismatch band grows from `37.1%` to `62.7%`
  - `gte_0.85` band shrinks from `40.6%` to `19.4%`
- So the remainder is not “more broken everywhere”; it is reweighted toward a
  narrower near-threshold mix:
  - positive remainder mass over-indexes on
    `actualGap 0.0_to_1.0 / evidenceGap lt_1.0`
  - false middle-transition remainder mass over-indexes on
    `actualGap -1.0_to_0.0 / evidenceGap 1.0_to_2.0`
- The strongest validation-only tail that disappears in the remainder is:
  - `other_family_samples|gte_0.85|-1.0_to_0.0|missing`
  - share delta `-22.4pp`
- Therefore the surviving remainder looks less like a new family and more like
  a redistribution inside the same weak family:
  - fewer ultra-high-local-mismatch / missing-evidence cells
  - more near-threshold true positives
  - plus a heavier middle-transition false slice

### Decision

- Freeze the sub-regime conclusion: there is a narrower frozen-shift signal
  inside `mismatch/one_sided/compact`, but it is still a mixture of:
  - valid near-threshold positives, and
  - middle-transition false cells.
- This still does **not** justify a direct production calibration rule, because
  the same family contains both the true and false over-indexed remainder mass.
- Keep all sub-regime labels diagnostic-only and do not tune PLUM from this
  report.
- Next step should stop broad family carving and inspect the separating axis
  between those two within-family remainder modes: compare production-available
  support/evidence signals for
  `0.0_to_1.0 / lt_1.0` positives versus `-1.0_to_0.0 / 1.0_to_2.0`
  middle-transition false cells inside `mismatch/one_sided/compact`.

## 2026-06-28 PLUM Tohoku mismatch/one_sided/compact Mode Signal Separation Diagnostic

- Added
  [tools/build_plum_tohoku_mismatch_one_sided_compact_mode_signal_separation_diagnostic_report.dart](../tools/build_plum_tohoku_mismatch_one_sided_compact_mode_signal_separation_diagnostic_report.dart),
  [test/plum_tohoku_mismatch_one_sided_compact_mode_signal_separation_diagnostic_report_test.dart](../test/plum_tohoku_mismatch_one_sided_compact_mode_signal_separation_diagnostic_report_test.dart),
  and generated
  [docs/baselines/plum_tohoku_mismatch_one_sided_compact_mode_signal_separation_diagnostic.generated.md](baselines/plum_tohoku_mismatch_one_sided_compact_mode_signal_separation_diagnostic.generated.md)
  (validation family `1254`; remainder family `67`; remainder target modes
  `30` near-threshold positives + `15` false middle-transition cells; status
  `pass`).
- Policy:
  `rawPredictedIntensityMutated=false`, `frozenTestEvaluated=true`,
  `productionReady=false`, `productionUiConnected=false`,
  `diagnosticOnly=true`, `parametersTuned=false`,
  `suppressionApplied=false`.
- Scope:
  same broader `tohoku` hotspot, dominant event
  `2022031623342701-37.6810-141.6062` removed, family fixed at
  `mismatch/one_sided/compact`, and feature buckets restricted to
  production-visible source/support/evidence signals only.

### Findings

- The two remainder modes are both overwhelmingly PLUM-led and single-support
  dominated:
  - source trigger family is `plum_only` for `30 / 30` near-threshold
    positives and `15 / 15` false middle-transition cells
  - source winner family is `plum_higher` for `30 / 30` near-threshold
    positives and `15 / 15` false middle-transition cells
  - mean top contribution share is `0.939` vs `1.000`
  - mean effective support count is `1.158` vs `1.000`
- There is directional separation, but not a broad clean hard boundary:
  - local mismatch `0.50_to_0.67`: `18` near-threshold positives vs `6` false
    cells, remainder share gap `+20.0pp`
  - quadrant coverage `q2`: `5` near-threshold positives vs `0` false cells,
    but only `11.1%` capture of the two-mode remainder mass
  - centroid offset `<5 km`: `9` near-threshold positives vs `0` false cells,
    but only `20.0%` capture
- The bulk false slice still sits in the same dominant buckets as valid
  near-threshold positives:
  - quadrant coverage `q1`: `25` near-threshold positives vs `15` false cells
  - nearest evidence distance `5.0_to_10.0 km`: `16` vs `10`
  - mean contribution margin `<0.25`: `23` vs `11`
- Validation shows the same directional tendency, but with strong overlap:
  - validation centroid offset means: `5.845 km` near-threshold positives vs
    `8.684 km` false middle-transition cells
  - validation local mismatch means: `0.630` vs `0.686`
  - validation q2 counts: `38` vs `8`
- So this is a gradient, not a transferable binary separator:
  false middle-transition cells are more degenerate and more offset, but many
  valid near-threshold positives live in the same one-sided, single-support,
  high-HHI buckets.

### Decision

- Freeze the separator conclusion: there is no broad production-safe hard gate
  inside `mismatch/one_sided/compact`.
- Do **not** add suppression rules based on `q1`, single-support collapse,
  centroid offset, local mismatch, or contribution concentration alone.
- Keep all mode labels and separator buckets diagnostic-only, and do not tune
  PLUM or mutate raw predicted intensity from this report.
- Next step should stop searching for a binary separator here and move to a
  non-suppression diagnostic: build a soft robustness score from the same
  source/support/evidence features, then test whether it can rank risky
  `mismatch/one_sided/compact` samples without suppressing valid
  near-threshold positives.

## 2026-06-28 PLUM Tohoku mismatch/one_sided/compact Mode Runtime-Score Diagnostic

- Added
  [tools/build_plum_tohoku_mismatch_one_sided_compact_mode_runtime_score_diagnostic_report.dart](../tools/build_plum_tohoku_mismatch_one_sided_compact_mode_runtime_score_diagnostic_report.dart),
  [test/plum_tohoku_mismatch_one_sided_compact_mode_runtime_score_diagnostic_report_test.dart](../test/plum_tohoku_mismatch_one_sided_compact_mode_runtime_score_diagnostic_report_test.dart),
  and generated
  [docs/baselines/plum_tohoku_mismatch_one_sided_compact_mode_runtime_score_diagnostic.generated.md](baselines/plum_tohoku_mismatch_one_sided_compact_mode_runtime_score_diagnostic.generated.md)
  (validation target modes `299` = `216` near-threshold positives + `83`
  false middle-transition; remainder target modes `45` = `30` + `15`; status
  `pass`).
- Policy:
  `rawPredictedIntensityMutated=false`, `frozenTestEvaluated=true`,
  `productionReady=false`, `productionUiConnected=false`,
  `diagnosticOnly=true`, `parametersTuned=false`,
  `suppressionApplied=false`.
- Scope:
  same broader `tohoku` hotspot, dominant event
  `2022031623342701-37.6810-141.6062` removed, family fixed at
  `mismatch/one_sided/compact`, and labels restricted to the two target modes:
  `0.0_to_1.0 / lt_1.0` near-threshold positives versus
  `-1.0_to_0.0 / 1.0_to_2.0` false middle-transition cells.

### Findings

- A soft score built from support geometry, evidence concentration, and
  evidence proximity does create useful ordering:
  - validation mode means: runtime score `0.392` for near-threshold positives
    vs `0.295` for false middle-transition
  - remainder mode means: `0.264` vs `0.149`
- Validation-anchored bands transfer directionally on the leave-top-event-out
  remainder:
  - `low` band: `11` near-threshold positives vs `11` false cells,
    near-positive rate `50.0%`, false capture `73.3%`
  - `high` band: `4` near-threshold positives vs `0` false cells,
    near-positive rate `100.0%`, false capture `0.0%`
  - middle bands stay near-positive dominant at `78.6%` and `80.0%`
- The score is useful as ranking, not as a hard threshold:
  - remainder quartile 4 reaches `91.7%` near-positive rate and only `8.3%`
    false rate
  - but quartile 2 is noisier than quartile 1 (`36.4%` near-positive rate),
    so the ordering is not perfectly monotone
  - monotonicity summary remains mixed: positive adjacent pairs `2`
    non-decreasing / `1` decreasing; negative adjacent pairs `2`
    non-increasing / `1` increasing
- The concentration branch contributes very little inside this family:
  - validation concentration mean already sits near zero (`0.034` for
    near-threshold positives, `0.000` for false middle-transition)
  - remainder concentration mean is `0.000` for both modes
  - most separation here comes from support-geometry and proximity, not from a
    broad de-concentration effect

### Decision

- Freeze the runtime-score conclusion: a soft score is more useful than a hard
  separator for this family, and it can rank risk directionally on the
  remainder slice.
- Do **not** threshold this score into suppression, rejection, or production
  coordinate gating.
- Keep the score diagnostic-only, and do not connect it to UI, wording, or
  notification.
- Next step should stay non-suppressive and test score parsimony/transfer:
  compare the full score against simpler ablations such as
  `supportGeometry-only` and `supportGeometry + proximity`, then verify whether
  the ranking survives without the currently weak concentration term.

## 2026-06-28 PLUM Tohoku mismatch/one_sided/compact Mode Runtime-Score Ablation Diagnostic

- Added
  [tools/build_plum_tohoku_mismatch_one_sided_compact_mode_runtime_score_ablation_diagnostic_report.dart](../tools/build_plum_tohoku_mismatch_one_sided_compact_mode_runtime_score_ablation_diagnostic_report.dart),
  [test/plum_tohoku_mismatch_one_sided_compact_mode_runtime_score_ablation_diagnostic_report_test.dart](../test/plum_tohoku_mismatch_one_sided_compact_mode_runtime_score_ablation_diagnostic_report_test.dart),
  and generated
  [docs/baselines/plum_tohoku_mismatch_one_sided_compact_mode_runtime_score_ablation_diagnostic.generated.md](baselines/plum_tohoku_mismatch_one_sided_compact_mode_runtime_score_ablation_diagnostic.generated.md)
  (validation target modes `299`; remainder target modes `45`; status `pass`).
- Policy:
  `rawPredictedIntensityMutated=false`, `frozenTestEvaluated=true`,
  `productionReady=false`, `productionUiConnected=false`,
  `diagnosticOnly=true`, `parametersTuned=false`,
  `suppressionApplied=false`.
- Scope:
  same broader `tohoku` hotspot, dominant event
  `2022031623342701-37.6810-141.6062` removed, family fixed at
  `mismatch/one_sided/compact`, and ablations compared on the same two target
  modes:
  `0.0_to_1.0 / lt_1.0` near-threshold positives versus
  `-1.0_to_0.0 / 1.0_to_2.0` false middle-transition cells.

### Findings

- The current concentration term is not helping this family:
  - `supportGeometry-only` has the largest validation mean gap (`0.176`) and
    remainder mean gap (`0.191`)
  - `supportGeometry + proximity` drops to `0.132` / `0.176`
  - `full score` drops further to `0.097` / `0.114`
- `supportGeometry-only` also has the cleanest quartile monotonicity:
  - high/low near-positive lift `1.53x`
  - high/low false-rate ratio `0.37x`
  - positive adjacent pairs `3` non-decreasing / `0` decreasing
  - negative adjacent pairs `3` non-increasing / `0` increasing
- Adding proximity changes the tradeoff, but not uniformly for the better:
  - `supportGeometry + proximity` and `full score` both push more false cells
    into the `low` band (`73.3%` false capture vs `60.0%` for
    `supportGeometry-only`)
  - but they also drag more valid near-threshold positives into that same
    `low` band (`36.7%` near capture vs `26.7%`)
- The high-end ranking remains equally pure across all three variants:
  - all variants have `100.0%` near-positive rate and `0.0%` false rate in
    the `high` band
  - so the extra terms are not buying a cleaner top slice
- Therefore the simplest score currently transfers best on this family:
  the geometry term carries most of the usable signal, proximity is a
  recall-leaning add-on with mixed value, and concentration is effectively dead
  here.

### Decision

- Freeze the ablation conclusion: for
  `mismatch/one_sided/compact`, `supportGeometry-only` is the best current
  family-level ranking baseline.
- Do **not** promote any of these variants into suppression or production
  gating.
- Keep all ablation results diagnostic-only and do not connect them to UI,
  wording, or notification.
- Next step should stay within non-suppressive diagnostics and test transfer:
  run the `supportGeometry-only` family score against additional event slices /
  manifests, then compare whether this family-local ranking remains stable
  outside the current leave-top-event-out remainder.

## 2026-06-28 PLUM Tohoku mismatch/one_sided/compact Support-Geometry Transfer Diagnostic

- Added
  [tools/build_plum_tohoku_mismatch_one_sided_compact_support_geometry_transfer_diagnostic_report.dart](../tools/build_plum_tohoku_mismatch_one_sided_compact_support_geometry_transfer_diagnostic_report.dart),
  [test/plum_tohoku_mismatch_one_sided_compact_support_geometry_transfer_diagnostic_report_test.dart](../test/plum_tohoku_mismatch_one_sided_compact_support_geometry_transfer_diagnostic_report_test.dart),
  and generated
  [docs/baselines/plum_tohoku_mismatch_one_sided_compact_support_geometry_transfer_diagnostic.generated.md](baselines/plum_tohoku_mismatch_one_sided_compact_support_geometry_transfer_diagnostic.generated.md)
  (validation target modes `299`; remainder target modes `45`; evaluated
  slices `4`; status `pass`).
- Policy:
  `rawPredictedIntensityMutated=false`, `frozenTestEvaluated=true`,
  `productionReady=false`, `productionUiConnected=false`,
  `diagnosticOnly=true`, `parametersTuned=false`,
  `suppressionApplied=false`.
- Scope:
  same broader `tohoku` hotspot, dominant event
  `2022031623342701-37.6810-141.6062` removed, family fixed at
  `mismatch/one_sided/compact`, score fixed at `supportGeometry-only`, and
  transfer evaluated on pooled remainder plus per-event slices with at least
  `4` target-mode samples.

### Findings

- The pooled leave-top-event-out remainder remains stable under the family-local
  support-geometry score:
  - mean gap `0.191`
  - low-band false capture `60.0%` vs low-band near capture `26.7%`
  - high-band near rate `100.0%` with `0.0%` false rate
  - quartile monotonicity is clean: high/low near lift `1.53x`,
    high/low false-rate ratio `0.37x`
- The main surviving event also keeps directional ordering, but with noise:
  - event `2022070605102497-38.4125-141.9545`
  - samples `34` (`25` near-threshold positives, `9` false middle-transition)
  - mean gap `0.213`
  - high band still pure (`3 / 3` near, `0` false)
  - but quartiles are not fully monotone because quartile 3 regresses relative
    to quartile 2
- The remaining per-event slices are too small to validate transfer:
  - `2022031700522985-37.7947-141.7145`: `4` target-mode samples
  - `2022080409481868-37.6118-141.6195`: `4` target-mode samples
  - both are correctly labeled `sample_sparse`
- Therefore the current evidence supports a narrower claim than the pooled
  remainder suggested:
  `supportGeometry-only` is a good family-local ranking baseline, but current
  cross-event proof is strong only for the pooled slice and directional-only
  for the largest residual event.

### Decision

- Freeze the transfer conclusion: `supportGeometry-only` remains the best
  diagnostic family-local ranking baseline, but its cross-event stability is
  only partially verified.
- Do **not** generalize this into a production family score yet, because the
  per-event evidence is still dominated by one residual event and two slices
  remain sample-sparse.
- Keep the score diagnostic-only and disconnected from UI, wording, and
  notification.
- Next step should stay on verification, not tuning: extend this same
  family-local transfer check to additional event pools / manifests so the
  ranking is either confirmed across more events or explicitly scoped to the
  current residual event family mix.

## 2026-06-28 PLUM Tohoku mismatch/one_sided/compact Support-Geometry Broader Verification Diagnostic

- Added
  [tools/build_plum_tohoku_mismatch_one_sided_compact_support_geometry_broader_verification_diagnostic_report.dart](../tools/build_plum_tohoku_mismatch_one_sided_compact_support_geometry_broader_verification_diagnostic_report.dart),
  [test/plum_tohoku_mismatch_one_sided_compact_support_geometry_broader_verification_diagnostic_report_test.dart](../test/plum_tohoku_mismatch_one_sided_compact_support_geometry_broader_verification_diagnostic_report_test.dart),
  and generated
  [docs/baselines/plum_tohoku_mismatch_one_sided_compact_support_geometry_broader_verification_diagnostic.generated.md](baselines/plum_tohoku_mismatch_one_sided_compact_support_geometry_broader_verification_diagnostic.generated.md)
  (validation target modes `299`; remainder target modes `45`; remainder
  events `4`; evaluated slices `8`; status `pass`).
- Policy:
  `rawPredictedIntensityMutated=false`, `frozenTestEvaluated=true`,
  `productionReady=false`, `productionUiConnected=false`,
  `diagnosticOnly=true`, `parametersTuned=false`,
  `suppressionApplied=false`.
- Scope:
  same broader `tohoku` hotspot, dominant event
  `2022031623342701-37.6810-141.6062` removed, family fixed at
  `mismatch/one_sided/compact`, score fixed at `supportGeometry-only`, and
  broader verification evaluated on:
  - pooled remainder;
  - `leave_event_out_pool` slices for each remainder event;
  - `event_only` slices with at least `4` target-mode samples.

### Findings

- The pooled remainder still looks strong in isolation:
  - `45` target-mode samples
  - mean gap `0.191`
  - stability `stable`
  - high/low near lift `1.53x`
  - high/low false-rate ratio `0.37x`
- But the broader pooled verification breaks once the largest residual event is
  removed:
  - `leave_event_out::2022070605102497-38.4125-141.9545`
  - `11` target-mode samples (`5` near, `6` false)
  - mean gap only `0.007`
  - stability `not_stable`
  - quartiles are no longer monotone and the high band disappears
- The other leave-event-out pooled slices remain only directional, not stable:
  - excluding `2022031700522985-37.7947-141.7145`: `41` samples,
    mean gap `0.221`, `directional_but_noisy`
  - excluding `2022080409481868-37.6118-141.6195`: `41` samples,
    mean gap `0.216`, `directional_but_noisy`
  - excluding `2022081814461047-37.6017-141.5853`: `42` samples,
    mean gap `0.159`, `directional_but_noisy`
- Event-only evidence is still narrow:
  - `event_only::2022070605102497-38.4125-141.9545`: `34` samples,
    `directional_but_noisy`
  - `event_only::2022031700522985-37.7947-141.7145`: `4` samples,
    `sample_sparse`
  - `event_only::2022080409481868-37.6118-141.6195`: `4` samples,
    `sample_sparse`
- Therefore the broader check falsifies the stronger transfer claim:
  `supportGeometry-only` is useful as a pooled family-local ranking baseline,
  but it is still materially dependent on the dominant residual event mix and
  does not hold as a broadly transferable score across the minor-event pool.

### Decision

- Freeze the broader-verification conclusion:
  `supportGeometry-only` remains the best current diagnostic ranking baseline
  inside this family, but it is **not** broadly transferable across pooled
  remainder events.
- Do **not** promote it into production scoring, gating, UI wording, or
  notification logic.
- Scope the conclusion explicitly:
  it is valid for pooled remainder diagnostics and informative for the dominant
  residual event, but not strong enough to justify a family-wide runtime score.
- Next step should stop trying to generalize this score directly and instead
  inspect the minor-event pooled remainder (`leave_event_out` of
  `2022070605102497-38.4125-141.9545`) for whether any other runtime-visible
  signal separates near-threshold positives from false middle-transition cells,
  or whether this branch should simply stay as pooled-only diagnostic context.

## 2026-06-28 PLUM Tohoku mismatch/one_sided/compact Minor-Event Pooled Signal Diagnostic

- Added
  [tools/build_plum_tohoku_mismatch_one_sided_compact_minor_event_pooled_signal_diagnostic_report.dart](../tools/build_plum_tohoku_mismatch_one_sided_compact_minor_event_pooled_signal_diagnostic_report.dart),
  [test/plum_tohoku_mismatch_one_sided_compact_minor_event_pooled_signal_diagnostic_report_test.dart](../test/plum_tohoku_mismatch_one_sided_compact_minor_event_pooled_signal_diagnostic_report_test.dart),
  and generated
  [docs/baselines/plum_tohoku_mismatch_one_sided_compact_minor_event_pooled_signal_diagnostic.generated.md](baselines/plum_tohoku_mismatch_one_sided_compact_minor_event_pooled_signal_diagnostic.generated.md)
  (validation target modes `278`; minor-slice target modes `11`; minor-slice
  events `3`; status `pass`).
- Policy:
  `rawPredictedIntensityMutated=false`, `frozenTestEvaluated=true`,
  `productionReady=false`, `productionUiConnected=false`,
  `diagnosticOnly=true`, `parametersTuned=false`,
  `suppressionApplied=false`.
- Scope:
  same broader `tohoku` hotspot, dominant event
  `2022031623342701-37.6810-141.6062` removed, then additional exclusion of
  `2022070605102497-38.4125-141.9545` to isolate the minor-event pooled slice
  across:
  - `2022031700522985-37.7947-141.7145` (`4` samples)
  - `2022080409481868-37.6118-141.6195` (`4` samples)
  - `2022081814461047-37.6017-141.5853` (`3` samples)

### Findings

- All current runtime-visible score variants fail on the minor slice:
  - `support_geometry_only`: mean gap `0.007`, `not_stable`
  - `support_geometry_plus_proximity`: mean gap `-0.061`, `not_stable`
  - `full_score`: mean gap `-0.041`, `not_stable`
- None of the score variants produce a high-confidence top band:
  - all three have `0` samples in the validation-anchored `high` band on the
    minor slice
  - all three collapse into the same quartile pattern: quartile 3 is all false
    middle-transition (`0` near, `3` false), so monotonicity breaks
- The minor slice is also structurally different from the broader pooled
  remainder:
  - near-threshold positives have **worse** local mismatch than falses
    (`0.833` vs `0.776`)
  - both classes are entirely one-sided (`quadrants = 1.0`) with zero spread
    and fully concentrated contributions (`top1 = 1.0`, `HHI = 1.0`)
  - so most broad-runtime geometry/concentration features degenerate and stop
    carrying separation
- The top feature buckets are only directional fragments, not stable signals:
  - `centroidOffsetBand=5_to_10`: `1` near / `5` false, support `6`
  - `evidenceCountBand=gte_16`: `1` near / `4` false, support `5`
  - `evidenceCountBand=12_to_15`: `3` near / `1` false, support `4`
  - `centroidOffsetBand=gte_10`: `3` near / `1` false, support `4`
- Those buckets are mutually conflicting and all tiny, so they do **not** form
  a clean runtime-visible separator for a new family score.

### Decision

- Freeze the minor-slice conclusion:
  there is currently **no stable runtime-visible family score** for the
  minor-event pooled remainder after removing
  `2022070605102497-38.4125-141.9545`.
- Keep `supportGeometry-only` scoped to pooled-remainder diagnostic context
  only; do **not** continue trying to generalize it into a minor-event score.
- Do **not** promote any of these minor-slice buckets or variants into
  production scoring, gating, wording, or notification logic.
- Next step should close this branch rather than keep tuning:
  record that no stable minor-event family score is currently demonstrated, and
  only revisit if additional manifests enlarge the minor-event pool enough to
  re-test transfer with materially more support.

## 2026-06-29 PLUM Tohoku mismatch/one_sided/compact Branch Closure

This closes the current `tohoku` / `mismatch` / `one_sided` / `compact`
diagnostic branch that started from frozen-test PLUM-only false positives.

### Closed Findings

- The hotspot is real and remains PLUM-led:
  - frozen-test `tohoku` false positives are dominated by PLUM-only triggers;
  - JMA-style explains the separate `kanto_chubu` attenuation failure, not this
    branch.
- Broad geometry/concentration diagnostics identified a useful pooled ranking
  signal, but that signal does not transfer cleanly once the dominant residual
  event mix is removed.
- The minor-event pooled slice is too small and structurally degenerate for the
  currently available runtime-visible features:
  - all tested score variants are `not_stable`;
  - no validation-anchored high-confidence band survives;
  - one-sided, fully concentrated evidence collapses most separator features.
- Therefore no stable runtime-visible family score is currently demonstrated
  for this minor-event remainder.

### Decision

- Stop tuning this branch for now.
- Keep all derived labels and scores diagnostic-only.
- Do not tune PLUM radius/damping, do not add a suppression gate, and do not
  connect this branch to UI, wording, notification, or raw intensity mutation.
- The only valid reopen condition is new data: additional manifests must enlarge
  the minor-event pool enough to re-test transfer with materially more support.

### Next Action

- Return to dataset/replay expansion and source-family validation:
  - prioritize adding more real high-shindo local captures and formally tagged
    JMA/Hi-net references;
  - rerun the existing frozen/replay diagnostics only after the sample pool
    changes materially;
  - keep the raw predicted intensity output unchanged while future wording or
    confidence layers remain separate diagnostic/product-policy work.

## 2026-06-29 Metric-Readiness Refresh After Replay-Pool Expansion

After closing the PLUM `tohoku` minor-event tuning branch, the split/readiness
chain was rerun so the data-coverage state reflects the latest local replay
fixtures instead of the older 10-case diagnostic-ready snapshot.

- Regenerated and validated:
  - `docs/baselines/source_estimation_split_assignment_readiness.generated.md`;
  - `docs/baselines/source_estimation_split_blocker_queue.generated.md`;
  - `docs/baselines/final_catalog_or_hinet_revision_review_packet.generated.md`;
  - `docs/baselines/source_metric_readiness_triage.generated.md`.
- Updated tests/tool guards so the newly added PLUM-like replay cases are
  recognized explicitly instead of failing stale hard-count checks:
  - diagnostic-ready report: `12` cases;
  - blocker queue: `14` blocked cases;
  - metric-readiness triage: `16` total cases, `12` diagnostic-ready blocked,
    `2` metadata-only/incomplete, `2` reference-validation only.

### Current Metric-Readiness State

- Metric-bearing ready: `0`.
- Reference-validation only: `2`
  (`20260622_fukushima_offshore_m22_eq4`,
  `noto_m27_20260621_jma_eq5`).
- Ready for manual split assignment but still not metric-bearing: `3`
  (`20260622_iwate_east_offshore_m30_hinet`,
  `20260622_tomakomai_south_offshore_m35_hinet`,
  `20260623_tokachi_southeast_offshore_m34_hinet`).
- PLUM-like replay-only cases: `3`.
  - `20260626_yamanashi_east_fuji_five_lakes_m56_jma_equake21` and
    `20260627_fukushima_aizu_m36_jma_equake17` have complete local capture
    packages but remain `keep_plum_like_diagnostic_only`.
  - `20260626_yamanashi_east_fuji_five_lakes_m33_jma_equake8` remains
    `metadata_only_or_incomplete` because its local capture manifest reports
    `failedGifCount=16` (`286/302` GIFs downloaded).

### Decision

- Do not promote PLUM-like replay lead-time cases into source-estimation
  metric-bearing split assignment from this triage.
- Keep the two complete PLUM replay cases as replay/lead-time diagnostics only.
- Treat the M3.3 Yamanashi aftershock as a concrete data-coverage gap:
  it has a JMA reference label, but the incomplete local capture package must
  be repaired or explicitly excluded before it can be used even as a complete
  replay diagnostic.
- The PLUM-like replay lead-time report now enforces this boundary by skipping
  replay cases whose `capture_manifest.json` has `failedGifCount > 0`.
  The current report evaluates `6` complete cases and lists the M3.3 Yamanashi
  aftershock under `skippedCases` with reason `capture_manifest_failed_gifs`.

### Next Action

- Data work first:
  - explicitly exclude
    `20260626_yamanashi_east_fuji_five_lakes_m33_jma_equake8` from complete
    replay diagnostics, or replace it with another complete capture; this is a
    missing-GIF gap (`302` expected, `286` downloaded, `16` failed), and its JST
    origin is already outside the 3-hour historical GIF repair window;
  - continue adding new high-shindo local captures when available;
  - only rerun frozen/replay diagnostics after the sample pool materially
    changes.
- Evidence work in parallel:
  - JMA-link blockers remain for `20260622_kushiro_offshore_m30_jma`,
    `20260624_fukushima_aizu_m32_jma_eq5`, and
    `20260625_iwate_offshore_m32_jma`;
  - Hi-net/revision blockers remain separate from replay-only PLUM diagnostics.

## 2026-06-29 PLUM Replay Capture Gap Report

The replay coverage blocker is now represented as its own report instead of
being inferred only from `plum_like_replay_leadtime.skippedCases`.

- Added:
  - `tools/build_plum_replay_capture_gap_report.dart`;
  - `tools/validate_plum_replay_capture_gap.ps1`;
  - `test/plum_replay_capture_gap_report_test.dart`;
  - `docs/baselines/plum_replay_capture_gap.generated.md`.
- Scope:
  - diagnostic-only;
  - reads replay fixture manifests and `capture_manifest.json`;
  - does not repair captures;
  - does not exclude captures;
  - does not change replay metrics directly.
- Current result:
  - cases scanned: `7`;
  - complete cases: `6`;
  - gap cases: `1`;
  - failed GIFs: `16`;
  - sole gap case:
    `20260626_yamanashi_east_fuji_five_lakes_m33_jma_equake8`
    (`302` expected, `286` downloaded, `16` failed).

### Decision

- Keep the M3.3 Yamanashi aftershock out of complete replay lead-time metrics.
- Keep acceptance/operating-point reports blocked on replay coverage until this
  missing-GIF gap is explicitly excluded or replaced by another complete
  high-shindo capture.
- The immediate data task is now concrete:
  resolve the single expired missing-GIF row in
  `plum_replay_capture_gap.generated.md` without proposing historical
  re-download.

### Validation

- `powershell -NoProfile -ExecutionPolicy Bypass -File
  tools\validate_plum_replay_capture_gap.ps1`.

## 2026-06-29 PLUM Replay Capture Gap Exclusion Decision

The expired M3.3 Yamanashi missing-GIF gap is now explicitly reviewed instead
of remaining an unresolved replay coverage blocker.

- Added `docs/data/plum_replay_capture_gap_decisions.json`.
- The approved decision covers all `16` failed GIF files for
  `20260626_yamanashi_east_fuji_five_lakes_m33_jma_equake8`.
- The decision records that the event is outside the 3-hour historical GIF
  repair window, so historical re-download must not be proposed.
- `tools/build_plum_replay_capture_gap_report.dart` now reads that decision
  ledger and separates:
  - unresolved gap cases: `0`;
  - excluded gap cases: `1`;
  - unresolved failed GIFs: `0`;
  - excluded failed GIFs: `16`.
- The excluded case remains out of complete replay lead-time metrics. It does
  not count as a complete capture and should only be replaced by another
  capture with no missing GIFs.

### Validation

- `powershell -NoProfile -ExecutionPolicy Bypass -File
  tools\validate_plum_replay_capture_gap.ps1`;
- `flutter test test\source_estimation_validation_suite_test.dart`;
- `flutter analyze tools\build_plum_replay_capture_gap_report.dart
  test\plum_replay_capture_gap_report_test.dart
  test\source_estimation_validation_suite_test.dart
  test\jma_catalog_availability_report_test.dart
  test\jma_final_catalog_review_packet_test.dart`.

## 2026-06-29 Hi-net Capture Provenance Exclusion Decision for Iwate M3.4 Ref

The expired M3.4 Iwate-offshore missing-GIF capture issue is now explicitly
reviewed instead of remaining an unresolved Hi-net capture provenance blocker.

- Updated `docs/data/hinet_capture_provenance_review_decisions.json` for
  `20260620_iwate_offshore_m34_ref`.
- `decisionStatus` moved from `pending_capture_repair_or_exclusion` to
  `capture_frame_exclusion_approved`; `exclusionApproved` is `true`.
- The decision records that the missing NIED GIF frame
  `20260620212727.jma_b.gif` cannot be repaired: the event origin
  (2026-06-20 21:25:27 JST) is older than the public KMoni replay retention
  window, and the recorded NIED repair URL returned HTTP 404.
- Historical re-download must not be proposed for this frame.
- `excludedFiles` lists `20260620212727.jma_b.gif` and `missing_frame_1`.

### Cascade effects after exclusion approval

The exclusion decision propagates through the Hi-net and external-input
report chain. All downstream reports were regenerated and their tests
updated to reflect the post-exclusion state.

- `hinet_capture_provenance_review`: pending `0`, approved `1`, ready `1`,
  unresolved `0`.
- `hinet_capture_exclusion_templates`: `0` templates (the tool only emits
  templates for pending cases).
- `hinet_capture_exclusion_review_packet`: `0` packets.
- `hinet_capture_repair_probe`: `0` cases, `0` affected files, `0` templates.
- `source_estimation_external_input_queue`: `inputItemCount` `6` (down from
  `7`); `missing_gif_archive_copy` no longer appears.
- `source_estimation_external_input_templates`: `templateCount` `6`;
  `missing_gif_archive_copy` no longer appears.
- `source_estimation_external_input_delta`: `deltaRowCount` `6`,
  `matchedTemplateCount` `6`.
- `source_estimation_external_input_attempts`: `attemptCount` stays `18`
  (the attempts ledger is unchanged), but each of the 4 historical
  `missing_gif_archive_copy::20260620_iwate_offshore_m34_ref` attempts now
  emits an `attempt_references_nonqueued_input` warning because that input
  is no longer queued.
- `source_estimation_external_input_worklist`: `openInputCount` `6`,
  `highestPriority` `20`, `nextInputType` `local_jma_reference_capture_package`,
  `nextCaseId` `20260625_iwate_offshore_m46_jma_eqsc9`.

### Known design gap (not fixed by this decision)

`tools/build_hinet_truth_quality_review_queue_report.dart` reads capture
provenance from the capture manifest via `_CaptureProvenance.fromDirectory`,
not from the exclusion decision ledger. As a result, the truth-quality review
queue still marks `20260620_iwate_offshore_m34_ref` as
`repair_capture_before_review` even though the capture frame exclusion is
approved. This is a known gap; the exclusion still clears the capture
provenance, exclusion template, exclusion packet, repair probe, and external
input chain. The truth-quality review queue design gap is left for a separate
roadmap step so that this exclusion decision stays focused and verifiable.

### Validation

- `powershell -NoProfile -ExecutionPolicy Bypass -File
  tools\validate_source_estimation_suite.ps1`;
- `flutter analyze
  test\source_estimation_validation_suite_test.dart
  test\source_estimation_external_input_queue_report_test.dart
  test\source_estimation_external_input_template_report_test.dart
  test\source_estimation_external_input_delta_report_test.dart
  test\source_estimation_external_input_attempt_report_test.dart
  test\source_estimation_external_input_worklist_report_test.dart
  test\hinet_capture_provenance_review_report_test.dart
  test\hinet_capture_exclusion_template_report_test.dart
  test\hinet_capture_exclusion_review_packet_test.dart
  test\hinet_capture_exclusion_decision_import_test.dart
  test\hinet_capture_repair_probe_report_test.dart`.

## 2026-06-29 Authenticated Hi-net Export Submission for Three Pending Cases

Three remaining Hi-net truth-quality pending cases now have authenticated JMA
unified arrival-time rows submitted, reviewed, and accepted as constrained
reference evidence.

- `20260621_fukushima_offshore_m32_eq6`: authenticated row origin
  `2026-06-21T23:41:11.87 JST`, location `37.624333N, 142.278167E`, M3.2,
  depth 32.88 km, region `SE OFF MIYAGI PREF`.
- `20260622_iwate_offshore_m30_eq10`: authenticated row origin
  `2026-06-22T09:28:23.11 JST`, location `40.393167N, 142.385333E`, M3.2,
  depth 42.69 km, region `NE OFF IWATE PREF`.
- `20260622_wakayama_south_m25_hinet`: authenticated row origin
  `2026-06-22T09:51:16.91 JST`, location `33.5615N, 135.7995E`, M2.5,
  depth 31.22 km, region `SOUTHERN WAKAYAMA PREF`.

### Submission and acceptance flow

1. `docs/data/hinet_authenticated_export_request.json` was extended with 3 new
   requests (total 6).
2. `docs/data/hinet_authenticated_export_rows.json` was extended with 3 new
   `submitted_for_review` rows (total 6).
3. The 3 fixture files had `catalogTruthVerified` corrected from `true` to
   `false` because `truthSource` is `user_provided_hinet_hypocenter`, not JMA
   final catalog.
4. `docs/data/source_hinet_no_row_found_findings.json` was extended with 3
   `pending_finding` entries so the evidence review report does not emit
   `unsupported_no_row_status:missing`.
5. `tools/import_source_hinet_reviewer_decision.dart` imported 3
   `accepted_constrained_reference` decisions with
   `evidenceType: authenticated_hinet_export_row`.
6. All 6 Hi-net truth-quality review decisions are now
   `accepted_constrained_reference`.

### Cascade effects after acceptance

The 3 newly accepted decisions propagate through the entire validation chain.
All downstream reports were regenerated and their tests updated.

- `hinet_truth_quality_review`: `pendingDecisionCount` 4→1,
  `acceptedForConstrainedReferenceSplitCount` 3→6.
- `hinet_truth_quality_review_queue`: `externalEvidenceMissingCount` 4→1,
  `acceptedForConstrainedReferenceSplitCount` 3→6.
- `source_estimation_split_assignment_readiness`:
  `readyForManualSplitAssignmentCount` 3→6,
  `assign_event_level_split` 3→6, `review_hinet_preliminary_truth_quality`
  3→1.
- `source_estimation_split_blocker_queue`:
  `readyForManualSplitAssignmentCount` 3→6,
  `assign_event_level_split` 3→6, `review_hinet_preliminary_truth_quality`
  3→1.
- `source_metric_readiness_triage`: `readyForManualSplitAssignmentCount`
  3→6, `assign_event_level_split` 3→6,
  `review_hinet_preliminary_truth_quality` 3→1.
- `source_hinet_truth_quality_triage_packet`: `packetCount` 4→1 (only
  `20260620_iwate_offshore_m34_ref` remains).
- `source_hinet_priority_evidence_template_packet`: `packetCount` 3→0 (all
  priority cases accepted).
- `source_hinet_no_row_found_review_packet`: `packetCount` 0 (unchanged,
  already empty).
- `hinet_authenticated_export_review`: `rowCount` 3→6,
  `acceptedDecisionCount` 3→6, `decisionEvidenceReadyCount` 3→0,
  `pendingDecisionCount` 3→0.
- `source_hinet_evidence_review`: `pendingEvidenceCount` 3→6,
  `authenticatedEvidenceReadyCount` 3→0, `combinedEvidenceReadyCount` 3→0,
  `acceptedDecisionCount` 3→6.
- `source_hinet_reviewer_decision_staging`: `reviewerDecisionEligibleCount`
  3→0, `blockedCount` 3→6, `alreadyAcceptedCount` 3→6.
- `hinet_external_evidence_targets`: `authenticatedExportRequestCount` 3→6,
  `authenticatedExportRowCount` 3→6,
  `submittedAuthenticatedExportRowCount` 3→6.

### Validation

- `powershell -NoProfile -ExecutionPolicy Bypass -File
  tools\validate_source_estimation_suite.ps1`;
- `flutter analyze
  test\source_estimation_split_assignment_readiness_report_test.dart
  test\source_estimation_split_blocker_queue_report_test.dart
  test\source_metric_readiness_triage_report_test.dart
  test\hinet_truth_quality_review_report_test.dart
  test\hinet_truth_quality_review_queue_report_test.dart
  test\source_hinet_truth_quality_triage_packet_test.dart
  test\hinet_authenticated_export_review_report_test.dart
  test\source_hinet_priority_evidence_template_packet_test.dart
  test\source_hinet_evidence_review_report_test.dart
  test\source_hinet_reviewer_decision_staging_report_test.dart
  test\hinet_external_evidence_targets_test.dart
  test\source_estimation_validation_suite_test.dart`.

## Five Hi-net constrained validation split assignments

After the authenticated Hi-net reviewer decisions were accepted, the
event-level split-assignment follow-up was executed for the safe constrained
reference cases only. Five Hi-net references were assigned to the frozen
validation split as `validation_reference`:

- `20260622_iwate_east_offshore_m30_hinet`;
- `20260622_iwate_offshore_m30_eq10`;
- `20260622_tomakomai_south_offshore_m35_hinet`;
- `20260622_wakayama_south_m25_hinet`;
- `20260623_tokachi_southeast_offshore_m34_hinet`.

All five remain constrained reference-validation cases. They are not catalog
truth, must not be used for final test claims, and must keep
`includeInDetectionMetrics: false`.

`20260621_fukushima_offshore_m32_eq6` was deliberately not assigned in this
pass. Although its Hi-net constrained reference decision is accepted, it is a
candidate-region false-recovery guard and remains `unassigned_reference` until
a later explicit split gate decides whether that diagnostic guard should be
promoted. It must not be auto-swept into validation by a generic Hi-net
assignment pass.

The resulting split/readiness state is:

- `source_estimation_split_assignment_patch`: 7 proposals, all already
  applied (the original 2 reference-validation cases plus the 5 safe Hi-net
  constrained references).
- `source_estimation_split_assignment_readiness`:
  `readyForFrozenSplitCount` 7,
  `readyForManualSplitAssignmentCount` 1,
  `blockedByManualSplitAssignmentCount` 12.
- `source_estimation_split_blocker_queue`:
  `completedSplitAssignmentCount` 7,
  `readyForManualSplitAssignmentCount` 1,
  `blockedCaseCount` 12.
- `source_metric_readiness_triage`:
  `referenceValidationOnlyCount` 7,
  `diagnosticReadyBlockedCount` 8,
  `metricBearingReadyCount` 0.

Validation run:

- `powershell -NoProfile -ExecutionPolicy Bypass -File
  tools\validate_source_estimation_split_assignment_patch.ps1`;
- `powershell -NoProfile -ExecutionPolicy Bypass -File
  tools\validate_source_estimation_split_assignment_readiness.ps1`;
- `powershell -NoProfile -ExecutionPolicy Bypass -File
  tools\validate_source_estimation_split_blocker_queue.ps1
  -UseExistingReadiness`;
- `powershell -NoProfile -ExecutionPolicy Bypass -File
  tools\validate_source_metric_readiness_triage.ps1`.

## Fukushima False-Recovery Diagnostic Split Gate

`20260621_fukushima_offshore_m32_eq6` is now explicitly held by
`keep_candidate_region_false_recovery_diagnostic_only` instead of the generic
`assign_event_level_split` action. This keeps the accepted Hi-net constrained
reference available for candidate-region diagnostics while preventing it from
being repeatedly proposed as an ordinary manual validation split assignment.

Current state:

- `splitStatus`: `unassigned_reference`;
- `includeInDetectionMetrics`: `false`;
- `readyForManualSplitAssignmentCount`: `0`;
- `nextAction`: `keep_candidate_region_false_recovery_diagnostic_only`;
- metric readiness remains diagnostic-only with `metricBearingReadyCount` `0`.

Promotion, if it is ever needed, must be handled by a later explicit
candidate-region false-recovery split gate. It must not be swept into
validation by a generic Hi-net constrained-reference assignment pass.

## Realtime NIED P/S Fit and Best-Hold Optimization

The 2026-06-30 realtime capture review compared two newly captured NIED GIF
windows against JMA/EQuake references:

- `20260630_fukushima_hamadori_m34`: JMA 2026-06-30 12:08:45 JST,
  Fukushima Hamadori, M3.4, 70 km.
- `20260630_iwate_offshore_m36`: JMA 2026-06-30 12:24:33 JST,
  Iwate offshore, M3.6, 50 km.

Both realtime windows are incomplete captures, so they must be treated as
runtime diagnostics rather than frozen metric-bearing evidence:

- Fukushima: 16 processed GIF frames in the checked window, 50 missing
  strict-1 Hz frames.
- Iwate: 38 processed GIF frames in the checked window, 58 missing strict-1 Hz
  frames.
- The 12:15 JST noise trigger produced no source estimate, which is the
  desired behavior.

Findings:

- The Iwate realtime case showed the estimator can find a good offshore
  solution early (`40.411, 142.312`, about 9.5 km from JMA), but later frames
  can drift west toward the land station cluster unless a P/S residual
  regression guard holds the cleaner earlier solution.
- A hard station-pair travel-time-difference score was tested but is not safe
  as a primary score for GIF-only input. On the sparse Fukushima realtime
  capture, small station-pair sets overfit and moved the result from the safer
  56.8 km solution to an 81.6 km solution. Therefore travel-time-difference
  residuals should remain diagnostics until gated by sufficient P/S accepted
  counts, pair counts, low missing-frame rate, and stable candidate geometry.
- Local reference replay samples are not affected by missing GIF frames
  (`151/151` decoded in the checked runs), but still show best-to-final
  degradation on several offshore cases. This means frame gaps are a real
  realtime problem, but not the only accuracy limiter.

Implemented/active direction:

- `NiedGifHybridSourceEstimator` now emits P/S fit diagnostics:
  `phase_line_score`, `phase_line_mean_residual_s`,
  `phase_line_p_count`, `phase_line_s_count`, `phase_line_other_count`.
- It also emits station-pair travel-time-difference diagnostics:
  `phase_difference_score`, `phase_difference_mean_residual_s`, and
  `phase_difference_pair_count`. These are currently diagnostic-only
  (`phaseDifferenceScoreWeight: 0.0`) because direct weighting was harmful on
  sparse GIF captures.
- `SeismicSourceTracker` holds the previous NIED GIF estimate when a new
  candidate is a P/S residual regression (`phase_line_regression`), low support,
  or an uncertain one-sided boundary hit.

Next implementation step:

- Add a conservative same-event P/S best-fit hold. The tracker should remember
  the best clean P/S candidate for the active event and prevent later candidates
  from overwriting it when they have materially worse P/S residual and a
  meaningful spatial jump. This specifically targets local replay cases where
  `bestErrorKm` is good but `finalErrorKm` degrades, without relying on truth
  coordinates at runtime.

Implemented follow-up:

- `SeismicSourceTracker` now keeps a same-event P/S best-fit candidate for
  NIED GIF estimates only. A candidate is eligible for best-fit memory only
  when it has at least 9 supporting stations and
  `phase_line_mean_residual_s <= 1.55`. Later candidates are held when they
  regress by at least 0.8 s in P/S mean residual and jump at least 20 km from
  the remembered best-fit candidate.
- Lower thresholds were rejected during tuning: allowing 5 or 8 station
  best-fit candidates over-held low-support or marginal candidates and
  degraded Tomakomai/Iwate reference replays.
- The selected gate keeps the 2026-06-30 realtime Iwate offshore diagnostic at
  about 9.5 km error while leaving the sparse Fukushima realtime diagnostic at
  the safer 56.8 km solution.

Latest checked local replay outcomes after the best-fit hold gate:

| Case | Decoded | Median km | P90 km | Final km | Best km |
| --- | ---: | ---: | ---: | ---: | ---: |
| `20260620_iwate_offshore_m34_ref` | 151/151 | 35.5 | 63.5 | 63 | 24 |
| `20260621_fukushima_offshore_m32_eq6` | 151/151 | 135.0 | 172.0 | 172 | 126 |
| `20260622_iwate_east_offshore_m30_hinet` | 151/151 | 34.0 | 52.6 | 9 | 9 |
| `20260622_iwate_offshore_m30_eq10` | 151/151 | 30.0 | 54.0 | 30 | 19 |
| `20260622_kushiro_offshore_m30_jma` | 151/151 | 13.0 | 25.0 | 13 | 2 |
| `20260622_tomakomai_south_offshore_m35_hinet` | 151/151 | 7.0 | 49.4 | 7 | 3 |
| `20260623_tokachi_southeast_offshore_m34_hinet` | 151/151 | 15.0 | 22.4 | 74 | 13 |
| `20260624_fukushima_aizu_m32_jma_eq5` | 151/151 | 8.0 | 14.0 | 14 | 1 |
| `20260625_iwate_offshore_m32_jma` | 151/151 | 41.0 | 58.0 | 19 | 10 |

### EQuake multi-report line-fit evidence packet

The user supplied an EQuake multi-report packet for a separate Iwate offshore
event around 2026-06-30 12:22:49 UTC+8. The packet contains 17 text reports
plus six screenshots of the map and the lower-left phase-fit plot.

Reference comparison from the packet:

- EQuake final report: Iwate offshore, `40.30N, 142.53E`, M3.8, 13 km,
  `A - 80.4% / 0.6s / 239°`, triggers `113` stations
  (`P:58 | S:37 | O:18`).
- Hi-net hypocenter: `40.233N, 142.428E`, M3.8, 48.2 km.

Operational observations:

- EQuake locks onto an offshore longitude early. From report 3 onward the
  longitude stays around `142.3E..142.5E`, instead of drifting toward the land
  station cluster.
- Reports 1-8 are essentially P-only (`S:0`) yet still form a stable offshore
  solution. This implies P-only line-fit quality can be strong enough to hold
  an early candidate before S arrivals become useful.
- Later reports show two clear lines in the lower-left plot: a dense P line and
  a smaller but coherent S line. O/outlier points are visually separated from
  the fitted lines.
- The reported residual stays roughly `0.46s..0.60s` in later reports, much
  lower than the current GIF estimator's typical `phase_line_mean_residual_s`
  range on several reference cases. The estimator needs grouped line-fit
  diagnostics rather than only per-station nearest-phase residuals.
- EQuake depth changes substantially across reports (`40 km -> 37 km -> 25 km
  -> 17 km -> 2 km -> 14 km -> 13 km`), so future work should add discrete
  depth search for P/S line fitting. Fixed-depth P/S diagnostics are not enough
  for deeper events such as Fukushima Hamadori.

Next algorithmic direction:

- Add grouped P/S line-fit diagnostics: fit P and S line intercepts separately
  for each candidate, classify stations into P/S/O by line residual, and expose
  grouped P/S/O counts plus grouped mean residual.
- Add P-only line-fit diagnostics so early P-only offshore candidates can be
  recognized explicitly instead of waiting for S support.
- Keep station-pair travel-time-difference residuals diagnostic-only until
  gated by stable grouped P/S fit, enough pair count, and low missing-frame
  risk.
- Later add discrete depth candidates for the grouped P/S fit before promoting
  depth-sensitive residuals into primary scoring.

Implemented first step:

- `NiedGifHybridSourceEstimator` now emits grouped line-fit diagnostics:
  `grouped_phase_line_score`, `grouped_phase_line_mean_residual_s`,
  `grouped_phase_line_p_count`, `grouped_phase_line_s_count`,
  `grouped_phase_line_other_count`, `p_only_line_mean_residual_s`,
  `p_only_line_residual_p90_s`, `s_only_line_mean_residual_s`, and
  `s_only_line_residual_p90_s`.
- The grouped fit separately estimates P-line and S-line intercepts for each
  candidate before assigning stations to P/S/O by residual. This better matches
  the EQuake lower-left phase-fit plot than the earlier per-station nearest
  P/S residual alone.
- A small primary-score weight was tested and rejected: it preserved the Iwate
  realtime offshore diagnostic but degraded the sparse Fukushima realtime
  diagnostic from the safer 56.8 km solution to 81.6 km. Therefore
  `groupedPhaseLineScoreWeight` is currently `0.0`; grouped diagnostics are
  available for calibration, best-hold gating, and future depth-search work but
  do not yet move the solution directly.

### EQuake Fukushima deep-source evidence packet

The user supplied a Fukushima EQuake packet for the 2026-06-30 11:08:36 UTC+8
event. It confirms the current grouped P/S diagnostics need depth search before
they can safely influence runtime location.

Reference comparison from the packet:

- EQuake final report: Fukushima Hamadori, `37.35N, 140.97E`, M3.6, 67 km,
  `A - 76.6% / 0.84s / 143°`, triggers `129` stations
  (`P:33 | S:75 | O:21`).
- JMA: Fukushima Hamadori, `37.3N, 141.0E`, M3.4, 70 km.
- Hi-net: `37.354N, 141.003E`, M3.5, 64.0 km.

Operational observations:

- EQuake converges on the deep source early: reports 3-5 are already around
  `64 km..71 km` depth while still mostly P-only
  (`P:19/S:0/O:1`, `P:21/S:0/O:1`, `P:27/S:1/O:1`).
- This explains why fixed-depth grouped diagnostics are unsafe. A fixed
  40 km grouped line fit can prefer a visually cleaner but wrong candidate on
  sparse Fukushima GIF captures.
- The Fukushima final phase-fit plot shows curved P/S structure, consistent
  with hypocentral distance `sqrt(surfaceDistance^2 + depth^2)`. Deep-source
  P/S line fit must search depth before becoming a scoring or best-hold gate.

Next depth-search step:

- Add diagnostic-only discrete depth search for grouped P/S and P-only line
  fits using `[10, 20, 40, 60, 80, 100, 140] km`.
- Emit `grouped_phase_best_depth_km`,
  `grouped_phase_depth_mean_residual_s`, `p_only_best_depth_km`, and
  `p_only_depth_mean_residual_s`.
- Keep these depth-aware diagnostics out of primary scoring until they are
  validated on the realtime Fukushima/Iwate captures and local reference
  replays.

Validation set for this work:

- Realtime diagnostic capture:
  `test\current_capture_replay_analysis_test.dart`.
- Local reference replays:
  `test\iwate_offshore_reference_replay_test.dart`,
  `test\iwate_offshore_m32_reference_replay_test.dart`,
  `test\iwate_offshore_m30_reference_replay_test.dart`,
  `test\iwate_east_offshore_reference_replay_test.dart`,
  `test\fukushima_offshore_reference_replay_test.dart`,
  `test\fukushima_aizu_reference_replay_test.dart`,
  `test\tokachi_southeast_offshore_reference_replay_test.dart`,
  `test\kushiro_offshore_reference_replay_test.dart`,
  `test\tomakomai_south_offshore_reference_replay_test.dart`.

### Depth and magnitude diagnostic implementation pass

Implemented diagnostic-only depth search for the NIED GIF hybrid estimator.
This deliberately does not change primary scoring or published source fields
yet.

New NIED GIF diagnostics:

- `grouped_phase_best_depth_km`
- `grouped_phase_depth_mean_residual_s`
- `grouped_phase_depth_supported`
- `p_only_best_depth_km`
- `p_only_depth_mean_residual_s`
- `p_only_depth_supported`

Depth support rule:

- grouped depth is supported only when both P and S have enough members
  (`P >= 3` and `S >= 3`), outliers remain limited, and grouped mean residual
  is low.
- P-only depth is retained as a raw diagnostic but marked unsupported. Current
  realtime captures show why: with free origin-time/intercept, P-only fits can
  drift to the maximum searched depth even when this is not physically reliable.

Realtime capture validation after implementation:

| Event | Final error | Support | Raw grouped depth | Supported | P/S/O | Magnitude diagnostic |
|---|---:|---:|---:|---|---|---:|
| Fukushima Hamadori 2026-06-30 11:08 UTC+8 | 56.8 km | 12 | 140 km | false | 11/0/1 | M2.54 |
| Iwate offshore 2026-06-30 11:24 UTC+8 | 9.5 km | 5 | 140 km | false | 5/0/0 | M2.72 |

The raw 140 km depth in both realtime captures is explicitly not trusted:
there is no S support in the accepted final estimate. This confirms that
depth must not be promoted into production output from P-only GIF timing.

Local reference replay validation:

| Case | Final error | Best error | Support | Raw grouped depth | Supported | P/S/O | Magnitude diagnostic |
|---|---:|---:|---:|---:|---|---|---:|
| `20260620_iwate_offshore_m34_ref` | 63 km | 24 km | 17 | 140 km | false | 5/3/9 | -- |
| `20260621_fukushima_offshore_m32_eq6` | 172 km | 126 km | 11 | 10 km | false | 7/3/1 | -- |
| `20260622_iwate_east_offshore_m30_hinet` | 9 km | 9 km | 18 | 10 km | false | 1/10/7 | M2.20 |
| `20260622_iwate_offshore_m30_eq10` | 30 km | 19 km | 13 | 40 km | false | 3/7/3 | -- |
| `20260622_kushiro_offshore_m30_jma` | 13 km | 2 km | 9 | 10 km | true | 3/5/1 | M2.22 |
| `20260622_tomakomai_south_offshore_m35_hinet` | 7 km | 3 km | 14 | 80 km | true | 8/6/0 | -- |
| `20260623_tokachi_southeast_offshore_m34_hinet` | 74 km | 13 km | 9 | 80 km | false | 2/6/1 | -- |
| `20260624_fukushima_aizu_m32_jma_eq5` | 14 km | 1 km | 6 | 10 km | false | 4/2/0 | -- |
| `20260625_iwate_offshore_m32_jma` | 19 km | 10 km | 10 | 10 km | false | 4/3/3 | -- |

Implemented a diagnostic-only JMA-style magnitude inverse:

- output keys:
  - `diagnostic_magnitude_jma_style`
  - `diagnostic_magnitude_supported`
  - `diagnostic_magnitude_station_count`
  - `diagnostic_magnitude_iqr`
  - `diagnostic_magnitude_depth_km`
  - `diagnostic_magnitude_depth_source`
- the inversion uses the existing JMA-style PGV/intensity attenuation equation
  and solves per station for an event magnitude, then reports the median and
  spread.
- when grouped depth is unsupported, the magnitude diagnostic uses 40 km as a
  neutral placeholder and records
  `diagnostic_magnitude_depth_source=default_40km_until_depth_supported`.

Current magnitude conclusion:

- The diagnostic is useful as a pipeline probe, but not ready as a production
  magnitude. On the two realtime M3-class events it underestimates by roughly
  `0.8..1.1` magnitude units because the GIF replay currently supplies weak
  realtime-intensity values and too few usable strong stations.
- Magnitude should be promoted only after either:
  - richer realtime intensity peak history is retained per station from the
    same NIED/KMoni GIF stream, or
  - JQ/JQuake-style GIF reverse-decoding adds stronger per-station amplitude
    evidence. Treat this as GIF-derived evidence, not as independent waveform
    PGA/PGV.

Reference algorithm reconnaissance:

- `SeriesNotFound/EQuake` public repository confirms the dependency chain but
  does not expose the core source-estimation implementation; its README points
  source estimation to `scratch-realtime-earthquake-viewer-page` and realtime
  shindo/acceleration extraction to JQuake.
- Operational interpretation from user clarification: EQuake,
  `scratch-realtime-earthquake-viewer-page`, and JQuake/JQ-style realtime
  shindo extraction should all be treated as NIED/KMoni GIF reverse-decoding
  workflows for this project. The algorithmic reference is JQ/JQuake-style GIF
  reverse decoding; `scratch-realtime-earthquake-viewer-page` is the public
  JS/SB3 carrier where part of that workflow is readable, not an independent
  "Scratch algorithm" source.
- The `scratch-realtime-earthquake-viewer-page` JS/SB3 carrier contains the
  relevant HYP workflow. Extracted procedure names include:
  - `HYP:震源検出`
  - `HYP:誤差レベル計算`
  - `HYP:誤差レベル比較`
  - `HYP:誤差レベル比較繰り返し`
  - `JMA2001距離近似`
- Extracted variables show it searches candidate longitude, latitude, depth,
  and origin time, builds time-difference lists, keeps an unarrived list, uses
  weights, counts S support, and compares squared error levels.

Next implementation direction:

1. Build a diagnostic `nied_gif_hyp_v1` scorer matching the JQ-style HYP shape
   visible in `scratch-realtime-earthquake-viewer-page`:
   candidate `(lat, lon, depth, originTime)` plus P/S travel-time residual,
   station-pair time-difference residual, unarrived-wave penalty, and distance
   weights.
2. Keep the current NIED hybrid location as production default while running
   `nied_gif_hyp_v1` in diagnostics on the same replay set.
3. Promote depth only when:
   - P/S support is real,
   - pairwise residual improves over the current grouped diagnostic,
   - missing-frame risk is not high,
   - and local reference replays do not regress offshore cases.
4. Revisit magnitude after HYP depth is stable and after the realtime
   GIF reverse-decoding pipeline can provide stronger station amplitude
   evidence. Do not mark JQ/JQuake-style GIF-derived values as independent
   physical PGA/PGV.

### `nied_gif_hyp_v1` diagnostic scorer implementation

Implemented the first diagnostic-only JQ-style HYP scorer inside the
existing NIED GIF hybrid output. Production coordinates, confidence, and
quality gates are unchanged; the new result is nested under
`diagnostics.nied_gif_hyp_v1`.

`nied_gif_hyp_v1` searches candidate:

- latitude;
- longitude;
- discrete depth `[10, 20, 40, 60, 80, 100, 140] km`;
- origin-time offset relative to the earliest trigger.

Scoring terms:

- P/S travel-time residual using GIF-derived trigger times;
- station-pair travel-time-difference residual;
- unarrived-wave penalty from nearby inactive/non-member GIF station records;
- simple distance weights that give closer early stations more influence;
- small depth regularization to avoid unconstrained deep drift.

The scorer reports:

- `supported`: conservative two-phase location support;
- `p_only_supported`: P-only timing fit only, not a trusted location/depth flag;
- `depth_supported`: stricter P/S depth support;
- candidate `latitude`, `longitude`, `depth_km`, and `origin_time`;
- phase counts/residuals, pair residuals, and unarrived penalty.

Synthetic validation:

- Added a unit test with mixed synthetic P and S arrivals. The HYP diagnostic
  recovers the source within the expected tolerance and marks both `supported`
  and `depth_supported` true.

Realtime GIF validation after implementation:

| Event | Hybrid final | HYP final | HYP error | HYP depth | Supported | P-only timing | Depth supported | P/S/O |
|---|---|---|---:|---:|---|---|---|---|
| Fukushima Hamadori M3.4 | `36.931, 140.556` | `36.670, 139.985` | 114.2 km | 100 km | false | true | false | 9/0/0 |
| Iwate offshore M3.6 | `40.411, 142.312` | `40.240, 141.871` | 33.1 km | 140 km | false | true | false | 5/0/0 |

Conclusion for realtime captures:

- HYP v1 correctly refuses to mark these final frames as supported because both
  are P-only (`S=0`).
- The P-only timing fit can look clean while the location is still wrong, so
  `p_only_supported` must be interpreted as "timing line fit only", not as
  usable hypocenter confidence.
- Do not promote HYP v1 to production scoring from these realtime captures.

Local reference replay validation:

| Case | Hybrid final error | Hybrid best error | HYP depth | Supported | Depth supported | P/S/O | Mean residual | Pair residual | Unarrived penalty |
|---|---:|---:|---:|---|---|---|---:|---:|---:|
| `20260620_iwate_offshore_m34_ref` | 63 km | 24 km | 100 km | false | false | 1/7/9 | 3.24 s | 1.23 s | 128.00 |
| `20260621_fukushima_offshore_m32_eq6` | 172 km | 126 km | 10 km | false | false | 3/0/8 | 24.58 s | 1.05 s | 11.73 |
| `20260622_iwate_east_offshore_m30_hinet` | 9 km | 9 km | 10 km | true | true | 5/12/1 | 1.31 s | 1.05 s | 40.81 |
| `20260622_iwate_offshore_m30_eq10` | 30 km | 19 km | 40 km | false | false | 1/9/3 | 1.26 s | 0.84 s | 17.66 |
| `20260622_kushiro_offshore_m30_jma` | 13 km | 2 km | 40 km | true | true | 4/5/0 | 0.65 s | 0.98 s | 1.39 |
| `20260622_tomakomai_south_offshore_m35_hinet` | 7 km | 3 km | 100 km | true | false | 11/2/1 | 1.15 s | 0.89 s | 115.96 |
| `20260623_tokachi_southeast_offshore_m34_hinet` | 74 km | 13 km | 100 km | false | false | 2/1/6 | 5.19 s | 0.73 s | 66.71 |
| `20260624_fukushima_aizu_m32_jma_eq5` | 14 km | 1 km | 10 km | false | false | 2/0/4 | 25.34 s | 0.06 s | 13.02 |
| `20260625_iwate_offshore_m32_jma` | 19 km | 10 km | 10 km | false | false | 1/0/9 | 34.24 s | 0.00 s | 4.89 |

Current HYP v1 interpretation:

- The scorer can find coherent two-phase solutions on some complete reference
  cases, so the HYP shape is worth continuing.
- It is not yet calibrated:
  - unarrived penalty is sometimes very large even for otherwise good cases;
  - P-only realtime fits still drift inland or to maximum depth;
  - depth support remains sparse and must stay diagnostic-only.

Next HYP calibration steps:

1. Separate `p_only_timing_fit` wording from any location-confidence wording in
   UI/debug reports.
2. Tune unarrived penalty against complete GIF reference cases so it rejects
   implausible inland candidates without punishing valid offshore/deep events.
3. Add an HYP-vs-hybrid replay report that records HYP candidate error when
   truth exists, but keep production on `nied_gif_hybrid_v1`.
4. Use the user-provided EQuake/JQ reports only as GIF-derived reference
   behavior; do not treat them as independent waveform truth.

Implemented the HYP-vs-hybrid replay report:

- tool: `tools/build_source_hyp_vs_hybrid_report.dart`;
- test: `test/source_hyp_vs_hybrid_report_test.dart`;
- JSON output:
  `.dart_tool/source_hyp_vs_hybrid_report/report.json`;
- Markdown output:
  `docs/baselines/source_hyp_vs_hybrid_report.generated.md`.

The report consumes existing
`.dart_tool/source_estimation_benchmark/*.reference.json` files and does not
re-decode GIFs.

Latest generated summary:

- cases: `10`;
- HYP supported: `2`;
- HYP depth supported: `2`;
- HYP P-only timing fits: `0`;
- HYP improved final error: `3`;
- median hybrid final error: `16.5 km`;
- median HYP final error: `103.8 km`;
- median HYP supported error: `5.4 km`;
- max unarrived penalty: `128.0`.

Report findings:

- `p_only_cases_must_not_promote_location`;
- `unarrived_penalty_needs_calibration`;
- `some_reference_cases_have_two_phase_depth_support`.

Safety adjustment after the first report:

- HYP `supported` and `depth_supported` now require unarrived penalty
  `<= 60.0`.
- This prevents a clearly regressed Tomakomai final-frame candidate
  (`97 km` HYP error, unarrived penalty `116`) from being marked supported.
- The rule is intentionally conservative and diagnostic-only. It is not a
  production promotion criterion.

Current report interpretation:

- HYP v1 is useful as a two-phase diagnostic filter: supported cases have low
  median error in the current sample.
- HYP v1 is not a general replacement: overall median final error is far worse
  than hybrid because unsupported/P-only cases can drift badly.
- The next calibration target is unarrived penalty scaling, not production
  switching.

### HYP unarrived-penalty gate calibration

Implemented a threshold calibration report for HYP supported/depth-supported
wording:

- tool: `tools/build_source_hyp_unarrived_calibration_report.dart`;
- test: `test/source_hyp_unarrived_calibration_report_test.dart`;
- JSON output:
  `.dart_tool/source_hyp_unarrived_calibration_report/report.json`;
- Markdown output:
  `docs/baselines/source_hyp_unarrived_calibration_report.generated.md`.

The report consumes the HYP-vs-hybrid report and does not rerun GIF replay. It
tests support-gate thresholds for `hypUnarrivedPenalty` while holding the HYP
candidate search result fixed. This means it calibrates the diagnostic
supported/depth-supported wording, not the candidate scoring weight.

Latest calibration summary:

- input cases: `10`;
- base two-phase eligible cases before unarrived gate: `4`;
- base depth-eligible cases before unarrived gate: `3`;
- recommended max unarrived penalty: `60.0`;
- recommendation reason: `max_supported_without_large_regression`;
- at threshold `60.0`:
  - supported: `3`;
  - depth supported: `3`;
  - improved: `3`;
  - regressed: `0`;
  - median HYP supported error: `4.0 km`;
  - median delta vs hybrid: `-5.0 km`.

Threshold sweep:

| Max unarrived penalty | Supported | Depth supported | Improved | Regressed | Verdict |
|---:|---:|---:|---:|---:|---|
| `0` | 0 | 0 | 0 | 0 | too strict |
| `2` | 1 | 1 | 1 | 0 | safe |
| `5` | 2 | 2 | 2 | 0 | safe |
| `10` | 2 | 2 | 2 | 0 | safe |
| `20` | 2 | 2 | 2 | 0 | safe |
| `40` | 2 | 2 | 2 | 0 | safe |
| `60` | 3 | 3 | 3 | 0 | safe |
| `80` | 3 | 3 | 3 | 0 | safe |
| `120` | 4 | 3 | 3 | 1 | unsafe |
| `160` | 4 | 3 | 3 | 1 | unsafe |

Findings:

- `recommended_threshold_60`;
- `high_thresholds_admit_regressed_hyp_candidates`;
- `low_thresholds_are_too_strict`;
- `calibration_is_gate_only_not_search_weight`.

Operational decision:

- Keep HYP `supported/depth_supported` gated at unarrived penalty `<= 60.0`.
- Do not use thresholds `>= 120` because they admit the clearly regressed
  Tomakomai candidate.
- The next calibration step should tune candidate scoring or candidate
  selection, not just the support gate, because unsupported HYP candidates still
  have very poor median error.

### JQ-style HYP reference extraction from `scratch-realtime-earthquake-viewer-page`

Separated the HYP source-estimation logic carried by
`scratch-realtime-earthquake-viewer-page` into a reviewable artifact:

- extractor: `tools/extract_scratch_hyp_algorithm.py`;
- source project:
  `.dart_tool/external_refs/scratch-realtime-earthquake-viewer-page/docs/assets/project.json`;
- readable extraction:
  `docs/reference/scratch_hyp_algorithm_extracted.md`;
- raw extracted block subset:
  `docs/reference/scratch_hyp_algorithm_blocks.json`.
- translated error-level notes:
  `docs/reference/scratch_hyp_error_level_notes.md`.

Important note: `scratch-realtime-earthquake-viewer-page` is the public
JS/SB3 carrier name. The upstream reference is not maintained as ordinary
hand-written JavaScript. The deployed `docs/index.js` is a TurboWarp build
artifact, while the readable logic is represented as Scratch blocks in
`project.json`. Therefore the extraction keeps the original procedure names,
argument names, and block structure rather than pretending it is executable JS.

Extracted HYP-related procedures include:

- `HYP:震源検出`;
- `HYP:誤差レベル計算`;
- `HYP:誤差レベル比較`;
- `HYP:誤差レベル比較繰り返し`;
- `JMA2001距離近似`;
- candidate/distance helpers such as `検出id4-2_適用id震源から候補選択`,
  `検出id距離計算`, `点-震源 距離計算`, and
  `緯度経度で距離km`.

Immediate reading from the extracted blocks:

- HYP starts from a provisional source and runs staged local search phases such
  as `start-h2`, `start-h10`, `start-h10-v50`, `start-h10-v10`, and `start-h60`.
- Error scoring is centralized through `HYP:誤差レベル計算`, with
  `JMA2001距離近似` and station/source distance helpers feeding the residual.
- This artifact is for reference and port planning only; production remains on
  `nied_gif_hybrid_v1`, with `nied_gif_hyp_v1` diagnostic-only.

The follow-up error-level notes translate `HYP:誤差レベル計算` and
`JMA2001距離近似` into a portable algorithm sketch. Key porting differences from
our current diagnostic HYP are:

- reference HYP uses the `d JMA2001走時表近似式` table approximation instead of
  fixed P/S speeds;
- origin time is derived as the mean of `observed - predictedTravelTime`;
- final error is weighted residual variance multiplied by an S-support factor
  and sample-size penalty;
- unarrived-wave penalty is count-like in the reference, whereas our current
  diagnostic HYP uses a continuous overdue-seconds penalty.

Implementation started:

- added `lib/core/source_estimation/jma2001_travel_time_approximation.dart`;
- added `test/jma2001_travel_time_approximation_test.dart`;
- verified the JQ-style JMA2001 coefficient table shape from the
  `scratch-realtime-earthquake-viewer-page` carrier:
  `1704 = 4 * 71 * 6`;
- verified the depth-bin index against the existing `assets/travel_times.json`
  JMA2001 table: `round(depthKm / 10) * 6`, not `1 + round(...)`;
- added opt-in `emitJma2001HypExperiment` to `NiedGifHybridSourceEstimator`.

When the switch is enabled, the estimator emits
`diagnostics.nied_gif_hyp_jma2001_experiment` using the JMA2001 polynomial travel
time model. The default is `false` to avoid doubling real-time HYP grid-search
cost before replay metrics justify it.

### HYP JMA2001 experiment replay report

Added a small opt-in experiment report for comparing the current fixed-speed
diagnostic HYP scorer, the JMA2001-travel-time scorer, and the first
JQ-style scoring experiment:

- report tool: `tools/build_source_hyp_jma2001_experiment_report.dart`;
- test and opt-in replay generator:
  `test/source_hyp_jma2001_experiment_report_test.dart`;
- generated reference input directory:
  `.dart_tool/source_hyp_jma2001_experiment_benchmark`;
- generated JSON:
  `.dart_tool/source_hyp_jma2001_experiment_report/report.json`;
- generated Markdown:
  `docs/baselines/source_hyp_jma2001_experiment_report.generated.md`.

The generator only runs when explicitly requested:

```powershell
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true
```

It uses existing local capture packages and does not redownload historical GIFs.

Latest four-case experiment summary:

- cases: `4`;
- JMA2001 diagnostic present: `4`;
- JQ-style scoring diagnostic present: `4`;
- baseline fixed-speed HYP supported: `3`;
- JMA2001 HYP supported: `3`;
- JQ-style HYP supported: `3`;
- JMA2001 improved vs fixed-speed HYP: `1`;
- JMA2001 regressed vs fixed-speed HYP by more than 10 km: `0`;
- JQ-style improved vs fixed-speed HYP: `2`;
- JQ-style regressed vs fixed-speed HYP by more than 10 km: `0`;
- median hybrid final error: `8.0 km`;
- median fixed-speed HYP error: `5.4 km`;
- median JMA2001 HYP error: `8.3 km`;
- median JQ-style HYP error: `5.7 km`;
- median JMA2001-minus-fixed HYP delta: `0.0 km`;
- median JQ-style-minus-fixed HYP delta: `-2.7 km`.

Per-case result:

| Case | Hybrid | HYP fixed | HYP JMA2001 | HYP JQ-style | JQ-fixed | Fixed/JMA/JQ supported |
|---|---:|---:|---:|---:|---:|---|
| `20260622_iwate_east_offshore_m30_hinet` | `9.0` | `4.0` | `9.8` | `9.8` | `+5.8` | true / true / true |
| `20260622_kushiro_offshore_m30_jma` | `13.0` | `6.9` | `6.9` | `1.4` | `-5.5` | true / true / true |
| `20260622_tomakomai_south_offshore_m35_hinet` | `7.0` | `97.0` | `91.1` | `17.9` | `-79.1` | false / false / false |
| `20260622_wakayama_south_m25_hinet` | `3.0` | `1.5` | `1.5` | `1.5` | `0.0` | true / true / true |

Interpretation:

- Merely swapping the travel-time model from fixed P/S speeds to JMA2001 does
  not improve the current diagnostic HYP scorer enough to promote it.
- The first JQ-style scorer is more promising than the plain JMA2001 swap:
  it sharply improves the Tomakomai bad candidate (`97.0 km -> 17.9 km`) and
  improves Kushiro (`6.9 km -> 1.4 km`) without creating a >10 km regression in
  this four-case set.
- The first JQ-style unarrived gate calibration uses `80` for the count-like
  penalty, while the fixed-speed/JMA2001 continuous penalty gate remains `60`.
  This keeps the otherwise good Iwate JQ-style candidate supported
  (`unarrived_penalty=62`, max supported `80`) without admitting Tomakomai,
  because Tomakomai still has no P support (`P/S/O = 0/13/1`).
- A first staged local-search probe was added to the JQ-style diagnostic path:
  `search.stages` now records `coarse`, `fine`, and a `jq_refine` candidate.
  The `jq_refine` candidate is intentionally recorded with `applied=false`.
  On Tomakomai it reduces numeric score/residual but keeps the unhealthy
  all-S phase interpretation (`P/S/O = 0/13/1`), so applying it would not solve
  the phase-origin problem.
- A `phase_balance_penalty` diagnostic is emitted for JQ-style candidates.
  It is not yet applied to candidate selection because the first attempt to
  hard-penalize all-S candidates made Tomakomai look supported while moving the
  location farther from truth. For the current Tomakomai final JQ candidate the
  diagnostic penalty is `145.2`, explicitly marking the all-S interpretation as
  unsafe.
- The JQ-style scorer is still not promotion-ready. Tomakomai improves sharply
  but remains `17.9 km` from truth and has phase-class imbalance, so the next
  step is staged local search and phase/origin semantics, not production
  switching.
- The experiment is still useful because it confirms the JQ-style JMA2001 table
  from the `scratch-realtime-earthquake-viewer-page` carrier is wired into
  replay diagnostics and that JQ-style scoring changes candidate selection in
  the expected direction.
- The next porting step should add staged local-search behavior and then broaden
  JQ-style gate validation beyond this four-case core set.
- Production coordinates remain `nied_gif_hybrid_v1`; `nied_gif_hyp_v1`,
  `nied_gif_hyp_jma2001_experiment`, and
  `nied_gif_hyp_jq_scoring_experiment` remain diagnostics.

### EQuake phase-origin reference comparison

Added a reference-only comparison packet for the user-provided local EQuake/JQ
text folders:

- structured reference data:
  `docs/data/equake_phase_origin_reference_cases.json`;
- report tool:
  `tools/build_source_hyp_equake_reference_comparison.dart`;
- test:
  `test/source_hyp_equake_reference_comparison_test.dart`;
- generated JSON:
  `.dart_tool/source_hyp_equake_reference_comparison/report.json`;
- generated Markdown:
  `docs/baselines/source_hyp_equake_reference_comparison.generated.md`.

The packet is explicitly `referenceOnly`, `notCatalogTruth`, and
`gifDerived`; it must not be used as frozen metric truth or to switch
production coordinates.

Current comparison summary:

- cases: `3`;
- HYP/JQ benchmark matched: `1`;
- current-capture replay matched: `1`;
- missing HYP/JQ benchmark rows: `2`;
- JQ-style near EQuake within 20 km: `1`;
- JQ-style zero-P mismatch against EQuake P support: `1`.

Per-case comparison:

| EQuake packet | EQ final | Catalog/reference error | EQ P/S/O | Local match | Our comparison | Finding |
|---|---:|---:|---:|---|---|---|
| `equake_20260630_iwate_offshore_m38_report17` | `40.30N 142.53E / 13 km` | `11.4 km` | `58/37/18` | none yet | no HYP row | missing matched replay; do not pair with the earlier `20260630_iwate_offshore_m36` capture |
| `equake_20260630_fukushima_hamadori_m36_report10` | `37.35N 140.97E / 67 km` | `3.0 km` | `33/75/21` | `20260630_fukushima_hamadori_m34` current capture | current production final is `59.3 km` from EQuake reference | needs a HYP/JQ experiment replay row |
| `equake_20260622_tomakomai_south_offshore_m29_report10` | `42.14N 141.22E / 118 km` | `13.5 km` | `10/33/6` | `20260622_tomakomai_south_offshore_m35_hinet` HYP benchmark | JQ-style candidate is `4.4 km` from EQuake but `P/S/O = 0/13/1` | location is close; phase-origin assignment is unhealthy |

Interpretation:

- The Tomakomai candidate confirms the next algorithm target: keep the useful
  JMA2001/JQ-style location search, but repair phase-origin semantics so an
  all-S solution cannot win when EQuake/JQ-style reference evidence keeps a
  stable nonzero P cluster (`10P`) through reports 5-10.
- The Fukushima packet is the healthy deep-source contrast: EQuake starts
  P-dominant and becomes S-rich (`33/75/21`) while retaining stable P support.
  Our current production replay for that capture is far from the EQuake
  reference, so it should be promoted into the HYP/JQ experiment benchmark
  before tuning gates from it.
- The Iwate packet is a shallow/offshore contrast: reports 1-9 are almost
  P-only, then later reports add S support. This should prevent overcorrecting
  the algorithm with a hard rule that penalizes early P-only solutions.

Next implementation target remains diagnostic-only:

1. generate HYP/JQ experiment rows for the matched Fukushima current capture
   and for the Iwate 12:22 UTC+8 packet if/when its local replay package is
   found;
2. add phase-origin diagnostics for candidate selection:
   `p_origin_cluster_count`, `s_origin_cluster_count`,
   `p_origin_mean_seconds`, `s_origin_mean_seconds`,
   `phase_origin_cluster_gap_seconds`, and per-phase origin spread;
3. prefer candidates with a plausible P origin cluster and later S cluster,
   instead of applying a blunt phase-balance penalty.

Initial phase-origin diagnostics have now been added to
`nied_gif_hyp_jq_scoring_experiment` and exported through the JMA2001/HYP report
row fields:

- `phase_origin_model`;
- `p_origin_cluster_count`, `s_origin_cluster_count`;
- `p_origin_mean_s`, `s_origin_mean_s`;
- `p_origin_spread_s`, `s_origin_spread_s`;
- `phase_origin_mean_gap_s`.

These fields are diagnostic-only and do not affect candidate selection. The
regenerated Tomakomai benchmark now exposes the problem directly:

- EQuake final phase reference: `P/S/O = 10/33/6`;
- our JQ-style candidate: `P/S/O = 0/13/1`;
- our JQ-style origin clusters: `P = 0`, `S = 2`;
- `p_origin_mean_s = null`, `s_origin_mean_s = -39.153...`;
- `phase_balance_penalty = 145.2`.

This confirms that the next scoring change should recover/retain a plausible P
origin cluster before accepting a deep S-rich candidate. It should not simply
apply the existing phase-balance penalty as a hard score term, because the first
attempt made Tomakomai look supported while worsening the location.

Correction after re-reading `scratch-realtime-earthquake-viewer-page` HYP:

- the inspected reference algorithm does not choose P/S by first clustering
  P-origin and S-origin candidates;
- it chooses S only when `currentTime > firstDetectedTime + 15s` and the
  detection point/station has an S flag; otherwise it uses P;
- it then derives origin time as the mean of
  `observedStationTime - selectedPhaseTravelTime`;
- S support reduces the final error multiplier, and unarrived P waves add a
  count-like penalty.

Therefore `p_origin_cluster_count` / `s_origin_cluster_count` remain useful
diagnostics for our own failures, but they are not the direct porting target
from `scratch-realtime-earthquake-viewer-page`. A follow-up block audit confirmed
that the reference `stationHasSFlag` is not an external GIF/S-pick field. It is
derived per candidate in `ten:推定用`:

- `+7`: predicted P arrival =
  `candidateOriginTime + JMA2001(..., P波=true, 走時計算=true)`;
- `+8`: predicted S arrival =
  `candidateOriginTime + JMA2001(..., P波=false, 走時計算=true)`;
- `+6`: S flag =
  `abs(observedTime - predictedSArrival) <
   abs(observedTime - predictedPArrival)`;
- HYP uses S only when
  `currentTime > firstDetectedTime + 15s` and `+6` is truthy.

So the next faithful porting step is not to search for a hidden data field in
our GIF decode. It is to keep deriving this flag from each candidate's predicted
P/S arrivals, then run the diagnostic phase-gated scorer against the local
Iwate/Fukushima/Tomakomai reference packets. Do not hard-promote the P-origin
cluster idea as "the reference algorithm".

Implemented diagnostic-only scorer alignment:

- `nied_gif_hyp_jq_scoring_experiment.scoring_model` is now
  `jq_reference_candidate_s_flag_origin_variance_v1`;
- `station_s_flag_model` records
  `candidate_predicted_s_closer_than_p_after_15s_v1`;
- S phase selection is gated by
  `observedAt - earliestObserved > 15s` and the per-candidate derived
  `abs(observed - S_pred) < abs(observed - P_pred)` flag;
- production coordinates remain unchanged.

Regenerated the JMA2001/HYP report from the five local benchmark references:

- baseline/JMA/JQ supported: `3 / 3 / 3`;
- median baseline/JMA/JQ HYP error: `6.9 / 9.8 / 17.9 km`;
- Kushiro regressed under this simple gate:
  JQ `1.4 km, 3/5/1, supported=true` became
  `23.5 km, 8/0/1, supported=false`;
- Tomakomai stayed near the EQuake location but still has zero P support:
  `17.9 km`, `0/13/1`, unsupported vs EQuake final `10/33/6`;
- Fukushima remains a low-coverage counterexample:
  `16/66` decoded frames and JQ `101.5 km`, `6/3/3`.

Interpretation: the block-level `stationHasSFlag` meaning is now confirmed, but
our first port of the 15 s gate uses the final benchmark `observedAt` as a
proxy for the reference cloud time. That is too blunt for early/partial replay
cases such as Kushiro. The next algorithm step is to model the gate with
per-frame/per-detection-id time semantics before tuning P/S support recovery.

Follow-up inspection of the reference state machine found the main hidden
inputs that influence this flag:

- station observed time is `ten:推定用 +1`, and may come from `+5` pre-trigger
  cache, a nearby 7-point older trigger, or the current cloud time;
- station detection membership is `ten:推定用 +3`, mirrored into `grid:検出id`;
- station distance cache is `ten:推定用 +4`, updated by `検出id距離計算`;
- `+7/+8/+6` are recomputed by `推定用tenPS時間計算`, either on station id
  membership changes or via `検出id_推定PS時間id別再計算`;
- the P/S prediction source comes from `4-4 検出id震源要素`:
  `+2 lon`, `+3 lat`, `+4 depth`, `+5 origin`;
- the 15 s S gate uses `4-3 検出id別情報[(offset + 3)]` as
  `@hyp:最初検知時刻`;
- under 10 s, or before a source cache exists, HYP seeds the provisional source
  from the first detected point with depth `10 km` and origin
  `firstDetectionTime - 2 s`.

Therefore a more faithful Dart diagnostic must not only score final replay
records. It needs to export or reconstruct per-frame equivalents for:

1. station `+1/+2/+3/+4/+5/+6/+7/+8`;
2. detection id `4-3` first-detection time, count, max distance, error/staleness;
3. detection source cache `4-4 +2/+3/+4/+5`;
4. the moments when membership changes trigger `推定用tenPS時間計算`.

Only after those are visible should we retune Tomakomai P-support recovery or
Kushiro early-frame behavior.

Implemented the first visibility layer as diagnostic-only
`jq_reference_state_proxy_v1` inside
`nied_gif_hyp_jq_scoring_experiment`. It exports:

- a proxy `4-3` detection id state: current age, first-detection time proxy,
  active station count;
- a proxy `4-4` source cache: longitude, latitude, depth, origin time;
- per-station `ten_plus_1/+2/+3/+4/+5/+6/+7/+8` rows for the most suspicious
  32 stations, including P/S predicted arrivals, residuals, derived `+6`, and
  phase after the 15 s gate;
- counts for derived S flags, gated S, accepted P/S, and other.

Regenerated the five local HYP/JMA benchmark references and reports with this
proxy. The stricter reference-gated JQ diagnostic is now clearly
diagnostic-only:

- baseline/JMA/JQ supported: `3 / 3 / 1`;
- median baseline/JMA/JQ HYP error: `6.9 / 9.8 / 23.5 km`;
- Fukushima comparison vs EQuake regressed to `134.7 km`, `12/0/0`, because
  the incomplete benchmark frame is now P-only under the gate.

Initial proxy readouts:

- Tomakomai final frame:
  `ten_plus_6_s_closer_than_p_count=14`, `gated_s_count=14`,
  `accepted_p_count=0`, `accepted_s_count=13`, `other_count=1`, gate age
  `29.0 s`. This proves the all-S failure is already present in the derived
  station state, not merely in the final support gate.
- Kushiro final frame:
  `ten_plus_6_s_closer_than_p_count=1`, `gated_s_count=0`,
  `accepted_p_count=8`, `accepted_s_count=0`, `other_count=1`, gate age
  `10.0 s`. This explains the current P-only regression: the simple proxy
  applies the 15 s gate before the reference state machine would have enough
  later-stage context.
- Fukushima incomplete benchmark:
  `ten_plus_6_s_closer_than_p_count=0`, `gated_s_count=0`,
  `accepted_p_count=12`, `accepted_s_count=0`, `other_count=0`, gate age
  `13.0 s`. Keep this as a low-coverage/cadence counterexample, not a tuning
  target.

Next algorithm step: promote the proxy from "best-candidate snapshot" to a
per-frame state reconstruction that tracks `ten_plus_5`/7-point older trigger
fallback and detection-id membership changes. Only then retest Tomakomai P
support recovery and Kushiro early behavior.

Added a second proxy layer for reference-like station timing:

- `ten_plus_5_pretrigger_cache_s`: best-effort from station observation history
  before the station's current first trigger/rise;
- `nearest_7_old_trigger_time_s`: best-effort nearest-seven older trigger
  fallback;
- `ten_plus_1_reference_like_time_s` and
  `ten_plus_1_reference_like_source`;
- reference-like P/S residuals, `reference_like_ten_plus_6_s_closer_than_p`,
  and reference-like phase after the 15 s gate.

Regenerated the five local references again. Initial readout:

- Tomakomai:
  raw proxy `S closer=14`, `gated S=14`, `accepted P/S/O=0/13/1`.
  Reference-like timing with the provisional `+5` proxy changes this to
  `S closer=7`, `gated S=7`, `accepted P/S/O=2/2/10`.
  This is useful but not yet faithful: the naive `+5` proxy pulls several
  station times before the event-local earliest trigger (negative local
  seconds), so it reveals that the missing piece is the exact reference
  write/clear timing for `+5`, not simply "use first observed frame".
- Kushiro:
  raw and reference-like remain P-only under the 15 s gate:
  `accepted P/S/O=8/0/1`; `+5` proxy appears on 3 stations but does not change
  S support because gate age remains `10 s`.
- Wakayama:
  raw/reference-like remain P-only under the gate:
  `accepted P/S/O=9/0/2`; `+5` proxy appears on 4 stations.
- Fukushima incomplete benchmark:
  no `+5` or nearest-seven fallback was available; remains
  `accepted P/S/O=12/0/0`.

Next step narrows further: reconstruct `ten_plus_5` as a stateful field with
the same write and clear conditions as `検出id2_各点の許可idと推定用をセット`,
instead of deriving it after the fact from generic observation history.

Implemented the first stateful `ten_plus_5` proxy:

- writes `+5` only while the station history is rising/triggered;
- clears `+5` when the station is no longer active/rising;
- limits retained `+5` to a 20 s pre-trigger window;
- exports `ten_plus_5_pretrigger_cache_model =
  stateful_rising_frame_write_clear_proxy_v1`.

Regenerated local references again. The stateful proxy improved the false
early-time behavior but did not recover Tomakomai P support:

- Tomakomai:
  raw proxy stays `S closer=14`, `accepted P/S/O=0/13/1`;
  reference-like stateful `+5` is now
  `S closer=14`, `accepted P/S/O=0/5/9`.
  This means `+5` timing can reduce over-confident S acceptance, but the
  all-S phase assignment is still being driven by the selected source cache
  and/or station membership, not by `+5` alone.
- Kushiro:
  unchanged at reference-like `accepted P/S/O=8/0/1`; the 15 s gate remains
  closed.
- Wakayama:
  unchanged at reference-like `accepted P/S/O=9/0/2`.
- Fukushima incomplete benchmark:
  unchanged at reference-like `accepted P/S/O=12/0/0`.

Next step: reconstruct detection-id membership and source-cache evolution
(`ten_plus_3`, `4-3`, `4-4`) per frame, then recompute `+7/+8/+6` at the
moments where the reference calls `推定用tenPS時間計算`. The current snapshot still
uses the final selected source cache for every station, which likely explains
why Tomakomai remains all-S.

### Fukushima Hamadori 2026-06-30 HYP/JQ benchmark intake

Added a surface-image-only benchmark fixture for the user-provided Fukushima
Hamadori EQuake/Hi-net packet:

- fixture:
  `test/fixtures/source_estimation/fukushima_hamadori_m35_20260630_hinet_equake10.json`;
- capture directory:
  `C:/Users/Rhythm/Desktop/nied_capture_20260630_110914/raw/jma_s`;
- input mode:
  `SourceEstimationBenchmarkInputMode.surfaceImageOnly`;
- reference link:
  `docs/data/equake_phase_origin_reference_cases.json`.

The test support manifest resolver now accepts Windows absolute capture paths,
so the local replay can be referenced without copying the GIFs into `tmp/`.

Regenerated HYP/JMA2001/JQ experiment summary after adding this case:

- cases: `5`;
- baseline fixed-speed HYP supported: `3`;
- JMA2001 HYP supported: `3`;
- JQ-style HYP supported: `4`;
- JQ-style improved vs fixed-speed HYP: `3`;
- JQ-style >10 km regression count: `0`;
- median fixed/JMA/JQ HYP error: `6.9 / 9.8 / 9.8 km`.

Important caveat: the Fukushima local replay is incomplete for this benchmark
window:

- requested frames: `66`;
- decoded frames: `16`;
- decoded coverage: `24.2%`;
- visible cadence has large gaps, e.g. `12:08:53`, `12:09:05-09`,
  `12:09:21-25`, `12:09:36-40` JST.

The generated reports now explicitly flag this:

- HYP report row findings:
  `low_decoded_frame_coverage`,
  `jq_scoring_supported_large_error`;
- EQuake comparison row findings:
  `jq_scoring_far_from_equake_40km`,
  `jq_scoring_supported_far_from_equake_40km`,
  `hyp_benchmark_low_decoded_frame_coverage`.

Fukushima current result from the incomplete replay:

| Method | Final error vs Hi-net | Error vs EQuake reference | P/S/O | Supported |
|---|---:|---:|---:|---|
| production hybrid | `61.0 km` | `59.3 km` in current-capture report | n/a | n/a |
| fixed-speed HYP | `118.1 km` | n/a | `9/0/3` | false |
| JMA2001 HYP | `118.1 km` | n/a | `9/0/3` | false |
| JQ-style HYP | `101.5 km` | `99.0 km` | `6/3/3` | true |

Interpretation:

- This is useful as a capture-cadence/low-coverage counterexample, not as a
  clean algorithm tuning case.
- The JQ-style support gate can still admit a large-error case when the replay
  has sparse/gapped frames. This should be handled first by benchmark/report
  gating and later by runtime capture-quality diagnostics if the same cadence
  appears live.
- Phase-origin cluster count alone is not a safe support-gate fix: good cases
  also have multiple small clusters. Example regenerated JQ-style rows:
  Iwate east `P/S clusters = 2/2`, Kushiro `2/3`, Wakayama `2/2`, while
  Fukushima incomplete is also `2/2`.
- Therefore no hard phase-origin coherence support gate was applied in this
  step. The next algorithmic target remains Tomakomai-style P-cluster recovery,
  while Fukushima should wait for a more complete replay/capture before being
  used for gate calibration.

### JQ/HYP diagnostic method bridge replay run

Correction after wiring the JQ-style HYP diagnostic into replay as an
independent method:

- method id: `nied_gif_hyp_jq_scoring_experiment`;
- source: promoted from the per-frame `nied_gif_hybrid_v1` diagnostics;
- scope: diagnostic-only, not a production coordinate switch;
- bridge model:
  `hybrid_diagnostics_promoted_to_independent_method_frame_v1`.

This matters because the previous reports could inspect the final HYP/JQ
diagnostic payload, but replay summaries could not treat it like a real method.
Now each decoded frame can carry a separate JQ/HYP estimate, with its own
error, jump, runtime, depth, origin time and P/S/O diagnostics.

Validation run:

```powershell
flutter analyze test\support\source_estimation_benchmark.dart
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true
```

Result: passed. The generation rebuilt the 5 local HYP/JMA2001/JQ benchmark
references and reports.

Latest independent-method replay readout:

| Case | Decoded | Estimates | Median error | P90 error | Final error | Final lat/lon | Depth | Supported | P/S/O | Residual |
|---|---:|---:|---:|---:|---:|---|---:|---|---:|---:|
| `20260622_iwate_east_offshore_m30_hinet` | `151/151` | `39` | `10.0 km` | `36.0 km` | `10.0 km` | `39.9381,142.2385` | `10 km` | true | `5/11/2` | `1.35 s` |
| `20260622_kushiro_offshore_m30_jma` | `151/151` | `44` | `23.5 km` | `40.6 km` | `24.0 km` | `42.6888,144.0190` | `10 km` | false | `8/0/1` | `1.93 s` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `151/151` | `42` | `2.0 km` | `38.8 km` | `18.0 km` | `42.1604,141.1736` | `140 km` | false | `0/13/1` | `1.10 s` |
| `20260622_wakayama_south_m25_hinet` | `151/151` | `43` | `37.0 km` | `37.0 km` | `37.0 km` | `33.2559,135.8636` | `20 km` | false | `9/0/2` | `1.59 s` |
| `20260630_fukushima_hamadori_m35_hinet_equake10` | `16/66` | `7` | `137.0 km` | `137.4 km` | `137.0 km` | `36.4304,139.9848` | `140 km` | false | `12/0/0` | `0.44 s` |

Updated summary from
`.dart_tool/source_hyp_jma2001_experiment_report/report.json`:

- cases: `5`;
- baseline/JMA/JQ supported: `3 / 3 / 1`;
- median baseline/JMA/JQ HYP error: `6.9 / 9.8 / 23.5 km`;
- JQ-style improved vs fixed-speed HYP: `1`;
- JQ-style regressed vs fixed-speed HYP by more than 10 km: `3`.

Interpretation:

- The algorithm is now wired into replay as a runnable method, so future
  changes can be measured frame-by-frame rather than by final diagnostic
  snapshots only.
- It is still not promotion-ready. The current bridge reuses the selected
  diagnostic candidate and does not yet reconstruct the full reference runtime
  state machine.
- Tomakomai shows the most useful failure signature: median error can be very
  good (`2 km`), but the final source cache drifts to an all-S solution
  (`0/13/1`) at `140 km` depth and ends `18 km` away. This strongly points to
  missing detection-id/source-cache evolution rather than just a travel-time
  table issue.
- Kushiro and Wakayama remain P-only under the current gate/candidate state,
  which means simply tightening S gating would not recover the reference
  behavior.
- Fukushima remains a low-coverage replay (`16/66` frames) and should stay a
  cadence/capture-quality counterexample, not a tuning target.

Next implementation target:

1. Build a real diagnostic state-machine runner instead of the bridge:
   maintain `ten_plus_1..8`, `4-3`, and `4-4` across frames.
2. Recompute `+7/+8/+6` only at the same semantic moments as the reference
   calls `推定用tenPS時間計算`.
3. Preserve multiple detection ids / memberships instead of collapsing all
   stations to one proxy id.
4. Re-run the same 5 cases and compare the new state-machine method against
   the bridge method.

### JQ reference HYP state-machine v0

Added the first diagnostic state-machine method:

- method id: `jq_reference_hyp_state_machine_experiment`;
- model: `jq_reference_state_machine_v0_bridge_cache`;
- scope: diagnostic-only;
- source cache: still supplied by the bridge
  `nied_gif_hyp_jq_scoring_experiment`;
- station state: maintained independently across replay frames.

The v0 runner now keeps per-frame/per-station state equivalent to the first
layer of the Scratch/JQ HYP runtime:

- `4-3` detection id proxy:
  - one detection id for this first layer;
  - `first_detection_time_s`;
  - `current_age_s`;
  - station-state count.
- `4-4` source cache proxy:
  - `plus_2_longitude`;
  - `plus_3_latitude`;
  - `plus_4_depth_km`;
  - `plus_5_origin_time_s`;
  - revision counter.
- `ten_plus_1..8` station fields:
  - observed/reference-like time;
  - last update time;
  - detection id membership;
  - distance cache;
  - stateful `+5` pretrigger cache;
  - `+6` S-closer-than-P flag;
  - predicted P/S arrivals.

Important correction during implementation:

- The first draft accidentally included all accumulated event station records,
  producing full-network P/S/O counts such as `22/20/1588`.
- The runner now limits state updates to `source_trigger_member_ids` when
  available, or triggered/active-like records as fallback.
- Exported station rows are capped at `16` per frame to keep replay references
  manageable.

Validation run:

```powershell
flutter analyze test\support\source_estimation_benchmark.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_estimation_baseline_test.dart --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --concurrency=1
```

Result: passed. `dart format test\support\source_estimation_benchmark.dart`
was attempted but the local Windows Dart process repeatedly hung without
output; the stuck Dart process was terminated. Analyzer and tests passed after
that.

Latest bridge vs state-machine readout:

| Case | Method | Estimates | Median error | Final error | Depth | P/S/O | Residual | S-closer | +5 cache | Recomputed |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `20260622_iwate_east_offshore_m30_hinet` | bridge | `39` | `10.0 km` | `10.0 km` | `10 km` | `5/11/2` | `1.35 s` | - | - | - |
| `20260622_iwate_east_offshore_m30_hinet` | state-machine v0 | `103` | `10.0 km` | `10.0 km` | `10 km` | `5/11/9` | `13.02 s` | `13` | `14` | `25` |
| `20260622_kushiro_offshore_m30_jma` | bridge | `44` | `23.5 km` | `24.0 km` | `10 km` | `8/0/1` | `1.93 s` | - | - | - |
| `20260622_kushiro_offshore_m30_jma` | state-machine v0 | `110` | `24.0 km` | `24.0 km` | `10 km` | `12/7/14` | `2.91 s` | `11` | `6` | `33` |
| `20260622_tomakomai_south_offshore_m35_hinet` | bridge | `42` | `2.0 km` | `18.0 km` | `140 km` | `0/13/1` | `1.10 s` | - | - | - |
| `20260622_tomakomai_south_offshore_m35_hinet` | state-machine v0 | `92` | `18.0 km` | `18.0 km` | `140 km` | `3/23/11` | `3.43 s` | `27` | `8` | `37` |
| `20260622_wakayama_south_m25_hinet` | bridge | `43` | `37.0 km` | `37.0 km` | `20 km` | `9/0/2` | `1.59 s` | - | - | - |
| `20260622_wakayama_south_m25_hinet` | state-machine v0 | `105` | `37.0 km` | `37.0 km` | `20 km` | `11/1/15` | `17.26 s` | `1` | `11` | `27` |
| `20260630_fukushima_hamadori_m35_hinet_equake10` | bridge | `7` | `137.0 km` | `137.0 km` | `140 km` | `12/0/0` | `0.44 s` | - | - | - |
| `20260630_fukushima_hamadori_m35_hinet_equake10` | state-machine v0 | `7` | `137.0 km` | `137.0 km` | `140 km` | `12/0/4` | `6.80 s` | `3` | `4` | `16` |

Interpretation:

- v0 does not move the source because it deliberately reuses the bridge
  source cache. It is not a candidate-search implementation yet.
- The new value is observability: the replay now exposes how stateful
  `ten_plus_1..8` evolves across frames and where it diverges from the bridge
  final diagnostic.
- Tomakomai is especially useful: bridge final is all-S (`0/13/1`), while the
  state-machine layer sees accumulated member-state support as `3/23/11`.
  That confirms the next bug is not only "S flag exists"; it is source-cache
  and membership evolution, plus when stale station states should be cleared or
  split into another detection id.

Next implementation target:

1. Stop using the bridge source cache for v1.
2. Own the candidate search inside the state machine.
3. Apply reference-like source-cache update timing:
   seed from first detection when age `<10 s`, then update `4-4` through staged
   local search.
4. Add station membership aging/clear rules so stale `ten_plus_3` members do
   not inflate residuals.

### JQ reference HYP state-machine v1 owned source cache

Implemented the next diagnostic step: the state-machine method now owns its
`4-4` source cache instead of copying the bridge candidate.

- method id remains: `jq_reference_hyp_state_machine_experiment`;
- model: `jq_reference_state_machine_v1_owned_cache`;
- the bridge `nied_gif_hyp_jq_scoring_experiment` is retained only as debug
  comparison;
- normal replay/baseline paths do not instantiate the JQ methods unless the
  JQ diagnostic is present, so production/default benchmark runtime remains
  lightweight.

v1 source-cache behavior:

- if no stable search is possible, seed from first detected station:
  depth `10 km`, origin `firstDetection - 2 s`;
- after the early window, run a compact owned grid search around the current
  state-machine cache / member centroid;
- candidate score uses JMA2001 P/S origin clustering, 15 s S gate, residual
  support count, other-count penalty, shallow depth preference, and an all-S
  overfit penalty;
- after the owned search updates `4-4`, all member station `+7/+8/+6` fields
  are recomputed from the owned cache.

Validation run:

```powershell
flutter analyze test\support\source_estimation_benchmark.dart
flutter test test\source_estimation_baseline_test.dart --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --concurrency=1
```

Result: passed.

Latest bridge vs state-machine v1 readout:

| Case | Method | Median error | P90 error | Final error | Final lat/lon/depth | P/S/O | Residual | Cache score |
|---|---|---:|---:|---:|---|---:|---:|---:|
| `20260622_iwate_east_offshore_m30_hinet` | bridge | `10.0 km` | `36.0 km` | `10.0 km` | `39.9381,142.2385,10` | `5/11/2` | `1.35 s` | - |
| `20260622_iwate_east_offshore_m30_hinet` | state-machine v1 | `13.0 km` | `41.0 km` | `13.0 km` | `39.9483,142.4885,40` | `5/13/7` | `12.52 s` | `24.12` |
| `20260622_kushiro_offshore_m30_jma` | bridge | `23.5 km` | `40.6 km` | `24.0 km` | `42.6888,144.0190,10` | `8/0/1` | `1.93 s` | - |
| `20260622_kushiro_offshore_m30_jma` | state-machine v1 | `7.0 km` | `7.0 km` | `7.0 km` | `42.9581,144.0098,10` | `23/2/8` | `2.02 s` | `14.92` |
| `20260622_tomakomai_south_offshore_m35_hinet` | bridge | `2.0 km` | `38.8 km` | `18.0 km` | `42.1604,141.1736,140` | `0/13/1` | `1.10 s` | - |
| `20260622_tomakomai_south_offshore_m35_hinet` | state-machine v1 | `14.0 km` | `43.5 km` | `14.0 km` | `42.1206,141.2009,10` | `26/0/11` | `7.54 s` | `25.24` |
| `20260622_wakayama_south_m25_hinet` | bridge | `37.0 km` | `37.0 km` | `37.0 km` | `33.2559,135.8636,20` | `9/0/2` | `1.59 s` | - |
| `20260622_wakayama_south_m25_hinet` | state-machine v1 | `167.0 km` | `167.0 km` | `167.0 km` | `32.8174,137.3336,10` | `17/0/10` | `11.13 s` | `27.23` |
| `20260630_fukushima_hamadori_m35_hinet_equake10` | bridge | `137.0 km` | `137.4 km` | `137.0 km` | `36.4304,139.9848,140` | `12/0/0` | `0.44 s` | - |
| `20260630_fukushima_hamadori_m35_hinet_equake10` | state-machine v1 | `165.0 km` | `191.0 km` | `165.0 km` | `36.2784,139.7208,140` | `12/3/1` | `6.03 s` | `9.03` |

Interpretation:

- v1 proves the state machine can now move the source independently:
  `4-4` no longer mirrors the bridge.
- It improves some cases:
  - Kushiro final error improves from `24 km` to `7 km`;
  - Tomakomai final error improves from `18 km` to `14 km`;
  - Tomakomai also avoids the bridge's all-S final (`0/13/1`) and becomes
    P-dominant (`26/0/11`) under the current scoring.
- It regresses others:
  - Iwate is slightly worse (`10 km` to `13 km`);
  - Wakayama drifts badly offshore (`37 km` to `167 km`);
  - Fukushima remains unusable for tuning because the replay is still
    low-coverage and now worsens (`137 km` to `165 km`).

Conclusion:

- v1 is not promotion-ready.
- The next fix is not "more grid search"; it needs reference-like constraints:
  1. region/search-bounds guard around the detection geometry;
  2. membership aging/clear rules for stale `ten_plus_3` records;
  3. staged source-cache update semantics instead of replacing `4-4` every
     frame;
  4. a p-origin cluster quality gate so shallow P-dominant solutions do not
     jump offshore on local inland events.

### JQ state-machine v1 guard pass: bounds, stale membership, staged update

Added a conservative guard pass on top of v1:

- stale `ten_plus_3` membership is cleared when a station leaves current
  `source_trigger_member_ids` or has not updated for more than `12 s`;
- search candidates are constrained to adaptive bounds around current usable
  detection-member station geometry;
- old out-of-bounds cache centers are clamped back into current detection
  bounds before local search;
- `4-4` source-cache updates now pass through a staged update guard, rejecting
  large jumps unless the score/support improvement is strong;
- the early seed score is represented as a large finite unscored value so JSON
  generation remains valid.

Validation run:

```powershell
flutter analyze test\support\source_estimation_benchmark.dart
flutter test test\source_estimation_baseline_test.dart --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --concurrency=1
```

Result: passed.

Latest bridge vs guarded state-machine v1 readout:

| Case | Method | Median error | P90 error | Final error | Final lat/lon/depth | P/S/O | Residual | Cache score | Final update decision |
|---|---|---:|---:|---:|---|---:|---:|---:|---|
| `20260622_iwate_east_offshore_m30_hinet` | bridge | `10.0 km` | `36.0 km` | `10.0 km` | `39.9381,142.2385,10` | `5/11/2` | `1.35 s` | - | - |
| `20260622_iwate_east_offshore_m30_hinet` | guarded state-machine v1 | `35.0 km` | `41.0 km` | `35.0 km` | `39.8283,141.9485,40` | `6/8/11` | `14.07 s` | `3.66` | `rejected_by_staged_update_guard` |
| `20260622_kushiro_offshore_m30_jma` | bridge | `23.5 km` | `40.6 km` | `24.0 km` | `42.6888,144.0190,10` | `8/0/1` | `1.93 s` | - | - |
| `20260622_kushiro_offshore_m30_jma` | guarded state-machine v1 | `7.0 km` | `7.0 km` | `7.0 km` | `42.9581,144.0098,10` | `23/2/8` | `2.04 s` | `6.30` | `rejected_by_staged_update_guard` |
| `20260622_tomakomai_south_offshore_m35_hinet` | bridge | `2.0 km` | `38.8 km` | `18.0 km` | `42.1604,141.1736,140` | `0/13/1` | `1.10 s` | - | - |
| `20260622_tomakomai_south_offshore_m35_hinet` | guarded state-machine v1 | `30.0 km` | `43.5 km` | `30.0 km` | `42.1806,141.0209,60` | `24/0/13` | `7.56 s` | `5.47` | `rejected_by_staged_update_guard` |
| `20260622_wakayama_south_m25_hinet` | bridge | `37.0 km` | `37.0 km` | `37.0 km` | `33.2559,135.8636,20` | `9/0/2` | `1.59 s` | - | - |
| `20260622_wakayama_south_m25_hinet` | guarded state-machine v1 | `60.0 km` | `60.0 km` | `60.0 km` | `33.5974,136.4336,10` | `12/4/11` | `14.24 s` | `2.95` | `rejected_by_staged_update_guard` |
| `20260630_fukushima_hamadori_m35_hinet_equake10` | bridge | `137.0 km` | `137.4 km` | `137.0 km` | `36.4304,139.9848,140` | `12/0/0` | `0.44 s` | - | - |
| `20260630_fukushima_hamadori_m35_hinet_equake10` | guarded state-machine v1 | `129.0 km` | `185.0 km` | `129.0 km` | `36.4584,140.0808,80` | `10/0/6` | `8.54 s` | `1.71` | `rejected_by_staged_update_guard` |

Interpretation:

- The bounds/aging pass helped the worst runaway cases:
  - Wakayama improved from the prior v1 `167 km` failure to `60 km`;
  - Fukushima improved from `165 km` to `129 km`, though this remains a
    low-coverage case and should not be tuned against.
- It hurt previously useful cases:
  - Iwate regressed from `13 km` to `35 km`;
  - Tomakomai regressed from `14 km` to `30 km`.
- The final decision field is often `rejected_by_staged_update_guard`, so the
  staged update rule is now the main suspect. It is preventing late cache
  correction in some cases while only partially controlling runaway drift.

Next implementation target:

1. Replace the hard staged update guard with a reference-like staged local
   search schedule:
   early seed, coarse owned update, then small local refinement only.
2. Keep adaptive bounds, but make the margin depend on station geometry
   one-sidedness/offshore likelihood instead of a fixed clamp.
3. Add a P-origin cluster quality score to the candidate ranking before the
   staged update decision, not after it.

### JQ state-machine v2: coarse-after-seed and P-origin cluster scoring

Implemented the first reference-like v2 scoring pass:

- an unscored early seed no longer forces the next frame into a small local
  search; seed/early frames run a coarse update first;
- later frames move to staged local refinement based on event age;
- candidate scoring now includes P-origin cluster quality:
  - `p_origin_spread_s`;
  - `p_origin_cluster_count`;
  - spread/cluster penalties before the update decision;
- staged update acceptance can also use P-cluster improvement, not only raw
  total score.

Validation run:

```powershell
flutter analyze test\support\source_estimation_benchmark.dart
flutter test test\source_estimation_baseline_test.dart --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --concurrency=1
```

Result: passed.

Latest bridge vs state-machine v2 readout:

| Case | Method | Median error | P90 error | Final error | Final lat/lon/depth | P/S/O | Residual | Cache score | P spread | P cluster |
|---|---|---:|---:|---:|---|---:|---:|---:|---:|---:|
| `20260622_iwate_east_offshore_m30_hinet` | bridge | `10.0 km` | `36.0 km` | `10.0 km` | `39.9381,142.2385,10` | `5/11/2` | `1.35 s` | - | - | - |
| `20260622_iwate_east_offshore_m30_hinet` | state-machine v2 | `35.0 km` | `41.0 km` | `35.0 km` | `39.8283,141.9485,40` | `6/8/11` | `14.07 s` | `5.94` | `5.08 s` | `8` |
| `20260622_kushiro_offshore_m30_jma` | bridge | `23.5 km` | `40.6 km` | `24.0 km` | `42.6888,144.0190,10` | `8/0/1` | `1.93 s` | - | - | - |
| `20260622_kushiro_offshore_m30_jma` | state-machine v2 | `1.0 km` | `9.0 km` | `1.0 km` | `42.8981,144.0098,10` | `23/2/8` | `2.06 s` | `7.11` | `1.78 s` | `27` |
| `20260622_tomakomai_south_offshore_m35_hinet` | bridge | `2.0 km` | `38.8 km` | `18.0 km` | `42.1604,141.1736,140` | `0/13/1` | `1.10 s` | - | - | - |
| `20260622_tomakomai_south_offshore_m35_hinet` | state-machine v2 | `7.0 km` | `45.0 km` | `7.0 km` | `42.1206,141.3209,10` | `26/0/11` | `7.82 s` | `7.39` | `1.73 s` | `27` |
| `20260622_wakayama_south_m25_hinet` | bridge | `37.0 km` | `37.0 km` | `37.0 km` | `33.2559,135.8636,20` | `9/0/2` | `1.59 s` | - | - | - |
| `20260622_wakayama_south_m25_hinet` | state-machine v2 | `26.0 km` | `29.0 km` | `26.0 km` | `33.5974,136.0736,20` | `12/4/11` | `16.48 s` | `4.44` | `3.21 s` | `11` |
| `20260630_fukushima_hamadori_m35_hinet_equake10` | bridge | `137.0 km` | `137.4 km` | `137.0 km` | `36.4304,139.9848,140` | `12/0/0` | `0.44 s` | - | - | - |
| `20260630_fukushima_hamadori_m35_hinet_equake10` | state-machine v2 | `134.0 km` | `185.0 km` | `134.0 km` | `36.3984,140.0808,100` | `11/0/5` | `8.32 s` | `2.34` | `1.26 s` | `12` |

Interpretation:

- This is the first state-machine version that beats the bridge on three clean
  local benchmark cases:
  - Kushiro: `24 km` -> `1 km`;
  - Tomakomai: `18 km` -> `7 km`;
  - Wakayama: `37 km` -> `26 km`.
- Iwate still regresses (`10 km` -> `35 km`), so v2 is still diagnostic-only.
- Fukushima remains low-coverage and should not drive scoring choices.
- The final update decision still often reads
  `rejected_by_staged_update_guard`; this now means the retained cache is good
  enough in several cases, but the diagnostic label should be split into
  "held good cache" vs "blocked needed correction" before promotion decisions.

Next implementation target:

1. Add explicit held-cache diagnostics:
   `held_good_cache`, `blocked_needed_correction`, `accepted_refinement`.
2. Audit Iwate frame-by-frame to find why the P-cluster score prefers the
   inland/nearshore cache over the bridge offshore cache.
3. Add one-sided/offshore geometry context to search-bounds margin instead of
   treating all station geometry the same.

### JQ state-machine v2 decision-label split

Split the previous ambiguous `rejected_by_staged_update_guard` label into
actionable source-cache update decisions:

- `accepted_initial_source_cache`;
- `held_seed_waiting_for_support`;
- `accepted_first_owned_search`;
- `accepted_refinement`;
- `accepted_strong_score_improvement`;
- `accepted_p_origin_cluster_improvement`;
- `accepted_high_support_score_improvement`;
- `held_good_cache`;
- `blocked_needed_correction_or_low_quality_jump`;
- `rejected_invalid_candidate`.

This does not change the final v2 geometry by itself, but it makes the staged
update behavior auditable. The model/status labels are now:

- `jq_reference_state_machine_v2_p_origin_cluster_scoring`;
- `stateful_station_fields_with_owned_source_cache_and_p_origin_cluster_scoring`.

Validation run:

```powershell
flutter analyze test\support\source_estimation_benchmark.dart
flutter test test\source_estimation_baseline_test.dart --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --concurrency=1
```

Result: passed.

Final decision labels after regeneration:

| Case | Final state-machine decision | Notes |
|---|---|---|
| `20260622_iwate_east_offshore_m30_hinet` | `held_good_cache` | final error remains `35 km`; the run contains `2` `blocked_needed_correction_or_low_quality_jump` frames |
| `20260622_kushiro_offshore_m30_jma` | `held_good_cache` | final error remains `1 km` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `held_good_cache` | final error remains `7 km` |
| `20260622_wakayama_south_m25_hinet` | `held_good_cache` | final error remains `26 km` |
| `20260630_fukushima_hamadori_m35_hinet_equake10` | `held_good_cache` | low-coverage case; still not a tuning target |

Decision-count summary:

| Case | accepted initial | waiting seed | first owned search | accepted refinement | blocked correction/low-quality jump | held good |
|---|---:|---:|---:|---:|---:|---:|
| `20260622_iwate_east_offshore_m30_hinet` | `1` | `9` | `1` | `3` | `2` | `87` |
| `20260622_kushiro_offshore_m30_jma` | `1` | `9` | `1` | `7` | `4` | `88` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `1` | `9` | `1` | `7` | `0` | `74` |
| `20260622_wakayama_south_m25_hinet` | `1` | `9` | `1` | `5` | `0` | `89` |
| `20260630_fukushima_hamadori_m35_hinet_equake10` | `1` | `1` | `1` | `0` | `0` | `4` |

Interpretation:

- The final `held_good_cache` label is now meaningful for the successful
  cases: Kushiro, Tomakomai, and Wakayama retain a cache that already beats the
  bridge.
- Iwate is still the key failure. It also ends as `held_good_cache`, but at
  `35 km` error, so the "good" label is local to the current scoring function,
  not truth quality.
- The Iwate run has two `blocked_needed_correction_or_low_quality_jump` frames.
  The next audit should inspect those frames to determine whether they were
  legitimate offshore corrections blocked by the staged update guard or simply
  low-quality jumps.

Next implementation target:

1. Build an Iwate frame-level source-cache decision trace:
   time, previous cache, candidate cache, jump, score delta, P spread, P
   cluster, and truth error.
2. Add one-sided/offshore geometry context to the search-bounds margin and
   staged update decision.
3. Only then tune acceptance thresholds.

### Iwate source-cache decision trace

Added `source_cache_update_trace` to the state-machine diagnostics. Each frame
now can expose:

- decision label and accepted/rejected status;
- previous cache;
- candidate cache;
- jump distance;
- score delta;
- P-origin spread delta;
- P-origin cluster delta;
- support delta.

Validation run:

```powershell
flutter analyze test\support\source_estimation_benchmark.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --concurrency=1
```

Result: passed after a transient Windows `errno 10055` socket-buffer failure
recovered.

Blocked-decision trace for `20260622_iwate_east_offshore_m30_hinet`:

| Time JST | Current error | Candidate error | Jump | Score delta | P spread delta | P cluster delta | Previous cache | Candidate cache |
|---|---:|---:|---:|---:|---:|---:|---|---|
| `2026-06-22T11:27:19` | `49.4 km` | `60.5 km` | `17 km` | `+1.21` | `-1.39 s` | `0` | `39.8883,141.7685,20` | `40.0083,141.6485,10` |
| `2026-06-22T11:27:20` | `49.4 km` | `60.5 km` | `17 km` | `+1.21` | `-1.39 s` | `0` | `39.8883,141.7685,20` | `40.0083,141.6485,10` |

Those two blocked candidates are not useful offshore corrections; they would
increase truth error from `49.4 km` to `60.5 km`. The staged update guard is
therefore correct for these two frames.

Accepted-cache trace for the same Iwate run:

| Time JST | Decision | Candidate error | Candidate cache | Score | P cluster | P spread |
|---|---|---:|---|---:|---:|---:|
| `2026-06-22T11:27:08` | `accepted_initial_source_cache` | `40.6 km` | `40.0083,141.8885,10` | unscored seed | `0` | - |
| `2026-06-22T11:27:18` | `accepted_first_owned_search` | `49.4 km` | `39.8883,141.7685,20` | `11.15` | `10` | `4.75 s` |
| `2026-06-22T11:27:24` | `accepted_refinement` | `35.7 km` | `40.0083,141.9485,10` | `6.97` | `8` | `4.19 s` |
| `2026-06-22T11:27:25` | `accepted_refinement` | `34.1 km` | `39.8883,141.9485,40` | `7.53` | `9` | `5.05 s` |
| `2026-06-22T11:27:26` | `accepted_refinement` | `35.2 km` | `39.8283,141.9485,40` | `5.94` | `8` | `5.08 s` |

Interpretation:

- Iwate's failure is not caused by a useful candidate being blocked.
- The first owned search at `11:27:18` already moves the cache to a
  `49.4 km`-error solution.
- Later local refinement can only recover it to about `35 km`.
- Therefore the next algorithmic fix should add offshore/one-sided geometry
  context before or during the first owned search, not simply loosen staged
  update acceptance.

Next implementation target:

1. Detect one-sided station geometry for the state-machine usable membership.
2. If geometry is one-sided and the bridge/centroid direction indicates an
   offshore source, allow the first owned search bounds to extend seaward and
   penalize inland/landward collapse.
3. Re-run Iwate first, then all five cases.

### Reference algorithm shape: Scratch/JQ HYP state machine

The source-estimation work in this branch is aligned to the public
`scratch-realtime-earthquake-viewer-page` carrier and the JQ/HYP-style runtime
semantics visible in it. This is not a centroid algorithm and not a single-frame
line fit. It is a stateful GIF-reverse-decoded hypocenter estimator.

Reference input model:

- The input is still NIED/KMoni-style GIF reverse decoding.
- There are no true waveform P/S picks in the GIF.
- P/S labels are inferred from station trigger/rise timing against predicted
  P/S arrivals from the current source cache.
- The travel-time basis is JMA2001-style P/S travel time, not a fixed
  straight-line speed model.

Reference state model:

1. Detection id state, represented in the Scratch carrier as the `4-3` family:

   - detection id;
   - first detection time;
   - current event age;
   - station membership for that detection id;
   - linkage to the corresponding source cache.

2. Source cache state, represented as the `4-4` family:

   - `+2`: longitude;
   - `+3`: latitude;
   - `+4`: depth;
   - `+5`: origin time.

   This cache is not supposed to be replaced by an unconstrained full search on
   every replay frame. The reference behavior is closer to staged evolution:

   - early seed from the first detected station / first detection region;
   - depth starts shallow, typically `10 km`;
   - origin starts around `firstDetection - 2 s`;
   - later frames update by staged coarse/local search;
   - local refinements should respect detection membership and prior cache
     continuity.

3. Station state, represented by `ten:推定用` rows:

   | Field | Meaning |
   |---|---|
   | `ten_plus_1` | station observed/trigger time used by HYP |
   | `ten_plus_2` | station last/update time |
   | `ten_plus_3` | detection id membership |
   | `ten_plus_4` | distance cache to current source |
   | `ten_plus_5` | pre-trigger/rise cache |
   | `ten_plus_6` | whether observed time is closer to predicted S than predicted P |
   | `ten_plus_7` | predicted P arrival from current source cache |
   | `ten_plus_8` | predicted S arrival from current source cache |

The key derived phase flag is:

```text
6 = abs(observedTime - predictedSArrival)
     < abs(observedTime - predictedPArrival)
```

S-phase usage is gated:

```text
currentTime > firstDetectionTime + 15s
AND ten_plus_6 == true
```

Before that gate opens, stations should be treated as P-side evidence even if a
later candidate could explain them as S.

Reference scoring shape:

- Candidate state is `(latitude, longitude, depth, originTime)`.
- Candidate quality should account for:
  - P residuals;
  - S residuals after the 15 s gate;
  - P-origin cluster quality;
  - S-origin cluster quality only when the gate allows it;
  - station membership consistency;
  - stale member clearing;
  - source-cache continuity;
  - unarrived/not-yet-triggered station penalties when available.

Implementation guidance for our diagnostic runner:

- `jq_reference_hyp_state_machine_experiment` should remain diagnostic-only
  until it beats production and bridge baselines on the replay set.
- Production coordinates remain `nied_gif_hybrid_v1`.
- The next implementation should prefer reference-like staged cache evolution
  over hard rejection guards:
  1. early seed;
  2. coarse owned update;
  3. bounded local refinement;
  4. P-origin cluster gate before accepting `4-4`;
  5. membership aging and split before phase scoring.
- Historical GIF re-download should not be proposed for events outside the
  NIED/KMoni short availability window. Low-coverage replay cases, especially
  the Fukushima current-capture sample, stay cadence/capture-quality
  counterexamples rather than tuning targets.

### JQ state-machine v3: one-sided geometry scoring audit

Implemented a diagnostic-only v3 pass for
`jq_reference_hyp_state_machine_experiment`:

- model label:
  `jq_reference_state_machine_v3_one_sided_geometry_scoring`;
- status:
  `stateful_station_fields_with_owned_source_cache_p_origin_cluster_and_one_sided_geometry_scoring`;
- the state machine still owns its `4-4` source cache and does not promote
  coordinates to production;
- production coordinates remain `nied_gif_hybrid_v1`;
- added a case-filter switch for the generated benchmark test:
  `SOURCE_HYP_JMA2001_CASE_FILTER`, so individual replay cases can be
  regenerated without running the full five-case replay set.

The geometry pass uses the current bridge/HYP diagnostic only as a weak
direction hint from the usable station centroid. It penalizes one-sided
candidate collapse back toward the station cloud, but it does not directly copy
the bridge coordinate into the state-machine source cache.

Validation run:

```powershell
flutter analyze test\support\source_estimation_benchmark.dart test\source_hyp_jma2001_experiment_report_test.dart
flutter test test\source_estimation_baseline_test.dart --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=iwate_east --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=kushiro --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=tomakomai --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=wakayama --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=fukushima --concurrency=1
```

Result: passed.

Current v3 final replay metrics:

| Case | Frames | Hybrid | Bridge/JQ scoring | State-machine v3 | Final cache | P/S/O | Notes |
|---|---:|---:|---:|---:|---|---|---|
| `20260622_iwate_east_offshore_m30_hinet` | `151/151` | `9 km` | `10 km` | `24 km` | `39.9483,142.0685,40` | `10/5/2` | improved from the previous `35 km` state-machine result, but still not competitive with bridge/hybrid |
| `20260622_kushiro_offshore_m30_jma` | `151/151` | `13 km` | `24 km` | `1 km` | `42.8983,144.0100,10` | `24/5/3` | preserved the strong state-machine result |
| `20260622_tomakomai_south_offshore_m35_hinet` | `151/151` | `7 km` | `18 km` | `14 km` | `42.1206,141.2009,20` | `27/0/3` | regression versus the previous `~7 km` state-machine result; geometry penalty is `0`, so the issue is not a direct geometry over-penalty |
| `20260622_wakayama_south_m25_hinet` | `151/151` | `3 km` | `37 km` | `26 km` | `33.5970,136.0740,20` | `11/4/1` | unchanged diagnostic improvement versus bridge, still worse than production hybrid |
| `20260630_fukushima_hamadori_m35_hinet_equake10` | `16/66` | `61 km` | `137 km` | `134 km` | `36.3980,140.0810,100` | `12/0/0` | low-coverage current capture; keep as capture/cadence counterexample, not a tuning driver |

Interpretation:

- The v3 geometry constraint fixed the most obvious Iwate landward/one-sided
  collapse mode, improving Iwate from `35 km` to `24 km`.
- It did not solve Iwate. Once the candidate is far enough from the station
  cloud, the geometry penalty becomes `0`, and the remaining error is dominated
  by phase/depth scoring.
- The Tomakomai regression is also phase/depth-related: its final geometry
  penalty is `0`, and the final state is a P-only cache (`27/0/3`) at `20 km`
  depth.
- A late `0.03°` refinement stage was tested and did not change Iwate or
  Tomakomai. Therefore the remaining error is not primarily grid resolution.

Next implementation target:

1. Stop strengthening the line-fit/grid side blindly.
2. Add a depth-aware phase scoring pass:
   - keep P-origin cluster existence as a soft requirement;
   - add S-origin cluster quality after the 15 s S gate;
   - penalize unrealistically deep early P-only first-owned searches;
   - allow deep solutions only when S-side evidence actually supports them;
   - keep low-coverage Fukushima out of threshold tuning.
3. Re-run Iwate and Tomakomai first. They now represent the two useful failure
   modes:
   - Iwate: one-sided offshore event still not far enough offshore;
   - Tomakomai: P-only/depth scoring can regress an otherwise good local
     solution.

### JQ state-machine v4: shallow-first depth/phase scoring audit

Implemented a follow-up diagnostic-only v4 pass:

- model label: `jq_reference_state_machine_v4_depth_phase_scoring`;
- status:
  `stateful_station_fields_with_owned_source_cache_p_origin_cluster_one_sided_geometry_and_depth_phase_scoring`;
- added a soft penalty for P-only candidates deeper than `40 km`;
- added a soft penalty for deep candidates with weak S support after the S gate;
- kept the v3 one-sided geometry scoring and staged source-cache semantics.

Validation run:

```powershell
flutter analyze test\support\source_estimation_benchmark.dart
flutter test test\source_estimation_baseline_test.dart --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=iwate_east --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=tomakomai --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=kushiro --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=wakayama --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=fukushima --concurrency=1
```

Result: passed.

Current v4 final replay metrics:

| Case | Frames | Hybrid | Bridge/JQ scoring | State-machine v4 | Final cache | P/S/O | Notes |
|---|---:|---:|---:|---:|---|---|---|
| `20260622_iwate_east_offshore_m30_hinet` | `151/151` | `9 km` | `10 km` | `24 km` | `39.948,142.068,40` | `10/5/2` | unchanged from v3; remaining error is not fixed by simple shallow-first depth pressure |
| `20260622_kushiro_offshore_m30_jma` | `151/151` | `13 km` | `24 km` | `1 km` | `42.898,144.010,10` | `24/5/3` | preserved |
| `20260622_tomakomai_south_offshore_m35_hinet` | `151/151` | `7 km` | `18 km` | `14 km` | `42.121,141.201,20` | `27/0/3` | unchanged from v3; remaining issue is not simply excessive deep P-only scoring |
| `20260622_wakayama_south_m25_hinet` | `151/151` | `3 km` | `37 km` | `26 km` | `33.597,136.074,20` | `11/4/1` | preserved |
| `20260630_fukushima_hamadori_m35_hinet_equake10` | `16/66` | `61 km` | `137 km` | `83 km` | `36.758,140.441,40` | `11/0/1` | improved by shallow-first pressure but remains low-coverage and must not drive tuning |

Interpretation:

- v4 confirms that the remaining Iwate/Tomakomai problem is not grid
  resolution and not only deep P-only overfitting.
- The next useful step is closer to the real JQ/HYP behavior: compare candidate
  quality using phase-origin clusters and station-pair travel-time differences.
- In other words, implement an explicit scoring term for:
  - S-origin cluster quality after the 15 s gate;
  - P/S origin separation consistency;
  - station-pair differential travel-time residuals;
  - only then adjust acceptance guards.

### 2026-07-01 Scratch/JQ magnitude-source recheck

Rechecked the public `scratch-realtime-earthquake-viewer-page` project for the
selected concern that `M` might already be derived from GIF station observations.

Findings:

- `距離の震度 %s %s %s %s` is a forward intensity formula with arguments
  `距離, M, 深さ, 増幅`.
- Its two observed call sites pass `M` from `0EEW +9` and depth from
  `0EEW +8`.
- `0EEW +9` is written from cloud message `内容` characters 24 and 25
  (`letter(24, 内容) + "." + letter(25, 内容)`), while `0EEW +8` is written
  from characters 21-23.
- No public Scratch block was found that writes `M` from GIF station intensity,
  acceleration, `ten:*` station history, or HYP `4-4` source cache.
- `SeriesNotFound/EQuake` public repository confirms that the application uses
  `scratch-realtime-earthquake-viewer-page` for source estimation and JQuake for
  realtime intensity/acceleration extraction, but the main application is
  closed source and the public repository only exposes the GeoJson parser.

Decision:

- Treat public Scratch/JQ HYP as the reference for
  `lat/lon/depth/originTime`, not as an already-auditable GIF-derived magnitude
  implementation.
- Implement our GIF-derived magnitude as a separate post-source inversion:
  use the estimated source cache, station GIF-derived intensity/acceleration,
  station distance/site amplification, and the `距離の震度` forward model to fit
  `M`.
- Do not mix this `M` inversion into the first HYP coordinate/depth search; run
  it after a candidate source cache exists.

### User-provided SB3 audit: viewer v1.6.3 and legacy simulator

Inspected the two user-provided SB3 files:

- `D:/Users/Rhythm/Downloads/リアルタイム地震ビューアー v1.6.3.sb3`;
- `D:/bdwp/地震模拟(存档恢复）.sb3`.

Findings:

- `リアルタイム地震ビューアー v1.6.3.sb3` is older than the current public
  GitHub project. It contains `距離の震度`, `JMA2001距離近似`, EEW handling,
  single/multiple trigger state, nearest-station logic and placeholder/debug
  `@1 hyp:震源計算` variables/lists, but not the full
  `HYP:震源検出` / `HYP:誤差レベル計算` / `4-4 検出id震源要素` state cache seen in
  the newer public project.
- In v1.6.3, `M` is still written to `0EEW +9` from cloud message characters
  24-25 and then passed into `距離の震度`; no GIF-derived magnitude inversion was
  found.
- The legacy simulator has a useful `P/S计算` toy model:
  three P detections -> perpendicular-bisector epicenter, then iterative depth
  refinement using a fixed `6.5 km/s` P-wave radius model. Its source cache is
  `[P/SCal]EarthquakeIn = [x, y, depth, status]`.
- The simulator's `震级M` is a Stage input variable used to synthesize station
  intensity. No block was found that writes or estimates `震级M` from station
  observations.

Decision:

- Keep using the newer public Scratch/JQ HYP shape as the reference for
  production-grade diagnostic source/depth work.
- Treat the legacy simulator only as intuition and as a possible synthetic-test
  fixture for simple P-wave geometry/depth behavior.
- Continue to implement GIF-derived magnitude as our own post-source inversion;
  neither user-provided SB3 supplies an auditable GIF→M implementation.

### Bilibili depth-search video audit

Inspected the user-provided video:

```text
【摇晃检测 本地计算震源】
https://b23.tv/6Z3SdKe
BV1aF4m177kW
```

The video description identifies the reference event as Tomakomai offshore,
`42°33.5′N, 141°54.9′E`, `M6.2`, depth `136 km`,
`2023-06-11 18:54:44.6`.

Visible algorithm behavior:

- The runtime maintains a temporary source candidate:
  `(latitude, longitude, depth)`.
- It evaluates neighbor candidates around the current source:
  longitude ± step, latitude ± step and depth ± step.
- Early frames show coarse movement such as longitude/latitude `±0.5°`
  with no depth movement.
- Later frames show refined movement such as longitude/latitude `±0.1°`
  and depth `±50 km` / `±10 km`.
- Each candidate is scored by a visible `誤差レベル` over the distance-vs-time
  arrival plots.
- The source is moved to the lower-error candidate and the process repeats
  until `震源決定完了`.
- The final video candidate is approximately
  `42.5N, 142.0E, 140 km`, close to the reference depth `136 km`.

Decision:

- Treat depth as a candidate-search dimension, not as a closed-form scalar
  correction.
- Implement the next HYP depth step as staged local search over
  `(lat, lon, depth, originTime)` with explicit neighbor comparison and
  `誤差レベル`-style scoring.
- Do not keep tuning a single depth penalty as the primary mechanism.

### kotoho7 note / scratchrev video audit

Inspected the article and embedded `Scratch動作チェック用` / `@scratchrev`
videos linked from the Bilibili description:

- article:
  <https://note.com/kotoho7/n/n59e423877b1b>
  (`揺れ検知から震央を検出してみる`);
- embedded videos:
  - `MaWB39GiZ64`: `仮の震源を移動させる`;
  - `v85t4Dwu60Y`: `苫小牧沖 M6.2 深さ136km`;
  - `doUBJoIUJLs`: `岩手県沖 M3.6 深さ40km`;
  - `i0Tgp3vwadU`: `千葉県北西部 M3.5 深さ90km`;
  - `UXRYI5TcGtU`: `能登半島沖 M2.8 深さ12km`;
  - `p4YmrE5mgGA`: `十勝沖 M4.6 深さ30km`;
  - `SIt-ZB9c7IM`: `東海道南方沖 M4.5 深さ33km`;
  - `gLp88jlZz3A`: `日本海中部 M6.1 深さ394 km`.

Useful evidence:

- The article directly describes scoring a candidate
  `(lat, lon, depth, originTime)` by:
  station distance -> JMA2001 P/S travel time -> per-station inferred origin
  time -> weighted squared scatter -> `誤差レベル`.
- The Scratch screenshots expose the relevant lists/variables:
  `@hyp:発生時刻リスト`, `@hyp:重みリスト`,
  `@hyp:未着走時リスト`, `@hyp:2乗誤差の合計`,
  `@hyp:誤差レベル`, and `JMA2001時刻`.
- The article's Osaka North counterexample shows why arrived-only fitting is
  unsafe: with few triggers, a false candidate can fit the arrived points while
  sitting among many untriggered stations. Adding the unarrived/`着未着法`
  penalty raises that false candidate's `誤差レベル`.
- The `MaWB39GiZ64` thumbnail visibly shows `仮の震源を移動中`, movement
  amounts such as `緯経度 ±0.1度` and `深さ ±10km`, plus multiple candidate
  panels with the lowest `誤差レベル` highlighted.
- The Tomakomai and Japan Sea Central thumbnails show that this local-search
  path can display deep solutions around `140 km` and several-hundred-km depth.

Implementation consequence:

The next source/depth implementation should not be another blind penalty pass.
It should be a reference-shaped HYP v1:

1. maintain an owned source cache `(lat, lon, depth, originTime)`;
2. initialize from the first detected station, `depth = 10 km`, and
   `originTime = firstDetectionTime - 2 s`;
3. run staged local search:
   - coarse horizontal `0.5°`;
   - fine horizontal `0.1°`;
   - fine horizontal plus depth `±50 km`;
   - fine horizontal plus depth `±10 km`;
4. score each candidate using:
   - JMA2001 P/S travel time;
   - per-station inferred origin-time scatter;
   - distance weighting;
   - explicit unarrived-station penalty;
5. select the lower `誤差レベル` candidate and repeat until no lower-error
   neighbor is found or the stage iteration cap is reached.

Magnitude decision remains unchanged:

- the note/video audit strengthens the HYP/depth/origin-time evidence;
- it still does not expose a GIF-derived `M` inversion;
- keep GIF-derived magnitude as a separate post-source inversion using the
  source cache and `距離の震度(distance, M, depth, amplification)` forward model.

### kotoho7 article cache and first replay implementation

Downloaded the kotoho7 article for local reference only:

```text
.dart_tool/reference_cache/kotoho7_yure_detection_note/article.html
.dart_tool/reference_cache/kotoho7_yure_detection_note/article_text.txt
.dart_tool/reference_cache/kotoho7_yure_detection_note/assets/
.dart_tool/reference_cache/kotoho7_yure_detection_note/manifest.json
```

The docs intentionally keep only our summary, implementation notes and source
link, not a full article copy.

Implemented the first diagnostic-only replay of the article shape:

```text
nied_gif_hyp_kotoho7_reference_replay_v1
```

Implementation details:

- gated by `emitKotoho7HypExperiment`, default `false`;
- exported by the benchmark runner as an independent diagnostic method frame;
- initializes from the first detected station:
  `lat/lon rounded to 0.01°`, `depth = 10 km`,
  `originOffset = -2 s`;
- uses staged neighbor descent:
  `start-h2`, `start-h10`, `start-h10-v50`, `start-h10-v10`;
- scores candidates by the article's P-wave origin-time error level:
  plain mean inferred origin time, distance weights only on squared scatter,
  and early-window 着未着 `+1` count penalties;
- intentionally does not mix in JQ/S-gate/source-lock optimizations in this
  reference method;
- does not change production coordinates.

Validation:

```powershell
flutter analyze lib\core\source_estimation\source_estimator.dart test\source_estimator_test.dart test\source_hyp_jma2001_experiment_report_test.dart test\support\source_estimation_benchmark.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=tomakomai --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=iwate_east --concurrency=1
```

Result:

| Case | Hybrid best/final | JQ scoring best/final | kotoho7 stateless best/final |
|---|---:|---:|---:|
| `20260622_iwate_east_offshore_m30_hinet` | `9 km / 9 km` | `4 km / 10 km` | `12 km / 37 km` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `3 km / 7 km` | `1 km / 18 km` | `22 km / 100 km` |

Follow-up correction:

The first replay was not faithful enough because it was stateless and also
mixed non-article P/S scoring. Reworked it into a real independent article
reference estimator:

```text
Kotoho7ReferenceHypSourceEstimator
method: nied_gif_hyp_kotoho7_reference_replay_v1
```

It is now wired into the benchmark runner as its own `SeismicSourceTracker`
method, not as a promoted hybrid diagnostic. It maintains a per-event source
cache keyed by `sourceId:eventId`:

- first detected station and initial rounded location;
- current `(lat, lon, depth, originOffset)` source cache;
- source-cache revision.

Per-frame behavior:

- initialize once from the first detected station;
- within the first 10 seconds after first detection, reseed from the first
  detected station as noted in the article;
- every frame, rescore the current source cache with current detected/undetected
  stations and continue the article's staged neighbor descent from that cache;
- no locked/determined shortcut is part of this reference implementation.

Additional validation:

```powershell
flutter analyze lib\core\source_estimation\source_estimator.dart test\support\source_estimation_benchmark.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=tomakomai --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=iwate_east --concurrency=1
```

Updated result:

| Case | kotoho7 reference best | median / p90 | final | Note |
|---|---:|---:|---:|---|
| `20260622_iwate_east_offshore_m30_hinet` | `32 km` | `33 km / 83 km` | `83 km` | final depth reaches the `700 km` search cap; P-only article error level cannot explain late mixed-phase/noise triggers |
| `20260622_tomakomai_south_offshore_m35_hinet` | `8 km` | `45 km / 50 km` | `140 km` | early frames can approach the event, but late frames also push depth to `700 km` |

Interpretation:

- Follow-up audit of the article code screenshot and public
  `scratch-realtime-earthquake-viewer-page/docs/assets/project.json` showed
  that the current "P-only reference" is still incomplete.
- The article text explains the error-level flow with P-wave travel time, but
  the actual Scratch code consumes `ten:推定用 +6` as a station S flag.
  In `HYP:誤差レベル計算`, detected stations call `JMA2001距離近似` with:
  `P波 = NOT ((@hyp:最初検知時刻 + 15 < 現在時刻) AND ten:推定用[station+6])`.
- Therefore, after 15 seconds from first detection, stations marked by the
  detection side as S-like should use S travel time in the kotoho7 reference
  replay. The current project does not yet pass the exact Scratch `ten+6`
  field into HYP, so the next correction is an explicit `article_s_flag_proxy`
  or a real detector-maintained S flag, not a production optimization.

Next implementation target:

1. Patch `nied_gif_hyp_kotoho7_reference_replay_v1` to include the article
   `ten:推定用 +6` S-flag semantics after the 15-second gate.
2. Keep non-article behavior such as production locking/depth guards out of
   the reference path unless it is traceable to the article/Scratch code.
3. After the article S-flag replay is in place, compare it against current JQ
   scoring on Iwate, Tomakomai,
   Kushiro, Wakayama and Fukushima before deciding production integration.

### kotoho7 article S-flag and error-level scale replay v2

Implemented the article code path that was missing from the P-only replay:

```text
scoring_model: kotoho7_article_error_level_with_s_flag_proxy_v2
station_s_flag_model: article_s_flag_proxy_candidate_origin_closeness_after_15s_v1
```

This follows the Scratch `HYP:誤差レベル計算` behavior:

- before the 15-second gate, detected stations use P travel time;
- after the gate, stations whose S-origin is closer to the current source-cache
  origin are treated as `ten:推定用 +6` S-flag proxy stations and use S travel
  time;
- the error level uses the Scratch-style normalized/scaled form:
  `S-factor * ((weightedResidualSquares + unarrivedCount) / weightSum) *
  (30 + 20000/(1+n^2) + 2000/(50+n))`;
- the article section (4) staged movement is still:
  `±0.5°`, then `±0.1°`, then `±0.1° + depth ±50 km`,
  then `±0.1° + depth ±10 km`.

Validation:

```powershell
flutter analyze lib\core\source_estimation\source_estimator.dart test\source_estimator_test.dart test\support\source_estimation_benchmark.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=tomakomai --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=iwate_east --concurrency=1
```

Replay result:

| Case | kotoho7 reference best | median / p90 | final | Note |
|---|---:|---:|---:|---|
| `20260622_iwate_east_offshore_m30_hinet` | `4 km` | `12 km / 68 km` | `94 km` | early fit improves sharply, but the late source cache still drifts; final depth is about `360 km` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `8 km` | `8 km / 50 km` | `28 km` | much better than the P-only `140 km` final; final depth is about `300 km`, still too deep |

Conclusion: the S-flag/error-scale article path reduces the 700 km cap failure,
especially for Tomakomai, but it does not by itself solve late-frame source-cache
drift.

### kotoho7 Scratch project staged-search completion

Continued the article/Scratch audit against
`scratch-realtime-earthquake-viewer-page/docs/assets/project.json`.

Important findings:

- `1フレーム休み判断` is a performance/yield guard; it increments a counter
  during station loops and yields after the counter exceeds `1000`. It is not
  the main source-stability logic.
- `4-3 検出id別情報 +5` is not an arbitrary current-frame maximum. It is updated
  by `検出id距離計算` from `ten:推定用 +4`:
  `sqrt(((firstStation.Xpix - station.Xpix)*11)^2 + ((firstStation.Ypix - station.Ypix)*11)^2)`.
  It is therefore the detection-id maximum expansion distance from the first
  detected station. The current Dart implementation still uses a clearly named
  geographic-distance proxy.
- The Scratch project has a final staged-search pass that the previous replay
  missed:
  `start-h60`, horizontal step `1/60°`, no depth move, limit `10`.
- Scratch stage limits are not a fixed `150`:
  - `start-h2`: `30`, or `15`/`1` in the first `<5s` depending on count;
  - `start-h10`: `80`, or `40`/`6` in the first `<5s` depending on count;
  - `start-h10-v50`: `100`;
  - `start-h10-v10`: `100`;
  - `start-h60`: `10`.

Implemented in `Kotoho7ReferenceHypSourceEstimator` and the diagnostic replay:

- dynamic Scratch-derived iteration limits;
- final `start-h60` pass;
- per-stage `max_iterations` diagnostics.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart test\source_estimator_test.dart test\support\source_estimation_benchmark.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=tomakomai --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=iwate_east --concurrency=1
```

Replay result:

| Case | best | median / p90 | final | Note |
|---|---:|---:|---:|---|
| `20260622_tomakomai_south_offshore_m35_hinet` | `2 km` | `5 km / 50.9 km` | `50 km` | best frame also recovers depth `100 km`, matching the reference depth; the last seconds drift after distant membership expansion |
| `20260622_iwate_east_offshore_m30_hinet` | `4 km` | `13 km / 65 km` | `101 km` | good best frame, but late membership expansion drives the cache to `310–350 km` depth |

Current conclusion:

- The article/Scratch depth search is now demonstrably active: Tomakomai reaches
  the correct `100 km` depth at the best frame.
- The remaining mismatch is not "no depth estimation"; it is detection-id
  membership maintenance. Late noisy/distant stations inflate the `4-3+5`
  expansion distance and allow bad deep candidates.
- Next faithful-replay target is the detection-id pipeline:
  `検出id4-2_適用id震源から候補選択`,
  `検出id_同一震源統合`, and
  `検出id適用数カウント追加` / station removal semantics.

### Scratch-like current detection-id member input

Implemented the first membership-side correction instead of tuning HYP depth:

- `source_trigger_member_ids` now carries the current continuity-aware
  detection members, matching the Scratch idea of the current `ten:推定用 +3`
  / detection-id assignment.
- The historical continuity union is still preserved for diagnostics under
  `source_trigger_continuity_member_ids`.
- If a replacement is held, the continuity-aware detection member list is the
  held accepted list, so HYP still keeps the previous source id.
- `SourceTriggerContinuityGate` now also holds same-`eventId` far member
  replacements when the raw cluster has low overlap and its centroid is too far
  from the current anchor. This catches cases where the event detector keeps the
  same id but the largest component has effectively switched to another
  cluster.
- The benchmark JSON writer now normalizes debug-only non-finite values to
  `null` so current-member under-supported frames do not block report
  serialization.

Regression coverage:

- `test/nied_source_estimation_driver_test.dart` now asserts that estimator
  metadata uses current detection members while preserving the continuity union
  separately.
- The same test file also covers same-event far member replacement hold.

Validation:

```powershell
flutter analyze lib\core\source_estimation\source_trigger_continuity_gate.dart lib\services\sources\nied_source_estimation_driver.dart test\nied_source_estimation_driver_test.dart test\support\source_estimation_benchmark.dart lib\core\source_estimation\source_estimator.dart
flutter test test\nied_source_estimation_driver_test.dart test\source_estimator_test.dart --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=tomakomai --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=iwate_east --concurrency=1
```

Replay result after member-input correction:

| Case | best | median / p90 | final | Note |
|---|---:|---:|---:|---|
| `20260622_tomakomai_south_offshore_m35_hinet` | `3 km` | `28 km / 49.7 km` | `9 km` | final drift is largely removed; held same-event replacement frames keep depth near `100 km` |
| `20260622_iwate_east_offshore_m30_hinet` | `4 km` | `12 km / 90 km` | `85 km` | same-event replacement hold prevents later expansion, but one earlier主体切换 around `11:27:38–11:27:41` still needs Scratch candidate-selection/removal semantics |

Current next step:

- Continue with the Scratch detection-id pipeline before adding more HYP
  scoring knobs:
  `検出id4-2_適用id震源から候補選択`,
  `検出id_同一震源統合`, and station removal/clear rules for `ten:推定用 +3`.

### kotoho7 estimator-local detection-id station set

Status update: the replay now carries a kotoho7-local assigned station set
inside `Kotoho7ReferenceHypSourceEstimator`, rather than relying only on the
outer production event cluster. This is the first Dart-side analogue of
Scratch's persistent `ten:推定用 +3` table.

Implemented:

- per `sourceId:eventId` assigned station-code set;
- new station entrance by proximity to assigned stations or by fitting the
  estimator's own source cache with JMA2001 P/S travel time;
- HYP scoring over assigned records with first trigger/rise time, even if the
  station is no longer `activeLike` in the current frame;
- diagnostics now include assigned station count, current raw station count,
  and the assignment model.

Validation:

```powershell
flutter analyze lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\source_trigger_continuity_gate.dart lib\services\sources\nied_source_estimation_driver.dart test\source_trigger_continuity_gate_test.dart
flutter test test\source_trigger_continuity_gate_test.dart test\nied_source_estimation_driver_test.dart test\source_estimator_test.dart --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=tomakomai --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=iwate_east --concurrency=1
```

Latest replay:

| Case | kotoho7 median / p90 | kotoho7 final | Current reading |
|---|---:|---:|---|
| `20260622_tomakomai_south_offshore_m35_hinet` | `11 km / 52 km` | `10 km` | good: final depth `90 km`, near the `100 km` reference |
| `20260622_iwate_east_offshore_m30_hinet` | `55 km / 55 km` | `55 km` | not done: no deep drift, but the wrong shallow detection-id set is stable |

Next real step:

- Implement the remaining Scratch detection-id semantics instead of tuning HYP:
  `検出id4-2_適用id震源から候補選択`,
  `検出id_同一震源統合`, and `ten:推定用 +3` clear/removal behavior.
- Do not mark depth estimation complete until Iwate no longer locks onto the
  wrong shallow id.

### kotoho7 detection-id assigned timing and clear/removal update

Implemented the next Scratch detection-id step in
`Kotoho7ReferenceHypSourceEstimator`:

- kotoho7's local `ten:推定用 +3` analogue now reads uncapped timing records for
  the assigned source-id station set. This avoids losing source members through
  the shared 24-station earliest/strongest cap before the state machine scores
  HYP candidates.
- `ten:推定用 +3` clear/removal is now approximated locally: an assigned station
  that is no longer a current member and no longer fits the current source-cache
  P/S travel-time window is removed from the assigned set.
- The first detected station is protected as the detection-id anchor, matching
  the source-cache/first-point fallback role in the Scratch pipeline.
- Diagnostics now include `last_assignment_removed_count` and
  `last_assignment_removed_station_codes`; assignment model is now
  `kotoho7_detection_id_station_set_source_cache_phase_window_recovery_clear_v4`.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimator_test.dart test\seismic_source_tracker_test.dart --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=iwate_east --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=tomakomai --concurrency=1
```

Replay result:

| Case | kotoho7 median / p90 | kotoho7 final | Depth | Notes |
|---|---:|---:|---:|---|
| `20260622_iwate_east_offshore_m30_hinet` | `10 km / 44 km` | `11 km` | `10 km` | assigned set `28`, P/S/O `11/13/4`; low-support hold removed |
| `20260622_tomakomai_south_offshore_m35_hinet` | `11 km / 23.2 km` | `11 km` | `60 km` | assigned set `39`, P/S/O `7/25/7`; 2 stale stations cleared in 1 frame |

Current next step:

- Continue faithful detection-id reproduction with
  `検出id4-2_適用id震源から候補選択` and `検出id_同一震源統合`.
- Keep depth estimation marked as active-but-not-complete: the depth search is
  running, but full depth reliability depends on the remaining detection-id
  state-machine semantics.

### kotoho7 existing source-cache selection and same-source merge scaffold

Implemented the next detection-id state-machine layer:

- when the current `sourceId:eventId` has no kotoho7 state, the estimator scans
  existing source-cache states before creating a new one;
- candidate selection follows the Scratch 4-2 shape: compute station residuals
  against an existing source cache using P first, then S only if P misses the
  `5 + distance/120` tolerance window; reject candidates with insufficient
  station support or large mean/p90 residual;
- selected states are aliased through `source_keys`, so a later event key can
  reuse an earlier source cache instead of creating a separate shallow id;
- same-source merge scaffold now unions station sets when two local source
  states have nearby first-detection times and source-cache locations within
  `50 + assignedRadius / 2`;
- diagnostics now expose `source_selection_*` and `same_source_merge_*`.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart test\source_estimator_test.dart
flutter analyze lib\core\source_estimation\source_estimator.dart test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=iwate_east --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=tomakomai --concurrency=1
```

Coverage note:

- The new unit test `kotoho7 replay reuses an existing detection-id source
  cache` verifies an `event-b` frame reusing `event-a` via
  `scratch_detection_id_4_2_existing_source_cache_candidate_v1`.
- The current Iwate/Tomakomai benchmark replays are single-event-id paths, so
  their `source_selection_model` remains `current_key_existing_state` after
  the first frame and same-source merge does not trigger. Their accuracy stays
  unchanged from the previous pass:

| Case | kotoho7 median / p90 | kotoho7 final |
|---|---:|---:|
| `20260622_iwate_east_offshore_m30_hinet` | `10 km / 44 km` | `11 km` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `11 km / 23.2 km` | `11 km` |

Remaining work:

- copy/compare the fuller Scratch `4-3` metadata fields during
  `検出id_同一震源統合`;
- add or locate a real multi-detection-id replay where selection/merge triggers
  naturally, instead of only the synthetic regression.

### kotoho7 `4-3` metadata proxy and raw/effective id audit

Implemented the fuller Dart-side `4-3 検出id別情報` proxy for kotoho7 state:

- `scratch_4_3_proxy.first_detection_at`;
- `scratch_4_3_proxy.last_detection_at` and `stale_age_ms`;
- `scratch_4_3_proxy.assigned_count`;
- `scratch_4_3_proxy.max_first_station_distance_km`, proxying `4-3 +5`;
- `scratch_4_3_proxy.best_score`,
  `best_phase_mean_residual_s`, and `best_source_keys`;
- same-source merge now copies/compares this metadata by earliest first
  detection, latest detection, max first-station expansion distance, max
  assigned count, and lower best score.

Validation:

```powershell
flutter analyze lib\core\source_estimation\source_estimator.dart test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=iwate_east --concurrency=1
flutter test test\source_hyp_jma2001_experiment_report_test.dart --dart-define=SOURCE_HYP_JMA2001_GENERATE=true --dart-define=SOURCE_HYP_JMA2001_CASE_FILTER=tomakomai --concurrency=1
flutter test test\iwate_east_offshore_reference_replay_test.dart --concurrency=1
```

Replay impact:

| Case | kotoho7 median / p90 | kotoho7 final | `scratch_4_3_proxy` |
|---|---:|---:|---|
| `20260622_iwate_east_offshore_m30_hinet` | `10 km / 44 km` | `11 km` | assigned `28`, max first-station distance `131.1 km`, best score `58.474` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `11 km / 23.2 km` | `11 km` | assigned `39`, max first-station distance `204.3 km`, best score `43.513` |

Real replay audit:

- Iwate east offshore has real raw multi-id behavior:
  - raw `nied_gif-2026-06-22T11:27:05.000`: `43` frames;
  - raw `nied_gif-2026-06-22T11:28:20.000`: `9` frames.
- Production continuity holds the effective id as
  `nied_gif-2026-06-22T11:27:05.000` for `106` frames, with `13` held
  replacement frames.
- Because kotoho7 currently receives the continuity effective id, not the raw
  id, `source_selection_model` remains `current_key_existing_state` after the
  first frame and `same_source_merge_count` remains `0`.

Next step:

- Add a raw-id diagnostic replay mode/script that feeds
  `source_trigger_continuity_raw_event_id` into kotoho7 only for diagnostics.
  That should let the real Iwate east multi-id replay naturally exercise
  `検出id4-2_適用id震源から候補選択` and `検出id_同一震源統合` without changing
  production effective-id behavior.

### kotoho7 raw-id diagnostic replay

Implemented a raw-id-only diagnostic path while preserving production
effective-id behavior:

- Added benchmark method
  `nied_gif_hyp_kotoho7_reference_raw_id_diagnostic_v1`;
- raw diagnostic feeds `rawSourceEventDetection.eventId` to kotoho7;
- `SeismicSourceTracker.ingestFrame` now has a default-off
  `splitOnEventIdChange` flag, enabled only by this diagnostic path;
- raw candidate frames are allowed into this diagnostic path so held raw
  replacements can create separate kotoho7 states;
- added `tools/build_kotoho7_raw_id_diagnostic_report.dart`.

Validation:

```powershell
flutter analyze lib\core\source_estimation\seismic_source_tracker.dart test\support\source_estimation_benchmark.dart
flutter test test\iwate_east_offshore_reference_replay_test.dart --concurrency=1
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
flutter test test\iwate_offshore_m30_reference_replay_test.dart --concurrency=1
flutter analyze tools\build_kotoho7_raw_id_diagnostic_report.dart
dart run tools\build_kotoho7_raw_id_diagnostic_report.dart
```

Generated report:

- `.dart_tool/kotoho7_raw_id_diagnostic/report.json`
- Current scanned source-benchmark outputs:
  - `caseCount=14`
  - `casesWithRawMultiId=5`
  - `casesWithRawSelection=0`
  - `casesWithRawMerge=0`

Findings:

| Case | Raw ids | Raw diagnostic result |
|---|---:|---|
| `20260622_iwate_east_offshore_m30_hinet` | `2` | later raw id becomes a separate kotoho7 state; no selection/merge; last raw error `66 km` |
| `20260622_iwate_offshore_m30_eq10` | `2` | later raw id becomes a separate kotoho7 state; no selection/merge; last raw error `76 km` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `1` | no raw split; raw diagnostic final `8 km`, production final `11 km` |

Interpretation:

- Production effective-id replay is unchanged.
- The raw diagnostic path now proves the current `検出id4-2` selection /
  `検出id_同一震源統合` gate is conservative on real held-replacement clusters:
  it does not merge later poor replacement raw ids into the good source.
- Remaining work is to find or build a true same-source raw split fixture where
  `same_source_merge_count > 0` should occur, then verify metadata copy and
  station-set union on that positive case.

### kotoho7 `検出id2` station lifecycle cache

Continued the faithful Scratch/JQ replay work by inspecting the actual sb3
blocks for `検出id2_各点の許可idと推定用をセット`. The important correction is
that Scratch reset is not based on Dart `isActiveLike`: it is based on
`ten:震度`, `変化速度`, station state `5/6`, and the `ten:推定用 +1/+2`
timestamps.

Implemented in `Kotoho7ReferenceHypSourceEstimator`:

- `scratchStationFirstUseAt` as `ten:推定用 +1`;
- `scratchStationLastUpdateAt` as `ten:推定用 +2`;
- `scratchStationPermissionState` for Scratch-like station states `5/6`;
- reset/refresh behavior for:
  - `ten:震度 <= 0`;
  - `+2` stale `>200s`;
  - `+2` stale `>90s` with low station state / no positive `変化速度`;
  - state `5 -> 6` when the station has not re-accelerated for the Scratch
    age/distance window.

Important mapping note:

- `ten:震度` in sb3 is the `震度30` 30-step index, not continuous JMA shindo.
  Therefore Dart maps `ten:震度 > 0` primarily to `lastRawLevel > 0`
  (fallback: `lastDetectLevel > 0` or `lastValue > -3.0`).
- `変化速度 > 0` maps to `lastAscend > 0`.

Validation:

```powershell
flutter analyze lib\core\source_estimation\source_estimator.dart test\support\source_estimation_benchmark.dart test\source_estimation_replay_case_runner_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/fukushima_aizu_m46_20260702_jma_p2p.json --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/shizuoka_west_m36_20260702_jma_p2p.json --concurrency=1
```

Replay result:

| Case | kotoho7 best | median / p90 | final | Reading |
|---|---:|---:|---:|---|
| `20260702_fukushima_aizu_m46_jma_p2p` | `8 km` | `100 km / 278 km` | `94 km` | Final keeps `135` assigned stations (`118` state 6, `17` state 5), max `+2` age `86s`; remaining drift is now likely `ten:+3` / inactive-id lifecycle, not HYP depth scoring. |
| `20260702_shizuoka_west_m36_jma_p2p` | `3 km` | `5.5 km / 9 km` | `3 km` | Stable final; `95` assigned stations (`59` state 6, `36` state 5). |

Next implementation target:

- Continue from `検出id3_点にIDを登録`,
  `検出id適用数カウント追加`, and `4-3 検出id別情報` inactive-id clearing.
  Do not tune HYP depth/score to hide Fukushima's over-retention; the observed
  issue is now upstream in detection-id membership.

### kotoho7 `検出id3` / `4-3 +2` active gate

Continued the sb3 replication through:

- `検出id3_点にIDを登録`;
- `検出id適用数カウント追加`;
- `検出id_消えたidに対応する検出無効化`;
- the final active-count sweep in `検出id1_全点へ適用`.

Implemented in the kotoho7 reference state:

- `scratch43Active` as proxy for `4-3 検出id別情報 +2`;
- `scratch43ExpireAt` as proxy for `4-3 +9`;
- inactive reason/time diagnostics;
- HYP is skipped when the detection id is inactive;
- positive station registration into an inactive id is blocked by invalidating
  the local assigned set, matching the Scratch reset path.

The implemented active=false rules are Scratch-derived:

- assigned/apply count `< 2`;
- id missing from grid-presence proxy after 2s;
- `now > +9` expiry, where the expiry window extends with assigned count;
- age > 150s and count < 50;
- small/weak/bad-score detection guard.

Validation:

```powershell
flutter analyze lib\core\source_estimation\source_estimator.dart test\support\source_estimation_benchmark.dart test\source_estimation_replay_case_runner_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/fukushima_aizu_m46_20260702_jma_p2p.json --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/shizuoka_west_m36_20260702_jma_p2p.json --concurrency=1
```

Replay result:

| Case | kotoho7 best | median / p90 | final | Active-gate result |
|---|---:|---:|---:|---|
| `20260702_fukushima_aizu_m46_jma_p2p` | `8 km` | `100 km / 278 km` | `94 km` | No inactive trigger; final remains active with `135` assigned stations and `+9` expiry at `20:53:10`. |
| `20260702_shizuoka_west_m36_jma_p2p` | `3 km` | `5.5 km / 9 km` | `3 km` | No inactive trigger; final remains active with `95` assigned stations and `+9` expiry at `20:17:06`. |

Interpretation:

- This rules out the basic `4-3 +2` inactive gate as the reason Fukushima
  over-retains stations.
- Next implementation target should be the more literal `grid存在id` /
  `grid:検出id` carrier and the id-selection entry path:
  `検出id4_点に適用するべきIDを検索`,
  `検出id_グリッド別idと存在idをセット`, and
  `検出id_周囲gridの最新ID検索`.

### kotoho7 `grid:検出id` carrier and `検出id4` entry-source diagnostics

Continued from the article/sb3 carrier path and added a diagnostic proxy for
`grid:検出id` / `grid:検出id時間`. The implemented selection-source order is:

1. current grid id updated within 2s;
2. `検出id4-2_適用id震源から候補選択`;
3. around-grid latest id fallback.

This is still a station-code carrier proxy, not yet the full Scratch
`dc ten:点からグリッド番号` / 9-grid array model. Diagnostics are exposed under:

```text
stateful_source_cache.station_assignment_selection
```

with `added_source_counts`, `rejected_source_counts`,
`added_sources_sample`, and `grid_carrier_size`.

Validation:

```powershell
flutter analyze lib\core\source_estimation\source_estimator.dart test\support\source_estimation_benchmark.dart test\source_estimation_replay_case_runner_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/fukushima_aizu_m46_20260702_jma_p2p.json --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/shizuoka_west_m36_20260702_jma_p2p.json --concurrency=1
```

Replay result:

| Case | kotoho7 best | median / p90 | final | Entry-source finding |
|---|---:|---:|---:|---|
| `20260702_fukushima_aizu_m46_jma_p2p` | `8 km` | `97 km / 278 km` | `16 km` | Added-source aggregate: `scratch_4_2_source_cache=136`, `scratch_grid_around=30`; final assigned `160`. |
| `20260702_shizuoka_west_m36_jma_p2p` | `3 km` | `5.5 km / 9 km` | `3 km` | Added-source aggregate: `scratch_4_2_source_cache=91`; final assigned `95`. |

Interpretation:

- The Fukushima final error improved after grid-carrier/source evolution, but
  station over-retention still mostly enters through `検出id4-2`.
- Next target should focus on exact `検出id4-2` source-cache candidate windows
  and then replace the station-code carrier with a real grid-number / 9-grid
  proxy.

### kotoho7 `検出id4-2` `+5/+10` split and candidate reason diagnostics

The next pass expanded the sb3 `検出id4-2_適用id震源から候補選択` conditions and
implemented the missing distinction between:

- `4-3 +5`: max distance from first detected station to assigned stations;
- `4-3 +10`: source/epicentral max-distance proxy used only by the
  `age > 100s` wide-distance rejection.

Code changes:

- added `scratch43MaxSourceDistanceKm` and exposed it as
  `stateful_source_cache.scratch_4_3_proxy.max_source_distance_km`;
- changed the `distance > 900 km && age > 100s` rejection to use `+10`, while
  keeping the `age > 15s` rejection on `+5`;
- added
  `stateful_source_cache.station_assignment_selection.candidate_reason_counts`
  for `4-2` branch/accept/reject diagnostics.

Validation:

```powershell
flutter analyze lib\core\source_estimation\source_estimator.dart test\support\source_estimation_benchmark.dart test\source_estimation_replay_case_runner_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/fukushima_aizu_m46_20260702_jma_p2p.json --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/shizuoka_west_m36_20260702_jma_p2p.json --concurrency=1
```

Replay result:

| Case | kotoho7 best | median / p90 | final | Reason aggregate |
|---|---:|---:|---:|---|
| `20260702_fukushima_aizu_m46_jma_p2p` | `8 km` | `97 km / 278 km` | `16 km` | `accept_p_window=81`, `accept_s_range=55`, `reject_before_p_window=32`, `reject_after_s_window=10`; no wide-distance rejects. |
| `20260702_shizuoka_west_m36_jma_p2p` | `3 km` | `5.5 km / 9 km` | `3 km` | `accept_p_window=57`, `accept_s_range=34`, `reject_before_p_window=3`; no wide-distance rejects. |

Interpretation:

- The `+5/+10` distinction is now closer to sb3, but it does not by itself fix
  Fukushima over-retention.
- The over-retained stations are timing-compatible with the current source
  cache under Scratch's broad P/S window. Next work should move upstream:
  implement a real grid-number / 9-grid `grid:検出id` carrier and `grid存在id`
  model, then audit `ten:推定用 +1/+2/+6/+7/+8` updates before adding more HYP
  scoring penalties.

### kotoho7 grid-number carrier and 9-grid latest-id proxy

Continued from the sb3 entry path:

```text
検出id3_点にIDを登録
検出id4_点に適用するべきIDを検索
検出id_周囲gridの最新ID検索
```

Scratch expressions confirmed:

- `grid:検出id[dc ten:点からグリッド番号[point]] = ten:推定用 +3`;
- `grid:検出id時間[...] = #r:最新クラウド変数[1]`;
- current-grid id is reused only when the grid timestamp is within 2 seconds;
- around-grid latest-id scans the 23-column 9-neighborhood offsets
  `-24,-23,-22,-1,0,+1,+22,+23,+24`.

Code changes:

- replaced the previous station-code carrier with `_scratchGridByNumber`;
- added current-grid selection by computed grid number;
- added around-grid fallback over the Scratch 9-grid offset set, choosing the
  newest carrier within 5 seconds;
- exposed
  `stateful_source_cache.station_assignment_selection.grid_model =
  grid_number_23_column_025deg_latlon_proxy_v2`.

The grid number is still a replay-side proxy because the GIF replay records do
not include Scratch's original `dc ten:点からグリッド番号` table. The current proxy
uses 0.25-degree lat/lon cells while preserving the Scratch 23-column offset
semantics. A whole-Japan 23-column grid was tested and rejected because it was
too coarse: final carrier size collapsed to 9 cells and Shizuoka p90 degraded
from `9 km` to `39 km`.

Validation:

```powershell
flutter analyze lib\core\source_estimation\source_estimator.dart test\support\source_estimation_benchmark.dart test\source_estimation_replay_case_runner_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/fukushima_aizu_m46_20260702_jma_p2p.json --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/shizuoka_west_m36_20260702_jma_p2p.json --concurrency=1
```

Replay result:

| Case | kotoho7 best | median / p90 | final | Entry-source aggregate |
|---|---:|---:|---:|---|
| `20260702_fukushima_aizu_m46_jma_p2p` | `8 km` | `97 km / 278 km` | `16 km` | `scratch_4_2_source_cache=113`, `scratch_grid_current=35`, `scratch_grid_around_9=18`; final assigned `160`, grid carrier size `91`. |
| `20260702_shizuoka_west_m36_jma_p2p` | `3 km` | `5.5 km / 9 km` | `3 km` | `scratch_grid_current=25`, `scratch_4_2_source_cache=66`; final assigned `95`, grid carrier size `50`. |

Interpretation:

- This makes the membership trace closer to Scratch without regressing the
  stable Shizuoka case.
- Fukushima's remaining over-retention is still mostly allowed by `4-2` P/S
  timing compatibility, so the next step is not score tuning.
- Next target: recover or approximate the original `dc ten:点からグリッド番号`
  mapping more closely, implement the `周囲9grid最大震度or上昇` guard before
  around-grid fallback, and continue checking `ten:推定用 +6/+7/+8` PS-time
  recomputation.

### kotoho7 `周囲9grid最大震度or上昇` guard proxy

Implemented the guard that Scratch runs before borrowing the around-grid latest
id in `検出id4_点に適用するべきIDを検索`.

Because the replay records do not include Scratch's original grid arrays
(`grid:検出グリッド最大震度`, `grid:長期上昇観測点数`, and the original
`dc ten:点からグリッド番号` table), the Dart path uses the current 0.25-degree /
23-column grid proxy and current-frame station records:

- current point level from latest `rawLevel` / `detectLevel` / numeric value;
- surrounding 9-grid max level from current-frame records;
- surrounding rise support from current-frame `lastAscend > 0`;
- block around-grid borrowing when the current point is at least `1.5`, is not
  weaker than the surrounding max, and surrounding rise support is below `10`.

Diagnostics:

```text
stateful_source_cache.station_assignment_selection.model =
  scratch_detection_id4_order_current_grid_4_2_around_9_grid_guard_v3
around_grid_guard_model =
  scratch_surrounding_9_grid_max_shindo_or_rise_proxy_v1
candidate_reason_counts.around_9_grid_guard_current_activity
```

Validation:

```powershell
flutter analyze lib\core\source_estimation\source_estimator.dart test\support\source_estimation_benchmark.dart test\source_estimation_replay_case_runner_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/fukushima_aizu_m46_20260702_jma_p2p.json --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/shizuoka_west_m36_20260702_jma_p2p.json --concurrency=1
```

Replay result:

| Case | kotoho7 best | median / p90 | final | Guard impact |
|---|---:|---:|---:|---|
| `20260702_fukushima_aizu_m46_jma_p2p` | `8 km` | `97 km / 278 km` | `16 km` | Guard hit `14`; around-grid additions dropped `18 -> 15`; final assigned `160`. |
| `20260702_shizuoka_west_m36_jma_p2p` | `3 km` | `5.5 km / 9 km` | `3 km` | Guard hit `3`; stable metrics unchanged, final assigned `95`. |

Interpretation:

- This makes the around-grid borrowing path closer to Scratch and preserves the
  stable Shizuoka replay.
- Fukushima's remaining over-retention still enters through `検出id4-2` P/S
  timing windows, so the next implementation target should be
  `推定用tenPS時間計算` / `ten:推定用 +6/+7/+8` recomputation and station S/P
  classification.

### kotoho7 stateful `推定用tenPS時間計算` / `ten:+6/+7/+8`

Implemented the sb3 `推定用tenPS時間計算(多目的0,2使用)` behavior as explicit
state on each kotoho7 detection id:

```text
if 4-3 +11 > 3000 or source cache is missing:
  clear +7/+8
else:
  +7 = source origin + P travel time
  +8 = source origin + S travel time
  +6 = abs(+1 - +8) < abs(+1 - +7)
```

Code changes:

- added `scratchStationPArrivalSeconds`, `scratchStationSArrivalSeconds`, and
  `scratchStationSFlag` to `_Kotoho7HypState`;
- after each accepted HYP/source-cache update, recompute `+7/+8/+6` for all
  assigned stations;
- scoring now uses cached `+6` when present and only falls back to arrival
  closeness on no-cache frames;
- exposed diagnostics under
  `stateful_source_cache.station_ps_cache`.

Validation:

```powershell
flutter analyze lib\core\source_estimation\source_estimator.dart test\support\source_estimation_benchmark.dart test\source_estimation_replay_case_runner_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/fukushima_aizu_m46_20260702_jma_p2p.json --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/shizuoka_west_m36_20260702_jma_p2p.json --concurrency=1
```

Replay result:

| Case | kotoho7 best | median / p90 | final | PS-cache result |
|---|---:|---:|---:|---|
| `20260702_fukushima_aizu_m46_jma_p2p` | `8 km` | `97 km / 278 km` | `16 km` | Final cache `+7/+8=160`, `+6 true=46`; final phase counts `P=85`, `S=34`, `other=41`. |
| `20260702_shizuoka_west_m36_jma_p2p` | `3 km` | `5.5 km / 9 km` | `3 km` | Final cache `+7/+8=95`, `+6 true=35`; final phase counts `P=57`, `S=27`, `other=11`. |

Interpretation:

- P/S classification is now stateful and inspectable instead of only a scoring
  heuristic.
- Headline metrics are unchanged, which is acceptable here: this pass removes a
  semantic gap rather than tuning accuracy.
- Next target should inspect exact recomputation timing around
  `検出id適用数カウント追加(... 距離セット=true ...)` and
  `検出id_推定PS時間id別再計算(id)`, especially whether newly joined stations get
  `+6/+7/+8` immediately in every branch.

### kotoho7 `検出id適用数カウント追加(... 距離セット=true ...)`

Implemented the next Scratch state-machine layer: when a point is registered to
a detection id through `検出id3_点にIDを登録`, the following
`検出id適用数カウント追加(point, 距離セット=true, +1)` branch now has immediate
effects in Dart.

Scratch behavior being replicated:

```text
距離セット=true:
  推定用tenPS時間計算(point, id)  -> ten:+7/+8/+6
  検出id距離計算(point, id)      -> ten:+4 and 4-3 +5 max
```

Code changes:

- added `scratchStationFirstDistanceKm` to mirror `ten:推定用 +4`;
- newly assigned stations now immediately refresh cached `+7/+8/+6`;
- newly assigned stations now immediately refresh first-station distance `+4`
  and update `scratch43MaxFirstStationDistanceKm`;
- full post-HYP recomputation remains, so this is state-machine timing
  alignment, not scoring tuning;
- diagnostics now include
  `stateful_source_cache.station_distance_cache` and immediate recompute counts.

Validation:

```powershell
flutter analyze lib\core\source_estimation\source_estimator.dart test\support\source_estimation_benchmark.dart test\source_estimation_replay_case_runner_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/fukushima_aizu_m46_20260702_jma_p2p.json --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/shizuoka_west_m36_20260702_jma_p2p.json --concurrency=1
```

Replay result:

| Case | kotoho7 best | median / p90 | final | `距離セット=true` finding |
|---|---:|---:|---:|---|
| `20260702_fukushima_aizu_m46_jma_p2p` | `8 km` | `97 km / 278 km` | `16 km` | Best frame immediate recompute `18/18`; final distance cache `160`, max first-station distance `341.5 km`. |
| `20260702_shizuoka_west_m36_jma_p2p` | `3 km` | `5.5 km / 9 km` | `3 km` | Best frame immediate recompute `8/8`; final distance cache `95`, max first-station distance `202.9 km`. |

Interpretation:

- This confirms the immediate assignment branch is now exercised on real replay
  frames.
- Metrics did not move, which is acceptable for this pass: the prior full-cache
  refresh already covered many later frames, while this closes the exact Scratch
  timing gap at station entry.
- Next target should replicate the negative/reset side of the same pipeline:
  `検出id適用数カウント追加(..., -1)` and
  `検出id_点の推定用をリセット`, especially exact clearing/decrement behavior for
  `+3/+4/+6/+7/+8` when a station switches id or becomes inactive.

### kotoho7 negative count / station reset cleanup

Implemented the negative side of `検出id適用数カウント追加` and the observable
cleanup semantics of `検出id_点の推定用をリセット`.

Scratch behavior being replicated:

```text
if point already has ten:+3:
  検出id適用数カウント追加(point, 距離セット=false, -1)

reset point:
  clear +1/+2/+3/+4/+6/+7/+8
```

Code changes:

- station reset now returns a reason string instead of a bare boolean;
- reset now goes through one helper that:
  - removes the station from the current detection id (`ten:+3` equivalent);
  - applies immediate `scratch43AssignedCount -= 1` accounting;
  - clears lifecycle `+1/+2`, permission state, PS cache `+6/+7/+8`, first
    station distance `+4`, and station grid carrier;
- diagnostics now include reset reason counts, negative count delta, and cleared
  cache counts.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart test\support\source_estimation_benchmark.dart test\source_estimation_replay_case_runner_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/fukushima_aizu_m46_20260702_jma_p2p.json --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/shizuoka_west_m36_20260702_jma_p2p.json --concurrency=1
```

Replay result:

| Case | kotoho7 best | median / p90 | final | Reset accounting |
|---|---:|---:|---:|---|
| `20260702_fukushima_aizu_m46_jma_p2p` | `8 km` | `97 km / 278 km` | `16 km` | Aggregate reset count `2`, all `scratch_reset_current_shindo_zero`; negative delta `-2`; cleared `+3`, PS cache, and `+4` for 2 stations. |
| `20260702_shizuoka_west_m36_jma_p2p` | `3 km` | `5.5 km / 9 km` | `3 km` | Aggregate reset count `1`, `scratch_reset_current_shindo_zero`; negative delta `-1`; cleared `+3`, PS cache, and `+4` for 1 station. |

Interpretation:

- Reset cleanup is now faithfully observable, but these two real replay windows
  barely exercise it, so headline metrics are unchanged.
- The remaining mismatch is more likely in the point-centric reassignment
  ordering: Scratch can decrement the old id and increment the newly selected id
  when a point switches detection id, while the current Dart state-local pass
  treats another-id selection as rejection for that state.
- Next target should therefore be a closer `検出id2/3/4` point-centric assignment
  pass or at least a diagnostic that records would-switch-to-other-id events and
  compares them with current rejection counts.

### kotoho7 would-switch-to-other-id diagnostic

Added the diagnostic first, without changing assignment behavior. During a
state-local update, if `検出id4` would select another active detection id for a
station, Dart still rejects it for the current state but now records:

- total would-switch count;
- source counts;
- sample rows with station code, residual, current `sourceKeys`, selected
  target `sourceKeys`, target assigned count, and target active flag.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart test\support\source_estimation_benchmark.dart test\source_estimation_replay_case_runner_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/fukushima_aizu_m46_20260702_jma_p2p.json --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/shizuoka_west_m36_20260702_jma_p2p.json --concurrency=1
```

Replay result:

| Case | kotoho7 best | median / p90 | final | Would-switch finding |
|---|---:|---:|---:|---|
| `20260702_fukushima_aizu_m46_jma_p2p` | `8 km` | `97 km / 278 km` | `16 km` | would-switch total `0`, max/frame `0`; best rejected only `no_candidate=1`, final rejected `0`. |
| `20260702_shizuoka_west_m36_jma_p2p` | `3 km` | `5.5 km / 9 km` | `3 km` | would-switch total `0`, max/frame `0`; no rejected stations at best/final. |

Interpretation:

- The current P2P replay pair does not support the hypothesis that Fukushima's
  remaining over-retention is caused by missed cross-id station switches.
- Next target should inspect accepted same-id entries instead: enrich
  `検出id4-2` diagnostics so each accepted source-cache station records the
  selected accept reason, source distance, first-station distance, current
  shindo/rise support, and selected P/S timing window.

### kotoho7 accepted same-id `検出id4-2` diagnostics

Added diagnostic detail for stations accepted into the current detection id.
This is still diagnostic-only; assignment behavior is unchanged.

For each sampled accepted station, the replay now records:

- accept reason and selection source;
- source-cache vs first-point fallback branch;
- current shindo proxy, `lastAscend > 0`, and current-frame evidence;
- source distance, first-station distance, `4-3 +5` and `4-3 +10` limits;
- observed time, P/S predicted arrival, residual, and tolerance.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart test\support\source_estimation_benchmark.dart test\source_estimation_replay_case_runner_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/fukushima_aizu_m46_20260702_jma_p2p.json --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/shizuoka_west_m36_20260702_jma_p2p.json --concurrency=1
```

Replay result:

| Case | kotoho7 best | median / p90 | final | Accepted same-id finding |
|---|---:|---:|---:|---|
| `20260702_fukushima_aizu_m46_jma_p2p` | `8 km` | `97 km / 278 km` | `16 km` | Accepted totals: `P-window=70`, `S-range=46`, `grid_current=35`, `grid_around_9=15`. Far P-window samples around `260-332 km` pass because tolerance is `5 + distance/120` (`~7-8s`). |
| `20260702_shizuoka_west_m36_jma_p2p` | `3 km` | `5.5 km / 9 km` | `3 km` | Accepted totals: `P-window=37`, `S-range=29`, `grid_current=25`; no sampled far-distance accepts above `250 km`. |

Late Fukushima final-frame note:

- `YMNH10`: S-range, `214.1 km`, S residual `0.41s`, S tolerance `9.78s`;
- `NGN021`: S-range, `212.8 km`, S residual `0.88s`, S tolerance `9.77s`.

Interpretation:

- The last Fukushima additions are plausible S-window accepts, not obvious noise.
- The bigger retention mechanism is earlier P-window acceptance plus grid
  carrier propagation.
- Next target should compare the Dart proxy against the sb3 body of
  `検出id4-2_適用id震源から候補選択`, especially constants and gates for:
  source-cache age/score, P/S tolerance windows, `4-3 +5`, and `4-3 +10`.

### kotoho7 exact `検出id4-2` constants from sb3

Expanded the sb3 block tree for
`検出id4-2_適用id震源から候補選択 %s %s %s %s %s %s` from
`docs/assets/project.json`.

Confirmed exact Scratch constants:

```text
source-cache branch:
  age > 5
  4-3 +11 < 500
  4-4 source x is not empty

first-point fallback:
  4-3 +4 assigned count > 4
  source = first station
  depth = 10km
  origin = ten:+1 - 3

wide-distance reject:
  distance > 900
  and (
    age > 100 and 1.5 * 4-3 +10 < distance
    or
    age > 15 and 1.4 * 4-3 +5 < distance
  )

P/S timing:
  P accept if abs(P arrival - observed) <= 5 + distance / 120
  otherwise S accept if observed is between
    P arrival - (5 + distance / 120)
    and S arrival + (8 + distance / 120)
```

Dart diagnostics now explicitly label these as exact Scratch gates:

- `source_cache_gate_model`;
- `first_point_fallback_gate_model`;
- `timing_window_model`;
- `wide_distance_gate_model`.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart test\support\source_estimation_benchmark.dart test\source_estimation_replay_case_runner_test.dart
```

Interpretation:

- The wide P tolerance is not an accidental Dart proxy; it is in the sb3.
- Do not tighten the P/S windows if the immediate goal remains reproduction.
- The next likely mismatch is upstream data/ordering: exact current-frame
  `ten:震度` mapping, grid carrier freshness, and which GIF stations are allowed
  to enter `検出id4-2`.

### kotoho7 pre-`4-2` entry pipeline audit

Added diagnostic-only entry auditing before station assignment. It compares the
actual capped assignment candidates against the uncapped eligible timing pool and
records current-frame shindo/evidence/rise/grid-carrier status.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart test\support\source_estimation_benchmark.dart test\source_estimation_replay_case_runner_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/fukushima_aizu_m46_20260702_jma_p2p.json --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/shizuoka_west_m36_20260702_jma_p2p.json --concurrency=1
```

Replay result:

| Case | capped total | uncapped total | avg capped/frame | avg uncapped/frame | max uncapped/frame | Entry finding |
|---|---:|---:|---:|---:|---:|---|
| `20260702_fukushima_aizu_m46_jma_p2p` | `1588` | `13333` | `23.4` | `196.1` | `365` | Every capped/uncapped candidate had positive current-frame shindo/evidence. |
| `20260702_shizuoka_west_m36_jma_p2p` | `1128` | `3773` | `18.2` | `60.9` | `109` | Every capped/uncapped candidate had positive current-frame shindo/evidence. |

Interpretation:

- The current-frame `ten:震度` mapping is not obviously too broad on these cases:
  no stale/empty candidates are entering the assignment candidate pool.
- Fukushima has a very large real positive-shindo eligible pool, while Dart only
  feeds a capped 24 records/frame into assignment. Therefore over-retention is
  not explained by a too-large Dart entry pool.
- Next target should inspect exact Scratch point-loop ordering/cap semantics in
  `検出id1_全点へ適用` and `検出id2_各点の許可idと推定用をセット`: whether it iterates
  every positive point, changed/rising points only, or a grid-local subset.

### kotoho7 exact `検出id1/2/3/4` point-loop ordering

Expanded the sb3 point-loop procedures.

Confirmed:

```text
検出id1_全点へ適用:
  repeat len(d ten:x):
    検出id2_各点の許可idと推定用をセット(...)
```

So Scratch has no Dart-style `24` record assignment cap at this level. But it is
not a naive "all positive points enter 4-2" loop:

- `検出id2` first checks `ten:震度[point] > 0`;
- it maintains `+5` from recent rising shindo history;
- initial registration requires station-state and 7-nearest/support-point
  conditions before `+1/+2` are written and `検出id3` is called;
- re-rise registration has a separate state `5/6` and 7-point support branch;
- stale/low-state branches reset instead of registering.

`検出id3` then performs:

```text
old ten:+3 -> 検出id適用数カウント追加(..., -1)
choose id via latest-id shortcut or 検出id4
write ten:+3
write grid:検出id / grid:検出id時間
検出id適用数カウント追加(..., distanceSet=true, +1)
```

`検出id4` ordering:

```text
1. shortest-7 candidate
2. recent latest-id shortcut, first-station distance < 400km
3. current grid id if not re-rise and grid id age < 2s
4. source-cache 4-2 selection
5. surrounding-9-grid max/rise guard
6. around-grid latest id search with source-distance margin
7. if still none and enough ids exist, return -1
```

Diagnostics now label:

- `scratch_reference_point_loop_model =
  scratch_detection_id1_repeats_all_points_len_d_ten_x_without_24_cap`
- `scratch_id2_registration_gate_model =
  ten_shindo_positive_then_station_state_neighbor_support_or_rerise_before_id3`

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart test\support\source_estimation_benchmark.dart test\source_estimation_replay_case_runner_test.dart
```

Next target:

- Add a diagnostic/full-loop simulation over the uncapped positive-shindo pool
  that estimates how many points would pass the `検出id2` registration gates and
  reach `検出id3`. This should happen before removing the Dart cap, because
  Scratch's all-point loop is filtered by station-state and neighbor support.

### kotoho7 diagnostic `検出id2` full-loop gate simulation

Added a diagnostic-only full-loop simulation over the uncapped positive-shindo
pool. This does not change assignment behavior and does not remove the current
24-row Dart cap.

Proxy caveat:

- Scratch uses `ten c:揺れ検出許可` and `dc ten:最短7点`.
- Historical note: this diagnostic originally used
  `scratchStationPermissionState` / `_initialKotoho7StationPermissionState`
  (`activeLike -> state 5`). That fallback is now superseded by the 2026-07-04
  `検出id2` current-state correction: live `id2` input is
  `scratchDetectionPermissionState` / `ten c:揺れ検出許可`, with unknown stations
  starting at `0`.
- Geographic nearest-7 was used as a proxy in that historical diagnostic.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart test\support\source_estimation_benchmark.dart test\source_estimation_replay_case_runner_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/fukushima_aizu_m46_20260702_jma_p2p.json --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/shizuoka_west_m36_20260702_jma_p2p.json --concurrency=1
```

Replay result:

| Case | uncapped pool | would call `id3` | avg would-id3/frame | max would-id3/frame | Dominant proxy decision |
|---|---:|---:|---:|---:|---|
| `20260702_fukushima_aizu_m46_jma_p2p` | `13333` | `11143` | `163.9` | `315` | `initial_state5_direct=11143` |
| `20260702_shizuoka_west_m36_jma_p2p` | `3773` | `2434` | `39.3` | `89` | `initial_state5_direct=2434` |

Interpretation:

- With the current Dart permission fallback, removing the 24 cap would explode
  station membership pressure.
- The diagnostic points to the next real mismatch: not the cap itself, but the
  upstream permission-state pipeline. Dart's fallback `activeLike -> state 5`
  is probably too permissive for never-registered stations.
- Next target should inspect and reproduce `ten c:揺れ検出許可`,
  `点許可状態更新`, and `gridトリガ` before attempting full Scratch all-point
  assignment.

### kotoho7 `単独トリガ` / `複数トリガ` permission audit

The sb3 block audit has now moved one layer earlier than `検出id2`. The important
finding is that Scratch does not make an unseen active point state `5` directly.
State `5` is created by the permission-state trigger procedures:

- `単独トリガ 状態` can write `0/1/3/4/5`. Its state `5` paths are explicit
  trigger-confirmation branches such as `時間overから上昇`, `円の中トリガ`,
  `通常許可`, and nearby auxiliary permission.
- `複数トリガ 状態` is the main neighboring-support stage. It can demote weak or
  stale points to `0/1`, and can promote points to `5` or `6` from surrounding
  trigger / permission support.
- `gridトリガ` only upgrades points that already have
  `ten c:揺れ検出許可 > 0`; it is not a blanket active-point permission rule.
- `点許可状態更新` refreshes trigger time for most promoted states, but state `6`
  intentionally does not refresh time unless forced or the trigger time was
  still zero.

Implemented diagnostic-only comparison in
`Kotoho7ReferenceHypSourceEstimator`:

- historical proxy: unknown station fell back to
  `_initialKotoho7StationPermissionState`.
  Superseded on 2026-07-04: live `検出id2` now reads
  `scratchDetectionPermissionState` / `ten c:揺れ検出許可`; unknown stations
  start as `0`;
- strict comparison: unknown station starts as state `0`, unless already present
  in `scratchStationPermissionState`.

Replay result for `nied_gif_hyp_kotoho7_reference_replay_v1`:

| Case | Uncapped pool | Old proxy would call `id3` | Strict unknown=0 would call `id3` |
|---|---:|---:|---:|
| `20260702_fukushima_aizu_m46_jma_p2p` | `13333` | `11143` | `617` |
| `20260702_shizuoka_west_m36_jma_p2p` | `3773` | `2434` | `96` |

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart test\support\source_estimation_benchmark.dart test\source_estimation_replay_case_runner_test.dart
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/fukushima_aizu_m46_20260702_jma_p2p.json --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/shizuoka_west_m36_20260702_jma_p2p.json --concurrency=1
```

Next step:

- implement a real Scratch-like permission-state cache for
  `ten c:揺れ検出許可` using GIF history proxies for `単独トリガ 状態` /
  `複数トリガ 状態`;
- keep the 24-row cap until that cache is in place, because the previous proxy
  is demonstrably too broad.

### First `ten c:揺れ検出許可` cache scaffold

Implemented the first independent detection permission cache in
`Kotoho7ReferenceHypSourceEstimator`:

- `scratchDetectionPermissionState` for `ten c:揺れ検出許可`;
- `scratchDetectionTriggerAt` for `ten c:揺れ検出トリガー時間`;
- `scratchDetectionPermissionReason` for diagnostics;
- station lifecycle initialization now prefers this permission cache;
- nearest-7 support and `検出id2` diagnostic now read the cache before the older
  station lifecycle permission state;
- `ten:震度変化速度` proxy now uses current GIF frame history first, instead of
  treating sticky `lastAscend` as current-frame speed.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart test\support\source_estimation_benchmark.dart test\source_estimation_replay_case_runner_test.dart
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/fukushima_aizu_m46_20260702_jma_p2p.json --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/shizuoka_west_m36_20260702_jma_p2p.json --concurrency=1
flutter test test\source_estimator_test.dart --concurrency=1
```

### 2026-07-05 kotoho7/Scratch rerise fidelity checkpoint

Status: continued Scratch/SB3 reproduction work for the depth/source-estimation
path. This is intentionally not a HYP-score tuning pass.

Confirmed from
`.dart_tool/external_refs/scratch-realtime-earthquake-viewer-page/docs/assets/project.json`:

- The local v1.6.3 SB3 does not contain the `検出id*` pipeline; the web project
  does, so the web project remains the source for this reproduction.
- `検出id2` rerise is state-sensitive:
  - state `5` normally only refreshes `ten:+2`;
  - state `5` re-enters `検出id3` only through the `Infinity` path caused by a
    newer nearest-7 detection id;
  - state `6` is the normal rerise waiting state and can promote back to state
    `5` / call `検出id3(再上昇=true)` when the nearest-7 score is strong enough.
- The rerise nearest-7 scan must use Scratch `dc ten:最短7点` all-station
  neighbors, not only stations present in the current replay candidate pool.
- `推定用tenPS時間計算` clears only `ten:+7/+8` when the detection-id score is
  above `3000` or the `4-4` source cache is missing; it does not clear `ten:+6`.

Implemented in `lib/core/source_estimation/source_estimator.dart`:

- `_kotoho7Id2ReriseScore` now receives `currentState`, uses all-station
  nearest-7 neighbors, and follows the state `5` vs state `6` SB3 split.
- `_kotoho7Id2GatedAssignmentCandidates` now uses the same rerise score instead
  of the previous compressed `state == 6 && nearest7Support > 0` proxy.
- The invalid `推定用tenPS` branch now gates on the `4-3 +11` score proxy plus
  4-4 source-cache availability, preserves the S flag (`+6`), and clears only
  P/S predicted-arrival caches (`+7/+8`).
- `検出id距離計算` was decoded and confirmed: `ten:+4` is distance from the
  first detection point (`4-3 +1`), not distance from the current source.
- `HYP:誤差レベル計算` was decoded and confirmed to read `ten:+6` for S-phase
  usage; it does not recompute P/S identity per candidate during the HYP search.

Current replay checkpoint:

| case | best | median | p90 | final | note |
| --- | ---: | ---: | ---: | ---: | --- |
| Fukushima offshore M3.2 | 82 km | 85 km | 237 km | 82 km | final phase P:3 / S:11 / O:40 |
| Iwate east offshore M3.0 | 3 km | 14 km | 15 km | 14 km | final phase P:7 / S:12 / O:2 |
| Tomakomai south offshore M3.5 | 85 km | 88 km | 112 km | 85 km | final phase P:6 / S:1 / O:10; depth remains unsupported |

Next step:

- Do not tune HYP score yet.
- Continue SB3 reproduction at the station re-registration / PS-cache lifecycle.
  Tomakomai still has 17 assigned stations but only 13 P/S cache rows and zero
  `+6` S flags at final. The current missing rows are diagnosed as
  `not_recomputed_since_source_cache_became_valid`, so the next concrete
  question is why early members that entered before a useful source cache do
  not naturally re-enter `検出id3`, and whether any non-obvious caller can
  legitimately run `検出id_推定PS時間id別再計算`.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\kotoho7_scratch_reference_tables.dart test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\fukushima_offshore_reference_replay_test.dart test\iwate_east_offshore_reference_replay_test.dart test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
```

### 2026-07-04 correction: kotoho7 reference path must not use raw/member proxies

User correction accepted: the kotoho7 path is a reproduction target, so raw
trigger membership and Dart active-like shortcuts must not be used as algorithm
substitutes.

Code correction:

- removed the default-off `current_raw_member_ids` grid-presence experiment from
  code and docs;
- changed the default kotoho7 assignment mode to
  `scratch_full_point_id2_gate`;
- the default path now feeds all timing-usable points through the decoded
  `検出id2` predicate before `検出id3/4` assignment;
- removed the fallback inside `_kotoho7Id2GatedAssignmentCandidates` that
  force-fed capped/uncapped candidates when fewer than three points passed id2;
- changed new detection-id creation to start from one point, matching
  `検出id_新規id追加(point)`, instead of seeding a whole trigger member group;
- removed the Dart-only immediate `assignedCount < 2` inactive gate;
- changed unknown station permission fallback from `activeLike/rising -> 5` to
  strict `0`, so only the permission cache can promote stations toward id2.

Static validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart test\support\source_estimation_benchmark.dart
flutter analyze lib\core\source_estimation\source_estimator.dart test\support\source_estimation_benchmark.dart
```

Remaining reproduction gaps to attack next, in order:

1. replace `_kotoho7DetectionAccelerationProxy` with the exact
   `揺れ検出許可 / 加速追加 / NG加速 / 通常許可` SB3 state update;
2. replace `_applyKotoho7GridTriggerPermissionProxy`,
   `_kotoho7GridLongRiseProxy`, and `_kotoho7GridDetectionMaxProxy` with exact
   `検出許可震度算出` + `gridトリガ`;
3. then revisit `検出id3` re-registration for existing `ten:+3` stations and
   exact `検出id適用数カウント追加(-1/+1)` slot side effects.

## 2026-07-03 update: Scratch `+6/+7/+8` shadow-cache diagnostic

Implemented a diagnostic-only shadow P/S cache for kotoho7/Scratch `ten:推定用`
slots:

- `+6`: S flag
- `+7`: predicted P arrival
- `+8`: predicted S arrival

Production behavior is unchanged: the estimator still uses the full-refresh
stateful P/S cache for final HYP scoring. The shadow cache is updated only by
Scratch-like slot lifecycle events:

- assignment;
- state-6 rerise re-register path;
- reset / invalidate / same-source merge.

The generated Scratch extraction now includes the previously omitted procedures:

- `推定用tenPS時間計算(多目的0,2使用) %s %s`
- `検出id_推定PS時間id別再計算 %s`

Decoded formula:

```text
+7 = source origin offset + JMA2001 P travel time
+8 = source origin offset + JMA2001 S travel time
+6 = abs(+1 - +8) < abs(+1 - +7)
```

Important correction: state-5 positive-change `+2` updates do **not** call
`推定用tenPS時間計算`.

Execution-order audit from the sb3:

```text
揺れ検出許可
→ 検出許可震度算出
→ 検出id1_全点へ適用
→ 円検出の毎処理
→ broadcast 推定震源計算
→ HYP:震源検出
```

This means `ten:+3` membership is assigned before HYP refreshes the source
cache. The current Dart post-HYP full refresh is kept as a next-frame
phase-cache bridge, not as a production algorithm change. It compensates for the
sb3-defined but currently uncalled `検出id_推定PS時間id別再計算`.

Hot-path caution:

- `検出id3_点にIDを登録` can re-register existing members and call
  `検出id適用数カウント追加(..., 距離セット=true, ...)`, which in turn calls
  `推定用tenPS時間計算`.
- Do not probe this by adding per-frame existing-member accounting to the
  estimator metadata; in the Fukushima replay runner this pushed the benchmark
  to the 5-minute timeout boundary. Build a separate offline report instead.

New metadata:

```text
stateful_source_cache.station_ps_cache_shadow
```

It reports:

- shadow cache counts;
- missing shadow S flag count;
- production-vs-shadow S flag disagreements;
- P/S arrival absolute deltas;
- same-source shadow rescore using the shadow S flags.

Fukushima Aizu M4.6 (`20260702_fukushima_aizu_m46_jma_p2p`) final-frame result:

| Path | Horizontal error | Depth | Score | P/S/O |
|---|---:|---:|---:|---:|
| production full-refresh cache | `17.95 km` | `40 km` | `156.05` | `89/20/25` |
| diagnostic event-driven shadow rescore | same source | `40 km` | `347.52` | `64/13/57` |

Shadow-vs-production final-frame deltas:

- assigned count: `134`
- shadow P/S arrival count: `112`
- missing shadow `+6`: `22`
- S-flag disagreements: `21`
- mean P-arrival delta: `5.34 s`
- mean S-arrival delta: `10.36 s`

Decision:

- Do **not** promote event-driven shadow `+6/+7/+8` to production.
- The current evidence says the remaining mismatch is the exact Scratch
  bulk-recompute timing for `ten:+3` members, not a local-search cap and not a
  reason to replace full refresh with the naive shadow cache.
- Next: continue decoding the article/sb3 procedures that write or clear
  `ten:推定用 +3/+6/+7/+8`, then rerun the shadow comparison as a guardrail.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
python tools\extract_scratch_hyp_algorithm.py
python -m py_compile tools\extract_scratch_hyp_algorithm.py
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/fukushima_aizu_m46_20260702_jma_p2p.json --concurrency=1
```

### kotoho7 `検出id_消えたidに対応する検出無効化` exact slot mapping

Decoded the local sb3 block graph for
`検出id_消えたidに対応する検出無効化`.

Relevant Scratch row semantics:

- `4-3 +2`: active flag;
- `4-3 +3`: base detection time for age/lifetime checks;
- `4-3 +4`: apply/assigned count;
- `4-3 +5`: max first-station distance proxy;
- `4-3 +6`: current max shindo/status proxy;
- `4-3 +7`: latched previous max shindo/status, set to `+6` when `+9` has not
  expired;
- `4-3 +9`: lifetime expiry timestamp;
- `4-3 +11`: best source/HYP score.

Extracted inactive logic:

```text
if id is present in @1 grid存在id:
  expiryWindow = +4 < 200 ? (3 + +4) * 2 : 400
  +9 = max(+9, +3 + expiryWindow)
  if +9 < now: +2 = false
  else: +7 = +6
  if now - +3 > 150 and +4 < 50: +2 = false
  if +4 < 5 and +5 < 80 and +11 > 3000 and +6 < 3 and now - +3 > 10:
    +2 = false
else:
  if now - +3 > 2: +2 = false
```

Implemented in Dart:

- `_updateScratch43ActiveState` now follows this extracted ordering.
- Added diagnostics:
  - `expire_window_s`;
  - `grid_presence_count`;
  - `grid_presence_disappeared_age_s`;
  - `slot_plus_6_current_max_shindo`;
  - `slot_plus_7_previous_max_shindo`.

Protected boundary:

- The exact Scratch `len(@1 grid存在id) == 0` branch clears all `4-3/4-4`
  state. The Dart replay path still keeps a current-frame evidence guard so
  known local capture gaps do not erase an otherwise valid state. Revisit this
  as a strict-live option after complete GIF frame continuity is guaranteed.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
flutter test test\fukushima_aizu_reference_replay_test.dart --concurrency=1
```

### 2026-07-05 kotoho7/Scratch ID2 state-5 initial ID3 correction

Status: implemented and verified against Tomakomai.

The next reproduction step was to stop tuning HYP score and continue tracing
the SB3 ID pipeline. Re-expanding `検出id2_各点の許可idと推定用をセット`
found a concrete missing branch in Dart:

- when `ten:+1` is empty and `現在状態 == 5`, Scratch enters
  `検出id3_点にIDを登録` even if `変化速度 > 0`;
- Dart previously allowed the direct state-5 initial ID3 path only in the
  non-rising branch.

Change:

- `_kotoho7Id2WouldCallId3` now treats
  `!hasPlus1 && currentState == 5` as ID3-eligible for both rising and
  non-rising frames.
- Diagnostic classification was updated to report this as
  `would_id3_initial_state5_direct`.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\kotoho7_scratch_reference_tables.dart test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
```

Current Tomakomai kotoho7 replay result:

- `estimateCount=38`
- `medianErrorKm=20.0`
- `p90ErrorKm=22.6`
- last valid estimate: `42.0167N, 141.5833E, depth=30km`
- last valid error: `20.0km`
- phase counts: `P=3 / S=7 / O=6`

Three-case replay after the correction:

| case | estimate count | median error | p90 error | last error | last depth | last P/S/O |
|---|---:|---:|---:|---:|---:|---|
| `20260621_fukushima_offshore_m32_eq6` | 45 | 62km | 146km | 62km | 10km | 7 / 11 / 34 |
| `20260622_iwate_east_offshore_m30_hinet` | 36 | 27km | 28.5km | 27km | 10km | 7 / 9 / 5 |
| `20260622_tomakomai_south_offshore_m35_hinet` | 38 | 20km | 22.6km | 20km | 30km | 3 / 7 / 6 |

Tomakomai depth checkpoint:

- At the last valid frame, the same-location depth candidates do not show a
  hidden preference for the Hi-net `100km` depth. The local stage reports
  `30km score=429`, `40km score=435`, and `80km score=588`.
- Therefore the remaining depth mismatch is not a depth-search cap problem.
  It is caused upstream by the station/phase set passed into HYP: assigned
  membership peaks at only `16` stations by `20:38:32 JST`, then stops growing,
  with final phase counts `P=3 / S=7 / O=6`.

Remaining next step:

- Continue following article/SB3, not score tuning: inspect the early/mid
  `検出id2 -> 検出id3 -> 検出id4` membership path between
  `20:38:24` and `20:38:32 JST`, because Tomakomai stops at 16 assigned
  stations while the expected JQ/EQ-style final phase set is much more S-rich.
- In particular, compare the exact `ten c:揺れ検出許可` state transitions and
  `検出id4-1/4-2` acceptance/rejection reasons for stations that are in the
  source-trigger continuity member list but never get `ten:+3` assigned.

### kotoho7 `4-4 検出id震源要素` source-cache slot mapping

Decoded the local sb3 writes from `epi最大距離`, `HYP:震源検出`, and
`HYP:誤差レベル計算`.

`4-4` row semantics:

```text
offset = (id - 1) * 10
+2 = source longitude, rounded to 1/60 degree
+3 = source latitude, rounded to 1/60 degree
+4 = source depth km, rounded
+5 = source origin / 発生時刻, rounded cloud seconds
```

Seed/reuse rule from `HYP:震源検出`:

```text
if 4-4 +2 is empty OR age < 10:
  seed from first detected station, depth 10, origin firstDetection - 2
else:
  reuse 4-4 +2/+3/+4/+5
```

Stage correction implemented:

- `start-h2` is only executed when `4-3 +4 > 10`.
- `age < 10` is now the reseed condition; `age == 10` reuses the existing
  source-cache, matching Scratch's strict `<` block.
- Diagnostics now include `stateful_source_cache.scratch_4_4_source_cache`
  with seed mode, slot proxy fields, and Scratch stage limits.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
flutter test test\fukushima_aizu_reference_replay_test.dart --concurrency=1
```

### kotoho7 `HYP:誤差レベル計算` score-component diagnostics

Decoded the final score expression from the local sb3.

Scratch score shape:

```text
errorLevel =
  max(0.25, 1 - (SCount * 3 / detectedCount))
  * ((weightedResidualSquares + unarrivedCount) / weightSum)
  * (30 + 20000 / (1 + detectedCount^2) + 2000 / (50 + detectedCount))
```

Additional semantics:

- `SCount` is a score multiplier input: S-rich candidates can reduce the final
  error level, but not below `0.25x`.
- unarrived penalty is count-like (`+1` for each predicted-arrived P that has
  not been detected).
- candidate source lon/lat/depth/origin is updated only when the new
  `errorLevel` is lower than `@hyp:最小誤差レベル`.

Implemented diagnostics:

- final estimate now includes `scratch_error_level_components`;
- each search stage row includes:
  - `s_factor`;
  - `s_flag_count`;
  - `weighted_residual_squares`;
  - `weight_sum`;
  - `station_count_scale`;
  - `unarrived_gate_open`.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
flutter test test\fukushima_aizu_reference_replay_test.dart --concurrency=1
```

### kotoho7 `HYP:誤差レベル計算` stop gates and grid-scan boundary

Decoded the front-half gate and grid scan conditions.

Scratch candidate stop gates:

```text
depth < 10
depth > 700
depth > @hyp:許可最大深さ
lon outside 115..155
lat outside 15..55
distance(candidate, firstDetectedStation) > @hyp:許可最大距離
```

Scratch grid-scan semantics:

- detected samples are points whose `ten:+3` equals the target id;
- non-target points can enter the unarrived list only near the P-wave radius
  and through Scratch's grid/id conditions;
- when `4-3 +4 >= 30`, Scratch randomly thins non-target points to control
  computation cost.

Dart status:

- scoring remains deterministic: assigned timing records are detected samples;
- the request/replay `unarrived` records are filtered by
  `maxDetectedDistance + 30 km` before count-like penalties;
- random grid thinning is not reproduced yet.

Added diagnostics:

- invalid candidate `reject_reason`;
- `distance_from_first_detected_km`;
- `max_allowed_depth_km`;
- `max_allowed_distance_km`;
- `unarrived_input_count`;
- `unarrived_within_radius_count`;
- `grid_scan_proxy`.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
flutter test test\fukushima_aizu_reference_replay_test.dart --concurrency=1
```

### kotoho7 deterministic Scratch grid-scan proxy diagnostics

Added a diagnostic-only deterministic proxy for the Scratch grid scan in
`HYP:誤差レベル計算`.

Behavior:

- scan a populated grid when it has any active detection id, or when the grid is
  within `P-surface-radius + 130 km`;
- count target-id stations as detected samples when they have timing;
- count non-target stations as deterministic unarrived candidates when they are
  within `P-surface-radius + 30 km`, or when their grid is carried by the target
  id;
- do not reproduce Scratch's random thinning yet.

Diagnostics:

- `scratch_error_level_components.grid_scan_proxy_diagnostics`;
- includes scanned grid/point counts, detected count, deterministic unarrived
  candidate counts, active-vs-inactive split, and sample stations.

Current status:

- diagnostic-only; scoring still uses assigned timing records plus the existing
  deterministic request/replay unarrived list.
- next step: add an experiment branch that scores from deterministic grid-scan
  detected/unarrived sets and compare it on Tomakomai/Fukushima/Iwate samples.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
flutter test test\fukushima_aizu_reference_replay_test.dart --concurrency=1
```

### kotoho7 deterministic grid-scan score comparison branch

Extended the diagnostic grid-scan proxy to return deterministic detected and
inactive-unarrived record sets. The final selected source is now rescored with
those sets using `_scoreKotoho7HypCandidate`.

Diagnostics:

- `scratch_error_level_components.grid_scan_score_comparison`;
- includes current-vs-grid-scan score, detected count, unarrived penalty,
  S-factor, weight sum, phase counts, and reject reason.

Current boundary:

- diagnostic-only; production estimate is unchanged;
- rescoring uses the already-selected final source, not a full staged local
  search over grid-scan inputs;
- random thinning remains disabled to keep replay outputs deterministic.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
flutter test test\fukushima_aizu_reference_replay_test.dart --concurrency=1
flutter test test\iwate_offshore_reference_replay_test.dart --concurrency=1
```

### kotoho7 capped deterministic grid-scan staged search comparison

Added a parallel diagnostic staged local search where every candidate is scored
from deterministic Scratch grid-scan detected/unarrived sets.

Status:

- diagnostic-only; production estimate is unchanged;
- deterministic; random thinning remains disabled;
- capped for replay latency: h2=8, h10=12, v50=16, v10=16, h60=6.

Diagnostics:

- `scratch_error_level_components.grid_scan_search_comparison`;
- includes current vs grid-scan source, score, horizontal shift, depth delta,
  residual/phase/unarrived/S-factor fields, and per-stage rows.

Next use:

- compare Tomakomai/Fukushima/Iwate reports to see whether grid-scan candidate
  scoring pulls the search toward more plausible depth/offshore geometry before
  considering any production switch.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
flutter test test\fukushima_aizu_reference_replay_test.dart --concurrency=1
flutter test test\iwate_offshore_reference_replay_test.dart --concurrency=1
```

Current replay comparison:

| Case | Pool | Old proxy would call `id3` | Strict unknown=0 would call `id3` | Permission cache would call `id3` | Final error |
|---|---:|---:|---:|---:|---:|
| `20260702_fukushima_aizu_m46_jma_p2p` | `13333` | `10934` | `820` | `8362` | `16 km` |
| `20260702_shizuoka_west_m36_jma_p2p` | `3773` | `2424` | `106` | `2329` | `3 km` |

Important conclusion:

- The layer boundary is now correct: `ten c:揺れ検出許可` is no longer just
  `activeLike`.
- The v1 cache is still too broad, especially on Fukushima.
- Do not remove the 24-row cap yet.
- Next target is the exact `複数トリガ 状態` internals: `加速追加`, `NG加速`,
  threshold-letter checks, and nearest-7 support scoring.

### kotoho7 `複数トリガ` low-state cleanup and promotion gate

Expanded the sb3 `複数トリガ 状態` conditions. Important confirmed semantics:

- high permission states (`>4`) can be demoted to state `1` after 10s when the
  converted shindo is low and speed is not rising (`震度一定以下`);
- state-5 promotion is gated by recent nearby permitted points, high surrounding
  shindo count, accumulated acceleration score, and `NG加速` geometry checks;
- `加速追加` only adds to `@1 c:揺れ検出用[4]`, which is later compared against
  the `通常許可` threshold.

Implemented a closer proxy in the permission cache:

- demote state `5/6` to `1` when converted shindo is low after 10s and not
  rising;
- require stronger current signal for state-5 promotion;
- require stronger current signal for one-point provisional state `4`.

Replay result:

| Case | Pool | Old proxy would call `id3` | Strict unknown=0 would call `id3` | Permission cache would call `id3` | Final error |
|---|---:|---:|---:|---:|---:|
| `20260702_fukushima_aizu_m46_jma_p2p` | `13333` | `10934` | `625` | `3109` | `16 km` |
| `20260702_shizuoka_west_m36_jma_p2p` | `3773` | `2424` | `84` | `435` | `3 km` |

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart test\support\source_estimation_benchmark.dart test\source_estimation_replay_case_runner_test.dart
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/fukushima_aizu_m46_20260702_jma_p2p.json --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/shizuoka_west_m36_20260702_jma_p2p.json --concurrency=1
flutter test test\source_estimator_test.dart --concurrency=1
```

Next target:

- implement the actual sb3 acceleration accumulator
  (`@1 c:揺れ検出用[1..10]`) plus `加速追加` / `NG加速`, then re-evaluate whether
  the all-point loop can safely replace the current 24-row cap.

### SB3 `@1 c:揺れ検出用[1..10]` accumulator pass

Implemented the first direct pass from the local
`リアルタイム地震ビューアー v1.6.3.sb3` procedures, not from replay tuning.

Code changes:

- `NiedStationDb` order is now treated as Scratch station order for diagnostics;
- NIED descriptors now include `scratch_station_index`, `threshold_code`,
  `pixel_x`, and `pixel_y`;
- the permission cache acceleration branch now models Scratch
  `@1 c:揺れ検出用`:
  - `c[1]`: nearest-7 points beyond `5 * elapsed - 2`;
  - `c[2]`: those within `12 * (elapsed + 4)`;
  - `c[3]`: close points with permission state `> 1`;
  - `c[4]`: score accumulated only through `加速追加`;
  - `c[5..10]`: two `NG加速` screen-geometry boundary caches;
- `通常許可` now uses the sb3 gate:
  `minimumPointCount - 2 < c[3]` and `0.3 + c[2] / 22.5 < c[4]`.

Later corrections:

- `ten c:検出許可済み震度` is now represented by
  `scratchDetectionPermittedShindo`, following the current/capped value behavior
  decoded from `検出許可震度算出`.
- `@1 ten:最高震度更新時刻` is represented by
  `scratchStationMaxShindoUpdatedAt`.
- `dc ten:最短7点` now reads the serialized Scratch nearest-7 table; geographic
  generation is only a defensive fallback.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart lib\services\sources\nied_source_estimation_driver.dart lib\core\source_estimation\station_event_tracker.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\services\sources\nied_source_estimation_driver.dart lib\core\source_estimation\station_event_tracker.dart
flutter test test\source_estimator_test.dart --concurrency=1
```

### kotoho7 exact `検出id4` rerise/current-grid and `count2=-1` control flow

Continued the direct SB3/article reproduction of `検出id3/4`, using
`.dart_tool/external_refs/scratch-realtime-earthquake-viewer-page/docs/assets/project.json`
as the source of truth.

Decoded `検出id4_点に適用するべきIDを検索` details:

```text
after nearest-7 and latest-id distance:
  if NOT(再上昇) && count2 == 0:
    current-grid shortcut may select grid:検出id[current grid]

after source-cache 4-2 and around-grid search:
  if count2 == 0 && 20 < LEN(4-3 検出id別情報):
    count2 = -1
```

Implemented in Dart:

- `_selectKotoho7StationSourceState(... isRerise)` now carries the Scratch
  `再上昇` flag into `検出id4`;
- current-grid carrier selection is skipped only for rerise, matching
  `NOT(再上昇)`;
- no-candidate selection now honors the final `count2=-1` branch when more than
  one `4-3` detection-id row exists, so Dart resets/rejects instead of creating
  a proxy mid-frame id;
- rerise reset clears station lifecycle after the prior membership `-1`,
  preserving the previously corrected `ten:+5` behavior.

Validation passed:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\kotoho7_scratch_reference_tables.dart test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\fukushima_offshore_reference_replay_test.dart test\iwate_east_offshore_reference_replay_test.dart test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
```

Effective-id replay metrics after the stricter Scratch control flow:

| Case | best | median / p90 | final |
|---|---:|---:|---:|
| `20260621_fukushima_offshore_m32_eq6` | `57 km` | `72 / 151 km` | `57 km` |
| `20260622_iwate_east_offshore_m30_hinet` | `13 km` | `102 / 107 km` | `30 km` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `49 km` | `54 / 65 km` | `54 km` |

This deliberately removes an older proxy behavior that created mid-frame ids
when Scratch would return `count2=-1`. Iwate therefore worsens in median error
until the upstream Scratch inputs are reproduced more exactly. The next work
should continue upstream, not tune HYP scoring:

1. exact `ten c:揺れ検出許可` state inputs feeding `検出id2`;
2. exact `dc ten:最短7点` ordering/offsets feeding `検出id4-1`;
3. exact grid carrier timing and `grid:検出id` lifecycle feeding current-grid
   and around-grid branches.

### kotoho7 `検出id4-1` all-station nearest-7 correction

Follow-up SB3 comparison found that Dart was still filtering `検出id4-1`
nearest-7 inheritance through the current replay pool. Scratch does not:
`dc ten:最短7点` is a global station table, and `検出id4-1` only needs the
neighbor station index, permission state, `ten:推定用 +3`, and `ten:+1` time.

Implemented:

- added `_kotoho7Nearest7StationCodes`, returning the full Scratch all-station
  nearest-7 code table when available;
- `検出id4-1` now uses that table, so a neighbor can provide an existing id even
  when it is absent from the current `allTimingUsable` pool;
- ID2 permission-5 support count also uses the all-station table, matching the
  global `ten c:揺れ検出許可` list;
- diagnostic label updated from the old geographic proxy name to
  `scratch_dc_ten_shortest7_all_station_table_with_generated_fallback_v1`.

Validation passed:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\kotoho7_scratch_reference_tables.dart test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\fukushima_offshore_reference_replay_test.dart test\iwate_east_offshore_reference_replay_test.dart test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
```

Effective-id replay metrics:

| Case | best | median / p90 | final |
|---|---:|---:|---:|
| `20260621_fukushima_offshore_m32_eq6` | `60 km` | `72.5 / 156.1 km` | `60 km` |
| `20260622_iwate_east_offshore_m30_hinet` | `3 km` | `14 / 14.5 km` | `14 km` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `85 km` | `88 / 107 km` | `85 km` |

Iwate confirms the all-station `4-1` path is necessary. Tomakomai worsened,
which points the next reproduction step back upstream: continue exact
`ten c:揺れ検出許可` and `ten:+1/+2/+5/+6/+7/+8` phase lifecycle replication
instead of tuning HYP scoring.

### kotoho7 global shared `ten c:揺れ検出許可`

Continued upstream reproduction after the all-station nearest-7 fix.

Finding:

- Scratch's `ten c:揺れ検出許可`, trigger-time cache, acceleration work values,
  permitted-shindo cache, and `grid:検出グリッド最大震度` are global station/grid
  lists.
- Dart still stored them per `_Kotoho7HypState`, so secondary detection ids
  could make `検出id2` / `検出id4-1` decisions from stale copied state.

Implemented:

- estimator-level shared maps for `ten c:*`, acceleration diagnostics,
  permitted shindo, station max shindo, and grid detection max/keep;
- new detection-id states now share those maps by reference;
- source-id invalidation no longer clears global permission/grid state;
- diagnostics label updated to
  `scratch_global_ten_c_yure_detection_permission_cache_from_gif_history_v2`.

Validation passed:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\kotoho7_scratch_reference_tables.dart test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\fukushima_offshore_reference_replay_test.dart test\iwate_east_offshore_reference_replay_test.dart test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
```

Effective-id replay metrics:

| Case | best | median / p90 | final |
|---|---:|---:|---:|
| `20260621_fukushima_offshore_m32_eq6` | `82 km` | `85 / 232.2 km` | `82 km` |
| `20260622_iwate_east_offshore_m30_hinet` | `3 km` | `14 / 14.5 km` | `14 km` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `85 km` | `88 / 107 km` | `85 km` |

This is more faithful but not yet better. Tomakomai still ends with
`assigned=17` but only `+7/+8=11` and `+6 true=0`; the missing PS-cache rows
are consistent with assignment-only `推定用tenPS時間計算` when stations join while
the source cache is invalid/too high-score. Next work should continue exact
`ten:+1/+2/+5` and state `5/6` rerise/re-registration timing rather than adding
a non-Scratch member-wide PS refresh.

### kotoho7 all-point `検出id2` `+5` pending cloud time

Continued the `ten:+1/+2/+5` lifecycle reproduction.

Scratch updates `ten:推定用 +5` during the all-point `検出id2` scan, before
`検出id3` assignment:

- positive current shindo and positive change speed: set `+5` to latest cloud
  time only if empty;
- positive current shindo and no positive change: clear `+5` if present.

Implemented:

- `_kotoho7Id2GatedAssignmentCandidates` now performs this all-point `+5`
  set/clear while scanning the candidate pool;
- `+5` uses `observedAt` / latest cloud time instead of first trigger/rise;
- station lifecycle initialization now uses existing `+5` for `+1/+2` before
  falling back to first trigger/rise.

Validation passed:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\kotoho7_scratch_reference_tables.dart test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\fukushima_offshore_reference_replay_test.dart test\iwate_east_offshore_reference_replay_test.dart test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
```

Metrics were unchanged, but final `+5` counts now show the all-point pending
cache is active:

| Case | best | median / p90 | final | final `+5` count |
|---|---:|---:|---:|---:|
| `20260621_fukushima_offshore_m32_eq6` | `82 km` | `85 / 232.2 km` | `82 km` | `35` |
| `20260622_iwate_east_offshore_m30_hinet` | `3 km` | `14 / 14.5 km` | `14 km` | `58` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `85 km` | `88 / 107 km` | `85 km` | `31` |

Tomakomai remains `assigned=17`, `+7/+8=11`, `+6 true=0`, so continue with
exact state `5/6` re-registration / `検出id3` call timing next.

### 2026-07-03 grid-scan search comparison audit

Status: diagnostic-only branch audited; do not promote to production yet.

Re-read the current replay outputs for
`scratch_error_level_components.grid_scan_search_comparison`.

| Case | Current final error | Grid-scan final error | Depth error | Notes |
| --- | ---: | ---: | ---: | --- |
| `20260702_fukushima_aizu_m46_jma_p2p` | `18 km` | `17.95 km` | `110 km` | Final score local-minimum at `37.07, 139.38, 40 km`; reference depth is `150 km`. |
| `20260622_tomakomai_south_offshore_m35_hinet` | `53 km` | `52.92 km` | `90 km` | Still stuck at `10 km` for a deep reference event. |
| `20260620_iwate_offshore_m34_ref` | `7 km` | `6.60 km` | `28 km` | Epicenter is good; depth remains shallow. |
| `20260622_iwate_offshore_m30_eq10` | `47 km` | `46.70 km` | `10.2 km` | Depth is acceptable; epicenter remains west-biased. |

Added per-stage candidate diagnostics:

- `evaluated_candidate_count`
- `finite_candidate_count`
- `rejected_candidate_count`
- `first_iteration_candidates[]`

Important finding:

- The capped grid-scan search is not failing because the iteration cap is too
  small. In Fukushima M4.6 final frame every stage stops after the first
  iteration because all neighboring candidates score worse than the current
  point.
- The deterministic grid-scan proxy currently keeps the detected timing set
  fixed to assigned `ten:推定用`-like stations. In late frames the Scratch
  unarrived gate is closed because the detected count is already high, so the
  large unarrived candidate set does not pull the solution.

Next step:

- Do not spend the next iteration on wider caps or random thinning.
- Continue reproducing the upstream Scratch station/source membership semantics:
  exact `ten:推定用 +3` lifecycle, `ten:+6/+7/+8` S-flag / PS cache transitions,
  and how `検出id` membership chooses the detected points passed into
  `HYP:誤差レベル計算`.

Validation:

```powershell
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/fukushima_aizu_m46_20260702_jma_p2p.json --concurrency=1
```

### 2026-07-03 `ten:+7/+8/+6` refresh boundary check

Checked whether the next step should be to stop recomputing station PS cache
after every HYP source update.

Finding:

- Scratch does not look like a pure full-refresh model: `検出id適用数カウント追加`
  invokes `推定用tenPS時間計算` from the `距離セット` branch, and reset clears
  the station's `ten:推定用` slots.
- But a naive event-driven-only Dart version is also wrong. On
  `20260702_fukushima_aizu_m46_jma_p2p`, final error worsened to about
  `172 km`; phase counts collapsed from `P/S/O=89/20/25` to `32/7/39`.
- That experiment was reverted; default behavior remains
  `scratch_suiteitenten_ps_time_recompute_stateful_v1`.

Next step:

- Decode and reproduce the `検出id2_各点の許可idと推定用をセット` slot writes for
  existing assigned points, especially state-5/state-6/rerise branches.
- Replace the coarse `assignedStationCodes + derived PS maps` abstraction with
  explicit `ten:推定用` slot state, then decide which slots drive HYP.

Validation after restore:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/fukushima_aizu_m46_20260702_jma_p2p.json --concurrency=1
```

### 2026-07-03 explicit `ten:推定用` slot diagnostics

Decoded the Scratch `ten:推定用` list writes into an explicit 10-slot station
layout.

Current mapping:

- `+1`: first/current use time
- `+2`: last update time
- `+3`: assigned detection id
- `+4`: first-station distance cache
- `+5`: pending/latest cloud time candidate
- `+6`: S flag
- `+7`: predicted P arrival
- `+8`: predicted S arrival

Implemented diagnostic-only `+5` support:

- new state map: `scratchStationPendingCloudAt`;
- clear/copy/update follows the same lifecycle as `+1/+2`;
- exposed in `stateful_source_cache.station_lifecycle` along with the decoded
  slot layout.

Fukushima M4.6 validation:

- final error unchanged at `17.95 km`;
- depth unchanged at `40 km`;
- phase counts unchanged at `P/S/O=89/20/25`;
- `+5` count is `134`, matching assigned stations.

Next step:

- Use the explicit slot model to reproduce the remaining `検出id2` slot writes
  for existing assigned points, instead of relying only on derived maps.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/fukushima_aizu_m46_20260702_jma_p2p.json --concurrency=1
```

### 2026-07-03 `検出id2` slot-write diagnostics

Added diagnostic-only tracking for the decoded `検出id2` `ten:推定用` writes.

Tracked branches:

- positive change sets `+5` if empty;
- non-positive change clears `+5` if present;
- state `5` positive change updates `+2`;
- state `6` positive rerise support refreshes `+1/+2`.

New diagnostics under `stateful_source_cache.station_lifecycle`:

- `estimated_slot_write_reason_counts`
- `estimated_slot_write_samples`

Fukushima M4.6 check:

- final estimate unchanged: `17.95 km`, depth `40 km`, `P/S/O=89/20/25`;
- final `+5` pending count: `2`;
- aggregate over replay:
  - `+5 set`: `197`
  - `+5 clear`: `195`
  - state-5 `+2 update`: `177`

Next step:

- Use these slot-write events as the candidate trigger for refreshing
  `+7/+8/+6`, rather than full-HYP refresh or naive event-driven-only refresh.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\source_estimation_replay_case_runner_test.dart --dart-define=SOURCE_ESTIMATION_CASE=test/fixtures/source_estimation/fukushima_aizu_m46_20260702_jma_p2p.json --concurrency=1
```

### kotoho7 `d #震度換算30段階[ten:震度 + 60]` grid/status range

Rechecked the local sb3 Stage hidden list `d #震度換算30段階`
(`a2{*m(q6TnFclX9Ot^rW`). It has 90 serialized entries:

- `1..30`: converted/display shindo values;
- `31..60`: color hex values;
- `61..90`: grid/status values used by `検出許可震度算出` through
  `d #震度換算30段階[ten:震度 + 60]`.

Correction made:

- `_kotoho7GridDetectionMaxProxy` now uses the third 30-entry range for the
  high-shindo branch instead of falling back to converted shindo.
- This keeps the Scratch semantics that high current `ten:震度` writes a
  grid/status value in `[-1..9]`, while low shindo still follows the
  `keep == -3 / keep == -2 / age < 15` branch.

Next replication target remains upstream carrier/assignment fidelity:

- continue mapping `grid存在id` / `grid:検出id` and
  `検出id4_点に適用するべきIDを検索` from sb3 before tuning HYP scoring.

### kotoho7 per-frame `grid存在id` / `grid:検出id` rebuild

Expanded `tools/extract_scratch_hyp_algorithm.py` so the generated reference
includes the upstream detection-id procedures, not just HYP/4-2:

- `検出id1_全点へ適用`
- `検出id2_各点の許可idと推定用をセット`
- `検出id3_点にIDを登録`
- `検出id4_点に適用するべきIDを検索`
- `検出id_グリッド別idと存在idをセット`
- `検出id_周囲gridの最新ID検索`
- `検出id_消えたidに対応する検出無効化`

Generated files:

- `docs/reference/scratch_hyp_algorithm_extracted.md`
- `docs/reference/scratch_hyp_algorithm_blocks.json`

Implementation update:

- added `_rebuildKotoho7GridCarrierFromAssignedStates`;
- `_scratchGridByNumber` is now rebuilt from active states'
  `assignedStationCodes`, approximating Scratch's per-frame
  `grid:検出id` / `@1 grid存在id` rebuild from `ten:+3`;
- stale grid carriers are removed when no assigned station still occupies that
  grid;
- carrier timestamps are preserved for the same source id, or fall back to the
  station's first-registration time, so the 2-second current-grid shortcut is
  not refreshed on every replay frame;
- diagnostics include `grid_presence_active_id_count`.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
flutter test test\fukushima_aizu_reference_replay_test.dart --concurrency=1
```

Next replication target:

- continue from the generated extraction into `検出id2` and
  `検出id3` details that decide whether a point reaches `ten:+3`, especially
  the re-rise branch and `検出id適用数カウント追加` distance/PS side effects.

### kotoho7 assigned-station `再上昇` refresh side effects

Continued from the extracted `検出id2_各点の許可idと推定用をセット` /
`検出id3_点にIDを登録` flow.

Scratch behavior:

- an already registered point with `ten:+1` does not simply remain unchanged;
- when current state is `6`, current shindo is rising, and nearest/support
  conditions are satisfied, Scratch updates it back to state `5`, refreshes
  `ten:+1/+2`, and calls `検出id3_点にIDを登録(point, 再上昇=true)`;
- state `5` with rising shindo refreshes `ten:+2` only.

Implementation update:

- `_kotoho7AssignedStationResetReason` now requires nearest-7 permission
  support before state `6 -> 5` assigned-station re-rise promotion;
- `_updateAssignedStationCodes` now applies the observable re-rise `ID3`
  side effects for already assigned stations:
  - refresh PS cache (`ten:+6/+7/+8`);
  - refresh first-station distance cache (`ten:+4`);
  - update the grid carrier with
    `scratch_id2_existing_rerise_refresh`;
- diagnostics expose `last_assignment_rerise_refresh_count` and
  `last_assignment_rerise_refresh_station_codes`.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
flutter test test\fukushima_aizu_reference_replay_test.dart --concurrency=1
```

Next replication target:

- continue into `検出id3`'s latest-id shortcut / new-id branch and
  `検出id適用数カウント追加` count metadata, because those decide whether the
  state machine creates a fresh detection id or reuses an existing one.

### kotoho7 `検出id3` latest-id shortcut and immediate `+1` count side effect

Continued from the extracted `検出id3_点にIDを登録` /
`検出id4_点に適用するべきIDを検索` ordering.

Scratch behavior:

- `検出id3` first removes any old `ten:+3` count with
  `検出id適用数カウント追加(..., -1)`;
- if the latest detection id is young enough, it can assign the point directly
  to that latest id before entering `検出id4`;
- after assigning `ten:+3`, it writes `grid:検出id` / `grid:検出id時間` and
  applies `検出id適用数カウント追加(..., distanceSet=true, +1)`.

Implementation update:

- added `_selectKotoho7LatestIdShortcutState` before the current-grid / 4-2 /
  around-grid selection branches;
- the shortcut is intentionally conservative:
  - latest active source must be younger than `10s`;
  - station distance from that source's initial first-station position must be
    `< 400 km`;
- added source labels:
  - `scratch_id3_latest_id_shortcut`;
  - `scratch_id3_latest_id_shortcut_other_state`;
- added reason counters:
  - `accept_latest_id_shortcut_young_distance_lt_400km`;
  - `latest_id_shortcut_no_young_active_id`;
  - `latest_id_shortcut_first_station_distance_gte_400km`;
- added immediate `scratch43AssignedCount += 1` on station assignment. The later
  metadata refresh still recomputes the exact count from `assignedStationCodes`.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
flutter test test\fukushima_aizu_reference_replay_test.dart --concurrency=1
```

Next replication target:

- implement or at least diagnostic-gate the mid-frame `検出id_新規id追加`
  branch for stations that reach `検出id3` but return `count2 == 0`.

### kotoho7 `検出id_新規id追加` and cross-state registration

Continued the `検出id3_点にIDを登録` reproduction.

Scratch behavior:

- if `count2 > 0`, the point is assigned to that id;
- if `count2 == 0`, `検出id_新規id追加` creates a new detection id and the point
  is assigned to that latest id;
- if `count2 < 0`, the point is reset and the script stops;
- after assigning `ten:+3`, Scratch writes `grid:検出id` /
  `grid:検出id時間` and applies
  `検出id適用数カウント追加(..., distanceSet=true, +1)`.

Implementation update:

- added `_assignKotoho7StationToState` for the common ID3 registration side
  effects:
  - add station to target `assignedStationCodes`;
  - immediate `scratch43AssignedCount += 1`;
  - initialize lifecycle;
  - refresh PS cache (`ten:+6/+7/+8`);
  - refresh first-station distance cache (`ten:+4`);
  - write grid carrier;
- when selection returns another active state, the station is now actually
  registered into that selected state. The current state's diagnostics still
  keep the rejected/would-switch trace;
- added `_createKotoho7MidFrameNewIdState` for `count2 == 0`:
  - seed source from the single station's rounded coordinate;
  - create a one-station detection id in `_states`;
  - allow later frames to grow it or active-id cleanup to expire it;
- diagnostics expose:
  - `last_assignment_mid_frame_new_id_count`;
  - `last_assignment_mid_frame_new_id_station_codes`;
  - candidate reason `created_mid_frame_new_id_for_count2_zero`.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
flutter test test\fukushima_aizu_reference_replay_test.dart --concurrency=1
```

Next replication target:

- continue into `検出id_新規id追加` metadata initialization in `4-3` /
  `4-4`, especially how one-station new ids avoid immediate invalidation and
  how latest-id ordering is represented.

### kotoho7 new-id metadata, latest ordering, and one-station grace

Expanded the generated `検出id_新規id追加` extraction.

Scratch behavior:

- new ids append a block of `4-3 検出id別情報` metadata:
  - first point / id source;
  - active flag;
  - first/latest detection time;
  - assigned count initialized to `1`;
  - initial distance/score placeholders;
  - source-key-ish string and expiry/lifetime fields;
  - additional metadata placeholders;
- new ids append ten blank `4-4 検出id震源要素` entries;
- non-rerise new ids immediately write `grid:検出id` /
  `grid:検出id時間` for the point's grid membership.

Implementation update:

- added `_Kotoho7HypState.scratch43Serial` and `_nextScratch43Serial` to model
  Scratch append-order latest-id semantics;
- latest-id shortcut now chooses the active state with the highest serial inside
  its young-id window, using `initializedAt` only as a tie-breaker;
- mid-frame new ids now set:
  - `scratch43CreatedByMidFrameNewId = true`;
  - `scratch43SingleStationGraceUntil = observedAt + 2s`;
- `_updateScratch43ActiveState` allows a one-station mid-frame new id to remain
  active during that grace window before applying the normal `<2 station`
  inactive gate;
- diagnostics expose:
  - `scratch_4_3_proxy.serial`;
  - `scratch_4_3_proxy.created_by_mid_frame_new_id`;
  - `scratch_4_3_proxy.single_station_grace_until`.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
flutter test test\fukushima_aizu_reference_replay_test.dart --concurrency=1
```

Next replication target:

- continue through `検出id_消えたidに対応する検出無効化` using
  `@1 grid存在id`, because active-id clearing is now the main remaining owner of
  late over-retention / stale id behavior.

### kotoho7 `検出id_消えたidに対応する検出無効化` grid-presence gate

Continued from the extracted `検出id_グリッド別idと存在idをセット` and
`検出id_消えたidに対応する検出無効化` procedures.

Scratch behavior:

- `検出id_グリッド別idと存在idをセット("", "", "")` clears
  `@1 grid存在id`, rebuilds `grid:検出id` from each point's `ten:+3`, and adds
  each present id to `@1 grid存在id`;
- `検出id_消えたidに対応する検出無効化` then uses that `grid存在id` list to decide
  whether a `4-3` detection id has disappeared from the grid carrier and should
  be marked inactive after its stale/disappearance window.

Implementation update:

- `_kotoho7ScratchGridPresenceProxy` now derives presence from
  `_scratchGridByNumber`, the Dart proxy for `grid:検出id` / `@1 grid存在id`;
- the old proxy checked assigned stations' current shindo directly, which could
  keep an id alive even when it no longer existed in the rebuilt grid carrier;
- the existing current-frame evidence gate remains before the disappearance
  check so missing replay frames do not immediately clear ids;
- diagnostics now expose `grid_presence_count_for_state` in addition to
  `grid_presence_active_id_count`.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
flutter test test\fukushima_aizu_reference_replay_test.dart --concurrency=1
```

Next replication target:

- continue inside `検出id_消えたidに対応する検出無効化` to map its exact stale
  windows and metadata updates, especially the branches that update `4-3 +2`,
  `+9`, and source-cache/best-score fields.

### kotoho7 nearest-7 and highest-shindo state pass

Continued the Scratch replication for the remaining non-equivalent fields.

Findings:

- Local `リアルタイム地震ビューアー v1.6.3.sb3` has `d ten:x/y/name/しきい`
  serialized with length `1748`.
- Local `dc ten:最短7点` starts as a one-item empty list; it is generated at
  runtime by `最短7点決定`, not stored as a full static table.
- `dtc:Xpix/Ypix` are also runtime lists; the Dart implementation continues to
  use NIED scan pixel tags as their carrier.

Implemented:

- a generated Scratch nearest-7 table from the full 1748 station order using
  the Scratch distance formula;
- nearest-7 lookup now uses station index first and only falls back to runtime
  pool sorting when the generated table cannot be used;
- third-nearest distance for the time-area gate now comes from the generated
  table;
- `scratchDetectionPermittedShindo` for `ten c:検出許可済み震度`;
- `scratchStationMaxShindoValue` + `scratchStationMaxShindoUpdatedAt` for
  `@1 ten:最高震度更新時刻`;
- `許可震度+` now reads the permitted max shindo cache;
- `震度高+ / 震度中+` now use the max-shindo update timestamp freshness window.

Correction after expanding `検出許可震度算出`:

- `ten c:検出許可済み震度` is a current permitted/capped shindo value, not a max
  value.
- Scratch writes current `ten:震度` when `ten:震度 > 0` and
  `ten c:揺れ検出許可 >= 4`.
- Otherwise, Scratch writes current `ten:震度` below `7`, or caps it to `6` for
  unpermitted high values.
- Dart now follows this current/capped value behavior; `許可震度+` reads
  `scratchDetectionPermittedShindo > 7`.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\services\sources\nied_source_estimation_driver.dart lib\core\source_estimation\station_event_tracker.dart
flutter test test\source_estimator_test.dart --concurrency=1
```

### kotoho7 `検出id4-2` age gate uses `4-3 +3`

Rechecked `検出id_新規id追加` and
`検出id4-2_適用id震源から候補選択` against the local sb3 and the extracted
Scratch blocks.

Finding:

```text
検出id_新規id追加:
  4-3 +3 = #r:最新クラウド変数[1]

検出id4-2 source-cache branch:
  age = #r:最新クラウド変数[1] - 4-3 +3
  if age > 5
     and 4-3 +11 < 500
     and 4-4 source cache exists:
       test the station against 4-4 +2/+3/+4/+5

検出id4-2 wide-distance rejection:
  reject if distance > 900 and:
    age > 100 and 1.5 * 4-3 +10 < distance
    or
    age > 15 and 1.4 * 4-3 +5 < distance
```

So this age is the detection-id creation/base time, not the earliest member
station time.

Implemented:

- new kotoho7 states now set `scratch43FirstDetectionAt = observedAt`, matching
  `4-3 +3 = now` when the id is created;
- `検出id4-2` source-cache and wide-distance age gates now use
  `observedAt - scratch43FirstDetectionAt`;
- diagnostics expose `detection_id_age_s` and `scratch43_first_detection_at`
  so future replay traces can confirm the gate source.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\kotoho7_scratch_reference_tables.dart test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
```

### kotoho7 `4-3 +20/+21` full SB3 audit

Continued the faithful SB3 reproduction by auditing the full web
`project.json` for `4-3 検出id別情報` slot `+20`, not just the extracted HYP
procedure set.

Confirmed:

- `+20` is written by `検出idに対応するEEW %s`, where a detection id is linked
  to an EEW offset when the estimated source is close to the EEW epicenter,
  the EEW timing relation is valid, and the current HYP error/timing
  difference gate passes.
- `+20` is read by `検出エフェクトなど %b` to suppress standalone estimated-source
  effects once the detection id is associated with EEW, unless the display
  override is enabled.
- In the HYP/source-estimation path, `+20` is only copied by
  `検出id_同一震源統合`; it is not a depth, magnitude, source score, P/S cache,
  or station-selection parameter.
- `検出id_新規id追加` appends a blank `+21` slot after `+20`; no HYP producer or
  consumer has been found for `+21`.

Decision:

- Do not add a fake Dart HYP field for `+20` or `+21` in the current GIF-only
  estimator.
- Keep the source-estimation reproduction focused on the slots that feed
  station assignment, source-cache update, travel-time error, P/S lifecycle,
  and display diagnostics.
- If an EEW replay package is added later, map `+20` as an EEW-association
  offset/display-suppression field, not as a hypocenter-estimation input.

Next:

- Continue static SB3 comparison before tuning: the remaining high-value area
  is exact `4-4` source-cache lifecycle and `推定用tenPS時間計算`/S-flag timing,
  because those directly decide which stations enter HYP as P or S and are the
  most likely cause of the remaining depth drift.

### kotoho7 default PS-cache refresh corrected to assignment-only

Continued the Scratch/SB3 alignment for `推定用tenPS時間計算`.

Correction:

- The previous Dart default used `member_wide_bridge`, refreshing `ten:+6/+7/+8`
  for every assigned station after accepted HYP source-cache updates.
- That bridge is useful diagnostically, but it is not the proven SB3 default
  call order.
- The source project shows the normal update path through station assignment /
  re-registration:

```text
検出id適用数カウント追加(point, 距離セット=true, +1)
  -> 推定用tenPS時間計算(point, id)
```

Implemented:

- default `kotoho7_ps_cache_refresh_mode` is now `assignment_only`;
- `member_wide_bridge` remains opt-in through request metadata;
- `stateful_source_cache.station_ps_cache.production_refresh_semantics` now
  reports whether the run is the Scratch-default assignment-only path or the
  explicit diagnostic bridge.

Full-project call audit:

- `推定用tenPS時間計算(...)` is called from:
  - `検出id適用数カウント追加(point, 距離セット, 変更数)`;
  - `検出id_推定PS時間id別再計算(id)`.
- No external call to `検出id_推定PS時間id別再計算(id)` was found in the current
  web `project.json`.
- Therefore `member_wide_bridge` is not the faithful default even if it improves
  some metrics.

Next:

- Re-run the narrow source-estimator validation after formatting.
- Then inspect the exact source-cache write order (`4-4 +2/+3/+4/+5`) relative
  to station assignment, because assignment-only PS cache means newly assigned
  stations may carry P/S flags computed from the previous source cache until
  Scratch explicitly re-registers or recalculates them.

### kotoho7 `4-4` source-cache quantization

Continued the source-cache audit and decoded all full-project writes to
`4-4 検出id震源要素`.

Normal `HYP:震源検出` completion writes:

```text
4-4 +2 = round(longitude * 60) / 60
4-4 +3 = round(latitude * 60) / 60
4-4 +4 = round(depth)
4-4 +5 = round(origin time)
```

Implemented:

- accepted source-cache writes now store a quantized `_HypCandidate` with the
  same `4-4` precision;
- returned `SourceEstimate` values for the kotoho7 path now use the quantized
  cache rather than raw candidate coordinates;
- the raw HYP score remains unchanged for `+19` acceptance gating.

Boundary confirmed:

- `HYP:誤差レベル計算` also contains keypress/debug-only `4-4 +2/+3/+4/+5`
  writes; not mapped as production behavior.
- `円検出の毎処理` writes `4-4 +6/+7`; these are display/EEW-circle radii, not
  hypocenter search parameters.

Next:

- After validation, compare assignment-only P/S cache traces on the narrow
  benchmark cases. If depth drift changes sharply, inspect whether Scratch's
  `検出id_推定PS時間id別再計算(id)` is actually called by a broadcast path not
  present in the extracted HYP procedure map.

### kotoho7 narrow replay check after assignment-only + `4-4` quantization

Ran the narrow local replay set:

```powershell
flutter test test\fukushima_offshore_reference_replay_test.dart `
  test\iwate_east_offshore_reference_replay_test.dart `
  test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
flutter test test\current_capture_replay_analysis_test.dart --concurrency=1
```

All tests passed.

Effective-id kotoho7 metrics after the faithful default switch:

| Case | estimates | best | median / p90 | final | final source | final PS cache |
|---|---:|---:|---:|---:|---|---|
| `20260621_fukushima_offshore_m32_eq6` | `44` | `57 km` | `72 / 151 km` | `57 km` | `37.9167, 141.7500, 80 km` | `+7/+8=62`, `+6 true=36` |
| `20260622_iwate_east_offshore_m30_hinet` | `36` | `13 km` | `19 / 36.5 km` | `19 km` | `39.9667, 142.1333, 70 km` | `+7/+8=43`, `+6 true=27` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `36` | `49 km` | `54 / 65 km` | `54 km` | `42.5333, 141.1833, 70 km` | `+7/+8=15`, `+6 true=2` |

Current 2026-06-30 capture analysis still uses the production
`nied_gif_hybrid_v1` driver, not kotoho7:

- Fukushima Hamadori M3.4: `16` processed frames, `50` missing frames,
  `7` estimates, final error `56.8 km`, final source
  `36.9314, 140.5558`, no depth.
- Iwate offshore M3.6: `38` processed frames, `58` missing frames,
  `26` estimates, final error `9.5 km`, final source
  `40.4106, 142.3119`, no depth, `2.8 km` from the EQuake reference point.
- 12:15 noise window: `18` processed frames, `28` missing frames, `0`
  estimates.

Conclusion:

- The current kotoho7 path is now closer to the audited SB3 call graph.
- Metric quality regressed relative to old bridge-assisted notes on
  Tomakomai/Iwate, but restoring all-member PS refresh would be knowingly less
  faithful.
- Next target should be exact `検出id2/3/4` station lifecycle:
  re-registration, `ten:+3` reset, and `検出id適用数カウント追加(...,
  距離セット=true, ...)`, because that is the only proven production path that
  recomputes `ten:+6/+7/+8`.

### kotoho7 `ten:+5` reset/assignment correction

Continued the exact station lifecycle audit by re-expanding
`検出id_点の推定用をリセット(point)`.

Confirmed reset order:

```text
clear ten:+1
clear ten:+2
検出id適用数カウント追加(point, -1)  # while +3 still contains the id
clear ten:+3
clear ten:+4
clear ten:+6
clear ten:+7
clear ten:+8
```

Important correction:

- reset does not clear `ten:+5`;
- assignment/registration does not blindly write `ten:+5`;
- `ten:+5` remains controlled by `検出id2`:
  - positive change speed: set `+5` only if empty;
  - no positive change speed: clear `+5` if present.

Implemented:

- `_initializeKotoho7StationLifecycle` no longer writes
  `scratchStationPendingCloudAt`;
- station reset no longer removes `scratchStationPendingCloudAt`;
- full detection-id invalidation still clears all station slot maps.

Next:

- Re-run the narrow validation and then re-check the three replay metrics to see
  whether the corrected `+5` lifecycle changes P/S timing or only diagnostics.

### kotoho7 state5 rerise gate correction

Expanded the decoded `検出id2` rerise branch:

```text
if 現在状態 > 3.5 and 変化速度 > 0:
  scan nearest 7
  if neighbor has positive change and permission > 4:
    多目的0 += 10000 + neighbor change speed
    if own ten:+3 < neighbor ten:+3:
      多目的0 = Infinity

  if 多目的0 == Infinity
     or (現在状態 == 6 and mod/bucket rerise condition):
    if 多目的0 > 10000000:
      点許可状態更新(5, "再び震度加速")
      set +1/+2 from +5 if present, otherwise current cloud time
      検出id3_点にIDを登録(point, 再上昇=false)
    else:
      点許可状態更新(6, "再び震度加速用待機")
  else if 現在状態 == 5:
    update +2 only
```

Dart correction:

- `_kotoho7Id2ReriseScore` now treats a newer neighbor `ten:+3` as
  `double.infinity`, matching Scratch instead of reducing the score.
- state `5` now evaluates the same rerise gate instead of always falling
  through to `+2` update.
- the rerise `+1/+2` refresh now uses `ten:+5` when present, otherwise the
  current frame time, matching the decoded branch.

Remaining gap:

- The current Dart path refreshes the existing state's PS/distance cache for
  this rerise. Full Scratch `検出id3` can also re-select another id or create a
  new id. That cross-id rerise re-registration is the next exact reproduction
  target if metrics still show late drift.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart `
  lib\core\source_estimation\kotoho7_scratch_reference_tables.dart `
  test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\fukushima_offshore_reference_replay_test.dart `
  test\iwate_east_offshore_reference_replay_test.dart `
  test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
```

All passed.

Replay metrics after this pass:

| Case | best | median / p90 | final | Note |
|---|---:|---:|---:|---|
| `20260621_fukushima_offshore_m32_eq6` | `57 km` | `72 / 151 km` | `57 km` | no material metric change |
| `20260622_iwate_east_offshore_m30_hinet` | `13 km` | `19 / 36.5 km` | `19 km` | final `+6 true` `26`; raw-id diagnostic worsened slightly |
| `20260622_tomakomai_south_offshore_m35_hinet` | `49 km` | `54 / 65 km` | `54 km` | no material metric change |

Conclusion:

- The corrections are still worth keeping because they follow the decoded SB3
  slot semantics.
- They do not solve the remaining drift. Continue with full cross-id
  `検出id3` re-registration instead of more HYP score tuning.

### kotoho7 cross-id rerise re-registration

Implemented the next `検出id3` reproduction step for rerise points.

Behavior now:

- rerise preserves the refreshed `ten:+1/+2/+5`;
- removes only the current detection-id membership (`検出id適用数カウント追加 -1`
  equivalent), not a full reset;
- re-enters the existing `検出id4` source selection;
- assigns the point to the same id, another active id, or a new mid-frame id.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart `
  lib\core\source_estimation\kotoho7_scratch_reference_tables.dart `
  test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\fukushima_offshore_reference_replay_test.dart `
  test\iwate_east_offshore_reference_replay_test.dart `
  test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
```

All passed.

Observed max per-frame rerise activity:

| Case | method | rerise | switch other id | new mid-frame id |
|---|---|---:|---:|---:|
| `20260621_fukushima_offshore_m32_eq6` | effective | `1` | `0` | `0` |
| `20260621_fukushima_offshore_m32_eq6` | raw | `1` | `0` | `0` |
| `20260622_iwate_east_offshore_m30_hinet` | effective | `1` | `14` | `2` |
| `20260622_iwate_east_offshore_m30_hinet` | raw | `3` | `12` | `3` |
| `20260622_tomakomai_south_offshore_m35_hinet` | effective | `2` | `1` | `1` |
| `20260622_tomakomai_south_offshore_m35_hinet` | raw | `4` | `2` | `1` |

Headline effective-id metrics remain:

| Case | best | median / p90 | final |
|---|---:|---:|---:|
| `20260621_fukushima_offshore_m32_eq6` | `57 km` | `72 / 151 km` | `57 km` |
| `20260622_iwate_east_offshore_m30_hinet` | `13 km` | `19 / 36.5 km` | `19 km` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `49 km` | `54 / 65 km` | `54 km` |

Next:

- Continue static SB3 comparison inside `検出id4_点に適用するべきIDを検索` and
  its three candidate sources:
  - latest-id shortcut;
  - nearest-7 existing-id selection;
  - source-cache candidate selection.
- Focus especially on inputs used by rerise frames, because cross-id rerise is
  now active but still not improving the problematic cases.

### kotoho7 `検出id4` latest-id distance guard

Rechecked the `検出id4_点に適用するべきIDを検索` branch that runs after
`検出id4-1` and before current-grid / source-cache / around-grid selection.

Scratch condition:

```text
if count2 == 0:
  if (
       LEN(4-3) < 40
       or (
         2 < 4-3[LEN(4-3) - 16]
         and (#r:最新クラウド変数[1] - 4-3[LEN(4-3) - 37]) > 40
       )
     )
     and (#r:最新クラウド変数[1] - 4-3[LEN(4-3) - 17]) < 10:
       if distance(current point, latest id first station) < 400:
         count2 = LEN(4-3) / 20
```

Decoded:

- `LEN(4-3) - 17` is latest row `+3`, so the `10 s` gate is latest-id
  creation age, not last update time;
- `LEN(4-3) - 16` is previous row `+4`, applied count;
- `LEN(4-3) - 37` is previous row `+3`, previous id creation/base time.

Implemented:

- `_selectKotoho7Id4LatestIdDistanceState` now follows Scratch append/serial
  order;
- latest row must be active and younger than `10 s` from
  `scratch43FirstDetectionAt`;
- if a previous row exists, it must have `scratch43AssignedCount > 2` and
  creation age `> 40 s`;
- the 400 km first-station distance check remains unchanged.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\kotoho7_scratch_reference_tables.dart test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
```

### kotoho7 `検出id距離計算` map-pixel distance

Rechecked `検出id距離計算 %s %s`, which updates station `ten:+4` and detection-id
`4-3 +5`.

Finding:

```text
dx = (dtc:Xpix[firstStation] - dtc:Xpix[station]) * 11
dy = (dtc:Ypix[firstStation] - dtc:Ypix[station]) * 11
ten:+4 = sqrt(dx^2 + dy^2)
4-3 +5 = max(4-3 +5, ten:+4)
```

`dtc:Xpix/Ypix` are generated from `d ten:x/y` during map initialization:

```text
xy3 = (((longitude + 44) mod 360) - 180) * 10
xy4 = ln(tan(45 + latitude / 2)) * 572.9577951308232
      - 374.04780730560344
screenX = 1.8 * (xy3 - 16)
screenY = 1.8 * (xy4 - 41)
dtc:Xpix/Ypix = round(screenX/Y * 100000) / 100000
```

Implemented:

- `4-3 +5` / `ten:+4` first-station distance now uses the Scratch map-pixel
  formula instead of the previous geographic haversine proxy;
- branches that explicitly call `緯度経度で距離km` remain geographic.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\kotoho7_scratch_reference_tables.dart test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
```

### kotoho7 `4-3 +10` empty/copy slot correction

Rechecked all reachable writes to `4-3 検出id別情報` around `+10`.

Finding:

- `検出id_新規id追加` initializes `4-3 +10` as empty;
- `検出id4-2_適用id震源から候補選択` only reads `+10` for the old-wide
  rejection:

```text
if sourceDistance > 900:
  if age > 100 and 1.5 * 4-3 +10 < sourceDistance:
    reject
```

- `検出id_同一震源統合` copies `+10` between `4-3` rows;
- no reachable HYP/source-cache update was found that refreshes `+10` as a
  maximum source-to-station distance.

Implemented:

- `scratch43MaxSourceDistanceKm` now defaults to `0.0`, matching Scratch's
  empty-value numeric comparison in this gate;
- state metadata refresh no longer writes source-to-station haversine max into
  `+10`;
- the `age > 100` wide-distance gate removed the Dart-only
  `sourceDistanceLimitKm > 0` guard;
- the same metadata refresh now preserves the Scratch map-pixel implementation
  of `4-3 +5`.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\kotoho7_scratch_reference_tables.dart test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
```

### kotoho7 `検出id_同一震源統合` mapped metadata copy

Expanded `検出id_同一震源統合 %s %s %b`.

Scratch merge behavior:

```text
rewrite member station ten:+3 from id1 to id2

if 4-3[id2 + 11] > 4-3[id1 + 11]:
  copy +4, +5, +8, +9, +10, +11, +18

if 4-3[id2 + 3] > 4-3[id1 + 3]:
  copy +1, +3, +12

if 4-3[id2 + 6] > 4-3[id1 + 6]:
  copy +6, +7

copy larger +19/+20
set id1 +2 inactive
```

Implemented for currently mapped Dart fields:

- merge metadata no longer uses generic `max` for mapped `+4/+5/+10/+11`;
- when the source row has lower `scratch43BestScore`, Dart copies:
  - `scratch43AssignedCount` (`+4`);
  - `scratch43MaxFirstStationDistanceKm` (`+5`);
  - `scratch43ExpireAt` (`+9`);
  - `scratch43MaxSourceDistanceKm` (`+10`);
  - `scratch43BestScore` / source cache (`+11` / `4-4`).

Completed after the first pass:

- `firstStationCode`, `initialLatitude`, and `initialLongitude` are now mutable
  state fields;
- when the source row has an earlier `scratch43FirstDetectionAt` (`4-3 +3`),
  Dart copies first-station identity and initial coordinates as the mapped
  `+1` equivalent.
- `scratch43LastSourceCacheUpdatedAt` now maps `+18`: it is written when the
  owned source cache is updated and copied together with the better `+11` row.
- `scratch43LastMaxCurrentShindoIndex` / `scratch43PreviousMaxCurrentShindoIndex`
  now map `+6/+7` more faithfully:
  - `+6` is computed from assigned stations'
    `scratchDetectionPermittedShindo` through the Scratch 30-step conversion
    table;
  - `+7 = +6` is still applied in the active-state not-expired branch;
  - merge copies `+6/+7` when the source row has a smaller `+6`, matching
    `if 4-3[id2 + 6] > 4-3[id1 + 6]`.
- `scratch43BestRawScore` now maps `+19`:
  - it initializes as infinity;
  - source-cache updates are accepted only when
    `bestError < 4-3 +19 * 1.7` or the id age is under `10 s`;
  - when accepted, `+19` is updated to the smaller raw best error;
  - `+11` remains separate and is written as the accepted display/selection
    score, including Scratch's early `<250` clamp to `250`;
  - merge copies the larger `+19`, matching the sb3 branch.

Still not mapped:

- `+20` does not yet have an explicit Dart field. In the extracted reachable
  blocks it initializes as empty and is only copied during same-source merge;
  no independent producer/consumer has been found yet.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\kotoho7_scratch_reference_tables.dart test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
```

### kotoho7 `検出id4-2` fallback and `4-4` slot confirmation

The next sb3 pass decoded the remaining `検出id4-2` fallback guard and
reconfirmed the source-cache slot order.

Finding:

```text
first-point fallback:
  if 4 < 4-3[offset + 4]:
    x/y = first station coordinates
    depth = 10
    origin = ten:+1(first station) - 3

4-4 source-cache slots:
  +2 = x / longitude
  +3 = y / latitude
  +4 = depth
  +5 = origin time

4-3 +11:
  @hyp:最小誤差レベル
```

Implemented:

- `検出id4-2` now gates the first-point fallback on
  `scratch43AssignedCount > 4`, matching `4-3 +4`, instead of using the Dart
  assigned set length directly;
- accepted-station diagnostics now include
  `scratch43_assigned_count_before_add`.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\kotoho7_scratch_reference_tables.dart test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
```

### kotoho7 `単独トリガ` fast-rise gate and threshold digit correction

Static SB3 check continued from the local v1.6.3 project.

Finding:

- `単独トリガ 状態` first computes `カウント2` from `上昇制限`:
  `75` when the digit is `0`, otherwise `上昇制限^2`.
- It then compares the squared converted-shindo energy between
  `ten:震度履歴[+1]` and `ten:震度履歴[+3]`.
- If the difference exceeds the limit, Scratch writes state `0` with
  `上昇速度早すぎおかしい` and stops before the rest of the single-trigger
  branches.
- The actual `点震度の処理` -> `単独トリガ 状態` call maps `d ten:しきい`
  as:
  digit 1 = `しきい値`, digit 2 = `点数`, digit 3 = `上昇制限`.
- This is caller-specific. The `揺れ検出許可` -> `複数トリガ 状態` path keeps
  the earlier mapping: digit 3 = `最低点数`, digit 2 = `しきい値`, digit 1 =
  `上昇制限`.

Implemented:

- added the slot-1/slot-3 fast-rise squared-energy gate to
  `_kotoho7NextDetectionPermissionState`;
- mapped replay `observationHistory` to recent Scratch `ten:震度履歴` slots for
  that gate;
- corrected `_kotoho7NextDetectionPermissionState` so single-trigger branches
  use the single-trigger mapping while multi-trigger / acceleration branches
  retain the multi-trigger mapping.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\kotoho7_scratch_reference_tables.dart test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
```

### kotoho7 `検出id2` current-state source correction

The Scratch extraction was rechecked before continuing depth/magnitude tuning.
`検出id1_全点へ適用` passes `ten c:揺れ検出許可[番号]` into
`検出id2_各点の許可idと推定用をセット` as `現在状態`.

Implemented correction:

- default `scratch_full_point_id2_gate` now reads
  `scratchDetectionPermissionState` as the `検出id2` current state;
- unknown stations enter the gate as state `0`, not as an active-like/state-`5`
  fallback;
- `検出id2` re-rise / no-rise wait transitions that call Scratch
  `点許可状態更新` now update `scratchDetectionPermissionState` to `5/6`;
- nearest-7 support for `検出id2` now counts only
  `scratchDetectionPermissionState >= 5`;
- the older `scratchStationPermissionState` cache remains only as a
  `ten:推定用` lifecycle/diagnostic cache and is no longer a substitute for
  `ten c:揺れ検出許可`.

Follow-up in the same block:

- The first-registration branch keeps the Scratch `多目的0 > 0` support test.
- The existing state-`6` re-rise branch now uses Scratch's `多目的0`
  accumulator instead of the earlier broad `nearest7Support > 0` shortcut:
  fresh neighbor permission `5/6` contributes `10000000`/`10020000`, rising
  permitted neighbors contribute `10000 + ten:震度変化速度`, and the current
  accumulator is divided by `10` when the current point's `ten:+3` id is lower
  than the neighbor's.
- Re-rise to state `5` + `検出id3` now requires the Scratch modulo/floor tests
  and `multi0 > 10000000`; otherwise the point stays in the state-`6`
  waiting branch.

This keeps the reproduction aligned with the article/SB3 path: station
membership and the later HYP/depth search must be driven by the same permission
state machine that Scratch runs before `検出id2`, rather than by a Dart proxy.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\kotoho7_scratch_reference_tables.dart test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
```

### kotoho7 `検出id4-1` nearest-7 existing-id inheritance

Continued from the extracted `検出id3 -> 検出id4` flow.

Important ordering:

- `検出id3` still has the outer latest-id shortcut
  (`timer < 10 && LEN(4-3 検出id別情報) > 0`), so the Dart latest-id shortcut
  remains first.
- When that shortcut does not decide `count2`, `検出id4` starts with
  `検出id4-1_適用id最短7から候補選択`.

Implemented:

- `_selectKotoho7Nearest7ExistingIdState`;
- inserted it after `_selectKotoho7LatestIdShortcutState` and before
  current-grid / source-cache / around-grid selection;
- uses the extracted nearest-7 table and stops at the Scratch `40 km` distance
  guard;
- only considers neighbors whose `ten c:揺れ検出許可` is `4` or `5`;
- requires an active `ten:+3` owner and chooses the owner with the smallest
  `abs(current.ten:+1 - neighbor.ten:+1)` under `10 s`.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\kotoho7_scratch_reference_tables.dart test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
```

### kotoho7 `検出id3` latest-id shortcut timer correction

Rechecked the outer `検出id3_点にIDを登録` latest-id shortcut:

```text
if timer < 10 and LEN(4-3 検出id別情報) > 0:
  count2 = LEN(4-3 検出id別情報) / 20
else:
  検出id4_点に適用するべきIDを検索(...)
```

The web project and local v1.6.3 sb3 contain no `control_resettimer`, so
`timer` is Scratch/TurboWarp runtime time, not earthquake/event age.

Implemented correction:

- the previous Dart "young active id" shortcut is superseded;
- `_selectKotoho7LatestIdShortcutState` now only fires when metadata explicitly
  supplies `kotoho7_scratch_runtime_timer_s < 10`;
- without that metadata, normal replay/production continues into `検出id4`;
- the `first-station distance < 400 km` rule is not applied here because it
  belongs to a later `検出id4` branch.

Follow-up:

- restored the later `検出id4` latest-id distance branch in the correct
  position: after `検出id4-1` nearest-7 inheritance and before current-grid /
  source-cache / around-grid selection;
- `_selectKotoho7Id4LatestIdDistanceState` selects the latest active id when it
  was updated within `10 s` and the current point is within `400 km` of that
  id's first station;
- selection sources:
  - `scratch_id4_latest_id_distance`;
  - `scratch_id4_latest_id_distance_other_state`;
- remaining gap: the Scratch condition also reads exact
  `4-3 検出id別情報` offsets around the latest id. Dart currently maps that
  branch through the `scratch43*` metadata proxy.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\kotoho7_scratch_reference_tables.dart test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
```

Follow-up implemented:

- `最大震度と時間経過` is now wired from the reproduced
  `検出許可震度算出` max source: max current `ten:震度100`-equivalent value among
  points with `ten c:揺れ検出許可 >= 4`.
- The state demotion uses the Scratch timeout expression
  `120 + 10^(1 + maxShindo / 1.2)` and writes state `1`.

Next reproduction target:

- revisit `通常トリガ更新` / `円の中トリガ` with exact inputs instead of
  replay-side guesses; `円の中トリガ` remains EEW-circle dependent.

Follow-up implemented:

- Decoded `震度履歴時間管理` slots from local v1.6.3 SB3:
  slot 11 = about 4 s, slot 12 = about 9 s, slot 13 = about 1 s, slot 14 =
  about 7 s.
- `通常トリガ更新` now uses the Scratch gate:
  `しきい値 < 4`, `dc ten:最短7点[+5] < 40` or elapsed `> 10 s`, and
  1-second `ten:震度履歴` rise `> 0.3`.
- The older proxy based on any nearest-7 support plus generic positive rise is
  removed from this branch.

Next reproduction target:

- `円の中トリガ`, which should stay disabled/explicit until the EEW circle
  inputs have a replay-equivalent source.

Follow-up audit:

- Decoded `円の中か判定(多目的0)` and the inline `円の中トリガ` branch from
  local v1.6.3 SB3.
- The branch requires Scratch live EEW state: `EEW全体で発表中？`,
  10-slot `0EEW`, `0-1EEW発表中`, `0-2EEW追加情報`, and per-station
  `ten c:震源距離` to each EEW slot.
- Current NIED GIF source-estimation requests do not carry those equivalents.
  Therefore this branch remains intentionally unimplemented rather than
  approximated from HYP/JMA/P2P truth.
- Added `single_trigger_circle_eew_gate` diagnostics to the kotoho7 reference
  report so replay output explicitly says `missing_scratch_eew_circle_inputs`
  instead of silently omitting the branch.

Next reproduction target:

- if we want `円の中トリガ`, first add a real EEW-state capture/replay channel
  that preserves the Scratch fields above; otherwise continue with non-EEW
  `検出id` / source-cache parity.

### kotoho7 static SB3 correction: nearest-7 table and grid-number formula

Status correction for the faithful Scratch/JQ reproduction path:

- `dc ten:最短7点` is no longer treated as a generated/proxy table in the Dart
  reference estimator.
- The official Scratch project serializes the full `dc ten:最短7点` list with
  `24472` items (`1748 * 7 * 2`), so the table is now embedded as
  `lib/core/source_estimation/kotoho7_scratch_reference_tables.dart`.
- `_kotoho7Nearest7Records` and `_kotoho7ThirdNearestDistanceKm` now read that
  Scratch table by station index; generated geographic nearest-7 remains only
  as a defensive fallback if the embedded table length is invalid.
- `dc ten:点からグリッド番号` is generated by Scratch during `リセット %b`, not
  serialized as a full list. The decoded expression is:

```text
((floor(d ten:y[point]) - 23) * 23) + (floor(d ten:x[point]) - 122)
```

- `_kotoho7GridNumber` now uses that exact formula from station
  latitude/longitude. The old 0.25-degree geographic grid proxy is superseded
  and should not be cited as current behavior.
- The reset-built grid carrier is now reproduced more closely:
  `dc grid連番:点がある番号` has `92` populated grids, and
  `dc grid:グリッドに含まれる点番号` is simulated as one flat list with nominal
  70-slot grid segments. This matters because official grid `293` contains
  `79` stations, so `9` stations spill past the nominal segment exactly as
  Scratch's `repeat until first empty slot` insertion would do.
- `gridトリガ` now reads stations through that serial grid carrier instead of
  grouping only the current request records by grid number.
- `grid:検出グリッド最大震度` reset/keep now covers all Scratch populated grids,
  not only grids currently present in the request.

Verified:

```powershell
dart format lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\kotoho7_scratch_reference_tables.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\kotoho7_scratch_reference_tables.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter analyze lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\kotoho7_scratch_reference_tables.dart test\source_estimator_test.dart
```

Unit-test correction:

- The kotoho7 source-cache reuse test now uses real NIED Iwate station codes
  instead of synthetic `A..F` station codes, because the reproduced nearest-7
  and grid tables are station-index based.
- That test explicitly sets `kotoho7_assignment_candidate_mode = uncapped`.
  It is a cache-reuse diagnostic test, not proof that a one-frame synthetic
  fixture has passed the default Scratch `検出id2` permission pipeline.

Remaining work stays the same: continue replacing the permission/grid-trigger
proxy names and approximations by the decoded SB3 pipeline
`揺れ検出許可 -> 検出許可震度算出 -> grid:上昇中割合計算&トリガ -> gridトリガ`,
then revisit HYP selection only after station permission state matches Scratch.

Additional static SB3 check:

- `点許可状態更新` was decoded and matches the Dart trigger-time refresh rule:
  forced update, or `state > 1 && state != 6`, or missing previous trigger
  time.
- `NG加速` was decoded and confirmed not to be inverted in Dart. Despite the
  name, the caller applies acceleration when `NG加速` leaves `多目的0 == 1`, so
  `_kotoho7ScratchNgAccelerationAccepted` intentionally returns the same
  side-of-line continue condition.
- `複数トリガ` branch `周りの多くが許可or揺れてるから` is now represented:
  Dart scans the first five Scratch nearest neighbors, counts
  `permission > 4`, counts `ten:震度 > 5`, compares the center shindo against
  first-five average + `1.6`, and promotes to state `5`.
  Both web and local SB3 have `7システム設定[51] == False`, so the default branch
  is state `5` rather than state `6`.
- State `3/4` now follows the SB3 cleanup behavior when the normal-permission
  accumulator fails: `時間エリア内に点なし` writes state `0`, and state `4`
  with `c[1] < 7` writes state `0` for `1点検知の時間切れ`.
- `単独トリガ` point-missing and long-time rising branches are now represented:
  no current shindo (`震度 == -9` equivalent) writes state `1`
  (`点なし解除`), and state `> 4` after 400 seconds with positive rise and
  `震度 > 0.45` writes state `5` with forced trigger-time refresh
  (`時間overから上昇`). `7システム設定[51]` is `False` in both checked SB3
  sources, so this branch is active by default.

Verified after this branch:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\core\source_estimation\kotoho7_scratch_reference_tables.dart test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --concurrency=1
```

### 2026-07-04 update: kotoho7 existing-member re-register offline report

Added and reran
`tools/build_kotoho7_existing_member_reregister_report.dart`.

Report:

```text
.dart_tool/kotoho7_existing_member_reregister_report/report.json
```

Purpose:

- read already-generated
  `.dart_tool/source_estimation_benchmark/*.reference.json`;
- inspect whether stations that are already in Scratch `ten:推定用 +3`
  overlap the current raw/effective source-trigger member sets;
- keep this analysis offline. It must not be moved back into replay/estimator
  hot-path metadata because the previous hot-path probe pushed the Fukushima
  replay close to the five-minute timeout.

New report fields:

- `interpretation`;
- `rawOverlapFrameRatio` / `effectiveOverlapFrameRatio`;
- `rawOverlapAssignedRatio` / `effectiveOverlapAssignedRatio`;
- `existingPlus3CurrentFrameSkipCandidateTotal`;
- `existingPlus3CurrentFrameSkipCandidateFrameCount`;
- `existingPlus3OfflineProbeRequired`;
- `existingPlus3GeometryProxy*`;
- `existingPlus3PhaseProxy*`;
- `finalEffectiveMinusRawOverlap`;
- `maxPositiveShadowScoreDelta` and its frame.

Current run summary:

| case | interpretation | raw frames | raw total | raw/assigned | final raw/effective |
| --- | --- | ---: | ---: | ---: | ---: |
| `20260702_shizuoka_west_m36_jma_p2p` | persistent raw + late effective retention dominance | `62/62` | `1333` | `0.434` | `2/95` |
| `20260702_fukushima_aizu_m46_jma_p2p` | persistent raw + late effective retention dominance | `68/68` | `1289` | `0.315` | `15/133` |
| `20260624_fukushima_aizu_m32_jma_eq5` | persistent raw current overlap | `61/62` | `838` | `0.488` | `0/0` |
| `20260620_iwate_offshore_m34_ref` | persistent raw + late effective retention dominance | `52/56` | `834` | `0.452` | `0/47` |
| `20260622_tomakomai_south_offshore_m35_hinet` | persistent raw + late effective retention dominance | `38/42` | `566` | `0.539` | `0/31` |
| `20260622_iwate_offshore_m30_eq10` | persistent raw current overlap | `47/47` | `549` | `0.545` | `1/24` |
| `20260622_iwate_east_offshore_m30_hinet` | effective retention only, no raw current overlap | `0/39` | `0` | `0.000` | `0/20` |

Current implementation action totals from the same report:

| case | added | rerise refresh | removed | would-switch-other-id |
| --- | ---: | ---: | ---: | ---: |
| `20260702_shizuoka_west_m36_jma_p2p` | `91` | `0` | `1` | `0` |
| `20260702_fukushima_aizu_m46_jma_p2p` | `105` | `0` | `2` | `473` |
| `20260624_fukushima_aizu_m32_jma_eq5` | `30` | `0` | `0` | `141` |
| `20260620_iwate_offshore_m34_ref` | `40` | `0` | `0` | `0` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `26` | `0` | `0` | `0` |
| `20260622_iwate_offshore_m30_eq10` | `20` | `0` | `0` | `15` |
| `20260622_iwate_east_offshore_m30_hinet` | `5` | `0` | `1` | `0` |

Offline geometry-only proxy for skipped existing `+3` stations:

| case | skipped existing `+3` | evaluated | same-id geometry | first-point fallback | wide reject |
| --- | ---: | ---: | ---: | ---: | ---: |
| `20260702_shizuoka_west_m36_jma_p2p` | `1333` | `1333` | `0` | `1333` | `0` |
| `20260702_fukushima_aizu_m46_jma_p2p` | `1289` | `1289` | `1166` | `123` | `0` |
| `20260624_fukushima_aizu_m32_jma_eq5` | `838` | `838` | `833` | `5` | `0` |
| `20260620_iwate_offshore_m34_ref` | `834` | `834` | `794` | `40` | `0` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `566` | `566` | `522` | `44` | `0` |
| `20260622_iwate_offshore_m30_eq10` | `549` | `549` | `474` | `75` | `0` |

This proxy is deliberately geometry-only: it uses station coordinates from
`NiedStationDb`, the exported `scratch_4_4_source_cache`, and the Scratch
wide-distance gate. It does **not** yet evaluate P/S timing residuals because
the exported `.reference.json` does not contain all per-station first
trigger/rise times.

Added a first P/S timing proxy using the first frame where a station appears in
`source_trigger_raw_member_ids` as the station observed time:

| case | skipped existing `+3` | same-id geometry | P-window | S-range | before-P reject | after-S reject | fallback |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `20260702_shizuoka_west_m36_jma_p2p` | `1333` | `0` | `0` | `0` | `0` | `0` | `1333` |
| `20260702_fukushima_aizu_m46_jma_p2p` | `1289` | `1166` | `963` | `175` | `0` | `28` | `123` |
| `20260624_fukushima_aizu_m32_jma_eq5` | `838` | `833` | `627` | `206` | `0` | `0` | `5` |
| `20260620_iwate_offshore_m34_ref` | `834` | `794` | `305` | `487` | `2` | `0` | `40` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `566` | `522` | `372` | `146` | `4` | `0` | `44` |
| `20260622_iwate_offshore_m30_eq10` | `549` | `474` | `121` | `353` | `0` | `0` | `75` |

Boundary: this is still a proxy, not the final sb3 record time. It uses
`first raw-member frame time`, not the internal `firstTriggerAt/firstRiseAt`
from `SeismicStationEventRecord`.

Interpretation:

- Existing-member overlap is real in six cases, not a rare edge case.
- Current code still reports `rerise refresh = 0` for all measured cases, so
  raw-current overlap should be read as "candidate evidence that Scratch may
  re-enter the existing-member path", not proof that Dart already reproduces
  that path.
- The geometry-only proxy says most skipped existing `+3` stations in the
  Fukushima/Iwate/Tomakomai cases can still geometrically belong to the same
  source id. Therefore the next missing discriminator is the P/S timing
  residual, not the broad distance gate.
- The first raw-member P/S proxy also accepts most skipped existing `+3`
  stations into P-window or S-range. This increases confidence that the missing
  `検出id3` existing-member path is materially affecting `+6/+7/+8`, but the
  final implementation still needs true `firstTriggerAt/firstRiseAt` timing
  before production behavior changes.
- However, late final frames often have much larger effective/continuity
  overlap than raw-current overlap. That means effective continuity cannot be
  treated as literal Scratch current-frame membership.
- Fukushima M4.6 shows the danger clearly: the diagnostic event-driven shadow
  cache can worsen the score sharply (`maxPositiveShadowScoreDelta ≈ 731.73`,
  at `2026-07-02T20:49:47 JST`). Therefore the answer is not to promote the
  naive event-driven shadow cache.
- Direct code difference found in the current Dart assignment loop:
  `if (state.assignedStationCodes.contains(code)) continue;`. This means
  already-assigned current detections never re-enter the `検出id3` /
  `検出id適用数カウント追加` path. Scratch instead runs
  `検出id1_全点へ適用 -> 検出id2 -> 検出id3` over points and then lets the
  procedure decide whether the point is a new assignment, same-id re-register,
  other-id switch, or lifecycle-only refresh.
- Tried a hot-path existing-assigned 4-2 selection probe and even a lighter
  count-only probe. Fukushima M4.6 still hits the replay test's five-minute
  timeout boundary. The probe was removed from `source_estimator.dart`; this
  analysis must stay offline until the replay runner is made faster or the
  timeout policy changes.

Next implementation target:

1. Continue from the sb3 procedures, not HYP score tuning:
   - `検出id3_点にIDを登録 %s %b`
   - `検出id適用数カウント追加 %s %b %s`
   - the `距離セット=true` branch that calls
     `推定用tenPS時間計算(多目的0,2使用)`.
2. Decode exactly when an already-assigned station re-enters the
   `距離セット=true` path. This is the missing piece for faithful
   `ten:推定用 +3/+6/+7/+8` lifecycle.
3. Build the sb3-shaped existing-assigned decision simulation in an offline
   report tool first. Same-id existing point, other-id switch candidate, and
   `+2`-only refresh must be counted separately before any production behavior
   changes.
4. Keep the current production full-refresh P/S cache as the guardrail until
   the Scratch event path is proven better in replay.

### 2026-07-04 update: true station timing for existing `+3` phase proxy

Added benchmark metadata:

- `sourceTriggerMetadata.station_trigger_observation_times`;
- per station: `first_trigger_at`, `first_rise_at`, interval starts, current
  trigger state, and `observed_time_source`.

This is exported from `StationTriggerSnapshot.firstTriggerInterval` /
`firstRiseInterval` in `test/support/source_estimation_benchmark.dart`, not
from estimator hot-path diagnostics.

Updated
`tools/build_kotoho7_existing_member_reregister_report.dart` to keep the old
first-raw-member proxy and add:

- `existingPlus3TrueTimingPhaseProxyModel`;
- `existingPlus3TrueTimingPhaseProxyPWindowTotal`;
- `existingPlus3TrueTimingPhaseProxySRangeTotal`;
- `existingPlus3TrueTimingPhaseProxyRejectedBeforePTotal`;
- `existingPlus3TrueTimingPhaseProxyRejectedAfterSTotal`;
- `existingPlus3TrueTimingPhaseProxyMissingObservedTimeTotal`.

Validation / regeneration:

```powershell
dart analyze tools\build_kotoho7_existing_member_reregister_report.dart test\support\source_estimation_benchmark.dart
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
flutter test test\iwate_offshore_m30_reference_replay_test.dart --concurrency=1
flutter test test\fukushima_aizu_reference_replay_test.dart --concurrency=1
dart run tools\build_kotoho7_existing_member_reregister_report.dart --input .dart_tool\source_estimation_benchmark --output .dart_tool\kotoho7_existing_member_reregister_report\report.json
```

True-timing comparison for regenerated references:

| case | skipped existing `+3` | same-id geometry | raw-member P/S | true-time P/S | after-S true | missing true |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `20260622_iwate_offshore_m30_eq10` | `549` | `474` | `121/353` | `290/153` | `0` | `0` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `566` | `522` | `372/146` | `403/15` | `0` | `0` |
| `20260624_fukushima_aizu_m32_jma_eq5` | `838` | `833` | `627/206` | `703/130` | `0` | `0` |

Interpretation:

- The old `first raw-member frame time` proxy is materially late. It was
  over-classifying existing `+3` stations as S-range.
- With true `firstTriggerAt ?? firstRiseAt`, the same skipped existing members
  become much more P-heavy, especially Tomakomai (`372/146 -> 403/15`) and
  Iwate M3.0 (`121/353 -> 290/153`).
- Therefore the next reproduction step should not tune a S-rich penalty from
  raw-member proxy numbers. It should implement the sb3 existing-member
  `距離セット=true` / `推定用tenPS時間計算` path using true station timing.
- P2P Fukushima/Shizuoka were not regenerated in this pass, so their
  true-timing fields remain missing and must not be used for this conclusion.

Added `scratchId2*` aggregate fields to the same offline report, sourced from
the already-exported
`stateful_source_cache.station_assignment_selection.entry_pipeline.scratch_id2_full_loop_simulation`.

Key result:

| case | id2 frames | would call id3 | initial state5 direct | existing rerise | existing +2 only | existing no-id3 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `20260702_fukushima_aizu_m46_jma_p2p` | `68` | `7038` | `7038` | `0` | `171` | `1013` |
| `20260702_shizuoka_west_m36_jma_p2p` | `62` | `2424` | `2424` | `0` | `27` | `1216` |
| `20260624_fukushima_aizu_m32_jma_eq5` | `62` | `372` | `372` | `0` | `72` | `737` |
| `20260620_iwate_offshore_m34_ref` | `56` | `155` | `155` | `0` | `135` | `671` |
| `20260622_iwate_offshore_m30_eq10` | `47` | `18` | `18` | `0` | `54` | `490` |
| `20260622_tomakomai_south_offshore_m35_hinet` | `42` | `10` | `10` | `0` | `51` | `501` |

Correction:

- In these replays, the current sb3-shaped id2 simulation does **not** find
  state6 existing-rerise candidates.
- `rerise refresh = 0` is therefore not by itself proof of a missing
  existing-rerise implementation.
- The dominant missing/interesting id3 path is `initial_state5_direct`, while
  already-known existing stations mostly fall into `existing_refresh_plus2_only`
  or `existing_no_id3_until_stale_or_rerise`.
- Next reproduction work should inspect why `initial_state5_direct` id3/4-2
  candidates are not producing the expected phase/source membership, instead
  of treating existing-rerise as the primary branch.

Historical code-level suspect (superseded on 2026-07-04):

- `_usableTimingRecords()` defaults to `maxRecords = 24`, selecting earliest 16
  plus strongest 16 and then taking 24.
- `_updateAssignedStationCodes()` currently receives capped
  `currentDetectionCandidates`, while the id2 diagnostic explicitly compares
  against `uncappedCandidatePool`.
- Scratch's point loop is over all points in `d ten:X`; this has since been
  moved into the default `scratch_full_point_id2_gate` assignment path. The
  note remains as historical context for the default-off experiments below.

Implemented gated experiments, default-off:

- metadata flag `kotoho7_assignment_candidate_mode = uncapped`;
- metadata flag `kotoho7_assignment_candidate_mode = uncapped_id2_gate`;
- benchmark switch
  `--dart-define=SOURCE_ESTIMATION_KOTOHO7_UNCAPPED_ASSIGNMENT_EXPERIMENT=true`;
- benchmark switch
  `--dart-define=SOURCE_ESTIMATION_KOTOHO7_ID2_GATED_ASSIGNMENT_EXPERIMENT=true`.

Superseded on 2026-07-04: default kotoho7 reference replay now uses
`assignment_candidate_mode = scratch_full_point_id2_gate`, i.e. the decoded
`検出id1_全点へ適用 -> 検出id2 -> 検出id3` full-point gate. The old `capped_24`
rows below are retained as historical measurements only.

Validation:

```powershell
flutter analyze lib\core\source_estimation\source_estimator.dart test\support\source_estimation_benchmark.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\iwate_offshore_m30_reference_replay_test.dart --concurrency=1
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --dart-define=SOURCE_ESTIMATION_KOTOHO7_UNCAPPED_ASSIGNMENT_EXPERIMENT=true --concurrency=1
flutter test test\iwate_offshore_m30_reference_replay_test.dart --dart-define=SOURCE_ESTIMATION_KOTOHO7_ID2_GATED_ASSIGNMENT_EXPERIMENT=true --concurrency=1
```

Measured experiment results:

| case / mode | wall test result | max uncapped pool | max assignment candidates | final error | final depth | final assigned | final P/S/O | p95 runtime |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Tomakomai reference `capped_24` | pass | `29` | `24` | `53 km` | `10 km` | `31` | `17/3/11` | `581 ms` |
| Tomakomai `uncapped` | pass (`02:29`) | `29` | `29` | `52 km` | `10 km` | `33` | `17/3/13` | `651 ms` |
| Iwate M3.0 reference `capped_24` | pass (`02:19`) | `23` | `23` | `47 km` | `40 km` | `25` | `5/14/6` | `1394 ms` |
| Iwate M3.0 `uncapped` | timeout (`05:03`) | not completed | not completed | - | - | - | - | - |
| Iwate M3.0 `uncapped_id2_gate` | pass (`04:05`) | `23` | `23` | `48 km` | `50 km` | `24` | `4/14/6` | `1390 ms` |

Interpretation:

- Tomakomai proves the uncapped path is wired correctly, but the improvement is
  tiny.
- Iwate M3.0 proves a second thing: this case never exceeded 24 candidates
  (`maxUncapped = 23`), so its poor result is not caused by the 24-point cap.
- The naive uncapped timeout should be treated as extra estimator overhead near
  the five-minute boundary, not proof that every frame has too many points.
- Next target should split cases:
  - cap-limited cases such as P2P Fukushima/Shizuoka need controlled candidate
    expansion;
  - non-cap-limited cases such as Iwate M3.0 need deeper alignment of source
    selection / PS timing / search, not cap work.

### 2026-07-04 update: article error-level truth score probe

Added diagnostic exports and a new offline tool:

- `stateful_source_cache.assigned_station_observed_times`;
- `station_ps_cache.s_flag_station_codes`;
- `tools/build_kotoho7_truth_score_probe.dart`.

The probe reads `.reference.json` without rerunning replay and scores the same
assigned station set twice:

1. current estimated source;
2. catalog truth source.

It uses the article-style error-level formula:

- station origin sample = observed time - selected P/S travel time;
- selected S is controlled by exported `ten:+6` S flag;
- origin time is the arithmetic mean of station origin samples;
- weight = first detected distance / station distance, with 50 km floor;
- score = S-factor * weighted origin scatter * station-count scale.

Validation:

```powershell
flutter analyze lib\core\source_estimation\source_estimator.dart tools\build_kotoho7_truth_score_probe.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\iwate_offshore_m30_reference_replay_test.dart --concurrency=1
dart run tools\build_kotoho7_truth_score_probe.dart --input .dart_tool\source_estimation_benchmark --output .dart_tool\kotoho7_truth_score_probe\report.json
```

Iwate M3.0 result after regenerating the reference with full assigned-station
times:

| frame | error | current score | truth score with same membership | truth-current | current P/S/O | truth P/S/O | assigned/scored | S flags |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| best | `22 km` | `3727.3` | `4012.7` | `+285.5` | `6/0/5` | `3/0/8` | `11/11` | `0` |
| final | `47 km` | `97.8` | `318.2` | `+220.4` | `5/14/6` | `2/13/10` | `25/25` | `16` |

Interpretation:

- For the final Iwate M3.0 frame, the current wrong source is not merely a
  search-path accident. Under the current replicated article error-level
  formula and current `ten:+6` S flags, the wrong source has a much lower score
  than the catalog truth using the same assigned stations.
- Therefore the next faithful-reproduction target is not more local-search
  radius/step tuning.
- The remaining likely mismatch is upstream of scoring:
  - exact station set that Scratch uses for `推定震源計算`;
  - exact `ten:+6/+7/+8` lifecycle and whether member-wide refresh is too broad;
  - Scratch grid/random thinning semantics for non-target points.
- Other cases in the probe should not be interpreted until their references are
  regenerated with `assigned_station_observed_times`; old references can show
  `scoredStationCount < assignedStationCount`.

### kotoho7 `複数トリガ` threshold digit/state-chain correction

Rechecked the local sb3 with a resolver that expands Scratch `[2, blockId]`
inputs instead of printing them as `?`. This exposed the exact active
`揺れ検出許可 -> 複数トリガ 状態` parameter mapping:

- `letter(1, d ten:しきい[番号])` = `上昇制限`
- `letter(2, d ten:しきい[番号])` = `しきい値`
- `letter(3, d ten:しきい[番号])` = `最低点数`

Implemented:

- fixed the Dart `@1 c:揺れ検出用` pass to use digit 3 for the normal-permission
  minimum point count and digit 2 for the acceleration threshold coefficient;
- added a nearest converted-shindo average probe for the Scratch
  `現在状態 = 0` / `そんなに震度高くない` branch;
- changed the detection-permission proxy from a direct rising-to-5 shortcut
  into a Scratch-style chain:
  `0 -> 1`, `1/2 -> 3`, `3/4 -> 5` only through nearby trigger or
  `@1 c:揺れ検出用` normal-permission gates;
- changed the first-trigger timeout to use
  `20 + 0.25 * third-nearest-distance`;
- removed the Dart-only generic `state 5 -> state 6 after 25s` timer.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\services\sources\nied_source_estimation_driver.dart lib\core\source_estimation\station_event_tracker.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
flutter test test\fukushima_aizu_reference_replay_test.dart --concurrency=1
```

### kotoho7 `gridトリガ` permission-state proxy

Expanded the local sb3 `grid:上昇中割合計算&トリガ` / `gridトリガ` branch.

Finding:

- `gridトリガ` is another permission-state producer, but it is not a blanket
  active-point-to-state-5 shortcut.
- Scratch first computes `grid:長期上昇観測点数` from each populated grid.
- A grid can trigger only when:
  - long-rising point count is greater than `5`;
  - weighted rise score is greater than `0.3`;
  - `grid:検出グリッド最大震度[grid] == -3`;
  - the four cardinal neighbor grid maxima are below `-2`.
- Then each point still needs:
  - `ten c:揺れ検出許可 > 0`;
  - positive long-rise delta;
  - `letter(3, d ten:しきい) < 4`;
  - own permitted shindo lower than nearby permitted shindo support.

Implemented:

- `_applyKotoho7GridTriggerPermissionProxy` after the per-point
  `複数トリガ` permission pass;
- `_kotoho7GridLongRiseProxy` for the Scratch weighted rise-count/score pair;
- Scratch-style no-op when the target point is already state `5`;
- reason count `scratch_permission_grid_permission` when the branch changes
  state.

Known proxy boundary:

- The replay data does not include runtime `grid:検出グリッド最大震度` or
  `grid:長期上昇観測点数`.
- Dart derives grid max from `scratchDetectionPermittedShindo`.
- The sb3 branch uses cardinal offsets `-26/+26/-1/+1`; Dart preserves those
  for this permission branch while the existing detection-id 9-grid carrier
  remains on the previously mapped 23-column offsets.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
flutter test test\fukushima_aizu_reference_replay_test.dart --concurrency=1
```

### kotoho7 stateful `@1 検出グリッド最大震度キープ`

Completed the stateful carryover for the grid-max proxy.

Implemented:

- `scratchGridDetectionMax` for current `grid:検出グリッド最大震度`;
- `scratchGridDetectionMaxKeep` for previous-frame
  `@1 検出グリッド最大震度キープ`;
- `_kotoho7GridDetectionMaxProxy` now follows the Scratch order:
  1. copy current grid max into keep;
  2. reset populated current grids to `-3`;
  3. update current grid max from current permitted records;
- low-shindo update now distinguishes `keep == -3`, `keep == -2`, and other
  previous values;
- invalidation clears both maps;
- same-source merge carries over stronger grid max / keep values.

Still not exact:

- This note's populated-grid limitation was removed by the later
  `dc grid連番:点がある番号` correction: Dart now mirrors the 92 Scratch populated
  grids and the flat 70-slot carrier insertion.
- The high-shindo `d #震度換算30段階[ten:震度 + 60]` approximation was also
  replaced by the extracted grid/status range in the later
  `d #震度換算30段階[ten:震度 + 60]` update.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
flutter test test\fukushima_aizu_reference_replay_test.dart --concurrency=1
```

### kotoho7 `grid:検出グリッド最大震度` source correction

Expanded `検出許可震度算出` and confirmed that `grid:検出グリッド最大震度`
is updated before `gridトリガ`, not inside it.

Finding:

- At the start of `検出許可震度算出`, Scratch copies the current grid max into
  `@1 検出グリッド最大震度キープ`, then resets each populated grid to `-3`.
- Only points with `ten:震度 > 0` and `ten c:揺れ検出許可 >= 4` can update the
  grid max.
- For `ten:震度 > 6`, the point updates the grid only when it is fresh:
  `age < 30`, or `ten:震度 > 9 && age < 400`.
- For lower shindo, Scratch writes the status-like values `-1` / `-2` /
  `-2 + (age < 15)` depending on the previous keep value.

Implemented:

- `_kotoho7GridDetectionMaxProxy` now computes a per-frame grid max from
  current records and permission state;
- the `gridトリガ` isolation check now reads this grid max proxy instead of the
  older `scratchDetectionPermittedShindo` maximum.

Known remaining gap:

- Later 2026-07-03 updates made
  `@1 検出グリッド最大震度キープ` stateful and replaced the high-shindo fallback
  with the extracted `d #震度換算30段階[ten:震度 + 60]` display/status range.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart
flutter test test\source_estimator_test.dart --concurrency=1
flutter test test\tomakomai_south_offshore_reference_replay_test.dart --concurrency=1
flutter test test\fukushima_aizu_reference_replay_test.dart --concurrency=1
```

### kotoho7 `ten:震度変化速度` source correction

Expanded `点震度の処理`, `震度履歴移動`, `ten震度更新`, and
`震度履歴時間管理` from the local sb3.

Finding:

- Scratch computes `ten:震度変化速度` from converted shindo history, not raw
  indexes and not immediate previous-frame difference.
- The relevant expression is effectively current converted shindo minus the
  converted shindo about 4 seconds earlier (`ten:震度履歴時間2000s[11]`).

Implemented:

- added the 30-step conversion table from `d #震度換算30段階`;
- current converted shindo now falls back through raw/detect 30-step conversion;
- change-speed now uses the observation-history frame about 4 seconds earlier;
- positive speed checks now read that signed 4-second value.

Validation:

```powershell
dart format lib\core\source_estimation\source_estimator.dart
flutter analyze lib\core\source_estimation\source_estimator.dart lib\services\sources\nied_source_estimation_driver.dart lib\core\source_estimation\station_event_tracker.dart
flutter test test\source_estimator_test.dart --concurrency=1
```

### 2026-07-05 scope marker: park cloud/EEW runtime, resume article HYP

Decision:

- The kotoho7 note article `揺れ検知から震央を検出してみる` documents the
  HYP-style algorithm: JMA2001 P/S travel time, `誤差レベル`, weighted origin
  time variance, unarrived-station penalty, and staged candidate search over
  lat/lon/depth/origin time.
- The Scratch cloud variables (`☁ c2h`, `☁ c2b*`) and the EEW circle branch
  (`0EEW`, `EEW情報の処理`, `円の中トリガ`) are real runtime logic, but they
  are not described by that article. They are now documented separately in
  `docs/reference/kotoho7_cloud_eew_source_logic.md`.
- Current implementation work should return to the article/Scratch HYP path
  rather than spending the next pass on cloud-variable capture.

Next algorithm focus:

1. Recheck `HYP:誤差レベル計算` against the article and extracted Scratch blocks.
2. Recheck staged movement order in `HYP:誤差レベル比較繰り返し`.
3. Keep depth/origin-time search inside the HYP candidate loop.
4. Treat cloud/EEW circle permission as a later integration item, not the
   current algorithm-replication blocker.

Immediate working rule:

- For the next implementation pass, start from the article HYP chain only:
  `HYP:誤差レベル計算` -> `HYP:誤差レベル比較` ->
  `HYP:誤差レベル比較繰り返し` -> `HYP:震源検出`.
- Do not use `円の中トリガ`, `EEW情報の処理`, or `☁ c2h/c2b*` to patch scoring
  behavior in this pass. Those are documented runtime/permission inputs, not
  the article's source-search algorithm.

### Production kotoho7 JS receiver replay hook

The production NIED source-estimation path now has an opt-in replay hook for
the direct kotoho7 Scratch JS receiver method:

```text
nied_gif_kotoho7_js_receiver_v1
```

Replay input uses the same metadata shape as production
`NiedSourceEstimationDriver`, so the JS bridge receives per-frame observations
instead of Dart-inferred phases:

```json
{
  "kotoho7_receiver_frame_key": "2026-06-10T18:12:34.000Z",
  "kotoho7_receiver_current_frame_observations": [
    {
      "stationCode": "NAR001",
      "observedAtUtc": "2026-06-10T18:12:34.000Z",
      "gifDecodedShindo": 0.7
    }
  ]
}
```

Run it explicitly, because the JS receiver bridge is much slower than the
legacy replay estimators:

```powershell
flutter test test\source_estimation_baseline_test.dart `
  --dart-define=SOURCE_ESTIMATION_KOTOHO7_JS_RECEIVER_REPLAY=true
```

Verified on the Nara replay: the report includes
`nied_gif_kotoho7_js_receiver_v1`, and JS diagnostics include
`best_source_phase_stations`, `best_source_p_radius_km`, and
`best_source_s_radius_km`.

### 2026-07-07 Dart local estimator parameter promotion

Scope:

- This pass only changes the Dart-side local estimators and UI data plumbing.
- It does not replace or modify the production kotoho7 JS receiver algorithm.
- It addresses the concrete gap found in the Dart layer: depth and magnitude
  were either absent from `SourceEstimate` or trapped inside diagnostics.

Implemented:

- `SourceEstimate` now has an optional formal `magnitude` field.
- `NiedGifHybridSourceEstimator` now promotes supported HYP/grouped depth into
  formal `depthKm` instead of leaving depth only in diagnostics.
- `NiedGifHybridSourceEstimator` now promotes supported
  `diagnostic_magnitude_jma_style` into formal `magnitude`.
- `TriggerTimeDepthGridSearchEstimator` now emits the same diagnostic
  JMA-style inverse magnitude and promotes it only when
  `diagnostic_magnitude_supported == true`.
- `Kotoho7ReferenceHypSourceEstimator` now emits and promotes the same
  Dart-side diagnostic magnitude against its HYP depth.
- `Kotoho7JsReceiverSourceEstimator` only maps an upstream JS
  `source.magnitude` if the JS result actually provides it; it does not invent
  one in Dart.
- The local timing-record cap in `_usableTimingRecords` increased from 24 to
  48 records, using up to 24 earliest timing picks and 24 strongest picks before
  the final deterministic sort. This reduces avoidable loss of far-field P/S
  and strong-station information for Dart local depth/magnitude diagnostics.
- Source-estimation UI events now pass `estimate.magnitude` into
  `UnifiedQuakeData`, so a supported Dart local magnitude can be displayed
  instead of being hidden.
- UI method labels now match the actual Dart depth-grid method id
  `trigger_time_depth_grid_v3`.

Important boundary:

- The promoted Dart magnitude is still `jma_style_intensity_inverse_v1`, i.e.
  a post-source inverse-intensity diagnostic. It is not an EEW report number
  and not the kotoho7/Scratch cloud EEW magnitude path.
- Promotion is intentionally gated: unsupported or high-spread diagnostic
  magnitude remains `null`, not a fake M value.
- The remaining Dart algorithm gap is still the deeper one: the simple
  grid/depth estimators are not a full station-cluster state machine with exact
  P/S lifecycle, inactive-station penalty, and article/Scratch HYP assignment
  semantics.

Validation:

```powershell
flutter analyze lib\core\source_estimation\source_estimation_models.dart lib\core\source_estimation\source_estimator.dart lib\widgets\ui\alert_module.dart test\source_estimator_test.dart
flutter test test\source_estimator_test.dart
```

### 2026-07-07 Production NIED source path switched back to Dart HYP

Scope:

- Production NIED source estimation no longer defaults to the JS receiver
  bridge.
- The default estimator is now the Dart HYP state-machine wrapper:
  `nied_dart_hyp_v1`.
- JS bridge classes and benchmark tooling remain in the tree for explicit
  comparison only; they are not the default production estimator.

Input adaptation:

- The NIED driver now emits a neutral station snapshot input format:
  `nied_station_hypocenter_snapshot_v1`.
- The snapshot follows the same worker-style data shape used by the external
  reference implementation, but uses our own names and production metadata:

```json
{
  "nied_hypocenter_new_active_stations": [
    {
      "id": 123,
      "code": "ABC001",
      "latLng": [37.1, 141.0],
      "triggerStamp": 1780000000000,
      "updateStamp": 1780000001000,
      "ascend": 3,
      "level": 12,
      "detectLevel": 12,
      "activity": 8.0,
      "isActive": true
    }
  ],
  "nied_hypocenter_active_stations": [],
  "nied_hypocenter_inactive_stations": [],
  "nied_hypocenter_adj_station_ids": {
    "123": [123, 124, 125]
  }
}
```

Implemented:

- `StationEventTracker.useDefaultNiedEstimator()` now installs
  `NiedDartHypSourceEstimator`.
- `NiedDartHypSourceEstimator` wraps the existing Dart HYP state machine but
  exposes production method id `nied_dart_hyp_v1` and neutral top-level
  diagnostics.
- `NiedSourceEstimationDriver` no longer publishes
  `kotoho7_receiver_frame_key` or
  `kotoho7_receiver_current_frame_observations` in production metadata.
- GIF direct replay/injection uses event ids prefixed with `nied-gif-dart-`.
- Non-GIF realtime input still waits for the source trigger gate; only GIF
  direct input bypasses the gate.
- Estimate signatures now include `nied_hypocenter_frame_key`, so Dart HYP can
  update once per input frame without depending on JS frame keys.

Validation:

```powershell
flutter analyze lib\core\source_estimation\station_event_tracker.dart lib\core\source_estimation\seismic_source_tracker.dart lib\core\source_estimation\source_estimator.dart lib\services\sources\nied_source_estimation_driver.dart lib\widgets\ui\alert_module.dart test\nied_source_estimation_driver_test.dart test\source_estimator_test.dart
flutter test test\nied_source_estimation_driver_test.dart
flutter test test\source_estimator_test.dart
```

### 2026-07-07 NIED station update alignment replay check

Scope:

- Aligned `NiedStation.update` with the station-side reference ordering and
  scales:
  - raw `originLevel` is pushed to `recentLevel` before `calcAscend`;
  - `calcAscend` and `isAbnormalStation` use `recentLevel`;
  - `calcActivity` uses display `level`;
  - ascend is calculated as `level - latestMinVal`.

Validation:

```powershell
flutter analyze lib\services\sources\nied_monitor.dart lib\services\sources\nied_source_estimation_driver.dart lib\core\source_estimation\station_event_tracker.dart
flutter test test\current_capture_replay_analysis_test.dart --timeout 10m
```

Result:

- Analyze passed with no issues in 9.5 s.
- Replay passed in 1 m 18 s and refreshed
  `.dart_tool/current_capture_replay_analysis/report.md`.
- Current replay report still shows the same large 岩手県沖 final error:
  `40.533, 141.600 / conf 0.31 / support 131`, `52.9 km`, with
  `late_first_estimate_23s`, `large_final_error_52.9km`, and
  `large_estimate_jump`.

Follow-up finding:

- The station update fixes are present, but this replay miss is now downstream
  of the HYP implementation rather than the station-side level/ascend update.
- Reference `NiedHypoInf.js` uses the four search steps
  `{3,100}`, `{1,50}`, `{0.3,20}`, `{0.1,10}`, a minimum inference cluster
  size of 5, inactive penalty weight from 10 at cluster size 0 to 0 at 50,
  and score `(rmse + inactivePenalty * weight) * waveCountPenaltyMultiplier`.
- The current Dart HYP path still uses a Scratch-derived/custom staged search
  and scoring model with additional phase, pair, regularization, and unarrived
  terms, so the next alignment task is to port the reference
  `FindNiedHypocenter` cluster/search/scoring path more directly before
  expecting this 岩手 replay error to move.

### 2026-07-07 NIED worker-snapshot HYP input and calculation path

Scope:

- `NiedDartHypSourceEstimator` now treats the reference worker update shape as
  first-class input:
  `newActiveStations`, `activeStations`, `inactiveStations`, `adjStationIds`
  via the existing `nied_hypocenter_*` metadata keys.
- The worker path no longer converts the snapshots back into the legacy
  `SeismicStationEventRecord` timing pipeline before estimating.
- The direct worker HYP branch uses the reference constants and scoring shape:
  - `minInferenceClusterSize = 5`;
  - search steps `{3,100}`, `{1,50}`, `{0.3,20}`, `{0.1,10}`;
  - inactive penalty weight from 10 at cluster size 0 to 0 at 50;
  - score `(rmse + inactivePenalty * weight) * waveCountPenaltyMultiplier`;
  - quality rank minimum counts `S:200`, `A:100`, `B:30`, `C:10`, `D:0`.
- The first worker calculation branch is intentionally P-only. The previous
  greedy P/S assignment moved late 岩手 frames westward; full reference parity
  still needs the multi-scenario P/S comparison from `NiedHypoInf.js`.
- `NiedSourceEstimationDriver` now seeds worker active snapshots from the
  current source detection members and writes back `station.setActive()` for
  reference-style active lifecycle behavior.

Validation:

```powershell
flutter analyze lib\services\sources\nied_source_estimation_driver.dart lib\core\source_estimation\source_estimator.dart test\source_estimator_test.dart
flutter test test\source_estimator_test.dart --name "NIED Dart HYP estimates directly from worker snapshot input"
flutter test test\nied_source_estimation_driver_test.dart --name "GIF direct input uses Dart hypocenter snapshot metadata"
flutter test test\current_capture_replay_analysis_test.dart --timeout 10m
```

Result:

- Analyze passed.
- The worker-snapshot unit test proves `NiedDartHypSourceEstimator` can estimate
  from the reference worker input shape with `stations: []`.
- Current capture replay passed in 20 s.
- Replay report after the worker HYP branch:
  - 福島県浜通り M3.4: final `36.400, 140.100`, error `128.2 km`;
  - 岩手県沖 M3.6: final `40.500, 141.500`, error `60.3 km`;
  - `12:15 noise trigger`: no estimate.
- 岩手 now has good intermediate frames, including `40.500, 142.200` with
  `11.1 km` error, but late frames still drift to the west. The remaining gap
  is the reference cluster lifecycle/stable hypocenter and full P/S scenario
  scoring, not the worker input plumbing.

### 2026-07-17 KA 输入与文章震源算法边界改造

规范边界：

- NIED 检出输入以 KA 为准：`level` 为 `-1..20`，并使用 KA 的
  `recentLevel / ascend / activity / triggerStamp / active / inactive` 语义；
- 震源核心以文章《揺れ検知から震央を検出してみる》为准；
- Scratch `project.json` 只补充文章未展开的实现细节，不反向覆盖文章步骤；
- 禁止用 Robust detector 时间、接收时间或固定间隔补造 worker
  `triggerStamp`。

本次修正：

- Yahoo 与 GIF 共用 KA 的活动站筛选、`chainActivate`、未活动站筛选和
  worker 快照，不再把 Yahoo 的旧 source-trigger 成员直接送入震源拟合；
- worker 快照对齐 KA：`id / latLng / triggerStamp / updateStamp / ascend /
  level / isActive`，仅额外保留本地 `code` 标识；
- 修复邻站表 key 错误：旧代码以 station id 建表，却用 station code 查询，
  导致所有站的邻站列表为空；
- 拆分 KA 两张邻站表：检出使用 30 km 内最多 6 站（孤站可补一个
  30--40 km 站），震源簇使用 30 km 内全部站并按四方向补站到 300 km；
- KA 的 1 度事件偏移网格继续用于检出和 detection ID carrier；HYP 未着惩罚
  后续已按当前 JS 修正为候选 P 波动态半径，不再固定为活动格周围 9 格；
- 修复 GIF 输入更新时间顺序：先写本帧 `lastDataTime/updateStamp`，再执行
  `NiedStation.updateFromContinuousShindo()`，确保 `calcAscend()` 生成的是
  本帧真实 `triggerStamp`；
- 修复 Yahoo 输入相同的更新时间顺序错误：原实现先执行 `station.update()`，
  再写本帧时间，会让 `calcAscend()` 使用上一帧时间或初始 `0`；现已与 KA
  `update(intensity, updateStamp)` 的先写 `updateStamp` 顺序一致；
- KA 新版 `NiedNet.vue` 为每站固定传入 `expireSeconds = 10`。生产 Yahoo、GIF、
  同步检出、后台检出及回放 fixture 已统一为 10 秒，并删除旧的“level 上升时
  动态延长 expireSeconds”和缺帧时动态缩短逻辑；`recentLevel` 历史容量仍为 KA
  的 60 帧，这里的 10 秒窗口与已删除的 Scratch 30 级输入是两个不同概念；
- 修复 KA `level 0` 的连续震度回退值：精确为 `-3.0`，不使用通式得到
  `-3.25`；
- 删除生产 NIED 推算路径的 Scratch 30 级转换表和 30 级 fallback；
- `NiedDartHypSourceEstimator` 有 KA 快照时不再退回旧
  `Kotoho7ReferenceHypSourceEstimator`；不足 5 个真实触发时刻时直接不估算；
- 此阶段曾删除旧实现中来源未核实的 `score * 1.7` 门；后续核对当前 Scratch
  `HYP:震源検出` 原块后，已恢复其真实的“本轮分数小于历史最低已发布分数
  `* 1.7` 才写回”语义；
- 文章步骤（3）改为：所有活动站发震时刻的普通平均值、距离权重乘平方误差
  后求和；规定时窗内每个理论已到但未检出的站对误差水平直接 `+1`；
- 文章步骤（4）保持四阶段邻域下降：`0.5 deg`、`0.1 deg`、
  `0.1 deg + 50 km`、`0.1 deg + 10 km`。
- KA worker 的 `activeStations` 按 detection ID 累积，不再随单站 10 秒 active
  窗口丢失；历史站继续参与本 ID 的走时拟合和 carrier 生命周期，但不再把固定
  周围 9 格并集当作 HYP 未着范围；
- 文章步骤（2）在首检出后 10 秒内从首站临时震源重新开始，10 秒后从上一轮
  震源继续搜索；所有历史站仍只使用各自真实 KA `triggerStamp`；
- Scratch 补充的 `ten:推定用 +6/+7/+8` 已接入：站点分配时用上一震源缓存
  P/S 理论到时和 `abs(observed-S) < abs(observed-P)` 标记，首检出 15 秒内仍
  全部按 P，15 秒后才按缓存标记选择 P/S。该标记采用 Scratch 默认的
  assignment-only 生命周期，不随每次震源更新做全站重算；
- P/S 缓存读取 Scratch `4-4 検出id震源要素` 的量化参考：纬经度 `1/60°`，
  深度与发震时刻为整数；该补充细节不改变文章的搜索坐标和误差公式；
- 新站并入事件前使用 Scratch `検出id4-2` 原始时间窗：P 容差
  `5 + 震央距離/120` 秒；不在 P 窗时，只有处于 P 窗之后且不晚于
  `S到时 + 8 + 震央距離/120` 的站才能按 S-range 并入。接受/拒绝原因写入
  request metadata 和本轮估算 diagnostics；
- 右下角真实算法曲线与评分共用同一 P/S 选择。诊断样本保留 station id/code、
  经纬度、`triggerStamp/updateStamp`、距离、观测/预测时刻、残差、权重、KA
  level、ascend 和 wave；出现真实 S 样本时同时绘制 P/S 理论曲线；
- 曲线点颜色删除残留的 30 级阈值，直接使用 KA `-1..20` 色表；
- 曲线上 P 站使用圆点，算法实际选择为 S 的站使用红色描边菱形；形状直接来自
  同一评分样本的 `wave` 字段，不做显示侧推测；
- 第 10 秒后若活动站 code/坐标/真实 `triggerStamp` 未变化且没有跨越 15 秒 P/S
  门，复用同事件上一轮结果，跳过重复的四阶段搜索和 5 个曲线候选计算。新增站、
  P/S 门变化和时间倒退仍强制重算。

验证：

```powershell
flutter analyze lib\services\sources\nied_source_estimation_driver.dart `
  lib\core\source_estimation\source_estimator.dart `
  lib\services\sources\jp_shindo_scale.dart

flutter test test\source_estimator_test.dart `
  test\nied_source_estimation_driver_test.dart `
  test\nied_detection_rules_test.dart `
  test\nied_station_observation_adapter_test.dart `
  test\station_event_tracker_test.dart --timeout 2m

flutter test test\current_capture_replay_analysis_test.dart --timeout 10m
```

结果：

- 最新静态分析通过；检出规则、driver、估算器和事件 tracker 定向测试 33 项
  全部通过；
- Yahoo/GIF 快照测试确认 KA level 与各站原始 `triggerStamp` 原样进入 worker；
- 反例测试确认活动站缺少 KA `triggerStamp` 时保持 `null`，且不输出震源；
- 后台 worker 测试确认所有测站固定收到 KA 的 10 秒 expire；测站测试确认
  `triggerStamp = 本帧 updateStamp - latestMinIndex * 1000`；
- 当前 capture 回放恢复真实估算，噪声窗口仍为 0 次估算；
- 福島県浜通り M3.4：12 帧有估算，最终解 `36.840, 140.300`，误差
  `80.5 km`，支持 13 站，深度 `40 km`；
- 岩手県沖 M3.6：28 帧有估算，最终解 `40.370, 141.880`，误差
  `27.3 km`，支持 39 站，深度 `90 km`；
- `12:15 noise trigger` 仍为 0 次估算；
- 历史站/P/S 改造没有普遍降低误差：岩手由 `34.2 km` 改进到 `27.3 km`，福岛
  由 `61.1 km` 恶化到 `80.5 km`。福岛在 `12:09:36` 尚为
  `37.040, 140.600 / 40 km / 45.7 km`，`12:09:37` 新加入 `SIT004`、
  `GNMH12` 并按缓存标记使用 S 后，立即移动到最终偏西位置；
- 把 P/S 缓存参考进一步对齐 Scratch `4-4` 的 `1/60°`/整数值后，两个事件的
  S 标记、最终坐标和误差均未改变，因此可排除量化边界；
- 加入 Scratch `4-2` 归属窗后，福岛 `SIT004/GNMH12` 和岩手
  `IWTH22/IWT014/IWTH19` 均按原公式通过 `accept_s_range`，最终结果不变；
- 回放报告增加只读真值分数探针：使用相同站集和缓存 wave，在目录真值经纬度
  扫描 `0..700 km` 深度。福岛首个 S 帧当前误差水平 `5.157`、真值最佳
  `58.778`；最终当前 `5.464`、真值最佳 `90.431`。岩手最终当前 `74.427`、
  真值最佳 `119.208`。因此错误位置确实是当前步骤（3）误差面的更低谷；
- KA 输入时刻顺序和固定 10 秒窗口修正阶段曾把同一报告从福岛 `192.5 km`、
  岩手 `135.9 km` 降到 `61.1 km`、`34.2 km`；本轮再加入事件历史站和 Scratch
  P/S 生命周期后变为 `80.5 km`、`27.3 km`。两个阶段都没有加入平滑、结果
  保留门或伪造时刻；
- 报告位置：`.dart_tool/current_capture_replay_analysis/report.md`。

剩余问题：

- KA 输入链已打通，当前剩余误差不再是 30 级错域、上一帧 Yahoo 时刻或动态
  expire 窗口造成的假象；
- 福岛当前误差跳变已锁定到两个真实晚加入站的 S 波选择，而不是网格搜索未运行、
  历史站丢失或曲线伪造；岩手的三个晚加入 S 站则使最终误差略有下降；
- 福岛真值探针中，原 P 站的反推发震时刻约集中在 `-19 s`，但 `SIT004`、
  `GNMH12` 按 S 反推分别约为 `-26.945 s`、`-29.371 s`，两站单独贡献真值
  误差水平约 `39.36/58.78`。当前偏西震源通过让这组触发贴近 S 曲线取得更低分；
- 文章原文以 P 波为默认检出走时，同时明确说明“S 波と思われる検知には S 波の
  走時を使用”；因此不能为了福岛真值误差而删除真实 S 选择。下一步只能继续核对
  步骤（3）中晚加入站进入同一事件及误差水平的条件；不得用恢复 30 级、删除真实站
  或补造触发时刻来压住漂移。

### 2026-07-17 KA 输入下的多 detection ID 与网格 carrier

边界：

- 文章步骤（2）（3）（4）的临时震央、误差水平和四阶段搜索保持不变；
- Scratch `project.json` 只补充测站属于哪个 detection ID、ID 何时失活/合并的
  生命周期，不把旧 Scratch 30 级震度重新带回输入；
- 每个 detection ID 独立保存历史站、assignment-only P/S 缓存、上一轮震源和
  真实曲线；一个 ID 的站不会进入另一个 ID 的误差水平；
- 网格 carrier 使用 KA 检出的 1 度事件偏移网格。carrier 只保存真实站所在格的
  detection ID 和归属帧时刻，不是测站，不进入 P/S 走时或误差曲线。

实现：

- 新站归属顺序为：显式 Scratch runtime timer 捷径（生产未提供时不触发）、KA
  邻站继承、Scratch 最新 ID 距离门、当前格 `<2 s`、`4-2` P/S 时间窗、周围
  9 格 `<=5 s`，最后才新建 ID；
- 与 Scratch 原始块一致，最多存在两个 detection ID；已有两个 ID 且所有候选门
  都失败时拒绝该站，不无限创建 ID；
- ID 寿命为成员数 `<200` 时 `(3 + 成员数) * 2 s`，否则 `400 s`；超过
  `150 s` 且成员少于 50 站也失活；
- 两个有效 ID 的首检出时刻相差小于 20 秒、文章分数均小于 500，且震源距离小于
  `50 km + 两个首站最大半径平均值 / 2` 时，旧 ID 合并到较新 ID；
- tracker 只能显示一个 `SourceEstimate`，输出层按本帧真实 KA 活动站与各 ID
  成员的重合数选择；同分时保持上一输出 ID。该选择只决定显示哪个独立文章结果，
  不进入任何 ID 的评分；所有 ID 状态均写入 `detection_ids` 诊断；
- 回放报告改为逐帧深拷贝 metadata/diagnostics，避免历史帧引用同一个可变 Map 后
  全部显示成末帧状态；estimator 返回 `null` 时也刷新 detection ID 诊断。

验证：

```powershell
flutter analyze lib\core\source_estimation\source_estimator.dart `
  lib\services\sources\nied_source_estimation_driver.dart `
  test\source_estimator_test.dart `
  test\current_capture_replay_analysis_test.dart

flutter test test\source_estimator_test.dart `
  test\nied_source_estimation_driver_test.dart `
  test\nied_detection_rules_test.dart --concurrency=1

flutter test test\current_capture_replay_analysis_test.dart `
  --timeout 10m --concurrency=1
```

结果：

- 静态分析通过；算法、driver 和 KA 规则共 30 项定向测试通过；真实回放测试约
  9 秒完成；
- 新增测试确认两个时空不相容的 KA 站群形成两个独立 ID，并分别保留自己的
  站集/P-S 缓存；当前格 `0.5 s` 命中 `scratch_grid_current`，邻格
  `3.5 s` 命中 `scratch_grid_around_9`；
- 福島県浜通り M3.4：最终 `37.040, 140.600 / 40 km / 支持 10 站`，误差
  `45.7 km`，取代上节单 ID 生命周期的 `80.5 km`；
- 福岛 ID 1 在 `12:09:36` 按 10 站对应的 `26 s` 寿命失活。`12:09:37`
  的 `SIT004/GNMH12` 均保留真实 `12:09:36` 触发时刻，`12:09:38` 的
  `SITH08` 保留真实 `12:09:37` 触发时刻；其余 KA 活动站的触发时刻为 null，
  因而新站群只有 3 个真实时刻，未达到文章最小 5 站门，未形成伪造的第二震源；
- 岩手県沖 M3.6 保持 `40.370, 141.880 / 90 km / 支持 39 站`，误差
  `27.3 km`。`IWTH22` 通过真实 `4-2 S` 窗进入 ID 1，`IWT014/IWTH19`
  通过 KA 邻站继承进入 ID 1；
- `12:15 noise trigger` 仍为 0 次估算；
- 最新报告：`.dart_tool/current_capture_replay_analysis/report.md`。

### 2026-07-17 当前 Scratch HYP 搜索与真实地图候选

依据边界：

- KA 继续只负责真实检出输入：`level -1..20`、`triggerStamp`、`activity`、
  `ascend` 和 detection ID；没有恢复 Scratch 30 级输入；
- 文章作者也是当前 Scratch 工程作者。文章解释算法目的和步骤，当前
  `project.json`/编译 JS 决定 HYP 的实际改良参数；
- 当前 JS 与文章旧截图的差异不是混用：临时震源和最终输出按 `1/60°` 量化，
  四个文章阶段后还有水平 `1/60°` 精细搜索。

搜索改造：

- 当前 detection ID 的真实首检出站固定为初始化站。KA worker 保留
  `activeStations` 的测站表顺序，Scratch `project.json` 的 `d ten:x/y` 点表
  均为 1748 项，并按该点索引顺序执行 detection ID 分配；不得再按
  `triggerStamp + code` 重排同秒测站。临时震源为
  `round(coord * 60) / 60`、深度 `10 km`、发生时刻 `triggerStamp - 2 s`；
- 搜索阶段对齐 JS：水平 `±0.5°`、水平 `±0.1°`、
  `±0.1° + 深度 ±50 km`、`±0.1° + 深度 ±10 km`、水平 `±1/60°`；
- 检出站数不超过 10 时跳过 `±0.5°`；早期帧和各阶段采用 JS 的移动次数上限，
  diagnostics 区分 `skipped_station_count`、`local_minimum` 和 `move_limit`；
- 候选顺序保持东、西、北、南、深度加、深度减；每个阶段停止时保存最后一轮
  实际比较的坐标、深度、分数和拒绝原因，不再从曲线面板反推地图候选；
- 候选有效域对齐 JS：深度 `10..700 km`、纬度 `15..55`、经度
  `115..155`，并应用
  `round(11 + 最大检出距离^3 * 0.00008)` 动态最大深度及
  `round(50 + 0.3 * (站数 * 10 + 最大检出距离))` 首站距离上限；
- `最大检出距离` 槽位继续按 Scratch detection ID 原式计算：
  `dtc:Xpix=(经度-136)*10`、
  `dtc:Ypix=(Mercator纬度-Mercator(35))*10`，两点投影差的欧氏长度再乘
  `11`。它不是 HYP 候选到首站所用的球面距离；旧实现误用 haversine，福岛
  首帧由错误的 `52.43 km` 修正为 `64.73 km`；
- 非法深度直接拒绝，不 clamp 成伪造的 `0 km` 候选。
- 10 秒后仅当本轮分数小于该 ID 历史最小已发布分数的 `1.7` 倍时写回
  `4-4`；被拒绝的搜索结果保留在 `searched_result`，不覆盖当前震源。

评分改造：

- 发生时刻仍取所有真实检出站反推发生时刻的普通平均值；每站平方残差乘
  `max(50, 首站震央距) / max(50, 本站震央距)`。临时震源、动态候选域和该
  距离权重都显式读取 detection ID 的 `firstStationCode`，不再让重新排序后的
  `active.first` 暗中替换首站；
- JS 分数改为
  `max(0.25, 1 - 3*S数/n) * ((加权平方和 + 未着数) / 权重和) *`
  `(30 + 20000/(1+n^2) + 2000/(50+n))`；不再把后三项错误固定为 1；
- 未着站主筛选改为同一候选发生时刻下 JMA2001 逆算的
  `P波半径 + 30 km`，并使用 JS 的 `100 + 最大检出距离*3` 半径上限；删除本地
  `最远活动站 + 30 km` 和 10 秒后直接关闭惩罚的非 JS 逻辑；
- JS 为大站数使用的随机抽样分支没有伪造成确定值；当前实现使用其确定性的
  P 波半径主分支，后续如同步随机抽样必须先定义可复现策略。

地图显示：

- Scratch 运行地图从 `4-4 检出id震源要素` 第 2/3 槽读取当前震源经纬度，
  第 7/8 槽绘制 P/S 圈；它不保存文章示意图中的红色真值点；
- 主地图显示真实首站临时点、当前解和最终 `1/60°` 阶段最后一轮真实候选。
  当前/临时点使用橙色叉与圆环，候选使用绿色叉；同经纬度的深度候选合并到
  当前点文字，避免重叠；
- 若 JS `1.7` 倍写回门拒绝本轮结果，橙色点继续表示已发布当前解，本轮搜索中心
  以绿色“未采用”显示；两者不会被混成一个点；
- P/S 圈由当前估算震源、当前发生时刻和 JMA2001 逆算得到，并使用同一簇半径
  上限；不使用固定波速或接收时刻补造半径；
- 实时没有目录真值，因此不画文章示意图中的红色“实际震源”叉。

验证：

```powershell
flutter analyze lib\core\source_estimation\source_estimator.dart `
  lib\widgets\map\quake_map_view.dart `
  test\source_estimator_test.dart

flutter test test\source_estimator_test.dart --concurrency=1

flutter test test\current_capture_replay_analysis_test.dart `
  --timeout 10m --concurrency=1
```

结果：

- 静态分析通过，震源估算器 11 项定向测试通过，真实回放约 9 秒完成；
- 福岛首轮 KA worker 测站表顺序为
  `IBR004, TCG001, TCG006, IBRH15, IBRH16, TCGH13, TCGH19`，因此当前
  Scratch detection ID 的真实首站是 `IBR004 / 12:09:07`，JS 临时点为
  `36.550000, 140.416667 / 10 km`。同秒时刻仍保留 KA 的整秒值，没有插值；
- 首站修复后，福岛首个当前解为
  `36.850000, 140.350000 / 10 km`。目录真值 `37.3, 141.0` 在相同 7 个 P 站、
  相同 `IBR004` 距离权重和 JS 深度域下的 active timing residual 为
  `1.4611`，低于当前解的 `1.6072`；但 7 站按 JS 条件跳过 `±0.5°`，搜索停在
  西南侧局部极小值；
- 投影距离修正后，福岛候选域首帧为 `最大深度 33 km / 首站半径 90 km`，
  末帧为 `33 km / 99 km`；末帧目录真值到 `IBR004` 的 `98.36 km` 已进入合法
  候选域，但 10 站仍不会触发 JS 的 `±0.5°` 粗搜索，因此最终解没有改变；
- 福島県浜通り M3.4 最终为 `36.850, 140.400 / 10 km / 支持 10 站`，误差
  `73.1 km`；岩手県沖 M3.6 最终为
  `40.383, 141.900 / 80 km / 支持 36 站`，误差 `25.5 km`；
- 仅用于定位的对照实验把 `±0.5°` 启用门从 JS 原值 `站数 > 10` 临时改为
  `站数 >= 5`：福岛改善到 `36.950, 140.517 / 20 km / 57.9 km`，岩手保持
  `25.5 km`。实验结束后已恢复 JS 原条件；该参数未进入生产代码；
- `12:15 noise trigger` 仍为 0 次估算；本轮对齐使误差变大，说明旧的较小误差
  不是 JS HYP 参数下的结果，不能为了贴近真值恢复非 JS 评分或伪造候选；
- 最新报告：`.dart_tool/current_capture_replay_analysis/report.md` 和
  `.dart_tool/current_capture_replay_analysis/report.json`。

### 2026-07-17 当前 Scratch JS 的完成、稳定与消失生命周期

语义边界：

- `end1` 只表示本轮五阶段 HYP 搜索结束，当前临时震源已停在本轮局部谷底；
  它不表示事件永久结束，也不停止后续接站、重算或波圈更新；
- 本轮搜索结果是否写回 `4-4`，只服从 Scratch JS 的规则：首次检出后 10 秒内
  直接写回，之后仅当本轮分数小于历史最低已发布分数的 `1.7` 倍时写回；
- detection ID 是否仍活动、已发布震源是否仍显示，是独立于本轮搜索结束的状态；
  没有导入 KA 的 15 次稳定门，也没有导入文章后半段气象厅改良 IPF 的 EQc
  稳定 5 秒及 300--900 秒删除条件；
- KA 仍只提供 `level -1..20`、真实 `triggerStamp`、`activity`、`ascend` 和
  active/inactive 输入。生命周期中的“最大震度低于 3”直接由 KA level 映射到
  JMA 震度判断，没有恢复 Scratch 30 级输入。

实现：

- 删除同站集超过 10 秒后直接复用整个 `SourceEstimate` 的错误缓存。每个不同的
  真实帧时刻都会重新计算未着惩罚、搜索、`1.7` 写回门、diagnostics 和波圈；
  完全相同的帧时刻与输入只计算一次，避免同一数据回调重复触发搜索；
- detection ID 失活条件按当前 JS 原块实现：不在 grid carrier 中超过 2 秒；
  成员数 `<200` 时超过 `(3 + 成员数) * 2 s`，否则超过 `400 s`；年龄
  `>150 s` 且成员数 `<50`；成员数 `<2`；以及成员数 `<5`、首站最大投影
  距离 `<80 km`、已发布误差 `>3000`、最大震度 `<3`、年龄 `>10 s` 的
  小簇条件；
- grid carrier ID 集合为空时清空 detection ID、已发布震源和地图状态，等价于
  JS 同时清空 `4-3 检出id別情報` 与 `4-4 检出id震源要素`；
- `NiedDartHypSourceEstimator` 显式拥有自己的输出生命周期。默认 NIED 路径不再
  经过 tracker 的 15 秒暖机、60 km 跳变和 100 km 锚点稳定门；估算器发出
  `nied_dart_hyp_clear_published_source` 后，tracker 必须清除旧震源，不能以
  “低支持”名义保留；
- HYP 只在 detection ID 年龄 `<120 s` 时运行。达到 120 秒后保留最后已发布
  震源并继续按当前算法时刻更新 P/S 圈；发生后达到 `300 s` 时半径写为 JS 的
  无效值并隐藏；
- 主地图直播使用当前时刻，回放使用真实回放帧时刻，依据已发布发生时刻、深度和
  JMA2001 逆算 P/S 半径，并应用同一簇 `100 + 最大检出距离 * 3` 上限；没有
  UI 自增的伪造时刻。

diagnostics 将四层状态分开记录：

- `search_cycle_ran` / `search_cycle_finished` / `search_termination_reason`；
- `search_result_accepted` 与 `historical_minimum_published_score`；
- `detection_id_active` / `detection_id_expire_at` /
  `nied_dart_hyp_has_active_detection_id`；
- `hyp_calculation_enabled` / `hyp_age_s` / `source_visible` /
  `source_clear_reason` / `wave_radius_visible`。

验证：

```powershell
flutter analyze lib\services\sources\nied_monitor.dart `
  lib\services\sources\nied_source_estimation_driver.dart `
  lib\core\source_estimation\station_event_tracker.dart `
  lib\core\source_estimation\seismic_source_tracker.dart `
  lib\core\source_estimation\source_estimator.dart `
  lib\widgets\map\quake_map_view.dart `
  test\source_estimator_test.dart `
  test\seismic_source_tracker_test.dart `
  test\current_capture_replay_analysis_test.dart

flutter test test\source_estimator_test.dart `
  test\seismic_source_tracker_test.dart --concurrency=1

flutter test test\current_capture_replay_analysis_test.dart `
  --timeout 10m --concurrency=1
```

结果：

- 9 个相关文件静态分析通过；估算器与 tracker 共 23 项测试通过；真实回放测试
  通过；
- 测试确认同一站集在下一真实帧不再返回冻结对象，elapsed、未着惩罚、搜索和
  波圈继续变化；同一帧重复输入只计算一次；JS 自有输出可绕过通用稳定门，并在
  detection ID 失活后清除旧震源；
- 福島県浜通り M3.4 最终为
  `36.800, 140.317 / 10 km / 支持 10 站 / 误差 82.3 km`；
- 岩手県沖 M3.6 最终为
  `40.383, 141.900 / 80 km / 支持 36 站 / 误差 25.5 km`；
- `12:15 noise trigger` 仍为 0 次估算；
- 最新报告：`.dart_tool/current_capture_replay_analysis/report.md` 和
  `.dart_tool/current_capture_replay_analysis/report.json`。

### 2026-07-17 Scratch 未着站动态半径

事实核对：

- JS `WHYP:誤差レベル計算` 不会把未着站固定限制在 detection active grid 的
  周围 9 格。它逐候选计算当前 P 波半径，扫描候选周围
  `P 波半径 + 130 km` 内的网格，并在确定性主分支中对
  `P 波半径 + 30 km` 内、尚未属于当前 detection ID 的测站判断理论 P 波是否
  已到达；
- 固定 9 格是 KA 检出阶段的网格范围，不能继续充当 Scratch HYP 未着站范围；
- 当前 Scratch 点表 `d ten:x/y` 均为 1748 项。KA 输入中 `level > -1` 的站
  表示本帧有有效观测，可作为“尚未检出”的证据；`level == -1` 的缺测站不作为
  未着证据；
- JS 对大簇另有随机降采样，以及当前 detection ID carrier 格内的 50% 随机
  补样。当前实现只同步确定性主分支，未把随机结果伪造成固定值。当前回放中，
  正常 `P+30 km` 半径外但位于 carrier 格内的候选站并非 0：福岛最多 47 站、
  岩手最多 24 站，因此该随机分支仍可能改变早期搜索，但不存在唯一可复现的
  Scratch 输出可直接写成固定断言；

实现：

- driver 向 Scratch HYP 提供全网 KA `level > -1` 且未进入本帧活动输入的站，
  不再预先裁成周围 9 格；
- 每个 detection ID 在 worker 内排除自己的历史成员，其他 detection ID 的站仍
  可作为本 ID 的未着证据；
- 候选评分继续用 JMA2001 逆算 P 波半径，并在候选层执行
  `surfaceDistance <= P 半径 + 30 km` 与理论 P 到时判断。直接按站距离过滤与
  JS 先按 `+130 km` 网格粗筛、再按 `+30 km` 测站精筛的确定性结果等价，同时
  避免为每个候选构造临时网格列表。
- 1.7 写回门拒绝本轮结果时，发布震源继续使用 `4-4` 旧坐标，但右下角走时
  曲线改为本轮真实 `searchedResult`，不再沿用旧发布帧的 score、origin 和未着
  半径；主界面曲线刷新签名同时纳入 searched score、接受状态和 elapsed。

验证结果：

- driver 与 estimator 共 23 项定向测试通过，真实回放测试通过；
- 岩手后段每帧输入约 1591 个 KA level 有效未着候选，但最终震源处真正满足
  动态半径及理论到时条件的未着惩罚保持为 27。原固定 9 格版本在西移候选处只看
  到局部 178 站，使该候选错误通过 `1.7` 写回门并产生 `53.0 km` 结果；动态
  半径同步后西移候选被拒绝，最终恢复为 `25.5 km`；
- 福岛由于候选间的全网动态未着约束发生变化，最终误差由 `73.1 km` 变为
  `82.3 km`。该变化来自 JS 未着范围同步，没有调整搜索步长、真实触发时刻或
  `1.7` 写回阈值；
- 回放验证被拒绝帧的发布解与本轮曲线已分开：岩手 `elapsed=65 s` 的发布解仍为
  `40.383, 141.900`，本轮 searched/曲线中心为 `40.267, 141.600`，曲线分数
  `1000.02`、未着参考半径 `624.9 km`；
- 最新报告：`.dart_tool/current_capture_replay_analysis/report.md` 和
  `.dart_tool/current_capture_replay_analysis/report.json`。

### 2026-07-18 P/S 波圈回放消失回归

现象与原因：

- detection ID 消失逻辑完成后，目录回放中的已发布震源仍存在，算法 diagnostics
  也包含正常的正数 P/S 半径，但主地图没有绘制波圈；
- 原因不在 detection ID 失活条件，而在地图层新增了第二次半径计算。该计算在
  `niedReplayNotifier` 未启用时使用 `DateTime.now()`；目录回放、测试回放等入口
  不一定通过这个设置开关，因此六月回放事件会被七月墙钟误判为发震后已超过
  300 秒，地图把 P/S 半径改成 `999999` 并隐藏；
- 这是 UI 层伪造算法时刻，覆盖了 estimator 已按真实回放帧计算的半径。

修复：

- 地图删除基于墙钟的二次 JMA2001 逆算，只读取 estimator diagnostics 中的
  `best_source_p_radius_km` / `best_source_s_radius_km`；
- 直播、设置页回放、目录回放和测试回放现在统一使用各自真实算法帧已经计算好的
  半径；只有 estimator 按算法时刻写入 `999999` 时，CircleLayer 才隐藏波圈；
- 新增纯函数 `niedWaveRadiiFromEstimate()` 和两项回归测试，确认历史 originTime
  不会触发墙钟隐藏，并确认算法的 `999999` 隐藏哨兵仍被保留。

验证：

```powershell
flutter analyze lib\widgets\map\quake_map_view.dart `
  test\nied_wave_radius_display_test.dart

flutter test test\nied_wave_radius_display_test.dart --concurrency=1

flutter test test\current_capture_replay_analysis_test.dart `
  --timeout 10m --concurrency=1
```

结果：静态分析通过；波圈显示回归测试 `2/2` 通过；真实回放测试通过。

### 2026-07-18 JMA2001 曲线真实范围与逐站拟合误差

问题事实：

- 算法曲线原来把最远测站距离至少扩到 `50 km`，并按 `25 km` 向上取整；
  painter 又把横轴乘以 `1.04`，并根据整条理论曲线扩大时间范围、额外添加
  `12%` 纵向留白。因此面板显示的时间和距离并不是本轮算法测站输入范围；
- 算法已经输出每站真实 `observed_s`、JMA2001 `predicted_s` 和
  `residual_s`，但主界面预处理丢弃了 `residual_s`，painter 只画观测点，无法
  直接判断每站到所选 P/S 曲线的拟合方向和误差；
- 原标题把 `score` 简写为“误差”，第二行又显示包含未着惩罚的 `rmse`。
  实际算法中三者定义不同：`score` 是搜索实际比较分值，`error_level` 是乘
  S 站数系数前的误差水平，原 `rmse` 为
  `sqrt((weightedResidualSquares + inactivePenalty) / weightSum)`；
- 评分使用未取整的平均发生时刻，旧曲线却使用写入 `DateTime` 后已按毫秒取整的
  `originTime`。单测确认这会使画面残差 RMSE 与评分残差出现约
  `0.000005 s` 的细小但真实差异。

修复：

- 算法曲线距离域严格结束在本候选全部真实活动站的最大震中距，不再强制
  `50 km`、不再按 `25 km` 取整；只有全部测站距离为 0 的退化输入使用
  `0..1 km` 防止除零；
- 正常事件坐标范围固定为
  `X = 0..distance_max_km`、
  `Y = observed_min_s..observed_max_s`。理论 P/S 曲线超出首站到末站的真实时间
  窗口时由 plot clip 裁剪，不能反向扩大坐标轴；只有零时间跨度使用
  `min..min+1 s` 防止除零；
- 曲线发生时刻直接按本候选评分公式，从所有活动站的
  `observed_s - selectedTravelTime` 求未取整平均值，不再经过毫秒化的
  `DateTime`；因此曲线、每站预测点、残差和评分使用同一个精确 origin offset；
- 新增 `active_timing_rmse =
  sqrt(weightedResidualSquares / weightSum)`，它只表示真实活动测站点对所选
  JMA2001 P/S 曲线的拟合，不包含未着惩罚；
- 主界面保留每站 `code` 和 `residual_s`。每个有效站绘制同一距离上的
  `predicted_s -> observed_s` 残差线，预测端画空心小点，观测端继续使用 KA
  level 颜色；P 站为圆点，算法实际选择为 S 的站为红色描边菱形；
- 当前选中的搜索候选保留全部真实活动站，UI 不再把有效站二次截断为前 48 个；
  仅非选中的邻近对比候选继续保留 80 站诊断上限，避免多个辅助面板无界扩大
  diagnostics；
- 面板明确分列“搜索分值 `score`”“误差水平 `error_level`”“点 RMSE
  `active_timing_rmse`”“含未着 RMSE”和“未着惩罚”，不再把不同公式都显示成
  一个模糊的误差；坐标轴端点直接显示真实秒数和公里数。

验证：

```powershell
flutter analyze lib\core\source_estimation\source_estimator.dart `
  lib\screens\main_screen.dart `
  test\source_estimator_test.dart

flutter test test\source_estimator_test.dart --concurrency=1

flutter test test\current_capture_replay_analysis_test.dart `
  --timeout 10m --concurrency=1
```

结果：

- 3 个相关文件静态分析通过；震源单测 `12/12` 通过；真实回放测试通过；
- 福島県浜通り M3.4 最终搜索曲线范围为
  `0..43.016123 km / 0..3 s`，曲线末端距离与最远站完全相同，搜索分值
  `3641.180235`，误差水平 `5201.686050`，点 RMSE `1.001450 s`，未着惩罚
  `189`；
- 岩手県沖 M3.6 最终搜索曲线范围为
  `0..135.327722 km / 0..20 s`，曲线末端距离与最远站完全相同，搜索分值
  `1000.020175`，误差水平 `1300.026227`，点 RMSE `1.763105 s`，未着惩罚
  `795`；
- 两个真实事件逐站检查均满足
  `residual_s == observed_s - predicted_s`，最大差值为 0；按显示样本重新计算的
  点 RMSE 与面板 `active_timing_rmse` 完全一致；
- `12:15 noise trigger` 仍为 0 次估算；最新报告位于
  `.dart_tool/current_capture_replay_analysis/report.md` 和
  `.dart_tool/current_capture_replay_analysis/report.json`。

### 2026-07-18 山梨 M5.6 后期搜索误差与 Scratch 权重下限

回放输入：

- 目录：
  `tmp/captures/20260626_yamanashi_east_fuji_five_lakes_m56_jma_p2p`；
- `capture_manifest.json` 与本地 JMA/P2P 参考均记录
  `35.6, 139.0 / 深度20 km / M5.6`；
- 时间范围 `2026-06-26 22:28:30..22:31:00 JST`，实际读取 141 个
  `jma_s` 帧，缺 10 秒。

修复前逐帧事实：

- 首个震源出现在 `22:29:05`；发布震源在 `22:29:24` 后保持
  `35.517, 139.100 / 10 km`，真值水平误差 `12.95 km`，没有继续移动；
- 继续变大的是本轮 `searched_result.score`，不是已发布震源误差：
  `22:30:00` 为 `168.14`，`22:31:00` 为 `515.18`；历史最低发布分数
  `76.78` 的 `1.7` 倍为 `130.53`，所以这些后期搜索结果均被 Scratch 写回门
  拒绝；
- 未着惩罚始终为 0。后期增长来自活动站曲线点 RMSE：从 `2.56 s` 增至
  `4.20 s`；
- `22:30:00` 与 `22:31:00` 比较，原有 638 站的 triggerStamp 和 P/S 标志均
  没有变化，后一帧新增 242 个远站，最终搜索面板共有 880 个同 ID 站；
- 最后一帧 KA 输入本身仍有 953 个 active 站，worker 选中 ID 使用其中 880
  站，因此本事件不是 worker 保留已从 KA active 消失的旧站。远站是 KA 当前
  active 输入，再通过 Scratch `検出id4-2` 的
  `5 + distance/120` P 窗口或 P 到 S 的宽区间进入该 ID。

确认的 Scratch 漏项：

- `HYP:誤差レベル計算` 在计算距离权重前明确执行：

  ```text
  firstDetectedDistance = max(50 km, candidateToFirstStationDistance)
  stationDistance = max(50 km, candidateToStationDistance)
  weight = firstDetectedDistance / stationDistance
  ```

- 直接 NIED worker 原来只对 stationDistance 实现了 50 km 下限，却直接使用
  candidateToFirstStationDistance 作为分子。山梨候选靠近首站时，50 km 外站权重
  会错误接近 0；这些站仍进入未加权 origin 均值，却几乎不能用自己的残差约束
  候选；
- `_niedHypWorkerFirstDetectedDistanceKm()` 已改为
  `max(50.0, haversineDistance)`；测试新增 50 km 外合成站，并断言远站权重严格
  等于 `max(50, firstDistance) / stationDistance`。

修复后回放：

- 最小真值误差为 `19.97 km`（`22:29:12`）；最终发布震源为
  `35.483, 139.183 / 20 km / 支持309站`，真值误差 `21.06 km`；
- 最终发布分值 `110.52`，后期本轮搜索分值仍随远站增加而上升，最后为
  `518.03`，但继续被 `1.7` 写回门拒绝；发布震源没有被后期搜索覆盖；
- 最后一帧搜索面板有 880 个真实站，权重和为 `251.80`，点 RMSE
  `4.707 s`，P/S 缓存中 S 站 96 个；
- 水平真值误差比修复前增大，说明旧的 `12.95 km` 部分依赖漏掉 50 km 分子
  下限后对远站的错误降权。不能为了贴近真值恢复该偏差；该修改是 Scratch 公式
  对齐，不是真值调参。

额外 JS 核查：

- `検出id_推定PS時間id別再計算` 在参考 `project.json` 中存在定义，但完整调用图
  中没有 `procedures_call`；因此不能把它解释为每次 HYP 后整批重算已有站 P/S；
- 当前“站进入 detection ID 时根据量化 4-4 震源缓存写入 +6，已有站保持缓存”与
  实际可达调用方向一致；本轮没有添加推测性的 P/S 重算；
- 福島、岩手和噪声回放结果在权重下限修复前后不变，仍分别为
  `82.3 km`、`25.5 km` 和 0 次估算。

验证：

```powershell
flutter analyze lib\core\source_estimation\source_estimator.dart `
  test\source_estimator_test.dart `
  test\current_capture_replay_analysis_test.dart

flutter test test\source_estimator_test.dart --concurrency=1

flutter test test\current_capture_replay_analysis_test.dart `
  --timeout 10m --concurrency=1
```

结果：静态分析通过；震源单测 `12/12` 通过；默认福島/岩手/噪声回放通过；
山梨定向回放通过。山梨报告单独输出到
`.dart_tool/yamanashi_m56_replay_analysis/report.md` 和 `report.json`。

### 2026-07-18 KA new-active 输入语义与活动网格生命周期

对照 KA 当前 `NiedNet.vue`、`FindNiedHypocenterWorker.js` 和
`NiedHypoInf.js` 后确认，worker 的三类输入职责不同：

- `newActiveStations` 只负责把本帧首次进入 KA active 窗口的测站注册进推算簇；
- `activeStations` 只负责更新已注册站的 `level`、`ascend`、`updateStamp` 等当前
  来源状态；
- `inactiveStations` 供未着惩罚和簇消失判断使用；
- KA worker 首次创建时由调用方把全部当前 active 站作为初始
  `newActiveStations`，后续帧不再把全部 active 站重复作为新成员候选。

发现并修复两个输入边界错误：

- Dart 解析器原来把 `newActiveStations` 与 `activeStations` 合并成一张表，随后
  detection-ID 层每帧都尝试把全部 KA active 站注册为新成员；现在 worker frame
  保留两张独立表，已有 owner 的 active 站只更新状态，只有 new-active 站才进入
  `検出id3/4` 注册路径；完全没有 new-active 字段的旧调用方保留首次兼容入口；
- `_dartHypActiveStationCodes` 原来在整场事件中只追加不删除，含义实际变成
  “曾经 active”，并被用于活动网格；现在每帧替换为当前 KA active 集合，活动
  网格只读取当前 `station.isActive`，失活站不会继续维持陈旧网格，再次进入的站
  可以重新出现在 new-active 输入中。

震度处理边界：

- Scratch `HYP:誤差レベル計算` 不直接使用 `level`；震度只影响上游成员/生命周期；
- Scratch 30 级 `ten:震度 > 0` 表示有有效数据，其第 1 级就是 `-3.0`。映射到
  KA 输入应为 `level >= 0`，不能把 KA `level == 0` 当成无效站删除；
- KA `NiedHypoInf.js` 的拟合贡献主要由历史 `maxAscend`、测站密度、触发顺序和
  异常值过滤决定；`maxLevel` 只参与未着惩罚参考站资格。由于生产核心仍按
  文章/Scratch，本轮没有把 KA 权重混入 HYP 评分公式。

山梨 M5.6 对比：

- 修复前最终发布震源为 `35.483, 139.183 / 20 km`，误差 `21.06 km`，发布支持
  309 站；最后一帧 worker 880 站，本轮搜索分值 `518.03`，点 RMSE `4.707 s`；
- 修复后最终发布震源为 `35.517, 139.133 / 10 km`，误差 `15.21 km`，发布支持
  231 站；最后一帧 worker 825 站，本轮搜索分值 `429.59`，点 RMSE `3.741 s`；
- 最终误差改善来自输入语义修正，没有修改 JMA2001、P/S 判定、搜索步长、距离
  权重、未着惩罚或 `1.7` 写回门；默认福島、岩手、噪声回放仍为
  `82.3 km`、`25.5 km`、0 次估算；
- 后期 worker 仍会累计 KA 真正发出的 new-active 站，这是 KA 簇生命周期本身；
  其本轮搜索分值继续上升的剩余原因位于“累计成员如何贡献评分”，不再是
  active/new-active 传递错误。若继续处理，必须明确选择是否在输入贡献层引入 KA
  的 `maxAscend`/密度/触发顺序规则，不能把它伪装成文章/Scratch 原公式修复。

验证：静态分析通过；`source_estimator_test.dart` 13/13、
`nied_source_estimation_driver_test.dart` 12/12、山梨定向回放和默认回放全部通过。
最新山梨报告位于 `.dart_tool/yamanashi_m56_ka_input_lifecycle/report.md` 和
`report.json`。

#### KA 零贡献测站门

继续核对 `NiedHypoInf.js#getStationWeight` 后确认，KA 簇成员不等于 KA 实际拟合
成员：历史 `maxAscend < 2` 时测站权重严格为 0。为保持“KA 输入、文章/Scratch
核心”的边界，本轮只实现这个零权重资格门，没有移植 KA 的非零权重倍率、密度
权重、触发顺序权重或异常值过滤：

- detection ID 和簇生命周期继续保存全部 KA new-active 成员；
- 临时震央、首站时刻和 detection ID 首站仍取真实簇首站；
- 进入 HYP 评分、P/S 曲线和站数缩放的有效输入要求历史 `maxAscend >= 2`；
- 通过资格门的站仍完全使用原有 Scratch 距离权重，JMA2001、P/S、搜索和评分
  常数均未改变；
- diagnostics 新增 `cluster_station_count`、`effective_input_station_count`、
  `zero_contribution_station_count`、`station_contribution_model`，曲线只绘制本轮
  实际参与评分的有效站，避免把零贡献站伪装成拟合点。

山梨最后一帧由 825 个真实簇成员分成 767 个有效拟合站和 58 个零贡献站；本轮
搜索分值从 `429.59` 降到 `316.01`，点 RMSE 从 `3.741 s` 降到 `3.096 s`。
最终发布震源保持 `35.517, 139.133 / 10 km`，误差仍为 `15.21 km`，发布支持由
231 变为 229，说明资格门改善的是后期真实拟合而不是用真值调坐标。

默认回放也发生输入集合变化：福島由 `82.3 km` 变为 `78.8 km`，岩手由
`25.5 km` 变为 `27.1 km`，噪声仍为 0 次估算。岩手的 `1.6 km` 变差被保留，
不能因为单个事件指标方向不利而恢复 KA 中本来为零的测站贡献。

验证：`source_estimator_test.dart` 14/14 通过，山梨定向回放和默认回放通过。
山梨报告位于 `.dart_tool/yamanashi_m56_ka_zero_weight_gate/report.md` 和
`report.json`。

### 2026-07-18 发布震源、地图标记与走时曲线快照统一

检查主界面后确认，地图与曲线此前读取了两个不同结果：地图当前标记使用通过
Scratch `1.7` 写回门后真正发布的 `result`，而 `travel_time_curve_panels` 使用
本轮 `searchedResult`。当后期搜索被拒绝时，地图标记保持不动，曲线却继续按
未采用候选的位置、深度、时间和当前站点集合重算，导致面板分值、距离与地图
当前标记不一致。

本轮只修正发布与诊断边界，没有改变搜索核心：

- 地图算法层只显示当前已发布震源，移除临时震源、未采用结果、最终搜索方向和
  深度候选标记；P/S 波圈仍使用同一个已发布 `SourceEstimate`；
- 曲线只保留一个 `current` 面板；面板经纬度、深度和 `origin_time` 必须分别等于
  当前已发布估计，不再生成邻近候选曲线；
- 新结果通过写回门时，按该次评分实际收到的有效站列表和当次 P/S 标志生成完整
  曲线快照。`maxAscend < 2` 的零贡献站、未分配进 detection ID 的站和未着惩罚站
  均不进入拟合点；
- 新结果未通过写回门时，直接复用上一次已发布曲线的同一个快照对象，不使用被
  拒绝的 `searchedResult`，也不按后续变化的测站重新计算距离、发生时刻、权重、
  P/S 或残差；
- 曲线覆盖层以快照对象身份作为刷新签名。后台继续搜索但发布快照未改变时，不再
  重复启动 isolate 解析和主线程重绘；
- diagnostics 改为
  `travel_time_curve_source=published_result_accepted_scoring_snapshot`，并新增
  `travel_time_curve_frozen` 与 `travel_time_curve_sample_count`；地图模型改为
  `map_candidate_model=published_result_only`。

验证：

- `flutter analyze` 对 5 个相关源码和测试文件检查通过；
- `source_estimator_test.dart` 与曲线生命周期测试共 17 项通过；新增定向测试明确
  制造后续高未着惩罚并命中 `search_result_accepted=false`，确认发布位置、时间、
  分值、曲线列表对象和样本列表对象全部保持不变；
- 默认真实回放通过，结果仍为福島 `78.8 km`、岩手 `27.1 km`、噪声 0 次估算；
- 最终福島和岩手报告都只有一个曲线面板，分别保留 8 站和 20 站；最后一帧均为
  `travel_time_curve_frozen=true`，面板位置、深度和发生时间与最终发布估计完全
  一致。报告位于 `.dart_tool/current_capture_replay_analysis/report.md` 和
  `report.json`。

### 2026-07-18 千葉県東方沖深度与 P/S 圈核查

用户提供的下载定位时间为 `2026-07-18 04:45:22 JST`；截图中的 JMA 事件卡
发震时刻为 `04:45:15 JST`，震源参数为 `35.7, 141.1 / 40 km / M4.3`。使用
`04:44:52--04:47:22 JST` 的 151 张 `jma_s` 回放后，算法最终发布震源为
`35.783333, 141.316667 / 10 km`，发生时刻 `04:45:14.681`，支持 209 站，到
JMA 震中的水平距离为 `21.64 km`。

深度核查结论：

- 最终候选域允许深度达到 `700 km`，深度阶段实际评估了 `20 km` 和 `60 km`；
  `10 km` 不是默认值未被更新，也不是动态深度上限误拒绝；
- 最终搜索中心的评分为 `10 km: 514.289`、`20 km: 520.310`、
  `60 km: 591.054`，因此当前错误经纬度附近确实以 10 km 为局部最低；
- 将经纬度固定在 JMA 震中、保持同一批 209 个算法实际 P/S 样本和权重，只读扫描
  深度时最佳为 `30 km`，点 RMSE `2.548 s`。这说明经纬度与深度的联合误差面陷入
  局部谷底；不得把 JMA 的 40 km 真值直接写回生产算法伪装修复；
- 地图当前震源标记保留最有用的“误差”显示，但数值改为读取算法真实
  `error_level`，不再把乘过 S 站数系数的 `score` 当成误差。截图对应值应为
  `误差 322.99`，而不是原来的 `score 285.72`；公里误差仍只在有目录真值的
  回放报告中计算。

P/S 圈核查与修正：

- 算法帧使用真实已发布震源、发生时刻、深度、JMA2001 逆算和
  `100 + 最大检出距离 * 3` 半径上限，公式本身未使用固定波速；
- 原地图虽然以 2 fps 重绘，却每次读取最后算法帧中冻结的
  `best_source_p_radius_km/best_source_s_radius_km`。NIED 帧停止后，JMA 正式事件
  继续按当前时钟传播，而推算圈停在最后一帧，视觉差距会持续扩大；
- diagnostics 现在显式保存本轮真实 `wave_radius_cap_km`。地图以最后真实
  `wave_elapsed_s` 为锚点，通过单调时钟继续使用同一 JMA2001 和同一半径上限反算，
  到 300 秒仍按 Scratch 生命周期隐藏；历史回放或缺少锚点时仍保留原算法帧半径；
- 在经过时间 141 秒时，JMA2001 的 10 km 深度 P/S 半径约为
  `1066.15/582.06 km`，40 km 深度约为 `1086.13/598.56 km`。剩余约
  `20/17 km` 差距来自真实推算深度不同，不在显示层伪造补齐。

验证：`nied_wave_radius_display_test.dart` 与 `source_estimator_test.dart` 共 19 项
全部通过；三个相关文件 `flutter analyze` 无问题。千葉回放报告位于
`.dart_tool/current_capture_replay_analysis_chiba_20260718/report.md` 和
`report.json`。

### 2026-07-18 主界面 HYP 曲线方形面板与 Debug 开关

本轮只修改算法诊断 UI，不改变已发布震源、测站样本、P/S 分类、JMA2001 曲线、
误差水平或搜索分值：

- 主界面右下角曲线由桌面 `560 x 268` 长方形改为响应式正方形；宽屏首选
  `300 x 300`，较窄桌面随 `UiScale.compact` 缩到约 `255 x 255`，手机首选
  `240 x 240`，并继续受实际视口可用宽高约束；
- 方形紧凑标题重新排成四行，保留当前震源坐标、深度、`error_level`、点 RMSE、
  发生时刻、搜索分值、含未着 RMSE、未着惩罚和实际使用站数；曲线坐标轴及真实
  测站点的数据范围没有变化；
- Debug 页 `NIED Source Estimation` 卡片新增“主界面曲线面板”开关。开关通过
  `UiRuntimeFlags.niedHypCurvePanelVisibleNotifier` 立即控制主界面，并持久化到
  `debug_nied_hyp_curve_panel_visible`；启动时加载，默认开启；
- 面板关闭时，overlay 不再为后续震源帧启动曲线 payload isolate 解析；重新开启后
  从当前已发布曲线快照重新准备一次，避免隐藏状态继续消耗 CPU；
- 测试构建入口使用同步 payload 准备，以便准确定位真实曲线画布；生产路径仍使用
  `compute` isolate，没有把曲线解析移回主线程。

验证：曲线 overlay 的方形尺寸、清空/缩放/卸载、deactivate/activate 和 Debug
开关关闭/恢复共 3 项组件测试全部通过；原 `source_estimator_test.dart` 15 项算法
测试通过；5 个相关文件 `flutter analyze` 无问题。

### 2026-07-18 千葉県東方沖后期误差增长与文章未着门修正

重新读取文章“③ 仮の震源が実際の震源にどのくらい近いかの値を計算する”和
“④ 誤差レベルの計算を繰り返して震源位置を特定する”后，确认文章对未着惩罚有
明确的启用范围：检出后 `3 s` 内，或者检出后 `10 s` 内且检出站少于 `30` 时，
才把理论上已经到达但尚未检出的站加入误差。当前 direct worker 原来采用新版
Scratch `project.json` 的长期未着分支，超过该范围后仍持续计数；这违反了“评分
核心按文章、project.json 只补充文章未展开部分”的边界。

修正内容：

- 每帧统一计算
  `elapsed <= 3 || (elapsed <= 10 && effectiveActiveCount < 30)`；本帧起始中心和
  所有经纬度/深度候选使用同一个门，门关闭时未着惩罚、未着 P 半径和参考距离
  均为 `0`；
- `elapsed` 锚定到 detection ID 创建时写入后不再变化的时刻，和 Scratch
  `4-3 +3` 一致；不再使用“当前成员最早 triggerStamp”，避免后加入一个更早时刻
  的成员后，ID 年龄从 `6 s` 倒跳到 `12 s`。diagnostics 分开记录
  `elapsed_since_detection_id_created_s` 和首站真实
  `elapsed_since_first_trigger_s`；
- diagnostics 新增
  `inactive_penalty_gate_model=kotoho7_article_elapsed_le_3_or_elapsed_le_10_and_active_lt_30`
  与 `inactive_penalty_gate_open`，不再根据误差值猜测门状态；
- 门关闭后不再为每个候选遍历全网未着站，减少后期搜索的无效距离和 JMA2001
  计算；Scratch 的 detection ID、P/S 缓存、五阶段搜索、`1.7` 写回门和生命周期
  没有改变。

同一 `2026-07-18 千葉県東方沖 M4.3` 回放对比：

- 修正前真值水平误差最小为 `7.56 km`（`04:45:37`），基础 `error_level` 最小为
  `189.47`（`04:45:47`）；之后未着惩罚增至 `370`，`04:46:17` 仍因
  `score=291.65 < 175.93 * 1.7` 被写回，最终为
  `35.783333, 141.316667 / 10 km / 21.64 km`；
- 修正后真值水平误差最小为 `8.68 km`（`04:45:32`，深度 `30 km`），基础
  `error_level` 最小为 `222.28`（`04:45:57`）；最终为
  `35.866667, 141.033333 / 10 km / 19.48 km`，基础 `error_level=321.07`、
  `score=239.37`，未着惩罚为 `0`；
- ID 建立后 `<10 s` 的 Scratch 写回规则会无条件接受本轮搜索；因此
  `04:45:30` 曾真实发布 `error_level=4955.73` 的早期结果，之后再逐步下降。这不是
  单轮邻域搜索接受更差候选，而是每个新帧的测站集合改变后重新搜索并写回；
- 深度仍会从早期 `30/40/90 km` 逐步降到 `10 km`。在 JMA 震中固定经纬度下，
  后段同一算法样本的最佳深度为 `20 km`；因此剩余深度偏差仍是经纬度/深度的
  联合局部谷底，不能把目录 `40 km` 直接写入算法。

修正后的剩余后期增长不是旧站数据被改写。`04:45:47` 的 126 个发布曲线站到
`04:47:22` 全部保留，公共站的 `triggerStamp`、P/S 标志和 `observed_s` 变化数
全部为 `0`；后续新增 98 个真实 detection ID 成员，使加权平方残差从 `339.15`
增至 `717.21`。最大单帧增长发生在 `04:47:15`：KA 输入站 `YMT016` 以
`scratch_id4_1_nearest7_existing_id` 加入，输入为 `level=3, ascend=3`，缓存波型为
S，曲线残差 `30.00 s`，单站加权平方残差贡献 `133.46`。因此文章所说的“越接近
实际震源，误差水平越低”适用于同一测站集合中的候选比较；跨帧加入新站后目标
函数已改变，两个原始误差水平不能直接解释为震中距离单调变化。

Scratch JS 的跨帧 `1.7 * 历史最低发布分数` 门已从原始块再次核实：它允许比历史
最低值高、但仍低于 1.7 倍阈值的结果写回。修正后历史最低 `score=185.84`，末帧
`239.37 < 315.93`，所以后期解仍会发布；这是当前按 JS 保留的稳定/写回语义，
不是文章单轮邻域下降遗漏。若要禁止发布误差回升，必须单独改变已确认的 JS 写回
规则，不能把它混作本次文章未着门修复。

验证：`source_estimator_test.dart` 16 项全部通过；新增测试覆盖 `3 s`、
`10 s + 少于30站`、`11 s` 和 `5 s + 30站` 四个门边界；千葉 151 帧回放通过。
修正前后报告分别位于
`.dart_tool/current_capture_replay_analysis_chiba_late_error/report.json` 和
`.dart_tool/current_capture_replay_analysis_chiba_article_inactive_gate/report.json`。

### 2026-07-18 HYP 跨帧写回门多事件对照实验

为判断 Scratch JS 的 `历史最低 score * 1.7` 是否普遍有利，使用完全相同的 KA
输入、文章未着门、P/S 缓存、JMA2001、候选域和五阶段搜索，只替换 10 秒后的
跨帧写回条件。不能从已有报告事后筛选：拒绝一帧会改变下一帧搜索起点和 P/S
缓存路径，因此每个组合均从空 detection ID 状态完整重跑。

实验实现：

- `NiedDartHypSourceEstimator` 构造器增加可重复测试用
  `writebackPolicy` 和 `historicalMinimumMultiplier`；生产默认仍为 Scratch
  `historicalMinimumMultiplier / 1.7`，主程序没有改成实验值；
- 回放测试支持紧凑报告及一次进程内的事件/策略矩阵。每轮先 `resetNied()`，再安装
  全新的策略 estimator；首帧强制断言 diagnostics 中的实际策略和倍率，避免 reset
  把实验静默恢复为默认值；
- 五个真实事件覆盖山梨内陆 M5.6、岩手近海 M4.1、福岛会津深发 M4.6、静冈
  内陆 M3.6、千叶远海 M4.3；目录真值只用于回放后统计，不参与搜索或写回判断。

极端策略结果：

| 策略 | 5 事件最终水平误差均值 | 最优到最终漂移均值 | 接受/拒绝帧 | 结论 |
|---|---:|---:|---:|---|
| 历史最低 `*1.7` | `8.647 km` | `3.511 km` | `218 / 260` | Scratch 基线 |
| 历史最低 `*1.0` | `8.801 km` | `3.665 km` | `90 / 388` | 过严，千叶变差 |
| 不高于当前发布 score | `12.319 km` | `7.585 km` | `132 / 346` | 岩手由 `3.39` 恶化到 `22.99 km` |

“不高于当前分数”失败的原因不是实现错误：它允许从一个高于历史最低的当前分数
开始，沿一串逐步下降的分数持续移动，最终进入错误谷底。岩手在 `14:39:53`
首次与基线分歧，基线按历史门拒绝，而当前分数门接受，最后水平误差增加
`19.60 km`。因此不能用它替代历史最低门。

中间倍率结果：

| 倍率 | 最终水平误差均值 | 漂移均值 | 平均深度绝对误差 | 接受/拒绝帧 |
|---:|---:|---:|---:|---:|
| `1.05` | `8.801 km` | `3.665 km` | `12 km` | `124 / 354` |
| `1.1` | `8.576 km` | `3.440 km` | `12 km` | `171 / 307` |
| `1.2` | `8.576 km` | `3.440 km` | `12 km` | `196 / 282` |
| `1.4` | `8.647 km` | `3.511 km` | `14 km` | `210 / 268` |
| `1.7` | `8.647 km` | `3.511 km` | `14 km` | `218 / 260` |

逐事件比较 `1.2` 与 `1.7`：

- 山梨最终水平误差 `9.74 -> 9.39 km`，最终深度同为 `10 km`；
- 千叶最终水平误差同为 `19.48 km`，深度 `10 -> 20 km`，基础
  `error_level 321.07 -> 259.40`；
- 岩手 `3.39 km / 20 km`、福岛 `3.49 km / 160 km`、静冈
  `7.13 km / 30 km` 完全不变；
- `1.1` 与 `1.2` 在五个事件上的最终位置和深度相同；`1.2` 多保留 25 个中间写回
  帧，因此在当前样本下是比 `1.1` 更保守的折中；
- `1.05` 会把千叶最终水平误差增至 `20.61 km`，过严；`1.4` 已回到 `1.7` 的
  最终结果，无法保留千叶的 20 km 深度。

当前证据支持把 `1.2` 作为后续生产候选：五个事件没有水平退化，山梨略有改善，
千叶深度和算法自身误差改善，总体漂移也下降。但它明确偏离 Scratch JS 的 `1.7`
常数，本轮只保留为可重复实验参数，没有静默修改生产默认值。

报告：

- `.dart_tool/nied_hyp_writeback_policy_matrix/report.md`：`1.7 / 1.0 / 当前分数`；
- `.dart_tool/nied_hyp_writeback_policy_matrix_intermediate/report.md`：
  `1.05 / 1.1 / 1.2 / 1.4`；
- 两轮共 35 个完整事件-策略组合，测试分别用时 `7:11` 和 `8:31`，全部通过。

### 2026-07-18 HYP 深度发布链路与曲线面板刷新

针对“回放时右下角曲线面板一直显示 10 km”，把生产链路拆成算法搜索结果、已发布
`SourceEstimate`、曲线诊断快照和主界面后台解析四层逐项核对。结论不能概括为
“算法深度写死为 10 km”：

- 五事件生产 `1.7` 回放的最终深度分别为山梨 `10 km`、岩手 `20 km`、福岛会津
  `160 km`、静冈 `30 km`、千叶 `10 km`；
- 重新运行福岛会津 15 帧完整诊断，算法逐帧发布
  `20 -> 60 -> 110 -> 130 -> 150 -> 160 km`。13 个估算帧中
  `SourceEstimate.depthKm`、选中曲线面板 `depth_km` 和面板经纬度逐帧完全一致；
- 千叶也不是全程 10 km。其发布深度实际经历
  `10 -> 30 -> 40 -> 50 -> 90 -> ... -> 20 -> 10 km`。最后一轮同一位置和站集下，
  `10 km` 分值为 `239.369`，`20 km` 为 `241.689`，`60 km` 为 `363.126`，所以
  文章/Scratch 邻域下降真实选择 10 km；这属于经纬度与深度联合误差面的局部谷底，
  不是显示层把 JMA 40 km 改成 10 km。

显示层发现的独立风险是刷新签名只包含曲线列表的 `identityHashCode`，没有事件、
深度、坐标、发生时刻或发布序号。为保证主界面一定跟随算法真实发布快照：

- 每个 detection ID 的 worker 增加 `publishedCurveRevision`。只有本轮搜索通过写回门
  并生成新曲线快照时递增；写回被拒绝、曲线冻结时保持不变；时间倒退重置 worker
  时归零；
- diagnostics 发布 `travel_time_curve_revision`。主界面签名改为组合事件 ID、版本、
  `SourceEstimate` 经纬度/深度/发生时刻、选中面板对应字段、误差和样本数；列表对象
  身份只保留为最后一层区分，不再是唯一依据；
- 新增实际后台 `compute` 路径回归测试，在复用同一个原始面板列表对象的情况下依次
  发布 `10 -> 160 -> 30 km`，断言 painter 每次都显示对应深度；现有清空事件、窗口
  缩放、组件移动和 Debug 开关测试继续通过；
- `source_estimator_test.dart` 新增版本冻结断言。算法测试 16 项、曲线生命周期测试
  4 项全部通过，四个相关文件静态分析无问题。

本轮没有修改临时震源 10 km 初值、五阶段搜索、JMA2001、P/S 选择、误差公式、动态
候选域或 `1.7` 写回门。修复的是“算法已发布非 10 km 时主界面必须可靠刷新”的显示
契约；千叶最终为何回到 10 km 仍按上面的真实候选分值解释，不能用 JMA 目录深度
直接覆盖。

复核报告：

- `.dart_tool/current_capture_depth_trace_fukushima/report.json`；
- `.dart_tool/current_capture_replay_analysis_chiba_article_inactive_gate/report.json`。

### 2026-07-18 JMA2001 入参、文章权重与发布面板数值审计

继续针对千叶最终回到 `10 km` 检查联合经纬度/深度谷底，并把算法发布值与右下角
曲线面板逐字段核对。本轮不使用 JMA 目录真值参与运行时搜索或写回。

JMA2001 距离语义：

- KA `TravelTimes.js` 的表格插值横轴是地表震中距；Scratch 六项式为同一张表的
  正向近似时，输入必须是 `sqrt(震中距^2 + 深度^2)` 的震源距；
- 深度 `150 km`、震中距 `20 km` 时，KA 表值为 P `20.327 s`、S `35.797 s`；
  当前震源距入参得到 P `20.299 s`、S `35.745 s`。若误传地表震中距，只得到
  P `2.747 s`、S `4.818 s`；
- 因此生产评分、P/S 曲线和波圈继续使用震源距输入。新增固定 KA 表值测试，防止
  后续因变量命名或面板横轴是震中距而错误修改多项式入参。

文章距离权重核对：

- Scratch 实际公式是
  `max(50, 首检站震中距) / max(50, 当前站震中距)`；旧 Dart 对 50 km 内当前站
  直接返回 `1.0`，当首检站震中距大于 50 km 时会错误降权近站；
- 已改为文章原式，面板点权重调用同一函数，单元测试对每个发布点独立复算；
- 五事件生产矩阵结果未变化：山梨 `9.74 km / 10 km`、岩手
  `3.39 km / 20 km`、福岛会津 `3.49 km / 160 km`、静冈
  `7.13 km / 30 km`、千叶 `19.48 km / 10 km`。这表示该修复在当前五个最终帧
  没有改变最优候选，但仍删除了真实的文章实现偏差。

联合谷底实验与深度剖面：

- 仅回放实验在原五阶段的两个深度阶段增加纬度、经度、深度同时移动的组合邻点；
  KA 输入、文章误差公式、P/S 缓存和 `1.7` 写回门均不变；
- 千叶结果与生产逐项相同：`35.866667, 141.033333 / 10 km`，水平误差
  `19.48 km`，误差水平 `321.070`，分值 `239.369`，因此没有启用该实验；
- 使用当前最终发布快照的 224 个真实有效站、真实触发时刻和发布 P/S 分配，分别
  固定深度并重新优化水平位置。最低分值为：`10 km = 239.369`、
  `20 km = 240.854`、`30 km = 252.317`、`40 km = 275.638`；
- 当前完整报告中 `SourceEstimate` 与选中面板的经纬度、深度、发生时刻、误差、
  分值和站数完全相同。由此可确定，千叶最终浅源不是相邻联合候选漏搜或面板替换，
  而是文章评分在这批 KA 触发时刻/P-S 分配下真实偏好 10 km；20 km 与 10 km
  只差约 `0.62%`，说明该事件的深度约束较弱。
- 相位对照把同一 224 站全部按 P 计算，最优深度仅移动到 `20 km`，并且最低分值
  恶化到约 `1039`；浅源偏好不是 19 个 S 标记单独造成的，不能通过删除 S 点修复；
- 当前 JS 使用的加权发生时刻也做了只读对照：`10 km = 239.32`、
  `20 km = 240.22`、`40 km = 270.59`，仍然选择 10 km。因此文章普通平均与
  JS 加权平均的差异也不能解释 JMA 40 km 与当前结果的差距。

面板契约：

- 算法样本显式携带 `epicentral_distance_km` 与
  `hypocentral_distance_km`；横轴模型固定为 6371 km Haversine 地表震中距，
  JMA2001 走时模型显式记录震源距入参；
- 时间零点固定为当前发布结果中最早的有效评分站，不再被已排除的 KA
  `ascend < 2` 成员提前；该平移不改变绝对发生时刻、残差、误差或分值；
- UI 后台预处理不再自行按 `weight > 0` 重算有效站数，直接使用算法 panel 内的
  `effective_station_count`；距离模型和每个点的震中距/震源距跨 isolate 保留；
- 面板中的位置、深度、绝对发生时刻、`t0`、误差水平、点 RMSE、含未着 RMSE、
  分值、未着数、P/S 数、S 系数、权重和、站数尺度及所有残差线均来自同一个已发布
  worker result；`1.7` 门拒绝新搜索时整张快照冻结，不混入后续站点。

报告与验证：

- `.dart_tool/nied_hyp_article_weight_matrix/report.md`；
- `.dart_tool/nied_hyp_chiba_current_full/report.json`；
- `.dart_tool/nied_hyp_joint_neighborhood_chiba/report.md`；
- JMA2001 4 项测试、震源估算器 16 项测试、面板生命周期 4 项测试均通过。
