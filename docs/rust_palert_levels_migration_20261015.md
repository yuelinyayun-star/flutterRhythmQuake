# P-Alert 实时等级与峰值历史迁移

## 采样与范围

对正在运行的 Windows Profile 进程 48284 开启 VM CPU 采样 30 秒，保存原始结果后关闭 profiler。主 isolate 收到 357 个样本；项目函数中 `_fetchRealtime` inclusive 14、`_checkShakeDetection` / `PAlertDetector.update` inclusive 9，NIED 测站交接也有样本。inclusive 调用相互包含，不能相加或直接视作整机 CPU 百分比。本轮选择 P-Alert 实时更新链，不将短时采样当作所有场景的热点排名。

原始采样：`build/performance/connection_hotspots_20261015-205641.json`。

本轮将 PGA／PGV 的批量等级计算、按报文时间维护的三秒峰值历史迁入 Rust，并接到实际 HTTP 响应后的实时更新流程。每帧一次 FFI 调用，目录以稳定索引映射，不在 Rust 中重复维护测站字符串表。实时发布的不可变测站对象保存本次计算结果，检出和显示读取当前等级时直接复用；更换 PGA／PGV 的 `copyWith` 会失效该缓存。

HTTP 连接调度、GraphQL／JSON 字段映射、时间解析、旧帧拦截、通知和联合检出总控仍保留现有 Dart 逻辑。本轮不属于整条 P-Alert 网络链完全迁移，也没有迁移其他源的连接管理。

## 一致性与释放

- 保留原 PGA／PGV 阈值和高 PGA 缺少有效 PGV 时的等级 15 下界。
- 只有 PGA／PGV 时间相同时才使用 PGV；这一判断仍在原服务入口。
- 使用源报文的微秒时间，三秒边界包含端点；不使用接收时间代替源时间。
- PGA 缺失不更新对应历史；NaN／无穷／负数仍按原规则处理。
- 目录重排保留对应测站历史，删除测站释放其历史，新站不继承旧站数据。
- 断开／停止清空原生 owner 和输入输出缓冲；返回结果独立拥有存储，后续调用不能改变旧结果。
- 不改变原始响应、归档、检出门槛、声音级别、震源算法、地图及统一 UI。
- 非原生平台使用同一批量接口的 Dart 实现；没有增加 Android 原生目标。

ABI `rq_palert_levels_*` 版本 1，现有 station core ABI 不变。CMake 已加入新源文件依赖。实现：`native/station_core/src/palert_levels.rs`、`palert_level_history.dart`、`native_palert_levels_io.dart`；接入：`palert_service.dart`。

## 原始输入和回归

使用原有 `test/fixtures/palert_cadence_20261014` 的目录与 12 条原始 GraphQL 响应，787 个目录站，原时间 2026-10-14 09:04:50–09:05:12 UTC。它们是安静时段的采样，不证明地震期间的震级精度或检出准确率。另以明确的控制输入测试阈值两侧、缺测、非有限值、时间回退和目录重排；控制输入不作为实时报文或性能数据。

独立旧实现保留原 `_heldLevelFor` 算法用于对照。HTTP 集成测试把保存的响应字节直接送给服务，核对原 PGA、PGV、报文时间、当前／保持等级，重新送旧帧验证不会覆盖新帧，并检查 `stop(clear:false)` 释放原生状态。

- 最终 Rust 30 项通过。
- Windows CMake 目标生成的 DLL：相关 Flutter 主组 72 项通过。
- 非原生组 53 项通过、4 项原生专属跳过；与主组有重复，不累加独立测试数。
- 新增代码、测试和工具静态分析无问题。
- 清理前清单中的 203 份原始 fixture SHA-256 全部未变，包括上述 P-Alert 原始响应。
- Windows CMake `rq_station_core_build` Profile 目标通过。

主组的 source visibility 测试仍输出既有测试环境 SQLite 未初始化诊断，但所有断言通过；没有因此宣称完整数据库集成已验收。

## 独立 AOT 对照

最终使用 Windows CMake 生成的 DLL，SHA-256：`96159A4E6A1D3BC02CE3A469B40112C8FAAE7CAECBC776B8E13F96CE95B81684`。

三轮、每种实现独立进程，轮次交替顺序，20 次预热。每轮重复 500 次完整 12 条序列，每条序列重建独立历史，不修改原时间或测量值。总计每种每轮 6000 帧；计时包含目录配置、输入打包、FFI 复制、计算、返回结果和校验和，不包含磁盘读取／JSON 解析。各实现的完整输出校验和相同。

| 实现 | 耗时中位 ms | 结束 RSS 中位 MiB |
| --- | ---: | ---: |
| 旧 Dart 阈值＋字符串历史表 | 4193.278 | 49.199 |
| 本轮紧凑批量 Dart 路径 | 2670.312 | 49.152 |
| Rust 批量路径 | 858.144 | 49.242 |

Rust 比旧实现耗时减少 79.54%，比本轮紧凑 Dart 路径减少 67.86%；包含交接的每帧平均约 0.143 ms。结束 RSS 基本持平，没有整机内存下降结论。测站等级缓存的额外收益没有单独计入这组基准。

工具：`tools/benchmark_palert_levels.dart`、`tools/benchmark_palert_levels.ps1`。最终轮次／DLL／样本哈希：`build/performance/palert_levels_comparison_20261015.json`。首次独立 Cargo DLL 的约 83% 结果已被上述产品构建链 DLL 的最终对照替代。

## 当前运行边界

未关闭或覆盖原先正在运行的 Profile 窗口；它仍加载上一轮代码。此次构建仅生成 CMake 原生目标和 AOT 基准，没有重新打包 Windows 安装程序，没有构建 Android，没有修改云端。整机 CPU、GPU、帧耗时及 EEW＋测站完整回放收益仍需在包含此修改的完整 APP 构建中单独验证。

没有新建整份项目备份；保留既有迁移前备份和实验资料。本轮新增的对照是小型旧算法参考文件。
