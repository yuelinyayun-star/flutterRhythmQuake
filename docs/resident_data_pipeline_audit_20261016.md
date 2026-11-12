# 连接至 UI 的常驻处理核验（2026-10-16）

本轮只检查本地代码和正在运行的 Windows Debug 进程，没有修改业务、UI、设置、原始报文或云端。下列优先级根据调用频率、全量遍历和数据所有权确定，不代表已测得各模块占用比例。

## 当前进程采样

- PID 44372，`build/windows/x64/runner/Debug/flutterrhythmquake.exe`。
- 约 15.40 秒内累计 CPU 13.27 秒，按 16 个逻辑处理器归一的整机平均约 5.38%。
- 工作集 606.40–624.69 MiB，私有内存 604.36–620.88 MiB；线程数 126–130。
- 并行线程采样的前五线程分别累计 3656、2094、2000、1984、1234 ms CPU，线程名称均未获取到，不能据此归为 UI、Rust 或某个台网。
- 原始计数保存在 `tmp/resident_pipeline_sample_20261016.json`。这是运行中 Debug 的短时观察，不是 Profile/Release 性能、固定输入对照或内存分配归因。

## 已核实的持续处理

| 优先级 | 路径 | 触发与实际工作 | 常驻数据 / 完整迁移缺口 |
| --- | --- | --- | --- |
| 1 | `quake_map_view.dart::_onWhewsNiedFrame` → `_acceptNiedStations` | 每个有效测站帧逐站写时间、震度、PGA/PGV；再进入检出、推算输入、显示签名、焦点、归档和摘要 | Flutter 侧仍持有完整可变测站对象；Rust 已承担部分解码/计算，但测站状态与领域编排仍回到 Dart |
| 1 | `nied_source_estimation_worker.dart` / `nied_source_station_frame.dart` | 开启推算后每帧扫描目录是否改变、分配数值数组并传往持久 isolate；worker 应用帧、执行 Dart 领域驱动、返回结果；其中数值内核可为原生 | 主 isolate 的测站、worker 的测站、推算状态与传输帧同时存在；isolate 不等于 Rust 全链迁移；推算关闭时已有 reset/关闭机制 |
| 2 | `quake_map_view.dart::_emitStationSummary` | 多个台网各自更新均调用同一个方法；每次扫描 SeisJS、NIED、TREM、KMA、P-Alert、S-net，整理长周期和检出区域 | 一个台网更新会重复计算其他台网的摘要；检出区域还建立站点桶、计算归属、排序。这是显示数据准备，不只是 Widget 绘制 |
| 2 | `StationHistoryCapture` | `retainOriginal` / `restoreOriginal` 持有各源最新原文；`publish` 保留最新帧构造闭包，录制时才构建完整显示快照 | 现有按需构建应保留；`setEnabled(false)` 只移除 `_latest[kind]`，不会清理 `_raw` 中已停用源的原文。应先明确元数据重新播种规则再迁移所有权，不能直接删目录 |
| 3 | `EqlistManager.onAnyUpdated` → `QuakeProvider::_rebuildFlat` | 任一列表更新都检查 ShakeMap/DYFI，遍历全部桶、过滤、JMA 去重、全量排序，然后裁为 100 条，最后计算签名 | 签名相同只省了最后发布，前面的合并/排序仍已执行；UI 的 100 条不代表所有桶只持有 100 条。应由原生事件仓库按桶修订维护索引和列表投影 |
| 3 | `QuakeProvider::_handleUnifiedEvent` / `_mergeUnifiedInfoEvent` | 报文到达时做接纳、过期、身份去重、修订/取消、历史同步、语音和发布决策 | 活跃事件、去重状态、历史与业务 Timer 仍由 Dart 拥有。这是按报文触发的常驻服务，不是空闲时不断忙算；取消报和多源顺序必须用原始归档验收 |
| 4 | `ObsAutomationInputService` / `ObsAutomationRunner` | 有输入监听时逐帧建立测站 Map 并比较边沿；runner 用 Future 链排队处理 | 无监听已经跳过，不能认定关闭 OBS 就必然仍处理；runner 是否监听由启用预设决定，和 WS 是否连接不是同一个条件。需测队列延迟再判断是否积压 |

## 已核实的缓冲与连接边界

- `NativeWebSocketChannel` 用 native port 收到通知才 drain，每批最多 32 项；没有常驻轮询 Timer。Rust WebSocket 队列有 64 MiB 字节上限，这只是上限，不能当作每条连接已分配 64 MiB。
- `StationJsonDecoder::_reserveInput` 只在容量不足时扩容，直到 dispose 才释放；每次原生解析的打包结果还通过 `Uint8List.fromList` 复制为 Dart 拥有的文档。当前迁移消除了部分 Map 对象树，却没有消除“完整结果回 Dart”的边界。
- `source_http_client_io.dart` 的原生 HTTP 默认开关关闭，现有普通 HTTP 仍走 Dart 客户端；此前组件对照回退已记录，不能宣称所有连接原生化。
- Wolfx 每 10 秒请求既有订阅数据。其原生桥显式 `textAsBytes:false`，收到的文本再进入原生 JSON 解码，仍存在字节→Dart String→原生字节中转；原文日志已有按类型相同正文抑制，并非每 10 秒必定打印整列表。
- NIED 图像实时轮询 1 秒、Yahoo 500 ms 是有效源的输入周期；物理图层已按实际检出激活，不能为了降占用改变观测输入或丢帧。
- 动画时钟已有租约机制，没有活动租约即停止；统一倒计时 Timer 仅存在于 EEW 活跃期。低频心跳、条件动画本轮不认定为主要 CPU 热点。

## 接下来应迁移的完整单元

先把测站源的目录、动态值、保持/过期、检出与推算输入交给同一原生会话；原文由后端归档，Flutter 只接收有限地图和侧栏快照。保留所有原始观测和顺序，显示快照可以批量发布，计算输入不能合并丢弃。

随后把列表桶、统一事件身份与修订/取消、有效期、产品绑定和语音决定迁入原生事件仓库。这样才会移走上层持续遍历和重复对象持有，单独替换 socket 或 JSON 解析器不完成这一步。

下一次收益验收应覆盖同一份原始 EEW＋测站归档、相同源设置、稳定运行及结束释放；同时记录处理延迟、队列长度、UI 帧耗时、进程 CPU、Dart 堆和原生保留量。当前采样没有将 600 多 MiB 分摊给这些路径，也没有报告尚未发生的优化收益。
