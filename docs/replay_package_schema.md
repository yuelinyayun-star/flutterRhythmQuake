# 地震回放包格式

> Schema：`replay_package_v1`  
> 状态：P1 初版  
> 更新时间：2026-06-20

## 1. 目标

回放包必须能够固定数据来源、时间轴、解码器、台站库、缺帧和真值版本。检测器与震源估算器只能消费包内明确声明的数据，不能依赖开发机绝对路径或不断变化的在线目录。

第一版兼容现有平铺 GIF 捕获目录，不移动或复制原始文件：

```text
<capture-directory>/
  manifest.json
  truth.json                 # event 必需，noise 不需要
  stations.json
  frames/index.json
  capture_manifest.json      # 原捕获记录
  *.jma_s.gif
  *.jma_b.gif
```

`rawLayout=flat_capture_v1` 表示帧索引中的路径相对于包根目录。后续可以增加 `raw/jma_s`、`raw/jma_b` 布局，但不能静默改变 v1 语义。

## 2. manifest.json

必填字段：

```text
schemaVersion
packageId
caseType
timeZone
startTime / endTime
expectedFrameIntervalMs
expectedTimestampCount
decoderVersion
stationDbVersion
sensorSelectionPolicy
rawLayout
frameIndexPath
stationSnapshotPath
truthPath
layers
missingFrames
sourceUrlTemplates
provenance
```

时间必须带明确偏移量。日本回放统一写为 ISO 8601 `+09:00`，不再依赖本机时区解释无偏移时间。

当前版本：

```text
decoderVersion = nied_gif_shindo_v1
stationDbVersion = kanameishi_niedsitepub_1749_v1
sensorSelectionPolicy = surface_jma_s_primary_v1
```

`surface_jma_s_primary_v1` means the default real-time shindo input and map
station display read `jma_s` for every scan-mapped station. `jma_b` may still be
captured and stored as an auxiliary borehole layer, but it is not default
source-estimation scoring evidence.

## 3. frames/index.json

索引为逐秒记录，不把地表和井下图层当成两个时间帧：

```json
{
  "observedAt": "2026-06-20T18:44:42+09:00",
  "receivedAt": null,
  "layers": {
    "jma_s": {
      "available": true,
      "path": "20260620184442.jma_s.gif",
      "bytes": 1234,
      "sourceUrl": "https://...",
      "qualityFlags": []
    }
  }
}
```

现有捕获 v1 没有保存逐帧接收时刻，因此 `receivedAt=null`，并在 provenance 中标记 `receivedAtStatus=unavailable_in_capture_v1`。不得用数据时间伪造接收时间。

更早的旧样本可能没有 `capture_manifest.json`。构建器允许按 fixture 的时间范围和 `gifNamePattern` 扫描本地 GIF，生成 `schemaVersion=0` 的 legacy synthesized manifest。该清单只证明“包目录里存在这些文件”，不证明下载时间、HTTP 状态或实时接收时刻，因此 `receivedAtStatus=unavailable_legacy_synthesized`。

历史捕获脚本 schema v2 新增：

```text
observedAt
receivedAt = null
retrievedAt
retrievalDurationMs
cacheStatus
sha256
qualityFlags
```

`retrievedAt` 仅表示从历史 URL 取回文件的时间，不是实时数据到达时间。只有后续实时捕获模式才能填写 `receivedAt` 和真实接收延迟。

实时捕获脚本 schema v3 新增并约束：

```text
captureMode = live
requestStartedAt
receivedAt
receiveDelayMs
attempts
clock.source / synchronized / offsetCorrectionMs
```

实时帧的 `receivedAt` 是本机成功接收并校验 GIF 的完成时刻。双图层都成功时，帧级 `receivedAt` 取两个图层中较晚的时刻；任一图层缺失时帧级值为 `null`，图层级记录仍保留。当前脚本只使用本机系统时钟，因此统一增加 `clock_unsynchronized` 质量标志；该延迟可用于采集链路诊断，但在接入可靠时钟校正前不能当作高精度网络延迟真值。

## 4. stations.json

冻结当前回放使用的完整台站快照与版本，包括代码、名称、经纬度、网络和都道府县。即使后续在线台站库变化，历史回放仍使用包内快照。

## 5. truth.json

真值与原始观测分开版本化。至少保存：

```text
status = reference_only | catalog_verified
agency
eventId
resourceId
revision
source / sourceUrl
preferredOrigin
magnitude
eventLabels
```

该结构借鉴 FDSN Event/QuakeML 对外部事件标识、来源机构和首选震源解的可追溯思路，但不是 QuakeML 的替代格式。参考解升级为最终目录解时必须更新状态和来源，不覆盖原始捕获 provenance。

参考：<https://www.fdsn.org/webservices/>

## 6. 构建与验证

构建茨城县冲样本：

```powershell
dart run tools/build_replay_package.dart `
  --case test/fixtures/source_estimation/ibaraki_offshore_m19_ref.json
```

验证：

```powershell
flutter test test/replay_package_test.dart
flutter test test/replay_dataset_test.dart
flutter test test/split_aware_replay_benchmark_test.dart
```

回放包验证器检查 schema、时间范围、逐秒连续性、安全相对路径、缺帧去重、版本字段、图层、文件存在性和字节数。数据集验证器检查 train/validation/test split、case 去重、安全路径和测试集泄漏。
split-aware 评测器输出位于 `.dart_tool/split_aware_replay_benchmark/`，包含顶层 `summary.json`、`summary.md`，以及每个 split 的 `source.json`、`source.md`、`detection.json`、`detection.md`。

开始新的在线捕获：

```powershell
.\tools\capture_nied_gif_live.ps1 `
  -CaseId "live_20260620_evening" `
  -DurationSeconds 900
```

实时捕获必须写入新的空目录，禁止从已有 GIF 推断 `receivedAt`。脚本每完成一个时间戳就原子更新 `capture_manifest.json`，中断后仍可识别已完成范围，但当前不支持恢复后继续伪装为同一次连续捕获。

## 7. 尚未完成

- 使用同步时钟标定实时捕获的 `receivedAt` 与下载延迟；
- 把解码后的逐站观测写入 `frames/<timestamp>.json.zst`；
- 冻结像素映射和台站选择质量标志；
- 关联 JMA 最终统一震源目录及修订号；
- 扩充到至少 20 个有效地震事件和 10 个噪声窗口。

JMA 最终目录的冻结格式和关联工具见
[`docs/jma_catalog_schema.md`](jma_catalog_schema.md)。关联工具默认只预览，
只有人工确认后使用 `--write` 才能升级 `truth.json` 的来源状态。
