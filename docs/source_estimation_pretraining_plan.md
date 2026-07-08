# 震源估算预训练数据规划

> 状态：规划完成，待实施  
> 更新时间：2026-06-20  
> 目标：在真实 GIF 事件数量不足时，先用历史震度与正式波形学习可迁移参数，
> 后续再用真实 GIF 回放精调实时行为。

## 1. 原则

预训练数据只学习它真实包含的信息，不伪造数据语义：

- JMA 最终逐站震度只用于静态震度场和台站偏差；
- K-NET/KiK-net 波形用于逐秒振幅、实时震度近似、触发特征和相位拾取；
- 理论走时逐步揭示属于 `synthetic_reveal`，不能当作真实触发时间；
- 真实 GIF 才用于最终校准事件触发、早期定位、报次更新和 UI 稳定性；
- 所有数据按事件划分 train/validation/test，禁止同一事件跨集合。

预训练目标不是训练一个直接上线的黑盒模型，而是为可解释震度反演提供：

```text
衰减关系参数
台站静态偏差
地表/井下角色偏差
深度类别先验
稳健残差尺度
逐秒触发特征初值
```

## 2. 数据源

### 2.1 JMA 年度逐站震度

官方入口：

- <https://www.data.jma.go.jp/eqev/data/bulletin/shindo.html>
- <https://www.data.jma.go.jp/eqdb/data/shindo/>

第一阶段使用 1997-2022 年数据。1997 年后地方公共团体和 NIED 震度站逐步
并入，台网条件更接近现代日本震度观测。

可用字段：

```text
event origin time
hypocenter latitude / longitude / depth
magnitude
station code / station location
final observed JMA intensity
```

适合训练：

- 震度随震源距离、深度类别和等效规模的衰减；
- 台站长期偏差与区域偏差；
- 部分台站缺失情况下的静态震中反演；
- P50/P90 位置不确定度的初始尺度。

不适合训练：

- 真实触发时间和首次上升时间；
- 事件检测延迟；
- P/S/O 分类；
- 一秒报次更新过程。

### 2.2 K-NET/KiK-net 正式波形

官方入口：

- <https://www.kyoshin.bosai.go.jp/en/eqdownload/>
- <https://www.kyoshin.bosai.go.jp/en/about_pubdata/>

从三分量加速度波形保留原始物理量，并生成：

```text
station / timestamp
sensorRole = knet_surface | kiknet_surface | kiknet_borehole
vectorAcceleration
oneSecondPga
oneSecondPgv
realtimeShindoApprox
triggerFeatures
optionalPPick / optionalSPick
```

额外生成 `gifEquivalentShindo` 仅用于与现有 GIF 解码域对齐：

```text
colorPosition = clamp((realtimeShindoApprox + 3) / 10, 0, 1)
```

真实 PGA/PGV 和原始波形必须保留，禁止只保存颜色位置。

局限：

- 正式数据只包含触发并发布的台站，不代表全网未触发状态；
- 强震事件偏多，小震覆盖不足；
- K-NET 地表、KiK-net 地表和井下不能无偏置混训；
- NIED 不提供 P/S 到时，拾取结果必须注明算法和质量。

### 2.3 JMA 强震波形

官方入口：

- <https://www.data.jma.go.jp/eqev/data/kyoshin/jishin/index.html>

主要作为独立验证域，避免训练和验证全部来自 NIED。使用和再分发必须遵守
JMA 页面列出的来源标注及第三方提供限制。

### 2.4 真实 GIF 回放

真实 GIF 仍是最终目标域：

```text
jma_s / jma_b
1 second frame interval
full network visible state
actual decoder and pixel mapping
actual missing-frame and transport behavior
```

上游只保留最近约 60/120 分钟，因此必须通过常驻滚动缓存持续积累。

## 3. 数据分层

统一把样本标记为以下域，训练时禁止静默混合：

| domain | 时间语义 | 主要用途 |
|---|---|---|
| `jma_final_intensity` | 事件最终峰值 | 静态衰减与台站偏差预训练 |
| `knet_waveform` | 原始高频波形 | 逐秒特征、触发和 P/S 拾取预训练 |
| `waveform_projected_gif` | 正式波形投影为 GIF 等价秒级观测 | 在真实 GIF 不足时训练 GIF 侧输入接口 |
| `jma_waveform` | 原始高频波形 | 独立波形验证 |
| `synthetic_reveal` | 理论走时生成 | 静态模型缺站鲁棒性训练 |
| `nied_gif_replay` | 真实一秒 GIF | 最终精调与实时评测 |

每条观测至少保存：

```text
source
sourceUrl
licenseOrTerms
eventId
stationId
sensorRole
observedAt semantics
value type / unit
processingVersion
qualityFlags
```

## 4. 训练阶段

### A：静态震度反演预训练

输入 JMA 最终逐站震度，训练 P3 所需的可解释衰减模型。

数据增强仅允许：

- 随机隐藏 50%-95% 已观测台站；
- 按震中距离截断可见台站；
- 注入可控比例的缺站和异常站；
- 使用理论 P/S 走时逐步揭示台站，但标记为 `synthetic_reveal`。

输出：

```text
attenuation coefficients
stationBias
regionBias
roleBias initial values
robust residual scale
depthClass prior
```

### B：波形域预训练

输入 K-NET/KiK-net 波形：

- 重建每秒实时震度近似；
- 计算每秒 PGA/PGV 和上升斜率；
- 训练单站触发器初值；
- 评估 P/S 自动拾取；
- 学习 GIF 等价震度与真实波形特征之间的映射误差。

### C：波形投影 GIF 预训练

如果长时间没有“正式波形 + 本地 GIF”的同一事件，不阻塞训练。先从
`knet_waveform` 特征包生成 `waveform_projected_gif`：

```text
gifEquivalentShindo = jmaIntensityApprox
colorPosition = clamp((gifEquivalentShindo + 3) / 10, 0, 1)
stationSecondState = projected_from_official_waveform
```

用途：

- 预训练震源估算输入管线，使模型先适应“秒级台站震度场”；
- 预训练单站触发、事件累计触发统计和 P/S/O 分类初值；
- 对比 ASCII/CSV、K-NET 地表、KiK-net 地表/井下的系统偏差；
- 生成受控缺站、延迟和量化样本，验证模型对 GIF 量化输入的鲁棒性。

限制：

- 该域不是真实强震モニタ GIF；
- 不包含全网未触发台站、真实缺帧、网络传输延迟、像素解码误差；
- 不进入真实检测延迟、真实首次估算延迟或最终上线验收；
- 训练和报告中必须保留 `domain=waveform_projected_gif` 与质量标志
  `projected_from_official_waveform`。

### D：GIF 域对齐

对同时存在正式波形和本地 GIF 的事件：

- 按台站和秒对齐；
- 比较 `gifDecodedShindo` 与 `realtimeShindoApprox`；
- 标定系统偏差、时间滞后和饱和范围；
- 不强制两者数值相等。

该阶段改为**校准/验证项**，不再阻塞 P1.5 当前推进。真实同域事件出现后，
用于修正 `waveform_projected_gif` 与 `nied_gif_replay` 的偏差、滞后和饱和
范围。

采集顺序约束：

- 无论事件参考来自 JMA、Hi-net、EQSC、EQuake 还是 P2P，只要仍处于
  KMoni 公共回放窗口内，必须先抓本地 `jma_s/jma_b` GIF，再补事件元数据；
