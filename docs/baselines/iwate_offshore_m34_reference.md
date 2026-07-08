# 岩手县冲 M3.4 参考回放

> 状态：reference only  
> 数据时间：2026-06-20 21:25:27 JST  
> 来源：Hi-net 震源情报；EQuake 最终报用于及时捕获窗口  
> 回放包：`tmp/captures/20260620_212527_jst_iwate_offshore_m34_ref`

累计触发口径复核：

```text
EQuake 触发：85 站
robust trigger 单帧峰值：39 站
robust trigger 全窗口累计 triggered：81 站
全窗口累计 activity >= 3：84 站
参考震中 160 km 内累计 triggered：42 站
```

因此 EQuake 的触发数更接近事件级累计集合，不应与单帧峰值直接比较。该接近关系
尚不能证明两者采用相同阈值或关联算法。

## 事件参考

```text
震中: 岩手县东方冲 (39.893 N, 142.512 E)
震级: M3.4
深度: 38.0 km
EQuake 触发: 85 站 (P: 30 | S: 42 | O: 13)
```

该解来自 Hi-net 震源情报，已写入回放包 `truth.json`，状态为 `catalog_verified`。由于当前数据集 split 尚未重新分配，该事件暂不进入正式指标分母。

## 回放包

```text
窗口: 2026-06-20T21:24:57 至 2026-06-20T21:27:27 JST
时间戳: 151
图层: jma_s / jma_b
GIF: 301 / 302
缺帧: 2026-06-20T21:27:27+09:00 jma_b
台站快照: 1749
```

缺帧原因：下载内容不是 GIF。该帧按缺帧记录，不做补值。

## 检测诊断

| 检测器 | 候选帧 | 确认帧 | 候选延迟 | 确认延迟 |
|---|---:|---:|---:|---:|
| legacy_shake_detection_adapter | 108 | 0 | 13s | - |
| spatiotemporal_event_detector_v0 | 54 | 52 | 21s | 23s |
| spatiotemporal_event_detector_temporal_bridge_v0 | 57 | 55 | 21s | 23s |

网络证据：

```text
最大触发台站数: 39
最大连通簇: 36
最大连通簇直径: 241.4 km
```

本地可观测性：

| 半径 | 最大 rising | 最大 triggered | 最大 connected | candidate evidence frames | confirmed evidence frames |
|---:|---:|---:|---:|---:|---:|
| 50 km | 0 | 0 | 0 | 0 | 0 |
| 100 km | 9 | 11 | 11 | 31 | 24 |
| 160 km | 23 | 34 | 34 | 41 | 36 |

半径扫描：

| 半径 | 最大连通簇 | candidate frames | confirmed frames |
|---:|---:|---:|---:|
| 80 km | 36 | 49 | 38 |
| 120 km | 36 | 52 | 38 |
| 160 km | 36 | 55 | 44 |
| 240 km | 36 | 74 | 44 |

## 震源估算诊断

source benchmark 现在使用独立 `spatiotemporal_event_detector_v1_source_trigger` 作为震源推算触发门控，而不是 legacy NIED 检出状态。独立检测确认后，旧震源算法能够输出，但海域误差很大：

| 方法 | 输出帧 | 首次输出延迟 | 中位误差 | P90误差 | 中位跳动 | P90跳动 |
|---|---:|---:|---:|---:|---:|---:|
| weighted_centroid_baseline | 53 | 22s | 96.0 km | 124.4 km | 2.0 km | 5.9 km |
| nied_gif_hybrid_v1 | 53 | 22s | 43.0 km | 54.0 km | 0.0 km | 21.4 km |
| scratch_scan_v1 | 53 | 22s | 486.0 km | 489.0 km | 0.0 km | 4.5 km |

上表已包含 P5 late-drift stability gate。该门控只在 warmup 后拒绝与上一稳定解
或 warmup anchor 距离过大的候选，不对输出坐标做无依据平滑。

legacy 检测在该事件中只有 candidate、没有 confirmed；如果仍用 legacy 驱动震源估算，会错误地得到 0 输出。该问题已在回放评测中修正：震源估算自己的触发门控消费独立事件检测结果，legacy 只保留为对照诊断。

## 结论

- 该事件是有效的近海参考样本，100-160 km 范围内有明确本地网络证据。
- 它证明“独立检测 confirmed 后可以启动震源估算”，但当前旧震源算法对海域事件定位很差。
- 不使用 EQuake 坐标计算正式震源误差；当前参考解已更新为 Hi-net。
- 暂不加入 split 指标分母，避免参考真值和正式目录真值混用。
