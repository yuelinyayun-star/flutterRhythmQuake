# JMA EEW 特殊状态核查（2026-11-06）

后续用户已明确：PLUM 保留本项目 EEW 的波圈、闪烁、倒计时等既有行为，只接好标志与所指定的显示文字。以下是修复前核查记录，不是删改这些行为的授权；后续实施与验证见 `jma_plum_eew_fix_20261106.md`。长周期仍等待用户说明后再接入。

本轮授权是调查 PLUM、长周期及其他 JMA EEW 特殊情况，并对照已有适配。没有修改生产源码、设置、安装版或云电脑。本文件不授权后续扩大修复范围。

## 官方资料与本次取得的原件

- JMA 技术参考：https://www.jma.go.jp/jma/kishou/know/jishin/eew/katsuyou/reference.pdf （2024-04-11；纯 PLUM 假定要素、混合处理、发报条件、VXSE43/44/45/47 的区别）。
- 当前 XML 技术资料：https://xml.kishou.go.jp/tec_material.html 。本次下载 2026-11-04 解说集和 2026-09-17 样例集，保存在 `tmp/jma_eew_special_audit_20261106/`。解说集的 `地震火山関連_解説資料.pdf` 第 100–118 页定义假定震源、精度、预测震度和长周期上下限、到达时刻等。
- 长周期发报条件：https://www.jma.go.jp/jma/kishou/know/jishin/eew/lpgm_start/lpgm_start.html 。预测长周期阶级 1 以上可达予报条件；3 以上可达警报条件，必须与普通震度区分。
- WHEWS 当前文档：https://api.2v8.cn/#ws-jma_eew 。本次取得页面和实际文档资源 `assets/ws-jma_eew-D9xs_kqe.js`，不是靠旧记忆推测字段。
- JIAN 当前文档：https://api.sismotide.top/api/ 。本次取得 HTML，确认 `isPLUM` 文档说明为 PLUM／假定震源，新增可选 `lgIntensity`。
- 样例是文档公开样例，不声称是真实事件抓包。官方 XML 样例直接读取，未转换为冒充 WHEWS/JIAN 的测试数据。

## PLUM 不是“丢失震级的普通定位”

PLUM 用邻近测站实际震动预测震度，本身不求震源、震级。纯 PLUM、没有可信推定震源时，官方报文会给假定震源要素：最早触发测站的坐标、深度 10km、震级 M1.0 占位，`Earthquake/Condition=仮定震源要素`。这些不是真实定位和震级，不应用来计算普通震源的波圈、到时及本地衰减。

混合处理同时使用震源/M 方法和 PLUM，各地区取两者较大震度，仍可能有有效震源及震级。不能仅凭含 PLUM 这个词就把所有震源和震级删除。WHEWS 的布尔说明比 JIAN 更宽泛，未给出所有混合情形的字段语义；缺少明确字段的情况不能自行猜测。

刚才福島県中通り事件 `20261106194044` 原始 5 报均有 `isPLUM=true`、`isIPF=false`、`magnitude=""`、`depth=10`、`warningAreas=[]`。这是这份转发数据的实际取值；不能将官方占位 M1.0 写回这份原始数据，也不能虚构这 5 报对应的完整官方 XML。

## 已确认的当前调用问题

| 项目 | 当前证据与影响 |
| --- | --- |
| WHEWS PLUM 标志 | `quake_event_adapter.dart` 的 `_convertWhews` JMA EEW 分支未把 `isPLUM` 接入 `isAssumption`；`_jmaEew` 只读 `isAssumption`。5 报实测均由原始 true 变为统一模型 false。原始字段仍完整保留在 sourcePayload。 |
| JIAN PLUM 标志 | `convertJian` 已有 `isAssumption: raw['isPLUM'] == true`，不是完全没适配；但后续处理不完整。 |
| 波圈 | `unified_event_wave_layers.dart` 按 `isEew` 打开波圈；`wave_layer.dart` 没有假定震源的传播计算排除条件，`isAssumption` 只用于标签。此项为明确源码调用证据，未宣称完成安装版视觉验证。 |
| 本地倒计时 | `local_eew_sidebar_panel.dart/calculateLocalEewEstimate` 未排除假定震源；对原始 5 报，经生产适配和真实走时表，以用户位置 29.36/120.17、经过时间 0 秒，均输出距离 2074.3895km、S 波 465 秒。本地烈度因 M=-1 为 null。465 秒是对假定参数计算的输出，不是官方发布的有效到时。 |
| 文本优先级 | `unified_event_presentation.dart`、`unified_alert_card.dart` 先判断震级缺失，再判断假定震源；只补标志也不会使缺失震级那条分支自动显示假定震源。`history_panel.dart` 的摘要又是分开拼接震级和假定深度文本，需要逐入口核查，不能只修一个标题。 |
| FAN | `fan_service.dart` 的统一输出把 `isAssumption` 固定 false。已确认输出行为，尚未用 FAN 的真实 PLUM 包复现，不能宣称每种 FAN 原报均受影响。 |
| Wolfx | 通用 JMA EEW 适配读取已有 `isAssumption`，不能把 WHEWS 的字段修复直接覆盖 Wolfx 契约。此轮没有新的 Wolfx 特殊事件实测。 |

