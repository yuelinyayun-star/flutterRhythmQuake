# 工作交接单 — 2026-06-28 PLUM 证据稳健性校准(非抑制型)

## 任务背景

延续上一轮 GPT 的"非抑制型 mask/evidence robustness scoring"方向。
上一轮已交付**边际分层报告**(单特征 bucket 看 precision),本轮在其上补
**联合校准表**(`branchAgreement × robustnessScore` 联合 bucket → 经验
precision → 置信带),仍保持非抑制型:不改预测震度、不阻断预测、不接
UI/通知/wording。

## 本轮所做内容

### 1. 验证上一轮交付物(状态确认)

| 项 | 路径 | 结果 |
| --- | --- | --- |
| 工具 | [tools/build_plum_evidence_robustness_report.dart](../tools/build_plum_evidence_robustness_report.dart) | `dart analyze` 通过 |
| 测试 | [test/plum_evidence_robustness_report_test.dart](../test/plum_evidence_robustness_report_test.dart) | 1 测试通过 |
| 报告 | [docs/baselines/plum_evidence_robustness.generated.md](baselines/plum_evidence_robustness.generated.md) | 185694 forecasts, pass |
| 文档 | [source_estimation_roadmap.md](source_estimation_roadmap.md) 章节 `## 2026-06-28 PLUM Evidence Robustness Diagnostic` | 已存在(行 5429-5485) |

### 2. 新增:联合校准报告(本轮主体)

| 项 | 路径 | 内容 / 结果 |
| --- | --- | --- |
| 工具 | [tools/build_plum_evidence_robustness_calibration_report.dart](../tools/build_plum_evidence_robustness_calibration_report.dart) | 联合 bucket 校准 + 置信带映射;`dart analyze` 通过 |
| 测试 | [test/plum_evidence_robustness_calibration_report_test.dart](../test/plum_evidence_robustness_calibration_report_test.dart) | 断言非抑制型 policy + 联合 bucket + 4 带 band 标签;1 测试通过 |
| 报告 | [docs/baselines/plum_evidence_robustness_calibration.generated.md](baselines/plum_evidence_robustness_calibration.generated.md) | 185694 forecasts, status `pass` |
| 文档 | [source_estimation_roadmap.md](source_estimation_roadmap.md) 章节 `## 2026-06-28 PLUM Evidence Robustness Calibration Diagnostic` | 行 5487-5594 |

### 3. 新增:wording-only 验收标准(C1-C4 + F1-F4)

| 项 | 路径 | 内容 |
| --- | --- | --- |
| 文档 | [source_estimation_roadmap.md](source_estimation_roadmap.md) 章节 `## 2026-06-28 PLUM Robustness Confidence-Band Wording-Only Acceptance Criteria` | 行 5596-5693 |

要点:
- **C1-C4**(validation 自洽):band 单调性、high 带精度底线、low 带隔离、high 带覆盖率底线。validation 表已自洽通过。
- **F1-F4**(frozen 一次性验收,预注册容差,看到结果前定死):
  - `F1_band_monotonicity`:frozen P(high)>P(medium)>P(low)
  - `F2_high_precision_hold`:frozen P(high) ≥ validation P(high) − 5pp
  - `F3_no_collapse_{high,medium,low}`:frozen P(band) ≥ validation P(band) − 15pp
  - `F4_coverage_hold`:frozen share(high+medium) ≥ 50% × validation share(high+medium)
- 容差常量在 [tools/build_plum_confidence_band_frozen_evaluation_report.dart](../tools/build_plum_confidence_band_frozen_evaluation_report.dart) 顶部硬编码,带中文注释标明"不得事后调整"。

### 4. 新增:一次性 frozen 评估(shindo4)

| 项 | 路径 | 内容 / 结果 |
| --- | --- | --- |
| 工具 | [tools/build_plum_confidence_band_frozen_evaluation_report.dart](../tools/build_plum_confidence_band_frozen_evaluation_report.dart) | 一次性 frozen 评估;进程内重建 validation 校准表 → band 标签查表(不在 test 上重算);`dart analyze` 通过 |
| 测试 | [test/plum_confidence_band_frozen_evaluation_report_test.dart](../test/plum_confidence_band_frozen_evaluation_report_test.dart) | 8 分钟超时;断言 schema、policy(oneShot/frozen/non-suppressive)、F1-F4 检查键、outcome 字段;1 测试通过 |
| 报告 | [docs/baselines/plum_confidence_band_frozen_evaluation.generated.md](baselines/plum_confidence_band_frozen_evaluation.generated.md) | 179844 forecasts;status `pass`(工具跑通)/ outcome `fail`(F1-F4 未全过) |
| 文档 | [source_estimation_roadmap.md](source_estimation_roadmap.md) 章节 `## 2026-06-28 PLUM Confidence-Band One-Shot Frozen Evaluation (shindo4)` | 行 5695-5778 |

### 5. 关键校准成果

`shindo4`(基线 P 55.9%):

| Band | Buckets | Pred+ | Precision |
| --- | ---: | ---: | ---: |
| high | 3 | 2635 | 82.2% |
| medium | 1 | 1156 | 62.5% |
| low | 5 | 2993 | 30.2% |
| insufficient | 6 | 55 | 60.0% |

`shindo5-`(基线 P 58.8%):

| Band | Buckets | Pred+ | Precision |
| --- | ---: | ---: | ---: |
| high | 1 | 44 | 86.4% |
| medium | 3 | 445 | 66.7% |
| low | 2 | 267 | 38.6% |
| insufficient | 5 | 25 | 84.0% |

要点:
- `agree_3/score_7` 在两个阈值都进 high 带(shindo4 82.6%、shindo5- 86.4%)。
- `agree_1` 行几乎全是 low 带,是未来 wording 层挂"低置信"标签的目标格。
- 联合表比边际表分离更锐:shindo4 high 带 82.2% vs low 带 30.2%,同一 split 同一 raw intensity。

### 6. 关键 frozen 评估结果(shindo4,一次性)

**Outcome: `fail`**(F1-F4 未全过;工具 status `pass`,即评估流程本身跑通)。

| Band | Validation P | Frozen P | Δ | Frozen Pred+ |
| --- | ---: | ---: | ---: | ---: |
| high | 82.2% | 54.3% | **−27.9pp** | 782 |
| medium | 62.5% | 42.6% | −19.9pp | 2605 |
| low | 30.2% | 28.9% | −1.3pp | 2795 |
| insufficient | 60.0% | 42.5% | −17.5pp | 106 |

F1-F4 检查结果:

| Check | Status | Actual | Required |
| --- | --- | ---: | ---: |
| `F1_band_monotonicity` | `pass` | 54.3% > 42.6% > 28.9% | P(high)>P(medium)>P(low) |
| `F2_high_precision_hold` | `fail` | 54.3% | ≥ 82.2% − 5pp = 77.2% |
| `F3_no_collapse_high` | `fail` | 54.3% | ≥ 82.2% − 15pp = 67.2% |
| `F3_no_collapse_medium` | `fail` | 42.6% | ≥ 62.5% − 15pp = 47.5% |
| `F3_no_collapse_low` | `pass` | 28.9% | ≥ 30.2% − 15pp = 15.2% |
| `F4_coverage_hold` | `pass` | 53.9% | ≥ 50% × 55.4% = 27.7% |

关键解读:
- **F1 单调性保持**:band 的相对排序在 frozen test 上仍有效,band 校准本身有泛化能力。
- **F2/F3 high&medium 崩**:high 带 precision 从 82.2% 掉到 54.3%(−27.9pp),而 low 带只掉 1.3pp。说明 validation 的 high 带部分依赖 validation-specific 模式,frozen 上无法保持。
- **根本阻塞不是 band 校准**:frozen baseline(纯 raw intensity,无 band)的 precision 已从 validation 55.9% 掉到 38.0%(−17.9pp)。band 的 high 带精度掉的更狠,是因为它放大了 raw intensity 的 frozen 回归。
- **shindo5- 不重做**:validation 阶段已 C4 coverage block,无 frozen 必要。

## 与已有报告的定位差异

| 报告 | 类型 | 作用 |
| --- | --- | --- |
| `plum_confidence_gate` | 门控选择器 | 评估多候选 gate,选一个进 replay(二值决策) |
| `plum_evidence_robustness`(上一轮) | 边际分层 | 单特征 bucket 看 precision |
| `plum_evidence_robustness_calibration`(本轮) | 联合校准表 | 联合 bucket → 经验 precision → 置信带 |
| `plum_confidence_band_frozen_evaluation`(本轮) | 一次性 frozen 验收 | 用 validation band 查表,在 test 上检查 F1-F4;**fail,阻断 UI wording** |

## 当前边界(明确)

- 非抑制型:`rawPredictedIntensityMutated=false`、`productionReady=false`、
  `diagnosticOnly=true`、`frozenTestEvaluated=true`(shindo4 已一次性评估,
  不可重跑调参后再次评估)。
- 不改预测震度、不阻断预测、**不接 UI/通知/wording**(frozen fail 已 block)。
- 生产仍阻断。
- **confidence band 降级为 validation-only diagnostic**,不进 wording 层。
- shindo5-:validation C4 coverage 已 block,无 frozen 评估必要。

## 复现命令

```powershell
# 校准表(validation 联合 bucket → 置信带)
dart analyze tools\build_plum_evidence_robustness_calibration_report.dart test\plum_evidence_robustness_calibration_report_test.dart
flutter test test\plum_evidence_robustness_calibration_report_test.dart
dart run tools\build_plum_evidence_robustness_calibration_report.dart

# 一次性 frozen 评估(预注册 F1-F4,不可重跑调参)
dart analyze tools\build_plum_confidence_band_frozen_evaluation_report.dart test\plum_confidence_band_frozen_evaluation_report_test.dart
flutter test test\plum_confidence_band_frozen_evaluation_report_test.dart
dart run tools\build_plum_confidence_band_frozen_evaluation_report.dart
```

## 续:Region/Site Calibration(A1 方向)

frozen 评估收口后,继续执行 [frozen regression drilldown](baselines/plum_frozen_regression_drilldown.generated.md)
列出的 4 个 validation-only guard 候选中的最后一个:**region/site-amplification
calibration**。前 3 个已处理(local-contrast reject、strong-evidence shape
reject、mask/evidence robustness frozen fail)。

### 7. 新增:region/site calibration(本轮续)

| 项 | 路径 | 内容 / 结果 |
| --- | --- | --- |
| 工具 | [tools/build_plum_region_site_calibration_report.dart](../tools/build_plum_region_site_calibration_report.dart) | region(估计震源纬度带)× site(站点纬度带)联合校准;非抑制型;`dart analyze` 通过 |
| 测试 | [test/plum_region_site_calibration_report_test.dart](../test/plum_region_site_calibration_report_test.dart) | 断言非抑制型 policy + region/site/joint buckets + band 标签合法;1 测试通过 |
| 报告 | [docs/baselines/plum_region_site_calibration.generated.md](baselines/plum_region_site_calibration.generated.md) | 185694 forecasts, status `pass` |
| 文档 | [source_estimation_roadmap.md](source_estimation_roadmap.md) 章节 `## 2026-06-28 PLUM Region/Site Calibration Diagnostic` | 行 5780-5908 |

### 8. 关键 region/site 校准结果

**shindo4**(基线 P 55.9%):**无 high 带**,分离力弱于 evidence robustness calibration。

| Band | Buckets | Pred+ | Precision |
| --- | ---: | ---: | ---: |
| high | 0 | 0 | - |
| medium | 1 | 1698 | 65.7% |
| low | 4 | 5140 | 52.7% |
| insufficient | 1 | 1 | 100.0% |

- 唯一 medium:`tohoku × kanto_chubu` 65.7%(震源在东北、站点在关东甲信)
- 同区域组合全是 low:`kanto_chubu × kanto_chubu` 53.5%、`tohoku × tohoku` 54.9%、`west_south × west_south` 21.8%、`hokkaido × hokkaido` 2.1%
- `hokkaido × hokkaido` 2.1%(47 FP / 1 TP),几乎全误报,台站稀疏导致 PLUM 传播失真

**shindo5-**(基线 P 58.8%):有 high 带,但很窄。

| Band | Buckets | Pred+ | Precision |
| --- | ---: | ---: | ---: |
| high | 1 | 126 | 79.4% |
| medium | 1 | 447 | 72.0% |
| low | 1 | 205 | 18.0% |
| insufficient | 1 | 3 | 0.0% |

- 唯一 high:`tohoku × kanto_chubu` 79.4%(与 shindo4 的 medium 是同一格)
- `kanto_chubu × kanto_chubu` 从 shindo4 的 53.5% 掉到 18.0%

### 9. 与 evidence robustness calibration 对比

| 校准表 | shindo4 high P | shindo4 low P | 分离度 |
| --- | ---: | ---: | ---: |
| evidence robustness(branchAgreement × robustnessScore) | 82.2% | 30.2% | 52.0 pp |
| region/site(region × site) | 无 | 52.7% | 13.0 pp(medium vs low) |

- evidence robustness 分离更锐(52.0 pp vs 13.0 pp),branchAgreement/robustnessScore 比纬度带更有区分力
- region/site 补充了 evidence robustness 没有的信息:**地理弱点定位**
- `kanto_chubu` region validation precision 53.5% 正是 frozen test 上 F1 drop 最严重区域(−46.0pp)的先兆 — frozen 回归在 validation 的 region/site 表里就能看到,而 robustness 表没标出

### 10. drilldown 4 候选最终状态

