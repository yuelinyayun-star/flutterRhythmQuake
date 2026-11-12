# JMA/P2PQ 情报展示期间的 NIED 小点样式

> 本文中的卡片/视角限制是实现者错误理解，已经纠正。当前规则及验证以 [JMA/P2PQ 情报填色联动说明](nied_jma_fill_binding_20261103.md) 为准；不再以卡片或相机选中的事件决定联动。

## 本轮授权与唯一生产修改

用户要求把已验收的小点联动扩展到 JMA/P2PQ 情报显示期间，禁止推广给其他来源。

仅修改 `lib/widgets/map/quake_map_view.dart` 的 `_buildNiedStationLayer`：

- 原行为：必须存在 EEW，且正在进行 JMA/P2PQ 情报的 6500ms 临时展示，才启用 NIED 小点模式。
- 新行为：没有 EEW 时，依据地图/卡片已有的当前展示事件启用小点模式；仅允许 `jmaEqlist`、`p2pJmaEqlist` 普通情报。切换到其他来源或检出视角后恢复原样。
- 有 EEW 时，仍只依据原有临时情报状态，保留 6500ms 展示、到期恢复和新 EEW 打断逻辑。
- 继续排除 EEW、LPGM 和火山特殊产品。后台存在 JMA 情报不构成启用条件。

当前选择复用 `historyInfoDisplayEvent` / `mobileCameraDisplayEvent`，不增加接收、轮播或相机策略。NIED 渲染器文件 SHA-256 与修改前一致；其他测站、数值、阈值、检出、推算、网格、透明度、配色和缩放均未修改。

## 已完成的验证

`test/nied_jma_information_display_test.dart` 使用未修改的原始报文，经正式回放投递回调、Rust 原生事件所有者和实际 `QuakeMapView` 验证：

- 桌面 1584×892 和手机 430×900 两种尺寸，JIAN JMA、WHEWS JMA、P2PQ ScalePrompt / Destination / DetailScale 均启用小点。
- 相同入口的 CWA、CENC、USGS、单独 JMA EEW 均不启用。
- JMA 和 USGS 同时存在时，显示 JMA 才启用；切换显示 USGS 后关闭，即使后台 JMA 仍存在。
- 检出视角接管及事件清空后关闭。
- 原始 `sourcePayload` 未改写。

与原有 `eew_information_focus_test.dart`、`nied_information_focus_style_test.dart` 合计 4 项测试通过，包含已有 6500ms 到期恢复、CENC 视角断言、网格/检出不变、样式切换后逐像素恢复。另补测原始 P2PQ 情报在第 3 秒被新 EEW 打断后恢复原样。

证据：`tmp/nied_jma_information_expansion_20261103/tests.log`、`eew-interrupt.log`、`production-change.diff`、`nied-layer-before.json`。新测试文件静态分析无问题。

本轮只完成源码及本地测试，未重新编译、打包、安装或更新云电脑；上一轮已安装版本仍是扩展前版本。
