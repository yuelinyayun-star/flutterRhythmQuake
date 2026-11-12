# 2026-10-16 KMA / SeisJS 原始 WS 抓包

由 `tools/capture_ws_followup.dart` 以只读方式连接应用现有公共端点，完成握手后观察 8 秒，分别保留前 8 帧。每个 `.original.bytes` 文件与接收到的解帧后原文逐字节一致；没有改写字段、站号、时间、坐标或数值。来源、长度和 SHA-256 见 `manifest.json`。

- KMA：`wss://ws.yuelinrhythm.top/kma-station`，收到 heartbeat、265 站目录、initial 和后续 update。
- SeisJS：`wss://seisjs.wolfx.jp/all_seis`，收到 heartbeat 和设备观测。
- P2P：`wss://api.p2pquake.net/v2/ws`，握手成功，观察期无事件帧，未生成任何虚构事件文件。

P2P 语义回归另使用既有 `jma_voice/p2p_scale_prompt.json` 原始样本。它是原始历史响应数组，在本地传输测试中原文整体发送，仅核验数组入口兼容；不声称它是本轮收到的实时 WS 帧。

测试中另外构造的连接失败、迟到回调、超限错误等均为明确标注的控制协议情形，不是上游地震数据。测试只运行隔离服务实例，不向运行中的 APP 注入事件，不触发云端归档。
