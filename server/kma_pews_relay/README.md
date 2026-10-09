# KMA PEWS Relay

## SASMEX 双连接对照

2026-10-08 按用户要求撤下测站服务、地图测站圆点及测站订阅。
州提示、已有震中和 P/S 波继续使用本项目地图组件。

APP 继续连接 `wss://ws.yuelinrhythm.top/sasmex-eew`，实时事件仅来自既有 Sidesis
Socket.IO。独立 `sasmex-dual-monitor.service` 同时只读观察同一 Socket.IO 根命名空间与
`https://firestore.googleapis.com/v1/projects/sasno-d79e1/databases/(default)/documents/app/events`。
Firestore 每秒轮询，只建立原始基线并记录变化，不调用旧预警映射，不向 APP 推送。

新服务代码放在 `/opt/rhythmquake/sasmex-dual-monitor`，旧 Firestore 轮询实现与实读
原文在其中的 `backup/` 留存并随首次启动归档。原 KMA/EEW 服务无须修改或重启。
服务器状态文件 `/var/lib/rhythmquake-sasmex-compare/connection-status.json` 每 60 秒更新。
记录实际连接、断线、传输帧、业务帧、符合现有 APP 解析条件的帧以及 Firestore 成功数、
原文 SHA-256、文档时间和内容变化数。连接健康与新事件出现分别统计。

`sasmex-compare-upload.timer` 每分钟将批次上传至 TG 云盘
`SASMEX原始归档/双连接对照/YYYY-MM-DD/`，上传后回读校验 SHA-256 与大小，
通过后才删除临时包。归档失败计数与最后错误保留在状态文件，积压最多 64 MiB，
不会覆盖已有原文。相同 Firestore 响应仅累计轮询计数；首个响应、文档变化、异常响应、
恢复和连接状态均单独留档。原事件时间保留在原文，归档文件日期使用实际采集时间。

部署本地准备文件后安装三个 systemd unit 并启动：
`systemctl enable --now sasmex-dual-monitor.service sasmex-compare-upload.timer`。
两个读取客户端没有 APP 广播接口；Firestore 原有旧文档不会重报。

这是给 Windows / Linux 服务器使用的韩国气象厅 PEWS 实时测站转发服务。

服务直接请求：

```text
https://www.weather.go.kr/pews/data/yyyyMMddHHmmss.b
https://www.weather.go.kr/pews/data/yyyyMMddHHmmss.s
```

时间只使用韩国气象厅 HTTP 响应头 `ST`。不请求 FAN，不使用 FAN 的时间，也不依赖 Windows 本机 NTP 是否准确。

## Windows 安装

需要 Python 3.11 或更高版本。

在 PowerShell 中进入本目录：

```powershell
.\install.ps1
```

安装脚本会：

1. 在当前目录建立 `.venv`。
2. 安装 `aiohttp` 和 `websockets`。
3. 使用 KMA `ST` 校时并实际读取一份官方 `.b/.s` 做解码检查。

## 运行

```powershell
.\run.ps1
```

默认监听：

```text
WebSocket: ws://0.0.0.0:8765/kma-station
健康检查:  http://127.0.0.1:8765/health
当前快照:  http://127.0.0.1:8765/snapshot
```

同一服务还会轮询公开的 SASMEX-CIRES RSS/CAP 页面，并提供独立的预警 WSS，
不会把 CAP XML 混入 KMA 二进制测站频道：

```text
WebSocket: ws://0.0.0.0:8765/sasmex-eew
健康检查:  http://127.0.0.1:8765/sasmex/health
当前快照:  http://127.0.0.1:8765/sasmex/snapshot
```

生产环境由同一个反向代理域名映射为 `wss://你的域名/sasmex-eew`。
该频道的主实时事件源是网页实际使用的
`wss://sidesis.iigea.org/socket.io/`。服务端连接 Socket.IO 根命名空间，按网页监听
当前参考网页 `https://asmx1-8.bolt.host/` 的真实 `new_message`，并广播现有 SASMEX
格式的 `source: "sasmex"` `update`。心跳优先分流，明确标记的模拟/回放包不进入实时频道。
网页心跳和重复事件不会当成新的地震事件通知。`rss.sasmex.net` 只保留给
CAP/正式警报原文归档；它的任何事件都不会进入这个客户端实时 WSS。

