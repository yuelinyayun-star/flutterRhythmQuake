# 震级斜率修正 —— 交接说明（交给实现方继续修改）

> 交接日期：2026-10-11
> **状态（2026-10-14 更新）：已落地。** 生产已切换到 `a=0.7016 / c=0.0903`（距离项与钳位不动），
> 单测 37 项全绿、`flutter analyze` 无 issue、端到端实测与预测逐位吻合。
> 变更与验证记录见 `docs/reference/magnitude_algorithm_multievent_20261010.md` **§18**。
> 本文以下内容保留为**改动依据与验证门**，无需重复施工。
> 交接原因：本机当前在做**后端重构**，前端（Flutter）改动不便在本机落地，故将「已定性的修改方案 + 证据 + 验证门」整理成文，交由实现方直接从代码层接手。
> 本文**自包含**：不需要阅读任何前序对话即可动工。所有数字都可用文末脚本一键复现。

---

## 0. 一句话任务

修改 `lib/core/source_estimation/srev_kaizou_magnitude.dart` 中**震级公式对「震度 I」的系数**（现为隐含 `1.0`，改为约 `0.70`，并成对重定标常数），即可把「低震度档系统性低估」的偏差拉平。

**不要动距离项的 20km 下限钳位**（有消融证据，动了更差，见 §4）。

---

## 1. 问题是什么

应用对**小震（震度 1–2 档）**的震级估计系统性偏低，最严重时欠估约 **−1.9 级**；而对**高震度档（震度 5–6）**反而略**高估**（+0.5 ~ +1.0）。

这个「偏差随震度档单调变化」的现象，在三套**互相独立**的语料上完全一致：

| 语料 | 内容 | 规模 | 来源 |
|---|---|---|---|
| A. K-NET 波形 | 波形 → 官方 JMA 计测震度（公式级对照） | 52 事件 | `tmp/knet_mag_lab/` |
| B. `.rqreplay` 云端回放 | kmoni JMA 图层真值近场峰值 + 真距离 | 10 可靠事件 | `tmp/rqreplay_probe/` |
| C. 桌面捕获端到端 | App 真实运行回放 | 9 事件 | `tmp/capture_survey/` |

三套管线独立、数据来源不同，却给出同一条规律 ⇒ 不是单一样本噪声。

---

## 2. 生产公式现状（逐字，改之前务必先读）

文件：`lib/core/source_estimation/srev_kaizou_magnitude.dart`

**① 关键函数（第 203–226 行）**

```dart
double? srevKaizouMagnitudeFromDistanceAndIntensity({
  required double stationDistanceKm,
  required double inputIntensity,
  required bool multipleSources,
}) {
  if (!stationDistanceKm.isFinite ||
      stationDistanceKm <= 0.0 ||
      !inputIntensity.isFinite) {
    return null;
  }
  final processedIntensity = srevKaizouProcessedIntensity(
    inputIntensity,
    multipleSources: multipleSources,
  );
  final intensityExponent = (processedIntensity - 0.94) / 2.0;
  final firstIntensityPower = math.pow(10.0, intensityExponent).toDouble();
  final secondIntensityPower = math.pow(10.0, intensityExponent).toDouble();
  final intensityProduct = firstIntensityPower * secondIntensityPower;
  final magnitude =
      1.0 * (math.log(intensityProduct) / math.ln10) +          // ← 对 I 的系数 = 1.0
      1.73 * (math.log(stationDistanceKm) / math.ln10);         // ← 距离项系数 = 1.73
  if (!magnitude.isFinite) return null;
  return magnitude < 0.0 ? 0.0 : magnitude;                      // ← 硬底 0
}
```

> 注意那两行 `math.pow(10.0, exponent)`：两次相同的幂相乘，再取 `log10`，数学上恒等于 `(processedIntensity − 0.94)`。
> 也就是说，**对震度 I 的实际斜率就是最外层那个 `1.0`**（第 222 行）。这是需要改的数。

**② 距离钳位（第 261–264 行，`calculateSrevKaizouMagnitude` 内）**

