# JMA/P2PQ 情报填色与 NIED 小点联动

## 当前规则

地图实际绘制 JMA/P2PQ 普通情报的震度填色时，NIED 显示既有的彩色小点；填色消失后恢复。卡片切到 USGS 或检出视角接管，不会解除仍在绘制的 JMA 情报填色联动。其他来源的填色不会触发此联动，也不修改其他测站。

“震源调查中”和其他 JMA/P2PQ 普通情报使用同一条件。NIED 没有单独特例或计时器；原有情报 6500ms 临时展示及 EEW 打断仍由情报/地图显示链路负责，NIED 仅跟随其实际填色。

上一轮把“当前卡片/相机选中 JMA”当作条件，并将“切到 USGS 或检出视角后关闭”写成断言，是实现者理解错误，已删除该限制并修正测试。

## 精确修改范围

唯一生产修改文件：`lib/widgets/map/quake_map_view.dart`。

- `_isJmaP2pInformationForNiedDots`：仅识别 JMA/P2PQ 普通情报，排除 EEW、LPGM、火山特殊产品。
- `_hasPaintedJmaInformationForNiedDots`：复用填色层的绘制筛选，读取实际多边形发布并经 Rust 处理后缓存的区域范围，不依赖卡片/视角，不重复计算区域或解析报文。
- `_buildNiedStationLayer`：传递样式开关。
- `_onInformationFillGeometry`：只在 JMA/P2PQ 区域变化后通知 NIED 样式刷新。

`nied_intensity_layer.dart`、`intensity_fill_layer.dart` 哈希与本轮修改前一致。配色、透明度、缩放、原始测站值、检出、推算、网格及既有相机规则均未修改。

## 验证结果

原始报文经正式回放投递回调、Rust 原生事件所有者和实际地图组件验证桌面、手机两种尺寸：

- JIAN/WHEWS JMA，P2PQ ScalePrompt（无震中）、Destination、DetailScale：实际有震度填色时启用。
- CWA、CENC、USGS、单独 JMA EEW：不触发。
- 原始 P2PQ Foreign 报文在日本没有绘出震度区域：不触发，证明不只依赖报文存在。
- JMA 与 USGS 同时存在，卡片切至 USGS、检出视角接管：仍有 JMA 填色时保留小点。
- 事件清空后关闭；原始 `sourcePayload` 未改写。

上述测试与既有 6500ms 到期恢复、CENC 视角断言、网格/检出不变及样式恢复逐像素一致测试，合计 4 项通过。现有 EEW 测试保留原断言，仅等待填色层 post-frame 几何发布后检查样式。

证据：`tmp/nied_jma_fill_binding_20261103/tests.log`、`production-change.diff`、`renderers-before.json`。

本轮完成源码及本地测试，尚未重新编译安装。当前安装版仍为最初的 EEW 临时情报联动版本。
