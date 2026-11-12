# Jian 统一 UI 接入核验（2026-10-10）

本文先记录修复前的核验事实；文末“后续修复”记录用户授权后的代码变更及验证结果。

核验基线：`ac247d859919d182056bb01a51fcc9d1a7bc1e78`。本次核验不修改业务代码，不改写原始事件的字段、时间或坐标，不向实时连接注入历史事件。

核验覆盖已注册的 46 类 Jian 地震来源：解析、原文保留、统一模型序列化、列表转换、事件身份及桌面与安卓后台接纳逻辑。使用真实历史原文渲染 6 类 EEW 卡片。另读取当前官方文档 <https://api.sismotide.top/api/>，与本地来源注册对照。

## 已复现的问题

### 1. CEA、CEA 省网、SA 的预估烈度只更新文字，没有更新颜色

原始报文未提供烈度时，展示层已经计算预估烈度；事件的原始 `maxIntensity` 保持 `-`，这一点符合保留上游事实的要求。问题在于颜色仍读取这个原始空值产生的 `className`。

| 原始样本来源 | 实际徽章 | 实际颜色 | 现有应用对应的烈度颜色 |
| --- | --- | --- | --- |
| `cea` | 预估烈度 VI | 灰色 `#CFCFCF` | 黄色 |
| `cea-pr` | 预估烈度 IV | 灰色 `#CFCFCF` | 蓝色 |
| `sa` | 预估烈度 V | 灰色 `#CFCFCF` | 绿色 |

徽章、卡片标题背景、边框均受影响。证据：`lib/widgets/ui/alert_module.dart:998`、`:1035`、`:1098`、`:1132`。预估值在 `estimatedNewApiEewBadgeIntensity` 计算，颜色没有随该展示值计算。

### 2. CWA EEW 徽章与整张卡的颜色不一致

真实样本显示“预估震度 3”，徽章已经是绿色；标题与卡片边框仍按原始空震度的 `dark-gray` 显示。CWA 徽章分支单独取了颜色，但整卡仍按原始 `className` 取色。

证据：`lib/widgets/ui/alert_module.dart:1121` 的 CWA 分支与上述整卡取色路径不同。应在展示层统一得到显示值和配色，不能为修颜色而把估计值写成上游实测值。

### 3. CENC 列表合并已修，统一 UI 的事件身份仍未同步

使用 10 月 9 日宝兴县同一事件的两份原始报文：

| 字段 | Wolfx 原文 | Jian 原文 |
| --- | --- | --- |
| ID | `CD.20261009122537.626` | `CD.20261009122537.626_M` |
| 发震时间 | `12:21:53` | `12:21:00` |
| 列表匹配结果 | 同一事件 | 同一事件 |
| 统一 UI 身份 | `cencEqlist\|observation\|1791519713000000\|30.29\|102.85` | `cencEqlist\|observation\|1791519660000000\|30.29\|102.85` |

列表会去掉已知的 `_M` 后缀比较 ID；统一身份分支仍优先使用包含秒精度的观测键，结果不相等。即使先登记第一份报文的身份，再接入第二份，仍不相等。

桌面 `_isSameUnifiedInfoEvent` 直接比较这两个身份；安卓后台调用同一身份函数，因此也受影响。影响同震修订、新旧事件判断及已见状态，不等于一定同时出现两张卡：信息卡本身还有按来源占用一个位置的逻辑。

证据：`lib/core/utils/catalog_event_identity.dart:368`、`:491`；`lib/providers/quake_provider.dart:4441`；`lib/services/background_event_processor.dart:358`。

### 4. USGS、GeoNet 的复核状态没有进入展示和合并使用的统一字段

两份实际原始数据都有 `infoTypeName: Automatic`，转换后的列表模型却为 `reviewType: null`，`infoTypeName` 变成泛化的机构标题。原文仍保存在 `sourcePayload`，但显示和复核升级判断读取的字段丢失了这一状态。

`convertJian` 读取 `infoTypeName` 后，仅 CENC 把它接入 `reportNumText`；其他来源丢掉了这一展示字段。`_unifiedReviewType` 又只读标题和报次文字，因此无法读到原文的 Automatic。不能据此宣称所有卡片一定不显示“自动测定”：列表另有显示兜底，但其数据已经失去来源明确给出的状态。

证据：`lib/services/quake_event_adapter.dart:295`、`:334`；`lib/providers/quake_provider.dart:3030`、`:3644`。

## 当前文档与代码确认的遗漏

### 5. Jian SA 固定报号会挡住同一事件的内容更新

当前官方 SA 文档明确说明 `number` 固定为 1。适配器却将其视为有递增报次的来源。接纳逻辑遇到小于等于已有报号时，只允许无报次来源的实时修订，或符合条件的 WHEWS 同报修订；Jian SA 不属于这两条路径。

因此同 ID 的 Jian SA 后续震级、位置、深度等正文发生变化、报号仍为 1 时，会被拦截。桌面与安卓后台逻辑都有这一问题。本次没有取得两份有明确新旧关系的 Jian SA 变更原文；此结论来自当前上游契约与代码分支核对，不冒充实时复现。