| 候选 | 状态 | 原因 |
| --- | --- | --- |
| local-contrast guard | reject | replay recall loss too large(行 5310-5313) |
| strong-evidence shape guard | reject | 无 F1 改进(行 5413-5417) |
| mask/evidence robustness calibration | frozen fail | high 带 −27.9pp collapse(行 5748-5764) |
| region/site calibration | validation-only,无 high 带(shindo4) | 分离力弱,不进 wording |

**4 个候选全部完成,无一产出 production-ready wording 层。** confidence band 方向彻底收口。

## 续:Raw Intensity Frozen Source Diagnostic(spec 驱动)

confidence band 方向收口后,根据 roadmap 的 Next action 推进根本阻塞:
**改进 raw intensity 的 frozen 迁移**(baseline 55.9% → 38.0%)。第一步是
prerequisite 诊断 — 分解 baseline drop 到 JMA-style vs PLUM r30/d0.50 各自
的贡献。已通过 spec 模式实现(change-id: `raw-intensity-frozen-source-diagnostic`)。

### 11. 新增:raw intensity frozen source diagnostic(spec 驱动)

| 项 | 路径 | 内容 / 结果 |
| --- | --- | --- |
| spec | [.trae/specs/raw-intensity-frozen-source-diagnostic/spec.md](../.trae/specs/raw-intensity-frozen-source-diagnostic/spec.md) + tasks.md + checklist.md | 已批准并实现 |
| 工具 | [tools/build_raw_intensity_frozen_source_diagnostic_report.dart](../tools/build_raw_intensity_frozen_source_diagnostic_report.dart) | 三组件(jmaStyle/plumR30D050/baselineMax)× 两 split(validation/test)P/R/F1 + region/distance 分桶 + FP 触发源分解;非抑制型;`dart analyze` 通过 |
| 测试 | [test/raw_intensity_frozen_source_diagnostic_report_test.dart](../test/raw_intensity_frozen_source_diagnostic_report_test.dart) | 8 分钟超时,真实数据;断言非抑制型 policy + 三组件 × 两 split 结构 + FP 触发源;1 测试通过 |
| 报告 | [docs/baselines/raw_intensity_frozen_source_diagnostic.generated.md](baselines/raw_intensity_frozen_source_diagnostic.generated.md) | validation 185694 + test 179844 forecasts, status `pass` |
| 文档 | [source_estimation_roadmap.md](source_estimation_roadmap.md) 章节 `## 2026-06-28 Raw Intensity Frozen Source Diagnostic` | 行 5910-6060 |

### 12. 关键 source diagnostic 结果

**shindo4 precision delta(test − validation)**:

| 组件 | Validation P | Test P | Delta |
| --- | ---: | ---: | ---: |
| **jmaStyle** | 56.5% | 27.7% | **−28.7%(largest drop)** |
| plumR30D050 | 69.7% | 43.0% | −26.7% |
| baselineMax | 55.9% | 38.0% | −17.9% |

- **largestDropComponent = `jmaStyle`**。baseline drop(−17.9pp)比两个组件都小,
  因为 max 组合摊薄了 FP。
- jmaStyle recall 也崩:51.0% → 9.3%。

**shindo4 kanto_chubu region(地理热点)**:

| 组件 | validation | test | delta |
| --- | ---: | ---: | ---: |
| **jmaStyle** | 49.0% | 3.6% | **−45.4pp(掉最狠)** |
| plumR30D050 | 65.1% | 26.6% | −38.5pp |
| baselineMax | 53.5% | 11.8% | −41.7pp |

- kanto_chubu 的 drop 主要由 JMA-style 驱动(−45.4pp),与 frozen regression
  diagnostic 定位的 kanto_chubu F1 −46.0pp 一致。source diagnostic 进一步
  把锅指向 JMA-style 衰减分支。

**shindo4 FP 触发源分解**:

| Split | jma_only | plum_only | both |
| --- | ---: | ---: | ---: |
| validation | 1572 | 940 | 503 |
| test | 894 | **2886** | 119 |

- test 上 baseline FP **74% 由 PLUM 单独触发**(2886/3899),validation 只 31%。
  PLUM r30/d0.50 在 test 上的 specificity 比 validation 差很多。
- `both` 从 503 暴跌到 119,与 JMA recall 崩一致。

**shindo5- 关键结果**:
- jmaStyle test 上几乎不预测(recall 0%,仅 2 个预测正例),baseline 在 shindo5-
  量级实际上是 PLUM-only
- shindo5- baseline FP **99.6% 由 PLUM 单独触发**(913/915)

### 13. 综合诊断结论(三个校准表的汇总)

| 诊断 | 揭示的问题 | 指向 |
| --- | --- | --- |
| evidence robustness calibration | branchAgreement/robustnessScore 分离力强,但 frozen fail | confidence band 不进 wording |
| region/site calibration | kanto_chubu validation precision 53.5% 是 frozen 回归先兆 | 地理弱点定位 |
| **raw intensity source diagnostic(本轮)** | **kanto_chubu drop 主因 JMA-style(−45.4pp);test FP 74% 由 PLUM 单独触发** | **raw intensity 模型族修订方向** |

三个诊断表互补:evidence robustness 说"band 不进 wording";region/site 说
"地理弱点在 kanto_chubu";source diagnostic 说"kanto_chubu 的锅主要在
JMA-style,test 的 FP 主要在 PLUM"。

## 下一步

raw intensity source diagnostic 已完成,根本阻塞的源头已定位。根据
[source_estimation_roadmap.md](source_estimation_roadmap.md) 行 6041-6055
的 Next action,后续优先级:

1. **JMA-style 衰减在 kanto_chubu 的泛化问题**(优先级 1):
   jmaStyle 在 kanto_chubu 掉 −45.4pp 最狠,且 recall 从 51.0% 崩到 9.3%。
   未来 raw-intensity 模型族修订应优先改进 JMA-style 衰减在 kanto_chubu
   的泛化,再考虑重试 confidence-band wording 层。
2. **PLUM r30/d0.50 在 test 上的 specificity 问题**(优先级 2):
   shindo4 test FP 74%、shindo5- test FP 99.6% 由 PLUM 单独触发。PLUM 参数
   调整不在此诊断范围内,但是 raw-intensity 修订的第二优先级。
3. **JMA-style recall 崩塌是独立问题**:shindo4 recall 51.0% → 9.3%,
   必须先解决才能让 JMA-style 作为 baseline 的高 recall 分支。
4. **所有 calibration 表保持 validation-only diagnostic**:不接 UI/wording。
5. **shindo5- 不重做 frozen**:validation C4 coverage block 仍在。

相关参考文档(已读完,本轮未复用其 wording,因 frozen fail):
- [docs/baselines/plum_frozen_test_acceptance_criteria.generated.md](baselines/plum_frozen_test_acceptance_criteria.generated.md)
- [docs/baselines/source_confidence_wording_boundary.generated.md](baselines/source_confidence_wording_boundary.generated.md)
- [docs/baselines/plum_operating_point_acceptance.generated.md](baselines/plum_operating_point_acceptance.generated.md)

## Codex 接续: JMA-style Kanto/Chubu Attenuation Diagnostic

在本交接单基础上已继续推进优先级 1:拆解 JMA-style 衰减在
`kanto_chubu` 的泛化问题。

新增内容:

| 项 | 路径 | 内容 / 结果 |
| --- | --- | --- |
| 工具 | [tools/build_jma_style_kanto_chubu_attenuation_diagnostic_report.dart](../tools/build_jma_style_kanto_chubu_attenuation_diagnostic_report.dart) | 对 `kanto_chubu` estimated-source 样本比较 `estimatedSourceJma` 与 `oracleSourceJma`,并按 source-error/distance/depth/magnitude/ARV 分桶;非抑制型;`dart analyze` 通过 |
| 测试 | [test/jma_style_kanto_chubu_attenuation_diagnostic_report_test.dart](../test/jma_style_kanto_chubu_attenuation_diagnostic_report_test.dart) | 真实数据,8 分钟超时;断言非生产 policy、validation/test 结构、估计震源/真值震源分支与 bucket schema;1 测试通过 |
| 报告 | [docs/baselines/jma_style_kanto_chubu_attenuation_diagnostic.generated.md](baselines/jma_style_kanto_chubu_attenuation_diagnostic.generated.md) | validation 1067 variants / 84634 station forecasts; test 978 variants / 88879 station forecasts;status `pass` |
| 文档 | [source_estimation_roadmap.md](source_estimation_roadmap.md) 章节 `## 2026-06-28 JMA-Style Kanto/Chubu Attenuation Diagnostic` | 已追加 |

关键结论:

- `shindo4` estimated-source JMA-style:
  - validation: precision 49.0%, recall 25.7%, F1 33.7%
  - test: precision 3.6%, recall 4.7%, F1 4.1%
- `shindo4` oracle-source JMA-style:
  - validation: precision 92.3%, recall 11.9%, F1 21.1%
  - test: precision 28.6%, recall 3.0%, F1 5.4%
- 解释:真值震源能显著减少 FP,但不能恢复 frozen precision。问题不是单纯
  source-location error;JMA-style 衰减/样本迁移本身在 `kanto_chubu` 不泛化。
- estimated-source test FP 主要集中在 source-error `gt_200km` 桶:502 FP / 3 TP。
- 近距离桶也崩:`030_060km` test precision 2.7%,`060_100km` test precision
  0.7%,说明还要看 local/near-field threshold crossing,不是只看远场。
- ARV default 不是主因:`default_arv` 样本极少;FP 集中在 `gte_1_2`
  amplification 桶。
- `shindo5-` 在这个 drilldown 里 JMA-style estimated-source 没有正预测,
  继续支持“shindo5- frozen test 基本是 PLUM-only”的结论。

边界:

- 仍是 diagnostic-only。
- 不改 raw predicted intensity。
- 不接 UI/wording/通知。
- 不调参,不重跑 confidence-band frozen evaluation。

下一步更新:

1. JMA-style:优先检查/修订 `kanto_chubu` M5-class local/near-field 衰减族,
   重点看 source-error `gt_200km` 和 distance `030_060km` / `060_100km`
   threshold crossing。
2. PLUM:另开 specificity 诊断线,因为 baseline frozen FP 仍大量来自
   PLUM-only trigger。

## Codex 接续: PLUM r30/d0.50 Specificity Frozen Diagnostic

在 JMA-style `kanto_chubu` drilldown 后,继续推进优先级 2:拆解 PLUM
r30/d0.50 在 frozen test 上的 specificity 问题。

新增内容:

| 项 | 路径 | 内容 / 结果 |
| --- | --- | --- |
| spec | [.trae/specs/plum-specificity-frozen-diagnostic/spec.md](../.trae/specs/plum-specificity-frozen-diagnostic/spec.md) + tasks.md + checklist.md | 已完成 |
| 工具 | [tools/build_plum_specificity_frozen_diagnostic_report.dart](../tools/build_plum_specificity_frozen_diagnostic_report.dart) | validation/test 两 split 的 PLUM r30/d0.50 specificity、FPR、PLUM-only FP、region/distance/mask/evidence/margin 分桶;非抑制型;`dart analyze` 通过 |
| 测试 | [test/plum_specificity_frozen_diagnostic_report_test.dart](../test/plum_specificity_frozen_diagnostic_report_test.dart) | 真实数据,8 分钟超时;断言非生产 policy、split 结构、specificity 指标和 bucket schema;1 测试通过 |
| 报告 | [docs/baselines/plum_specificity_frozen_diagnostic.generated.md](baselines/plum_specificity_frozen_diagnostic.generated.md) | validation 2688 variants / 185694 forecasts; test 2757 variants / 179844 forecasts;status `pass` |
| 文档 | [source_estimation_roadmap.md](source_estimation_roadmap.md) 章节 `## 2026-06-28 PLUM Specificity Frozen Diagnostic` | 已追加 |

关键结论:

- `shindo4` PLUM r30/d0.50:
  - validation precision 69.7%, recall 62.8%, specificity 99.2%, FP 1443
  - test precision 43.0%, recall 54.3%, specificity 98.3%, FP 3005
  - PLUM-only FP:940 -> 2886
- `shindo5-` PLUM r30/d0.50:
  - validation precision 58.1%, recall 45.5%, specificity 99.8%, FP 321
  - test precision 26.5%, recall 38.1%, specificity 99.5%, FP 913
  - PLUM-only FP:311 -> 913
- Specificity 百分比下降看起来小,但负类基数巨大,所以 FP 数量翻倍才是产品风险。
- PLUM 的主热点不是 JMA-style 的 `kanto_chubu`:
  - `shindo4` test `tohoku`:2565 FP / 2496 PLUM-only FP
  - `kanto_chubu`:270 FP / 267 PLUM-only FP
- 最坏证据桶不是"证据少",而是"证据很多":
  - `shindo4` test evidenceCount `gte_8`:2824 FP / 2723 PLUM-only FP
  - `shindo5-` test evidenceCount `gte_8`:887 FP / 887 PLUM-only FP
- 最近证据也不是缺失:
  - `shindo4` test nearestEvidence `000_010km`:2573 FP / 2474 PLUM-only FP
  - `shindo5-` test nearestEvidence `000_010km`:842 FP / 842 PLUM-only FP
- prediction margin 显示不是单纯阈值边缘噪声:
  - `shindo4` test margin `gte_100`:663 FP,validation 只有 92

边界:

- 仍是 diagnostic-only。
- 不调 PLUM radius/damping。
- 不抑制、不改 raw predicted intensity。
- 不接 UI/wording/通知。

下一步更新:

1. 不要用简单 evidence-count 置信规则,因为 worst FP bucket 是
   `evidenceCount=gte_8`。
2. 优先做 `tohoku` strong-nearby-evidence propagation-shape 诊断,特别是
   margin `>=1.0` shindo 的 FP。
3. 如果未来要比较 radius/damping,必须走 validation-first spec,不要复用已
   spent 的 confidence-band frozen wording 路径。
## Codex Continuation: PLUM Tohoku Strong-Nearby-Evidence Propagation-Shape Diagnostic

After the PLUM specificity frozen diagnostic, the next documented action was to
inspect the frozen-test `tohoku` hotspot without changing PLUM parameters or
adding a suppression rule. That continuation is now implemented.

Added artifacts:

| Item | Path | Notes |
| --- | --- | --- |
| spec | [.trae/specs/plum-tohoku-propagation-shape-diagnostic/spec.md](../.trae/specs/plum-tohoku-propagation-shape-diagnostic/spec.md) + tasks.md + checklist.md | Completed |
| tool | [tools/build_plum_tohoku_propagation_shape_diagnostic_report.dart](../tools/build_plum_tohoku_propagation_shape_diagnostic_report.dart) | validation/test split drilldown for `tohoku + gte_8 evidence + 000_010km nearest + margin>=1.0`; diagnostic-only |
| test | [test/plum_tohoku_propagation_shape_diagnostic_report_test.dart](../test/plum_tohoku_propagation_shape_diagnostic_report_test.dart) | 8-minute timeout; asserts non-production policy, focus filter, split structure, feature aggregates, and markdown sections |
| report | [docs/baselines/plum_tohoku_propagation_shape_diagnostic.generated.md](baselines/plum_tohoku_propagation_shape_diagnostic.generated.md) | validation 2688 variants / 185694 forecasts; test 2757 variants / 179844 forecasts; status `pass` |
| document | [source_estimation_roadmap.md](source_estimation_roadmap.md) section `## 2026-06-28 PLUM Tohoku Propagation-Shape Diagnostic` | Added |

Key findings:

- `shindo4` focus subset:
  - validation: 457 samples, 389 TP, 68 FP, precision 85.1%
  - test: 1051 samples, 458 TP, 593 FP, precision 43.6%
  - test PLUM-only FP inside focus subset: 549
- `shindo5-` focus subset:
  - validation: 28 samples, 26 TP, 2 FP, precision 92.9%
  - test: 40 samples, 10 TP, 30 FP, precision 25.0%
  - test PLUM-only FP inside focus subset: 30
- The hotspot is real, but the hoped-for separator is weak:
  production-available support geometry overlaps heavily between TP and FP on
  the frozen test.
  - `shindo4` support count TP/FP: `12.88 / 12.83`
  - quadrant coverage TP/FP: `2.28 / 2.31`
  - centroid offset TP/FP: `10.53 km / 10.24 km`
  - max spread TP/FP: `28.15 km / 28.43 km`
- What separates TP and FP more clearly is diagnostic-only outcome mismatch,
  not evidence geometry:
  - `shindo4` evidence-target gap TP/FP: `0.85 / 3.84`
  - `shindo5-` evidence-target gap TP/FP: `0.46 / 3.79`

Boundary:

- still diagnostic-only;
- no PLUM radius/damping tuning;
- no suppression gate;
- no mutation of raw predicted intensity;
- no UI/wording/notification connection.

Updated next step:

1. Do **not** turn quadrant/spread/centroid geometry into a hard suppression
   rule; TP/FP overlap is too high in the frozen-test hotspot.
2. Continue with non-suppressive robustness scoring or region/site calibration
   for `tohoku` strong-nearby-evidence cases.
3. Keep confidence/wording/UI disconnected.

## Codex Continuation: PLUM Tohoku Focus Robustness Frozen Diagnostic

After the propagation-shape drilldown, the next question was whether the
existing production-available robustness table still transfers inside the
`tohoku` hotspot. That continuation is now implemented.

Added artifacts:

| Item | Path | Notes |
| --- | --- | --- |
| spec | [.trae/specs/plum-tohoku-focus-robustness-frozen-diagnostic/spec.md](../.trae/specs/plum-tohoku-focus-robustness-frozen-diagnostic/spec.md) + tasks.md + checklist.md | Completed |
| tool | [tools/build_plum_tohoku_focus_robustness_frozen_diagnostic_report.dart](../tools/build_plum_tohoku_focus_robustness_frozen_diagnostic_report.dart) | validation-defined `branchAgreement x robustnessScore` buckets projected to frozen test inside the `tohoku` focus subset |
| test | [test/plum_tohoku_focus_robustness_frozen_diagnostic_report_test.dart](../test/plum_tohoku_focus_robustness_frozen_diagnostic_report_test.dart) | 8-minute timeout; asserts non-production policy, focus filter, transfer structure, and `shindo4` precision degradation |
| report | [docs/baselines/plum_tohoku_focus_robustness_frozen_diagnostic.generated.md](baselines/plum_tohoku_focus_robustness_frozen_diagnostic.generated.md) | validation 2688 variants / 185694 forecasts; test 2757 variants / 179844 forecasts; status `pass` |
| document | [source_estimation_roadmap.md](source_estimation_roadmap.md) section `## 2026-06-28 PLUM Tohoku Focus Robustness Frozen Diagnostic` | Added |

Key findings:

- Focus baseline still collapses:
  - `shindo4`: `85.1% -> 43.6%`
  - `shindo5-`: `92.9% -> 25.0%`
- Existing robustness buckets do **not** transfer:
  - `shindo4` projected `high` band: `85.1% -> 47.4%`
  - `shindo5-` projected `high` band: `100.0% -> 25.0%`
- The largest test mass lands where validation had almost no coverage:
  - `shindo4` validation `agree_2 / score_6`: `2` samples, `100%`,
    `insufficient`
  - same bucket on test: `839` samples, `43.1%`
- Conclusion: current production-available robustness features are not stable
  enough to become the next confidence layer inside the `tohoku` hotspot.

Boundary:

- still diagnostic-only;
- no PLUM radius/damping tuning;
- no suppression gate;
- no mutation of raw predicted intensity;
- no UI/wording/notification connection.

Updated next step:

1. Do **not** continue with the current generic `branchAgreement x
   robustnessScore` table for `tohoku` hotspot confidence.
2. Shift to focus-specific `region/site` or related production-available
   calibration features for `tohoku` strong-nearby-evidence cases.
3. Keep confidence/wording/UI disconnected until that transfer problem is
   solved.

## Codex Continuation: PLUM Tohoku Focus Region-Site Frozen Diagnostic

After the focus robustness frozen diagnostic, the next check was whether the
existing coarse `region/site` geography transfers any better inside the same
hotspot. That continuation is now implemented.

Added artifacts:

| Item | Path | Notes |
| --- | --- | --- |
| spec | [.trae/specs/plum-tohoku-focus-region-site-frozen-diagnostic/spec.md](../.trae/specs/plum-tohoku-focus-region-site-frozen-diagnostic/spec.md) + tasks.md + checklist.md | Completed |
| tool | [tools/build_plum_tohoku_focus_region_site_frozen_diagnostic_report.dart](../tools/build_plum_tohoku_focus_region_site_frozen_diagnostic_report.dart) | validation-defined region/site buckets projected to frozen test inside the `tohoku` focus subset |
| test | [test/plum_tohoku_focus_region_site_frozen_diagnostic_report_test.dart](../test/plum_tohoku_focus_region_site_frozen_diagnostic_report_test.dart) | 8-minute timeout; asserts non-production policy, focus filter, transfer structure, and `shindo4` degradation |
| report | [docs/baselines/plum_tohoku_focus_region_site_frozen_diagnostic.generated.md](baselines/plum_tohoku_focus_region_site_frozen_diagnostic.generated.md) | validation 2688 variants / 185694 forecasts; test 2757 variants / 179844 forecasts; status `pass` |
| document | [source_estimation_roadmap.md](source_estimation_roadmap.md) section `## 2026-06-28 PLUM Tohoku Focus Region-Site Frozen Diagnostic` | Added |

Key findings:

- Focus baseline still collapses:
  - `shindo4`: `85.1% -> 43.6%`
  - `shindo5-`: `92.9% -> 25.0%`
- Coarse `region/site` does **not** rescue transfer:
  - `shindo4` `tohoku -> tohoku`: `83.4% -> 43.8%`
  - `shindo4` `tohoku -> kanto_chubu`: `92.1% -> 42.9%`
  - `shindo5-` `tohoku -> tohoku`: `90.0% -> 25.0%`
- Every populated `shindo4` validation bucket is labeled `high`, but all of
  them collapse together on test. So the current latitude-band geography is
  too coarse for this hotspot.

Boundary:

- still diagnostic-only;
- no PLUM radius/damping tuning;
- no suppression gate;
- no mutation of raw predicted intensity;
- no UI/wording/notification connection.

Updated next step:

1. Do **not** reuse the current coarse latitude-band `region/site` table for
   `tohoku` hotspot confidence.
2. Move to finer production-available geography:
   `tohoku` source sub-bands, offshore-distance/site combinations, or similar
   partitions that can separate offshore propagation structure better.
3. Keep confidence/wording/UI disconnected until that finer partition proves
   stable on frozen transfer.

## Codex Continuation: PLUM Tohoku Focus Distance-Site Frozen Diagnostic

After the coarse focus `region/site` diagnostic, the next refinement was the
documented offshore-distance/site combination. That continuation is now
implemented.

Added artifacts:

| Item | Path | Notes |
| --- | --- | --- |
| spec | [.trae/specs/plum-tohoku-focus-distance-site-frozen-diagnostic/spec.md](../.trae/specs/plum-tohoku-focus-distance-site-frozen-diagnostic/spec.md) + tasks.md + checklist.md | Completed |
| tool | [tools/build_plum_tohoku_focus_distance_site_frozen_diagnostic_report.dart](../tools/build_plum_tohoku_focus_distance_site_frozen_diagnostic_report.dart) | validation-defined distance-site buckets projected to frozen test inside the `tohoku` focus subset |
| test | [test/plum_tohoku_focus_distance_site_frozen_diagnostic_report_test.dart](../test/plum_tohoku_focus_distance_site_frozen_diagnostic_report_test.dart) | 8-minute timeout; asserts non-production policy, focus filter, transfer structure, and `shindo4` degradation |
| report | [docs/baselines/plum_tohoku_focus_distance_site_frozen_diagnostic.generated.md](baselines/plum_tohoku_focus_distance_site_frozen_diagnostic.generated.md) | validation 2688 variants / 185694 forecasts; test 2757 variants / 179844 forecasts; status `pass` |
| document | [source_estimation_roadmap.md](source_estimation_roadmap.md) section `## 2026-06-28 PLUM Tohoku Focus Distance-Site Frozen Diagnostic` | Added |

Key findings:

- Focus baseline still collapses:
  - `shindo4`: `85.1% -> 43.6%`
  - `shindo5-`: `92.9% -> 25.0%`
- Distance helps describe the hotspot, but still does not produce a stable
  transfer:
  - `000_030km`: `74.3% -> 48.0%`
  - `030_060km`: `79.3% -> 45.5%`
  - `060_100km`: `95.9% -> 42.9%`
  - `100_200km`: `100.0% -> 37.6%`
- Projected validation `high` buckets still collapse together:
  - overall `high`: `90.3% -> 43.6%`
  - `060_100km x tohoku`: `94.4% -> 41.0%`
  - `100_200km x tohoku`: `100.0% -> 30.4%`
- Conclusion: `distance x site` is more informative than coarse `region/site`,
  but still not stable enough for hotspot confidence.

Boundary:

- still diagnostic-only;
- no PLUM radius/damping tuning;
- no suppression gate;
- no mutation of raw predicted intensity;
- no UI/wording/notification connection.

Updated next step:

1. Do **not** promote the current `distance x site` table into confidence.
2. Move to even finer production-available geography:
   `tohoku` source sub-bands, or source-sub-band x distance/site combinations.
3. Keep confidence/wording/UI disconnected until that finer partition proves
   stable on frozen transfer.

## Codex Continuation: PLUM Tohoku Focus Source-Band/Site Frozen Diagnostic

After the focus `distance/site` diagnostic, the next documented refinement was
to split the `tohoku` source region into production-available sub-bands while
keeping the existing site bands. That continuation is now implemented.

Added artifacts:

| Item | Path | Notes |
| --- | --- | --- |
| spec | [.trae/specs/plum-tohoku-focus-source-band-site-frozen-diagnostic/spec.md](../.trae/specs/plum-tohoku-focus-source-band-site-frozen-diagnostic/spec.md) + tasks.md + checklist.md | Completed |
| tool | [tools/build_plum_tohoku_focus_source_band_site_frozen_diagnostic_report.dart](../tools/build_plum_tohoku_focus_source_band_site_frozen_diagnostic_report.dart) | validation-defined source-band/site buckets projected to frozen test inside the `tohoku` focus subset |
| test | [test/plum_tohoku_focus_source_band_site_frozen_diagnostic_report_test.dart](../test/plum_tohoku_focus_source_band_site_frozen_diagnostic_report_test.dart) | 8-minute timeout; asserts non-production policy, focus filter, transfer structure, and `shindo4` degradation |
| report | [docs/baselines/plum_tohoku_focus_source_band_site_frozen_diagnostic.generated.md](baselines/plum_tohoku_focus_source_band_site_frozen_diagnostic.generated.md) | validation 2688 variants / 185694 forecasts; test 2757 variants / 179844 forecasts; status `pass` |
| document | [source_estimation_roadmap.md](source_estimation_roadmap.md) section `## 2026-06-28 PLUM Tohoku Focus Source-Band/Site Frozen Diagnostic` | Added |

