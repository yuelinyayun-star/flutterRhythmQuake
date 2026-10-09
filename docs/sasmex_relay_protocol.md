# SASMEX 地震预警接口说明

## 1. 这是什么

SASMEX 是墨西哥的地震预警系统。客户端 WebSocket 只转发网页正在使用的实时事件，
并转换成 RhythmQuake 已使用的 JSON 格式，供桌面端、移动端和 Web 端使用。

公开 CAP 接口是独立的归档输入，只用于保存原始请求、CAP XML 和解析结果，不会把 CAP
事件混入客户端实时 WebSocket。

这里的 `source: "sasmex"` 表示实时消息来源；警报展示按参考网页真实 IO 的
`info[0].severity`（优先）或顶层 `severity` 判断。Severe 对应 `isWarn: true`，
其余为检出，不附加测站范围条件。三档原始严重性全部保留，不从描述文字、
`grado` 或 `severidad` 推算。CAP 归档中的 `sasmexAlertIssued` 是独立字段，
不作为实时 IO 警报的额外门槛。

接口只输出上游实际提供并且客户端需要的内容，不伪造震级、深度、测站、PGA、PGV、
到达倒计时或官方警报等级。

## 2. 连接方式

### WebSocket

```text
wss://ws.yuelinrhythm.top/sasmex-eew
```

客户端只需要连接这一个地址。

### 运维接口

| 地址 | 用途 |
| --- | --- |
| `https://ws.yuelinrhythm.top/sasmex/health` | 查看实时源和中继运行状态 |
| `https://ws.yuelinrhythm.top/sasmex/snapshot` | 查看中继当前缓存的消息 |

这两个 HTTP 地址不是额外的数据源，也不会产生新的地震事件。

## 3. 消息外层格式

### 地震事件

外层继续使用 `type: "update"`、`source: "sasmex"`、`Data: 事件对象`。
`Data` 的字段映射见第 5 节。本地解析只接收当前参考网页
`https://asmx1-8.bolt.host/` 的真实 Socket.IO `new_message`；不接收 DOM
`simulated_alert`，明确标记为 `isSimulation` 或 `isReplay` 的包也不进入实时频道。

震中从上游顶层 `circle` 读取。原文格式为“纬度,经度 半径”，保留原始
`circle`，只把第一个经纬度对转为我们的 `lat` / `lng`。不会使用网页的默认
州坐标、默认墨西哥城坐标或 `[0, 0]` 占位来补造震中。

### 心跳

```json
{
  "type": "heartbeat",
  "source": "sasmex",
  "timestamp": "2026-10-07T08:00:00.000000+00:00"
}
```

### 查询当前缓存

客户端可以发送：

```json
{"type":"query"}
```

服务端返回：

```json
{
  "type": "query_response",
  "source": "sasmex",
  "Data": null
}
```

有缓存时，`Data` 是当前真实 IO 消息对象；没有缓存时为 `null`。
连接时的 `snapshot` 和查询的 `query_response` 都只使用实时 IO 缓存，
不会返回独立 CAP 归档数据。

### 心跳检测

客户端可以发送字符串 `ping` 或：

```json
{"type":"ping"}
```

服务端返回 `type: "pong"`。

## 4. 两类事件消息的区别

### 4.1 网页实时事件

这类消息来自真实 Socket.IO `new_message`，三档都已接入本项目统一 UI 的
EEW 消息。Minor / Moderate 为检出展示，Severe 为警报展示，保留其原始档位。
心跳先按 `type: "heartbeat"` 分流，不会因夹带 severity 而变成地震事件。

地域名称复用网页的确定性文本匹配：先检查 `info[0].description`，再检查顶层
`description`，最后检查 `title`，按网页固定州名列表查找。没有匹配时，仅保留
上游明确提供的 region / place / location；不生成默认地点。

### 4.2 正式警报报文（仅归档）

这类消息来自独立归档的正式警报报文。只有上游明确给出已经执行警报动作的状态，
才会出现 `sasmexAlertIssued: true`。这类 CAP 报文不会通过客户端实时 WebSocket
发送；字段只保存在归档包中供追溯。

`sasmexAlertIssued: false` 表示这条消息没有确认已经执行警报动作，不能当作公众警报。

## 5. 字段说明

