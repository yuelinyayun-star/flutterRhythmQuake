# SASNO 2026-10-17 原始文档

`sasmex_firestore_20261017.original.json` 是公开 Firestore `sasno-d79e1/app/events`
实读响应的原始字节，SHA-256：
`668842f7958b668b23dddf263d6831abff3996a6d40cb50303a5346497b3dbc5`。

事件 `unix: 1792229803`、`region: Zihuatanejo, Gro.`、`intensity: Leve`。
`sasmex_firestore_20261017.relay.json` 由当前服务器转换器对该原文转换得到，
保留 `original`；补齐已有英文 `msgType: Alert`，事件时间未修改。

APP 历史与 OBS 回归测试使用这条原报文和独立测试时钟，不向实时源或用户历史注入。
测试中另行声明的 SSN 条件输入仅用于机构、时区、空间和停止延迟的单元验证，不是实收 SSN 报文。