网页实时事件的 `Data` 保持项目之前的字段格式。真实字段映射为：

| 上游内容 | Data 输出 |
| --- | --- |
| identifier / id | id、eventId；缺失时只使用上游 sent / updated 作稳定键 |
| sent，缺失有效值时 updated | epochMs；发送/更新时间原文同时保留 |
| 顶层 circle | circle 原文以及中心 lat、lng；缺失时不造默认坐标 |
| info[0].severity，其次顶层 severity | severity 原文；Severe 对应 isWarn=true |
| info[0].description，其次 description、title | description 原文 |
| 描述/标题中按网页列表匹配的州名 | region；否则只保留明确的上游地点 |
| title、msgType、info[0].event | 同名元数据 |
| 上游确实给出的 intensidad / intensity、grado、severidad | intensidad、grado、severidad；不自行估算 |

`snapshot` 与 `query_response` 都只返回真实 IO 缓存；缓存为空时 Data=null，
不会返回 CAP 归档。完整格式见 `../../docs/sasmex_relay_protocol.md`。

只有上游实际提供 `severity` 时才会额外保留该原始字段；不根据 `grado` 或
`severidad` 自行制造警报状态。原始 `severity` 为 `Severe` 时 `isWarn` 才为 `true`。

连接建立时会发送 `heartbeat`；如果已有网页实时事件，则发送 `source: "sasmex"` 的
`snapshot`。CAP 的 `Execute` 等正式警报只保存到归档，不通过这个 WSS 推送。

线上使用时应由 IIS、Caddy 或 Nginx 终止 HTTPS/WSS，再反向代理到 `127.0.0.1:8765`。

## 与现有客户端兼容的消息

连接建立后依次发送：

```text
heartbeat
initial_stations
initial
```

实时更新发送：

```text
kma_stations_update
update
heartbeat
pong
```

WebSocket 报文与 FAN `/kma-station` 保持相同字段。`Data` 只包含 `timestamp` 和 `mmi`：

```json
{
  "type": "update",
  "source": "kma-station",
  "Data": {
    "timestamp": "2026-07-23 20:20:25",
    "mmi": [-2, -2, -1, 0, 1]
  },
  "md5": "..."
}
```

PEWS 原始 `rawMmi`、UTC 时间、阶段和事件编号只保存在服务器 `/snapshot` 的 `diagnostics` 中，不会混入 WebSocket 的 FAN 兼容报文。

## 环境变量

```powershell
$env:KMA_RELAY_HOST = '0.0.0.0'
$env:KMA_RELAY_PORT = '8765'
$env:KMA_MAX_CLIENTS = '500'
$env:KMA_LOG_LEVEL = 'INFO'
$env:KMA_RELAY_TOKEN = ''
.\run.ps1
```

设置 `KMA_RELAY_TOKEN` 后：

```text
wss://你的域名/kma-station?token=你的令牌
```

HTTP 接口可使用同一个查询参数，或：

```text
Authorization: Bearer 你的令牌
```

其余可调参数：

| 环境变量 | 默认值 | 说明 |
| --- | ---: | --- |
| `KMA_TARGET_LAG_SECONDS` | `1` | 按 KMA ST 时间请求前 1 秒文件 |
| `KMA_LAG_RETRY_SECONDS` | `2` | 当前文件未生成时最多再检查前 2 秒 |
| `KMA_REQUEST_TIMEOUT_SECONDS` | `3` | KMA 单次 HTTP 超时 |
| `KMA_STALE_AFTER_SECONDS` | `5` | 超过该时间未收到新帧则健康检查返回 503 |
| `KMA_HEARTBEAT_SECONDS` | `25` | 应用层 heartbeat 间隔 |

SASMEX 参数：

