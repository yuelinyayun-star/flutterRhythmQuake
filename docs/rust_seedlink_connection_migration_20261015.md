# SeedLink 连接数据处理迁移（2026-10-15）

本轮迁移 Windows SeedLink 收包链中的两段逐样本处理：MiniSEED 数值解码，以及持续波形滤波和活动检出。TCP、TLS、代理、订阅、心跳、断线重连、时间过滤、机构归属和 UI 仍由原 Dart 代码处理。Android 等其他平台继续使用既有 Dart 路径。

## 备份与边界

改动前文件及 SHA256 清单保存在 `build/performance/backups/seedlink-signal-20261015-082004`。旧信号实现冻结在 `test/support/seedlink_signal_analysis_before_20261015.dart`，旧解码循环冻结在 `test/support/seedlink_codec_before_20261015.dart`。原始采集文件没有修改，没有改 SDK 或云端服务。

连续信号状态、三段 Direct Form II 滤波、初始化窗口、峰值历史、重复/迟到过滤、间断重置和检出状态迁入 Rust。滤波系数由原 `iirjdart` 生成，按原 Float64 数值传给 Rust；没有重新设计滤波器。每个 NSLC 单独持有状态，共享的 FFI 输入缓冲仅在同步调用期间使用，不向 Dart 返回借用指针。

MiniSEED 解码迁入 Rust 的范围是 INT16、INT32、STEIM1、STEIM2。报头解析、UTC 时间、采样率和业务有效性判断仍沿用原路径；解码保持大小端、D0 跳过、32 位有符号积分和不完整记录输出。每份返回的 Int32List 独立拥有存储，后续解码或断线释放缓冲不会改写旧记录。

停止/重连先逐一释放连接里的信号会话，再清空 Map；编解码 scratch 同时释放。连接诊断增加 `sampleDecoder`、`signalProcessor`，可核对是否运行 `rust-abi-1`。NativeFinalizer 用于释放未显式销毁的信号 owner，不能代替正常连接清理。

## 原始输入核验

使用此前保存的 TC.QUEP 实际采集，共 206 包、45,003 个样本。原始波形 SHA256：

`e7439875fc6ea7a12631eff2719a2c329f626c3ca0ebdac78cb36190c803bc94`

ObsPy 解码/灵敏度记录 JSON SHA256：

`49bfd3f5643b7a2d0e2a51b2e42040ba52f1ec2e91e0612191bf6e32e057a8ef`

全部样本同时对照冻结 Dart 和既存 ObsPy 结果，逐项一致。186 个已有 ratio 逐 Float64 位比较一致，77 个检出包状态一致；已有 Java BetterAnalysis oracle 最大误差为 0。重复包返回原快照，间断/迟到输入与原 Dart 一致，显式释放后会话数、scratch 字节均归零。

独立的 ObsPy/libmseed 编码测试夹具用于验证两种字节序、四种编码及所有 payload 前缀的部分输出；它们是既有受控编解码测试数据，不作为真实地震采集或性能样本。

## AOT 性能

同一 Flutter 3.41.1 所带 Dart AOT，独立进程顺序运行，各三轮取中位数。信号负载重复相同未改动的 EHZ 原始记录至不同独立状态，不能视为实际观察到 300/5000 个在线测站。

| 范围 | 输入工作量 | 原 Dart | Rust + FFI | 耗时下降 |
| --- | --- | ---: | ---: | ---: |
| 信号处理，300 路 | 19,800 包，4,500,300 样本 | 293.173 ms | 148.883 ms | 49.22% |
| 信号处理，5000 路 | 330,000 包，75,005,000 样本 | 4636.190 ms | 2430.868 ms | 47.57% |
| 数值解码 | 61,800 包，13,500,900 样本 | 239.052 ms | 113.764 ms | 52.41% |

信号组件进程 RSS 中位数：300 路 48.594 → 18.918 MiB，5000 路 75.727 → 54.328 MiB。采样时两侧状态均仍存活；Rust 侧另记录显式销毁后的 RSS，未拿销毁后的值与原 Dart 的存活值比较。解码组件 RSS 约 47.53 → 47.81 MiB，没有内存下降证据。

三轮原始数字：`build/performance/seedlink_signal_comparison_20261015.json` 和 `build/performance/seedlink_codec_comparison_20261015.json`。数值解码速度和信号速度是两个局部测量，不能相加后当作整个连接或 APP CPU 降幅；没有本轮完整主界面帧耗时、GPU 或长期 RSS 结论。

## 验证

- Rust 内核 21 项单元测试通过。
- 带新 DLL 的 45 项 Dart 回归通过，覆盖原始输入、编码、信号、连接恢复及多机构订阅。
- 连接回归包含 3000 订阅扩容、断线 live DATA 恢复、过期记录、220 站慢元数据、INFO 分包和多机构去重。
- 本轮重点文件定向静态检查通过，完整 Windows Profile 构建成功。
- 17 项连接测试增加逐项 teardown 核验，会话数和 scratch 字节归零；非原生 Dart 路径另有 9 项回归通过。
- 打包目录里的 DLL 再跑 8 项原始解码/信号回归通过，DLL 与 Cargo release 产物 SHA256 相同：`a74a11f8d2f4cc3acacf6a3ec2074d5c43ed1e53cba37419c4482527ad0d8e96`。

WHEWS/Jian 的 JSON 解析、GlobalQuake Java 对象流解析与测站业务分发仍是后续待测路径，本轮没有将它们宣称为已迁移。