```dart
final clampedDistanceKm = math.max(
  nearestDistanceKm,
  srevKaizouMinimumStationDistanceKm,   // = 20.0（文件顶部第 7 行常数）
);
```

即 `D_used = max(最近站距, 20km)` —— **下限钳**。近场内陆浅震几乎必然被钳（多数事件最近站 < 20km），此时 `1.73·log10(D)` 退化为常数 `1.73·log10(20) = 2.251`。

**③ 分段压缩（第 193–201 行）** —— 仅 `multipleSources=true` 且 `I>4` 时生效：

```dart
if (multipleSources && inputIntensity > 4.0) {
  return (inputIntensity - 4.0) / 2.0 + 5.0;
}
```

**把①②合起来写**，生产等效于：

```
M = 1.0 · (I_proc − 0.94) + 1.73 · log10(max(D, 20))
```

**口头结论**：斜率对 I = 1.0、对距离 = 1.73，二者都是「抄来的常数」。

---

## 3. 诊断结论：两个**彼此正交**的误差源

### 源 ①（公式级）：对 I 的斜率过大

- 生产用 `1.0`；多事件拟合给出的实证斜率是 **0.52 – 0.70**。
- 物理对应：衰减律 `I = a·M + b·log10(R) + c` 拟合出 `a ≈ 1.43`，则 `dM/dI = 1/a ≈ 0.70`。
- 后果：低档欠估、高档过估、**偏差必随档单调**（这正是观察到的主症状）。

### 源 ②（输入级）：低震度档「输入震度触底」

- App 端到端在低档时，喂进公式的 `I` 本身已被压到极低（实测底在 `0.14 ~ 0.50`，甚至出现 `−0.84`）。
- 即使改了斜率，输入太小也补不回来 —— 这是端到端（语料 C）独有的第二误差源。
- 根因是「NIED 实时震度」与「JMA 计测震度」的**语义差**（§11），不是公式系数问题。

> **结论：端到端要同时修两处。只改公式系数，只能解掉源 ① 那一半。**

---

## 4. 证据与消融（本节是「为什么这样改」的依据）

### 4.1 三语料按震度档偏差（偏差 = 预测 M − 官方 M，负 = 低估）

**A. K-NET 52 事件（公式级）**

| 震度档 | n | 生产 a=1.0 | 换 a=0.70 | 候选（逐站反演） |
|---|---:|---:|---:|---:|
| 1 | 3 | **−1.10** | −0.54 | −0.21 |
| 2 | 13 | −0.69 | −0.34 | −0.07 |
| 3 | 23 | +0.01 | +0.05 | −0.07 |
| 5 | 1 | +0.96 | +0.27 | −0.24 |
| 6 | 3 | +0.58 | −0.36 | +0.15 |
| **全部** | **52** | −0.16 / RMS 0.65 | −0.16 / RMS **0.52** | −0.06 / RMS **0.32** |
| **档间极差** | | **2.06** | **1.12** | **0.52** |

- 只改 I 系数（距离项一字不动、整体均值保持）：**整体 bias 不变（−0.16）**，但 **RMS 0.65→0.52（−20%）、档间极差 2.06→1.12（−46%）**。
- 这是**因果消融**（只动一个参数），不是相关性。

**B. `.rqreplay` 可靠 10 事件**：生产 −0.28/RMS 0.62 → 换 a=0.70 −0.28/RMS 0.58（同向）。

**C. 桌面端到端 9 事件**：生产 −0.90/RMS 1.42 → 换 a=0.70 −0.90/RMS 1.19。
（其中档 2 换完仍 −1.83 ⇒ 就是**源 ②** 在拖后腿。）

### 4.2 「不要动 D 钳位」的消融证据

在语料 B 上做**同输入三变体**对照：

| 变体 | 平均偏差 |
|---|---:|
| 生产（下限钳 20km） | **−0.28** |
| 取消钳位（用真距离） | −0.47（**更差**） |
| 强制退化（D ≡ 20km） | −0.62（更差） |

