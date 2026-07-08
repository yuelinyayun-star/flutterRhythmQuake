# 震源估算数据与算法研究

> 状态：设计基线  
> 更新日期：2026-06-20  
> 适用范围：NIED 强震监测数据的实时震中估算与局地强震动预测

## 1. 结论

现有数据最适合实现两条相互独立的能力：

1. **震中估算**：使用“实时震度衰减反演 + 阈值到达时间 + 未触发台站”的混合概率模型。
2. **强震动预测**：使用 PLUM 类局地传播算法，不依赖震源、震级和深度。

当前数据不支持直接照搬标准 P/S 到时定位、JMA IPF/IPFx 或 FinDer：

- 没有原始三分量连续波形；
- 没有可靠的 P 波、S 波拾取；
- 当前所谓 PGA、PGV、PGD 由同一个实时震度颜色位置换算而来，并非独立观测；
- 每站只有最新值和首次状态时间，没有完整的短时序列。

因此，第一目标是稳定估计**震中区域**，而不是宣称能够反演精确震源深度。输出应包含位置、不确定度和数据质量，不应只返回一个缺乏统计含义的 `confidence`。

## 2. 当前运行链路

事件检测与震源估算的职责边界、文献依据和独立实施顺序见：

- [`docs/event_detection_research.md`](event_detection_research.md)

```text
NIED GIF / Yahoo 数据
  -> NiedStation
  -> ShakeDetectionService
  -> StationEventTracker
  -> SeismicSourceTracker
  -> NiedGifHybridSourceEstimator
  -> SourceEstimate
  -> 地图与调试面板
```

主要实现位置：

- 数据获取与一秒轮询：[`lib/services/sources/nied_monitor.dart`](../lib/services/sources/nied_monitor.dart)
- GIF 像素采样：[`lib/services/sources/lmoni_image_service.dart`](../lib/services/sources/lmoni_image_service.dart)
- 颜色值解码：[`lib/services/sources/nied_gif_value_decoder.dart`](../lib/services/sources/nied_gif_value_decoder.dart)
- 台站事件记录：[`lib/core/source_estimation/seismic_source_tracker.dart`](../lib/core/source_estimation/seismic_source_tracker.dart)
- 当前估算器：[`lib/core/source_estimation/source_estimator.dart`](../lib/core/source_estimation/source_estimator.dart)
- 回放测试：[`test/nied_nara_replay_estimation_test.dart`](../test/nied_nara_replay_estimation_test.dart)

旧版 [`lib/core/hypocenter_estimator.dart`](../lib/core/hypocenter_estimator.dart) 使用固定扫描点和加权距离，仅保留作对照基线，不作为后续算法基础。

## 3. 数据审计

### 3.1 GIF 数据

当前抓取图层为：

- `jma_s`：地表实时震度图；
- `jma_b`：井下实时震度图。

防災科研当前页面还公开以下独立图层：

- `acmap_s/acmap_b`：最大加速度；
- `vcmap_s/vcmap_b`：最大速度；
- `dcmap_s/dcmap_b`：最大变位；
- `rsp0125`、`rsp0250`、`rsp0500`、`rsp1000`、`rsp2000`、`rsp4000`
  的地表/地中速度响应。

官方页面脚本使用如下路径：

```text
/data/map_img/RealTimeImg/<layer>/<YYYYMMDD>/<timestamp>.<layer>.gif
```

每帧具有统一的数据时间，应用按台站像素位置读取颜色，并解码为连续震度。正常情况下时间分辨率约为 1 秒。

可用字段：

