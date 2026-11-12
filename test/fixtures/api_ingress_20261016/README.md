# 2026-10-16 原始数据入口样本

- `trem_stream.original.bytes`：使用现有客户端的 URL、User-Agent、Accept 与 Cache-Control，对 `https://api.lb-tpe1.exptech.dev/api/v2/trem/rts` 进行只读接收。原始响应 MIME 为 `text/event-stream; charset=utf-8`。保存约 6 秒收到的 30 个原始 HTTP 块，共 30,685 字节，字节顺序未改动。manifest 保留实际块长度、URL 和 SHA-256；采样停止不等同于上游主动 EOF。
- `weather_alarm_full.original.bytes`：完整读取 `https://forecast.weather.com.cn/api/v1/traffic/alarm/alarmMap` 的原始响应，保留现有 Referer/User-Agent 请求行为。响应头为 `text/html;charset=utf-8`，正文实际是 JSON，保留原先明确 UTF-8 解码的语义。完整正文 1,975,538 字节，manifest 保留 SHA-256。

测试首先核对原始 SHA-256，再直接处理原始字节。1/2/3/7/1024/16384 字节分块只改变同一字节序列的输送边界，未修改报文内容、时间、观测值或顺序。受控坏 UTF-8、CR/LF、BOM、无效 JSON 与 JS 包装边界另列为协议单元测试，不用于性能结论，也没有注入实时应用。