⇒ 去掉钳位**不会变好，反而更差**。**所以本次只改 I 系数，距离处理保持原样。**

### 4.3 一条必须纠正的旧说法（勘误）

早期文档 `docs/reference/magnitude_algorithm_multievent_20261010.md` 的 **§13 结论 2** 曾称「D=20km 钳位是随距离放大的误差源」——**该说法不准确，已在该文档顶部加勘误**：生产对远场（D>20）其实用的是**真距离**，钳位只对近场（D<20）生效，效应是**抬高**近场 M。**请勿采纳 §13 结论 2。**

另一份更早的总账 `docs/reference/nied_magnitude_bias_20261003.md` 曾建议「相干配对（改用最强站自身距离）」——该建议已被 4.2 的消融**否证**（那是"取消钳位"的一种），**同样不要采纳**。

---

## 5. 修改方案

### 方案 A（廉价、建议先做）：只改 I 系数

**改动点**：`srevKaizouMagnitudeFromDistanceAndIntensity`（§2①）。

**新增顶层常数**（与 `srevKaizouMinimumStationDistanceKm` 并列放在文件顶部）：

```dart
/// 对处理震度 I 的斜率。生产原始值为 1.0；
/// 多语料留一(LOO)重拟合 ≈ 1/a_fit = 1/1.4334 ≈ 0.70。
const double srevKaizouMagnitudeIntensitySlope = 0.7016;

/// 与 slope 成对的重定标常数（使语料均值处整体偏差保持 ≈0）。
const double srevKaizouMagnitudeIntensityOffset = 0.0903;
```

**推荐写法（等价：`M = slope·I_proc + offset + 1.73·log10(D)`）**：

```dart
  final magnitude =
      srevKaizouMagnitudeIntensitySlope * processedIntensity +
      srevKaizouMagnitudeIntensityOffset +
      1.73 * (math.log(stationDistanceKm) / math.ln10);
```

> 若为「忠实复刻上游工具」而必须保留原 `pow10` 链条，用这个等价写法（`log10(product) ≡ I_proc − 0.94`）：
>
> ```dart
>   final magnitude =
>       srevKaizouMagnitudeIntensitySlope *
>           (math.log(intensityProduct) / math.ln10 + 0.94) +
>       srevKaizouMagnitudeIntensityOffset +
>       1.73 * (math.log(stationDistanceKm) / math.ln10);
> ```

**系数出处（请照抄，别自拟）**：
- `a = 0.7016` = K-NET 52 事件 LOO 重拟合（`tmp/mag_scoreboard/ablation.json` → `knet.fit2_in.a`）。
- `c = 0.0903` = 同源 `knet.fit2_in.c`，是「距离项系数固定为 1.73」的两参拟合常数。
- 交叉验证：rqreplay 10 事件独立拟合出 `a = 0.6193, c = 0.0670`（同向，量级一致）。

**预期效果**（对照 §4.1 表）：档间极差 ≈ 2.06 → 1.12，RMS 0.65 → 0.52，整体 bias 保持 −0.16。

**建议同时**把 `srevKaizouMagnitudeModelId`（文件第 10 行）与模型诊断里的 `srev_kaizou_magnitude_arithmetic` 标注更新（如 `..._v2` / 追加 `intensity_slope_0.7016`），避免新旧行为在日志里不可区分。

---

### 方案 B（最优、后续）：接入「逐站反演」候选

**已存在的影子实现**（未被生产引用）：`lib/core/source_estimation/magnitude_perstation_candidate.dart`

- 类：`MagnitudePerStationCandidate.estimate({ required List<MagnitudeStationIntensity> stations, required double sourceLatitude, required sourceLongitude, ... })`
- 每站用**自身震源距**反演 M，再 **MAD 稳健合并**（天然绕开单点钳位、也自发处理离群站）。
- 标定：`kMagnitudeCalibSmallM1V1`（`a=1.4334, b=−3.3730, k=0, c=0.9120`，小震 M<5 操作域）。
- 效果（§4.1 表右列）：档间极差 **0.52**、RMS **0.32**、全档近零。
- **代价/前提**：需要**逐站「(震度, 坐标)」列表**；而生产当前只把「全局最大震度 + 最近站距离」两个标量喂给公式。接线前需先在 `lib/core/source_estimation/source_estimator.dart`（`calculateCurrentSrevMagnitude` 附近，约第 1523 行）把逐站数据暴露出来——这是**接口改动**，建议方案 A 落地、验证通过后再做。