| 字段 | 可用性 | 说明 |
|---|---:|---|
| 台站坐标 | 可用 | 来自本地 NIED 台站库 |
| 网络类型 | 可用 | K-NET 或 KiK-net |
| 传感器角色 | 部分可用 | K-NET 地表，KiK-net 当前优先井下图层 |
| 连续震度 | 可用 | 从 `jma_s/jma_b` 颜色位置反解 |
| 数据时间 | 可用 | 每帧统一时间戳 |
| 首次上升/触发时间 | 派生 | 首次在某帧跨过应用阈值的时间 |
| PGA/PGV/PGD | 条件可用 | 只能分别来自 `acmap/vcmap/dcmap`，不能从 `jma` 换算 |
| 原始波形 | 不可用 | 无三分量加速度时序 |
| P/S 拾取 | 不可用 | 触发时间不是震相到时 |

### 3.2 PGA、PGV、PGD 语义问题

旧解码器曾从同一个 `jma` 图层 `colorPosition` 同时计算：

```text
shindo = 10p - 3
PGA    = 10^(5p - 2)
PGV    = 10^(5p - 3)
PGD    = 10^(5p - 4)
```

这些公式是不同图层各自从色标位置换算数值的公式，不能对同一张 `jma` 图重复使用。
2026-06-21 已修正为“一图层一物理量”：

- `jma` 只输出实时震度；
- `acmap` 只输出 PGA；
- `vcmap` 只输出 PGV；
- `dcmap` 只输出 PGD；
- 震源 tracker 只接受带独立来源标记的物理量；
- `nied_gif_hybrid_v1` 已移除 PGA/PGV/PGD 重复排序项。

`ObservationProvenance` 保存来源、图层 ID、物理量类型和是否为独立物理观测。
`SensorSelection` 显式约束地表、井下、海底等传感器角色。采集器已支持通过
`-Layers` 指定独立图层，但生产轮询仍默认只抓 `jma_s/jma_b`，后续必须实现同一
时间戳多图层同步后才能把 PGA/PGV/PGD 接入生产估算。

接口探测：

```text
time:    2026-06-21 16:33:18 JST
package: tmp/captures/physical_layer_probe_v2_20260621_163318
layers:  jma/acmap/vcmap/dcmap x surface/borehole
result:  8 downloaded / 0 failed
decoder: nied_gif_layered_v2
```

台站级对齐报告：
[`docs/baselines/nied_layer_alignment_probe_20260621.generated.md`](baselines/nied_layer_alignment_probe_20260621.generated.md)

该静默时刻中，1260 个台站四层均可解码；`jma` 与 `acmap/vcmap/dcmap` 的色标
位置相关系数分别为 0.577、0.095、0.003。这不是地震事件效果指标，但足以否定
“同一个 `jma` 色标位置可以同时代表 PGA/PGV/PGD”的旧假设。

2026-06-21 能登 M2.7 事件已捕获首个完整多图层窗口。151 个时间戳共
246130 条 station-second，其中 190041 条四层齐全；事件窗口中 `jma` 与
`acmap/vcmap/dcmap` 的色标位置相关系数分别为 0.476、0.184、0.075。
详细记录：

- [`docs/baselines/noto_m27_20260621_reference.md`](baselines/noto_m27_20260621_reference.md)
- [`docs/baselines/noto_m27_20260621_multilayer_alignment.generated.md`](baselines/noto_m27_20260621_multilayer_alignment.generated.md)

2026-06-21 宫城县东南冲/福岛县冲 M3.2 参考事件是第二个完整多图层窗口：151 个
时间戳、1208/1208 张 GIF、190062 条四层齐全 station-second。事件窗口中
`jma` 与 `acmap/vcmap/dcmap` 的色标位置相关系数分别为 0.447、0.202、0.112。
该事件已补入用户提供的 Hi-net 震源标签：2026-06-21 22:41:12 UTC+8、
宫城县东南冲、37.616N/142.279E、M3.2、深度 29.8 km。EQuake 第 6 报
只作为触发、质量和 UI 参考；该事件仍需 split 复核后才能进入冻结精度指标。

- [`docs/baselines/fukushima_offshore_m32_20260621_reference.md`](baselines/fukushima_offshore_m32_20260621_reference.md)
- [`docs/baselines/fukushima_offshore_m32_20260621_multilayer_alignment.generated.md`](baselines/fukushima_offshore_m32_20260621_multilayer_alignment.generated.md)

