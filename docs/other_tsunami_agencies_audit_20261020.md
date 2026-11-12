# 其他海啸机构接入核验

2026-10-21补充：NMEFC原生解析、报次接纳、无坐标观测保留及右侧完整分页已补齐，
详见`nmefc_adaptation_20261021.md`。以下是2026-10-20历史核验，不代表上述改动后的状态。

核验日期：2026-10-20。依据当前代码、当前 APP 已接收的消息字段，以及已有原始样本。这里只记录适配边界，不修改机构原报文，也不改变 JMA 左下预报列表。

## 当前入口与可显示内容

| 机构 | 当前入口 | 已有结构化内容 | 当前缺口 |
| --- | --- | --- | --- |
| 国家海洋预报台 NMEFC | WHEWS `tsunami`；既有 FAN 分支也有入口 | `forecasts` 的预报地区、预警颜色、预计到达、波高；`waterLevelMonitoring` 的观测站、位置、时刻、实测波高 | 当前模型未保留 `sourcePayload`，批次仅拼进标题，没有写入统一报次。无有效坐标的观测站在解析阶段就被丢弃，文字显示也无法使用。未知等级走默认“解除”标题，需要纠正 |
| 台湾中央气象署 CWA | WHEWS `cwa_tsunami` | 报次、有效期、`reportType`、`reportColor`、`warningAreas`、`stations`、区域色、到达时间和波高文字 | 通用模型保留了原文，但部分机构专属字段没有用于展示；没有左下机构信息卡片。波高无单位的裸数不能自行当成米 |
| 太平洋海啸预警中心 PTWC | WHEWS `ptwc` | 事件、报次、等级、公报、CAP、有效期、`jsonUrl`、地图链接；活动报文可从 NOAA JSON 补预警海岸区域 | 补充服务只提取 `alerts.areaList`，并未实现完整预计波高、到达和观测产品。不能把只有公报和震源字段的消息画成有区域预报 |
| 美国国家海啸预警中心 NTWC | WHEWS `ntwc` | 同 PTWC，已有 NOAA 区域补充入口 | 同 PTWC；目前 `Watch`、`Advisory` 映射到相同通用等级，界面仍应保留原始类别 |
| 印度海啸早期预警中心 INCOIS | WHEWS `incois` | 事件、报次、等级、`bulletinType`、`updatesText`、公报描述、指示、详情页等 | 当前运行消息没有结构化区域和观测数据；不能据此认定上游所有公报都没有。需用正式原报文核验预报区、到达和预计波高结构；保留 `Warning / Alert / Watch` 的机构语义 |
| 墨西哥海啸预警中心 CAT | WHEWS `cat_tsunami` | 事件、报次、等级、描述、行动指示、`severity / urgency / certainty`、公报和 CAP | 已有原始样本为信息公报，没有区域／测站数组。应先完整显示公报信息，不生成不存在的波高、区域和验潮站 |

入口存在只证明代码已接入，不等于当前每家都有有效警报或全部字段已经适配。

## 共用链路缺口

- 左下列表目前专门读取 JMA 分级预报；其他机构尚未进入同类信息列表。
- 右侧非 JMA 分支仍使用 `areas.take(4)` 和 `observations.take(4)`，超出的项目不展示，也没有对应的完整分页。
- NMEFC 与国际公报解析、旧报拦截及展示准备仍有 Dart 处理。后续新增适配应将解析、排序、分级、关联、报次判断和分页放在 Rust；Dart 只测量并绘制。
- 预报地区、预计波高与验潮站实测必须保持各自含义。地点来自哪个字段，应由机构和产品类型明确决定，不能用站名替换预报区，也不能把单站波高直接当整个地区的最大值。
- 地图现有 NMEFC／国际海啸层主要绘制观测点和震源标记；JMA 的海岸线数据不能直接用于其他地区。只有上游提供并核验的地理信息才能用于对应地图图层。
- 后续核验要覆盖解除、降级、同事件报次更新、迟到旧报、有效期、同报补全和原报文保留。机构声明的有效期与 APP 的展示时长应区分。

## 当前运行证据

- JMA Mock 测试已解除，核验结果为 `grade=none`、预报区数量 0、左下海啸分组数量 0。
- 当前 APP 的 PTWC、NTWC 消息保留了原文中的 `jsonUrl / maps / expires / severity / urgency / certainty`；当前这两条消息没有已准备的区域或观测点。
- 当前 APP 的 INCOIS 消息原文包含 `bulletinType / updatesText / ocean / topoBathy`，模型尚未使用这些专属字段展示内容。
- 当前 NMEFC 消息的 `sourcePayload` 为空，`reportNumber` 为空。以上是运行状态证据，不能替代尚未取得的其他等级真实报文。

## 适配次序

1. NMEFC 与 CWA：已有地区／测站结构，先补齐字段保留、机构等级、生命周期及显示准备。
2. PTWC 与 NTWC：核验官方 JSON 与公报，完善区域和原始预警类别展示；对有结构依据的数据接地图。
3. INCOIS 与 CAT：先按实际可得的公报产品完整显示；取得并核验结构化预报或观测报文后再接表格、波高与地图。

当前 WHEWS 在线文档访问未成功，尚未确认其最新版本是否增加上述产品字段。已有 CWA／CAT 文档示例与运行消息分别记录，不将旧文档示例称为新抓取实时报文。

## 官方资料

- WHEWS 文档入口：<https://api.beecld.com/>
- NOAA 预警类别：<https://www.weather.gov/safety/tsunami-alerts>
- INCOIS 官方公报流程：<https://tsunami.incois.gov.in/TEWS/dsssop.jsp>
- INCOIS 正式公报示例（历史产品，含分区到达时间和预计波幅）：<https://incois.gov.in/DSSProducts/Product_NTWC/Web/dss111005100000_Bulletin2_box_pub_A.html>

官方产品具备某类信息，不代表 WHEWS 当前聚合 JSON 已经提供同样的结构化字段，接入前仍需逐项核验。
