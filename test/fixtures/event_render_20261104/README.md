# 原始成图问题报文（2026-11-04）

以下文件为本轮实际 HTTP 响应正文，按字节保存；SHA256 见 sha256.json。

| 文件 | 来源 |
| --- | --- |
| wolfx-jma.original.json | https://api.wolfx.jp/jma_eqlist.json |
| p2p.original.json | https://api.p2pquake.net/v2/history?codes=551&limit=100 |
| wolfx-cenc.original.json | https://api.wolfx.jp/cenc_eqlist.json |
| cenc-ir.original.json | https://api-cencint-public.nowquake.cn/list?pageNo=0&pageSize=20 |
| cenc-ir-detail.original.json | https://api-cencint-public.nowquake.cn/event/20261104053408 |

测试使用原始响应，不修改地名、时间、坐标、震级或烈度。LPGM“震度7／阶级4”测试另外明确构造组件输入，不冒充上游报文。
