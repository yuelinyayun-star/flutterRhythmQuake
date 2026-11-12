# 回放录制逐帧写入审查与修改（2026-11-10）

## 授权范围与现场依据

本次针对“收到一帧／一报就提交独立文件，历史只留索引”，处理录制持有链、
写入积压和相关读取／关闭入口。没有重新设计事件分类、事件匹配、EEW 过期、
地图绘制、视角、测站取值、回放时钟或 OBS 业务。

云电脑旧进程的只读诊断见 `tmp/cloud_hang_20261110/findings.md`：
两个历史分组各引用 3,587 帧，去重后仍是 3,587 个完整帧对象，不是 7,174 帧；
保存任务积压为 17。主线程采样在 Dart 堆分配与 GC 中，伴随系统换页。
这些证据证明了帧持有／保存积压与未响应机制，没有证明最初是哪一帧导致落后。

## 找到的未完成入口

1. `QuakeProvider._recordStationHistoryFrame` 每次复制并追加完整帧列表，
   等整批历史保存返回才释放。目录格式并没有消除这个内存持有链。
2. `_queuePersistEewHistory` 每次定时调用都追加一个 Future；慢保存期间继续排队。
3. 历史报文原文仍等待整批保存才替换成文件引用。
4. `ReplayCollector._Capture.pending` 持有全部未检查点帧；
   检查点还复制这些列表、逐帧启动 compute，再保存所有事件。
5. 正常 APP 启动中，非 Windows IO 平台没有初始化独立历史文件 owner，
   仍可能进入首选项／旧 archive 写入路径。

## 具体改动

| 文件／位置 | 原行为 | 新行为与涉及功能 |
| --- | --- | --- |
| `lib/providers/quake_provider.dart` 的 `_recordStationHistoryFrame` | 完整帧追加到历史对象 | 同步交出当前帧给文件 owner，历史只持有文件键；保留原启用检查与活动事件匹配 |
| 同文件 `_queuePersistEewHistory`、`_persistEewHistoryUntilCurrent` | 每次请求追加整批保存 Future | 同时只运行一次保存，以 dirty 标记合并后续索引更新 |
| 同文件 `_captureHistoryReportsAt`、`_addToEewHistory` | 新报原文等待整批保存 | 立即提交独立报文文件，只压缩历史副本；活动 EEW 继续持有其原文 |
| 同文件 `dispose`、测试／性能只读入口 | 保存后没有独立 live owner 关闭步骤 | 最后一次索引完成后排空并关闭 owner；增加写入队列统计及测试等待入口 |
| `lib/providers/quake_provider_native_events.dart` 的 `history` action | Rust 分组结果直接保留原文 | 接入相同逐报提交，并重绑定 Rust 历史副本；不重算分类与匹配 |
| `lib/services/eew_history_store.dart` 的 `acceptFrame`、`acceptReports` | 没有接收即提交入口 | 多事件共享一次帧提交；返回轻量帧索引／报文引用，不持有异步模型队列 |
| 同文件 `_FrameIndex`、`_FrameKeys` | 每帧复制全部旧键或遍历查重 | 追加索引、按键查重；旧视图长度固定，不随后续追加改变 |
| 同文件 `_writeFolderGroup`、`_saveFolder`、读取入口 | 旧保存与新接收并发时可能覆盖引用／误删新文件 | 保留较新帧引用；按接收版本保护等待期间的新事件；读取前等待文件提交；清理已替换报文的缓存引用 |
| `lib/services/history_storage.dart`、`history_storage_stub.dart` | 仅普通异步读写接口 | 增加逐条提交、排空、重试、关闭接口及平台初始化入口 |
| `lib/services/history_storage_io.dart` | 新帧与设置读写共同经过 Windows worker | live 数据使用独立文件 owner，worker 只提交小索引／处理旧格式；其他 IO 客户端初始化同一目录格式 |
| `lib/main.dart` | 只初始化桌面首选项 | 在创建 provider 前初始化文件历史存储；仅新增 import 与初始化调用 |
| `lib/services/replay_history_files.dart` | 只有 await 文件接口 | 不支持此原生模块的平台逐条同步提交单个文件；不攒帧列表 |
| `lib/services/native_replay_history_files_io.dart` | 在串行存储 isolate 内写单文件 | 增加逐条 FFI 提交、轻量状态、异步排空、显式重试；Linux 仅为回放模块加载原生库，不改变其他模块的平台开关 |
| `native/station_core/src/replay_files.rs` | 单次借用字节并同步写文件 | Rust 后台写入线程负责有界字节队列、压缩、校验和文件提交；正常关闭排空；失败项保留待显式重试 |
| `lib/services/collector/replay_collector.dart` | 等 tick 的完整帧 pending 列表及批量 compute | 收到即提交一帧并记文件名；tick 只写元数据索引；空闲时仍仅留每源一个种子，不无事件落盘 |
| 同文件最近帧与关闭 | 原文种子与录制帧混在 pending 中 | 活动录制的最近帧只留文件名；按原有有效期清理失效种子，关闭时释放空闲种子 |
| `lib/services/collector/replay_file_export.dart` 的 `saveCaptureReports` | 检查点时逐报写文件 | 收报时提交并返回引用；导出继续复用独立原文文件 |
| `linux/CMakeLists.txt` | Linux bundle 没有回放 Rust 库 | 增加 Cargo 构建及 `lib/librq_station_core.so` 安装 |
| `test/history_streaming_capture_test.dart` | 无逐条接收／慢索引并发验收 | 增加实际 provider 入口、原文回读、共享、并发、失败重试及真实留存帧持续录制测试 |
| `tools/benchmark_live_replay_files.dart` | 无生产 AOT 文件通道测量 | 用原始留存帧调用生产模型与 Rust writer，记录提交耗时、进程内存和队列；逐帧回读校验，结束释放 owner 并删除本次临时帧副本 |
| `docs/replay_directory_storage.md`、`server/replay_collector/README.md` | 文档描述旧检查点写入／平台路径 | 更新数据所有权、平台范围、队列限制、构建依赖与索引时机 |