- 超出公开回放窗口后，允许仅保留文本参考、正式波形或外部真值标签，但必须
  明确标记“未关联本地 GIF capture”；
- 这条约束同时适用于后续真实 GIF 精调样本和 source/reference 诊断样本。

### E：真实 GIF 精调

真实 GIF 数量足够后，只在 train/validation 事件上精调：

- 独立事件触发门槛；
- 早期 5/10/20 秒定位；
- 未触发台站约束；
- 递推稳定性；
- 质量等级和不确定度覆盖率。

测试集保持冻结，不参与超参数选择。

## 5. 第一批数据

第一批目标不是追求最大规模，而是验证全链路：

### JMA 静态震度

- 下载 2020、2021、2022 三个年度包；
- 解析观测点代码和最终震度；
- 与同年份震源目录关联；
- 筛选至少 200 个有效事件；
- 按事件划分 70%/15%/15%。

### K-NET/KiK-net 波形

优先选择 6-10 个类型差异明显的事件：

- 2016 熊本：内陆浅源；
- 2018 北海道胆振：内陆较深；
- 2021 福岛县冲：海域；
- 2022 福岛县冲：海域强震；
- 2024 能登：复杂破裂；
- 2024 日向滩：板块边界。

每类事件先下载少量台站，验证解析和时间对齐，再扩大范围。

## 6. 验收门槛

### 数据

- JMA 年度包解析无未解释字段错位；
- 事件和台站代码关联率可报告；
- 波形单位、采样率、地表/井下角色明确；
- 每个派生字段都有算法版本和来源；
- 任何 synthetic 数据都不会进入真实时间指标。

### 模型

- 静态模型在事件级验证集上优于加权质心；
- 随机隐藏 80% 台站后误差退化可量化；
- 海域、深源、内陆分别报告结果；
- 波形重建震度与正式计测震度的偏差分布可报告；
- GIF 精调前后均保留冻结基线。

## 7. 实施顺序

1. [x] 实现 JMA 年度震度数据与观测点表解析器；
2. [x] 建立静态震度事件包和事件级 split；
3. [x] 实现台站遮蔽与 `synthetic_reveal` 生成器；
4. [x] 训练并评测 P3 静态衰减基线；
5. [x] 实现 K-NET/KiK-net ASCII/CSV 波形解析器；
6. [x] 生成每秒 PGA、PGV、实时震度近似和触发特征 v1；
7. [x] 建立 K-NET/KiK-net 下载清单与 GIF/波形域对齐工具；
8. [x] 填入第一批真实 K-NET/KiK-net 事件候选并生成下载 manifest；
9. [x] 下载正式波形，生成特征包，并建立波形域训练索引；
10. [x] 构建 `waveform_projected_gif` 投影数据集；
11. [x] 建立事件级留一训练/评估基线；
12. [x] 用统一时序缓冲实现历史峰值/到时约束的时空基线；
13. [ ] 真实同域事件出现后生成 GIF/波形对齐报告；
14. [ ] 持续采集真实 GIF，达到门槛后进入最终精调。

当前立即实施项：持续采集真实事件的 `jma/acmap/vcmap/dcmap` 同步窗口，并在
冻结事件级 split 上比较“仅震度”和“震度 + 独立物理图层”。多图层同步、像素不可
解码质量标志、`ObservationProvenance` 与 `SensorSelection` 已完成；在真实事件
验收前，PGA/PGV/PGD 只记录，不进入生产震源评分。真实 GIF/波形同域事件可能
需要长期等待，因此不再作为当前阻塞项；它只作为后续校准/验证。仍需复核 2022 福岛、
2024 日向滩和 2026 岩手小震的 NIED 目录 ID，但这不影响已下载 4 个强震事件
进入波形域预训练。NIED HTTPS 直链无凭据访问已返回 `401 Unauthorized`，因此
项目只保存下载 manifest，不保存账号、cookie 或受限波形文件。已下载的正式
波形 zip 和特征 JSON 默认存放在 `tmp/`，不提交到仓库。

2026-06-21 16:33:18 JST 已完成一帧多图层接口探测：
`tmp/captures/physical_layer_probe_v2_20260621_163318`，成功下载
`jma/acmap/vcmap/dcmap` 的地表与地中共 8 张 GIF，无失败。

台站级对齐结果：

- 有扫描坐标台站：1630；
- 四图层均可解码：1260（77.3%）；
- `jma/acmap` 色标位置相关系数：0.577；
- `jma/vcmap` 色标位置相关系数：0.095；
- `jma/dcmap` 色标位置相关系数：0.003。

这是一帧静默时刻接口探测，不是事件效果评估，但已经证明四个图层不能互相替代。
报告：
[`docs/baselines/nied_layer_alignment_probe_20260621.generated.md`](baselines/nied_layer_alignment_probe_20260621.generated.md)

首个真实地震多图层窗口：

```text
event:       2026-06-21 石川県能登地方 M2.7
JMA origin:  21:07:56 UTC+8
capture:     tmp/captures/noto_m27_20260621_210754_multilayer
window:      22:07:24-22:09:54 JST
timestamps:  151
GIF:         1208/1208
station-sec: 246130
four-layer:  190041 (77.2%)
split:       unassigned_reference
```

EQuake 最终报相对 JMA 的水平误差为 3.45 km、时间差 -2 秒、深度差 -5 km、
震级差 -0.6。EQuake 只作参考，JMA 为真值。

报告：

- [`docs/baselines/noto_m27_20260621_reference.md`](baselines/noto_m27_20260621_reference.md)
- [`docs/baselines/noto_m27_20260621_multilayer_alignment.generated.md`](baselines/noto_m27_20260621_multilayer_alignment.generated.md)

第二个真实地震多图层窗口：

```text
event:       2026-06-21 Miyagi southeast offshore M3.2 (Hi-net label, EQuake reference)
origin:      22:41:12 UTC+8 / 23:41:12 JST
capture:     tmp/captures/fukushima_offshore_m32_20260621_224108_multilayer
window:      23:40:38-23:43:08 JST
timestamps:  151
GIF:         1208/1208
station-sec: 246130
four-layer:  190062 (77.2%)
split:       unassigned_reference
```

用户提供的 Hi-net 标签为宫城县东南冲、37.616N/142.279E、M3.2、深度 29.8 km。
EQuake 第 6 报为福岛县冲、M3.2、深度 30 km、35 个触发台站，只作为触发、质量和
UI 参考。该事件可用于输入完整性、震源专用触发召回和多图层特征诊断；进入冻结
定位误差指标前仍需事件级 split 复核。

报告：

- [`docs/baselines/fukushima_offshore_m32_20260621_reference.md`](baselines/fukushima_offshore_m32_20260621_reference.md)
- [`docs/baselines/fukushima_offshore_m32_20260621_multilayer_alignment.generated.md`](baselines/fukushima_offshore_m32_20260621_multilayer_alignment.generated.md)

第三个真实地震多图层窗口：

```text
event:       2026-06-22 Iwate northeast offshore M3.4 (Hi-net label, EQuake reference)
origin:      08:28:23 UTC+8 / 09:28:23 JST
capture:     tmp/captures/iwate_offshore_m30_20260622_082823_multilayer
window:      09:27:53-09:30:23 JST
timestamps:  151
GIF:         1208/1208
station-sec: 246130
four-layer:  190067 (77.2%)
split:       unassigned_reference
```

