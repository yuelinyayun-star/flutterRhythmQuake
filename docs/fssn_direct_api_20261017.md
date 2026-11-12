# FSSN 独立接口接入

文档：https://fssn-api.fanstudio.tech/ ，核验日期 2026-10-17，接口版本 1.0.0。

## 接口与 FAN 的差异

- 独立地址为 `wss://fssn-api.fanstudio.tech/all`；包含 `fssn` 情报和 `fssn-cmt` 震源机制解。单源路径为 `/fssn`、`/fssn-cmt`。
- 文档未要求 FAN 的 App ID 或 API Key；本次独立连接未发送 FAN 认证包，并成功接收数据。
- 心跳每 20 秒一次，收到 `heartbeat` 回复 `ping`。连接建立时分别请求 `fssnlist`、`cmtlist`，之后接收推送，不周期轮询列表。
- `initial_all`、`query_response` 中源名与 `type` 同级；实时 `update` 使用 `source + Data`。两个列表分别返回 `fssnlist_response`、`cmtlist_response`。
- 情报含 `createTime` 和 `placeName_zh`；时间仍为 UTC+8。地点继续复用 FAN 现有 FE 中文转换。
- CMT 的 `id` 是解的 ID，`eventId` 是关联地震 ID且可以为空。继续沿用 FAN 的事件身份规则：优先关联地震 ID，否则使用解 ID；原始两个字段均保留在 `sourcePayload`。CMT 使用独立 `fssnCmt` 桶，不合并成普通情报一行。

## 本地连接与展示

`FssnService` 注册进 SourceManager，独立设置键为 `api_source_fssn_enabled`，默认开启。设置页新增“FSSN 地震情报/震源机制解”，独立于 FAN 开关。独立接口开启时，FAN 只暂停自身 FSSN 情报、CMT 投递和 FSSN 列表请求，其他 FAN 来源沿用现有流程；关闭独立接口会恢复这些 FAN 投递。

Windows 复用 `connectSourceSocket` 原生 WS 和 `decodeApiJsonBytes` 原生 JSON 入口，事件转换复用 `FanService` 的现有 FSSN 解析，不改写原始 Data。API 标记设为 `FSSN`；地点、预估烈度、CMT 震级优先级、矩心深度和 NED 矩张量处理沿用现有实现。FSSN CMT 的语音来源补成 `FSSN`，避免播出内部键 `fssnCmt`。

首包和列表仅填充历史，不进入实时提醒。实时变化进入现有统一事件处理、过滤、地图、轮播与语音链。列表点击使用现有历史选择链进入统一 UI。前台与后台连接均已桥接，后台新增 `fssnCmt` 列表分发。

连接失败自动退避重连，心跳长时间无消息会重连；重连会重取两份列表。重复 Data 不重复投递，晚到列表不能覆盖本连接已经收到的实时版本，较旧 `createTime` 不覆盖已接收版本。手动关闭会取消重连、心跳检查和流订阅。每类最多保留 50 条用于列表与去重。

## 验证

- 独立原生 WS 实连：5 条情报、10 条 CMT；FAN 关闭，首包触发提醒数为 0。
- 原始报文回送本地 WS，检查首包静默、两个源的实时投递、重复包、晚到列表、断线恢复与手动停止。回送只改变传输外层类型，不修改事件 Data；不冒充实网新地震或修改事件时间。
- 两类原文渲染现有统一 UI，验证 API 标记、地点、CMT 徽章、语音来源与无布局异常；测试不改生产 UI。
- 本轮 24 项测试通过；Windows Debug 构建通过。
- 新增连接与展示测试文件：`test/fssn_service_test.dart`、`test/fssn_direct_ui_test.dart`。真实网络测试通过 `RQ_FSSN_LIVE=1` 显式启用，其余测试使用固定的实网原文。

原始抓包见 `test/fixtures/fssn_direct_20261017/`；其数据未修改。实网验证仅覆盖连接时的快照与列表，实时更新、断线重连使用原文协议回送验证；未等待新的实网地震发生。后台桥接已通过代码检查及 Windows 编译，本轮未进行 Android 构建或设备后台实测。
