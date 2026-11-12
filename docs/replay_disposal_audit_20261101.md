# 回放销毁与推算资源完整专项审查（2026-11-01）

> 2026-11-02 状态更新：本问题已按用户本轮授权修复并通过实际 Release FFI 资源验证，见 [A3 修复及验证](replay_disposal_fix_20261102.md)。下文是修复前专项审查，保留原结论、22 项复现及影响边界；不是当前未修复状态。

## 结论

此前“控制器销毁后仍有一个worker”成立，但影响不止一个计数：**销毁路径没有结束其拥有的推算session、排队任务、独立读取游标及计算所有者。** 原始P-Alert和NIED通过控制器播放入口均已复现，生产 `QuakeProvider.dispose()` 也复现。

本轮只审查，没有改回放生产代码；此前“只记录，不改回放”的要求继续有效。没有改原始数据或用户桌面。本轮新增一个专项测试及本文，并补充审查索引。

## 根因与所有权

1. `HistoryReplayController.play()` 在 `history_replay.dart:935` 调用 `ReplaySourceEstimation.instance.start(session, () => position)`。
2. 正常 `stop()` 在清除控制器session之前确认全局推算session归属，再调用 `ReplaySourceEstimation.stop()`，释放读取游标、清空队列、销毁两种推算worker、清空clock及结果。
3. `HistoryReplayController.dispose()` 取消了一部分控制器定时器并清除自身session，却没有执行上述推算清理。生产 `QuakeProvider.dispose()` 直接调用这里，没有先stop。
4. `ReplaySourceEstimation.instance` 是强引用单例；它保留 `_nied` / `_palert`、`_reader`、队列及 `_clock`。clock闭包引用控制器的 `position`，因此控制器dispose并不意味着这个对象图可以GC。dispose也没有清空控制器的 `_stationDisplayCurrent` / `_pendingStationSnapshot`。
5. NIED回放仍通过独立Dart isolate编排并持有Rust检出和观测历史；P-Alert回放使用独立Rust runtime。不能把P-Alert的 `NativeStationRuntime.workers` 一个计数当成所有NIED资源计数。
6. Rust释放函数本身能工作：P-Alert `NativeStationRuntime.stop()` 关闭接收端口并调用 `rq_station_runtime_release`，原生注册表移除所有者、发送Close；NIED发送协作关闭消息，worker释放driver和tracker后退出。缺口在控制器销毁时没有发起这条释放链，不是已证实的Rust free无效。

引入记录仍为10月14日17:07:03 `call_9621be51eda44fd985a221150f7063b9`：新增推算start和stop，遗漏dispose；原始补丁引用见 `tmp/october_audit_20261101/replay-changes.txt`。

## 实际保留资源

原始数据、真实Release DLL；启动、销毁后等待200ms、再显式清理进行对照：

| 原始输入 | 推算已启动时 | 控制器dispose之后 | 显式stop之后 |
| --- | --- | --- | --- |
| P-Alert CWA 1150077归档 | 1个Rust runtime worker | 仍为1，session保留 | worker为0，session清空 |
| NIED紀伊水道原始归档 | 1个trigger句柄、1个KA句柄、1573个观测历史句柄 | 三组计数均保留，session保留 | 三组计数全部为0 |

1573是这份实际原始样本的句柄数，不是所有事件的固定数；没有据此虚构保留字节数或推断2GB内存归因。

## 异步与退出场景矩阵

新增 `test/replay_disposal_full_audit_test.dart`，完整组合执行 **22项通过**。其中缺陷特征测试通过表示成功复现缺陷，不表示已经修复。

| 场景 | 已验证结果 |
| --- | --- |
| 从未播放的控制器dispose | 不产生推算session或原生资源 |
| P-Alert/NIED正常手动停止 | session、队列和受测原生句柄均清理 |
| P-Alert/NIED自然播放结束 | 原始报文配合独立参考时钟推进，不改原数据；自动stop后资源归零 |
| 只关闭回放控制面板 | 控制器和session继续存在，符合面板不拥有播放寿命的设计；此项只验证UI所有权，实际原生资源另由生产控制器用例验证 |
| P-Alert/NIED启动过程中stop | 未完成提交被丢弃，资源归零 |
| P-Alert/NIED启动过程中dispose | 仍完成处理并保留资源，缺陷成立 |
| P-Alert/NIED从控制器读入原始测站帧，计算完成后dispose | 上表资源保留；不是仅手动调用推算服务的孤立结果 |
| 一个文件读取阻塞，另有3帧排队，然后stop | 队列清空；只执行当前1次读取，迟到结果不计算、不创建worker |
| 相同条件改为dispose | 3帧仍排队，释放读取阻塞后总共处理4帧；**控制器销毁之后仍能新建P-Alert worker** |
| 控制器测站文件读取失败 | 在已有实际worker的条件下触发受控IO错误；控制器自动stop，保留错误提示，资源归零 |
| 准备本地历史期间dispose | 迟到loader结果不开始播放，不产生资源 |
| 原始报文读取期间dispose | 迟到报文不发布；但已创建的推算session仍保留，属同一清理遗漏 |
| 新控制器接管后旧控制器stop/dispose | 不会停止新session；所有者比较目前有效，后续修复必须保留 |
| 停止/重启后旧测站读取迟到 | 不覆盖新session、不增加新session处理数 |
| 连续3次P-Alert重新播放/销毁 | 计数保持1，没有每次加1；新的 `start()` 会先清旧session。不能把本缺陷说成每次重启无限多出一个worker |
| 实际 `QuakeProvider.dispose()` | 同样遗漏其回放推算清理 |

