# JMA 最终目录关联格式

> Schema：`jma_catalog_v1`  
> 用途：为回放事件关联可追溯的最终震源标签

## 约束

- 目录文件必须离线冻结，不能在评测过程中查询变化中的在线接口；
- `generatedAt` 使用 UTC；
- 每个事件的 `originTime` 必须带 `Z` 或明确时区偏移；
- 只接受 `status=final` 或 `status=reviewed`；
- 必须保存目录级 `catalogId/revision/sourceUrl` 和事件级
  `eventId/resourceId/revision`；
- P2PQuake 最近有感地震列表不能作为最终统一目录。

JMA 官方月报使用 96 字节固定长震源记录。下载并解压官方文件后可转换：

```powershell
dart run tools/import_jma_hypocenter.dart `
  --input path/to/hypocenter-file `
  --output data/catalogs/jma_2023.json `
  --catalog-id jma-monthly-2023 `
  --revision 2025-12-15 `
  --source-url https://www.data.jma.go.jp/eqev/data/bulletin/hypo.html
```

官方格式说明：

- <https://www.data.jma.go.jp/eqev/data/bulletin/data/format/fmthyp_j.html>
- <https://www.data.jma.go.jp/eqev/data/bulletin/data/format/hypfmt_j.html>

截至 2026-06-20，JMA 月报下载页最新仅到 2023 年，因此项目中的
2026 年事件暂时不能升级为 `catalog_verified`。

## NIED 数据的角色

NIED 可以补足 JMA 月报发布前的空窗，但来源必须分级：

| 来源 | 项目用途 | 真值等级 |
|---|---|---|
| Hi-net 自动震源目录 | 近期小震的时间、位置、深度参考；事件检索 | `reference_only` / preliminary |
| Hi-net 提供的 JMA 一元化震源目录 | 按其目录版本使用 | 只有明确最终版时才可 `catalog_verified` |
| K-NET/KiK-net 自动发布 | 快速获取大震强震波形，允许噪声和误关联 | provisional observation |
| K-NET/KiK-net 正式发布 | PGA、PGV、仪器震度和波形验证 | reviewed observation |

注意：

- Hi-net 自动震源目录与 JMA 最终目录不是同一层级；
- NIED 说明 K-NET/KiK-net 的事件震源信息基于 JMA；
- 自动发布数据可能包含非地震噪声、仪器异常和测试记录；
- K-NET/KiK-net 不提供 P/S 到时，若使用波形必须由项目自行拾取；
- 波形下载需要注册，并受禁止再分发等使用条款约束。

官方说明：

- <https://www.hinet.bosai.go.jp/sitemap/>
- <https://www.kyoshin.bosai.go.jp/en/about_pubdata/>
- <https://www.kyoshin.bosai.go.jp/en/faq/>

## 格式

```json
{
  "schemaVersion": 1,
  "catalogId": "jma-unified-2026-06",
  "revision": "2026-07-01",
  "sourceUrl": "https://example.invalid/jma/catalog",
  "generatedAt": "2026-07-01T00:00:00Z",
  "events": [
    {
      "eventId": "event-id",
      "resourceId": "jma:event-id",
      "revision": "final-1",
      "status": "final",
      "originTime": "2026-06-20T12:25:27Z",
      "latitude": 39.893,
      "longitude": 142.512,
      "depthKm": 38.0,
      "magnitude": 3.4,
      "region": "岩手県東方沖",
      "sourceUrl": "https://example.invalid/jma/event-id"
    }
  ]
}
```

## 关联

默认只输出候选，不修改 fixture：

```powershell
dart run tools/link_jma_catalog.dart `
  --catalog path/to/jma_catalog.json `
  --case test/fixtures/source_estimation/iwate_offshore_m34_ref.json
```

人工确认候选后增加 `--write`。工具会更新震源参数、
`catalogTruthVerified` 和完整目录来源。若前两名评分过近则返回
`ambiguous`，禁止自动写入。
