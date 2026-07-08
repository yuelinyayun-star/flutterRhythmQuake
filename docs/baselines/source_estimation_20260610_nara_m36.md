# 震源估算基线：2026-06-10 奈良 M3.6

> 基线日期：2026-06-20  
> 数据窗口：2026-06-10 18:01:20-18:02:10 JST  
> 真值标签：北纬 34.2、东经 135.8、M3.6  
> 状态：P0 首个单事件基线，不用于参数标定

## 运行方式

```powershell
flutter test test/source_estimation_baseline_test.dart --reporter expanded
```

默认读取：

```text
tmp/captures/20260610_180130_jst_nara_m36
```

可以覆盖捕获目录：

```powershell
flutter test test/source_estimation_baseline_test.dart `
  --dart-define=SOURCE_ESTIMATION_CAPTURE_DIR=D:\path\to\capture
```

机器可读报告生成到：

```text
.dart_tool/source_estimation_benchmark/20260610_nara_m36.json
```

## 输入一致性

三种算法使用相同的逐帧 GIF 解码结果与台站状态：

- `weighted_centroid_baseline` 和 `nied_gif_hybrid_v1` 分别运行在独立的 `SeismicSourceTracker` 中；
- `scratch_scan_v1` 直接读取同一帧 `NiedStation` 状态；
- 现代算法沿用生产逻辑，只在检测阶段达到 `detected/strong` 后建立事件；
- Scratch 算法在至少三个活动台站时即可输出，所以首次结果时间不能与现代算法直接等同。

## 首次结果

本次运行完整解码 51/51 帧。

| 方法 | 有结果帧数 | 首次结果相对标签时间 | 中位误差 | P90 误差 | 10 秒误差 | 20 秒误差 | P90 跳动 |
|---|---:|---:|---:|---:|---:|---:|---:|
| `weighted_centroid_baseline` | 34 | +7 秒 | 210 km | 237 km | 238 km | 213 km | 4.8 km |
| `nied_gif_hybrid_v1` | 34 | +7 秒 | 646 km | 737 km | 725 km | 718 km | 15.4 km |
| `scratch_scan_v1` | 40 | +1 秒 | 48 km | 65 km | 42 km | 48 km | 5.2 km |

5 秒时 `weighted_centroid_baseline` 与 `nied_gif_hybrid_v1` 尚未输出，因此该指标为 `null`，不能写成 0 公里。

运行耗时受设备、调试模式和首次编译影响，保留在 JSON 报告中用于发现数量级回归，不作为跨设备冻结值。

## 解读

本事件中，当前混合算法明显偏离真值，不能通过继续手调某个权重直接修复。需要先在更多事件上判断误差来自：

- 触发时间语义；
- 同源派生 PGA/PGV/PGD 的重复计权；
- 活动台站选择；
- 候选搜索范围；
- 海陆或台网几何；
- 当前真值标签精度。

旧 Scratch 在这一事件上更好，但单事件结果不能证明其整体更优。P1 数据集建立前，本报告只用于确认基准框架和防止无记录回归。

## 关联文件

- 事件清单：[`test/fixtures/source_estimation/nara_m36.json`](../../test/fixtures/source_estimation/nara_m36.json)
- 基准测试：[`test/source_estimation_baseline_test.dart`](../../test/source_estimation_baseline_test.dart)
- 基准支持库：[`test/support/source_estimation_benchmark.dart`](../../test/support/source_estimation_benchmark.dart)
- 实施路线：[`docs/source_estimation_roadmap.md`](../source_estimation_roadmap.md)