Key findings:

- Focus baseline still collapses:
  - `shindo4`: `85.1% -> 43.6%`
  - `shindo5-`: `92.9% -> 25.0%`
- Hotspot mass is concentrated in `south_tohoku`, but the transfer still
  collapses:
  - `shindo4` `south_tohoku`: `84.4% -> 43.6%`
  - `shindo5-` `south_tohoku`: `92.9% -> 25.0%`
- Populated source-band/site buckets remain misleading:
  - `south_tohoku x tohoku`: `82.4% -> 43.8%`
  - `south_tohoku x kanto_chubu`: `92.1% -> 42.9%`
  - `mid_tohoku x tohoku`: validation `100.0%`, test mass `0`
- Projected validation `high` buckets still collapse together:
  - `shindo4` overall `high`: `85.1% -> 43.6%`
  - `shindo5-` overall `high`: `90.0% -> 25.0%`
- Conclusion: source sub-band explains where the hotspot mass sits, but
  `source-band x site` still does not transfer well enough for confidence.

Boundary:

- still diagnostic-only;
- no PLUM radius/damping tuning;
- no suppression gate;
- no mutation of raw predicted intensity;
- no UI/wording/notification connection.

Updated next step:

1. Do **not** promote the current `source-band x site` table into confidence.
2. Combine source sub-band with the more offshore-sensitive `distance/site`
   view, i.e. move to `source-sub-band x distance/site`.
3. Keep confidence/wording/UI disconnected until that finer partition proves
   stable on frozen transfer.

## Codex Continuation: PLUM Tohoku Focus Source-Band Distance/Site Frozen Diagnostic

After the focus `source-band/site` diagnostic, the next documented refinement
was to combine source sub-band with the more offshore-sensitive
`distance/site` view. That continuation is now implemented.

Added artifacts:

| Item | Path | Notes |
| --- | --- | --- |
| spec | [.trae/specs/plum-tohoku-focus-source-band-distance-site-frozen-diagnostic/spec.md](../.trae/specs/plum-tohoku-focus-source-band-distance-site-frozen-diagnostic/spec.md) + tasks.md + checklist.md | Completed |
| tool | [tools/build_plum_tohoku_focus_source_band_distance_site_frozen_diagnostic_report.dart](../tools/build_plum_tohoku_focus_source_band_distance_site_frozen_diagnostic_report.dart) | validation-defined source-band-distance/site buckets projected to frozen test inside the `tohoku` focus subset |
| test | [test/plum_tohoku_focus_source_band_distance_site_frozen_diagnostic_report_test.dart](../test/plum_tohoku_focus_source_band_distance_site_frozen_diagnostic_report_test.dart) | 8-minute timeout; asserts non-production policy, focus filter, transfer structure, and `shindo4` degradation |
| report | [docs/baselines/plum_tohoku_focus_source_band_distance_site_frozen_diagnostic.generated.md](baselines/plum_tohoku_focus_source_band_distance_site_frozen_diagnostic.generated.md) | validation 2688 variants / 185694 forecasts; test 2757 variants / 179844 forecasts; status `pass` |
| document | [source_estimation_roadmap.md](source_estimation_roadmap.md) section `## 2026-06-28 PLUM Tohoku Focus Source-Band Distance-Site Frozen Diagnostic` | Added |

Key findings:

- Focus baseline still collapses:
  - `shindo4`: `85.1% -> 43.6%`
  - `shindo5-`: `92.9% -> 25.0%`
- The combined geography is more descriptive, but still not transferable:
  - `south_tohoku x 000_030km x tohoku`: `70.5% -> 48.0%`
  - projected `high` overall: `90.8% -> 43.6%`
  - `south_tohoku x 030_060km x tohoku`: `79.8% -> 45.4%`
  - `south_tohoku x 060_100km x tohoku`: `94.4% -> 41.0%`
  - `south_tohoku x 100_200km x tohoku`: `100.0% -> 30.4%`
- Hotspot mass is now clearly localized:
  - test mass is effectively all `south_tohoku`
  - `mid_tohoku` is only sparse validation-only mass
  - `north_tohoku` has no material mass
- `shindo5-` remains unusable for confidence:
  - every populated bucket is `insufficient`
  - projected precision remains `25.0%`
- Conclusion: production-available geography appears exhausted for this hotspot;
  the next step should not be yet another geographic split.

Boundary:

- still diagnostic-only;
- no PLUM radius/damping tuning;
- no suppression gate;
- no mutation of raw predicted intensity;
- no UI/wording/notification connection.

Updated next step:

1. Do **not** promote the current `source-band x distance/site` table into
   confidence.
2. Stop refining geography and move to a validation-only event-family /
   propagation-family hotspot diagnostic.
3. Keep confidence/wording/UI disconnected until that non-geographic
   diagnostic finds a transferable signal.

## Codex Continuation: PLUM Tohoku Validation Event/Propagation-Family Diagnostic

After the geographic hotspot drilldowns were exhausted, the next documented
step was to switch to a strictly validation-only event/propagation-family
diagnostic. That continuation is now implemented.

Added artifacts:

| Item | Path | Notes |
| --- | --- | --- |
| spec | [.trae/specs/plum-tohoku-validation-event-family-diagnostic/spec.md](../.trae/specs/plum-tohoku-validation-event-family-diagnostic/spec.md) + tasks.md + checklist.md | Completed |
| tool | [tools/build_plum_tohoku_validation_event_family_diagnostic_report.dart](../tools/build_plum_tohoku_validation_event_family_diagnostic_report.dart) | validation-only event-level propagation signatures and family aggregates for the `tohoku` hotspot |
| test | [test/plum_tohoku_validation_event_family_diagnostic_report_test.dart](../test/plum_tohoku_validation_event_family_diagnostic_report_test.dart) | 8-minute timeout; asserts validation-only policy, family definitions, and report sections |
| report | [docs/baselines/plum_tohoku_validation_event_family_diagnostic.generated.md](baselines/plum_tohoku_validation_event_family_diagnostic.generated.md) | validation 2688 variants / 185694 forecasts; status `pass` |
| document | [source_estimation_roadmap.md](source_estimation_roadmap.md) section `## 2026-06-28 PLUM Tohoku Validation Event/Propagation-Family Diagnostic` | Added |

Key findings:

- Validation `shindo4` hotspot mass comes from only `3` events, and those
  events do separate into distinct propagation families.
- The dominant validation-positive family is strong:
  - `consistent/surrounded/wide`: `345` samples, `91.9%` precision
- The clearly weakest validation family is:
  - `mismatch/surrounded/moderate`: `90` samples, `55.6%` precision
  - event `2021032018094483-38.4680-141.6277`
  - median below-threshold local share `50.0%`
  - median quadrant coverage `3.0`
  - median max spread `30.52 km`
- Another small positive family also exists:
  - `consistent/surrounded/moderate`: `22` samples, `100.0%` precision
- `shindo5-` validation diversity is too small:
  - only `1` event contributes (`28` samples, `92.9%`)
  - only one family appears: `consistent/one_sided/compact`
- No validation family contains PLUM-only FP in this current subset, so this
  report identifies candidate family structure but does not yet explain the
  frozen-test collapse by itself.

Boundary:

- still diagnostic-only;
- strictly validation-only;
- no PLUM radius/damping tuning;
- no suppression gate;
- no mutation of raw predicted intensity;
- no UI/wording/notification connection.

Updated next step:

1. Do **not** promote these validation family labels into confidence.
2. Freeze the current validation-defined family labels and run one frozen
   transfer comparison against the existing Tohoku hotspot.
3. Keep confidence/wording/UI disconnected unless that frozen comparison shows
   a family signal that actually transfers.

## Codex Continuation: PLUM Tohoku Frozen Family Transfer Diagnostic

After the validation-only family diagnostic, the next documented step was to
freeze those family labels and compare them against the existing frozen Tohoku
hotspot. That continuation is now implemented.

Added artifacts:

| Item | Path | Notes |
| --- | --- | --- |
| spec | [.trae/specs/plum-tohoku-frozen-family-transfer-diagnostic/spec.md](../.trae/specs/plum-tohoku-frozen-family-transfer-diagnostic/spec.md) + tasks.md + checklist.md | Completed |
| tool | [tools/build_plum_tohoku_frozen_family_transfer_diagnostic_report.dart](../tools/build_plum_tohoku_frozen_family_transfer_diagnostic_report.dart) | validation/test event families and frozen transfer summary for the `tohoku` hotspot |
| test | [test/plum_tohoku_frozen_family_transfer_diagnostic_report_test.dart](../test/plum_tohoku_frozen_family_transfer_diagnostic_report_test.dart) | 8-minute timeout; asserts non-production policy, family definitions, and transfer sections |
| report | [docs/baselines/plum_tohoku_frozen_family_transfer_diagnostic.generated.md](baselines/plum_tohoku_frozen_family_transfer_diagnostic.generated.md) | validation 2688 variants / 185694 forecasts; test 2757 variants / 179844 forecasts; status `pass` |
| document | [source_estimation_roadmap.md](source_estimation_roadmap.md) section `## 2026-06-28 PLUM Tohoku Frozen Family Transfer Diagnostic` | Added |

Key findings:

- The frozen hotspot does **not** land in the weakest validation family
  `mismatch/surrounded/moderate`.
- Instead, `shindo4` test mass is entirely concentrated in a previously unseen
  adjacent family:
  - `mismatch/one_sided/moderate`
  - `1051` samples
  - `458 TP / 593 FP`
  - precision `43.6%`
  - `549` PLUM-only FP
- Validation `shindo4` families were:
  - `consistent/surrounded/wide`: `91.9%`
  - `mismatch/surrounded/moderate`: `55.6%`
  - `consistent/surrounded/moderate`: `100.0%`
- `shindo5-` shows the same family-direction shift:
  - validation: `consistent/one_sided/compact`, `92.9%`
  - test: `mismatch/one_sided/compact`, `25.0%`
- Conclusion: the transfer-breaking axis is not more geography; it is the
  `mismatch + one_sided` regime.

Boundary:

- still diagnostic-only;
- no PLUM radius/damping tuning;
- no suppression gate;
- no mutation of raw predicted intensity;
- no UI/wording/notification connection.

Updated next step:

1. Do **not** promote these family labels into confidence.
2. Stop refining geography and stop broad family search; drill directly into
   the `mismatch + one_sided` regime.
3. Keep confidence/wording/UI disconnected unless that narrower regime shows a
   transferable signal.

## Codex Continuation: PLUM Tohoku Mismatch One-Sided Transfer Diagnostic

After the frozen family transfer diagnostic, the next documented step was to
test whether `one_sided` geometry itself is the transfer-breaking dimension
inside mismatch regimes. That continuation is now implemented.

Added artifacts:

| Item | Path | Notes |
| --- | --- | --- |
| spec | [.trae/specs/plum-tohoku-mismatch-one-sided-transfer-diagnostic/spec.md](../.trae/specs/plum-tohoku-mismatch-one-sided-transfer-diagnostic/spec.md) + tasks.md + checklist.md | Completed |
| tool | [tools/build_plum_tohoku_mismatch_one_sided_transfer_diagnostic_report.dart](../tools/build_plum_tohoku_mismatch_one_sided_transfer_diagnostic_report.dart) | sample-level mismatch/geometry/spread transfer summary inside the `tohoku` hotspot |
| test | [test/plum_tohoku_mismatch_one_sided_transfer_diagnostic_report_test.dart](../test/plum_tohoku_mismatch_one_sided_transfer_diagnostic_report_test.dart) | 8-minute timeout; asserts non-production policy, regime definitions, and mismatch transfer sections |
| report | [docs/baselines/plum_tohoku_mismatch_one_sided_transfer_diagnostic.generated.md](baselines/plum_tohoku_mismatch_one_sided_transfer_diagnostic.generated.md) | validation 2688 variants / 185694 forecasts; test 2757 variants / 179844 forecasts; status `pass` |
| document | [source_estimation_roadmap.md](source_estimation_roadmap.md) section `## 2026-06-28 PLUM Tohoku Mismatch One-Sided Transfer Diagnostic` | Added |

Key findings:

- `one_sided` is not the sole transfer-breaking dimension.
- Validation already contains weak `mismatch/one_sided/*` buckets:
  - `mismatch/one_sided/moderate`: `53.8%` on `13`
  - `mismatch/one_sided/compact`: `50.0%` on `8`
- Frozen test keeps those regimes weak, but the precision drop is modest:
  - `mismatch/one_sided/moderate`: `53.8% -> 43.5%`
  - `mismatch/one_sided/compact`: `50.0% -> 45.0%`
- `mismatch/surrounded/*` behaves similarly:
  - `mismatch/surrounded/moderate`: `50.0% -> 43.3%`
  - `mismatch/surrounded/wide`: `50.0% -> 42.4%`