用户提供的 Hi-net 标签为岩手县东北冲、40.392N/142.341E、M3.4、深度 50.2 km。
EQuake 第 10 报为岩手县冲、M3.0、深度 22 km、52 个触发台站，只作为触发、
质量和 UI 参考。该事件可用于输入完整性、震源专用触发召回和多图层特征诊断；
进入冻结定位误差指标前仍需事件级 split 复核。

报告：

- [`docs/baselines/iwate_offshore_m30_20260622_reference.md`](baselines/iwate_offshore_m30_20260622_reference.md)
- [`docs/baselines/iwate_offshore_m30_20260622_multilayer_alignment.generated.md`](baselines/iwate_offshore_m30_20260622_multilayer_alignment.generated.md)

第四个真实地震多图层窗口：

```text
event:       2026-06-22 Wakayama south M2.5 (Hi-net label)
origin:      08:51:17 UTC+8 / 09:51:17 JST
capture:     tmp/captures/wakayama_south_m25_20260622_085117_multilayer
window:      09:50:47-09:53:17 JST
timestamps:  151
GIF:         1208/1208
station-sec: 246130
four-layer:  189984 (77.2%)
split:       unassigned_reference
```

用户提供的 Hi-net 标签为和歌山县南部、33.580N/135.791E、M2.5、深度 28.1 km。
该事件可用于输入完整性、震源专用触发召回和多图层特征诊断；进入冻结定位误差
指标前仍需事件级 split 复核。

报告：

- [`docs/baselines/wakayama_south_m25_20260622_reference.md`](baselines/wakayama_south_m25_20260622_reference.md)
- [`docs/baselines/wakayama_south_m25_20260622_multilayer_alignment.generated.md`](baselines/wakayama_south_m25_20260622_multilayer_alignment.generated.md)

解析器：

- [`lib/core/replay/jma_intensity_archive.dart`](../lib/core/replay/jma_intensity_archive.dart)
- [`lib/core/replay/jma_intensity_dataset.dart`](../lib/core/replay/jma_intensity_dataset.dart)
- [`lib/core/replay/synthetic_reveal_dataset.dart`](../lib/core/replay/synthetic_reveal_dataset.dart)
- [`lib/core/replay/knet_waveform_archive.dart`](../lib/core/replay/knet_waveform_archive.dart)
- [`lib/core/replay/knet_waveform_features.dart`](../lib/core/replay/knet_waveform_features.dart)
- [`lib/core/replay/knet_waveform_event_manifest.dart`](../lib/core/replay/knet_waveform_event_manifest.dart)
- [`lib/core/replay/knet_gif_domain_alignment.dart`](../lib/core/replay/knet_gif_domain_alignment.dart)
- [`lib/core/replay/waveform_projected_gif.dart`](../lib/core/replay/waveform_projected_gif.dart)
- [`lib/core/replay/waveform_projected_gif_baseline.dart`](../lib/core/replay/waveform_projected_gif_baseline.dart)
- [`tools/import_jma_intensity_archive.dart`](../tools/import_jma_intensity_archive.dart)
- [`tools/build_jma_intensity_dataset.dart`](../tools/build_jma_intensity_dataset.dart)
- [`tools/build_synthetic_reveal_dataset.dart`](../tools/build_synthetic_reveal_dataset.dart)
- [`tools/train_static_intensity_baseline.dart`](../tools/train_static_intensity_baseline.dart)
- [`tools/build_knet_waveform_features.dart`](../tools/build_knet_waveform_features.dart)
- [`tools/build_knet_waveform_feature_index.dart`](../tools/build_knet_waveform_feature_index.dart)
- [`tools/build_waveform_projected_gif_dataset.dart`](../tools/build_waveform_projected_gif_dataset.dart)
- [`tools/train_waveform_projected_gif_baseline.dart`](../tools/train_waveform_projected_gif_baseline.dart)
- [`tools/build_knet_download_manifest.dart`](../tools/build_knet_download_manifest.dart)
- [`tools/download_knet_waveforms.ps1`](../tools/download_knet_waveforms.ps1)
- [`tools/build_knet_gif_waveform_alignment.dart`](../tools/build_knet_gif_waveform_alignment.dart)
- [`tools/build_nied_layer_alignment_report.dart`](../tools/build_nied_layer_alignment_report.dart)
- [`tools/build_jma_intensity_pretraining.ps1`](../tools/build_jma_intensity_pretraining.ps1)

第一批 K-NET/KiK-net 波形候选：

- [`test/fixtures/source_estimation/knet_waveform_event_candidates.json`](../test/fixtures/source_estimation/knet_waveform_event_candidates.json)
- 生成的本地下载清单：`tmp/knet_waveform_seed_download_manifest.json`

| 事件 | 类型 | NIED 目录 ID | 本地 GIF |
|---|---|---:|---|
| 2016 熊本 M7.3 | 内陆浅源 | `20160416012500` | 无 |
| 2018 北海道胆振 M6.6 | 内陆较深 | `20180906030800` | 无 |
| 2021 福岛县冲 M7.3 | 海域中深 | `20210213230800` | 无 |
| 2022 福岛县冲 M7.4 | 海域中深 | `20220316233630` | 无 |
| 2024 能登半岛 M7.6 | 沿岸复杂破裂 | `20240101161000` | 无 |
| 2024 日向滩 M7.1 | 板块边界 | `20240808164230` | 无 |
| 2026 岩手县冲 M3.3 EQuake 参考 | 海域小震 | `20260621113200` provisional | 有 |

2026 岩手小震的 `niedDirectoryId` 只是 00/30 秒辅助建议值，必须在 NIED
目录中确认后才能用于波形/GIF 对齐。大震候选优先用于波形特征预训练；因为本
项目没有对应实时 GIF 回放，不进入 GIF 域对齐。

正式波形下载与特征包生成结果：

```text
download manifest: tmp/knet_waveform_seed_download_manifest.json
download report:   tmp/knet_downloads/download_report.json
downloaded zip:    8 files / 469.55 MB
feature packages:  8 files / 275.33 MB
feature index:     tmp/knet_features/knet_waveform_feature_index.json
```

| 事件 | 格式 | 通道 | 特征序列 | 特征包 |
|---|---|---:|---:|---|
| 2016 熊本 M7.3 | ASCII | 1110 | 370 | `tmp/knet_features/kumamoto_20160416_m73_20160416012500_ascii_features.json` |
| 2016 熊本 M7.3 | CSV | 1110 | 370 | `tmp/knet_features/kumamoto_20160416_m73_20160416012500_csv_features.json` |
| 2018 北海道胆振 M6.6 | ASCII | 804 | 268 | `tmp/knet_features/hokkaido_iburi_20180906_m66_ascii_features.json` |
| 2018 北海道胆振 M6.6 | CSV | 804 | 268 | `tmp/knet_features/hokkaido_iburi_20180906_m66_20180906030800_csv_features.json` |
| 2021 福岛县冲 M7.3 | ASCII | 1638 | 546 | `tmp/knet_features/fukushima_offshore_20210213_m73_20210213230800_ascii_features.json` |
| 2021 福岛县冲 M7.3 | CSV | 1638 | 546 | `tmp/knet_features/fukushima_offshore_20210213_m73_20210213230800_csv_features.json` |
| 2024 能登半岛 M7.6 | ASCII | 1785 | 595 | `tmp/knet_features/noto_peninsula_20240101_m76_20240101161000_ascii_features.json` |
| 2024 能登半岛 M7.6 | CSV | 2730 | 910 | `tmp/knet_features/noto_peninsula_20240101_m76_20240101161000_csv_features.json` |