2026-06-22 岩手县东北冲/岩手县冲 M3.4 参考事件是第三个完整多图层窗口：151 个
时间戳、1208/1208 张 GIF、190067 条四层齐全 station-second。事件窗口中
`jma` 与 `acmap/vcmap/dcmap` 的色标位置相关系数分别为 0.679、0.337、-0.008。
该事件已补入用户提供的 Hi-net 震源标签：2026-06-22 08:28:23 UTC+8、
岩手县东北冲、40.392N/142.341E、M3.4、深度 50.2 km。EQuake 第 10 报
只作为触发、质量和 UI 参考；该事件仍需 split 复核后才能进入冻结精度指标。

- [`docs/baselines/iwate_offshore_m30_20260622_reference.md`](baselines/iwate_offshore_m30_20260622_reference.md)
- [`docs/baselines/iwate_offshore_m30_20260622_multilayer_alignment.generated.md`](baselines/iwate_offshore_m30_20260622_multilayer_alignment.generated.md)

2026-06-22 和歌山县南部 M2.5 Hi-net 标记事件是第四个完整多图层窗口：151 个
时间戳、1208/1208 张 GIF、189984 条四层齐全 station-second。事件窗口中
`jma` 与 `acmap/vcmap/dcmap` 的色标位置相关系数分别为 0.681、0.348、-0.009。
该事件已补入用户提供的 Hi-net 震源标签：2026-06-22 08:51:17 UTC+8、
和歌山县南部、33.580N/135.791E、M2.5、深度 28.1 km。该事件仍需 split
复核后才能进入冻结精度指标。

- [`docs/baselines/wakayama_south_m25_20260622_reference.md`](baselines/wakayama_south_m25_20260622_reference.md)
- [`docs/baselines/wakayama_south_m25_20260622_multilayer_alignment.generated.md`](baselines/wakayama_south_m25_20260622_multilayer_alignment.generated.md)

参考：

- 防災科研官方说明：<https://www.kyoshin.bosai.go.jp/ja/about_kmoni/>
- 強震モニタ当前脚本：<http://www.kmoni.bosai.go.jp/kyoshin_monitor/static/eqmonitor/memberview/js/EqMonitorCfg.js>
- 色标位置换算线索：<https://qiita.com/NoneType1/items/a4d2cf932e20b56ca444>

### 3.3 Yahoo 数据

Yahoo 路径提供离散检测等级和台站状态，可用于事件检测和较粗的空间估计，但没有 GIF 连续震度。当前默认 `NiedGifHybridSourceEstimator` 只接受 `nied_input_kind == gif`，Yahoo 数据不会进入默认震源估算。

### 3.4 时间语义

`firstRiseAt` 和 `firstTriggerAt` 表示应用第一次在某帧观察到状态变化。它们具有以下误差：

- 约 1 秒的时间量化；
- 网络抓取和缺帧造成的延迟；
- 阈值受噪声、场地、震级和距离影响；
- 它们通常晚于真实 P 波初至，且不同台站偏差不一致。

所以不能直接把它们当作精确 P 波到时。合理做法是按区间观测处理，例如一次首次触发发生在第 `t` 秒帧，则真实跨阈时间属于 `(t-1, t]`，并在模型中使用稳健误差。

### 3.5 空间与场地差异

NIED 官方说明 K-NET 主要为地表强震观测，KiK-net 同时具有地表和井底观测。地表与井下振幅受不同场地响应影响，不能在同一衰减关系中无修正混用。模型至少需要：

- `sensorRole` 分组偏置；
- K-NET/KiK-net 分组尺度；
- 有足够历史事件后学习台站静态修正项；
- 对异常台站使用稳健损失和质量降权。

## 4. 当前算法评估

默认算法 `nied_gif_hybrid_v1` 执行三级经纬度网格搜索：

