# 两个 DYFI 原始事件（2026-11-02）

用于复现手动选中第一条事件后，第二条自动情报的震中漏画。详情、网格和坐标均为官方响应原始字节；SHA256 见 manifest.json。

- California：`nc75461147`，https://earthquake.usgs.gov/fdsnws/event/1/query?eventid=nc75461147&format=geojson
- Kenai：`aka2026vqjriv`，https://earthquake.usgs.gov/fdsnws/event/1/query?eventid=aka2026vqjriv&format=geojson
- KMZ URL 已记录在 manifest.json，均从详情原始 contents 下载，没有拼造替代网格。
- 获取时 California 已更新为 81 份报告、最大 CDI 3.4；截图是更早的 79 份版本。没有为了匹配截图改写当前原始数据。
- Kenai 为 113 份报告、最大 CDI 3.9，与截图对应事件一致。

测试中的 publish/select 只控制本地 UI 状态，不改动事件或产品报文字段。
