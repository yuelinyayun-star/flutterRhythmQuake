# 原始 PLUM 核查样本

`whews_report_01.json` 至 `whews_report_05.json` 是事件 20261106194044（福島県中通り）的原始 Data 对象，直接逐字节取自用户此前要求导出的 `exports/whews_jma_20261106194044_reports_1-5_20261106.zip`。原始外层 WebSocket 封套当时未保存，不伪造。

`whews_saved_report_05.json` 是同一 ZIP 内修复前的保存记录，包含实际漏标的 `isAssumption:false` 和原始 sourcePayload；用于验证新版读取路径，不修改该记录来使测试通过。

`jian_documented_non_plum.json` 是 2026-11-06 从 JIAN 官方 API 文档取得的原样示例（https://api.sismotide.top/api/），是协议文档样例，不冒充实际抓包。

测试中的额外缺失参数组合仅验证显示组件，不是经过改造的真实报文，也不注入实时系统。原始文件不修改时间、坐标、震级、深度或 PLUM 标志。