```text
粗搜 0.20 deg -> 细搜 0.05 deg -> 精搜 0.02 deg
```

当前总分由以下部分组成：

```text
1.15 * 触发时间残差平方和
+ 震度距离排序惩罚
+ PGA/PGV/PGD 距离排序惩罚
+ 最强台站距离惩罚
+ 偏离震度加权中心的惩罚
```

主要问题：

1. 固定 `3.8 km/s`，没有针对阈值到达时间标定有效传播速度。
2. 时间平方误差、震度排序和公里惩罚直接相加，量纲及权重缺少统计依据。
3. PGA、PGV、PGD 重复使用同一颜色证据。
4. 未使用尚未触发台站提供的负证据。
5. 已结束台站从 `isActiveLike` 集合退出，可能导致估算跳变。
6. 强度随距离单调下降的假设没有处理场地效应。
7. 默认不估深度；已有深度网格版本也无法从当前数据中稳定识别深度。
8. `confidence` 是经验公式，未经过覆盖率校准，不能解释为概率。

当前算法适合作为回放基准，不应继续通过手工增加权重来演化。

## 5. 文献方法与适用性

### 5.1 烈度/震度反演

Bakun 与 Wentworth 证明可以仅利用烈度点，通过网格搜索联合约束震中区域和震级，并使用场地修正、距离权重与残差等值线表达位置范围。其经验关系针对加州 MMI，不能直接套用于日本 JMA 震度，但方法结构适合当前数据。

对本项目的启示：

- 同时优化位置和等效规模，避免把规模差异误判成距离差异；
- 使用残差面或后验分布，而不是只取一个最低分点；
- 使用经验台站修正；
- 参数必须由日本历史事件回放重新标定。

### 5.2 P 波到时与未触发台站

Horiuchi 等提出的日本实时定位系统使用少量台站 P 波到时，并把截至当前仍没有 P 波到达的台站作为约束。这能在观测站很少时排除大量错误震源。

本项目没有 P 波拾取，因此只能迁移“未触发台站是删失观测”这一思想，不能宣称复现原算法。

### 5.3 IPF/IPFx

IPFx 分为两级：单台站从连续波形提取触发和振幅信息，网络级再以贝叶斯推断估计位置和规模。当前 GIF 数据缺少第一级所需连续波形，但可以借鉴：

- 粒子或候选集表示不确定度；
- 新帧到来后递推更新；
- 同时处理多个事件假设；
- 以概率形式融合异质证据。

### 5.4 FinDer

FinDer 使用密集台网的 PGA 空间分布匹配有限断层模板，适合快速识别大震破裂范围。当前 `jma_s/jma_b` 数据没有独立 PGA，因此不能使用。若未来获取真实 PGA 图层或原始加速度数据，可作为大震专用算法，而不是小震通用震中定位器。

### 5.5 PLUM

PLUM 根据附近已经观测到的地面运动，直接推断目标区域即将出现的强震动，不要求先得到可靠震源和震级。它特别适合密集台网和复杂、多重或超大震源场景。

PLUM 不返回传统震源参数，因此应作为独立的“强震动预测层”，不能拿来替代地图上的震中估算。

## 6. 推荐模型

### 6.1 观测

对事件中的台站 `i`、帧 `t`，保留：

```text
I(i,t)       连续 JMA 震度
q(i,t)       数据质量与缺帧状态
T_rise(i)    首次持续上升时间区间
T_trigger(i) 首次触发时间区间
C(i,t)       截止当前是否仍未触发
role(i)      地表/井下
```

必须保留至少最近 60 秒的逐站环形时序，而不是只存最新值。

### 6.2 状态参数

```text
theta = (latitude, longitude, originTime, sourceScale, depthClass)
```

其中：

- `sourceScale` 是供衰减模型使用的等效规模，不应在标定完成前直接标为 JMA 震级；
- `depthClass` 只使用浅、中、深等离散类别并边缘化；
- 第一版产品只展示震中和不确定度，不展示精确深度。

