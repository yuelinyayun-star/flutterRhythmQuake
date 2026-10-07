# SASMEX 地震预警 JSON 接口

本文档说明服务端从 SASMEX-CIRES CAP 报文中解析出的客户端 JSON。服务端内部读取
CAP XML，但对 APP 只发送 JSON，不发送 XML 原文，也不补充 SASMEX 没有提供的震级、深度、烈度或测站数据。

服务端另外会把通过去重并实际发出的新事件归档到 TG 云盘的
`SASMEX原始归档/YYYY-MM-DD/`。归档包保留本次实际 GET 的 `latest` JSON、正式警报列表
JSON、对应 CAP XML、解析后的 JSON，以及完整的 WebSocket 输出 JSON；`report.json` 保存
请求 URL、状态码、响应头、接收时间、耗时和各文件 SHA-256。上传回读校验成功后才删除
服务器临时包，失败会保留并由 timer 重试。

## 1. 连接地址

APP 只需要连接一个 WebSocket：

```text
wss://ws.yuelinrhythm.top/sasmex-eew
```

运维接口不是额外的数据源：

| 地址 | 作用 |
| --- | --- |
| `https://ws.yuelinrhythm.top/sasmex/health` | 查看中继服务状态 |
| `https://ws.yuelinrhythm.top/sasmex/snapshot` | 查看当前缓存的最后一条消息 |

## 2. 是否发警报

服务端只保留两个 SASMEX 专用字段，不判断官方警报属于 `Alerta Preventiva` 还是
`Alerta Pública`：

| 字段 | 含义 |
| --- | --- |
| `sasmexAlertIssued` | 根据 CAP 动作字段判断当前报文是否确认发出警报。 |
| `sasmexAlertAction` | 原始 `responseType`，例如 `Monitor` 或 `Execute`。 |

判断规则只看 CAP 的动作语义：

| `responseType` | `sasmexAlertIssued` | 含义 |
| --- | --- | --- |
| `Monitor`、`None` | `false` | 继续监测，没有确认发出警报 |
| `Prepare`、`Assess` | `false` | CAP 没有确认执行警报动作 |
| `Execute`、`Shelter`、`Evacuate` | `true` | 已确认执行警报动作 |

`msgType` 只表示报文生命周期，不表示警报等级：

| `msgType` | 含义 |
| --- | --- |
| `Alert` | 首次发布一条报文 |
| `Update` | 更新报文，替代 `references` 指向的旧报文 |
| `Cancel` | 取消 `references` 指向的旧报文 |

当前公开样本中，`Monitor` 报文是“检测到地震但没有发出警报”；`Execute` 报文是“已执行警报动作”。
当前 CAP 样本没有明确返回 `Alerta Preventiva` 或 `Alerta Pública` 这两个官方名称，因此服务端不判断具体官方等级。

服务端轮询两个索引：`/api/v1/alerts/latest/` 用于获取最新检测或事件，
`/api/v1/alerts/?type=alert` 用于补充发现正式警报。启动时正式警报列表只建立基线，
不会把历史记录重新发送；新出现或摘要更新的警报才会读取 CAP 并推送。两个索引指向同一条报文时，
服务端会用事件 ID、CAP 内容指纹和近期指纹缓存去重。

## 3. Monitor 示例：检测到地震但未发警报

这是 SASMEX 真实报文 `20260902031439` 的客户端格式：

```json
{
  "type": "update",
  "source": "sasmex",
  "Data": {
    "source": "sasmex",
    "id": "20260902031439",
    "eventId": "20260902031439",
    "sasmexAlertIssued": false,
    "sasmexAlertAction": "Monitor",
    "msgType": "Alert",
    "time": "2026-09-02T03:14:39",
    "sent": "2026-09-02T03:14:39-06:00",
    "effective": "2026-09-02T03:14:39-06:00",
    "expires": "2026-09-02T03:15:39-06:00",
    "event": "SASMEX: Sismo Moderado en Petatlan Gro",
    "headline": "Sismo Moderado en Petatlan Gro",
    "description": "Sismo Moderado en Petatlan Gro, a 25km de Guerrero",
    "category": "Geo",
    "urgency": "Immediate",
    "severity": "Unknown",
    "certainty": "Observed",
    "region": 41202,
    "states": [41],
    "areas": [
      {
        "name": "Zona Probable Epicentro",
        "circles": [
          {
            "raw": "17.22,-100.79 70.0",
            "latitude": 17.22,
            "longitude": -100.79,
            "radiusKm": 70.0
          }
        ]
      }
    ]
  }
}
```

这条消息的判断结果是：检测到地震，`Monitor`，没有发出警报。圆形区域是可能的震中区域，不是公众警报覆盖区。

## 4. Execute 示例：已执行警报动作

这是 SASMEX 真实报文 `20260504091933` 的客户端格式：