证据：`lib/services/quake_event_adapter.dart:294`、`:367`；`lib/providers/quake_provider.dart:3718`、`:3967`；`lib/services/background_event_processor.dart:821`。

### 6. JMA 普通地震信息的订正状态未进入标题

适配器识别了 `infoType == 取消` 并设置取消布尔值，这部分不是完全没接。遗漏在于普通 JMA 信息的 `infoType` 没有接入报次状态文字；`reportNumText` 只有报号与最终报标志。统一标题又有意隐藏普通 JMA 的纯报号，只保留括号里的状态，所以订正无法通过这条链路显示。

本次捕获的 JMA 列表 50 条均为发布报文，没有实际订正/取消样本，未声称完成这些场景的运行验证。

证据：`lib/services/quake_event_adapter.dart:269`、`:334`；`lib/models/unified_event_presentation.dart:298`。

### 7. 普通卡片时间仍按来源时区显示

真实 JMA、KMA 原文转换后显示 UTC+9；当前电脑为 UTC+8。普通统一卡调用 `formatUnifiedOriginClock`，其显示时钟使用事件 `timeZone`。墨西哥等专门分支才调用电脑当地时区函数。

这是显示路径的不一致；源时间解析与原文保留没有因此被改写。若按此前约定统一使用电脑当地时区，普通 Jian 卡片这条路径也需要接入。

证据：`lib/core/utils/quake_time.dart:117`、`:174`；`lib/models/unified_event_presentation.dart:257`。

## 来源覆盖边界

当前注册的 46 类为 6 类 EEW、40 类地震信息。逐项解析与模型往返验证均完成，原始 `sourcePayload` 保持一致；这不代表每类都完成了所有更新场景的运行验收。

6 类 EEW：`cea`、`cea-pr`、`cwa-eew`、`jma-eew`、`sa`、`kma-eew`。

40 类信息：见 `lib/models/jian_sources.dart`；完整逐项结果保存在本次核验的 `observations.json`。

当前上游文档还列出 NMEFC、CWA、JMA、USGS 海啸，以及 JMA 火山、USGS 火山、USGS VONA。这些类型不在 Jian 的地震来源注册表，收到后只登记到 `ignoredTypes`，不会进入已有海啸/火山统一 UI。此前接入文档已经把部分非地震类型列为未接入范围；本次将此作为覆盖边界单列，不与已接来源的回归混为一谈。天气、GDACS、IFRC 同样不在这 46 类地震来源中。

证据：`lib/services/sources/jian_service.dart:254`；`docs/jian_api_integration.md`。

## 验证与局限

- 真实原文：`test/fixtures/jian/all.json`、`test/fixtures/catalog_20260917/jian_all.json`、`test/fixtures/catalog_20260917/whews_all.json`、`test/fixtures/jian/jmalist_response.json`，以及 `test/fixtures/cenc_history_20261009/` 下 Wolfx/Jian 原文。
- 6 类 EEW 实际 Flutter 控件渲染；CEA、CWA 截图已核对。
- 本次诊断与已有相关测试 199 项通过；补查 Early-est、CENC 列表及统一 UI 生命周期、倒计时语音 29 项通过，共 228 项。通过的是现有测试与诊断断言，不代表上述缺陷已修复。原来的 CEA 徽章测试检查了文字和布局，没有断言颜色，因此不能挡住这次颜色遗漏。
- 测试环境打印了 SQLite 未初始化的已有日志；不能把本次测试说成数据库或实际设备持久化验收。
- 核验产物位于忽略目录 `.dart_tool/jian_unified_audit_20261010/`：原始官方文档、逐来源观察结果、诊断测试、控件截图及测试日志。未连接用户 APP 触发实时事件，未执行手机设备上的 UI 验收。
- 本次只增加核验报告与忽略目录内的诊断产物，没有修改业务逻辑、提交、构建或上传。

## 46 类逐项核验记录

原文烈度为空时，以下“模型烈度”可能是已有的估计结果；此表不把估计结果当作原始观测。EEW 的预估徽章另见上文。所有行均验证原文保持一致及统一模型序列化往返。