上述 PLUM 报仍是 EEW。震级缺失不会把 EEW 变成 JMA/P2PQ“震源调查中”震度情报；两种产品必须保持区分。本轮不改变任何情报填色、NIED 小点、信息聚焦规则。

## 长周期与其他需要独立适配的情况

| 情况 | 字段或官方语义 | 当前接入边界 |
| --- | --- | --- |
| EEW 预测长周期 | WHEWS `maxLgInt`（0–4，空字符串无数据）；JIAN `lgIntensity`（可选，缺失表示无数据） | 文档原样例经过实际适配后只在 sourcePayload 保留，没有 EEW 统一预测字段或对应显示。现有 `JmaLpgmBulletin` 是震后观测产品，不能混用。 |
| 警报依据 | 普通震度和长周期可分别触发警报 | 当前两源已有 isWarn／警報识别；不能自行要求震度达到 5- 才承认上游警报，也不能把长周期 3 当震度 3。 |
| 警报地域名单 | WHEWS `warningAreas[].name/code/scope`；没有逐区域震度值 | 当前 `_parseJmaWarnArea` 只读 Wolfx 格式，WHEWS 文档的非空名单实测变成统一模型空串。修复若接名单，只能保留名单的语义，不能把最大震度套给所有区域。 |
| 震度上下限 | JIAN `intensityFrom/intensityTo`；官方 XML `ForecastInt/From/To`，含 `over`（某值以上）及不明 | 当前 JIAN 仅取 intensityTo 或 intensity，再降为 name/intensity/className，未结构化保留下限和 over。sourcePayload 保持原始值。 |
| 长周期上下限／区域值 | VXSE45 及警报 XML 的 `ForecastLgInt/From/To`，0 表示阶级 1 未满，与缺测不同 | 当前最大阶级字段尚未接入，地区预测也未形成 EEW 模型。WHEWS/JIAN 是否提供完整地区长周期值须以实际字段为准，不能按震后观测数据补造。 |
| 到时语义 | 普通区域 ArrivalTime 为预测到时；PLUM 区域同字段表示首次预测该震度的时刻；Condition 可表示已到达 | 当前 JIAN 地区归一化只保留震度相关三个字段，未承接这一整套语义；不可统一转成 S 波倒计时。 |
| IPF／可信度／阶段 | `isIPF`；官方 Accuracy、rank2=9 等 | `isIPF=false` 也可能是上游无法判明，不能推导必为 PLUM。rank2=9 是定位/M 已达最终精度，PLUM 地区仍可能更新，不等于整事件最终报。当前没有完整统一元数据支持；未使用完整真实包做所有阶段验证。 |
| 强震检出／单站／深发 | レベル法可无 M；单站或深度大于 150km 时，官方可不提供震度预测，PLUM 有例外 | 合法的缺失必须与解析丢失区分；不能仅凭缺失就套用普通震级估算。此轮已查官方规则，未声称这些每一类都有转发源原报复现。 |
| 取消／训练／最终报 | cancel/isCancel、isTraining、final/isFinal | 已有相关适配和训练过滤，不是从零缺失。未来修特殊状态必须保留这些路径以及报序、原始载荷、历史和 OBS 的既有行为。 |

## 实际验证与未做事项

`tmp/jma_eew_special_audit_20261106/current_path_audit_test.dart` 读取导出 ZIP 内原始 5 报（内容未改）以及当前两源文档样例，走生产适配、本地走时计算并保存 `current-path-results.json`。7 个只读核查用例执行完成，断言原始载荷不变；它们用于记录缺陷现状，不代表特殊 EEW 已修复。

本轮未修改生产业务、地图、UI、阈值、设置，也未编译安装包或更新云电脑。后续若获准实施，应只针对明确的 JMA EEW 特殊状态，并按项目要求把相关后端归一化与计算资格策略落到 Rust，保留各入口原始数据与既有行为；不能只给 Dart 增加字段映射就宣称全链路完成。