- The real shift is sample mass:
  - validation mismatch buckets are tiny (`2` to `30` samples)
  - frozen mismatch buckets dominate the hotspot (`170` to `253` samples`)
- `shindo5-` confirms the mass-shift pattern:
  - validation has no mismatch buckets
  - test is entirely `mismatch/one_sided/compact|moderate` at `25.0%`

Boundary:

- still diagnostic-only;
- no PLUM radius/damping tuning;
- no suppression gate;
- no mutation of raw predicted intensity;
- no UI/wording/notification connection.

Updated next step:

1. Do **not** promote these regime labels into confidence.
2. Stop chasing a tiny extra precision delta; explain why frozen test shifts so
   much mass into mismatch regimes.
3. Keep confidence/wording/UI disconnected unless that regime-mass shift can be
   explained with a transferable signal.

## Codex Continuation: PLUM Tohoku Mismatch Gap-Transition Diagnostic

After the mismatch mass-shift diagnostic, the next documented step was to check
whether frozen test creates new mismatch `actual-gap x evidence-gap` cells that
validation never saw. That continuation is now implemented.

Added artifacts:

| Item | Path | Notes |
| --- | --- | --- |
| spec | [.trae/specs/plum-tohoku-mismatch-gap-transition-diagnostic/spec.md](../.trae/specs/plum-tohoku-mismatch-gap-transition-diagnostic/spec.md) + tasks.md + checklist.md | Completed |
| tool | [tools/build_plum_tohoku_mismatch_gap_transition_diagnostic_report.dart](../tools/build_plum_tohoku_mismatch_gap_transition_diagnostic_report.dart) | mismatch-only actual-gap x evidence-gap frozen transfer matrix |
| test | [test/plum_tohoku_mismatch_gap_transition_diagnostic_report_test.dart](../test/plum_tohoku_mismatch_gap_transition_diagnostic_report_test.dart) | 8-minute timeout; asserts non-production policy, gap-band definitions, and matrix sections |
| report | [docs/baselines/plum_tohoku_mismatch_gap_transition_diagnostic.generated.md](baselines/plum_tohoku_mismatch_gap_transition_diagnostic.generated.md) | validation 2688 variants / 185694 forecasts; test 2757 variants / 179844 forecasts; status `pass` |
| document | [source_estimation_roadmap.md](source_estimation_roadmap.md) section `## 2026-06-28 PLUM Tohoku Mismatch Gap-Transition Diagnostic` | Added |

Key findings:

- Validation `shindo4` mismatch space is polarized into only two kinds of cells:
  - far-below-threshold + huge evidence gap (`0.0%`)
  - above-threshold + tiny evidence gap (`100.0%`)
- Frozen test keeps those extremes, but also introduces new **middle
  transition** cells:
  - `0.0_to_1.0 x 1.0_to_2.0`: `117`, `100.0%`
  - `0.0_to_1.0 x 2.0_to_3.0`: `47`, `100.0%`
  - `-1.0_to_0.0 x 2.0_to_3.0`: `55`, `0.0%`
  - `-1.0_to_0.0 x 1.0_to_2.0`: `27`, `0.0%`
- This means frozen test is not only amplifying old mismatch cells. It is
  creating a large near-threshold / medium-gap transition zone that validation
  barely or never covered.
- `shindo5-` follows the same direction on a smaller sample:
  validation has no mismatch cells; test introduces both extreme-gap and
  middle-gap mismatch cells.

Boundary:

- still diagnostic-only;
- no PLUM radius/damping tuning;
- no suppression gate;
- no mutation of raw predicted intensity;
- no UI/wording/notification connection.

Updated next step:

1. Do **not** promote these mismatch cells into confidence.
2. Stop broad regime work and isolate the new middle transition zone:
   `actual around threshold [-1, +1]` plus `evidence gap 1-3`.
3. Keep confidence/wording/UI disconnected unless that narrower transition zone
   proves to be the transferable frozen-only signature.

## Codex Continuation: PLUM Tohoku Middle-Gap Transition-Zone Diagnostic

The next documented step was to collapse the mismatch cell matrix into a few
comparison zones and test whether the near-threshold / medium-gap zone is the
real frozen-only signature. That continuation is now implemented.

Added artifacts:

| Item | Path | Notes |
| --- | --- | --- |
| spec | [.trae/specs/plum-tohoku-middle-gap-transition-zone-diagnostic/spec.md](../.trae/specs/plum-tohoku-middle-gap-transition-zone-diagnostic/spec.md) + tasks.md + checklist.md | Completed |
| tool | [tools/build_plum_tohoku_middle_gap_transition_zone_diagnostic_report.dart](../tools/build_plum_tohoku_middle_gap_transition_zone_diagnostic_report.dart) | aggregates mismatch cells into middle/extreme/other zones using the prior report as source |
| test | [test/plum_tohoku_middle_gap_transition_zone_diagnostic_report_test.dart](../test/plum_tohoku_middle_gap_transition_zone_diagnostic_report_test.dart) | 8-minute timeout; asserts policy, zone definitions, and signature sections |
| report | [docs/baselines/plum_tohoku_middle_gap_transition_zone_diagnostic.generated.md](baselines/plum_tohoku_middle_gap_transition_zone_diagnostic.generated.md) | validation 2688 variants / 185694 forecasts; test 2757 variants / 179844 forecasts; status `pass` |
| document | [source_estimation_roadmap.md](source_estimation_roadmap.md) section `## 2026-06-28 PLUM Tohoku Middle-Gap Transition-Zone Diagnostic` | Added |

Key findings:

- `shindo4` confirms that the frozen hotspot is not best explained by the old
  extreme mismatch cells:
  - `middle_transition_zone`: `0.0% -> 25.2%`, precision `66.7%`
  - `extreme_false_zone`: `49.2% -> 44.7%`, precision `0.0%`
  - `extreme_true_zone`: `50.8% -> 25.3%`, precision `100.0%`
- So for `shindo4`, the dominant validation-to-test share delta is now clearly
  the new middle transition zone (`+25.2pp`), with no validation mass at all.
- `shindo5-` does **not** collapse to the same answer:
  - `middle_transition_zone`: `0.0% -> 25.0%`, precision `20.0%`
  - `extreme_false_zone`: `0.0% -> 50.0%`, precision `0.0%`
  - `extreme_true_zone`: `0.0% -> 20.0%`, precision `100.0%`
- This means the narrow middle zone is the main frozen-only signature for
  `shindo4`, but not a universal rule for every threshold. The higher-threshold
  hotspot still contains a stronger extreme-false component.

Boundary:

- still diagnostic-only;
- no PLUM radius/damping tuning;
- no suppression gate;
- no mutation of raw predicted intensity;
- no UI/wording/notification connection.

Updated next step:

1. Do **not** promote the middle-transition label itself into confidence or UI.
2. Shift from truth-defined zoning to production-available proxies: identify
   which observable evidence/local-shape features best predict the `shindo4`
   middle-transition zone without using actual intensity.
3. Keep `shindo5-` separated as a small-sample extreme-false audit track rather
   than forcing one shared rule across both thresholds.

## Codex Continuation: PLUM Tohoku Middle-Transition Proxy Diagnostic

The next documented step was to test whether any current production-available
evidence or support-shape buckets can approximate the `shindo4`
`middle_transition_zone`. That continuation is now implemented.

Added artifacts:

| Item | Path | Notes |
| --- | --- | --- |
| spec | [.trae/specs/plum-tohoku-middle-transition-proxy-diagnostic/spec.md](../.trae/specs/plum-tohoku-middle-transition-proxy-diagnostic/spec.md) + tasks.md + checklist.md | Completed |
| tool | [tools/build_plum_tohoku_middle_transition_proxy_diagnostic_report.dart](../tools/build_plum_tohoku_middle_transition_proxy_diagnostic_report.dart) | scores production-available proxy buckets against a truth-defined middle-transition label |
| test | [test/plum_tohoku_middle_transition_proxy_diagnostic_report_test.dart](../test/plum_tohoku_middle_transition_proxy_diagnostic_report_test.dart) | 8-minute timeout; asserts policy, label definition, and ranked proxy sections |
| report | [docs/baselines/plum_tohoku_middle_transition_proxy_diagnostic.generated.md](baselines/plum_tohoku_middle_transition_proxy_diagnostic.generated.md) | validation 2688 variants / 185694 forecasts; test 2757 variants / 179844 forecasts; status `pass` |
| document | [source_estimation_roadmap.md](source_estimation_roadmap.md) section `## 2026-06-28 PLUM Tohoku Middle-Transition Proxy Diagnostic` | Added |

Key findings:

- Validation still contains **zero** `middle_transition_zone` samples in the
  `tohoku` focus subset, while frozen test contains `246 / 1051` (`23.4%`).
- The current proxy families do **not** isolate that zone sharply:
  - the biggest mass-shift buckets are broad runtime states, not selective
    predictors:
    - `branchAgreement=agree_2`: `885` test samples, `23.5%`, `1.00x` lift
    - `robustnessScore=score_6`: `885` test samples, `23.5%`, `1.00x` lift
  - geometry and spread buckets also remain close to baseline:
    - `supportGeometry=one_sided`: `23.1%`, `0.99x`
    - `supportSpreadBand=moderate`: `23.6%`, `1.01x`
    - `geometrySpread=surrounded/moderate`: `25.0%`, `1.07x`
- The best non-trivial joint bucket in the current feature set is:
  - `plumMarginBand=1.0_to_1.5` + `geometrySpread=surrounded/moderate`:
    `140` test samples, `39` positives, `27.9%`, `1.19x` lift, `15.9%`
    capture share.
- That is still a weak separator. So the present production-available bucket
  family explains **where the mass moved**, but it does not yet provide a
  strong proxy for labeling the middle-transition zone.

Boundary:

- still diagnostic-only;
- no PLUM radius/damping tuning;
- no suppression gate;
- no mutation of raw predicted intensity;
- no UI/wording/notification connection.

Updated next step:

1. Do **not** promote any current proxy bucket into confidence or wording.
2. Stop refining the same coarse bucket families; add richer
   production-available features such as support-contribution concentration,
   top-support dominance, propagated-margin spread, or similar runtime-visible
   continuous signals.
3. Re-run the proxy search with those richer features for `shindo4`, while
   keeping `shindo5-` as a separate extreme-false audit track.

## Codex Continuation: PLUM Tohoku Middle-Transition Runtime-Signal Diagnostic

The next documented step was to move beyond the coarse proxy buckets and test
whether richer runtime-visible support-contribution signals isolate the
`shindo4 middle_transition_zone` better. That continuation is now implemented.

Added artifacts:

| Item | Path | Notes |
| --- | --- | --- |
| spec | [.trae/specs/plum-tohoku-middle-transition-runtime-signal-diagnostic/spec.md](../.trae/specs/plum-tohoku-middle-transition-runtime-signal-diagnostic/spec.md) + tasks.md + checklist.md | Completed |
| tool | [tools/build_plum_tohoku_middle_transition_runtime_signal_diagnostic_report.dart](../tools/build_plum_tohoku_middle_transition_runtime_signal_diagnostic_report.dart) | scores concentration/dominance/spread runtime signals against the truth-defined middle-transition label |
| test | [test/plum_tohoku_middle_transition_runtime_signal_diagnostic_report_test.dart](../test/plum_tohoku_middle_transition_runtime_signal_diagnostic_report_test.dart) | 8-minute timeout; asserts policy, outcome means, and ranked runtime-signal sections |
| report | [docs/baselines/plum_tohoku_middle_transition_runtime_signal_diagnostic.generated.md](baselines/plum_tohoku_middle_transition_runtime_signal_diagnostic.generated.md) | validation 2688 variants / 185694 forecasts; test 2757 variants / 179844 forecasts; status `pass` |
| document | [source_estimation_roadmap.md](source_estimation_roadmap.md) section `## 2026-06-28 PLUM Tohoku Middle-Transition Runtime-Signal Diagnostic` | Added |

Key findings:

- Richer runtime signals do add a little structure, but they still do **not**
  create a strong bucket-level separator.
- The strongest current joint runtime-signal buckets are:
  - `contributionHhiBand=lt_0.10` + `plumMarginBand=1.0_to_1.5`:
    `308` test samples, `82` positives, `26.6%`, `1.14x` lift,
    `33.3%` capture share.
  - `marginStdDevBand=0.30_to_0.50` + `plumMarginBand=1.0_to_1.5`:
    `325` test samples, `86` positives, `26.5%`, `1.13x` lift,
    `35.0%` capture share.
- Single-feature signals remain weak:
  - `contributionHhiBand=lt_0.10`: `24.9%`, `1.06x`
  - `marginStdDevBand=0.30_to_0.50`: `25.1%`, `1.07x`
  - `effectiveSupportCountBand=gte_8`: `24.5%`, `1.05x`
- Dominance signals are effectively dead in this subset:
  - all frozen-test mass collapses into `dominanceShareGapBand=lt_0.05`
  - all frozen-test mass collapses into `dominanceMarginGapBand=lt_0.10`
  - so those two features do not meaningfully partition the hotspot.
- Outcome means show only subtle directional shifts:
  - middle-transition samples have slightly **lower** concentration
    (`HHI 0.123` vs `0.127`, top1 share `0.144` vs `0.148`)
  - slightly **higher** effective support count (`10.29` vs `9.90`)
  - and slightly **higher** spread variation (`stddev 0.379` vs `0.376`)
- So the runtime-signal story is now clearer:
  the middle-transition zone looks like a **diffuse, mildly low-concentration,
  moderate-spread, low-PLUM-margin** regime, not a crisp discrete bucket.

Boundary:

- still diagnostic-only;
- no PLUM radius/damping tuning;
- no suppression gate;
- no mutation of raw predicted intensity;
- no UI/wording/notification connection.

Updated next step:

1. Do **not** promote any current runtime-signal bucket into confidence or UI.
2. Drop the non-informative dominance families from follow-up work.
3. Build a small diagnostic-only continuous runtime score from the mildly
   informative directions now observed:
   low concentration (`HHI` / top-share), moderate spread variance, and
   low-to-mid `PLUM` margin; then test score monotonicity and frozen transfer.

## Codex Continuation: PLUM Tohoku Middle-Transition Runtime-Score Diagnostic

The next documented step was to collapse the mildly informative runtime-signal
directions into a small continuous diagnostic score and test whether that score
orders the frozen hotspot better than the prior discrete buckets. That
continuation is now implemented.

Added artifacts:

| Item | Path | Notes |
| --- | --- | --- |
| spec | [.trae/specs/plum-tohoku-middle-transition-runtime-score-diagnostic/spec.md](../.trae/specs/plum-tohoku-middle-transition-runtime-score-diagnostic/spec.md) + tasks.md + checklist.md | Completed |
| tool | [tools/build_plum_tohoku_middle_transition_runtime_score_diagnostic_report.dart](../tools/build_plum_tohoku_middle_transition_runtime_score_diagnostic_report.dart) | computes a small concentration/spread/margin score and evaluates validation-anchored transfer + test monotonicity |
| test | [test/plum_tohoku_middle_transition_runtime_score_diagnostic_report_test.dart](../test/plum_tohoku_middle_transition_runtime_score_diagnostic_report_test.dart) | 8-minute timeout; asserts policy, score-definition, band-transfer, and monotonicity sections |
| report | [docs/baselines/plum_tohoku_middle_transition_runtime_score_diagnostic.generated.md](baselines/plum_tohoku_middle_transition_runtime_score_diagnostic.generated.md) | validation 2688 variants / 185694 forecasts; test 2757 variants / 179844 forecasts; status `pass` |
| document | [source_estimation_roadmap.md](source_estimation_roadmap.md) section `## 2026-06-28 PLUM Tohoku Middle-Transition Runtime-Score Diagnostic` | Added |

Key findings:

- The continuous score is directionally better than random ordering, but still
  only mildly informative:
  - test outcome mean score: `0.631` for middle-transition vs `0.616` for
    other focus samples;
  - top test decile positive rate: `26.4%`
  - bottom test decile positive rate: `22.9%`
  - top-to-bottom lift: `1.16x`
  - adjacent decile ordering: `6` non-decreasing vs `3` decreasing pairs.
- Validation-anchored transfer shows only a modest high-band enrichment:
  - `mid_high`: `26.4%`, `1.13x` lift
  - `high`: `26.3%`, `1.12x` lift
  - `low`: `22.4%`, `0.96x` lift
  - `mid_low`: `21.7%`, `0.93x` lift
- So the score is usable as a **soft ordering signal**, but not yet as a sharp
  diagnostic gate or a wording-ready confidence layer.
- It also does **not** materially outperform the best prior joint buckets,
  which reached about `1.13x` to `1.14x` lift already.

Boundary:

- still diagnostic-only;
- no PLUM radius/damping tuning;
- no suppression gate;
- no mutation of raw predicted intensity;
- no UI/wording/notification connection.

Updated next step:

1. Do **not** promote this runtime score into confidence, UI, or wording.
2. Do **not** keep hand-tuning the current three weights blindly; the gain is
   too small.
3. Audit the strongest omitted production-available axis next:
   add an explicit `localBelowThresholdShare10Km` continuous ramp and test
   whether `runtimeScore x local-mismatch-ramp` materially improves monotonicity.
   If not, stop direct middle-transition proxy optimization and treat the score
   as diagnostic-only evidence.

## Codex Continuation: PLUM Tohoku Middle-Transition Local-Mismatch-Ramp Diagnostic

The next documented step was to audit whether a continuous
`localBelowThresholdShare10Km` ramp materially improves the existing runtime
score. That continuation is now implemented.

Added artifacts:

| Item | Path | Notes |
| --- | --- | --- |
| spec | [.trae/specs/plum-tohoku-middle-transition-local-mismatch-ramp-diagnostic/spec.md](../.trae/specs/plum-tohoku-middle-transition-local-mismatch-ramp-diagnostic/spec.md) + tasks.md + checklist.md | Completed |
| tool | [tools/build_plum_tohoku_middle_transition_local_mismatch_ramp_diagnostic_report.dart](../tools/build_plum_tohoku_middle_transition_local_mismatch_ramp_diagnostic_report.dart) | compares base runtime score vs `runtimeScore * localMismatchRamp` on validation-anchored transfer and test monotonicity |
| test | [test/plum_tohoku_middle_transition_local_mismatch_ramp_diagnostic_report_test.dart](../test/plum_tohoku_middle_transition_local_mismatch_ramp_diagnostic_report_test.dart) | 8-minute timeout; asserts policy, base/adjusted transfer, monotonicity, and comparison sections |
| report | [docs/baselines/plum_tohoku_middle_transition_local_mismatch_ramp_diagnostic.generated.md](baselines/plum_tohoku_middle_transition_local_mismatch_ramp_diagnostic.generated.md) | validation 2688 variants / 185694 forecasts; test 2757 variants / 179844 forecasts; status `pass` |
| document | [source_estimation_roadmap.md](source_estimation_roadmap.md) section `## 2026-06-28 PLUM Tohoku Middle-Transition Local-Mismatch-Ramp Diagnostic` | Added |

Key findings:

- The adjusted score improves the raw top-to-bottom decile lift slightly:
  - base: `1.16x`
  - adjusted: `1.26x`
- But it does **not** improve monotonicity quality:
  - base decreasing adjacent pairs: `3`
  - adjusted decreasing adjacent pairs: `3`
- More importantly, the validation-anchored adjusted-score bands collapse:
  - validation anchors become `q25=0.0`, `q50=0.0`, `q75≈0.097`
  - validation mass is mostly in `low`, while frozen test mass is entirely in
    `high`
  - this means the adjusted score no longer provides a meaningful transferable
    validation-anchored partition.
- So the ramp changes ranking numerically, but not in a robust way that we can
  trust outside this frozen sample.

Boundary:

- still diagnostic-only;
- no PLUM radius/damping tuning;
- no suppression gate;
- no mutation of raw predicted intensity;
- no UI/wording/notification connection.

Updated next step:

1. Stop direct middle-transition proxy optimization here; the current line has
   converged to weak, unstable gains.
2. Keep the runtime score and ramp results as diagnostic-only evidence.
3. Return to broader, more transferable analysis: use this evidence as context
   when auditing upstream frozen-regression / event-family behavior, rather
   than trying to ship a middle-transition proxy.

## Codex Continuation: PLUM Tohoku Upstream Source-Family Diagnostic

The next documented step was to return to broader transferable analysis and
audit which upstream source families actually carry the frozen `tohoku`
hotspot. That continuation is now implemented.

Added artifacts:

| Item | Path | Notes |
| --- | --- | --- |
| spec | [.trae/specs/plum-tohoku-upstream-source-family-diagnostic/spec.md](../.trae/specs/plum-tohoku-upstream-source-family-diagnostic/spec.md) + tasks.md + checklist.md | Completed |
| tool | [tools/build_plum_tohoku_upstream_source_family_diagnostic_report.dart](../tools/build_plum_tohoku_upstream_source_family_diagnostic_report.dart) | audits broader `tohoku` strong-nearby-evidence hotspot by source trigger family, winner family, and event family |
| test | [test/plum_tohoku_upstream_source_family_diagnostic_report_test.dart](../test/plum_tohoku_upstream_source_family_diagnostic_report_test.dart) | 8-minute timeout; asserts non-production policy and source-family transfer sections |
| report | [docs/baselines/plum_tohoku_upstream_source_family_diagnostic.generated.md](baselines/plum_tohoku_upstream_source_family_diagnostic.generated.md) | validation 2688 variants / 69909 forecasts; test 2757 variants / 60373 forecasts; status `pass` |
| document | [source_estimation_roadmap.md](source_estimation_roadmap.md) section `## 2026-06-28 PLUM Tohoku Upstream Source-Family Diagnostic` | Added |

Key findings:

- The broader hotspot is overwhelmingly `PLUM`-led on frozen test:
  - source trigger family shifts from `plum_only 21.3%` / `both 53.6%` on
    validation to `plum_only 96.9%` / `both 2.8%` on test.
  - source winner family shifts from `plum_higher 59.7%` / `jma_higher 40.3%`
    on validation to `plum_higher 99.6%` / `jma_higher 0.4%` on test.
- This means the active hotspot is not JMA-style-led inside this subset:
  - `plum_higher` precision drops from `69.8%` to `40.4%`
  - `jma_higher` almost vanishes instead of becoming the failure mass.
- The middle-transition label remains almost entirely inside the PLUM-led
  branch:
  - `plum_higher + middle_transition_zone`: `2.3% -> 14.9%`
  - `jma_higher + middle_transition_zone`: `0.6% -> 0.0%`
- The dominant frozen family is now
  `plum_higher + mismatch/one_sided/compact`:
  - validation `13.4%`
  - test `63.9%`
  - share delta `+50.5pp`
- Test concentration is extreme:
  - event `2022031623342701-37.6810-141.6062` contributes `3511 / 3598`
    (`97.6%`) of focus samples.

Boundary:

- still diagnostic-only;
- no PLUM radius/damping tuning;
- no suppression gate;
- no mutation of raw predicted intensity;
- no UI/wording/notification connection.

Updated next step:

1. Freeze the source-family conclusion: the current hotspot is PLUM-led, not
   JMA-style-led.
2. Do **not** generalize from the current test hotspot yet, because it is
   almost entirely concentrated in one event.
3. Run an event-concentration / leave-top-event-out diagnostic on the PLUM-led
   hotspot, centered on `2022031623342701-37.6810-141.6062`, before deciding
   whether any follow-up calibration is transferable.

## Codex Continuation: PLUM Tohoku Event-Concentration Diagnostic

The next documented step was to test how much of the current PLUM-led hotspot
survives after removing its dominant test event. That continuation is now
implemented.

Added artifacts:

| Item | Path | Notes |
| --- | --- | --- |
| spec | [.trae/specs/plum-tohoku-event-concentration-diagnostic/spec.md](../.trae/specs/plum-tohoku-event-concentration-diagnostic/spec.md) + tasks.md + checklist.md | Completed |
| tool | [tools/build_plum_tohoku_event_concentration_diagnostic_report.dart](../tools/build_plum_tohoku_event_concentration_diagnostic_report.dart) | compares full test hotspot vs dominant event vs leave-top-event-out remainder |
| test | [test/plum_tohoku_event_concentration_diagnostic_report_test.dart](../test/plum_tohoku_event_concentration_diagnostic_report_test.dart) | 8-minute timeout; asserts non-production policy, dominant-event summary, and slice sections |
| report | [docs/baselines/plum_tohoku_event_concentration_diagnostic.generated.md](baselines/plum_tohoku_event_concentration_diagnostic.generated.md) | validation 2688 variants / 69909 forecasts; test 2757 variants / 60373 forecasts; status `pass` |
| document | [source_estimation_roadmap.md](source_estimation_roadmap.md) section `## 2026-06-28 PLUM Tohoku Event-Concentration Diagnostic` | Added |

Key findings:

- The hotspot is almost entirely concentrated in one event:
  - dominant event `2022031623342701-37.6810-141.6062`
  - focus share `97.6%` (`3511 / 3598`)
  - top-3 cumulative share `99.7%`
  - top-5 cumulative share `100.0%`
- Removing that event materially improves precision:
  - full test precision `40.4%`
  - leave-top-event-out precision `51.7%`
  - recovery `+11.3pp`
- But the remainder is still overwhelmingly PLUM-led:
  - leave-top-event-out `plum_only 97.7%`
  - leave-top-event-out `plum_higher 97.7%`
  - `41 / 42` remaining false positives are still PLUM-only
- So the full frozen hotspot is partly concentration-driven, but not purely a
  single-event illusion.
- The remainder is now very small (`87` samples), so it is still too sparse to
  justify transferable calibration decisions directly.

Boundary:

- still diagnostic-only;
- no PLUM radius/damping tuning;
- no suppression gate;
- no mutation of raw predicted intensity;
- no UI/wording/notification connection.

Updated next step:

1. Freeze the concentration conclusion: the current full-test hotspot
   overstates cross-event confidence because one event dominates it.
2. Freeze the residual conclusion: the surviving remainder is still PLUM-led,
   so the problem does not disappear entirely after removing that event.
3. Run a residual leave-top-event-out family audit on the remaining `87`
   samples, focused on whether the surviving PLUM-only false positives collapse
   to one stable geometry family or are too sparse for transferable
   calibration.

## Codex Continuation: PLUM Tohoku Residual Remainder Family Audit

The next documented step was to audit whether the remaining `87`
leave-top-event-out samples collapse to one stable family or are too sparse for
transferable calibration. That continuation is now implemented.

Added artifacts:

| Item | Path | Notes |
| --- | --- | --- |
| spec | [.trae/specs/plum-tohoku-residual-remainder-family-audit/spec.md](../.trae/specs/plum-tohoku-residual-remainder-family-audit/spec.md) + tasks.md + checklist.md | Completed |
| tool | [tools/build_plum_tohoku_residual_remainder_family_audit_report.dart](../tools/build_plum_tohoku_residual_remainder_family_audit_report.dart) | audits family concentration inside the leave-top-event-out remainder |
| test | [test/plum_tohoku_residual_remainder_family_audit_report_test.dart](../test/plum_tohoku_residual_remainder_family_audit_report_test.dart) | 8-minute timeout; asserts non-production policy and remainder family sections |
| report | [docs/baselines/plum_tohoku_residual_remainder_family_audit.generated.md](baselines/plum_tohoku_residual_remainder_family_audit.generated.md) | validation 2688 variants / 69909 forecasts; test 2757 variants / 60373 forecasts; status `pass` |
| document | [source_estimation_roadmap.md](source_estimation_roadmap.md) section `## 2026-06-28 PLUM Tohoku Residual Remainder Family Audit` | Added |

Key findings:

- The remainder is small but not random:
  - `87` samples total
  - `42` false positives
  - `41` PLUM-only false positives
  - `41` PLUM-higher false positives
- Those surviving false positives collapse strongly to a single family:
  - `mismatch/one_sided/compact` is `85.7%` of remainder false positives
  - and `85.4%` of remainder PLUM-only false positives
  - top-2 remainder PLUM-only false-positive families already cover `97.6%`
- But this is not a new frozen-only family:
  - validation already has `mismatch/one_sided/compact` as its largest family
    (`1254` samples)
  - validation precision there is already weak at `25.4%`
- So the remainder is collapsing into an already-known weak family, not a new
  frozen-only transferable family signature.
- The residual event set is still sparse:
  - event counts `53`, `23`, `6`, and `5`

Boundary:

- still diagnostic-only;
- no PLUM radius/damping tuning;
- no suppression gate;
- no mutation of raw predicted intensity;
- no UI/wording/notification connection.

Updated next step:

1. Freeze the remainder-family conclusion: the surviving PLUM-led remainder is
   concentrated, but not in a new family.
2. Do **not** promote `mismatch/one_sided/compact` itself into a new hotspot
   calibration rule, because validation already shows it as a large weak
   family.
3. Run a sub-regime audit inside `mismatch/one_sided/compact`, comparing
   validation vs residual remainder on middle-transition share, local mismatch,
   and event mix, to see whether a narrower frozen-only slice exists inside
   that already-weak family.

## Codex Continuation: PLUM Tohoku mismatch/one_sided/compact Sub-Regime Audit

The next documented step was to inspect whether a narrower frozen-only slice
exists inside the already-weak family `mismatch/one_sided/compact`. That
continuation is now implemented.

Added artifacts:

| Item | Path | Notes |
| --- | --- | --- |
| spec | [.trae/specs/plum-tohoku-mismatch-one-sided-compact-subregime-audit/spec.md](../.trae/specs/plum-tohoku-mismatch-one-sided-compact-subregime-audit/spec.md) + tasks.md + checklist.md | Completed |
| tool | [tools/build_plum_tohoku_mismatch_one_sided_compact_subregime_audit_report.dart](../tools/build_plum_tohoku_mismatch_one_sided_compact_subregime_audit_report.dart) | compares validation vs leave-top-event-out remainder inside `mismatch/one_sided/compact` |
| test | [test/plum_tohoku_mismatch_one_sided_compact_subregime_audit_report_test.dart](../test/plum_tohoku_mismatch_one_sided_compact_subregime_audit_report_test.dart) | 8-minute timeout; asserts non-production policy and sub-regime sections |
| report | [docs/baselines/plum_tohoku_mismatch_one_sided_compact_subregime_audit.generated.md](baselines/plum_tohoku_mismatch_one_sided_compact_subregime_audit.generated.md) | validation family samples 1254; remainder family samples 67; status `pass` |
| document | [source_estimation_roadmap.md](source_estimation_roadmap.md) section `## 2026-06-28 PLUM Tohoku mismatch/one_sided/compact Sub-Regime Audit` | Added |

Key findings:

- There is a real within-family shift:
  - validation middle-transition share: `7.1%`
  - remainder middle-transition share: `22.4%`
  - remainder false-positive middle-transition share: `41.7%`
- But the remainder does **not** shift toward more extreme local mismatch:
  - `0.50_to_0.67` local-mismatch band grows from `37.1%` to `62.7%`
  - `gte_0.85` shrinks from `40.6%` to `19.4%`
- So the remainder is not simply “a more broken version” of the family.
- Instead, the within-family redistribution looks like two competing slices:
  - valid near-threshold positives over-index on
    `actualGap 0.0_to_1.0 / evidenceGap lt_1.0`
  - false middle-transition cells over-index on
    `actualGap -1.0_to_0.0 / evidenceGap 1.0_to_2.0`
- The strongest validation-only tail that disappears is
  `other_family_samples|gte_0.85|-1.0_to_0.0|missing` (`-22.4pp`).
- So there is a narrower frozen-shift signal, but it is still mixed with a
  large true-positive near-threshold mode inside the same family.

Boundary:

- still diagnostic-only;
- no PLUM radius/damping tuning;
- no suppression gate;
- no mutation of raw predicted intensity;
- no UI/wording/notification connection.

Updated next step:

1. Freeze the sub-regime conclusion: the current signal is a redistribution
   inside `mismatch/one_sided/compact`, not a standalone new family rule.
2. Do **not** promote any sub-regime directly into production calibration yet,
   because the same family contains both the over-indexed true and false modes.
3. Compare production-available support/evidence signals for the two within-
   family remainder modes next:
   `0.0_to_1.0 / lt_1.0` positives versus
   `-1.0_to_0.0 / 1.0_to_2.0` middle-transition false cells.

## Codex Continuation: PLUM Tohoku mismatch/one_sided/compact Mode Signal Separation Diagnostic

The next documented step was to compare production-available support/evidence
signals for the two within-family remainder modes inside
`mismatch/one_sided/compact`. That continuation is now implemented.

Added artifacts:

| Item | Path | Notes |
| --- | --- | --- |
| spec | [.trae/specs/plum-tohoku-mismatch-one-sided-compact-mode-signal-separation-diagnostic/spec.md](../.trae/specs/plum-tohoku-mismatch-one-sided-compact-mode-signal-separation-diagnostic/spec.md) + tasks.md + checklist.md | Completed |
| tool | [tools/build_plum_tohoku_mismatch_one_sided_compact_mode_signal_separation_diagnostic_report.dart](../tools/build_plum_tohoku_mismatch_one_sided_compact_mode_signal_separation_diagnostic_report.dart) | compares `0.0_to_1.0 / lt_1.0` positives vs `-1.0_to_0.0 / 1.0_to_2.0` false middle-transition cells using production-visible source/support/evidence signals only |
| test | [test/plum_tohoku_mismatch_one_sided_compact_mode_signal_separation_diagnostic_report_test.dart](../test/plum_tohoku_mismatch_one_sided_compact_mode_signal_separation_diagnostic_report_test.dart) | 8-minute timeout; asserts non-production policy, separator sections, and markdown output |
| report | [docs/baselines/plum_tohoku_mismatch_one_sided_compact_mode_signal_separation_diagnostic.generated.md](baselines/plum_tohoku_mismatch_one_sided_compact_mode_signal_separation_diagnostic.generated.md) | validation family `1254`; remainder family `67`; remainder target modes `30` near positives + `15` false middle-transition; status `pass` |
| document | [source_estimation_roadmap.md](source_estimation_roadmap.md) section `## 2026-06-28 PLUM Tohoku mismatch/one_sided/compact Mode Signal Separation Diagnostic` | Added |

Key findings:

- The two remainder modes are both PLUM-only / PLUM-higher in the current
  leave-top-event-out remainder, so source-family choice itself no longer
  separates them.
- Both modes are highly single-support dominated:
  - remainder near-threshold positives: top1 share `0.939`, effective support
    `1.158`, centroid offset `6.929 km`
  - remainder false middle-transition: top1 share `1.000`, effective support
    `1.000`, centroid offset `9.346 km`
- The strongest positive-skew buckets are real but small:
  - centroid offset `<5 km`: `9` near-threshold positives vs `0` false cells
    (`20.0%` capture)
  - quadrant coverage `q2`: `5` near-threshold positives vs `0` false cells
    (`11.1%` capture)
  - local mismatch `0.50_to_0.67`: `18` vs `6` (`+20.0pp` share gap)
- The bulk false slice still overlaps the same broad buckets as valid
  near-threshold positives:
  - `q1`: `25` vs `15`
  - nearest evidence distance `5.0_to_10.0 km`: `16` vs `10`
  - mean contribution margin `<0.25`: `23` vs `11`
- So the result is a gradient, not a clean transferable binary separator:
  false middle-transition cells are more degenerate and more offset, but many
  valid near-threshold positives still occupy the same one-sided,
  single-support, high-concentration regime.

Boundary:

- still diagnostic-only;
- no PLUM radius/damping tuning;
- no suppression gate;
- no mutation of raw predicted intensity;
- no UI/wording/notification connection.

Updated next step:

1. Freeze the separator conclusion: there is no broad hard gate inside
   `mismatch/one_sided/compact` that cleanly removes false middle-transition
   cells without also hitting valid near-threshold positives.
2. Do **not** add suppression rules from `q1`, centroid offset,
   single-support collapse, or concentration buckets alone.
3. Move to a non-suppression continuation next: build a soft robustness score
   from these source/support/evidence signals and test whether it can rank
   risky `mismatch/one_sided/compact` samples without suppressing the valid
   near-threshold tail.

## Codex Continuation: PLUM Tohoku mismatch/one_sided/compact Mode Runtime-Score Diagnostic

The next documented step was to move from hard separator hunting to a soft
ranking diagnostic for the two within-family remainder modes. That continuation
is now implemented.

Added artifacts:

| Item | Path | Notes |
| --- | --- | --- |
| spec | [.trae/specs/plum-tohoku-mismatch-one-sided-compact-mode-runtime-score-diagnostic/spec.md](../.trae/specs/plum-tohoku-mismatch-one-sided-compact-mode-runtime-score-diagnostic/spec.md) + tasks.md + checklist.md | Completed |
| tool | [tools/build_plum_tohoku_mismatch_one_sided_compact_mode_runtime_score_diagnostic_report.dart](../tools/build_plum_tohoku_mismatch_one_sided_compact_mode_runtime_score_diagnostic_report.dart) | validation-anchored soft score for `0.0_to_1.0 / lt_1.0` positives vs `-1.0_to_0.0 / 1.0_to_2.0` false middle-transition cells |
| test | [test/plum_tohoku_mismatch_one_sided_compact_mode_runtime_score_diagnostic_report_test.dart](../test/plum_tohoku_mismatch_one_sided_compact_mode_runtime_score_diagnostic_report_test.dart) | 8-minute timeout; asserts non-production policy, score anchors, transfer rows, and quartile sections |
| report | [docs/baselines/plum_tohoku_mismatch_one_sided_compact_mode_runtime_score_diagnostic.generated.md](baselines/plum_tohoku_mismatch_one_sided_compact_mode_runtime_score_diagnostic.generated.md) | validation target modes `299`; remainder target modes `45`; status `pass` |
| document | [source_estimation_roadmap.md](source_estimation_roadmap.md) section `## 2026-06-28 PLUM Tohoku mismatch/one_sided/compact Mode Runtime-Score Diagnostic` | Added |

Key findings:

- The soft score separates directionally:
  - validation means: runtime score `0.392` for near-threshold positives vs
    `0.295` for false middle-transition
  - remainder means: `0.264` vs `0.149`
- Validation-anchored bands transfer meaningfully on the remainder:
  - `low` band captures `11 / 15` false cells (`73.3%`) but also
    `11 / 30` near-threshold positives (`36.7%`)
  - `high` band captures `4 / 30` near-threshold positives and `0 / 15`
    false cells
  - mid bands remain strongly near-positive dominant (`78.6%` and `80.0%`)
- Quartile ordering is useful but not perfectly monotone:
  - quartile 4 reaches `91.7%` near-positive rate and `8.3%` false rate
  - quartile 2 drops to `36.4%` near-positive rate, so the ranking is not a
    clean threshold boundary
- The concentration branch is nearly dead inside this family:
  - validation concentration means `0.034` / `0.000`
  - remainder concentration means `0.000` / `0.000`
  - most remaining signal comes from support geometry and evidence proximity

Boundary:

- still diagnostic-only;
- no PLUM radius/damping tuning;
- no suppression gate;
- no mutation of raw predicted intensity;
- no UI/wording/notification connection.

Updated next step:

1. Freeze the soft-score conclusion: it is useful for ranking this family's
   remainder risk, but not clean enough for threshold-based suppression.
2. Do **not** turn the score into rejection, gating, or production wording.
3. Continue with score parsimony/transfer next: compare the full score against
   simpler ablations such as `supportGeometry-only` and
   `supportGeometry + proximity`, then verify whether the ranking survives
   without the weak concentration term.

## Codex Continuation: PLUM Tohoku mismatch/one_sided/compact Mode Runtime-Score Ablation Diagnostic

The next documented step was to compare the family-specific soft score against
simpler ablations. That continuation is now implemented.

Added artifacts:

| Item | Path | Notes |
| --- | --- | --- |
| spec | [.trae/specs/plum-tohoku-mismatch-one-sided-compact-mode-runtime-score-ablation-diagnostic/spec.md](../.trae/specs/plum-tohoku-mismatch-one-sided-compact-mode-runtime-score-ablation-diagnostic/spec.md) + tasks.md + checklist.md | Completed |
| tool | [tools/build_plum_tohoku_mismatch_one_sided_compact_mode_runtime_score_ablation_diagnostic_report.dart](../tools/build_plum_tohoku_mismatch_one_sided_compact_mode_runtime_score_ablation_diagnostic_report.dart) | compares `supportGeometry-only`, `supportGeometry + proximity`, and `full score` on the same target-mode remainder slice |
| test | [test/plum_tohoku_mismatch_one_sided_compact_mode_runtime_score_ablation_diagnostic_report_test.dart](../test/plum_tohoku_mismatch_one_sided_compact_mode_runtime_score_ablation_diagnostic_report_test.dart) | 8-minute timeout; asserts non-production policy and ablation sections |
| report | [docs/baselines/plum_tohoku_mismatch_one_sided_compact_mode_runtime_score_ablation_diagnostic.generated.md](baselines/plum_tohoku_mismatch_one_sided_compact_mode_runtime_score_ablation_diagnostic.generated.md) | validation target modes `299`; remainder target modes `45`; status `pass` |
| document | [source_estimation_roadmap.md](source_estimation_roadmap.md) section `## 2026-06-28 PLUM Tohoku mismatch/one_sided/compact Mode Runtime-Score Ablation Diagnostic` | Added |

Key findings:

- `supportGeometry-only` is the strongest current family-local ranking
  baseline:
  - validation mean gap `0.176`
  - remainder mean gap `0.191`
  - high/low near-positive lift `1.53x`
  - fully monotone quartile ordering on the remainder
- `supportGeometry + proximity` and `full score` both widen low-band coverage
  but not cleanly:
  - low-band false capture rises to `73.3%`
  - but low-band near-positive capture also rises to `36.7%`
- All three variants already achieve the same pure `high` band:
  - `100.0%` near-positive rate
  - `0.0%` false rate
  - so proximity/concentration are not improving the top slice
- The concentration term is therefore not only weak in means, but actively
  unnecessary for the current family-local ranking problem.

Boundary:

- still diagnostic-only;
- no PLUM radius/damping tuning;
- no suppression gate;
- no mutation of raw predicted intensity;
- no UI/wording/notification connection.

Updated next step:

1. Freeze the ablation conclusion: `supportGeometry-only` is the best current
   diagnostic ranking baseline for `mismatch/one_sided/compact`.
2. Do **not** turn any variant into suppression, gating, or production
   wording.
3. Continue with transfer validation next: run the
   `supportGeometry-only` family score on additional event slices / manifests
   and verify whether this family-local ordering remains stable outside the
   current leave-top-event-out remainder.

## Codex Continuation: PLUM Tohoku mismatch/one_sided/compact Support-Geometry Transfer Diagnostic

The next documented step was to verify whether the `supportGeometry-only`
family-local score remains stable outside the pooled leave-top-event-out
remainder. That continuation is now implemented.

Added artifacts:

| Item | Path | Notes |
| --- | --- | --- |
| spec | [.trae/specs/plum-tohoku-mismatch-one-sided-compact-support-geometry-transfer-diagnostic/spec.md](../.trae/specs/plum-tohoku-mismatch-one-sided-compact-support-geometry-transfer-diagnostic/spec.md) + tasks.md + checklist.md | Completed |
| tool | [tools/build_plum_tohoku_mismatch_one_sided_compact_support_geometry_transfer_diagnostic_report.dart](../tools/build_plum_tohoku_mismatch_one_sided_compact_support_geometry_transfer_diagnostic_report.dart) | pooled remainder + per-event transfer slices for fixed `supportGeometry-only` |
| test | [test/plum_tohoku_mismatch_one_sided_compact_support_geometry_transfer_diagnostic_report_test.dart](../test/plum_tohoku_mismatch_one_sided_compact_support_geometry_transfer_diagnostic_report_test.dart) | 8-minute timeout; asserts non-production policy and slice-report sections |
| report | [docs/baselines/plum_tohoku_mismatch_one_sided_compact_support_geometry_transfer_diagnostic.generated.md](baselines/plum_tohoku_mismatch_one_sided_compact_support_geometry_transfer_diagnostic.generated.md) | validation target modes `299`; remainder target modes `45`; evaluated slices `4`; status `pass` |
| document | [source_estimation_roadmap.md](source_estimation_roadmap.md) section `## 2026-06-28 PLUM Tohoku mismatch/one_sided/compact Support-Geometry Transfer Diagnostic` | Added |

Key findings:

- The pooled remainder slice is still stable:
  - mean gap `0.191`
  - low-band false capture `60.0%` vs low-band near capture `26.7%`
  - high band pure (`100.0%` near, `0.0%` false)
  - quartiles remain monotone
- The largest residual event remains directionally consistent but not fully
  monotone:
  - `2022070605102497-38.4125-141.9545`
  - `34` target-mode samples
  - high band pure, but quartile 3 regresses, so the event is
    `directional_but_noisy`, not fully stable
- The remaining event slices are too sparse to prove transfer:
  - `2022031700522985-37.7947-141.7145`: `4` samples
  - `2022080409481868-37.6118-141.6195`: `4` samples
  - both flagged `sample_sparse`
- So the current proof is narrower than “fully transferable family score”:
  it is reliable on the pooled slice, promising on the largest residual event,
  and still underpowered on the smaller events.

Boundary:

- still diagnostic-only;
- no PLUM radius/damping tuning;
- no suppression gate;
- no mutation of raw predicted intensity;
- no UI/wording/notification connection.

Updated next step:

1. Freeze the transfer conclusion: `supportGeometry-only` is still the best
   current diagnostic family-local ranking baseline, but cross-event stability
   is only partially verified.
2. Do **not** promote it into production scoring or gating yet.
3. Continue with broader verification next: extend the same transfer check to
   additional event pools / manifests so the ranking is either confirmed across
   more events or explicitly scoped to the current residual event mix.

## 14. PLUM Tohoku mismatch/one_sided/compact Support-Geometry Broader Verification Diagnostic

The next documented step was to broaden that transfer check beyond pooled
remainder plus sparse event-only slices. That continuation is now implemented.

Added artifacts:

| Item | Path | Notes |
| --- | --- | --- |
| spec | [.trae/specs/plum-tohoku-mismatch-one-sided-compact-support-geometry-broader-verification-diagnostic/spec.md](../.trae/specs/plum-tohoku-mismatch-one-sided-compact-support-geometry-broader-verification-diagnostic/spec.md) + tasks.md + checklist.md | Completed |
| tool | [tools/build_plum_tohoku_mismatch_one_sided_compact_support_geometry_broader_verification_diagnostic_report.dart](../tools/build_plum_tohoku_mismatch_one_sided_compact_support_geometry_broader_verification_diagnostic_report.dart) | pooled remainder + leave-event-out pooled slices + event-only slices for fixed `supportGeometry-only` |
| test | [test/plum_tohoku_mismatch_one_sided_compact_support_geometry_broader_verification_diagnostic_report_test.dart](../test/plum_tohoku_mismatch_one_sided_compact_support_geometry_broader_verification_diagnostic_report_test.dart) | 8-minute timeout; asserts non-production policy, slice-category summary, and slice sections |
| report | [docs/baselines/plum_tohoku_mismatch_one_sided_compact_support_geometry_broader_verification_diagnostic.generated.md](baselines/plum_tohoku_mismatch_one_sided_compact_support_geometry_broader_verification_diagnostic.generated.md) | validation target modes `299`; remainder target modes `45`; remainder events `4`; evaluated slices `8`; status `pass` |
| document | [source_estimation_roadmap.md](source_estimation_roadmap.md) section `## 2026-06-28 PLUM Tohoku mismatch/one_sided/compact Support-Geometry Broader Verification Diagnostic` | Added |

Key findings:

- The pooled remainder is still stable:
  - `45` target-mode samples
  - mean gap `0.191`
  - high/low near lift `1.53x`
  - high/low false-rate ratio `0.37x`
- But the score is not broadly transferable once the dominant residual event is
  removed from the pooled slice:
  - `leave_event_out::2022070605102497-38.4125-141.9545`
  - `11` samples (`5` near, `6` false)
  - mean gap `0.007`
  - stability `not_stable`
- The other leave-event-out pooled slices are only
  `directional_but_noisy`, not stable:
  - excluding `2022031700522985-37.7947-141.7145`: `41` samples
  - excluding `2022080409481868-37.6118-141.6195`: `41` samples
  - excluding `2022081814461047-37.6017-141.5853`: `42` samples
- Event-only evidence remains narrow:
  - largest residual event `directional_but_noisy`
  - two smaller events still `sample_sparse`
- So the broader verification resolves the ambiguity:
  `supportGeometry-only` is a useful pooled family-local diagnostic ranking,
  but it is still materially dependent on the dominant residual event mix and
  does not justify a broadly transferable family score.

Boundary:

- still diagnostic-only;
- no PLUM radius/damping tuning;
- no suppression gate;
- no mutation of raw predicted intensity;
- no UI/wording/notification connection.

Updated next step:

1. Freeze the broader-verification conclusion: keep `supportGeometry-only` as
   pooled diagnostic context only, not as a production family score.
2. Do **not** continue generalizing this score by threshold or wording.
3. Inspect the minor-event pooled remainder created by
   `leave_event_out::2022070605102497-38.4125-141.9545` and test whether any
   other runtime-visible signal separates near-threshold positives from false
   middle-transition cells there, or explicitly conclude that no stable minor-
   event family score exists.

## 15. PLUM Tohoku mismatch/one_sided/compact Minor-Event Pooled Signal Diagnostic

The next documented step was to inspect that minor-event pooled slice directly.
That continuation is now implemented.

Added artifacts:

| Item | Path | Notes |
| --- | --- | --- |
| spec | [.trae/specs/plum-tohoku-mismatch-one-sided-compact-minor-event-pooled-signal-diagnostic/spec.md](../.trae/specs/plum-tohoku-mismatch-one-sided-compact-minor-event-pooled-signal-diagnostic/spec.md) + tasks.md + checklist.md | Completed |
| tool | [tools/build_plum_tohoku_mismatch_one_sided_compact_minor_event_pooled_signal_diagnostic_report.dart](../tools/build_plum_tohoku_mismatch_one_sided_compact_minor_event_pooled_signal_diagnostic_report.dart) | compares validation-anchored score variants, ranked runtime-visible feature buckets, and sample ledger on the minor pooled slice |
| test | [test/plum_tohoku_mismatch_one_sided_compact_minor_event_pooled_signal_diagnostic_report_test.dart](../test/plum_tohoku_mismatch_one_sided_compact_minor_event_pooled_signal_diagnostic_report_test.dart) | 8-minute timeout; asserts non-production policy, variant comparison, ranked separators, and sample ledger |
| report | [docs/baselines/plum_tohoku_mismatch_one_sided_compact_minor_event_pooled_signal_diagnostic.generated.md](baselines/plum_tohoku_mismatch_one_sided_compact_minor_event_pooled_signal_diagnostic.generated.md) | validation target modes `278`; minor-slice target modes `11`; minor-slice events `3`; status `pass` |
| document | [source_estimation_roadmap.md](source_estimation_roadmap.md) section `## 2026-06-28 PLUM Tohoku mismatch/one_sided/compact Minor-Event Pooled Signal Diagnostic` | Added |

Key findings:

- All current score variants fail on the minor pooled slice:
  - `support_geometry_only`: mean gap `0.007`, `not_stable`
  - `support_geometry_plus_proximity`: mean gap `-0.061`, `not_stable`
  - `full_score`: mean gap `-0.041`, `not_stable`
- None of them retain a validation-anchored high band:
  - all three have `0` minor-slice samples in the `high` band
  - all three share the same broken quartile pattern: quartile 3 is entirely
    false middle-transition (`0` near / `3` false)
- The minor slice itself is structurally degenerate for broad runtime signals:
  - both classes are fully one-sided (`quadrants=1.0`)
  - both have zero spread and fully concentrated evidence
    (`top1 share = 1.0`, `HHI = 1.0`)
  - this collapses most geometry/concentration distinctions
- The strongest remaining feature buckets are only tiny directional fragments:
  - `centroidOffsetBand=5_to_10`: `1` near / `5` false
  - `evidenceCountBand=gte_16`: `1` near / `4` false
  - `evidenceCountBand=12_to_15`: `3` near / `1` false
  - `centroidOffsetBand=gte_10`: `3` near / `1` false
- Those fragments conflict with each other and remain too small to justify a
  stable runtime-visible family score.

Boundary:

- still diagnostic-only;
- no PLUM radius/damping tuning;
- no suppression gate;
- no mutation of raw predicted intensity;
- no UI/wording/notification connection.

Updated next step:

1. Freeze the branch conclusion: no stable minor-event family score is
   currently demonstrated.
2. Keep `supportGeometry-only` scoped to pooled diagnostic context only.
3. Do **not** continue tuning minor-slice thresholds or wording.
4. Only revisit this branch if additional manifests enlarge the minor-event
   pooled slice enough to re-test with materially more support.

## 16. PLUM Tohoku mismatch/one_sided/compact Branch Closure

The current PLUM-led `tohoku` / `mismatch` / `one_sided` / `compact` branch is
now closed rather than extended with more bucket tuning.

Closure decision:

1. The branch found a real frozen-test failure mode, but not a stable
   production-usable runtime score.
2. `supportGeometry-only` remains useful as pooled diagnostic context, but it
   is not broadly transferable after dominant-event removal.
3. The minor-event pooled slice has only `11` target-mode samples across `3`
   events, and all tested runtime-visible score variants are `not_stable`.
4. No PLUM radius/damping change, suppression gate, raw intensity mutation,
   UI/wording wiring, or notification wiring should be made from this branch.

Reopen condition:

- Revisit only when additional manifests materially enlarge the minor-event
  pool. Until then, the next useful work is dataset/replay expansion and
  re-running the existing diagnostics after the sample pool changes.

Roadmap sync:

- [source_estimation_roadmap.md](source_estimation_roadmap.md) now has
  `## 2026-06-29 PLUM Tohoku mismatch/one_sided/compact Branch Closure`.
