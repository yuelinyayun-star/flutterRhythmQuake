# JMA 长周期情报显示流程（2026-11-10）

## 本次授权与最终显示

- 普通 JMA／P2P 同事件情报仍有效：保留普通情报的标题、震源、震级、深度、普通最大震度和事件身份，临时切换为上游 VXSE62 长周期区域填色。长周期事件有效期间，15 秒后且播报结束时恢复普通震度填色。
- 普通情报已经过期／不在活动列表：沿用独立长周期情报入口，显示长周期区域填色。
- 两种情况均保留原来的长周期测站。
- 按用户最后一次调整：**长周期区域不显示区域数值图标**；测站原来的数字保留。普通 JMA／P2P 情报的区域数字不改。
- 区域由 VXSE62 的行政区代码匹配，颜色只使用各区 `maxLgInt`（1～4）对应的既有长周期颜色，不使用普通震度，也不预估其他区域。
- 填色采用 JMA 情报现有的 0.55 alpha 和 1px 边线。长周期的独立配色保持不变。

## 精确改动位置

| 文件／位置 | 原行为 | 本次行为／影响入口 |
| --- | --- | --- |
| `native/station_core/src/jma_lpgm_display.rs`（新增） | 没有原生长周期显示投影 | Rust 按既有同事件匹配规则关联普通 JMA／P2P 与 VXSE62；同事件隐藏独立显示项，保留原生事件；管理 15 秒、播报延后、重复／修订和状态回收 |
| `native/station_core/src/lib.rs` | 未注册该模块 | 注册长周期显示模块 |
| `native/station_core/src/unified_event_state.rs` 的 `Engine`、`next_deadline`、`execute`、`finish` | 只发布原始活动事件列表 | 额外发布显示投影和关联；生产 worker 使用原生截止时间唤醒；增加播报状态和定向清理长周期命令 |
| `native/station_core/src/unified_event_policy.rs` 的 `elapsed` | 长周期已解析的绝对时间再次经过 JST 墙钟转换 | 仅长周期使用 bulletin 的绝对时间戳计算年龄，避免误减 9 小时；既有 60 秒有效期不延长 |
| `lib/services/native_unified_event_owner_io.dart` 的 `describe` | 长周期描述符只有 ID／报次 | 增加原始 bulletin 的指纹、区域存在标记、绝对时间和匹配所需震源标量；原报文不重写 |
| `lib/providers/quake_provider_native_events.dart` 的原生 context／batch 绑定 | 直接使用全部 active 作为可见列表 | 绑定 Rust 显示列表和同事件关联，切换时更新地图 revision；原生内部事件与原有入库、OBS、音效动作继续保留 |
| `lib/providers/quake_provider.dart` 的长周期关联、清理、构造／销毁 | 关联保存在历史 companion 字典；清理只遍历可见列表 | 优先使用原生活动关联；清理能覆盖隐藏的长周期；保留历史关联数据；注册和移除播报状态订阅 |
| `lib/services/tts_service.dart` 的 `_processQueue` | 未对外公开队列播放状态 | 增加只读用途的状态 notifier，播放流程不变；显示计时仍由 Rust 决定 |
| `lib/screens/main_screen.dart` 的 `_activeJmaLpgmBulletin` | 同事件仍可能选中独立长周期侧栏 | 合并期间排除独立侧栏候选；独立显示沿用原入口 |
| `lib/widgets/map/quake_map_view.dart` 的长周期图层、合并 JMA 图层、填色几何 revision | 普通填色与长周期区域未按显示模式互斥接入 | 合并预览／独立情报接长周期区域层，恢复时回普通层；保留测站；长周期测站有效性使用源时钟；几何回调检查显示模式，避免旧回调回写 |
| `lib/widgets/map/information_event_fill_layer.dart` | 普通 JMA＋长周期关联只画普通震度和测站 | 提供显式长周期区域模式；独立长周期也画区域和测站；默认普通情报仍画普通震度和测站 |
| `lib/widgets/map/jma_lpgm_region_fill_layer.dart` | 0.42 alpha 的区域多边形，没有区域数值图标 | 改为上述 JMA 填色样式；缓存多边形和几何摘要，缩放／平移不重复构造多边形；最终仍不画区域数值图标 |

## 范围检查

- 普通 JMA／P2P 的区域数字、EEW 徽章、波圈、倒计时、其他信源填色没有在本次修改中重写。
- 长周期预览只关联 `jmaEqlist`／`p2pJmaEqlist` 的非 EEW 同事件，且回放 session 必须相同。
- 普通情报的原标题、最大震度、源标识和原始 payload 保留；显示合并没有删除原生原始事件。
- 重复完整报文不延长预览；仅完整修订重启。只有阶级的后续转发不能清掉已确认的完整匹配依据。
- 预览恢复后，其他后续语音不会重新触发预览。
- 取消清理仅移除长周期；普通情报和历史关联保留。此前回归测试发现误清历史关联的问题已恢复，并对失败项所在的关联测试文件重新验证。
- 相机继续接既有实际绘制几何入口；没有修改 Rust 相机算法、震中锚点或多情报视野保留规则。

## 实际验证

原数据：

- `test/fixtures/jma_lpgm_20261108/20261107161354_0_VXSE62_010000.xml`
- `test/fixtures/jma_lpgm_20261108/p2p_551_live_all_reports.original.json`
- 同事件 `20261108010441`；P2P 自有标识 `2026-11-08 01:04:00`，保留两种源标识，不改成一样来通过匹配。
- XML 为 3 个长周期阶级 1 区域、4 个测站。测试通过外部源时钟／原生测试时钟重现有效时段，不修改原报文的时间、震源或观测值。

结果：

1. Rust 长周期显示测试 **4 项通过**：JMA／P2P 限定、EEW／其他源／回放隔离、15 秒和播报恢复、恢复后不重启、普通过期后独立、重复／修订／清理、摘要转发保留完整匹配。
2. `jma_lpgm_display_flow_test.dart`、`jma_lpgm_main_map_flow_test.dart`、`information_fill_geometry_test.dart` **共 6 项通过**。覆盖原生 DLL 实际调用、所有权释放、原始报文两种分支、真实 `QuakeMapView` 切换／恢复／独立／清理、4 个测站、正确长周期颜色、无区域数值图标、几何缓存复用。
3. 已运行关联、多 API、统一入口、测站、EEW 长周期徽章回归 **21 项**：首轮 20 通过、1 项发现上述历史关联清理回归；修正后仅重跑该关联文件，**3 项全部通过**。已经通过且不受后续改动影响的测试未再次整组运行。
4. 最后一次多源匹配状态修改后，重建 DLL 并重跑两个原始报文原生流程测试，**2 项通过**。
5. 定向 analyze **0 error／0 warning**，仍有 58 条风格 info；未为整理风格扩大修改。
6. 离屏渲染并实际查看长周期填色／测站截图，未占用桌面。截图在 `tmp/jma_lpgm_display_20261110/`：`combined.png`、`restored.png`、`standalone.png` 和三张 `main-*.png`。

验证边界：测试没有运行历史数据库，provider 初始化日志有 sqflite 未配置提示；本次没有据此声称历史数据库运行验收完成。主地图与原生显示流程断言通过。已编译测试用 Windows 原生 DLL，**未编译 APP 安装包、未安装、未更新云电脑**。
