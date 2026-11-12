# 工作流 E 实施方案（设计决策稿，2026-11-12）

> 状态：**E-1（方案 B）已于 2026-11-12 实施并通过验证**（实现见 `lib/services/background_station_history_recorder.dart`；验收记录见 `.workbuddy/memory/2026-11-12.md`）。E-2（方案 C）待后续会话。前置分析见 `.workbuddy/memory/migration_lists_20261112.md` 工作流 E 清单。

## 现状（代码事实）

1. **文件 IO 已全部在 Rust**：`NativeReplayHistoryFiles` op 0–13（帧/报告/记录/索引读写、压缩、原子写、队列 flush）+ `NativeStationArchive`（gzip 打包）。
2. **仍在 Dart 的部分**：
   - 录制决策：`QuakeProvider._syncStationHistoryRecording`（UI 侧 `_unifiedEvents` 活动判定）
   - 帧入组/3min 窗口/去重：`QuakeProvider._recordStationHistoryFrame` → `EewHistoryStore.acceptFrame`
   - 事件分组/快照/索引编排：`EewHistoryStore`（1273 行，含 Expando 缓存语义）
   - 读取：新路径（`HistoryFileStorage`）已是惰性 entry + Rust 逐文件读取，无重计算；legacy 路径有 `compute(_indexStoredFrames)` 解码
3. **架构缺陷（E 的核心目标）**：录制链路为 后台 isolate → 桥接 → UI → acceptFrame → Rust 落盘。UI 引擎被系统回收时录制中断（前台服务 isolate 仍存活）。

## 关键方案分叉：双写者问题

录制迁到后台 isolate 后，**UI 与后台同时持有指向同一存储目录的 EewHistoryStore**：

- UI 需要写：EEW 历史列表展示的分组/快照更新（`save`/`acceptReports`）、历史删除、回放导出
- 后台需要写：录制期间逐帧 `acceptFrame`、录制窗口的事件分组

### 方案 A：录制写路径整体后台化，UI 降级为只读消费者
- 后台 isolate：判定活动 EEW（复用 `sendUnifiedEvent` 已有的判定点）→ 建组/入组/落盘（acceptFrame→Rust op=8）→ 维护 index
- UI：`restoreForStartup`/`loadStationFrames`/`loadReports` 只读；历史删除/导出通过桥接命令发后台执行
- 桌面（非托管）：保持现状（UI 即数据所有者）
- **优点**：单一写者（Android 托管时）；彻底解决"UI 死录制断"
- **缺点**：改动面大——quake_provider 录制状态机、eew_history_store 写归属、历史删除/导出的桥接命令、桌面/Android 双路径分叉；EEW 分组匹配逻辑（`_isSameUnifiedEewEvent`）需在后台复制或抽出共享

### 方案 B：录制窗口期间后台独占写，UI 暂停写
- 录制中（工作流 A 的 `stationHistoryRecording=true`）：后台 isolate 直写帧；UI 的 save/acceptFrame 跳过（桥接帧仍发用于展示）
- 录制结束：后台发"录制完成+index 增量"给 UI，UI 恢复写并合并
- **优点**：改动集中（后台加录制窗口写路径；UI 加跳过+合并）；非录制期 UI 行为不变
- **缺点**：合并协议要处理两侧行期间的事件分组一致性（边界帧归属）；UI 死亡时后台 index 与 UI 内存 index 的对账逻辑仍需实现（即仍要方案 A 的对账子集）

### 方案 C：Rust 单一所有者状态机（完整迁移）
- 按 Explore 清单：Rust 端扩展 `replay_log.rs` 承载 acceptFrame/acceptReports/save/restoreForStartup 全状态机，Dart 两侧都退化为命令发起器
- **优点**：彻底满足"后端策略迁 Rust"；天然单写者；双 isolate 零协调
- **缺点**：工作量最大（复刻 1273 行编排语义 + snapshot/legacy 兼容 + Expando 等价去重 + 一致性验收测试）；多会话工程

## 建议

**分两阶段**：
1. **E-1 = 方案 B**（本会话可完成）：后台录制窗口直写 + UI 暂停写 + 完成后对账合并。解决核心架构缺陷（UI 死录制断），改动可控可验证。
2. **E-2 = 方案 C**（后续会话）：Rust 状态机完整接管，两侧 Dart 退化为命令发起器。届时方案 B 的对账逻辑被自然替代。

## 验收基线（两阶段通用）
- 同一批真实历史文件（`test/fixtures/history_replay/cwa_1150074.rqreplay` + 现有 `history_streaming_capture_test` 场景）迁移前后读取结果逐字段一致
- 前后台切换/后台录制中 UI 被杀（模拟）场景下帧完整
- 已存历史文件零迁移（文件布局不变）
