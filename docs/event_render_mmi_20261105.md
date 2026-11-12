# 成图窗口缺少 ShakeMap MMI（2026-11-05）

## 授权范围和缺口

用户截图的 USGS 事件主地图已显示 MMI 等值线，进入“渲染事件”后只有震中，并显示“预估烈度 VII”。

明确调用链证据：列表 `_EqCardState._renderEvent()` 只传普通情报快照；成图 `_buildFlutterMap()` 只有 `InformationEventFillLayer` / `CencIrLayer`，前者的支持列表本来就不包含 USGS。`RenderInformationLoader` 也没有 ShakeMap 读取入口。因此成图既没有产品数据，也没有专用绘制层；侧栏走普通非震度情报的预估烈度文案。这是成图入口漏接专用产品，不是主地图等值线绘制失效。

本轮仅补该成图入口。没有把 USGS 加进通用地区填色层，没有改变主地图、自动/手动选择、信息轮播、EEW、测站、DYFI 或其他类型的渲染规则。

## 具体修改

| 文件和位置 | 原行为 → 新行为 |
| --- | --- |
| `lib/widgets/ui/eqlist_panel.dart` `_renderEvent()` | 只传普通快照 → USGS 额外传入所点原始目录行及其详情链接，不改变地图选中项 |
| `lib/services/render_information_loader.dart` `shakeMap()` / `close()` | 无产品入口 → 独立持有一个现有 `UsgsShakeMapService`，只调用该私有实例的选择/加载，复用既有事件身份校验、首选版本及原始等值线解析；关闭窗口时释放请求客户端和私有服务，不订阅实时目录，不调用主地图服务 |
| `lib/widgets/ui/event_render_page.dart` `_loadSources()` / `_selectShakeMap()` | USGS 无产品 → 加载完成默认展示 MMI，提供“地震情报 / ShakeMap · MMI”产品切换，失败保留明确的重试入口 |
| 同上 `_buildFlutterMap()` | 缺少专用层 → 复用原 `UsgsShakeMapLayer` / `UsgsMmiContourPainter`，原始数值、颜色、线宽、顶点和世界副本处理保持原样；成图关闭主地图底部浮动图例以沿用右栏布局 |
| 同上 `_fitMapCamera()` | 只有普通填色几何 → 仅选中 MMI 时使用既有 `shakeMapFocusPoints()` 的等值线范围，仍用原 Rust 固定震中锚点拟合；普通情报和其他产品分支保持不变 |
| 同上 `RenderRightSidebarPanel` | 普通预估烈度 → MMI 产品显示产品标题、版次和上游最大 MMI，色条采用对应上游等值线颜色；不把 CSIS 罗马数字当作 MMI |

本轮是 Flutter 独立成图的读取入口/绘制接线。没有新增后端计算或复制新的产品解析器；已有信源和后端业务实现未改写。

## 用户实际事件的原始数据

- `nc75462637`，2026-11-05 04:56:02.670 UTC，Petrolia 以西海域，M4.96（界面按现有规则显示 M5.0）。
- 官方首选 ShakeMap 第 8 版，原始 `cont_mmi.json` 有 9 个 Feature。
- `maxmmi=2.816`、`maxmmi-grid=5.19`。复用主地图既有优先有效 `maxmmi` 的规则，所以右栏显示“最大 MMI 2.8”；没有修改原值，也没有用本地预估 VII 替代它。
- 两份原始 HTTP 响应与散列：`test/fixtures/event_render_mmi_20261105/`。散列复核通过。

## 验证和边界

- 既有成图、复制图片、手动填色、ShakeMap 读取/绘制/主地图服务回归加新测试首次共 41 项通过；补充实际 USGS 列表按钮入口后，新测试文件 4 项全部通过，合计覆盖 42 项不同测试。
- 原事件回放原始响应，核对身份、版次、最大 MMI、全部等值线的值/颜色/线宽/坐标；错误事件详情被拒绝；非 USGS 不发起 ShakeMap 请求；关闭客户端及重复关闭安全。
- 实际 `_EqCardState._renderEvent()` 点击进入后，确认所点 USGS 行被完整传递，先前地图选中项未变化，未新增主地图历史选择。该入口测试使用测试引擎默认的网络阻断，错误提示符合预期；成功加载和绘制由同文件使用原始响应的独立 HTTP 客户端验证，不能混称为安装版联网验收。
- 成图组件实际绘制 PNG，验证等值线出现、震中保留、右栏 MMI 2.8；16:9 / 4:3、分栏 / 全幅切换后所有原始等值线顶点入镜，震中在无遮挡地图中心，误差不超过 1px。产品切换复用已加载数据，不重复请求；事件输入不变；销毁后客户端关闭。
- JMA / CWA / CENC 的原始报文自动/手动填色回归、LPGM、既有底图切换及导出断言通过。测试框架对栅格外网的预期 HTTP 400 不是在线底图验收；测试数据库初始化提示不是新增生产问题。
- 定向静态检查无 error / warning，保留既有大括号样式 info。`git diff --check` 通过。
- 本轮源码与组件/原生调用回归完成；未重新编译 Windows 安装包、未安装、未更新云电脑，也未宣称安装版已经包含此修改。

日志：`tmp/event_render_mmi_20261105/regression.log`、`entrypoint-tests-final.log`、`analyze-final.log`。组件成图同目录下 `nc75462637-mmi-16x9.png`、`nc75462637-mmi-4x3.png`；测试引擎的默认 Painter 字体是 Ahem，不把这些字形当作生产字体验收。
