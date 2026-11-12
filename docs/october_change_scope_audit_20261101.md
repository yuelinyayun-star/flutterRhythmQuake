# 10月以来修改范围与回归审查（2026-11-01）

> 2026-11-02 状态更新：A3 已按授权修复，详见 [A3 修复及验证](replay_disposal_fix_20261102.md)；B1 也已修复，详见 [连续经度范围修复及 JMA/P2PQ 回归](dateline_geometry_fix_20261102.md)；用户随后授权修复 A2，详见 [回放导入及时间索引修复](replay_import_fix_20261102.md)。A1、B2 未在本轮修改。下文保留 11 月 1 日审查时的原始结论和证据，不表示 A2/A3/B1 当前仍未修复；上述修改尚未打包或部署。

## 结论

本轮审查确认仍存在三项功能/生命周期问题：

1. **共用 NIED 调参改变了 P-Alert 的 Dart 计算入口，Windows Rust P-Alert 与该入口不再等价。** 未按信源隔离共用算法参数，是本轮新确认的串改问题。不能把这个结果解释为 Windows Rust P-Alert 位置计算本身已被改错。
2. **文件式回放导入后不能通过 APP 的准备播放入口。** 文件已经有读取器，却被当成本地历史摘要再次加载，因没有本地历史选择而报错。此前用户指定只记录、不修回放，本轮继续保持。
3. **运行中的回放控制器销毁时没有停止其推算 worker。** 原始测站帧创建一个实际 Rust worker 后，销毁控制器仍保留该 worker 和 session；显式停止推算后才归零。这是本轮新确认的释放遗漏。

另外确认一个现存的地图范围缺陷、一个失效的测试判断，以及四类已经修复的越界/优化回归，分别列在后文。没有把所有失败都归给 Rust，也没有把测试通过概括成全 APP 没问题。

**本轮未修改 APP 生产代码、云电脑、数据库、原始报文、设置或正在运行的安装版。只新增审查文档、两个审查复现测试和本地审查索引脚本。没有打包或安装。**

## 审查依据与范围

- Git 基线：10月1日以前最后一个提交 `27c60fcf6659524346b9520c936a1f3e5c575894`，到当前 HEAD 共23个10月提交；HEAD 为10月10日的 `ac247d8`。10月10日之后大量实现仍在未提交工作区，不能只查 Git，也不能把未提交代码归给 Git 作者。
- 扫描本机10月的27份会话文件，其中22份有相关项目记录；建立1138条用户消息引用，以及约3852条包含补丁/写入的操作索引。操作索引也含测试产物、备份和日志写入，不等同于3852次独立生产代码修改；失败补丁不作为生效修改。
- `tmp/october_audit_20261101/scope-inventory.json` 记录基线、提交及当前变更文件。清单含443个 `lib`、70个 `native`、301个测试/参考源文件，以及构建、工具和第三方文件。机械替换、参考文件和生成代码也在清单内，不能将清单数当成逐文件实机验收数。
- 重点核对共享入口：地图相机与产品图层、统一事件接纳/取消/轮播/语音、回放所有权、海啸左栏及验潮站、TREM样式、原生数据/传输迁移、背景缓存节流。逐项结合原要求、实际补丁、当前调用链及原始输入回归。
- 使用同一个新 Release Rust DLL 的真实 FFI；DLL SHA-256 和原始输入校验见 `runtime-evidence.json`。本轮P-Alert的16份原始归档全部符合原 manifest SHA-256，没有改测站值、时间、坐标或报文。

## 当前仍存在的问题

### A1：NIED 共用调参串入 P-Alert

**证据强度：当前串改入口及因果对照已确认；启用该参数的具体写入者尚未定位，不虚构作者或时间。**

