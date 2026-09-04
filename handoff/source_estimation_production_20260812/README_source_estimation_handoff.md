# 震源推算生产算法交接说明

本目录用于对外分享当前应用中实际接入的震源推算（Source Estimation）生产链路代码。

## 生产算法与入口

- 生产估算器类：`NiedDartHypSourceEstimator`
- 所在文件：`lib/core/source_estimation/source_estimator.dart`
- 生产默认接线：`StationEventTracker.useDefaultNiedEstimator()`
- 接线文件：`lib/core/source_estimation/station_event_tracker.dart`

## 打包文件清单

1. `lib/core/source_estimation/source_estimator.dart`  
   核心震源推算实现（包含 `NiedDartHypSourceEstimator` 等估算器）。
2. `lib/core/source_estimation/station_event_tracker.dart`  
   生产默认估算器装配与切换入口。
3. `lib/core/source_estimation/source_estimation_models.dart`  
   震源推算请求与结果模型定义。
4. `lib/core/source_estimation/seismic_source_tracker.dart`  
   事件级跟踪与估算流程编排。
5. `lib/core/source_estimation/srev_kaizou_magnitude.dart`  
   震级估算相关实现（与主算法输出联动）。
6. `lib/core/source_estimation/srev_kaizou_scratch_station_table.dart`  
   震级估算用台站参考表。

## 说明

- 本包是按原始相对路径复制，便于对方直接定位调用关系。
- 如果对方只看主算法，至少需要阅读 `source_estimator.dart`。
- 若要理解“生产如何启用”，需同时查看 `station_event_tracker.dart` 的 `useDefaultNiedEstimator()`。

## 打包信息

- 打包目录：`handoff/source_estimation_production_20260812/`
- 压缩文件：`handoff/source_estimation_production_20260812.zip`
- 生成日期：`2026-08-12`
