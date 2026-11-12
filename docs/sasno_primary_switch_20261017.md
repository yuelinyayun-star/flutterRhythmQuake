# SASNO Firestore 主源切换验收

2026-10-17 10:59 UTC 完成服务器切换。APP 地址继续使用
`wss://ws.yuelinrhythm.top/sasmex-eew`，不需要重新编译客户端。

## 当前链路

SASNO Firestore `projects/sasno-d79e1/databases/(default)/documents/app/events`
→ 服务端每 5 秒通过 REST 读取原始响应
→ 现有 Firestore Value 解包及 SASNO 转换
→ 现有 `type: update / source: sasmex / Data` JSON
→ APP 已有解析、报数、统一 UI 和地图。

这是文档 REST 轮询，不是 Firestore `onSnapshot` 长连接。Socket.IO 继续由对照观察器记录，
不参与 APP 主源推送。CAP 保持独立归档，不进入 APP 查询和启动快照。

首次文档仅建立基线；后续内容变化且未过期才推送。文档更新时间变化但事件字段未变不重推。
事件时间取原始 `unix`；过期时间沿用 APP 检出 3 分钟、警报 6 分钟的源时间期限。
HTTP 429 和其他连接故障使用退避，并遵守 Retry-After。

## 部署与备份

本地准备、测试后部署以下文件，保留服务器原文件权限和所有者：

- `/opt/rhythmquake/kma-pews-relay/kma_pews_relay.py`
- `/opt/rhythmquake/kma-pews-relay/sasno_realtime.py`
- `/opt/rhythmquake/kma-pews-relay/sasmex_archive.py`：服务器旧白名单缺少 Firestore 原文附件，补齐兼容。
- `/opt/rhythmquake/sasmex-dual-monitor/sasmex_dual_monitor.py`：更新主源状态说明。
- `/etc/systemd/system/kma-pews-relay.service.d/sasno-primary.conf`

服务器备份：`/opt/rhythmquake/backups/sasno-primary-20261017T105808Z`，含原文件和部署哈希清单。
部署前重新核验旧文件 SHA-256，暂存验证通过后才替换。中继和对照观察器均为 active。

## 验证结果与边界

- 本地 SASNO、Sidesis、SASMEX 相关 Python 测试 39 项通过。
- 服务器在自身 Python 环境运行 SASNO 与归档相关测试通过。
- APP 既有 SASMEX 服务、报数及地图测试 38 项通过。
- 额外使用 10 月 16 日原始 Firestore 报文，APP 解析和统一 UI 展示字段测试通过：
  `1792150811000`、坐标 `15.1385,-92.46365`、检出、第 1 报、轻微，原时间未改。
  原始响应 SHA-256 为 `72b44c5f5cc7e2a667905a0ea0b6a34472b00b2a1b572aedad72a75f3c68adef`。
- 服务器和外网 `/sasmex/health` 均验证 `primaryTransport: firestore`、`healthy: true`、
  `baselineInitialized: true`、上游 HTTP 200。
- 外网 WSS 实测连接、query_response、ping/pong 正常。
- 验收时 `latestObservedEventId: 1792229803000`、`acceptedUpdates: 0`；查询 `Data: null`，
  符合首次旧文档只建基线的规则。没有向线上注入或修改时间重放测试报文。
  自然新报文的实时送达尚需等上游下一次更新。

本轮完整 Python 测试中还存在一项原有 KMA MMI 断言失败，已用修改前备份复现，
与本次 Firestore 主源切换无关，未改动该规则。

部署及外网验收原始记录：`tmp/sasno_primary_20261017/deployment-report.json`、
`tmp/sasno_primary_20261017/public-verification.json`。