## 数据所有权、限制与提交边界

- 接收回调只临时持有当前模型。跨 FFI 边界逐条编码，Rust 接收后只持有编码字节；
  Dart 历史对象不再保留等待磁盘的完整测站图。
- 普通待写字节上限 8 MiB，包含正在写的一条。单个超过此预算的合法输入可以
  独占队列，仍受 128 MiB 单文件限制。满队列会施加背压，不丢帧、不无限分配。
- 当前帧的 JSON 编码与 FFI 提交仍在调用线程执行；队列满时提交也会等待空间。
  这消除了历史模型和保存任务的无界积压，但不代表磁盘任意慢时还能同时保证
  接收线程零等待。没有用另一个无界异步模型队列掩盖背压。
- 接收提交与持久化完成是两个步骤。回读、导出、索引提交和正常关闭等待排空；
  磁盘失败明确报错，失败项保留原始编码字节，可显式重试。
- 事件清单仍合并提交小索引（APP 原有计时、采集器每 5 秒），不是每帧重写全部历史。
  突然终止进程可能遗留尚未纳入最后清单的独立文件；本次没有增加崩溃恢复日志。
- 原始数值、时间、`snapshot` 和 `originalJson` 不抽样、不改写。压缩仅改变文件编码。
- 新录制使用独立帧／报文文件；旧历史 archive、旧 JSON 导入仍作为兼容输入。
  旧单体 JSON 导入仍需在短生命周期 worker 中转换，现有 128 MiB 输入限制保持。
  无文件系统的浏览器保留其平台存储路径，不把该兼容路径宣称为已迁完。
- Android／iOS 的目录文件 owner 仍是 portable 实现；本次原生写入模块正式支持
  Windows／Linux，不宣称其他平台或整个回放业务已全部迁到 Rust。

## 已执行验证

- 186 项 Rust 测试通过，包含队列容量、关闭排空、失败项保留／重试及已有所有权回归。
- 使用新 Rust DLL 的 130 项历史、回放、导入、导出、生命周期、原始报文、
  native event owner 回归通过，2 项可选用例跳过。
- 实际 `QuakeProvider → StationHistoryCapture → 文件 owner` 入口验证：
  活动 EEW 原文保持，历史报文变成文件引用，完整历史帧为 0，文件可回读。
- 用真实留存目录的 6,163 个帧文件逐个读取原始内容、录制、回读并比较完整 JSON 的
  SHA-256；测试仅长期保存摘要及索引，不把原文另存一份测试列表。
- 最终相关测试（含上述 6,163 帧完整持续录制、采集器、目录回放）28 项通过。
  完整历史帧始终为 0，Rust 队列峰值 3,720,052 B，结束积压 0。
  测试进程每 500 帧的 RSS 采样约 244–276 MiB，最终约 273 MiB；
  写入、读取、校验合计约 165 秒。
  这是 Flutter 测试进程数据，不是云电脑整机内存、CPU 或地图 FPS 验收。
- 独立 AOT 工具使用生产 `StationHistoryFrame → FFI → Rust writer` 通道，
  对相同 6,163 帧逐个回读并比较 SHA-256 全部一致，关闭后原生 owner 回到基线、
  result 数为 0。本次文件副本已清理，仅保留指标。
  写入阶段（含读取原始文件、解码、摘要校验准备）69,119 ms，
  回读与校验 39,896 ms；提交调用中位数 77 μs、95 分位 21,608 μs、
  最大 37,863 μs，队列峰值 3,449,506 B，结束积压 0。
  每 500 帧 RSS 采样约 50–67 MiB，最终约 58 MiB，进程峰值约 85 MiB。
  该工具不包含地图、信源连接与推算，不能与旧云电脑 APP 的整机占用直接相减；
  大帧同步编码的耗时仍客观存在，不能据此声称 UI 刷新效果已验收。
- 存储相关文件、新测试与 AOT 工具静态分析通过。Windows 个人版 Debug
  最终源码构建成功；生产 DLL SHA-256 为
  `493c371946af3e86d5e160dcd99f3ebeeda6da104d66e779e1ffb217a107e1c9`。
- Linux Rust 模块 `cargo check --target x86_64-unknown-linux-gnu` 通过。
  本机 WSL 的 Ubuntu VHDX 不存在、Docker Linux engine 未运行，因此没有宣称完成
  Linux bundle 的链接或运行验证，也没有修改这些环境来扩大本次范围。

原始日志／指标位于 `tmp/replay_stream_*20261110*`，
AOT 指标为 `tmp/replay_stream_aot_20261110/metrics.json`。
本次没有生成安装包、
安装或更新云电脑，也没有重启诊断中的旧进程。
