# A2：回放导入及报文时间索引修复（2026-11-02）

用户在新旧格式专项核查后授权“你修一下”。范围仅为已确认的导入准备误判和报文时间索引遗漏；本轮未修改其他回放时间轴、地图、测站样式、源适配、轮播或推算算法。

## 生产改动及调用位置

| 文件 / 位置 | 原行为 | 当前行为及影响 |
| --- | --- | --- |
| `lib/services/debug/history_replay.dart`：`needsHistoryLoading`、`playPrepared`、`play` | 准备入口把所有 `storedReports` 都当成本地历史；实际播放入口又单独排除文件读取器，规则不一致 | Rust 统一判断加载需求。独立导入且文件读取器齐全时不需要本地选择；本地历史选择继续保留原预加载，即使已具备文件读取器；存盘测站索引和未准备的历史仍要求原加载流程。播放入口保留原先就绪检查。 |
| 同文件：`_sourceReportInstant`、`reportTiming` | Dart 选择来源时间、存盘时间或原始报文时间并换算 UTC | Windows 生产调用直接进入 Rust；保留原始字段优先级、时区、秒/毫秒判断以及普通墙钟毫秒精度和 ISO 微秒精度；返回 UTC 时间描述，不改原始报文。 |
| `lib/services/debug/history_replay_directory_io.dart`：`exportReplayDirectory` 报文索引 | 仅写已有存盘引用的 `reportInstant`，内存原始报文的时间可能丢失 | 原始报文经 Rust 确定的发布时间写入索引；已有原始文件直接复用。只有旧引用缺失必要时间时逐报读原文件，保持哈希及摘要校验。 |
| 同文件：`openReplayDirectory` 完整路径/文件索引验证之后 | 旧 v3 索引缺失发布时间时，摘要没有原始时间可用，可能改选接收时间 | 缺失时间的旧索引逐报读取原文件，补齐内存里的时间描述；不改原 ZIP、manifest 或报文文件，不保留完整报文对象；新文件索引齐全时不走这一补读。 |
| 同文件：`_validateOriginal` | 原校验位于逐报读取闭包内 | 抽为同文件函数，由原闭包及必要的时间索引补读复用；原有签名和非空原始报文校验保留。 |
| `native/station_core/src/replay_policy.rs` | 无统一的原生回放准备/发布时间策略 | 新增两个 Rust 命令：`needsHistory` 和 `reportInstant`，以及借用输入、释放输出的 FFI；不保留报文或会话。 |
| `lib/services/native_replay_policy.dart`、`native_replay_policy_io.dart` | 无该桥接 | Windows 调用 `rq_replay_policy_prepare`；输出成功或错误均在 `finally` 释放。原生错误直接报错，不静默改用 Dart。 |
| `lib/services/native_replay_policy_portable.dart` | 非 Windows/无原生后端平台需要兼容入口 | 仅供不支持 Windows Rust 后端的平台，沿用原时间解析器及相同修复后的分类；不是 Windows 原生错误兜底。 |
| `native/station_core/src/lib.rs`、`include/rq_station_core.h`、`CMakeLists.txt` | 无新模块、符号、构建依赖 | 注册模块、声明借用输入/释放输出 ABI、加入构建依赖，保证后续修改 Rust 文件会重新编译。 |

实际调用链：

`HistoryReplayControls._import` → 原文件导入器 → `importPackages` → `_play` → `playPrepared` → `NativeReplayPolicy` → Rust `needsHistory` → 原文件报文读取器 → `onReport`。

导出与旧格式转换都通过 `HistoryReplayPackage.reportTiming` → Rust `reportInstant`。Flutter 继续负责文件桥接、报文投递、计时器和 UI，没有迁移或重写地图及推算规则。

## 原始数据与时间回归