| 环境变量 | 默认值 | 说明 |
| --- | ---: | --- |
| `SASMEX_BASE_URL` | `https://rss.sasmex.net` | CAP/正式警报原文站点，不作为主实时事件源 |
| `SASMEX_POLL_SECONDS` | `10` | `latest` 和正式警报索引的轮询间隔 |
| `SASMEX_REQUEST_TIMEOUT_SECONDS` | `15` | 单次公开接口超时 |
| `SASMEX_STALE_AFTER_SECONDS` | `90` | CAP 归档源健康检查允许的轮询间隔 |

网页实时 Socket.IO 事件参数：

| 环境变量 | 默认值 | 说明 |
| --- | ---: | --- |
| `SIDESIS_SOCKET_URL` | `wss://sidesis.iigea.org/socket.io/` | 网页实际使用的 Socket.IO 地址 |
| `SIDESIS_RECONNECT_SECONDS` | `3` | 断线后的重连间隔 |
| `SIDESIS_SOCKET_TIMEOUT_SECONDS` | `20` | Socket.IO 建立连接超时 |
| `SIDESIS_STALE_AFTER_SECONDS` | `90` | 实时源健康检查阈值 |

服务端连接网页使用的 Engine.IO 4 根命名空间，响应传输层 `2` 心跳为 `3`，
并监听参考网页真实使用的 `new_message` 事件。服务启动后不会发送未知订阅指令，
只按网页已经确认的事件格式解析。检测事件和正式警报使用原始事件内容指纹去重。

`rss.sasmex.net` 仍单独用于 CAP/正式警报原文归档，不参与客户端实时 WSS。

## Windows 防火墙

如果反向代理与 relay 不在同一台机器，才需要开放 relay 端口：

```powershell
New-NetFirewallRule -DisplayName 'KMA PEWS Relay 8765' -Direction Inbound -Protocol TCP -LocalPort 8765 -Action Allow
```

反向代理与 relay 在同一台 Windows 服务器时，建议只监听 `127.0.0.1`：

```powershell
$env:KMA_RELAY_HOST = '127.0.0.1'
.\run.ps1
```

## 检查

离线协议单元测试：

```powershell
.\.venv\Scripts\python.exe -m unittest -v test_kma_pews_relay.py
.\.venv\Scripts\python.exe -m unittest -v test_sasmex_relay.py
```

官方实时数据检查：

```powershell
.\.venv\Scripts\python.exe .\kma_pews_relay.py --check-once
```

健康条件同时要求：

- 已从 KMA `ST` 完成校时。
- 已得到有效站点表。
- 最新帧年龄不超过 `KMA_STALE_AFTER_SECONDS`。

WebSocket 已建立但 KMA 数据卡住不会被判定为健康。

## SASMEX 原始归档

SASMEX 每个通过现有去重并进入发送流程的新事件，都会在后台写入一份独立 ZIP，
再由独立 timer 上传到 TG 云盘的 `SASMEX原始归档/YYYY-MM-DD/`。归档包含：

```text
report.json             请求 URL、GET 状态、响应头、接收时间、耗时、事件编号和文件 SHA-256
raw/latest.json         本轮实际 GET 到的 latest 原始 JSON
raw/alerts.json         本轮实际 GET 到的正式警报列表原始 JSON
raw/cap-<id>.xml        对应事件实际 GET 到的原始 CAP XML
raw/socketio-frame.txt  网页实时事件实际收到的原始 Socket.IO 帧
parsed.json             服务端解析后准备发送的事件 JSON
emitted.json            实际通过 SASMEX WebSocket 发出的完整 JSON
```

网页 Socket.IO 实时事件和 CAP 归档使用同一个 TG 上传器与同一个
`SASMEX原始归档/YYYY-MM-DD/` 目录。网页心跳、无法解析的帧和重复事件不会生成归档包。

原始响应按 UTF-8/字节原样保存，不用二次请求覆盖；上传通过 TGFS WebDAV 回读校验，
校验成功后才删除服务器本地临时 ZIP，失败则保留并重试。归档目录和 KMA 异常目录
分开，避免混淆。服务端健康接口中的 `sasmexArchive` 显示队列、成功和失败计数。

