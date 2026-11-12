# A3 回放销毁资源释放修复（2026-11-02）

## 授权范围与证据

用户在回到 10 月问题清单后指定“先继续这个”，承接清单 A3（回放销毁资源未释放）。本次仅修复该控制器的销毁生命周期、所属推算资源与残留 UI 发布定时器。A2 导入播放条件继续只记录，不修改；不改推算公式、时间轴、报文、颜色、地图、轮播或其它信源策略。

修改前已使用当前真实 Release DLL 重跑原审查 22 项，确认原缺陷仍可复现。该组通过表示确认旧缺陷，不表示正确行为。原输入、基线结果保存在 `tmp/replay_disposal_fix_20261102/baseline.log`、`baseline-results.json`。

将测站发布定时器用例改为要求销毁后计数归零后，旧生产代码实测失败：Expected 0 / Actual 1；见 `red.log`。没有通过修改原始帧或放宽停止/新旧 session 约束来修复。

## 精确修改

| 文件及位置 | 原行为 | 新行为 |
| --- | --- | --- |
| `lib/services/debug/history_replay.dart`，`HistoryReplayController.dispose()`（1181 行起） | 清掉控制器 session，但没有停止这个 session 的独立推算服务 | 先保存自身 session 并使控制器失效；只有全局推算服务仍属于这个 session 时，才调用既有 `ReplaySourceEstimation.stop()`。新控制器已经接管时不停止新 session。 |
| 同方法的定时器清理 | 漏取消 `_stationPublishTimer`，取消后的其它 Timer 仍有字段引用 | 取消并置空测站发布 Timer、播放 Timer、测站调度 Timer；复位准备/测站交付状态。 |
| 同方法的显示缓存清理 | 保留 `_stationDisplayCurrent`、`_pendingStationSnapshot`、上次发布时间 | 清空三个控制器字段；原 `stationSnapshots.dispose()` 和文件释放流程保留。没有给已销毁通知器写值或额外通知 UI。 |
| `test/replay_disposal_full_audit_test.dart` | 审查用例要求看到旧泄漏和剩余定时器 | 对已修复缺陷改为要求资源/session/队列归零；原始输入、停止、自然结束、只关面板继续播放、读取错误、新旧 session 隔离断言保留。增加 P-Alert/NIED 旧活动控制器直接 dispose、新 owner 继续工作，以及 dispose 不调用 onClear/历史重载/UI 通知，共 3 项。输出移到本轮目录，不覆盖旧审查结果。 |
| `test/october_scope_audit_test.dart` | A3 特征用例要求销毁后 worker 仍在 | 改为销毁后原生 worker 回到基线、session 清空；A2 原导入失败特征及原始文件校验保持。 |

生产修改只发生在一个 `dispose()` 方法。`stop()`、`play()`、`playPrepared()`、推算队列、worker 实现及 Rust 计算代码保持本轮修改前内容。

## Rust 生产路径与所有权

这里修的是 Flutter `ChangeNotifier` 控制器的销毁挂接，不新增 Dart 后端计算、数据处理或业务策略。调用已有生产释放链：

- P-Alert：`ReplaySourceEstimation.stop()` → `PAlertSourceWorker.dispose()` → `NativeStationRuntime.stop()` → `rq_station_runtime_release`，实际 Rust runtime 退出并释放注册所有者。
- NIED：同一入口 → `NiedSourceEstimationWorker.dispose()` → 协作 close → `NiedSourceEstimationDriver.dispose()`、tracker/decoder 释放既有 Rust trigger、KA、观测历史等原生句柄。
- 同时沿现有 stop 逻辑增加 generation、取消 UI 通知 Timer、清空待处理队列、释放独立读取 cursor、移除 clock 闭包与推算结果。迟到旧帧不再计算或创建 worker。

未为绕开 Rust 失败添加 Dart 备用计算，也没有借销毁修复迁移或重写无关算法。

## 验证结果

修复后 2 文件共 27 项通过（专项 25 项 + 10 月审查 2 项）：

| 场景 | 实际结果 |
| --- | --- |
| P-Alert 原始帧经控制器后销毁 | Rust worker 1 → 0，session 清空 |
| NIED 原始帧经控制器后销毁 | trigger 1 → 0、KA 1 → 0、观测历史 1573 → 0；1573 仅为该样本的实际数量 |
| 启动过程中销毁 | P-Alert/NIED 启动中的迟到结果被丢弃，原生计数归零 |
| 一次读取阻塞、另有 3 帧排队时销毁 | 队列 3 → 0；只执行已进入的一次读取，迟到帧不处理，销毁后没有新 worker |
| 测站 UI 发布 Timer 未到时销毁 | 剩余 Timer 0；推进时钟无迟到发布或已销毁通知器错误 |
| `QuakeProvider.dispose()` 生产入口 | session 清空、worker 归零 |
| 旧活动控制器销毁，新 P-Alert/NIED owner 已接管 | 新 session 和资源不变，仍可处理下一原始帧 |
| 销毁的 UI 副作用 | onClear、历史重载、控制器通知、测站通知均为 0 |
| 正常停止、自然结束、只关闭回放面板、读取错误、旧帧迟到 | 原约束继续通过；只关闭面板仍继续回放 |
| A2 导入缺陷 | 仍按原来报错，未顺带修改 |

所有使用的原始文件结束后 SHA256 不变，最终受测原生计数均归零；没有根据句柄数虚构内存字节或将过去 2GB 内存/30% CPU 全部归因于 A3。

另有 9 个原有回放/测站/worker 测试文件共 64 项全部通过：播放和 Provider 接纳、时间轴、面板、目录读写、CWA 时序、测站归档/压缩块、排队推算、NIED worker。包括 10 份原始回放帧产生 10 次推算且实时 tracker 不变，以及原始奈良 GIF 51 帧产生 40 次推算。未修改这些原有测试。两批合计 11 个测试文件 91 项通过，无跳过；不是全仓库测试数量。

`dart analyze` 对本次 1 个生产文件、2 个测试文件检查无问题。原有数据读取错误用例和隔离 Provider 数据库未初始化日志不作为生产故障；相关断言继续通过。

本轮入口测试通过本地离屏 Flutter 引擎运行生产控制器、Provider 和实际 Release FFI，不占桌面、不向云机或上游发报。尚未将本次源码修复打包、安装或更新到云电脑；这与上一个安装包/云端更新分开记录。

证据目录：`tmp/replay_disposal_fix_20261102/`。`lifecycle-fixed.log` 和 `after/results.json` 保存完整资源矩阵，`production-before.json` 供比对本次修改范围。
