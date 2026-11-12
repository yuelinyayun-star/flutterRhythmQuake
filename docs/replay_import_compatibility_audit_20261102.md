# A2：导入入口与新旧回放格式核查（2026-11-02）

> 后续状态：用户随后授权修复，两处问题已经修复并完成回归，详见 [A2 修复及验证](replay_import_fix_20261102.md)。下文是修复前审查记录；初始日志保留，相关测试后来改为验证正确行为。

本轮授权是检查 A2 与新旧格式兼容的关联。只新增专项测试和核查记录，未修改任何生产导入、播放、时间策略或 Rust 代码，未打包、安装或更新云电脑。

## 已验证结论

### 1. 导入后的准备播放入口没有适配文件式包

Windows 生产调用链：

`HistoryReplayControls._import` → `history_replay_file_io.importReplay` → `importReplayFile` → `controller.importPackages` → 点击播放 → `playPrepared`。

- v1/v2 JSON 先由 `HistoryReplayPackage.decode` 读取，随后在工作 isolate 中转换为 v3 `files-v1` 目录，打开为拥有逐报读取器的包。
- v3 ZIP 先解压，再经同一个 `openReplayDirectory` 打开。不是把 ZIP 交给旧 JSON 解析器。
- 这两条路径都会得到 `storedReports != null`、`hasFileReports == true` 的独立文件式包。
- `QuakeProvider.historyReplay` 一直配置本地历史加载器；`playPrepared` 只检查 `storedReports != null`，误将独立导入包判定为需要本地历史锚点。导入并未选择本地历史，因此抛出 `Missing saved replay selection`，加载器实际调用次数为 0，报文也没有发布。
- 同一控制器、同一包在诊断测试中直接调用 `play()`，可以按文件读取并发出原始首报；这个对照只定位故障，不是生产修复或建议用户绕过入口。

位置：`lib/widgets/ui/history_replay_controls.dart` 的 `_import` / `_play`；`lib/widgets/ui/history_replay_file_io.dart` 的 `importReplay`；`lib/services/debug/history_replay_directory_io.dart` 的 `importReplayFile` / `openReplayDirectory`；`lib/services/debug/history_replay.dart` 的 `importPackages` / `playPrepared` / `play`；`lib/providers/quake_provider.dart` 的 `historyReplay` 初始化。

旧测试为什么没有挡住：部分控件测试创建控制器时没有传 `loadHistoryGroup`，`playPrepared` 直接转入 `play()`，恰好绕过生产配置下出错的分支；目录格式测试检查了文件读取、导出以及本地已保存历史播放，但没有覆盖“独立导入 + 配置历史加载器 + 点击播放”的组合。本轮补测该组合，没有修改旧断言。

### 2. 另有一处报文时间索引兼容遗漏

原始 CEA v1 文件 `cea_202609290220.rqreplay` 的 `reportTime` 字段为 null，但原始 `sourcePayload.ReportTime` 为 `2026-09-29 02:20:44`，接收时间为 `2026-09-29T02:21:17.061343`（UTC+8）。

| 阶段 | 时间策略 | UTC 回放起点 |
| --- | --- | --- |
| 直接解码原始 v1 | report | 2026-09-28T18:20:44.000Z |
| 生产导入转换后 | arrival | 2026-09-28T18:21:17.061343Z |
| 当前导出 v3 再导入 | arrival | 2026-09-28T18:21:17.061343Z |

差值为 **33.061343 秒**。原始报文内容全部一致，发生变化的是回放时间索引策略。

调用证据：`exportReplayDirectory` 只从已有存盘引用 `ref?.reportInstant` 写入索引。对内存解码的原始包，`ref == null`，导致索引 `reportInstant == null`；摘要又按既有文件式设计移除了大报文 `sourcePayload`。重新打开时，`_sourceReportInstant` 无法从摘要获得原始 `ReportTime`，便选择接收时间。对应位置是 `history_replay_directory_io.dart` 的报文索引生成 / 引用读取，以及 `history_replay.dart` 的 `_sourceReportInstant` / `_validated`。

已确认适用条件是：时间只存在于原始报文、导出时缺少已有 `reportInstant` 引用、并且存在有效接收时间；不将这一结果直接推广为所有信源都存在时间漂移。样本中的 CWA v1 和 GQ v2 时间数组均保持一致。

## 实际验证与边界

- 原始输入：CWA v1（4 报）、CEA v1（1 报）、GQ v2（18 报）。没有改版本号、报文、观测或时间戳。
- 分别通过当前生产导出器生成 3 个 v3 ZIP，保留原始报文；原始 3 个文件加新导出 3 个文件，共 6 种输入。
- 6 种输入分别开关时间轴联动，共 12 项：逐一读取全部报文比较完整 `toMap()`、比较时间索引、复现准备错误，再对照直接播放首报。CEA 时间差以明确缺陷断言记录，没有忽略差值。
- 另有 3 项真实控件入口测试：模拟选择文件，但导入和播放使用真实 `HistoryReplayControls` 按钮及真实文件 IO；v1/v2/v3 均显示同一错误。测试在独立 Flutter 引擎运行，未操作桌面 APP。
- 专项 15 项加原有目录/文件 IO 12 项，合计 **27 项通过**。其中缺陷特征断言通过表示缺陷被稳定复现，不表示已经修复。原有本地保存历史准备播放测试正常。
- 所有原始输入 SHA-256 在测试结束后复核不变。结果、原始失败断言和日志保存在 `tmp/replay_import_compatibility_audit_20261102/`。
- 本次三个原始包都是报文包，没有包含测站帧；原有目录测试覆盖逐帧文件读写，但不把它宣称为原始完整测站包兼容验收。没有测试浏览器或安装版，也未宣称它们已通过。
- 该准备判断及目录格式转换当前仍在 Dart 调用链；本轮只核查。若后续授权修复，相关后端策略应按项目要求切换 Rust，并保留本地历史加载及原始回放时间规则。

## 本轮文件变化

- 新增 `test/replay_import_compatibility_audit_test.dart`：新增 15 项缺陷定位测试；生产行为没有变化。
- 新增本文件：记录入口、格式、时间索引差异、验证及未覆盖范围。
- `docs/october_change_scope_audit_20261101.md`：A2 增加本次核查链接，原始审查记录保留。