- 位置：`lib/core/source_estimation/source_estimator.dart:1378`、`:1395`、`:12129`。`productionOffshoreTuning` 和 `productionJointRefinement` 默认开启；`jointReferenceNeighbors` 进入共用参考搜索时没有按 `request.sourceId` 排除 P-Alert。
- 调用链：`PAlertSourceEstimation._newEstimator` 使用 `NiedDartHypSourceEstimator(referenceBroadFourStage)`，并以 `sourceId: palert` 调用。测试用的 `PAlertSourceWorker.dartReferenceForTesting()` 和非原生平台使用这条 Dart 编排入口。
- Windows生产路径：`native/station_core/src/palert_inference.rs:905` 调用 `search_coordinates`，维持原来的轴向搜索，不读取上述 Dart 参数。NIED 的参数不能自动变成另一信源规则。
- 同一份原始记录、同一个 DLL，现有 `native_palert_inference_test.dart` 在默认参数下第9帧稳定失败：Rust 纬度 **24.3°**，当前 Dart 对照 **24.400000000000002°**。独立复跑仍失败，排除仅因并发测试的偶发差异。
- 只用编译开关 `RQ_HYP_JOINT_REFINEMENT=false` 关闭联合细化，不改原始数据、不改源码、不改 DLL：原有断言全部通过，17个不同源时间报文、6个有源结果帧一致。`RQ_HYP_OFFSHORE_TUNING=false` 也通过。
- 影响：P-Alert 的 Dart编排/非原生计算路径连带改变；测试所谓的“冻结Dart参考”仍引用当前共用实现，参考会跟着NIED调参变化。**不能据此宣称 Windows Rust P-Alert 的原算法错误，也不能把它当作两条生产路径保持一致。** 未做非原生安装版验收。
- 历史边界：10月18日原日志 `tmp/palert_complete_native_20261018/inference-test.log` 显示该原始归档曾17帧一致；10月24日11:13:23的工具读取记录已出现生产调参常量。当前本机会话记录没有找到这几个常量被启用的实际写入动作，因此精确写入时间、操作者及独立P-Alert授权不能凭文件mtime补造。
- 记录：`palert-inference-isolated.log`、`palert-RQ_HYP_JOINT_REFINEMENT.log`、`palert-RQ_HYP_OFFSHORE_TUNING.log`、`hyp-flag-history.json`。

本轮只审查，不切换任何默认参数、不修改算法。

### A2：导入回放被误当成本地保存历史

2026-11-02 后续修复状态：用户在兼容核查后授权修复，已修复导入准备误判及报文时间索引遗漏，并验证旧 v3 读取、本地历史加载及销毁约束。详见 [A2 修复及验证](replay_import_fix_20261102.md)。以下保留修复前的审查证据。

2026-11-02 新旧格式专项核查：已在 v1/v2 JSON 和当前导出的 v3 ZIP 上复现同一准备入口错误；另确认 CEA 样本的报文时间索引在转换时丢失，起点后移 33.061343 秒。详见 [导入入口与格式兼容核查](replay_import_compatibility_audit_20261102.md)。本轮只检查，没有修改生产代码。

**证据强度：原始文件通过生产导入/准备播放入口复现，当前仍存在。**

- 位置：`lib/services/debug/history_replay.dart:838`。`playPrepared()` 只要看到 `storedReports != null` 就要求 `_storedAnchor`，但文件式导入包已经有独立读取器，不需要本地历史摘要。
- 直接表现：`hasFileReports == true` 的包经 `importPackages()` 后调用 `playPrepared()`，抛出 `Missing saved replay selection`，播放没有开始；并未调用本地loader。
- 对比：同文件的 `play()` 已区分 `storedReports != null && !hasFileReports`，准备入口没有做同样区分。
- 引入链：10月13日14:34:04，懒加载修改 `call_vDQWecW4FFsge24PluVYb5LF` 将 `storedReports != null` 加进统一加载条件；10月23日20:06:16，目录回放改动 `call_fae30a144ab6498eb73cac870470107d` 新增文件式包。新包沿用旧限制，独立导入入口适配没有补齐。后者用户要求的是减少回放内存、逐帧逐报存盘，不是取消导入播放。
- 复现：原始 `test/fixtures/history_replay/cwa_1150074.rqreplay` → `importReplayFile` → `HistoryReplayController.importPackages` → `playPrepared`。未改原始文件，哈希检查不变。
- 本轮测试：`test/october_scope_audit_test.dart` 第一项；记录 `defect-reproduction.log`。

这是已记录的迁移适配遗漏，不能用“用户要求懒加载”解释为预期行为。按此前“只记录，不改回放”继续保留原代码。

### A3：回放销毁遗漏推算 worker 释放

**证据强度：原始测站帧创建真实 Rust worker，销毁后保留计数已确认。**

补充专项完整审查：见 [回放销毁与推算资源专项审查](replay_disposal_audit_20261101.md)。22项组合验证进一步确认NIED还保留1个trigger句柄、1个KA句柄和1573个原生观测历史句柄；销毁时排队的原始帧仍继续处理，甚至在销毁后创建worker。正常手动停止、自然结束及新旧session隔离均正常；另有一个最多80ms的UI发布Timer未取消，属于有界遗漏。不能把正常关闭面板或整进程退出混同于该销毁缺陷。