下载失败项：

- 2022 福岛县冲 `20220316233630`：4 个目标均返回 `404 Not Found`，需复核
  NIED 目录 ID；
- 2024 日向滩 `20240808164230`：4 个目标均返回 `404 Not Found`，需复核
  NIED 目录 ID；
- 2026 岩手小震 `20260621113200`：4 个目标均返回 `404 Not Found`，说明
  provisional 目录 ID 未确认或该小震无正式强震动 zip；
- 2024 能登 K-NET CSV 曾出现一次传输 EOF，但本地已有完整 zip 并已成功生成
  特征包。

`waveform_projected_gif` 构建结果：

```text
source index:   tmp/knet_features/knet_waveform_feature_index.json
output index:   tmp/waveform_projected_gif/waveform_projected_gif_index.json
packages:       4
stations/roles: 2094
station-seconds: 353484
preferred format: csv
```

| 事件 | 格式 | 台站/角色 | station-second | 输出 |
|---|---|---:|---:|---|
| 2016 熊本 M7.3 | CSV | 370 | 46766 | `tmp/waveform_projected_gif/kumamoto_20160416_m73_csv_waveform_projected_gif.json` |
| 2018 北海道胆振 M6.6 | CSV | 268 | 35276 | `tmp/waveform_projected_gif/hokkaido_iburi_20180906_m66_csv_waveform_projected_gif.json` |
| 2021 福岛县冲 M7.3 | CSV | 546 | 87492 | `tmp/waveform_projected_gif/fukushima_offshore_20210213_m73_csv_waveform_projected_gif.json` |
| 2024 能登半岛 M7.6 | CSV | 910 | 183950 | `tmp/waveform_projected_gif/noto_peninsula_20240101_m76_csv_waveform_projected_gif.json` |

每条观测保留 `domain=waveform_projected_gif`、`projected_from_official_waveform`
和 `not_real_nied_gif` 语义，不能用于真实 GIF 延迟、缺帧或上线验收。

事件级留一空间基线：

- 投影格式已升级到 v2，保留事件真值与台站经纬度；
- 只使用地表传感器和震源时刻后 120 秒，事件整体留出，不拆 station-second；
- 在其余三个事件选择震度阈值和权重指数，要求每个训练事件至少覆盖 25% 帧；
- 4 个留出事件的首个可估位置误差中位数为 13.62 km；
- 120 秒逐帧位置误差中位数为 74.48 km，投影等级量化 MAE 为 0.083 震度单位；
- 海域事件和后期帧漂移明显，当前帧加权质心不能接入生产。

冻结报告：
[`docs/baselines/waveform_projected_gif_spatial_baseline.generated.md`](baselines/waveform_projected_gif_spatial_baseline.generated.md)

统一时序与到时约束结果：

- 生产 `SeismicSourceTracker` 已为每站保存最近 60 秒逐帧历史；
- 历史帧区分 `dataTime` 与 `receivedAt`，并保留缺失/陈旧等质量标志；
- 首次上升和首次触发已保留为观测时间区间，旧估算器兼容读取区间终点；
- 事件级峰值与首次触发证据不随 60 秒环形缓冲淘汰；
- 投影域基线使用事件累计峰值，并按相对首次到时指数衰减晚到台站；
- 4 个留出事件的首个可估位置误差中位数由 13.62 km 降至 7.40 km；
- 120 秒逐帧位置误差中位数由 74.48 km 降至 10.58 km；
- 80% 缺站下仍需单独看事件结果，不能据此宣称真实 GIF 上线可用。

冻结报告：
[`docs/baselines/waveform_projected_gif_temporal_baseline.generated.md`](baselines/waveform_projected_gif_temporal_baseline.generated.md)

批量构建：

```powershell
.\tools\build_jma_intensity_pretraining.ps1 -Years 2020,2021,2022
```

2020-2022 年真实构建结果：

```text
events: 5994
eligible events: 2559
train / validation / test: 744 / 896 / 919
station history records: 7239
observations: 173447
usable observations: 171146 (98.67%)
events rejected for fewer than 4 usable stations: 3435
```

split 按年度冻结为 `2020=train`、`2021=validation`、`2022=test`，避免事件级
时间泄漏。有效事件必须具有完整经纬度、深度和震级标签，并至少包含 4 个同时
具有坐标与计测震度的不同台站。生成的数据和质量报告默认写入
`tmp/jma_intensity_pretraining/`，不提交大型派生 JSON。

台站遮蔽与理论揭示真实构建结果：

```text
source train/validation events: 1640
generated variants: 4920
mask rates: 20% / 50% / 80%
effective mask rates: 19.87% / 49.08% / 77.96%
frozen test events: 919
test derived samples: 0
```

掩码由固定 seed 和事件/台站 ID 生成，可跨运行复现，并保持
`80% subset 50% subset 20%` 的嵌套关系。每个保留台站保存常速理论 P/S
到时，120 秒外到时只统计为窗口外，不提前揭示。震度值始终标记为 JMA 最终
峰值，不能作为真实一秒时序或真实 P/S 拾取。

P3 静态衰减 v1 使用 train 拟合 Huber 衰减参数，并在 validation 上选择质心
退化正则，未读取冻结 test。validation 结果：

```text
cases: 2688
P3 median error: 33.98 km
weighted centroid median: 35.68 km
P3 P90 error: 92.55 km
weighted centroid P90: 94.91 km
P50 / P90 coverage: 60.3% / 78.2%
```

三档遮蔽的中位误差均优于质心。P90 覆盖率仍明显低于 90%，因此该模型只作为
预训练基线，不接入生产，也不代表路线图整体 P3 已通过最终验收。

K-NET/KiK-net 波形解析器实现状态：

- ASCII：解析 17 行官方头、原始 digit、`Scale Factor`、`Max. Acc. (gal)`、
  采样率、记录时间和数据源路径；
- ASCII 时间语义：`Record Time` 是触发记录时刻，样本起点按官方说明回退
  15 秒；
- CSV：解析 K-NET 三通道和 KiK-net 六通道物理加速度，标记为
  `csv_physical_gal_0.01`，不再当作原始高精度 digit；
- 角色：K-NET 默认地表；KiK-net `NS1/EW1/UD1` 为井下，
  `NS2/EW2/UD2` 为地表；
- 输出字段包含 `processingVersion`、`sourcePath`、`format`、`network`、
  `sensorRole`、`component`、`samplingHz`、`sampleStartTimeUtc`、单位和精度
  标记。

实现依据：

- NIED K-NET ASCII format: <https://www.kyoshin.bosai.go.jp/en/knetascii/>
- NIED K-NET CSV format: <https://www.kyoshin.bosai.go.jp/ja/knetcsv/>
- NIED HTTPS download directory semantics:
  <https://www.kyoshin.bosai.go.jp/en/https_download/>

K-NET/KiK-net 波形特征 v1 实现状态：