### 5.1 通用字段

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `type` | string | 消息类型。`update` 是事件更新，`heartbeat` 是心跳，`pong` 是心跳响应。 |
| `source` | string | 消息来源标识。SASMEX 消息固定为 `sasmex`。这不是警报状态。 |
| `Data` | object/null | 地震事件内容。查询时没有缓存可以是 `null`。 |
| `id` | string | 优先使用上游 identifier，其次 id；都没有时使用上游 sent / updated 原文作为稳定键，不生成本地时间编号。 |
| `eventId` | string | 与 id 相同。 |
| `epochMs` | number | 优先从上游 sent 解析 Unix 毫秒值，没有有效 sent 时使用 updated；不把接收时间写成事件时间。 |

### 5.2 网页实时事件字段

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `region` | string | 依照网页描述/标题匹配出的州名，或上游明确给出的地点。缺失时不补值。 |
| `circle` | string | 顶层 circle 原文，保留中心与半径文本。 |
| `lat` | number | 由 circle 第一个经纬度对读取的纬度。无有效 circle 时省略。 |
| `lng` | number | 由 circle 第一个经纬度对读取的经度。无有效 circle 时省略。 |
| `title` / `event` | string | 上游标题 / 事件名称。 |
| `description` | string | info[0].description 优先，其次顶层 description，最后 title；文字原样保留。 |
| `sent` / `updated` / `msgType` | string | 上游发送时间、更新时间、消息类型原文。 |
| `intensidad` | string | 上游实际提供的强度文字，仅原样保留，不从 severity 转换，也不是我们估算的烈度。 |
| `grado` | number | 上游实际提供的数值原值；当前实时网页未确认其官方等级含义，不用于生成徽章或判断警报。 |
| `severidad` | number | 上游实际提供的数值原值；不作为震级、烈度或是否发警报的依据。 |
| `severity` | string | 上游明确提供的严重性原文，例如 `Minor`、`Moderate`、`Severe`。上游没有该字段时不输出。 |
| `isWarn` | boolean | 按网页全局警报规则判断；选择后的原始 severity 为 Severe 时为 true，不附加测站距离条件。缺失或其他值为 false。 |

`intensidad`、`grado`、`severidad` 只在上游实际提供时转发；不再借用其他网页或
模拟分支的文字转换逻辑补值，也不能从它们反推警报状态。

### 5.3 正式警报字段

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `sasmexAlertIssued` | boolean | 上游是否明确确认已经执行警报动作。`true` 才表示可以按正式警报处理。 |
| `sasmexAlertAction` | string | 上游给出的动作状态。`Monitor` 表示继续监测；`Execute`、`Shelter` 或 `Evacuate` 表示已经进入警报动作流程。 |
| `msgType` | string | 这条报文是首次发布、更新还是取消。它表示报文生命周期，不表示警报等级。 |
| `time` | string | 事件发生或被记录的时间，原样保留。 |
| `sent` | string | 上游发送这条报文的时间。 |
| `effective` | string | 这条消息开始生效的时间。 |
| `expires` | string | 这条消息预计失效的时间。 |
| `event` | string | 面向用户的事件标题或事件名称。 |
| `headline` | string | 警报卡片使用的简短标题。 |
| `description` | string | 上游对事件或警报范围的说明。 |
| `category` | string | 事件类别。地震预警消息通常属于地球物理事件。 |
| `urgency` | string | 上游对响应速度的要求。它不是警报等级。 |
| `severity` | string | 上游对影响严重程度的描述。它不是震级、烈度，也不能单独决定是否发警报。 |
| `certainty` | string | 上游对信息可靠程度的描述。 |

没有这些字段时，客户端不得自行补值。

### 5.4 警报区域

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `region` | string/number | 上游地区标识或地点信息。保持上游类型，不强行翻译编号。 |
| `states` | array | 上游涉及的州编号列表。编号只用于定位，不在中继中猜测州名。 |
| `areas` | array | 上游给出的影响区域集合，必须全部保留。 |
| `areas[].name` | string | 区域名称，供列表和地图提示使用。 |
| `areas[].circles` | array | 圆形区域。通常表示可能震中或初始影响范围。 |
| `circles[].latitude` | number | 圆形中心纬度。 |
| `circles[].longitude` | number | 圆形中心经度。 |
| `circles[].radiusKm` | number | 圆形半径，单位为公里。 |
| `areas[].polygons` | array | 警报区域边界。地图必须绘制全部多边形，不能只取第一个。 |
| `areas[].points` | array | 上游提供的点位置。没有提供时不输出。 |

圆形区域和多边形区域含义不同：圆形更多用于表示震中附近的初始范围，
多边形用于表示已经给出的警报覆盖区域。它们都不是中继自行计算出的范围。

## 6. 正式警报判断方式

如果读取归档中的 CAP JSON，客户端或分析工具可以使用 `sasmexAlertIssued` 判断是否进入正式警报流程：