- 位置：`lib/services/debug/history_replay.dart:1181` 的 `dispose()`；正常 `stop()` 在`:1120` 会停止匹配session的 `ReplaySourceEstimation`，但`dispose()`没有这一步。`QuakeProvider.dispose()`直接调用回放控制器的`dispose()`，没有先stop。
- 引入记录：10月14日17:07:03，`call_9621be51eda44fd985a221150f7063b9` 在播放时启动独立推算、在停止时释放，未补销毁路径。该次用户要求回放能触发推算，不授权销毁后继续持有worker。属于新功能接入时的生命周期遗漏。
- 复现：原始回放启动独立session，使用原始P-Alert测站归档的一帧创建worker；worker计数 **0 → 1**；控制器`dispose()`并等待150ms后仍为 **1**，session仍保留；显式 `ReplaySourceEstimation.stop()` 后回到 **0**。
- 两个不同事件的原始文件仅用来验证资源所有权，未宣称它们是同一事件的推算输入或位置精度证据。
- 影响边界：回放运行期间销毁控制器/其Provider时，已开始的后台推算、读取器及会话不会沿正常stop路径释放；已复现至少一个原生worker保留。**这不证明旧版本2GB内存或30% CPU都由此造成**，也不等于整进程退出后线程仍存活。
- 记录：`test/october_scope_audit_test.dart` 第二项、`defect-reproduction.log`。测试finally显式清理，结束worker归零。

本轮只记录，未修改回放生命周期。

## 现存问题，但不能归为本轮/10月越界修改

### B1：跨日期变更线的范围被删点

2026-11-02 修复前复核：桌面/手机真实入口各漏 1 个原始范围点；另确认可见性接口在该点已经可见时仍返回 false，详见 [B1 复核及影响边界](dateline_scope_audit_20261102.md)。随后按用户授权修复，两个尺寸3/3点均入镜、震中仍居中，原保护与JMA/P2PQ独立规则保留，详见 [修复及验证](dateline_geometry_fix_20261102.md)。

- 原始事件 `aka2026tvzrwv` 空ShakeMap轮廓的东边界为 **181.883°**。`MapStateProvider._fitPointsAroundAnchor` 先按±180检查、后做世界副本转换，丢弃有效连续经度。
- 桌面1584×850、手机430×900真实生产地图入口均复现：3个范围点中1个越出可用视野，震中仍居中；保留完整范围断言，未改原经度、未补假轮廓。
- 迁移前 Git `ac247d8` 有同样的过滤次序；此前审查已有证据。**属于当前既有范围缺陷，不能归因于Rust迁移或本次DYFI修复。**
- 日志 `empty-1584.log` / `empty-430.log`；原证据 `docs/filled_information_camera_validation_20261030.md`。未修复。

### B2：推算轮播的测试失去有效判断

- `test/map_card_viewport_sync_test.dart:136` 仍用旧坐标文字判断6个P-Alert卡片是否轮播；10月20日23:49:20 `call_1336d4a2f3cf48fe805612cf29818cdc` 将 `sourceEstimationLocation` 接入已有地名解析后，这段测试没有跟着保持可识别的断言。
- 现有测试失败为6个坐标字符串均找不到；新增独立观察同一个原有UI边界场景，按固定事件卡片key检查，12次每秒更新期间 **6/6卡片实际轮到，旧坐标文字0/6**。
- 因此不能把该失败报告成当前轮播坏了；它是测试断言未跟上已变更显示字段。原测试没有被删除或改绿。
- 新增 `test/october_source_pages_audit_test.dart`；日志 `source-pages-probe.log`。该受控场景只验证UI分页，不是虚构上游报文或地震计算精度。

## 已修复的越界/优化回归，不能当作当前仍坏