- 输入：解析后的三分量加速度，按 `stationCode + sensorRole` 分组；
- PGA：每秒 offset-corrected 三分量向量加速度峰值，单位 gal；
- PGV：每秒 offset-corrected 加速度积分速度峰值，单位 cm/s，质量标志为
  `pgv_integrated_without_instrument_response_correction`；
- 实时震度代理：每秒向量加速度排序后取 0.3 秒持续阈值并套用
  `I = 2 log10(a) + 0.94`，但未执行 JMA 频率滤波，质量标志为
  `jma_intensity_unfiltered_duration_proxy`；
- 触发特征：每秒 RMS 加速度和相对前序背景 RMS 的能量比，只输出特征，不在
  该层做事件检出决策；
- CLI：`dart run tools/build_knet_waveform_features.dart --input <zip|csv|ascii> --output <features.json>`。

实现依据：

- JMA 计测震度计算方法：
  <https://www.jma.go.jp/jma/kishou/know/jishin/kyoshin/kaisetsu/calc_sindo.html>

K-NET/KiK-net 下载清单与 GIF/波形对齐工具状态：

- 下载清单 schema：`knet_waveform_download_manifest_v1`；
- 事件候选必须显式保存 `niedDirectoryId`，不允许只用发震时刻秒数猜测 NIED
  目录；辅助函数只给出 00/30 秒建议值，人工确认后写入；
- 生成目标 URL 覆盖 `all/knet/kik/kik0` 的 `ascii/csv` zip，但只写 manifest，
  不处理账号、密码或大文件再分发；
- GIF 秒级观测输入 schema 建议为：

```json
{
  "schemaVersion": "gif_station_second_observations_v1",
  "observations": [
    {
      "stationCode": "TST001",
      "observedAtUtc": "2026-06-20T12:00:00Z",
      "gifDecodedShindo": 1.2,
      "sensorRole": "surface",
      "qualityFlags": []
    }
  ]
}
```

- 对齐报告 schema：`knet_gif_domain_alignment_v1`；
- 对齐器按 `stationCode + sensorRole` 匹配，避免混用 K-NET 地表、KiK-net 地表
  和 KiK-net 井下；
- 默认搜索 -5 到 +5 秒滞后，输出每站最佳滞后、均值偏差、平均绝对偏差、
  RMSE、饱和/低值计数、缺失波形台站和样本明细；
- CLI：
  `dart run tools/build_knet_download_manifest.dart --input <events.json> --output <manifest.json>`；
- CLI：
  `dart run tools/build_knet_gif_waveform_alignment_readiness_report.dart`；
- CLI：
  `dart run tools/build_knet_waveform_directory_id_confirmation_worklist.dart`；
- CLI：
  `dart run tools/export_nied_capture_gif_observations.dart --capture <capture_dir> --output <gif_observations.json> [--sensor-role surface|borehole]`；

Current confirmed progress:

- `20260624_fukushima_aizu_m32_jma_eq5` and
  `20260626_yamanashi_east_fuji_five_lakes_m56_jma_equake21` now have official
  CSV waveforms downloaded, per-event feature packages extracted, and the
  confirmation readiness report regenerated at
  [`docs/baselines/knet_confirmation_alignment_readiness.generated.md`](baselines/knet_confirmation_alignment_readiness.generated.md).
- The official query review is also saved at
  [`docs/baselines/knet_official_search_review.generated.md`](baselines/knet_official_search_review.generated.md):
  2 capture fixtures confirmed, 6 provisional overlaps still unresolved in the
  current official search window.
- The unresolved six are now tracked in
  [`docs/baselines/knet_official_unresolved_queue.generated.md`](baselines/knet_official_unresolved_queue.generated.md),
  so future authoritative evidence can re-enter the queue without losing
  provenance.
- The first real GIF / waveform alignment report is also saved at
  [`docs/baselines/knet_confirmation_alignment_report.generated.md`](baselines/knet_confirmation_alignment_report.generated.md),
  covering the two confirmed official CSV pairs.
- The projected waveform dataset has also been expanded to CSV+ASCII all-formats
  coverage for the four seed events, and the current spatial baseline was
  regenerated on the 8-package all-formats index at
  [`docs/baselines/waveform_projected_gif_spatial_baseline.generated.md`](baselines/waveform_projected_gif_spatial_baseline.generated.md).
  This all-formats variant is for parser/format robustness diagnostics; the
  CSV-preferred single-format index remains the main pretraining pool.
- The remaining provisional overlaps stay in the directory-id confirmation
  queue until their official NIED rows are found.
- CLI：
  `dart run tools/build_knet_gif_waveform_alignment.dart --event-id <id> --features <features.json> --gif-observations <gif.json> --output <alignment.json>`。
- 无凭据访问测试：
  `https://www.kyoshin.bosai.go.jp/kyoshin/download/knet/zip/2016/04/20160416012500/20160416012500_ascii.zip`
  返回 `401 Unauthorized`；后续下载必须由已注册用户在本地完成。
- 本地下载脚本：
  `powershell -NoProfile -ExecutionPolicy Bypass -File tools\download_knet_waveforms.ps1 -ManifestPath tmp\knet_waveform_seed_download_manifest.json -OutputDirectory tmp\knet_downloads -Username <user> -SkipExisting`
  运行时隐藏输入密码，不把密码写入命令行、项目文件或下载报告。
## 2026-06-22 Iwate East Offshore M3.0 Capture

The user-provided Hi-net automatic hypocenter at `2026-06-22 10:26:50 UTC+8`
(`39.910N, 142.347E`, M3.0, depth 42.4 km) is linked as a preliminary,
`reference_only` label. A complete 151-second, eight-layer NIED GIF window was
captured with 1208/1208 files and no failures. The event remains outside frozen
metrics pending event-level split review and final-catalog linking.

Replay diagnostics show source-trigger candidate/confirmation at +15/+17 s,
with 14 connected evidence stations within 100 km. Hybrid median/P90 location
errors are 65/615 km, so this event is retained as an offshore network-bias and
late-drift validation countercase rather than a tuning target.

- [`docs/baselines/iwate_east_offshore_m30_20260622_reference.md`](baselines/iwate_east_offshore_m30_20260622_reference.md)
- [`docs/baselines/iwate_east_offshore_m30_20260622_multilayer_alignment.generated.md`](baselines/iwate_east_offshore_m30_20260622_multilayer_alignment.generated.md)
## 2026-06-22 Fukushima Offshore M2.2 EQuake Capture

EQuake report 4 (`2026-06-22 14:36:56 UTC+8`, 37.38N/141.27E, M2.2,
depth 23 km) was used only to capture a complete 151-second, eight-layer NIED
window. All 1208 GIFs downloaded successfully. The event is `reference_only`
until an independent Hi-net or JMA catalog label is linked.

The source-specific detector now leaves the +49 s activity as candidate-only.
Its 145-161 km chain fails the 120 km initial compact-core gate, times out after
eight candidate frames, and produces no source estimate. Rejected members must
clear before the detector can rearm.

- [`docs/baselines/fukushima_offshore_m22_20260622_reference.md`](baselines/fukushima_offshore_m22_20260622_reference.md)
- [`docs/baselines/fukushima_offshore_m22_20260622_multilayer_alignment.generated.md`](baselines/fukushima_offshore_m22_20260622_multilayer_alignment.generated.md)
## 2026-06-22 Kushiro Offshore M3.0 JMA Capture