### 6.3 震度模型

初始模型采用可标定的经验衰减形式：

```text
I_hat(i) = a + b*S - c*log10(R_i + r0) - d*R_i
           + stationBias(i) + roleBias(role_i)

R_i = sqrt(epicentralDistance_i^2 + depthClass^2)
```

使用 Huber 或 Student-t 残差，避免少数场地异常点支配结果：

```text
L_intensity = sum_i qualityWeight_i * robust(I_obs(i) - I_hat(i))
```

早期阶段优先使用当前值、短窗峰值和上升斜率中的可解释特征；最终采用哪一种由回放验证决定。

### 6.4 到达时间模型

阈值到达时间不是震相到时，先使用经验有效速度：

```text
T_hat(i) = originTime + travelTime(distance_i, depthClass, v_effective)
```

对一秒区间观测计算区间外距离，而不是点误差：

```text
L_arrival(i) = distance(T_hat(i), observedInterval_i)^2
```

`v_effective` 应按事件规模、阈值和传感器角色用回放数据标定。若标定显示时间信息没有稳定增益，则降低权重或只用于事件早期排序。

### 6.5 未触发台站

若候选震源预测某个健康、邻近台站早应跨阈，但当前仍未触发，则加入删失惩罚：

```text
L_censored = sum_j penalty(predictedArrival_j << currentTime
                           and station_j not triggered)
```

只使用数据新鲜且质量正常的台站，避免把离线站误认为负证据。

### 6.6 联合目标

```text
L(theta) =
    w_I * L_intensity
  + w_T * L_arrival
  + w_C * L_censored
  + w_Q * L_quality
  + regularization
```

第一版可继续使用粗到细网格，但必须保存候选分数面。之后可替换成粒子滤波进行逐帧递推；接口层不应依赖具体求解器。

### 6.7 输出

建议输出结构：

```text
latitude / longitude
originTimeRange
equivalentSourceScale
depthClassProbabilities
horizontalUncertaintyKmP50
horizontalUncertaintyKmP90
supportingStationCount
negativeEvidenceStationCount
dataQualityScore
method / modelVersion
diagnostics
```

地图展示 P50/P90 概率区域。只有经过独立事件集校准后，才能把某个数值称为置信概率。

## 7. 数据与验证要求

用于完整实时指标的 GIF 回放事件至少需要：

- 事件前 30 秒至事件后 120 秒的完整 GIF 帧；
- 每帧时间、接收时间、缺帧记录；
- 台站实际选用的表层/井下来源；
- JMA 最终震中、深度、震级、发震时间作为标签；
- 数据版本、台站库版本和解码器版本。

震前或震后帧不完整的事件仍可用于静态震中误差、最终震度场或波形域评测，
但必须记录可用时间范围，且不能进入首次估算延迟、真实触发延迟和完整事件
召回率等指标。

数据集必须按**事件**划分训练、验证、测试集，禁止把同一事件的不同帧分到不同集合。

核心指标：

| 指标 | 含义 |
|---|---|
| 首次估算延迟 | 发震后多久给出第一个结果 |
| 震中误差中位数 | 常规精度 |
| 震中误差 P90 | 尾部风险 |
| 5/10/20 秒误差 | 随数据积累的收敛速度 |
| 帧间跳动距离 | 地图稳定性 |
| P50/P90 覆盖率 | 不确定度是否校准 |
| 空事件误报率 | 非地震触发时是否输出震中 |
| 计算耗时 P95 | 是否满足每秒更新 |

结果必须按内陆/海域、浅/深、小/大震、台网内部/边缘分别报告，不能只给总体平均值。

### 7.1 真实 GIF 不足时的预训练

真实 GIF 上游只保留最近约 60/120 分钟，无法事后构建大规模历史时序集。
因此采用分域预训练：

1. JMA 最终逐站震度用于学习静态震度衰减、台站偏差和深度类别先验；
2. K-NET/KiK-net 正式波形用于逐秒 PGA/PGV、实时震度近似、触发特征和
   可选 P/S 拾取；
