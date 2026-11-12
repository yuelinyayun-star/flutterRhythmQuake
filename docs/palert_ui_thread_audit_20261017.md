# P-Alert 与 LPGM 主 isolate 卡顿核验（2026-10-17）

## 运行时证据

采样对象为用户正在运行的 Windows Debug 进程 PID 40492（11:55:59
启动）。VM CPU profiler 采样窗口为 8 秒。VM 返回的缓冲区包含更早的
记录，因此按请求窗口的 requestedStart/requestedEnd 过滤逐条 sample，
没有直接使用累计 inclusiveTicks。

主 isolate 窗口内共 796 个样本，出现以下调用栈：

| 调用 | 包含此调用的样本数 |
| --- | ---: |
| LpgmMonitorService._fetchGifOrPng | 56 |
| PAlertService._fetchRealtime | 16 |
| PAlertDetector.update / _checkShakeDetection | 14 |
| NiedSourceStationEncoder.capture | 14 |
| _StationDotPainter.paint | 19 |

这些是采样栈计数，不是独占耗时，也不是整个进程的 CPU 百分比。
P-Alert HYP 已在 palert-source-estimation isolate；其上游 HTTP、JSON、
等级历史和联合检出仍在主 isolate。同步 FFI 会占用调用 isolate，
Rust 内核并不自动让调用异步。

## 修改范围

- 原生平台的 PAlertService 改为展示与转发接口。持续运行的
  palert-data-processing isolate 拥有原有 HTTP 客户端、原文、解析器、
  等级历史和联合检出器。已有 Rust 解析和等级内核在该线程调用。
- TLS 根证书只在根 isolate 加载一次，将原始 DER 字节交给连接 owner，
  保留既有证书校验和请求头。
- 处理 owner 同时提交测站、检出、确认 ID、原文与冻结历史快照，避免
  当前检出配到上一帧。UI 直接复用快照；地图回调不再重复生成历史。
- 回放直接将冻结的原始快照交给既有 P-Alert 推算 worker。测站解码、
  旧归档缺少确认 ID 时的联合检出，也在这个 worker 完成，保留原帧时间。
- 原生平台的 LPGM 原图直接传入现有图像 worker，由 Rust 解码采样，
  在 worker 中完成既有 SVA、排序和离群站历史计算。UI 接收最终摘要，
  不再分配 Skia 图像并遍历 352×400 个像素打包 RGB。
- GIF 透明通道保持原 rawRgba 的预乘表示；原图字节、站点、阈值和
  色标公式没有改动。Web 路径保持原有实现。
- 停止连接关闭 HTTP 与 native 会话；旧 generation 的返回被丢弃。
  数据 isolate 异常退出后断开显示，3 秒后重建连接。共享图像 worker
  关闭时取消 LPGM reset 不产生未处理的异步异常。

## 原始报文对照

输入为已归档 CWA 1150077 同期 P-Alert 原文：787 站、28 帧。源时间、
PGA、PGV、元数据均保持原值。对照仅将 HTTP 返回间隔压至 40 ms，
用根 isolate 的 8 ms 定时器测事件循环间隔，连续交替执行 3 轮。

| 轮次 | 原主 isolate 处理的最长间隔 | 独立处理后的最长间隔 |
| --- | ---: | ---: |
| 1 | 83.164 ms | 13.087 ms |
| 2 | 38.667 ms | 14.239 ms |
| 3 | 44.511 ms | 12.440 ms |

三轮独立处理均未观察到超过 16 ms 的定时器间隔；原主 isolate 路径每轮
均有超过 32 ms 的间隔。该实验验证这条数据链对事件循环的阻塞变化，
不是全 APP 帧率、CPU、GPU 或内存下降的证明。

## 验证与剩余工作

55 项定向回归通过，包括原始 HTTP 连接、等级/峰值历史、重复帧、
失败与停止重连、真实地震检出与帧一致性、PGA 初估和 CWA EEW 同屏、
LPGM 原图的数值/颜色/排序一致性、NIED 图像与联合检出回归。
原始 28 帧回放的 15 帧推算输出与原有 typed-frame 路径逐项一致，
同时确认回放没有写入实时推算状态。
Windows Profile 构建通过。没有构建 Android。

NIED 输入整理、部分连接收包/状态汇总和地图绘制仍在主 isolate，
不能宣称整个数据链已经全部移出。数据处理移出线程也不等于已经把
全部 Dart 算法改写为 Rust。用户当前旧 Debug 进程需要完整重启加载
新的持久数据 owner，再进行整机帧率与占用采样。

本轮备份、CPU 原始采样、对照脚本和结果保存在本地审计目录
`tmp/palert-ui-thread-20261017/`。