The JMA source and intensity event at `2026-06-22 15:38:12 UTC+8`
(`42.9N, 144.0E`, M3.0, depth 50 km, maximum shindo 1) has a complete
151-second, eight-layer NIED window with 1208/1208 GIFs and no failures.

Source-specific candidate/confirmation occurs at +9/+11 s with eight connected
evidence stations within 50 km. Weighted centroid median/P90 error is
16.5/22.9 km, while the current hybrid reaches 28/118.2 km. This JMA-verified
event is a positive offshore/depth regression case for suppressing late hybrid
drift without weakening source-trigger recall.

- [`docs/baselines/kushiro_offshore_m30_20260622_reference.md`](baselines/kushiro_offshore_m30_20260622_reference.md)
- [`docs/baselines/kushiro_offshore_m30_20260622_multilayer_alignment.generated.md`](baselines/kushiro_offshore_m30_20260622_multilayer_alignment.generated.md)
## 2026-06-23 Tokachi Southeast Offshore M3.4 Capture

The user-provided Hi-net automatic hypocenter at `2026-06-23 22:13:06 UTC+8`
(`42.497N, 143.647E`, M3.4, depth 55.5 km) is linked as a preliminary,
`reference_only` label. EQuake final report 11 is retained as source-estimation
reference text only: `42.49N, 143.70E`, M3.1, depth 61 km, quality B 73.5%,
RMS 0.75 s, azimuthal gap 155 deg and 54 triggered stations (`P:9 S:33 O:12`).

A complete 151-second, eight-layer NIED GIF window was captured with 1208/1208
files and no failures. This is the eighth complete multilayer event window in
the current local set. It remains outside frozen metrics pending event-level
split review and final-catalog linking.

Replay diagnostics show source-trigger candidate/confirmation at +16/+19 s.
Hybrid median/P90 location errors are 18/45 km, outperforming weighted
centroid's 63/162 km. The final tail still drifts to a 98 km one-sided boundary
solution, so this event is useful both as a Hokkaido offshore positive case and
as a late-drift regression case.

- [`docs/baselines/tokachi_southeast_offshore_m34_20260623_reference.md`](baselines/tokachi_southeast_offshore_m34_20260623_reference.md)
- [`docs/baselines/tokachi_southeast_offshore_m34_20260623_multilayer_alignment.generated.md`](baselines/tokachi_southeast_offshore_m34_20260623_multilayer_alignment.generated.md)

## 2026-06-27 Surface-Only Default Training Target

The default real-time GIF training and fine-tuning target is now the surface
shindo layer `jma_s` for every scan-mapped station.

Training implications:

- `waveform_projected_gif` surface targets should map official waveform-derived
  seconds to a surface-shindo-equivalent target by default.
- KiK-net borehole channels remain available as explicit auxiliary features or
  diagnostic domains, but they must not silently replace the default surface
  target.
- Any model using `jma_b` must declare a named sensor-selection policy and run
  a separate non-regression report before it can affect production scoring.
- Historical validation numbers produced with the old `K-NET surface /
  KiK-net borehole` default remain historical baselines only. The current P3
  static attenuation report is retained as a validation baseline, but a
  surface-default-aligned recalibration is still required before production use.

This keeps pretraining aligned with the production input decision:

```text
default training target = jma_s
default production shindo input = jma_s
default map station display = jma_s
jma_b = explicit auxiliary borehole domain
```

## 2026-06-27 Static Intensity Estimation Status

Current status:

- The JMA final station-intensity parser and event-level split builder are
  implemented.
- The 2020-2022 JMA final intensity synthetic-reveal dataset has been built:
  1640 source events, 744 train events, 896 validation events and 919 frozen
  test events.
- `static_intensity_attenuation_v1` has been trained on train and selected on
  validation only.
- Validation result: median/P90 error is 33.98/92.55 km, compared with
  weighted-centroid 35.68/94.91 km.
- Forecast validation result on the same validation split:
  max-shindo class MAE 0.61 classes, numeric max-shindo MAE 0.62, station
  intensity MAE 0.67, exact max-class accuracy 47.2%, within-one-class
  accuracy 92.7% and max-class underestimation rate 52.8%.
- Global additive calibration scan result:
  the best diagnostic high-shindo offset is `-0.20`, improving station MAE
  from 0.67 to 0.59 and high-shindo F1, but worsening max-class MAE from 0.61
  to 0.77 and increasing max-class underestimation from 52.8% to 65.8%.
- Precision-safe stratified calibration scan result:
  one of three predicted-max/uncertainty strata selects a non-zero offset
  (`pred_le_2/p90_50_100km -> +0.10`). Overall max-class MAE improves
  0.61 to 0.56 and underestimation improves 52.8% to 48.7%, but station MAE
  worsens 0.67 to 0.70 and high-shindo precision does not improve.
- Station-distance diagnostics show the far-distance bucket `gt_200km` has a
  strong positive residual (`+1.09` mean residual, 1.14 MAE), making it a
  likely source of long-range high-shindo false positives.
- Distance residual correction scan:
  correcting all distance buckets improves station MAE and high-shindo
  precision, but worsens max-class MAE 0.61 to 0.95 and underestimation
  52.8% to 76.2%.
- Targeted `gt_200km` correction preserves max-class MAE and underestimation
  while improving station MAE 0.67 to 0.56, `shindo4` precision 28.3% to
  46.2% and `shindo5-` precision 17.2% to 33.3%.
- Probability/confidence gate scan leaves the raw intensity field unchanged
  and uses the `gt_200km` correction only as a threshold feature:
  `shindo3` improves to 41.6% precision / 84.6% recall / 55.8% F1,
  `shindo4` improves to 55.1% / 63.6% / 59.0%, and `shindo5-` matches hard
  `gt_200km` correction at 33.3% / 71.1% / 45.3%.
- Probability-gate acceptance:
  `shindo5-` passes validation criteria, while `shindo4` is `warn` because
  precision/F1 improve but recall loss is 24.9% and false-negative ratio is
  3.18x. The gate is therefore not ready for automatic frozen-test evaluation.
- Baseline report:
  [`docs/baselines/static_attenuation_validation.generated.md`](baselines/static_attenuation_validation.generated.md).
- Forecast metric report:
  [`docs/baselines/static_intensity_forecast_validation.generated.md`](baselines/static_intensity_forecast_validation.generated.md).
- Calibration scan report:
  [`docs/baselines/static_intensity_calibration.generated.md`](baselines/static_intensity_calibration.generated.md).
- Stratified calibration report:
  [`docs/baselines/static_intensity_stratified_calibration.generated.md`](baselines/static_intensity_stratified_calibration.generated.md).
- Distance residual calibration report:
  [`docs/baselines/static_intensity_distance_residual_calibration.generated.md`](baselines/static_intensity_distance_residual_calibration.generated.md).
- Probability-gate literature notes:
  [`docs/baselines/static_intensity_probability_gate_literature.md`](baselines/static_intensity_probability_gate_literature.md).
- Probability gate report:
  [`docs/baselines/static_intensity_probability_gate.generated.md`](baselines/static_intensity_probability_gate.generated.md).
- Probability gate acceptance report:
  [`docs/baselines/static_intensity_probability_gate_acceptance.generated.md`](baselines/static_intensity_probability_gate_acceptance.generated.md).
