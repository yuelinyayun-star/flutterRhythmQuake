# JMA EEW PLUM 适配与标签修复（2026-11-06）

## 本轮确认的行为

用户明确要求适配 PLUM，不删除其 EEW 行为：波圈、闪烁、倒计时、视角和既有发报状态保持原样。标题追加 `（PLUM）`，不使用点号分隔。地图的假定震源标签显示 `PLUM所得假定震源`；统一 UI 在 PLUM 的震级或深度缺失时显示相同文字。长周期接入留待用户说明，本轮不实施。

技术核查中关于假定震源物理意义的说明，不构成删掉本项目波圈或倒计时的授权。

## 具体修改

| 文件／位置 | 原行为 → 新行为 |
| --- | --- |
| `native/station_core/src/jma_eew.rs`；`src/lib.rs` 模块注册 | 新增无分配的 Rust 标志归一化函数 `rq_jma_eew_is_plum`，仅识别 JMA EEW 的原始 PLUM／已有假定震源标志，不包含接纳、计时、传播、阈值或长周期策略。 |
| `lib/services/native_jma_eew{,_io,_portable}.dart` | 新增标量 FFI 编码桥；支持原生库的平台直接调用 Rust，库或符号错误不静默退回 Dart。不支持原生库的平台有明确兼容实现。 |
| `lib/services/quake_event_adapter.dart`：JIAN、通用 JMA EEW（含取消分支） | WHEWS 的 `isPLUM` 原来未接入；现在与已有 `isAssumption` 经 Rust 合并为统一方法标志。JIAN 已有映射切到同一 Rust 处理。原始数据、EEW 分类、震度、震级、深度、坐标、取消／最终／警报及时间字段保持原值和原规则。 |
| `lib/services/sources/fan_service.dart`：JMA 统一输出 | 原来固定输出 `isAssumption:false`；现在仅对 JMA 转送原始 `isAssumption`、`isPLUM`，交给上述 Rust 归一化。其他 FAN 类型维持原行为。不改写 sourcePayload。 |
| `lib/models/unified_quake_data.dart`：显示 getter、fromMap | 新增严格限于 `source=jmaEew && isEew && isAssumption` 的显示资格。标题派生 `（PLUM）`，不改原 titleText；缺失震级或深度时派生指定文字，不填造数值。读取带原始载荷的旧记录时恢复先前漏掉的 PLUM 标志，持久化新摘要后可无载荷保留标志。已有只含轻量摘要、且漏标志又无原始载荷的旧条目不会被猜成 PLUM。 |
| `lib/models/unified_event_presentation.dart`：统一显示 | PLUM 缺失参数时不再落入“規模 調査中”，改为指定文字；统一标题使用括号 PLUM 标记。非 PLUM 与其他类型沿用原规则。 |
| `lib/widgets/ui/unified_alert_card.dart` | 备用统一卡片同样显示上述标题、缺失参数文字。 |
| `lib/widgets/ui/history_panel.dart`：摘要、报次展开 | 历史标题同样加括号 PLUM；缺失参数行和展开报次使用指定文字。摘要行数、尺寸、顺序、播放和导出按钮不变。 |
| `lib/widgets/map/wave_layer.dart`：`_drawEpicenterLabel` | 仅 JMA EEW 假定震源标签由“假定震源”改为指定文字。取消标签仍优先。传播公式、波圈、透明度、颜色、十字、刷新和闪烁实现不变。 |
| `lib/widgets/map/history_marker_layer.dart` | 手动选择 JMA PLUM EEW 时传入假定标志并显示指定标签，其他历史及情报产品不变。 |

主界面 `AlertModule` 复用现有 `UnifiedEventPresentation`，无需改该组件。原始报文存储仍完整保留 `isPLUM` 等字段，不回填 M1.0 或修改原始载荷。

## 验证

- Rust 专项 1 项通过，release DLL 已编译；Flutter 在实际 Rust DLL 路径下运行，专项断言原生支持已启用。
- PLUM 专项 9 项通过：用户原始 5 报逐一适配、旧保存记录再读取、原始载荷不变、缺失参数显示、普通原始事件／JIAN 文档样例、实际统一 UI／备用卡片／历史／地图组件。
- 原始 5 报的夹具与先前导出 ZIP 中 Data 文件逐字节一致，没有改时间、震级、坐标或原始 PLUM 值。界面组合测试明确只改变显示时钟，不修改事件时间。
- 每一报仍为 EEW；普通本地计算与修复前完全相同：位置 29.36/120.17、经过时间 0 秒，距离 2074.3895292703405km、S 波 465 秒、本地烈度 null。保留原计算输出是用户本轮明确要求。
- 真实 `UnifiedEventWaveLayers` 仍给出 `showWaves=true`，`blinkOn=false` 输入原样传递；手动历史标记也保留 PLUM 标签资格。
- 合并回归 167 项通过、1 项失败，覆盖 JIAN、JMA 取消、原生事件接纳和释放、倒计时、EEW 视角、统一卡片、历史布局、EEW/情报不同图层键。失败为 `unified_event_presentation_test.dart` 的普通 WHEWS 情报 0 值断言：期望 `0`，实际 `I`；使用本任务开始前保存的 presentation 源码及原断言再次执行，同样失败。对照原件和日志在 `tmp/jma_plum_fix_20261106/baseline-comparison.log`，本轮未扩大范围修改它。
- 静态检查无 error／warning，有 20 项既有 info，均位于本次未修改的原有语句。
- 逐任务前后差异保存在 `tmp/jma_plum_fix_20261106/task-only.diff`。确认 `unified_event_wave_layers.dart`、`local_eew_sidebar_panel.dart`、`quake_map_view.dart` 与任务开始前文本完全一致；`wave_layer.dart` 的传播和十字绘制部分也完全一致，仅标签分支变化。
- 组件渲染图在 `tmp/jma_plum_fix_20261106/unified-history-map.png`。已核查括号标题、统一卡片及历史参数文字、十字与波圈保留；测试引擎无显式字体的 Canvas 标签存在 Ahem 替代字形，此图不作为安装版系统字体渲染的证明。没有为测试图改动生产字体样式。

## 交付边界

本轮源码、Rust DLL 及 Windows Release 编译完成，Windows 构建用时 75.8 秒。核对 Release 目录 DLL 与测试所用 DLL 的 SHA-256 相同，并从实际 Release DLL 调用 PLUM 导出符号成功，证据在 `tmp/jma_plum_fix_20261106/release-verification.json`。

未重新打包安装包、安装、启动或更新云电脑；组件测试不等同于已安装版本运行验收。长周期预测字段、警报地域名单、震度范围和到时语义等其他核查项未在此轮接入。
