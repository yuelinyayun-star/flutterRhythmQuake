# FSSN 实网原文

2026-10-17 从 `wss://fssn-api.fanstudio.tech/all` 抓取，保存收到的 UTF-8 字节，不格式化、不补时间、不修改字段。

| 文件 | SHA-256 |
| --- | --- |
| heartbeat.original.json | 8fd617b6bdf209e314c77ac0af19fae46d72578a92ed70fd28755f97fb4c418d |
| initial_all.original.json | fa80c7eb2c774fec6df28b9fab33a2f0459d7d8172481be2fc90d3bb9c341dfb |
| fssnlist_response.original.json | 6cf393f2856757c743186f93ffa480f7d30771ba6d271c2b6ba0b42e192e38c6 |
| cmtlist_response.original.json | 70b13b6a46226225a4e508f4404010cc7db92e86973697b96c7e87efaae5fca6 |

本次列表返回 5 条情报和 10 条 CMT。协议测试会把捕获的列表行 Data 装入 `update` 外层，以验证实时分发；行内的震级、坐标、时间和身份字段均保持原样。这不是新地震的实网推送证据。