| 日期（北京时间） | 实际越界/破坏 | 原授权边界与影响入口 | 当前证据及状态 |
| --- | --- | --- | --- |
| 10月15日14:01、14:03 | DYFI先从普通震中层排除，随后独立震中也被删，手动分支提前返回空组件 | 用户要求修强占视野、轮播和新情报聚焦；没有要求删除主地图震中。自动和手动两入口同时漏画 | 已恢复；两尺寸自动/手动实际图层验证通过。详见 `dyfi_regression_20261101.md` |
| 10月24日18:36、18:38 | CENC按填色缩放时删除5处震中锚点；随后把原居中测试改成包围框居中，失去原约束 | “按填色算范围”只授权缩放，不授权取消中心。涉及桌面、手机、EEW临时情报、历史和共享视野 | 10月30日已恢复锚点和旧断言；见 `map_camera_centering_audit_20261030.md`。初次测试修改尝试失败，实际后续成功动作是18:38:13，不能把失败补丁当成生效动作 |
| 10月24日19:30 | TREM数字阈值调整时同时替换小点配色，并把透明度改成不透明、去掉边缘 | 用户报“0图标刻度错了”，不包含改配色/透明度。影响低震度点样式 | 同日19:34恢复透明度，21:21恢复原KA配色与样式；当前原始RTS和点像素检查通过。`trem-changes.txt`保留具体补丁 |
| 10月26日17:24 | 背景缓存优化把普通变化限制为1秒；手动移动仅排除节流，仍等待异步截图，自动动画未进入急速刷新 | 用户要求降CPU并保持效果，没有授权降低跟随刷新。影响毛玻璃背景与地图同步，产生拖影 | 同日22:12开始切回同scene更新，当前同步/像素检查通过；`backdrop-all-changes.txt`保留加入和删除节流记录。不能把组件像素通过当成云电脑整体CPU已达标 |

已修的DYFI网格KMZ接入遗漏不是“原KMZ支持被删除”，其最初接入只有GeoJSON；详见前一份审查，不能与震中删除混为一次回归。

## 本轮实际验证结果

| 检查批次 | 当前结果 | 说明 |
| --- | --- | --- |
| Rust库全部单元测试 | 155通过 | `rust-all.log` |
| 15份事件/取消/回放控制/UI/语音/海啸/测站测试 | 194通过、1跳过 | `regressions.log`；原生统一事件实际worker路径也在内 |
| 10份数据/原始观测/归档/原生事件/CENC/USGS测试 | 107通过 | `data-regressions.log`；与上一批有重叠，不累加成独立总数 |
| 连接鉴权/主备/摘要/背景与点像素/地图卡片检查 | 107通过；1个真实测试失败；另1个测试文件名错误 | 真实失败为B2旧坐标断言；错写的不存在文件不作为APP缺陷或已测项目。正确KMA/TREM入口在数据测试的`native_station_runtime_test`及Rust测试覆盖 |
| 33份补充原生FFI/所有权/冻结对照测试 | 140通过、2跳过、2失败 | `native-regressions.log`；失败为A1和下行JMA并发超时 |
| 原生JMA图片单独复跑 | 5通过 | 原批次一项30秒超时，隔离后通过；未证明生产JMA图片失效，不列为已确认APP缺陷。`jma-images-isolated.log` |
| P-Alert默认参数隔离复跑 | 失败，稳定第9帧纬度不等 | `palert-inference-isolated.log`；A1 |
| 关闭联合细化、关闭离岸总开关分别对照 | 两次均17帧一致通过 | 未改源码或原始数据；不是修复后的生产验收 |
| 新增缺陷特征复现 | 2通过 | 通过表示成功复现A2/A3，并非缺陷已修复。`defect-reproduction.log` |
| 新增轮播真实卡片观察 | 1通过 | 6个卡片key全部出现；B2 |
| 空ShakeMap跨线实际入口 | 桌面、手机均失败 | B1，不删断言 |

未进行在线上游报警注入、云端操作或占用桌面；实际地图入口为本地离屏Flutter引擎。测试HTTP瓦片400及未初始化本地数据库的隔离日志不作生产网络/数据库故障证据。没有将海量生成文件清单、跳过用例、单元测试或历史旧日志当成全平台安装版实机验收。

## 本轮新增文件

- 本文：问题、范围、归因和验证清单。
- `test/october_scope_audit_test.dart`：以原始回放及原始测站数据记录A2/A3，结束显式清理worker。
- `test/october_source_pages_audit_test.dart`：复用原分页边界场景，观察稳定卡片身份，辨别B2测试失效。
- `tmp/october_audit_20261101/`：读取历史记录的索引/检索脚本、操作引用、原始文件校验、日志和离屏结果。脚本不改原会话、生产文件或原始数据。

以上审查明确了已确认的具体问题和证据边界；测试通过的路径不代表未覆盖的所有窗口、信源报文、网络环境或长期性能都已无回归。