| `sasmexAlertIssued` | 客户端处理 |
| --- | --- |
| `true` | 按正式 SASMEX 警报显示，可进入声音、红色警报和警报区域流程。 |
| `false` | 按普通检测或监测消息显示，不当作已经发出的公众警报。 |
| 字段不存在 | 不自行判断，按普通网页实时事件处理。 |

本节只说明 CAP 归档，不覆盖前述实时 IO 的 severity → isWarn 规则。
分析 CAP 归档时，不要使用以下内容代替 `sasmexAlertIssued`：

- `severity` 的文字；
- `grado` 或 `severidad` 的数值；
- `intensidad` 的文字；
- 地点是否在某个州；
- `areas` 是否存在；
- 标题中是否出现 `ALERTA`。

这些字段各自描述不同内容，不能互相替代。

## 7. 不输出或不推断的内容

当前接口不补充以下信息：

- 震级；
- 震源深度；
- 震中烈度或最大烈度；
- 测站实测数据；
- PGA、PGV；
- 城市到达倒计时；
- 官方警报等级的本地估算；
- 上游没有返回的地点、州名或警报区域。

所有时间、文字、坐标和区域数据都以实际收到的上游内容为准。

## 8. 去重、快照和归档

APP 的报数是同一 `eventId` 的本地有效修订序号，当前上游没有提供报号。
首次接收为第 1 报；震中坐标、源时间（`sent` / `epochMs`）、地点、圆形区域、
类型、严重性、描述等原文内容变化时递增，检出升级为警报同样递增。
仅 `updated` 变化、字段顺序变化、心跳、重复消息和相同缓存不递增。
旧 `updated` 报文被拦截；没有更晚源时间的已见旧正文也不能顶掉后报。
重连缓存若给出更晚 `updated` 且正文变化，作为断线期间漏接的有效更新计数一次，
随后相同的实时包沿用该报数。报数和已见正文摘要在本地保存，重启后继续使用。
统一 UI、地图、历史和 EEW 更新语音使用同一序号，语音仍遵守用户更新播报开关。
`Data` 与 `sourcePayload` 的原始字段不写入报数，也不修改源时间。

- 服务启动第一次读取只建立基线，不把已经存在的旧事件重新推送。
- 同一事件内容没有变化时不重复推送。
- 新事件或正式报文更新时发送 `type: "update"`。
- `snapshot` 只返回当前缓存，不代表产生了一条新警报。
- 正式进入发送流程的请求和结果会归档到 TG 云盘的 `SASMEX原始归档/YYYY-MM-DD/`。
- 网页实时事件归档保留原始 Socket.IO 帧、解析 JSON 和实际发出的 JSON。
- CAP 归档保留实际请求 JSON、正式警报列表、CAP 原文、解析 JSON 和实际发出的 JSON，便于追溯。
- 两种归档都使用同一个自动上传器，上传回读校验成功后才删除服务器临时包。

## 9. 实现说明

服务端可以使用网页所使用的实时链路来获得最新事件，但只复用网页的字段提取和显示值转换逻辑。
对外输出仍遵循本项目既有的 SASMEX JSON 结构，不把网页内部字段名直接暴露给客户端，
也不把网页显示等级扩展成中继自己的警报判断。

## 10. 双连接备份和对照（2026-10-08）

测站 WS、地图测站圆点和测站订阅已按用户要求撤下。
APP 仍只连接 `/sasmex-eew`，保持现有真实 Sidesis 事件通道。

独立对照服务同时连接网页 Socket.IO 根命名空间与历史 Firestore `sasno-d79e1`
`app/events`。Firestore 每秒轮询，原始响应先保存，再仅解码 REST Value；
不执行旧显示等级映射，不参与 APP 广播，也不把启动时已有文档当作新预警。
旧轮询代码和实际 Firestore 文档均备份到服务器并归档到 TG。

TG 目录为 `SASMEX原始归档/双连接对照/YYYY-MM-DD/`。每个记录均标明
`transport`、`recordKind`、`recordedAtUtc` 和 `publishedToApp: false`。
Socket.IO 保留每个实际接收帧；Firestore 保留首个原文和后续变化原文、失败响应，
相同响应只累计成功轮询数。每 60 秒记录双方连接状态、最后成功时刻、实际收包数、
业务消息数、符合当前 APP 解析条件的帧数、FireStore 文档时间和变化数。
上传后回读核验 SHA-256 与字节数，失败时保留本地原始包。

这些指标用于分别判断传输可达和事件数据是否更新。文档返回 HTTP 200 或 Socket.IO
握手成功不表示已有新事件；没有收到真实业务数据时不得推断哪一路更有效。
