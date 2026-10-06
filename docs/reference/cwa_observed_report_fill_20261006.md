# CWA 地震报告实测震度填色

## 来源核对

核对日期：2026-10-06。地震报告与 EEW 的本地预估是两条独立路径。

| 来源 | 已核对格式 | 地区/测站震度 |
| --- | --- | --- |
| WHEWS | 当前公开文档 `/ws/cwa` | `intensities[].pref -> areas[] -> stations[]`；县市和测站均使用显示震度字符串，包含 `5- / 5+ / 6- / 6+`。文档说明上游缺少完整震度表时不输出此字段。旧抓包中也确实有不带震度表的摘要。 |
| TREM / ExpTech | 当前原始列表与详细报告响应 | 列表 `int` 只有事件最大震度；详细报告 `list[县市].int` 与 `town[站名].int` 才是区域、测站实测震度。此格式为 0..9 序数：6 是 5强、7 是 6弱、9 是 7级。 |
| Jian | 当前 `/cwa` 文档、现有原始抓包 | `intensity` 为事件最大震度，没有声明或提供地区、测站明细。适配器仍支持显式 `intensityAreas`，但不能声称当前 Jian CWA 报文有该字段。 |
| FAN | 仓库归档 `/cwa` 文档 | 声明震源参数、报告图 `imageURI`、等震度图 `shakemapURI`，没有结构化测站震度表。现在保留收到的 `intensities` / `intensityAreas`，但不把协议兼容测试说成 FAN 实际已输出明细。 |
| Wolfx | 现有服务 | CWA EEW，不是 CWA 地震报告路径。 |

参考：

- [WHEWS 当前报告文档](https://api.beecld.com/#ws-cwa-report)
- [Jian 当前 CWA 文档](https://api.sismotide.top/api/#ws-cwa)
- [ExpTech 原始列表](https://api.core.exptech.dev/api/v2/eq/report?limit=2)
- [ExpTech 原始详细报告](https://api.core.exptech.dev/api/v2/eq/report/115068-2026-1006-164108)
- `docs/fan_studio_api/FAN Studio WebSocket 数据服务 API 文档.md` 的 `/cwa` 段落。

## 实现

- 每个县市取报文中有效的区域、测站实测震度最高值，同县市重复项合并。不同县市不共享事件最大震度。
- 统一 `warnArea` 中持久化实测区域值，标记 `kind: observed`；原始 `sourcePayload` 不改写。
- CWA 报告使用 `cwaObserved` 模式和现有 CWA 测站震度颜色；没有明细的区域不填色，也不调用 CSIS 或 EEW 预估。
- ExpTech 只为最新报告请求详情。事件 ID、发震时间、经纬度、震级、深度必须全部与原始列表相符，否则不绑定。没有按“最近时间”猜测配对，也没有跨 API 偷换事件。
- 详细报告缓存最多 16 项、5 分钟；列表 md5 变化时重新取详情，失败不缓存，下一轮重试。轮询禁止并发重入，停止后未完成请求不再发布事件。
- 列表先更新，再等待详情（最多 6 秒）；详情失败仍发布原始摘要，不将报告详情失败当成整个列表源断线。
- 实测区域变化纳入前台、后台正文去重。相同报告后来补上地区表可更新原卡，不延长其首次到达时间，不重复通知。

## 验证数据

- `test/fixtures/source_estimation/cwa_report_115068_original.json`：详细报告原始 HTTP 响应，未改写数据。
- `test/fixtures/source_estimation/cwa_report_list_20261006_original.json`：原始 HTTP 列表响应，未改写数据。
- `test/fixtures/source_estimation/whews_cwa_report_documented_example.json`：公开文档原例子，不是实测抓包。
- 对报告 `115068-2026-1006-164108`，实测结果为高雄市 3、屏东县 2、嘉义县/彰化县/台中市/台南市 1；其他县市不填色。
- 手机 390x844 和桌面 1280x800 验证实际 PolygonLayer 的县市覆盖、逐区域颜色和拖动后的多边形列表复用；摘要无明细时不产生填色多边形。

尚无结构化明细的 API 不从报告图片 OCR 猜测，也不以预估取代实测。