3. 理论走时逐步揭示只用于 `synthetic_reveal` 数据增强；
4. 真实 GIF 用于最终校准触发、早期定位、缺帧行为和递推稳定性。

如果长期没有同一事件同时具备本地 GIF 和正式波形，不能停在等待状态。可从
K-NET/KiK-net 正式波形构建 `waveform_projected_gif` 域：把每秒
`jmaIntensityApprox` 映射为 GIF 等价震度和颜色位置，用于训练秒级台站震度
场输入、触发统计和缺站鲁棒性。该域必须明确标记为
`projected_from_official_waveform`，不能用于真实检测延迟、真实首次估算延迟、
缺帧行为或最终上线验收。真实 GIF/波形同域事件之后只作为偏差、滞后和饱和
范围校准，而不是当前 P1.5 的阻塞条件。

不同域不得静默混合。JMA 最终峰值震度不是一秒时序，K-NET/KiK-net 已发布
台站也不代表全网未触发状态。详细数据规划和实施门槛见：

- [`docs/source_estimation_pretraining_plan.md`](source_estimation_pretraining_plan.md)

### 7.2 能登 M2.7 多图层消融

2026-06-21 能登 M2.7 完整窗口表明，独立物理图层“可解码”不等于“直接加入
排序项就会提高定位”。震源专用触发在震后 6 秒形成 5 台石川空间簇；限定定位器
只使用该事件成员后，JMA-only 首报误差为 7.46 km。固定权重加入 PGA/PGV/PGD
排序项后首报误差增至 40.63 km，且出现 37.57 km 的 P90 帧间跳动。

因此当前结论是：

- 保留 `acmap/vcmap/dcmap` 的独立来源和单位语义；
- 禁止把单帧绝对物理值直接并入生产震中评分；
- 后续先评估相对震前基线、事件峰值、到峰时间和图层间时差；
- 至少在多个事件的 validation 集上稳定改善后，才允许配置生产权重。

## 8. 明确不做的事情

在获得新数据前，以下内容不进入近期实现：

- 从实时震度 GIF 宣称精确反演 P/S 到时；
- 输出连续、精确的震源深度；
- 把派生 PGA/PGV/PGD 作为独立证据；
- 直接套用加州 MMI 或其他地区的衰减参数；
- 在没有事件级独立测试集时训练并上线神经网络；
- 继续通过个别案例手调当前评分权重。

## 9. 参考资料

1. NIED, K-NET and KiK-net overview and data information. <https://www.kyoshin.bosai.go.jp/ja/>
2. Bakun, W. H. and Wentworth, C. M. (1997). Estimating earthquake location and magnitude from seismic intensity data. <https://doi.org/10.1785/bssa0870061502>
3. Horiuchi, S. et al. (2007). Development of an automatic hypocenter location system for the earthquake early warning in Japan. <https://doi.org/10.3124/segj.60.399>
4. Kodera, Y. et al. (2018). The Propagation of Local Undamped Motion (PLUM) Method. <https://doi.org/10.1785/0120170085>
5. Saunders, J. K. et al. (2022). Real-time earthquake detection and alerting behavior of PLUM in the United States. <https://pubs.usgs.gov/publication/70237103>
6. Kodera, Y. et al. (2021). The Extended Integrated Particle Filter Method (IPFx). <https://doi.org/10.1785/0120210008>
7. Böse, M. et al. (2012). Real-time Finite Fault Rupture Detector (FinDer) for large earthquakes. <https://doi.org/10.1111/j.1365-246X.2012.05657.x>
8. USGS ShakeMap overview. <https://earthquake.usgs.gov/data/shakemap/>
9. Japan Meteorological Agency, Earthquake Early Warning System. <https://www.jma.go.jp/jma/en/Activities/eew.html>

## 10. 关联规划

具体实施顺序、阶段产物和验收门槛见：