- JMA-style traditional intensity diagnostic:
  [`docs/baselines/jma_style_intensity.generated.md`](baselines/jma_style_intensity.generated.md).
  This uses oracle catalog source and magnitude, then applies the JMA-style
  traditional PGV path (`Mw = Mjma - 0.171`, 司・翠川 PGV600 attenuation,
  `ARV700 * 0.90`, and `I = 2.68 + 1.72 log10(PGVS)`). Validation summary:
  max-shindo class MAE 0.43 classes, within-one accuracy 97.1%, `shindo4`
  precision/recall/F1 78.3% / 27.5% / 40.7%, and `shindo5-`
  65.0% / 4.0% / 7.5%. The same traditional path with P3-estimated source
  variants produces 2688 cases, max-shindo class MAE 0.59 classes, within-one
  accuracy 92.9%, `shindo4` 56.5% / 51.0% / 53.6%, and `shindo5-`
  87.8% / 8.1% / 14.8%.

Decision:

- This is a diagnostic P3 intensity-only attenuation/source-inversion baseline,
  not a production maximum-shindo forecast.
- The forecast metric report is still a synthetic reveal of final peak station
  intensity, not a true realtime lead-time validation.
- A single global additive offset is not sufficient as a final calibration
  policy because it trades high-shindo false positives for more maximum-shindo
  underestimation.
- The first precision-safe stratified offset scan improves maximum-shindo
  class metrics but does not improve high-shindo precision, so it is not a
  production calibration policy.
- Targeted `gt_200km` residual correction is promising as a confidence or
  probability-calibration feature, but it still must not directly mutate
  runtime intensity fields before frozen-test acceptance.
- Literature review supports this boundary: EEW intensity prediction has
  unavoidable attenuation/site/source uncertainty, so far-distance residuals
  should enter threshold exceedance probability or confidence, not raw
  production intensity mutation.
- The first probability gate improves high-shindo precision and F1 without
  mutating raw intensity fields, but `shindo4` recall falls to 63.6%, so it
  requires explicit operating-point acceptance criteria.
- The validation acceptance report blocks automatic frozen-test use until the
  `shindo4` recall tradeoff is either accepted by product policy or the gate is
  revised.
- The JMA-style traditional diagnostic is useful as a conservative baseline and
  calibration reference, but it is not production-ready because high-shindo
  recall is low under both oracle and P3-estimated source variants.
- PLUM-like observed-shaking propagation has been implemented as a separate
  validation-only diagnostic:
  [`docs/baselines/plum_like_intensity.generated.md`](baselines/plum_like_intensity.generated.md).
  It is source-independent and uses retained stations as observed evidence
  while excluding the target station itself. On synthetic reveal validation,
  the selected config is radius 30 km, damping 0.25 shindo / 10 km and minimum
  evidence 1 station. It improves high-shindo recall/F1 versus the traditional
  path: `shindo4` 57.4% / 78.9% / 66.5%, and `shindo5-`
  43.8% / 67.4% / 53.1%.
- The combined diagnostic:
  [`docs/baselines/combined_intensity_prediction.generated.md`](baselines/combined_intensity_prediction.generated.md)
  compares P3 static raw, P3 probability gate, JMA-style P3-source,
  PLUM-like, and station-level `max(JMA-style, PLUM-like)`. The max branch
  lowers maximum-shindo underestimation to 16.9%, but `shindo4` precision
  drops below PLUM-like alone, so it is not an automatic production policy.
  It now also compares the replay-grid false-positive candidates
  `plum_like_r20_d0_50` and `plum_like_r30_d0_50` plus their `max(JMA, PLUM)`
  branches. On synthetic reveal, `plum_like_r30_d0_50` improves `shindo4`
  precision to 69.7% while lowering recall to 62.8%; its combined branch gives
  `shindo4` 55.9% / 72.5% / 63.1% and `shindo5-`
  58.8% / 46.9% / 52.2%. This makes `30 km / 0.50` the next diagnostic
  operating-point candidate, not a production replacement.
- The PLUM operating-point acceptance diagnostic:
  [`docs/baselines/plum_operating_point_acceptance.generated.md`](baselines/plum_operating_point_acceptance.generated.md)
  combines the synthetic-reveal combined report with the real replay lead-time
  grid. Current diagnostic criteria require replay `shindo4` recall >= 60%,
  replay `shindo4` false-alarm station reduction >= 25%, combined `shindo4`
  recall >= 70%, and combined `shindo4` F1 no worse than the baseline combined
  branch. After the replay complete-capture guard, the Yamanashi M3.3
  aftershock is skipped because its capture has 16 failed GIFs, leaving only
  6 complete replay cases and 906 decoded frames. Therefore no operating point
  is currently recommended for a new frozen-test criteria step; both replay
  candidates are `warn` on `replayCoverage=false`. The report still sets
  `advanceToFrozenTest=false` and `advanceToProduction=false`.
- The frozen-test acceptance criteria have now been fixed before opening the
  frozen split:
  [`docs/baselines/plum_frozen_test_acceptance_criteria.generated.md`](baselines/plum_frozen_test_acceptance_criteria.generated.md).
  The selected diagnostic operating point is `plum_like_r30_d0_50`
  (`30 km / 0.50 shindo per 10 km`, minimum evidence 1). Synthetic-reveal
  frozen criteria include max-class MAE <= 0.50, max-class underestimation
  <= 25%, `shindo4` P/R/F1 >= 52% / 68% / 60%, and `shindo5-` P/R/F1
  >= 52% / 40% / 48%. Real-replay criteria require at least 7 cases, 1000
  decoded frames, 20 actual `shindo4` stations, `shindo4` recall >= 55%,
  false-alarm reduction >= 25%, false-alarm ratio <= 50%, and non-negative
  median lead. Replay `shindo5-` remains a watch metric until it has at least
  10 actual stations.
- The first real replay-frame PLUM-like lead-time diagnostic has been added:
  [`docs/baselines/plum_like_replay_leadtime.generated.md`](baselines/plum_like_replay_leadtime.generated.md).
  It decodes local `jma_s` GIF frames only and measures station-threshold lead
  time without source coordinates. The current complete-capture diagnostic
  covers 6 evaluated cases, 906 decoded frames and 1476780 station-frames,
  including the Yamanashi M5.6 strong-motion replay. The Yamanashi M3.3
  aftershock remains in `skippedCases` because its capture manifest reports
  16 failed GIFs (286/302 downloaded), so it must not contribute to replay
  lead-time metrics until repaired or explicitly excluded. Baseline
  `30 km / 0.25 shindo per 10 km`
  propagation gives `shindo4` recall/false-alarm ratio `84.4% / 49.1%` and
  `shindo5-` `50.0% / 86.4%`. Evidence-count gates from 1 to 3 do not change
  the result, and 2-3 frame persistence reduces recall without materially
  reducing high-threshold false-alarm stations. The new radius/damping grid
  shows the false-positive control is mainly a propagation-distance/damping
  problem: `20 km / 0.50` gives `shindo4` `56.3%` recall with 14 false-alarm
  stations, while `30 km / 0.50` gives `62.5%` recall with 17 false-alarm
  stations. These are diagnostic operating-point candidates only.
