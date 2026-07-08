# 震源估算自动基线：`source_estimation_p0`

> 此文件由基线测试自动生成，请勿手工修改。

案例总数：3（事件 2，静稳 1）

## 数据集

| 案例 | 类型 | 请求帧 | 解码帧 |
|---|---|---:|---:|
| `20260610_nara_m36` | event | 51 | 51 |
| `20260620_satsuma_m26_d179` | event | 151 | 151 |
| `20260614_quiet_175544` | noise | 41 | 41 |

## Event Detection Summary

> Detection denominator: 1 eligible observable events; 1 of 2 catalog/reference events excluded.

| Detector | Candidate coverage | Confirmed coverage | Missed confirmed events | Noise candidate frames | Noise confirmed frames | Median candidate delay | Median confirmation delay |
|---|---:|---:|---:|---:|---:|---:|---:|
| `spatiotemporal_event_detector_v1_source_trigger` | 1/1 | 1/1 | 0 | 0/41 | 0/41 | 3s | 3s |

## 方法汇总

| 方法 | 事件覆盖 | 漏估事件 | 静稳误报帧 | 中位误差 | P90误差 |
|---|---:|---:|---:|---:|---:|
| `weighted_centroid_baseline` | 1/2 | 1 | 0/41 | 23.5 km | 55.9 km |
| `nied_gif_hybrid_v1` | 1/2 | 1 | 0/41 | 8 km | 13 km |
| `scratch_scan_v1` | 1/2 | 1 | 0/41 | 48 km | 65 km |

## 分案例结果

| 案例 | 方法 | 输出帧 | 中位误差 | P90误差 | 误报帧 |
|---|---|---:|---:|---:|---:|
| `20260610_nara_m36` | `weighted_centroid_baseline` | 38 | 23.5 km | 55.9 km | 0 |
| `20260610_nara_m36` | `nied_gif_hybrid_v1` | 38 | 8 km | 13 km | 0 |
| `20260610_nara_m36` | `scratch_scan_v1` | 38 | 48 km | 65 km | 0 |
| `20260620_satsuma_m26_d179` | `weighted_centroid_baseline` | 0 | - | - | 0 |
| `20260620_satsuma_m26_d179` | `nied_gif_hybrid_v1` | 0 | - | - | 0 |
| `20260620_satsuma_m26_d179` | `scratch_scan_v1` | 0 | - | - | 0 |
| `20260614_quiet_175544` | `weighted_centroid_baseline` | 0 | - | - | 0 |
| `20260614_quiet_175544` | `nied_gif_hybrid_v1` | 0 | - | - | 0 |
| `20260614_quiet_175544` | `scratch_scan_v1` | 0 | - | - | 0 |