- [`docs/source_estimation_roadmap.md`](source_estimation_roadmap.md)
## Iwate East Offshore M3.0 Replay Note

The `2026-06-22 10:26:50 UTC+8` Hi-net preliminary reference has a complete
151-second `jma/acmap/vcmap/dcmap` surface/borehole replay window. Independent
source triggering confirms at +18 s and reaches 14 connected evidence stations
within 100 km. After the P5 late-drift stability gate, the current hybrid
estimator has 40 km median and 51 km P90 error, with 16.3 km P90 frame-to-frame
jump. This is evidence that offshore trigger recall and offshore hypocenter
stability must still be evaluated separately: stability can suppress late drift,
but it is not enough to solve all offshore geometry failures.

- [`docs/baselines/iwate_east_offshore_m30_20260622_reference.md`](baselines/iwate_east_offshore_m30_20260622_reference.md)
## Fukushima Offshore M2.2 False-Association Countercase

The complete `2026-06-22 14:36:56 UTC+8` replay exposed a 145-161 km
chain that previously confirmed at +50 s. The source trigger now requires a
stable five-station compact core within 120 km for two consecutive frames. Once
this candidate fails coherence, it cannot recover by dropping edge stations;
it times out at +57 s and produces no source estimate.

- [`docs/baselines/fukushima_offshore_m22_20260622_reference.md`](baselines/fukushima_offshore_m22_20260622_reference.md)
## Kushiro Offshore M3.0 Positive Offshore Counterpart

The JMA-verified `2026-06-22 15:38:12 UTC+8` event confirms at +11 s with
eight connected stations inside 50 km and maximum decoded shindo 1, matching
JMA. Weighted centroid median/P90 error is 16.5/22.9 km, while the hybrid
estimator remains 28/118.2 km after the P5 gate. Together with the Fukushima
M2.2 false-association case, this gives a concrete positive/negative pair for
designing locality rejection and late-drift stability gates.

- [`docs/baselines/kushiro_offshore_m30_20260622_reference.md`](baselines/kushiro_offshore_m30_20260622_reference.md)
## P5 Late-Drift Stability Gate

The P5 stability gate is now implemented for the NIED source-estimation path.
It accepts estimates during warmup, then holds the previous estimate when a new
candidate jumps too far from the previous accepted estimate or the warmup anchor.
Held estimates do not increment `estimate_revision`, and the rejected candidate
is recorded in metadata for diagnostics.

The gate fixes the largest late drift in the current Iwate/Wakayama references
and keeps the Fukushima M2.2 false-association countercase rejected. It does not
fix the Fukushima/Miyagi offshore M3.2 absolute location error, so the next
algorithm step is offshore geometry scoring and uncertainty, not more stability
threshold tuning.

- [`docs/source_estimation_p5_stability_report.md`](source_estimation_p5_stability_report.md)

## 2026-06-27 Surface-Only Default Shindo Input

The default real-time source-estimation shindo input is changed to the NIED
surface image layer `jma_s` for every scan-mapped station.

This is a semantics decision, not an accuracy claim:

- K-NET is surface-only in the current GIF station model.
- KiK-net has both surface and borehole sensors, so the station network name
  cannot be used as a GIF layer selector.
- The default source-estimation shindo field must be one coherent surface
  field before attenuation, rank residual, and trigger-member diagnostics are
  calibrated.
- `jma_b` remains available only as explicit borehole provenance for capture,
  diagnostic reports, and future named experiments.

Implementation rule:

```text
default gifDisplayPrimaryLayer = jma_s
default source-estimation shindo input = jma_s
default map station display = jma_s
jma_b = auxiliary borehole layer, not default scoring evidence
```

The existing surface-only replay comparison remains useful as a regression
baseline, but it does not block the semantics correction. Any offshore
regression after the switch must be handled by source-trigger membership,
geometry priors, uncertainty gates, or attenuation calibration, not by silently
mixing borehole and surface shindo values.