- The one-time frozen-test evaluation has been run:
  [`docs/baselines/plum_frozen_test_evaluation.generated.md`](baselines/plum_frozen_test_evaluation.generated.md).
  The tool completed successfully, but the candidate outcome is `fail`.
  Overall max-class metrics pass (MAE 0.440, underestimation 17.2%, within-one
  95.4%), but high-shindo threshold metrics do not generalize:
  `shindo4` P/R/F1 is 38.0% / 57.2% / 45.7%, and `shindo5-`
  P/R/F1 is 26.5% / 38.1% / 31.3%. Production remains blocked, and this
  frozen result must not be used for further tuning claims.
- The frozen-regression diagnostic has been generated:
  [`docs/baselines/plum_frozen_regression_diagnostic.generated.md`](baselines/plum_frozen_regression_diagnostic.generated.md).
  It compares validation vs frozen test for the frozen diagnostic method
  `max_jma_style_plum_like_r30_d0_50`. Overall `shindo4` drops from
  55.9% / 72.5% / 63.1% to 38.0% / 57.2% / 45.7%, and `shindo5-` drops from
  58.8% / 46.9% / 52.2% to 26.5% / 38.1% / 31.3%. Worst `shindo4` F1 drops
  are `eventLatitudeBand=kanto_chubu` (-46.0 points), `stationDistance=030_060km`
  (-25.6 points), `maskRate=80pct` (-22.2 points), and `actualMaxClass=max_5plus`
  (-18.1 points). This indicates the validation gate did not cover geographic
  and high-mask high-shindo generalization well enough.
- The frozen-regression drilldown has been generated:
  [`docs/baselines/plum_frozen_regression_drilldown.generated.md`](baselines/plum_frozen_regression_drilldown.generated.md).
  It inspects 179844 frozen station forecasts and produces event/station
  false-positive and false-negative exemplars for the worst buckets:
  `kanto_chubu`, `030_060km`, `80pct`, and `max_5plus`. The result shows the
  failure is not one simple far-distance issue. False positives come from
  strong local observed shaking being spread into weak stations, while false
  negatives come from high-mask variants and true strong stations that the
  current `max(JMA-style, PLUM-like)` branch does not recover. The opened
  frozen split remains diagnostic evidence only and must not be used as a
  tuning set.
- A validation-only local-contrast guard diagnostic has been generated:
  [`docs/baselines/plum_validation_guard.generated.md`](baselines/plum_validation_guard.generated.md).
  The guard caps only the diagnostic PLUM branch when the nearest retained
  neighbor inside a local radius is weak. The current best candidate is
  `local_contrast_r20_w3_0_m1_cap0_5`, which reduces validation `shindo4`
  false positives from 3015 to 2872 and nudges `shindo4` F1 from 63.1% to
  63.5%, while lowering recall from 72.5% to 71.9%. It also lowers `shindo5-`
  F1 from 52.2% to 50.0%, so it is only a candidate for further real-replay
  validation, not a production policy.
- The local-contrast guard has been checked on real replay frames by adding
  `r30_d0.50_local_contrast_r20_w3.0` to
  [`docs/baselines/plum_like_replay_leadtime.generated.md`](baselines/plum_like_replay_leadtime.generated.md).
  It reduces replay `shindo4` false alarms from 17 to 12, but recall falls
  from 62.5% to 40.6%. This is too expensive, so this hard-cap local-contrast
  guard is rejected for now and must not advance to frozen test or production.
- A soft confidence-gate diagnostic has been generated:
  [`docs/baselines/plum_confidence_gate.generated.md`](baselines/plum_confidence_gate.generated.md),
  with triage in
  [`docs/baselines/plum_confidence_gate_acceptance.generated.md`](baselines/plum_confidence_gate_acceptance.generated.md).
  This preserves raw predicted intensity and only evaluates whether a
  high-threshold prediction is confidence-supported. The recommended validation
  gate is `plum_r20_d0_50_only`: validation `shindo4` precision/recall/F1 moves
  from 55.9% / 72.5% / 63.1% to 69.6% / 60.7% / 64.8%, while false positives
  fall from 3015 to 1399. Replay maps this to `r20_d0.50`, where `shindo4`
  recall/false alarms are 56.3% / 14 versus the `r30_d0.50` baseline
  62.5% / 17. The triage status is `warn`: false alarms improve, but replay
  recall is below the preferred 60% floor, so manual product decision is
  required before wording-only criteria can be written.
- Product boundary for this line:
  raw predicted intensity remains the canonical prediction output. Confidence
  gates must not replace, cap, hide or relabel the predicted intensity itself.
  They may only become inputs to a later wording layer, such as
  `high_confidence`, `possible`, or `reference`. Notification triggering must
  not consume this confidence layer until a separate notification policy and
  tests are written.
- The model is not connected to production UI, notifications or warning
  wording.
- Next work is not production wiring. Wording labels such as
  `high_confidence`, `possible`, and `reference` are deferred to a later
  UI/wording design step. If that later step proceeds, write wording-only
  acceptance criteria before any future frozen evaluation.
- A validation-only strong-evidence shape diagnostic has been generated:
  [`docs/baselines/plum_evidence_shape.generated.md`](baselines/plum_evidence_shape.generated.md).
  It checks whether hard PLUM suppression based on strong-evidence count and
  spatial spread can reduce isolated false positives. It does reduce some
  `shindo4` false positives, but every tested hard shape gate lowers validation
  `shindo4` F1 versus the baseline. The strongest false-positive reducer,
  `shape_t4_min3_r30_margin0_5_spread10`, reduces false positives from 3015 to
  2674 but drops recall from 72.5% to 69.1% and F1 from 63.1% to 62.9%.
  Therefore no shape candidate is recommended for replay validation, frozen
  test, UI, notification or wording paths.
- Next algorithm work should move away from hard suppression gates. Prefer
  non-suppressive features: per-region/site calibration, mask/evidence
  robustness scoring, or threshold probability/confidence features that
  preserve raw predicted intensity.
- Follow-up non-suppressive diagnostics have now been run through the
  robustness, region/site, raw-source-family, JMA-style `kanto_chubu`, and
  PLUM-led `tohoku` branches. The current conclusion is deliberately narrow:
  the diagnostics identify failure families, but they do **not** produce a
  stable production-ready correction.
  - Evidence robustness and region/site tables are useful diagnostic
    confidence/weakness maps, but frozen-test transfer is insufficient for
    wording or production wiring.
  - JMA-style explains the `kanto_chubu` attenuation/recall failure and must be
    revised as a model-family problem, not patched by confidence wording.
  - PLUM `r30/d0.50` explains the `tohoku` PLUM-only false-positive branch, but
    the latest minor-event pooled check finds no stable runtime-visible family
    score after dominant-event removal.
  - All of these remain validation/frozen diagnostics only:
    no raw intensity mutation, no suppression gate, no UI wording, and no
    notification wiring.
- Current next work returns to data coverage rather than another small-bucket
  tuning pass. Add more real high-shindo local captures and formally tagged
  JMA/Hi-net references, then rerun the existing replay/frozen diagnostics only
  after the sample pool changes materially.
- The current replay coverage gap is tracked by
  [`docs/baselines/plum_replay_capture_gap.generated.md`](baselines/plum_replay_capture_gap.generated.md):
  7 replay cases scanned, 6 complete, 1 gap case, 16 failed GIFs. The sole gap
  is `20260626_yamanashi_east_fuji_five_lakes_m33_jma_equake8`; it must remain
  outside complete replay lead-time metrics until repaired, explicitly
  excluded, or replaced by another complete high-shindo capture.