---

## 6. 必须同步修改的测试与工具（否则构建/CI 会红）

### 6.1 会被**改坏**的测试（改完必须同步更新）

**文件：`test/srev_kaizou_magnitude_test.dart`** —— 有且仅有 2 处会失败：

| 用例 | 行号 | 失败原因 | 处理 |
|---|---|---|---|
| `keeps the two pow10 operations and outer log10 chain` | 100–118 | 硬编码了旧公式 `1.0*(...) + 1.73*(...)` 作为期望值 | 改为按 `slope*I + offset + 1.73*log10(D)` 重算期望，或直接删掉该用例（它只是「结构快照」，非行为断言） |
| `clamps negative magnitude to zero` | 129–138 | 用例 `I=−3.0, D=20` 期望 `0.0`；新式给正值（≈`0.24`）⇒ 不再触发钳零 | 改成用更极端的输入触发钳零（如 `I=−10`），或在函数内对 `I` 设下限后再测 |

> ⚠️ **不要**为了让这两条过而把系数改回去——那是「测试倒逼实现」，会掩盖本次修复。

### 6.2 已确认**不会**被改坏的测试（无需动）

- `test/source_estimator_test.dart:822-829`：期望值**也是**调用 `calculateSrevKaizouMagnitude` 现算的 ⇒ 自洽，随改动自动一致。
- `test/support/nied_magnitude_audit.dart` 等：只做「观测性反事实」记录，不断言固定 M 值。
- `test/current_capture_replay_analysis_test.dart`、`test/nied_pgv_capture_replay_test.dart`：只读取诊断字段名。

### 6.3 Python 侧复刻（**务必同步**）

**文件：`tools/knet_app_reduction.py` 第 106 行**：

```python
m = (I_proc - 0.94) + 1.73 * math.log10(D)   # ← 复刻了生产公式
```

它被用于生成「App 还原」语料。**不改这一行，语料与生产就会口径分裂。** 同步为：

```python
m = 0.7016 * I_proc + 0.0903 + 1.73 * math.log10(D)
```

（同文件第 21–23 行的注释引用了源码行号，若行号变动请一并订正。）

---

## 7. 验证门（怎么判定「改对了」）

### 7.1 Dart 单测

```bash
flutter test test/srev_kaizou_magnitude_test.dart test/source_estimator_test.dart
```

- 期望：**全绿**（含 §6.1 两处更新后的新期望）。
- 另建议跑一次全量回归：`flutter test`（重点看 `nied_*magnitude*`、`current_capture_replay*`）。

### 7.2 Python 评分台（量化「是否拉平」）

```bash
python tmp/mag_scoreboard/threeway.py      # 生成 THREEWAY.md
python tmp/mag_scoreboard/ablation.py      # 生成 ABLATION.md
python tmp/mag_scoreboard/scoreboard.py    # 生成 SCOREBOARD.md
```

逐项**通过判据**（对照改前基线）：

| 指标 | 改前 | 改后期望 |
|---|---:|---:|
| K-NET 档间偏差极差 | 2.06 | **≤ 1.15** |
| K-NET 全档 RMS | 0.65 | **≤ 0.53** |
| K-NET 整体 bias | −0.16 | **仍在 −0.16 附近（不得恶化）** |
| 档 1 偏差 | −1.10 | ≥ −0.56 |
| 档 6 偏差 | +0.58 | ≤ −0.30 |

（数值来自 §15 消融，可用 `ablation.py` 的 `a` 扫描复现。）

### 7.3 单事件抽查（改完后功能自检）