队列/IO用例只控制读取完成时机或制造明确IO异常，使用未改动的原始帧；未伪造地震数值、未改接收时间。

## 额外的定时器遗漏

`HistoryReplayController.dispose()` 还没有取消 `_stationPublishTimer`。用两份原始帧、参考时钟及受控慢文件读取复现积压追赶：销毁前2个非周期定时器，销毁后剩1个测站UI发布定时器。

这一个计时器的延迟上限为80ms；推进100ms后计数为0。其session比较挡住了迟到发布，没有触碰已dispose的 `stationSnapshots`。**它是有界的清理遗漏，不应混同为持续worker泄漏。**

主播放Timer、下帧Timer、事件过期Timer已有dispose取消；准备/报文读取的generation或session保护在受测边界有效。没有发现这些保护反过来杀掉新session。

## 影响边界与不能推出的结论

- 根Provider在 `main.dart` 中是顶层所有者。关闭历史面板、抽屉或回放控件不等于销毁这个Provider，也不等于触发该缺陷；面板关闭时继续播放不属于泄漏。
- 缺陷发生在进程仍存活而回放控制器/Provider已销毁时。整个进程退出后的操作系统资源回收不属于本问题，不能说退出APP后Rust线程还在。
- P-Alert回放配置为 `sourceDisplayOnly`，队列耗尽后原生线程等待命令；不能仅由worker数量断言它在持续满CPU计算。有积压时，销毁后的队列确实继续计算，已实测。
- 未测量该对象图的精确保留字节、云电脑长期内存或整机CPU。因此不能宣称已解释用户此前2GB/30%的全部来源。
- 独立推算session不向实时tracker/上游连接/录制器写回；本轮没有发现该缺陷把回放观测当成新的实时报警发送。也没有向云端发报。
- 原始NIED归档位于本机既有验证目录，测试明确依赖该原件，不把缺件当作通过。所有使用过的原始文件结束时逐项校验SHA-256不变。

## 建议的精确修复边界（尚未实施）

仅处理销毁资源：在清除控制器session之前结束**该控制器拥有的**推算session；复用资源清理步骤，取消测站发布Timer，清空最后的快照引用。必须保留新旧session归属判断和迟到结果保护。

不能无条件停止全局新session；也不能简单复制整个stop的UI通知、历史重新加载和onClear副作用到dispose而不检查调用时机。此修复不需要改报文、时间轴、导入条件、推算公式、颜色或地图行为。已有Rust资源通过现有原生关闭接口释放；Flutter所有者销毁不应被扩写为一次算法重构。

## 复跑与产物

```powershell
$OutputEncoding=[Console]::OutputEncoding=[Text.UTF8Encoding]::new()
$env:RQ_STATION_CORE_LIBRARY=(Resolve-Path build/windows/x64/rq_station_core/cargo/x86_64-pc-windows-msvc/release/rq_station_core.dll).Path
flutter test --no-pub test/replay_disposal_full_audit_test.dart
```

- `tmp/replay_disposal_audit_20261101/lifecycle-complete.log`：22项组合运行。
- `results.json`：逐场景的实际计数、原始文件哈希及最终资源状态。
- `analyze.log`：新增测试静态分析无问题。
- `production-hashes.json`：本轮核查的生产文件指纹，未修改生产实现。

早期测试夹具曾误取另一个时间段的NIED帧而尚未到调度时间；改为按该事件原始归档索引选帧。FakeAsync与原生Future初版未完整驱动微任务，出现测试框架等待；修正参考时钟驱动并将UI所有权和原生计算用例分开。相关旧日志未算成通过或生产缺陷；没有通过改原始时间、删已有生产断言或改生产实现来解决这些夹具问题。