```json
{
  "type": "update",
  "source": "sasmex",
  "Data": {
    "source": "sasmex",
    "id": "20260504091933",
    "eventId": "20260504091933",
    "sasmexAlertIssued": true,
    "sasmexAlertAction": "Execute",
    "msgType": "Update",
    "time": "2026-05-04T09:19:33",
    "sent": "2026-05-04T09:19:33-06:00",
    "effective": "2026-05-04T09:19:33-06:00",
    "expires": "2026-05-04T09:20:33-06:00",
    "event": "SASMEX: ALERTA SISMICA en CDMX por sismo en Costa Oax-Gro",
    "headline": "ALERTA SISMICA por sismo Severo en Costa Oax-Gro",
    "description": "Sismo Severo en Costa Oax-Gro, a 347km de CDMX",
    "category": "Geo",
    "urgency": "Immediate",
    "severity": "Severe",
    "certainty": "Observed",
    "region": 42201,
    "states": [40],
    "references": [
      {
        "id": "20260504091932",
        "isEvent": true,
        "region": 42201,
        "states": [42]
      }
    ],
    "areas": [
      {
        "name": "Region de Alertamiento",
        "polygons": [
          "15.48,-94.06 18.35,-93.87 18.55,-98.59 15.62,-98.70 15.48,-94.06",
          "19.15,-98.95 19.60,-98.95 19.60,-99.35 19.15,-99.35 19.15,-98.95"
        ]
      }
    ]
  }
}
```

这条消息的判断结果是：`Execute`，已执行警报动作；`areas` 中的两个多边形就是完整警报区域，不能只取第一个。

## 5. 客户端字段说明

### 外层

| 字段 | 含义 |
| --- | --- |
| `type` | 中继消息类型，`update` 表示数据更新。 |
| `source` | 数据源标识，固定为 `sasmex`。 |
| `Data` | SASMEX 这条报文的内容。 |

### 报文和警报判断

| 字段 | 含义 |
| --- | --- |
| `id` | 当前 SASMEX 报文编号，用于去重。 |
| `eventId` | 当前报文对应的事件编号。 |
| `sasmexAlertIssued` | 是否已经确认执行警报动作。 |
| `sasmexAlertAction` | 原始 CAP `responseType`，例如 `Monitor` 或 `Execute`。 |
| `msgType` | CAP 报文生命周期，不是警报等级。 |
| `references` | 当前报文关联的旧事件或旧报文。只有上游提供时才输出。 |

### 时间

| 字段 | 含义 |
| --- | --- |
| `time` | SASMEX 列表接口给出的事件时间。 |
| `sent` | CAP 报文发送时间。 |
| `effective` | CAP 信息开始生效时间。 |
| `expires` | CAP 信息失效时间。 |

时间原样保留。没有时区的 `time` 不由服务端擅自改成北京时间。

### CAP 信息

| 字段 | 含义 |
| --- | --- |
| `event` | SASMEX 事件名称。 |
| `headline` | 给用户看的短标题。 |
| `description` | SASMEX 原始描述。 |
| `category` | CAP 信息类别，`Geo` 表示地球物理事件。 |
| `urgency` | 需要多快响应，例如 `Immediate`。 |
| `severity` | CAP 通用影响严重程度，例如 `Severe` 或 `Unknown`；不是震级、烈度或官方警报等级。 |
| `certainty` | CAP 对信息的确定程度，例如 `Observed`。 |

### SASMEX 地区和警报区域

| 字段 | 含义 |
| --- | --- |
| `region` | SASMEX 区域编号。服务端不把数字硬翻成不存在的地点名称。 |
| `states` | SASMEX 返回的州编号列表。 |
| `areas` | CAP 的全部 `<area>` 区域列表。 |
| `areas[].name` | `<areaDesc>`，区域的人类可读名称。 |
| `areas[].circles` | 该区域中的所有圆形范围。 |
| `circles[].raw` | 原始圆形字符串。 |
| `circles[].latitude` | 圆形中心纬度。 |
| `circles[].longitude` | 圆形中心经度。 |
| `circles[].radiusKm` | 圆形半径，单位为公里。 |
| `areas[].points` | 该区域中的点位置，只有上游提供时才输出。 |
| `areas[].polygons` | 该区域中的全部多边形原始坐标字符串。 |

`areas` 不是额外的假字段，而是 CAP 原文中的 `<area>` 列表。`Monitor` 通常有圆形的可能震中区域；
正式警报通常有多边形警报区域。两者都必须保留。

## 6. 明确不输出的内容

SASMEX 当前公开报文没有提供以下内容，因此客户端 JSON 不输出这些字段：

- 震级；
- 震源深度；
- 震中烈度或最大烈度；
- 测站列表；
- PGA、PGV；
- 城市到达倒计时；
- 服务端估算出的官方警报等级。

`severity: Severe` 只表示 CAP 的通用严重性，不能直接改写成 `Alerta Preventiva` 或 `Alerta Pública`。

## 7. 心跳和查询

服务端心跳：

```json
{
  "type": "heartbeat",
  "source": "sasmex",
  "timestamp": "2026-10-06T16:41:25.277553+00:00"
}
```

客户端可以发送：

```json
{"type":"ping"}
```

服务端返回：

```json
{
  "type": "pong",
  "source": "sasmex",
  "timestamp": "2026-10-06T16:41:26.277553+00:00"
}
```

客户端可以发送：

```json
{"type":"query"}
```

服务端返回当前缓存数据：

```json
{
  "type": "query_response",
  "source": "sasmex",
  "Data": null
}
```

没有缓存时 `Data` 为 `null`。

## 8. 当前实现依据

服务端只在内部解析 SASMEX 的 `latest` JSON、列表 JSON 和对应 CAP XML。对外输出使用上面的紧凑 JSON。
同一条报文内容不会重复推送；心跳、健康检查和快照不属于地震事件数据。