```bash
python tmp/mag_scoreboard/threeway.py --I 1.61 --D 41
```

期望输出（新式）：
```
生产  a=1.00              : M=3.460
置换  部署式 a=0.702,c=+0.090: M=4.010  (Δ=+0.550)
```

---

## 8. 资产清单（路径 + 复现命令）

**生产代码**
- `lib/core/source_estimation/srev_kaizou_magnitude.dart` ← **本次唯一必改的生产文件**
- `lib/core/source_estimation/magnitude_perstation_candidate.dart` ← 方案 B 的现成候选（影子，未接线）
- `lib/core/source_estimation/source_estimator.dart`（约 1523 行 `calculateCurrentSrevMagnitude`）← 方案 B 接线点

**测试**
- `test/srev_kaizou_magnitude_test.dart`（**必改 2 处**）
- `test/source_estimator_test.dart`（无需改）

**工具**
- `tools/knet_app_reduction.py`（第 106 行复刻公式，**必同步**）

**评测/证据脚本（系统 Python，无需 numpy）**
- `tmp/mag_scoreboard/threeway.py` → `THREEWAY.md`（三方表 + 单事件判分 CLI）
- `tmp/mag_scoreboard/ablation.py` → `ABLATION.md` / `ablation.json`（系数出处）
- `tmp/mag_scoreboard/scoreboard.py` → `SCOREBOARD.md`

**依据文档（按需查阅）**
- `docs/reference/magnitude_algorithm_multievent_20261010.md`
  - §11 低震度档触底（源 ②）
  - §12 桌面端到端重放
  - §14 误差源锁定为「对 I 的斜率」+ §13 勘误
  - §15 斜率消融（1.0 → 0.70 的因果证据）
  - §16 三方评测台 + 第二误差源
- `docs/reference/nied_magnitude_bias_20261003.md`（更早总账；其「相干配对」建议**已被否证**，仅作历史）

---

## 9. 边界、风险与禁忌

1. **别动 D 钳位**（§4.2 两处消融一致：去掉更差）。
2. **别动 `multipleSources` 的 `(I−4)/2+5` 分段压缩**——它是另一条独立规则，本次不在范围内。
3. **只解掉源 ①**：单公式改完，端到端低档仍会残留（源 ②），这属预期，不要试图用「再压系数」硬凑。彻底解需方案 B 或修输入震度语义。
4. **小样本约束**：语料里震度 1 档仅 3 例。结论应表述为「方向 + LOO 表现」，**不要**把 `a=0.7016` 当成高精度常数（写成 0.70 亦可）。
5. **档 7 残余**：改后高档仍略过冲（源于分段压缩 + 事件间散射），这是单公式的固有极限，方案 B 才能进一步压。
6. **改完更新 model id / 诊断标注**，保证新旧日志可区分。

---

## 10. 本机环境坑（若在同机复现）

- **同一文件并行编辑会丢改动**（一条消息多个 edit 只生效最后一个）⇒ 改代码请**顺序**进行，改完 grep 复核。
- PowerShell 工具**不回显 stdout**、且 `*>` 重定向产出 UTF-16 ⇒ 让脚本自己写 utf-8 文件，再读回。
- 后台 PowerShell 任务本机约 **2 分钟被硬杀** ⇒ 长任务用前台 + 长超时。
- 本机 managed Python **无 numpy** ⇒ 用系统 `Python313\python.exe`。

---

## 11. 交付判据（Definition of Done）

- [ ] `srev_kaizou_magnitude.dart` 对 I 的系数改为 `0.7016`、常数 `0.0903`（距离项与钳位不动）。
- [ ] `test/srev_kaizou_magnitude_test.dart` 的 2 处用例已同步更新且全绿。
- [ ] `flutter test` 全量通过。
- [ ] `tools/knet_app_reduction.py:106` 已同步。
- [ ] `threeway.py` 复跑：档间极差 ≤1.15、RMS ≤0.53、整体 bias ≈−0.16。
- [ ] model id / 诊断标注体现版本变化。