## 异常原文归档

Linux 服务端可启用独立异常归档，不改变客户端屏蔽条件，也不改变现有
WebSocket `Data`、`md5` 或原始码到 MMI 的转换。

记录条件：解析结果包含客户端会整帧屏蔽的 `-3`、帧或测站表解码失败、
上游帧返回非 200/404 HTTP 状态，以及 HTTP 200 的验证码、防火墙或其他 HTML
响应。HTML 内容在帧头、测站表及测站值解析前拒绝，原始响应仍归档；不会广播、
更新最新有效帧、MD5 或成功计数。有效数据停止超过现有新鲜度门限后，健康检查
返回 503。单纯 MMI 较高不判为异常。普通 404、
没有收到响应的网络超时和常规心跳不产生数据归档。

每份记录是 ZIP，包含：

```text
report.json             UTF-8 JSON：实际解析结果、异常原因、解析阶段、时间、HTTP 元数据
raw/frame.b             接收时的原始响应字节，未修改
raw/stations.s          解析使用的原始测站表（复用缓存时保留当时获取时间）
raw/station_attempt.s   刷新测站表失败时的新响应；仅在存在时保存
```

JSON 保存头部字段、原始站点码 `rawMmi`、转换后的完整 `Data`、当前测站坐标及
客户端屏蔽站点索引。解码中断时保留已经实际得到的部分结果；没有解析出的
字段为 `null`，不补造数据。所有原始附件及完整记录包都有 SHA-256。
记录原文必须在接收时进行，事后请求相同时间路径不能证明得到的是同一内容。
HTTP 元数据只保存 ST、日期、内容类型等诊断字段，不保存令牌或 Cookie。

开启方式：将 `anomalies.conf` 部署到
`/etc/systemd/system/kma-pews-relay.service.d/anomalies.conf`，重载并重启 KMA。
默认本地目录是 `/var/lib/rhythmquake-kma-anomalies/outbox`，待上传容量上限
64 MiB，工作队列上限 8 份，单份完整原文与 JSON 上限 4 MiB。
写盘和低级 ZIP 压缩在后台线程中完成，不在实时轮询协程里执行。
容量满或记录失败会明确写入日志，并在 `/health` 的 `anomalyArchive`
字段显示失败计数，不会悄悄截断原文，也不会为记录失败而阻断转发。

安装 `kma-anomaly-upload.service` / `.timer`，每轮结束后约一分钟上传一批。
上传账户与 KMA 相同，为 `rhythmquake`。将现有仅含 `tgfs` / `tgfs-webdav`
的 rclone 配置部署到 `/etc/rhythmquake-kma-anomalies/telegram.conf`，文件权限
`root:rhythmquake 0640`、父目录权限 `root:rhythmquake 0750`；凭据不能提交到仓库。
上传通过已验证的本机 TGFS WebDAV，而不是异步 FUSE 写缓存。

TG 云盘目录独立于安装包和回放：

```text
Telegram 云盘/KMA异常记录/YYYY-MM-DD/批次.zip
```

日期和批次文件名使用 UTC，JSON 同时保存 UTC 和韩国时间。
每批最多 120 份或 8 MiB 内层记录，外层 ZIP 不重复压缩；内层记录包原封不动。
上传后读回校验整批 SHA-256，成功才删除本地原文包与上传暂存。
失败保留同一批次，重试不重复生成不同名字；只保留一份最近上传记录，
避免上传收据无限增长。上传进程限制内存 128 MiB、CPU 单核 10%，任务结束退出。
没有为异常目录创建匿名公开分享。

实时验证工具（不会启动另一个 WebSocket 服务）：

```bash
.venv/bin/python validate_live_archive.py --directory /var/lib/rhythmquake-kma-validation
.venv/bin/python upload_anomalies.py --directory /var/lib/rhythmquake-kma-validation --validation
```

验证使用真实实时帧、原始测站表和生产解析器，显式标记
`manual_live_validation` / `validationOnly`，上传到 `KMA异常记录/验证/`，
不伪造异常、不修改测站值，不混入正式异常日期目录。