- 原始 CWA v1：4 报；原始 CEA v1：1 报；原始 GQ v2：18 报。所有完整报文及原始时间戳保持一致，输入文件 SHA-256 复核不变。
- 分别通过生产导出器导出 3 个 v3 ZIP，再导入，与原始解码结果逐报比较。
- 另使用修复前生产导出器实际生成的 `test/fixtures/history_replay/cea_202609290220_v3_pre_fix.rqreplay`，不是用修复后的代码制造缺陷索引。该文件原 manifest 的 `reportInstant` 为 null。
- CEA 原文件、新导出的 v3、修复前导出的旧 v3，导入后的单事件时间策略均为 `report`，起点均为 **2026-09-28T18:20:44.000Z**；不再后移到接收时间。原时间轴联动按有效接收时间选择联动基准的规则保持不变。
- 旧 v3 重新导出后，索引具有正确发布时间，原报文文件字节未改变。

## 验证结果

### Windows 真实 Rust 动态库路径

测试显式使用本次编译的：

`build/windows/x64/rq_station_core/cargo/x86_64-pc-windows-msvc/release/rq_station_core.dll`

SHA-256：`ac8a6d2b96ea6d7eee1b68fa5b7f8faa39eae557784cb9a2d785398fbf83bca8`。

专项导入矩阵记录 `nativePolicyUsed: true`、617 次原生调用、未释放输出数 **0**。另外验证 300 次错误命令后的输出数为 0，原始输入哈希均保持不变。

### 测试

- Flutter：13 个相关测试文件，**124 项通过，1 项跳过**。跳过项是 `history_lazy_loading_test.dart` 需要额外外部历史副本环境变量的可选大文件测试；没有删掉或弱化该断言。
- 专项：7 种输入分别开/关时间轴联动共 14 项；4 项真实控件导入/播放按钮测试；旧 v3 再导出和多包切换/联动各 1 项，共 20 项。选择文件使用测试选择器，文件 IO、格式转换、按钮处理器和播放准备使用生产代码。报文确实投递到回调，不只检查 `active` 或不报错。
- 原有约束：本地历史预加载、准备中销毁后不发报、读取中销毁后丢弃迟到报文、事件联动、停止后不再投递、推算 worker/trigger/KA/观测句柄释放均通过。
- 时间解析：810 组字段/时区/格式组合与原解析行为对照；原始报文、已有存盘时间及显式 `reportTime` 的优先级另行对照。测试值是时间协议单元输入，没有伪造地震观测。
- Rust：**168 项单元测试通过**。
- Dart：本轮 8 个相关文件静态分析无问题。

回归过程中，原有“准备中销毁”测试拦住了将所有文件读取器一律视为无需预加载的范围错误。最终原生判断明确接收 `storedSelection`，保留本地历史选择的预加载流程；该原断言未删除，最终已通过。

证据：`tmp/replay_import_fix_20261102/results.json`、`regressions.log`、`rust-all.log`、`rust-build.log`、`analyze.log`。修复前审查证据仍保存在 `tmp/replay_import_compatibility_audit_20261102/`，没有覆盖。

## 测试及文档文件变化

- `test/replay_import_compatibility_audit_test.dart`：原缺陷特征测试改为严格检查正确准备播放和原时间；增加修复前 v3、再导出、多包联动/切换覆盖，原报文完整比较保留。
- `test/october_scope_audit_test.dart`：A2 的“应复现旧错误”改为“应能准备播放且加载器调用 0 次”；原哈希、A3 资源断言保留。
- 新增 `test/native_replay_policy_test.dart`：原生时间/准备策略、原报文优先级和 FFI 错误释放检查。
- 新增修复前真实导出 ZIP 及其 README，原始 3 个 JSON 回放文件未改。
- 本文新增；原十月审查和兼容核查文档增加当前修复状态链接，历史结论保留。

## 交付边界

已完成源码修复、Rust release 动态库编译及上述本地运行测试。没有生成新安装包、安装到桌面 APP 或更新云电脑；没有占用用户桌面。三个原始 JSON 样本都是报文包，原有测站测试和真实推算帧回归通过，但不把它表述为某个外部完整巨型测站回放包的兼容验收。