| Jian 类型 | 统一来源 | 模型烈度 | 模型颜色 | 报次/状态 |
| --- | --- | --- | --- | --- |
| `cea` | `ceaEew` | - | gray | 第1報 |
| `cea-pr` | `ceaEew` | - | gray | 第1報 |
| `cwa-eew` | `cwaEew` | - | dark-gray | 第4報 |
| `jma-eew` | `jmaEew` | 4 | yellow | 第7報（最終） |
| `sa` | `sa` | - | gray | 第1報 |
| `kma-eew` | `kmaEew` | 6.0 | yellow | 空 |
| `cenc` | `cencEqlist` | 5.0 | green | [正式测定] |
| `cwa` | `cwaEqlist` | 3 | green | 空 |
| `jma` | `jmaEqlist` | 2 | blue | 第1報 |
| `kma` | `kmaEqlist` | 1.0 | dark-gray | 空 |
| `usgs` | `usgsEqlist` | - | gray | 空 |
| `emsc` | `emsc` | 2.0 | gray | 空 |
| `hko` | `hko` | 7.0 | orange | 空 |
| `gfz` | `gfz` | 4.0 | blue | 空 |
| `bcsf` | `bcsf` | 2.0 | gray | 空 |
| `usp` | `usp` | 3.0 | sky-blue | 空 |
| `ningxia` | `ningxia` | 3.0 | sky-blue | 空 |
| `yunnan` | `yunnan` | 6.0 | yellow | 空 |
| `shanxi` | `shanxi` | 0.0 | gray | 空 |
| `beijing` | `beijing` | 3.0 | sky-blue | 空 |
| `tmd` | `whews_tmd` | 3.0 | sky-blue | 空 |
| `mmd` | `whews_mmd` | 6.0 | yellow | 空 |
| `bmkg` | `whews_bmkg` | 6.0 | yellow | 空 |
| `geonet` | `whews_geonet` | 1.0 | dark-gray | 空 |
| `ingv` | `whews_ingv` | 3.0 | sky-blue | 空 |
| `nrcan` | `whews_nrcan` | 1.0 | dark-gray | 空 |
| `afad` | `whews_afad` | 2.0 | gray | 空 |
| `ipma` | `whews_ipma` | 4.0 | blue | 空 |
| `noa` | `whews_noa` | 1.0 | dark-gray | 空 |
| `sed` | `whews_sed` | 1.0 | dark-gray | 空 |
| `scsn` | `whews_scsn` | 2.0 | gray | 空 |
| `gsras` | `whews_gsras` | 5.0 | green | 空 |
| `phivolcs` | `whews_phivolcs` | 2.0 | gray | 空 |
| `ssn` | `whews_ssn` | 5.0 | green | 空 |
| `ga` | `whews_ga` | 6.0 | yellow | 空 |
| `peru` | `whews_igp` | 4.0 | blue | 空 |
| `ipgp` | `ipgp` | 1.0 | dark-gray | 空 |
| `infp` | `infp` | 2.0 | gray | 空 |
| `isc` | `isc` | 7.0 | orange | 空 |
| `knmi` | `knmi` | 1.0 | dark-gray | 空 |
| `ncedc` | `ncedc` | - | gray | 空 |
| `lmu` | `lmu` | 2.0 | gray | 空 |
| `koeri` | `koeri` | 2.0 | gray | 空 |
| `csn` | `csn` | 2.0 | gray | 空 |
| `igepn` | `igepn` | 3.0 | sky-blue | 空 |
| `early-est` | `earlyEst` | 5.0 | green | 第6報 |

## 后续修复（同日，用户授权后）

上述七项缺陷已修复于本地代码：

1. CEA／省网／SA 的预估值复用现有烈度配色，徽章、标题、边框一致；估计值与颜色只影响展示，原始字段不被替换。
2. CWA EEW 整卡复用既有 CWA 震度配色。
3. CENC 的统一身份与列表使用相同的已知 ID 后缀规则；完整秒值优先于同一报文的分钟副本，保留入站原始 ID 与 API，不重置首次到达时间。前台的精度补全不重复通知。
4. 统一读取原始复核状态，接入标题状态、列表徽标、主体去重及跨平台修订；自动报不能覆盖正式报。首次正式报可替换已关闭的自动报一次，重复或已关闭正式报保持拦截。
5. SA 固定报号保留显示，但不当作递增报次使用。实时同 API 的正文修订可更新；重复正文、首连缓存和无时间证据的其他 API 副本仍受拦截。
6. 普通 JMA 信息接入订正／取消状态；按既有约定不显示普通信息的纯报号。原始 serial 仍保留在 payload。
7. 普通统一卡和通知转换到电脑当地时区，来源时间、身份与过期计算不变；时区标签使用该显示时刻实际的偏移。

修订接纳检查中还补齐了无递增报次 EEW 的警报、最终报和仮定震源标志比较，避免只更新标志时被当成重复正文。

验证结果：27 个相关测试文件合计 **398 项通过**。新增回归见 `test/jian_unified_adaptation_test.dart`。覆盖原始样本、桌面／手机尺寸的实际 Flutter 卡片、CENC 两种到达顺序与关闭保护、自动转正式、SA 固定报号、警报标志变化、安卓接续、既有语音／EMSC／USGS／CWA 流程。原始抓取报文没有修改；时序与状态边界使用明确标注的独立模型／契约测试。

静态分析未发现错误；其他文件仍有既有警告及风格提示。测试中的数据库未初始化日志仍属于测试环境局限，不代表验证了实际设备数据库。

修复后原始样本截图：`build/test-previews/jian_fixed_cea.png`、`jian_fixed_cea-pr.png`、`jian_fixed_sa.png`、`jian_fixed_cwa-eew.png`；已人工核对 CEA、CWA。未向运行中的 APP 注入事件，未构建新安装包或发布。海啸／火山等整类新增接入仍按前述覆盖边界单列，本次没有扩展来源范围。
