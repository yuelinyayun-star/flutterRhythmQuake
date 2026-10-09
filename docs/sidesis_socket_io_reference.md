# Sidesis Socket.IO 实时源

## 已确认的连接方式

本次对齐的是 `https://asmx1-8.bolt.host/` 当前脚本中的 `Bh` 真实 Socket.IO
接收器，而非 `simulated_alert`、模拟按钮或历史回放。实际服务地址是：

```text
wss://sidesis.iigea.org/socket.io/
```

网页客户端配置为：

- 只使用 `websocket`
- 自动重连
- 初始重连间隔 1 秒、上限 30 秒
- 重连次数上限 10
- 连接超时 20 秒

Engine.IO 4 的 WebSocket 连接顺序为：

```text
服务端 -> 0{...}
客户端 -> 40
服务端 -> 40{...}
```

传输层心跳为：

```text
服务端 -> 2
客户端 -> 3
```

生产中继实现位于 `server/kma_pews_relay/sidesis_realtime.py`，连接根命名空间，
不会发送未知的业务订阅指令。APP 使用自己的 `/sasmex-eew` 中继，而非直接连接上游。
`lib/services/sources/sidesis_socket_io_client.dart` 是此前保留的诊断客户端，不是
当前 APP 的活动 SASMEX 源；其旧分类不能替代本次已核实的生产解析规则。

## 网页实际监听的事件

当前参考网页 `Bh.connect()` 实际监听一个业务事件：

```text
new_message
```

收到真实包后，网页才在浏览器内部派发 `sidesis_message`。
后者和 `simulated_alert` 都是 DOM 事件名，不是上游 Socket.IO 业务事件名。
中继只接受 `new_message`；带 `isSimulation` / `isReplay` 标志的包被排除。

## 测站心跳

网页判断条件：

- `type` 等于 `heartbeat`
- 先分流心跳，即使报文同时带 severity，也不进入地震事件。

页面读取的字段包括：

```json
{
  "type": "heartbeat",
  "station_name": "...",
  "station_id": "...",
  "lat": 0,
  "lon": 0,
  "timestamp": "..."
}
```

网页将它显示为测站在线心跳，不当作地震事件。

## 警报消息

排除心跳之后，网页读取真实消息的这些字段；缺失严重性时网页内部使用 Unknown。
中继保留缺失状态，不伪造原始 severity：

```json
{
  "title": "...",
  "updated": "...",
  "sent": "...",
  "identifier": "...",
  "id": "...",
  "msgType": "...",
  "severity": "...",
  "info": [
    {
      "event": "...",
      "description": "..."
    }
  ],
  "description": "..."
}
```

字段优先级与网页一致：

- 标识：`identifier`，没有时使用 `id`
- 事件时间：`sent`；中继没有有效 sent 时才兼容 updated，两个原文都保留
- 描述：`info[0].description`，没有时使用顶层 `description`，再使用 `title`
- 事件名称：`info[0].event`
- 严重性：`info[0].severity` 优先，网页也兼容顶层 `severity`

## 实时震中与本项目 JSON

网页 `extractCoordinatesFromCircle()` 从顶层 `circle` 的第一个“纬度,经度”对
读取事件中心。剩余半径文本不用于决定震中。中继保留完整 circle，并转换成
我们的 lat / lng；缺失或无效时省略坐标，不使用网页补出的默认州坐标或墨西哥城。

州名匹配同网页：优先检查 info[0].description，再检查 description，最后 title，
按网页固定列表查找。没有匹配时，只保留上游明确的 region / place / location。

输出使用 `type: update`、`source: sasmex`、`Data: 事件对象`。
Data 包含 id、eventId、isWarn，以及实际存在的 epochMs、severity、circle、lat、lng、
region、title、description、event、sent、updated、msgType。
intensidad / grado / severidad 只在上游明确提供时转发，不自行估算。

原始 Socket.IO 帧逐字节归档，解析不会改写输入。snapshot 和 query_response 都使用
真实 IO 缓存，不能用 CAP 归档补成实时事件。详见 `sasmex_relay_protocol.md`。

## 三档严重性

网页报文中的 `severity` 有三档，客户端保留原文，同时提供统一语义：

| 上游值 | 客户端档位 | 是否官方警报 |
|---|---|---|
| `Minor` | 轻度 | 否，属于检测消息 |
| `Moderate` | 中度 | 否，属于检测消息 |
| `Severe` | 强 | 是，属于地震警报 |

`info[0].severity` 存在时按网页显示逻辑优先使用它；否则使用顶层
`severity`。其他值（包括 `Unknown`、缺失值）保留原值并标记为未知，不会被
强行当成警报或检测。

代码中对应的字段是：

- `rawSeverity`：顶层原始 `severity`；
- `severity`：网页展示优先级后的严重性文本；
- `asMxLevel`：轻度、中度、强或未知；
- `isOfficialAlert`：仅 `Severe` 为 `true`；
- `isNoAlertDetection`：仅 `Minor`、`Moderate` 为 `true`。

网页地图后续会自行计算波圈和预计烈度，并有默认震级、深度、位置；这些不是
Socket.IO 原始数据，不进入中继的原始事件字段。详情见 `sasmex_realtime_map_reference.md`。

## 当前限制

2026-10-08 的 45 秒原始 IO 观察确认握手和传输心跳，期间没有收到业务事件。
因此本地已完成基于真实网页接收器的解析和 JSON 转换，但尚无本次真实新地震业务包
的端到端验证；不会使用模拟事件、修改历史事件时间或混入 CAP 来代替这一验证。
