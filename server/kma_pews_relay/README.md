# KMA PEWS Relay

这是给 Windows 服务器使用的韩国气象厅 PEWS 实时测站转发服务。

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
